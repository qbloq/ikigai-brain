# Marketico Port — la UX de llamadas de setters y closers

**Fecha**: 2026-08-26 · **Estado**: diseño aprobado en conversación (secciones 1-5) ·
**Loop**: «Marketico Port» — portar el proceso de agendamiento/llamadas de la
App de Marketico al Cerebro (Agentico).

## 0. Contexto y decisión

El equipo comercial cambió el proceso el fin de semana del 22-24 de agosto, y
el Cerebro se enteró por el drift de la reconciliación de agenda
(`bash/intercepciones/`): el calendario oficial «Calendario Premium Mastermind»
pasó de citas de 60 min repartidas round-robin entre closers a **citas de 20
min con dos *call confirmers*** (Cristian Buelvas y Anthony Velásquez, sus
únicos miembros). En esa llamada el confirmador **califica**, decide el
**producto** (Premium Mastermind o Premium Academy, «según el capital») y
**agenda la llamada de venta de 60 min con un closer** en «Aplicación a
Premium Mastermind» (miembros: Lucho, Carlos, Ayrton, Diego). Mateo, que no es
miembro de ninguno, recibe sus llamadas en su calendario personal — y esas
**no entran al sistema** (el webhook de Marketico las descarta por venir sin
`appointment_id`). Confirmado por dirección y por Lucho en ONLY CLOSERS
(2026-08-26): *«La llamada se le agenda al call confirmer, en periodos de 20
min, y ahí ellos agendan a closer»*.

Decisiones de Santiago (2026-08-26):

- **Se da de baja el proceso de la App de Marketico.** De Marketico solo se
  toma el **link de Google Meet** y los **assets de la llamada** (resultado,
  transcript, reporte estructurado).
- Ni setters ni closers tocan el CRM: **el Cerebro asigna el closer** al cerrar
  la confirmación, por prioridad de closers.
- **Doble superficie** para toda acción operativa: UI publicada **y** Iki por
  WhatsApp; se instrumenta la superficie para medir la tesis de Parallelo (la
  UI entra en desuso frente al chat).
- Acceso: el Cerebro puede todo; los copilotos tienen boundaries; **lectura y
  escritura son permisos distintos**. Escritura de agendas GHL = `ejecutivo`,
  `director-comercial`, `setter`; `technology` super rol.
- **Prioridad de closers en tabla local por ahora**; después la produce el
  análisis de closers (efectividad/BANT contra plata).
- Alcance de hoy: **toda la UX de llamadas de setters y closers**.

### Forma del puerto: A — estrangulamiento

Marketico se queda como **identidad de Google + fábrica de assets**: cuando una
cita entra al calendario de venta, su webhook (`processBooking`) crea el
espacio de Meet con grabación automática, el evento de Calendar, la
suscripción de grabación y la fila `meetings` — de ahí salen transcript y
reporte. El Cerebro toma **todo lo humano**: la creación de las citas de venta
(la asignación escribe en GHL → Marketico reacciona como hoy), la UX de setters
y closers, los desenlaces y la prioridad. La App de closers se apaga; el
backend no. Riesgo bajo, sin cambios de código en Marketico hoy; la
reconciliación horaria mide la paridad.

Descartados: **B** corte directo (el Cerebro recibe el webhook y pide el Meet
por API — exige que Marketico exponga «crear espacio con grabación +
suscripción»; es el loop siguiente) y **C** identidad propia de Google.

## 1. Calendarios y datos

### 1.1 Dos calendarios oficiales con rol

| rol | calendario GHL | id | duración | miembros |
|---|---|---|---|---|
| `entrada` | Calendario Premium Mastermind | `bFFbTpMillO1n35FuDmv` | 20 min | Cristian, Anthony (confirmadores) |
| `venta` | Aplicación a Premium Mastermind | `rmiAFkJKOZ2QZ1yEr8dn` | 60 min | Lucho, Carlos, Ayrton, Diego (+ **Mateo**, pendiente) |

Migración `catalog/migrations/008_calendarios_rol.sql` (idempotente):

- `crm_calendars.rol text CHECK (rol IN ('entrada','venta'))`, NULL para los
  históricos. Insert de la fila de «Aplicación» (David Guerrero, `is_active`,
  `rol='venta'`) y update de la fila existente a `rol='entrada'`.
  **Marketico no lee `crm_calendars`** (verificado: `google_calendar_id` sale de
  `project_crm_configs`); la leen el reconciliador y la agenda del setter, que
  se adaptan.
- `meetings.ghl_calendar_id text` (nullable). Lo llena el Cerebro desde GHL por
  `appointment_id` (el reconciliador ya lee ambos calendarios cada hora; la
  agenda del setter lo sabe al instante). El **tipo de llamada** se deriva:
  `rol_llamada = crm_calendars.rol` vía `ghl_calendar_id` — `confirmacion` /
  `venta` / NULL (histórico = venta).
- Todo lo que hoy asume UN calendario pasa a filtrar por rol: la agenda de
  closers (`bash/closers/agenda.sh` + escenarios WhatsApp) = `venta`; la
  reconciliación = ambos, cada uno contra su calendario; los dominios de
  llamadas (`calls`, reportes, BANT) = `venta` (una confirmación no es una
  llamada de venta y no debe entrar a `call_stats`).

### 1.2 Las confirmaciones no deben disparar a Marketico

Hoy cada reserva de entrada nace con Meet, evento de Calendar y fila
`meetings` de 20 min a nombre del confirmador — el lead recibe un link que no
va a usar y el sistema cuenta una llamada que no es. Pedido a quien administre
GHL (Lucho/Pablo): **filtrar el workflow por calendario** para que solo
«Aplicación» dispare el webhook `/crm`. Mientras tanto el Cerebro tipa esas
filas como `confirmacion` (1.1) y las excluye de llamadas y agendas de closer.

### 1.3 Base local `asignacion` (`data/sqlite/asignacion.db`)

Estado propio del proceso mientras se prueba; lo que sea dato de la org se
gradúa a Postgres después (patrón `testeos`). Vive en el servidor del
publicador (la UI publicada corre allí) — declarado, como `publicaciones.db`.

- `prioridad(closer_ghl_user_id PK, nombre, orden INT, activo INT, tope_diario INT, actualizado_at, actualizado_por)` — editable **desde la conversación con el Cerebro** (script WRITE local), no desde el navegador. Semilla: la que fije Lucho.
- `asignaciones(id PK, appointment_entrada, contact_id, lead_nombre, producto, banda, closer_ghl_user_id, appointment_venta, inicio_venta, regla, superficie ('ui'|'wa'), ejecutado_por, ejecutado_at, resultado, error)` — la bitácora: **cada** ejecución, también las fallidas.
- `confirmaciones(appointment_entrada PK, contact_id, desenlace ('calificado'|'no_califica'|'no_contesto'|'pendiente'), producto, motivo, reintento_at, superficie, registrado_por, registrado_at)` — el desenlace del confirmador, el dato que hoy nadie registra.
- `solicitudes(id PK, tipo ('reagendar'|'no_asistio'), appointment_venta, closer_ghl_user_id, nota, estado ('abierta'|'ejecutada'|'descartada'), superficie, creado_por, creado_at, resuelto_por, resuelto_at)` — lo que pide el closer y ejecuta el confirmador.

### 1.4 Regla de asignación (v1, explícita y versionada)

`regla = 'v1'` en cada fila de `asignaciones`:

1. Candidatos = closers `activo=1` en `prioridad`, miembros del calendario
   `venta`, con `citas_del_dia < tope_diario` para el día propuesto.
2. Banda **A** → el candidato de menor `orden`. Bandas **B** y **C** → el
   candidato con menos citas de venta en la semana (reparto equitativo);
   empate → menor `orden`.
3. Slots = `free-slots` de GHL para ese closer en el calendario `venta`
   (verificado en vivo 2026-08-26: `GET /calendars/{id}/free-slots?userId=…`,
   Version 2021-04-15, responde por día). Sin slots en los próximos 7 días →
   siguiente candidato.
4. El confirmador puede **pasar al siguiente** candidato si el lead no puede en
   esos horarios; la fila registra `regla='v1+manual'`.

La banda A/B/C es la de `docs/lead-score.md` §5 (ya calculada por
`bash/setters/agenda.sh`). El producto lo decide el confirmador (v1); una regla
por capital declarado puede proponerlo después.

## 2. UX del setter (confirmador) — `agenda-setter` v2

Misma página, mismos destinatarios (Cristian, Anthony, Lucho), mismo spec de
rol (`viz/specs/roles/setter/agenda-setter.json`), extendida:

- **Mis confirmaciones** (calendario `entrada`, en vivo): las citas de 20 min a
  nombre del confirmador, día/semana. Por fila, lo que ya trae (lead en vivo,
  banda, respuestas textuales de la encuesta, etapa del tablero, closer
  asignado) **más** el desenlace (`pendiente` · `calificado → asignada a X el
  D H` · `no_califica` · `no_contesto (reintento D H)`), leído de
  `confirmaciones` + `asignaciones`.
- **Agenda de closers** (calendario `venta`, en vivo): citas de 60 min por
  closer, carga del día y de la semana, quién tiene hueco, quién está cerca
  del tope. Se lee mientras el lead está en línea.
- **Acción «Asignar»** (fila de una confirmación pendiente), tres pasos:
  1. producto (Mastermind | Academy) — la banda se ve, el número no;
  2. el Cerebro propone **el closer que toca** (regla 1.4) y sus slots libres
     reales; botón «siguiente closer»;
  3. confirmar → `asignar` crea la cita en `venta` a nombre del closer con el
     lead (Marketico crea el Meet); la fila pasa a `asignada`.
- **«No contestó»** (con reintento: +2 h / mañana misma hora / elegir) y
  **«No califica»** (motivo corto): un clic cada uno → `confirmaciones`.
- **Cola de solicitudes** de closers (reagendas / no asistió), con los slots
  del propio closer para ejecutar la reagenda.

Reglas: el confirmador nunca ve score ni ranking (ve «el closer que toca» y
sus horas). GHL caído → se muestra la última lectura con su hora y las
acciones se apagan con aviso; jamás se inventan slots.

## 3. UX del closer — `agenda-closer` (nueva) 

Página publicada **por closer** con identidad fija (`closer=$user_id`, ve solo
lo suyo); el Director Comercial la ve con `{}` (todos). Spec de rol
`viz/specs/roles/closer/agenda-closer.json`.

- **Mi agenda** (calendario `venta`, en vivo): sus llamadas del día y la
  semana con lead, **link de Meet** (de `meetings`; si no existe aún: «sin
  Meet aún»), respuestas textuales de la encuesta (nunca banda ni score),
  quién confirmó y cuándo, y el estado por capas de las pasadas (ocurrió ·
  analizada · venta · anunciada — la misma derivación de la agenda del
  setter).
- Enlaces a sus páginas actuales (`llamadas-closer`, `reporte-llamada`) por
  fila; no se rehacen.
- **Acciones**: «Pedir reagenda» (nota opcional → `solicitudes`, aparece en la
  cola del confirmador) y «No asistió» (→ `solicitudes`, tipo `no_asistio`).
  Ninguna toca el CRM.

Los mensajes de WhatsApp de closers (07:00 agenda, recordatorio 45 min, cierre
20:00) no cambian de forma; pasan a leer el calendario `venta`.

## 4. El motor y las dos superficies

### 4.1 Escritura en GHL — lado WRITE de `bash/ghl/`

Nuevos, todos `[WRITE→GHL]`, cercados por la llave `escrituras` (4.4), con
`--dry-run`, antes/después (GET previo y posterior), `--json`, idempotencia y
token por stdin como hoy:

| Script | Hace |
|---|---|
| `appointment_create.sh --project N --calendar ID --contact ID --user GHL_USER --inicio 'YYYY-MM-DD HH:MM' [--fin …] [--titulo T]` | `POST /calendars/events/appointments` con `assignedUserId`, `appointmentStatus=confirmed`. Idempotencia: si ya existe una cita viva del mismo contacto en ese calendario a esa hora, la devuelve en vez de crear. |
| `appointment_move.sh <appointment-id> --inicio … [--fin …]` | `PUT` de horas (ya usado con éxito el 2026-08-18). |
| `appointment_cancel.sh <appointment-id> [--motivo T]` | `appointmentStatus=cancelled` — estado, nunca DELETE. |
| `free_slots.sh --calendar ID --user GHL_USER [--desde D] [--dias N]` (read) | `GET /calendars/{id}/free-slots`, Bogotá, por día. |

Horas: GHL recibe ISO con offset `-05:00`; el reloj Bogotá entra literal.

### 4.2 Comandos de negocio — `bash/agenda/` (nuevo dominio)

Cada uno existe **una vez** y recibe `--superficie ui|wa --por <quien>`:

| Comando | Hace |
|---|---|
| `proponer.sh --confirmacion <appt> --producto P` (read) | Aplica la regla 1.4: devuelve `{closer, slots[], siguientes[]}` y la banda. |
| `asignar.sh --confirmacion <appt> --producto P --closer GHL_USER --inicio H` **[WRITE]** | `appointment_create.sh` en `venta` + `confirmaciones(calificado)` + `asignaciones`. Una fila de bitácora aunque falle. |
| `no_contesto.sh --confirmacion <appt> [--reintento H]` / `no_califica.sh --confirmacion <appt> --motivo T` **[WRITE local]** | Desenlaces. |
| `solicitar.sh --cita <appt-venta> --tipo reagendar\|no_asistio [--nota T]` **[WRITE local]** | Del closer. |
| `reagendar.sh --solicitud <id> --inicio H` **[WRITE]** | `appointment_move.sh` + cierra la solicitud. |
| `prioridad.sh [--set CLOSER --orden N --activo 0\|1 --tope N]` **[WRITE local]** | La tabla, desde la conversación con el Cerebro. |

### 4.3 Superficie UI — primer camino de escritura del publicador

`viz/publish.js` gana **una** ruta `POST /act/<slug>/<act>` que: verifica la
sesión (JWT) y que el visitante tenga permiso sobre el slug; resuelve el rol y
aplica la cerca de `escrituras`; exige cabecera `Origin` propia (CSRF, como
`/login`); ejecuta solo los scripts declarados en `manifest.writes` del
componente por el `makeRunner` de `viz/lib/actions.js` (el carril del viz, sin
SQL ni shell libre); inyecta `--superficie ui --por <user_id>`. Respuesta = el
JSON del script; la página re-renderiza por SSE.

### 4.4 Cerca por rol — lectura ≠ escritura

`docs/roles/acceso.json` gana la llave `escrituras` (lista de dominios de
escritura); `bash/lib/acceso.sh` la evalúa aparte de `dominios`
(`require_escritura <dominio>`). Primer dominio: `ghl-agenda` →
`setter`, `director-comercial`, `ejecutivo`; `technology` = `*`. Rol `setter`
nace en el mapa con `dominios: ["ghl"]`, `escrituras: ["ghl-agenda"]`,
`uis: ["setter"]`. Es decisión de gobernanza; se registra también en el spec de
control de acceso del 2026-08-20.

### 4.5 Superficie Iki

Iki no tiene shell. Hoy llega a los datos por `API_SOURCES` (`viz/server.js`,
lista blanca de fuentes). Esa puerta gana su gemela de **acciones**: una lista
blanca `API_ACTIONS` con exactamente los comandos de 4.2, y el remitente se
resuelve por número E.164 contra el directorio (`bash/agentes/sync_directorio.sh`)
→ rol → cerca 4.4. Iki conduce: «califica, Mastermind» → `proponer` → «Carlos:
jueves 3 pm, 4 pm; viernes 10 am» → «jueves 3» → `asignar` → «Listo: Carlos,
jueves 3 pm, Meet en camino». Cada ejecución queda en `asignaciones` con
`superficie='wa'`. La regla de contexto ya existente aplica: cada envío del
Cerebro deja aviso en la memoria de Iki (`aviso_iki.sh`).

### 4.6 Medición de la tesis

`asignaciones`, `confirmaciones` y `solicitudes` llevan `superficie` y quién.
Fuente viz `superficies` (read-only, agregada: por persona × acción × semana,
`ui` vs `wa`) para el rol `technology`. Solo señal agregada, nunca contenido.

## 5. Errores, verificación, orden de salida

### 5.1 Errores

| Falla | Comportamiento |
|---|---|
| GHL no responde | Páginas: última lectura con su hora, acciones apagadas con aviso. Iki: «no puedo confirmar contra el calendario ahora». Nunca slots inventados. |
| Cita creada en GHL, Marketico no crea el Meet | La cita es válida; la fila del closer dice «sin Meet aún»; el log de intercepciones lo muestra; la reconciliación lo señala. |
| Slot ocupado entre proponer y confirmar | GHL rechaza → el confirmador ve slots frescos; nunca se fuerza. |
| Doble ejecución del mismo `asignar` | Misma cita (idempotencia por contacto+calendario+hora), una sola fila válida. |
| Rol sin permiso de escritura | `exit 3` del script, 403 en la UI, «no tienes permiso para esto» en Iki. |
| Postgres caído | Sin agenda (las credenciales de GHL viven ahí) — como hoy. |

### 5.2 Verificación

1. Scripts WRITE contra una cita `[test]` en «Aplicación» a nombre de Lucho: crear → mover → cancelar; dry-run de cada uno; idempotencia (crear dos veces = una cita).
2. Página del setter con Cristian, un lead real, hasta la cita creada — con Cristian avisado y Santiago mirando.
3. Página del closer con Carlos leyendo esa cita con su Meet.
4. `asignar` por Iki con Anthony (misma bitácora, `superficie='wa'`).
5. Reconciliación de las 17: cero drift con los dos calendarios.
6. Mensajes de WhatsApp de closers del día siguiente con la agenda de `venta`.

### 5.3 Orden de salida

1. Migración 008 + base `asignacion` + prioridad inicial (la fija Lucho o Santiago).
2. Lado WRITE de `bash/ghl/` + cerca `escrituras` + rol `setter` en el mapa.
3. Comandos `bash/agenda/`.
4. `agenda-setter` v2 + `POST /act` del publicador.
5. `agenda-closer` + publicación por closer.
6. Escenarios WhatsApp de closers leyendo `venta`.
7. Iki: `API_ACTIONS` + conversación de asignación.

**Fuera del Cerebro, pedidos hoy:** filtrar el workflow de GHL por calendario
(solo `venta` dispara `/crm`) y agregar a Mateo como miembro de «Aplicación».

## 6. Fuera de alcance (y por qué)

- Recibir el webhook de GHL en el Cerebro y pedir el Meet por API (forma B): loop siguiente.
- Prioridad calculada del análisis de closers: cuando exista, reemplaza la tabla sin tocar el comando.
- Producto propuesto por capital declarado: v2 de la regla.
- Desenlaces post-venta (venta/plan de pagos): ya cubiertos por el registro por el grupo (`docs/rutina-registro-only-closers-brief.md`).
- Caída de volumen de reservas desde el 17-ago (15-20/día → 1-4/día): mirada aparte, no es de este diseño.

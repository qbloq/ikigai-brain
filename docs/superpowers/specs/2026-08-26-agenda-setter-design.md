# Agenda del Setter — diseño (2026-08-26)

Primera pieza del ecosistema del rol **Setter** (Antonio = Cristian Buelvas,
Anthony Velásquez): un dashboard con la **agenda del día y de la semana**
tomada 100 % de GHL, enriquecida con lo que el Cerebro sabe de cada lead —
el link de Meet, el closer dueño, el **predictor pre-llamada** para las que
vienen, y el **estado por capas** (ocurrió · analizada · BANT · venta) para
las que ya pasaron.

Nace de tres hechos verificados el 2026-08-25/26:

- La cita del calendario oficial de GHL ya trae **`contactId`**,
  **`assignedUserId`** (que resuelve a closer o a setter) y su estado; por el
  id de la cita se llega al meeting del sistema y a su `meet_url`. Hoy hay
  además 5 llamadas en el sistema que **no** existen en GHL (drift
  `sobra_en_db`).
- El predictor pre-llamada validado son **bandas A/B/C** sobre dos preguntas
  del survey (`docs/lead-score.md` §3/§5), no un número; y el lead recién
  agendado existe en GHL **antes** que en el espejo de la base (el de hoy
  09:20 tenía 7 respuestas en GHL y ninguna fila en `crm_contacts`).
- «¿Ya la reportó el closer?» no tiene fuente: `call_meeting_results` tiene 13
  filas en su historia; en 14 días, de 79 llamadas: 1 con resultado en la App,
  13 con grabación, 11 con transcript usable, 13 con reporte BANT. Desde el
  25-ago el closer **anuncia en el grupo ONLY CLOSERS**, que no se persiste.

Decisión (Santiago, 2026-08-26): **opción C** — el dashboard sale con lo
verificable en el sistema; la columna «anunciada por el closer» nace declarada
como *pendiente de conectar al grupo* y la llena el detector de anuncios de la
rutina de registro (`docs/rutina-registro-only-closers-brief.md`, pieza 1)
como segundo sub-proyecto.

## 1. Alcance de la v1

**Entra**

- Fuente `bash/setters/agenda.sh` (read-only: GET a GHL + `psql_ro`) que
  emite UN objeto: la agenda de un día o de una semana con cada cita
  enriquecida.
- Página `agenda-setter` del viz (autosuficiente — el publicador v1 no monta
  `/c/`, así que el detalle del lead va inline, no por fragmento enrutado).
- Spec de rol `viz/specs/roles/setter/agenda-setter.json` (capa de rol nueva).
- Publicación en la app por **usuario** (Antonio, Anthony, Luis).

**No entra** (y queda dicho dónde vive)

- Leer los anuncios del grupo → sub-proyecto 2 (detector de anuncios).
- Score pre-llamada 0-100 → paso 2 del plan de `docs/priorizacion-leads-informe.md`
  §7; requiere validación contra plata como el BANT. Aquí solo bandas.
- Escribir en GHL (agendar/reagendar/marcar asistió) → política `bash/ghl/`:
  solo lecturas. El setter lo hace en GHL; el dashboard lo refleja.
- Andrea Torres: su calendario está inactivo en `crm_calendars`. El script
  acepta `--project` y toma los calendarios **activos** del proyecto; DG es el
  único hoy.
- Copiloto (fork) del setter y rol `setter` en `docs/roles/acceso.json`: v1
  publica por usuario; el rol en `acceso.json` se declara cuando exista un
  fork que lo lea.

## 2. Fuente: `bash/setters/agenda.sh`

```
agenda.sh [--project N] [--fecha YYYY-MM-DD] [--vista dia|semana] [--json]
  --project  fragmento del nombre (default: David Guerrero)
  --fecha    día de referencia, Bogotá (default hoy)
  --vista    dia (default) = ese día · semana = lunes–domingo que contiene --fecha
```

Siempre emite JSON (un objeto). Read-only. Dominio nuevo `bash/setters/`
(README corto con la regla «GHL manda»). Cerca por rol: usa `bash/ghl/lib`
(dominio `ghl` en `bash/lib/acceso.sh`) — desde el cerebro y el publicador
corre; desde un fork sin ese dominio se niega con exit 3, como todo `bash/ghl/`.

### 2.1 Algoritmo

1. **Calendarios**: `crm_calendars` activos del proyecto (hoy uno:
   `bFFbTpMillO1n35FuDmv`). Miembros del calendario vía
   `GET /calendars/{id}` (`teamMembers[].userId`) = **los setters** (verificado
   2026-08-25: solo Cristian y Anthony son miembros; es lo que hace que un
   closer que reagenda caiga a su calendario personal).
2. **Citas**: `GET /calendars/events` en la ventana (mismo contrato que
   `bash/ghl/appointments.sh`: Version `2021-04-15`, epoch millis; se descartan
   las que caen fuera de la ventana Bogotá — el filtro del server es grueso).
   Se conservan **todos** los `appointmentStatus` (`confirmed`, `new`,
   `cancelled`, `showed`, `noshow`, `invalid`).
3. **Contacto en vivo** por `contactId` distinto: `GET /contacts/{id}` →
   nombre, email, teléfono, `source` (formulario), `tags`,
   `attributionSource` (sesión, campaña, utm), `customFields[{id,value}]`.
   En paralelo con un semáforo de 4 (la función `ghl_api` se hereda en
   subshells; credenciales cargadas UNA vez). Si un GET falla → fallback al
   espejo `crm_contacts` y la fila lo declara (`lead.fuente = "espejo"`).
4. **Catálogo del survey**: `crm_custom_fields` del proyecto
   (`ghl_field_id → name, position`) para nombrar cada respuesta.
5. **Sistema** (una sola consulta a Postgres con todos los ids de cita y de
   contacto):
   - `meetings` por `event_id = appointment.id` (o
     `event->'booking'->>'appointment_id'`): `id`, `meet_url`, `status`,
     `recording_url`, `drive_file_id`.
   - `meeting_transcripts`: `length(transcript) >= 2000` = usable.
   - `call_report_vigente` + `call_reports` (última generación): fuente,
     medianas BANT, `baja_confianza`, arquetipo votado.
   - `payment_plans` por `customer_id = ghl_contact_id` con
     `created_at >= fecha de la cita` y `plan_status='Active'` → venta.
   - `crm_opportunities` del contacto (espejo): etapa del tablero (nombre
     desde `crm_pipelines.stages`), dueño.
   - Historial: meetings anteriores del mismo `contact_id` (n, última fecha,
     BANT del último reporte).
   - `users.integrations->>'<locationId>'` = `assignedUserId` → persona.
6. **Solo en el sistema**: meetings `call` del proyecto en la ventana, no
   cancelados, cuyo `event_id` no está entre las citas de GHL — la lista de
   alertas (drift), con id corto, hora, lead y closer.
7. Reloj: el `startTime` de GHL trae offset → hora de pared Bogotá;
   `meetings.scheduled_start_time` se lee LITERAL (quirk Bogotá-como-UTC).

### 2.2 Banda pre-llamada (de `docs/lead-score.md` §5)

Dos campos del survey, identificados por nombre en el catálogo (los ids son
por proyecto):

- **presupuesto** — nombre `ILIKE '%al menos $1.500%'`; valores vistos:
  `$500`, `$1.500`, `$2.000`, `más de $4.000`.
- **disposición** — nombre `ILIKE '%situación te encuentras actualmente%'`;
  valores: «listo para tomar acción…», «interesado en saber más», «en
  búsqueda…».

| banda | regla |
|---|---|
| **A** | presupuesto respondido y ≠ `$500` **y** disposición empieza por «listo» |
| **C** | ninguno de los dos respondido |
| **B** | cualquier otra combinación |

Un valor no reconocido en presupuesto cuenta como **respondido pero no A**
(banda B) y viaja crudo en `banda.presupuesto` — nunca se descarta un lead
por un rótulo nuevo. La lógica vive en una función Python pura dentro del
script (`banda(presupuesto, disposicion)`) y se prueba con casos fijos
(`bash/setters/test_banda.sh`, mismo estilo que `bash/lib/test_acceso.sh`).

### 2.3 Estado derivado

Para cada cita, `pasada = inicio < ahora (Bogotá)`.

| estado | condición (primera que aplica) |
|---|---|
| `cancelada` | `estado_ghl = cancelled` |
| `proxima` | no pasada |
| `venta` | plan Active creado desde la fecha de la cita |
| `analizada` | hay reporte vigente |
| `ocurrio_sin_analisis` | transcript usable **o** grabación (recording_url / drive_file_id) |
| `sin_rastro` | nada de lo anterior — la cola de «¿qué pasó?» |

Banderas accionables (independientes del estado): `sin_closer`
(`assignedUserId` es miembro del calendario = setter, o no resuelve),
`sin_meet` (sin meeting en el sistema: la llamada no pasó por el webhook —
no habrá grabación ni análisis), `etapa_no_confirmada` (etapa CRM distinta
de «LLAMADA CONFIRMADA», regla del tablero de `bash/closers/agenda.sh`).

`anunciada` va **siempre `null`** en v1 y `sin_instrumentar` lo explica.

### 2.4 Contrato de salida

```json
{
  "proyecto": "David Guerrero",
  "calendarios": [{"id": "bFFb…", "nombre": "Calendario Premium Mastermind", "setters": ["Cristian Buelvas", "Anthony Velásquez"]}],
  "ventana": {"vista": "dia", "fecha": "2026-08-26", "desde": "2026-08-26", "hasta": "2026-08-26", "ahora": "2026-08-26T10:42"},
  "fuente": {"ghl": "ok", "detalle": null, "contactos_en_vivo": 5, "contactos_espejo": 0},
  "kpis": {"citas": 6, "confirmadas": 5, "canceladas": 1, "banda_a": 2, "sin_closer": 1, "sin_meet": 0,
           "pasadas": 3, "ocurrieron": 2, "analizadas": 1, "ventas": 0, "sin_rastro": 1},
  "citas": [{
    "appointment_id": "clbGUYBJlCXy2BvUXoAi", "fecha": "2026-08-26", "hora": "09:20", "fin": "09:40",
    "estado_ghl": "confirmed", "titulo": "Mauricio Carmona - Premium Mastermind", "creada_por": "booking_widget",
    "pasada": false, "estado": "proxima",
    "lead": {"nombre": "Mauricio Hernán Carmona", "email": "…", "telefono": "+57…", "formulario": "Survey Mastermind - VSL NUEVO OCT 2025",
             "sesion": "Social media", "campana": "Fly_test_genero_masc_50", "tags": ["…"], "fuente": "ghl"},
    "closer": {"nombre": "Carlos González", "user_id": "…", "ghl_user_id": "6T2t…"}, "sin_closer": false,
    "meeting": {"id8": "05e43816", "meet_url": "https://meet.google.com/…", "status": "scheduled"}, "sin_meet": false,
    "etapa_crm": "LLAMADA CONFIRMADA", "etapa_no_confirmada": false,
    "banda": {"letra": "A", "presupuesto": "$1.500", "disposicion": "Estoy listo para tomar acción e invertir"},
    "survey": [{"campo": "¿Tienes al menos $1.500 USD…?", "valor": "$1.500"}],
    "historial": {"llamadas_previas": 0, "ultima": null, "bant_previo": null},
    "ocurrio": {"transcript": false, "grabacion": false},
    "reporte": null,
    "venta": null,
    "anunciada": null
  }],
  "solo_en_sistema": [{"id8": "05e43816", "fecha": "2026-08-26", "hora": "09:00", "lead": "Javier Gutierrez", "closer": "Carlos González"}],
  "sin_instrumentar": [
    "anunciada: el desenlace que el closer anuncia en ONLY CLOSERS no se persiste aún (detector de anuncios, sub-proyecto 2)",
    "asistió/no asistió: GHL lo soporta (showed/noshow) y nadie lo marca; el setter puede empezar hoy"
  ]
}
```

`reporte`, cuando existe: `{"fuente": "cerebro|gemini", "bant": {"budget": 70, "authority": 80, "need": 60, "timeline": 75, "total": 71}, "baja_confianza": ["budget"], "arquetipo": "Emocional", "meeting_id8": "…"}`.
`venta`: `{"plan_id8": "…", "monto": 1000, "cuotas": 1, "creado": "2026-08-20"}`.

### 2.5 Errores

- **GHL caído ≠ agenda vacía**: si la sonda de citas falla, `fuente.ghl =
  "error"` con el detalle, `citas = []`, y la página lo muestra como aviso —
  jamás se rellena desde la base.
- Contacto que falla → espejo + `lead.fuente = "espejo"` (y si tampoco está:
  nombre del título de la cita, `fuente = "titulo"`).
- Postgres caído: la agenda sale igual (citas + lead + banda + closer sin
  resolver), con `fuente.db = "error"`; las columnas del sistema quedan
  `null` y la página lo declara. GHL es la fuente de la agenda; la base solo
  enriquece.

## 3. Página `agenda-setter`

`viz/pages/agenda-setter.js` exporta `{id: "agenda-setter", render(ui), manifest}`,
`manifest.consumes = "object"`, `overridable = ["fecha", "vista", "project"]`.
Autosuficiente (sin `/c/`): todo el detalle viaja en el HTML y se despliega
con un toggle por fila (Datastar `data-signals` + `data-show`).

**Cabecera**: proyecto · selector de vista (Hoy / Semana) · navegación
← día/semana → · fecha de referencia · aviso si `fuente.ghl != ok` o
`fuente.db == error` · «contactos en vivo N / espejo M».

**KPIs** (bloque `kpi-cards`, dos filas): *Por venir*: citas · confirmadas ·
banda A · sin closer · sin Meet. *Ya pasaron*: ocurrieron · analizadas ·
ventas · sin rastro. «Anunciadas» va **muted** (promesa visible, no medible
aún).

**Vista día**: sección **Por venir** (cronológica) y sección **Ya pasaron**
(la más reciente primero), separadas por la hora actual. **Vista semana**: lo
mismo agrupado por día (lunes→domingo), cada día con su corte.

**Fila** (`.tbl`): hora · lead · banda (badge A/B/C; solo en las por venir) ·
closer (badge «sin closer» en `--cau`) · Meet (link; «sin Meet» en `--neg`) ·
estado GHL (es-ES) · etapa CRM · — para las pasadas — ocurrió (transcript /
grabación) · BANT total (+ tramo por color; `baja_confianza` con ⚠) · venta ·
estado derivado (badge) · anunciada (—, tooltip «pendiente de conectar al
grupo»). Canceladas atenuadas (`--text-3`).

**Detalle** (toggle): datos de contacto · origen (formulario, sesión,
campaña) · **survey completo** (campo → valor) · historial de llamadas ·
reporte (4 ítems BANT, arquetipo, link a la página `reporte-llamada`
`?meeting=`) · plan de pago · ids cortos (cita GHL, meeting).

**Alertas**: bloque «En el sistema, no en GHL» con `solo_en_sistema` (para
que el setter corrija la agenda), y el bloque `sin_instrumentar` como nota
al pie.

Política de visibilidad: el setter **sí** ve la banda (es la capa de
operación de `docs/lead-score.md` §5); el número BANT de las pasadas se
muestra porque el setter no está en la llamada — no hay profecía que
cumplir. Si Luis publica la misma UI a un closer, ese es otro spec.

Tema: solo clases del DS y tokens semánticos; nada de hex. Overlay de carga
estándar en la re-consulta (cambio de fecha/vista).

## 4. Registro y publicación

- `viz/lib/datasources.js`: `agenda_setter = {script: "bash/setters/agenda.sh",
  emits: "object", args: {project, fecha, vista}}`, **sin caché** (vista
  operativa) — GHL es la latencia (~30 GETs en semana, en paralelo).
- Spec `viz/specs/roles/setter/agenda-setter.json`: `{id: "agenda-setter",
  name: "Agenda del setter", component: "agenda-setter", source:
  "agenda_setter", params: {project: "David Guerrero", vista: "dia"}, scope:
  "role", role: "setter"}`.
- Publicar: `publicar_ui.sh agenda-setter --slug agenda-setter` y
  `permiso_ui.sh agenda-setter --user <email>` para Cristian Buelvas,
  Anthony Velásquez y Luis David Flórez (sin plantilla de identidad: el setter
  ve toda la agenda). Requiere que los tres tengan cuenta en la app
  (Anthony la tiene desde el 03-ago; verificar Cristian).
- Higiene declarada, tarea aparte: Cristian y Anthony figuran como *Closer*
  en `team_members`/`team_roles`; pasarlos a *Setter* y regenerar
  `docs/roles/setter.md` (que aún dice Mateo).

## 5. Verificación

1. `test_banda.sh`: A/B/C con respondido/no respondido, `$500`, valor
   desconocido, disposición sin «listo».
2. `agenda.sh --json` de hoy y `--vista semana --fecha <lunes pasado>`:
   el número de citas cuadra con `bash/ghl/appointments.sh` en la misma
   ventana; cada cita con meeting trae `meet_url`; las 5 `sobra_en_db` del
   drift aparecen en `solo_en_sistema`.
3. Simulación de fallo: `GHL_BASE` inválido → `fuente.ghl = error` y
   `citas = []`; sin Postgres → agenda con `fuente.db = error`.
4. Página en el viz local (`npm run viz:restart`): día y semana, un lead
   desplegado, modo claro y oscuro; luego `publicar_ui.sh --dry-run`.

## 6. Después de la v1

1. **Detector de anuncios** del grupo (brief de la rutina, pieza 1) → llena
   `anunciada` y persiste el desenlace (pregunta §5.3 del brief).
2. Pedirle al setter que marque `showed/noshow` en GHL: si lo adopta, la
   columna «asistió» sale gratis y alimenta el embudo de asistencia (§4.1 del
   informe ONLY CLOSERS).
3. Score pre 0-100 con las preguntas del censo, validado contra plata.
4. Rol `setter` en `acceso.json` + fork cuando haya copiloto.

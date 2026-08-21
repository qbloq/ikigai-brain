# Control de acceso a fuentes por rol (copilotos)

**Fecha**: 2026-08-20 · **Estado**: implementado 2026-08-21 (plan
`docs/superpowers/plans/2026-08-21-control-de-acceso-fuentes.md`) + **adenda
del mismo día** (abajo): el mapa salió a `docs/roles/acceso.json` y cubre
también las UIs del viz; `technology` = todo-poderoso. Preguntas abiertas:
1 resuelta (archivo, no código — ver adenda), 2 resuelta
(`director-comercial` sin `ghl`), 3-4 siguen abiertas

## Contexto y propósito

Hoy la casa tiene dos dominios de `bash/` que operan con **credenciales de
proveedor** leídas de la base (tokens en claro): `bash/ghl/`
(`project_crm_configs`) y `bash/vturb/` (`project_vturb_video_configs`). Ambos
traen el mismo guardián, copiado a mano: si existe `copilot.json` en la raíz,
el script se niega (`exit 3`) — «este dominio es solo del cerebro». La doctrina
detrás: el cerebro corre en una máquina que la org controla; los copilotos
están destinados a 19 laptops de empleados, y una llave maestra regada no se
puede auditar ni revocar por persona. El patrón correcto para copilotos es
`bash/google/`: el backend es dueño de la identidad y cada copiloto le habla
con SU `CEREBRO_TOKEN` (auditado, revocable).

Lo que lo hizo saltar (2026-08-20): la UI **Embudo · El cruce** (`embudo.sh` →
`bash/vturb/analitica.sh`) se llena en el cerebro pero en el copiloto de
Lorenzo (rol `ejecutivo`) muestra el bloque VSL con error declarado. La
cerca binaria trata igual al CEO que al editor de video.

**Decisión de Santiago**: el acceso a fuentes lo define **el rol**, no el
hecho de ser copiloto. El rol **Ejecutivo puede acceder a cualquier fuente de
datos del negocio**, incluidas las que llevan credencial de proveedor.

Dos honestidades que el diseño tiene que cargar, no esconder:

1. **La cerca es un riel, no un muro.** Un fork con `DATABASE_URL` podría
   leer el token con un `SELECT`. El guardián mantiene honesto el camino
   honesto (y evita que se construya algo NUEVO que dependa de la llave en un
   fork); el muro de verdad es mover las credenciales detrás del backend —
   estado final ya declarado en `bash/ghl/README.md`.
   *Corrección (adenda 3, 2026-08-21): eso era cierto para el DSN admin, no
   para los roles PG de copiloto — la migración 003 §2b ya les REVOCABA
   `project_*_configs`; Postgres era un muro más alto que el riel, y los dos
   mapas se contradecían. Desde la 007 el mapa es uno solo (`tablas`).*
2. **La máquina no es el criterio.** Hoy «el copiloto de Lorenzo» corre en la
   máquina de Santiago; mañana en la de Lorenzo. La cerca decide por
   `copilot.json` (rol), no por dónde corre, para que no se olvide de cerrar
   el día de la mudanza.

## Qué NO hace esta fase (no-goals)

- No mueve credenciales al backend ni construye el fallback vía proxy Mkt
  (VTurb) para roles sin acceso. Eso es el paso siguiente, y la salvedad
  medida sigue vigente: el normalizador de retención de Marketico tiene el
  bug documentado en `bash/vturb/README.md` (plays/pitch/CTA bien,
  retenciones mal).
- No toca el control de acceso de **git** (forja `accesos/` + `bin/authz`,
  pre-receive): ese es otro plano (quién puede empujar a qué bare).
- No cifra los tokens en la base (el nombre de la columna miente; es un
  hallazgo conocido, no este spec).
- No decide el mapa completo de roles: solo fija `ejecutivo` = total y deja
  el resto como está (negado), con el socket listo para ampliar.

## Componentes

### 1. `bash/lib/acceso.sh` — la doctrina en UN lugar

Helper pequeño, independiente de `common.sh` (tiene que poder correr en un
fork sin `.env`), con una función:

```
require_acceso <dominio>   # dominio ∈ {ghl, vturb, …}
```

Comportamiento:
- Sin `copilot.json` → cerebro → acceso total, retorna 0 en silencio.
- Con `copilot.json` → lee `role`; consulta el mapa. Si el rol tiene el
  dominio → 0. Si no → mensaje de hoy (qué dominio, por qué, a dónde ir:
  espejo `bash/crm/` para ghl; proxy Mkt pendiente para vturb) y `exit 3`.
- `copilot.json` ilegible o sin `role` → se niega (fail-closed) con mensaje
  claro: un fork sin identidad no hereda permisos.

El mapa vive en el helper como tabla comentada (editar = decisión de
gobernanza, registrada en `gobernanza/`):

```
ejecutivo   : *            # acceso total a fuentes del negocio
# director-comercial : ghl   # candidato; no decidido
```

Regla de lectura: `*` = todos los dominios con credencial; lista = solo esos.

### 2. Las cercas existentes llaman al helper

`bash/ghl/lib/common.sh` y `bash/vturb/lib/common.sh` reemplazan su
`if [[ -f copilot.json ]]` por `require_acceso ghl|vturb`. Mismo mensaje,
misma salida 3, mismo comportamiento para todo rol distinto de `ejecutivo`.
Cualquier dominio futuro con credencial de proveedor **nace** llamando al
helper — la cerca deja de copiarse a mano.

### 3. La doctrina escrita donde viven los roles

- `docs/roles/README.md`: la regla general — «el acceso a fuentes con
  credencial de proveedor lo define el rol; el mapa vive en
  `bash/lib/acceso.sh`; ampliar el mapa es decisión de gobernanza».
- `docs/roles/ejecutivo.md`: «Nivel de acceso a fuentes: **total** — incluye
  dominios con credencial de proveedor (`bash/ghl/`, `bash/vturb/`)».
- `CLAUDE.md` (secciones GHL y VTurb): una línea cada una remitiendo al helper
  en vez de «se niega en forks».

### 4. Propagación

Como todo cambio de `bash/`: commit en el cerebro → `derivar_canal.sh` →
`actualizar_flota.sh` → el hook de SessionStart (o `/actualizarse`) lo trae
al laptop. Nada que desplegar en servidores.

## Manejo de errores (resumen)

- `copilot.json` roto / sin `role` → fail-closed + mensaje (no se inventa
  el rol).
- Rol desconocido (no en el mapa) → negado, mismo camino que hoy.
- El helper nunca toca red ni base: decide con el archivo local. Las
  credenciales siguen saliendo de la base en el dominio, por stdin, nunca argv.

## Testing

- Cerebro (sin `copilot.json`): `bash/vturb/auth_status.sh` y
  `bash/ghl/auth_status.sh` corren como hoy.
- Fork `ejecutivo` (clon de prueba con `copilot.json` `{role:"ejecutivo"}`):
  ambos corren; `bash/metrics/embudo.sh` llena el bloque `vsl` (no `error`).
- Fork de otro rol (p.ej. `editor`): ambos se niegan con exit 3 y el mensaje.
- Fork con `copilot.json` sin `role`: negado con el mensaje de identidad.
- Prueba real: copiloto de Lorenzo tras `/actualizarse` — UI embudo con VSL.

## Preguntas abiertas para la sesión

1. ¿El mapa se queda en código (tabla en `acceso.sh`) o sale a un archivo
   declarativo (`docs/roles/acceso.json`) que el helper lee? Código es más
   simple y viaja por el canal; archivo es más «gobernanza edita sin tocar
   bash». Inclinación: código, con la decisión registrada en `gobernanza/`.
2. ¿`director-comercial` recibe `ghl`? Hoy lee el espejo (`bash/crm/`) y le
   alcanza; la sonda directa es para medir el espejo. Probablemente no.
3. ¿Se registra el uso de credencial desde un fork (telemetría agregada, sin
   contenido — [[privacidad-telemetria-copilotos]])? Va de la mano del spec
   hermano `2026-08-19-seguridad-copiloto-claude-code-design.md`.
4. El paso siguiente real: credenciales detrás del backend + fallback proxy
   Mkt para los roles sin acceso (VTurb ya tiene endpoints de analytics;
   reportar el bug del normalizador antes de apoyarse en sus retenciones).

## Decisiones tomadas en la conversación

- El acceso a fuentes lo define el **rol**, no ser copiloto (Santiago,
  2026-08-20).
- `ejecutivo` = acceso total a fuentes del negocio, incluidas las de
  credencial de proveedor.
- La cerca se decide por `copilot.json`/rol, jamás por la máquina donde corre.
- Un solo helper para todas las cercas; las dos actuales migran a él; las
  futuras nacen con él.
- Se retoma en su propia sesión; este spec es el punto de partida.

## Adenda 2026-08-21 — un solo mapa para fuentes Y UIs; `technology` = todo

**Lo que la disparó.** Santiago: «el rol Technology —o sea nosotros— es el
usuario todo-poderoso; deberíamos poder ver todas las UIs de todos los roles…
la pregunta es si lo podemos hacer elegantemente». Hasta hoy el viz de un fork
cargaba ÚNICAMENTE la capa de su rol
(`viz/lib/store.js`: `roles.filter(r => r.name === COPILOT.role)`), y el mapa
de fuentes vivía como `case` dentro de `bash/lib/acceso.sh`. Dar a technology
las UIs con un `Set` en JS habría dejado **dos mapas de poder en dos
lenguajes**.

**Decisión (Santiago, 2026-08-21).** Un solo archivo declarativo,
**`docs/roles/acceso.json`**, con dos consumidores:

```json
{ "technology": { "uis": "*", "fuentes": "*" },
  "ejecutivo":  { "fuentes": "*" } }
```

- `bash/lib/acceso.sh` lee `fuentes` (el `case` se fue). Mapa ausente o
  ilegible → negado (fail-closed) — salvo el cerebro, que nunca consulta el
  mapa. Sigue sin red ni base, sigue portable a bash 3.2 (parse en python3,
  como `copilot.json`).
- `viz/lib/store.js` lee `uis` al boot: `"*"` → carga **todas** las capas de
  rol; si no, solo la propia. Función pura `rolesVisibles(copilot, acceso,
  roles)` (test `viz/test/acceso.test.js`). **Cambio de comportamiento
  alineado**: un `copilot.json` sin `role` ya no ve todo por accidente — ve
  cero capas de rol (antes, sin filtro = veía todas), la misma regla que el
  helper: *un fork sin identidad no hereda permisos*.
- «Todo-poderoso» incluye **las fuentes**, no solo las UIs: ver la UI Embudo
  del ejecutivo sin `bash/vturb` habría mostrado el bloque VSL en error. Ver
  una UI es ver sus datos.
- Cuando un workspace ve más de una capa de rol (cerebro, technology), el panel
  de UIs muestra un **badge con el rol** de cada UI (`_layer`, que ya existía
  y no se mostraba). Y el store **avisa en consola** si dos capas de rol
  comparten un slug (sombreado silencioso; hoy no hay colisiones — es un
  aviso, no una regla).

**Por qué esto reabre y cierra la pregunta 1.** Se había decidido «código»
porque había UN consumidor; con dos, la balanza se da vuelta. El registro de
la decisión sigue siendo este spec; el archivo es el *estado*, el spec es el
*porqué*.

**Alcance.** Es el viz local del fork (Fase 1, identidad sin auth). El
publicador (`app.ikigaigm…`) tiene su propio `permiso_ui.sh` por rol/usuario
y no se toca. Tampoco cambia `actualizar_flota`/canal: `docs/roles/` ya viaja
a los copilotos, así que el mapa llega solo.

**Verificado.** `bash/lib/test_acceso.sh` 15/15 en bash 5.2 y 3.2.57;
`npm run test:viz` 38/38; forks simulados: technology carga las 4 capas de
rol, ejecutivo solo la suya, editor y «sin role» ninguna, cerebro todo.

## Adenda 2 · 2026-08-21 — `bash/users` sale de `EXCLUIR`; `fuentes` → `dominios`

**La pregunta de Santiago**: «el rol Technology debe tener acceso a todos los
bash; ¿lo podemos hacer con el esquema que ya tenemos, o lo pasamos de largo?».
Lo pasamos de largo a medias: había **dos mecanismos** decidiendo lo mismo —
`acceso.json` (por rol, explícito) y la lista `EXCLUIR` de
`derivar_canal.sh` (forja; «esto no viaja a ningún fork», implícito, anterior
al sistema de acceso). `technology` ya tenía `*`, pero tres directorios
(`bash/ops`, `bash/users`, `bash/whatsapp_evo_api`) no le llegaban porque no
llegaban a nadie.

**Decisión (Santiago)**: el sistema de acceso es el juez; **`EXCLUIR` queda
para lo que no debe existir en un laptop**. Por ahora sale solo
**`bash/users`**: viaja a todos los forks y lo cerca `require_acceso users`
(en `bash/users/lib/common.sh` y en `usuarios_db.sh`, que no carga esa lib).
`bash/ops` (escrituras destructivas de operador: `wipe_tasks.sh`…) y
`bash/whatsapp_evo_api` siguen excluidos — el riel no basta para eso.

**Rename**: la clave `fuentes` pasa a **`dominios`** — ya no son solo fuentes
de datos con credencial, son los `bash/` cercados por rol. Mapa vigente:
`technology = {uis:*, dominios:*}`, `ejecutivo = {dominios:*}`.

**Capa que sigue aparte**: la credencial. `bash/users` necesita
`MARKETICO_JWT_TOKEN` en `.env`; un fork technology pasa la cerca y después
se detiene en el token si su máquina no lo tiene. Eso no es del esquema de
roles — es *qué secretos tiene la máquina* — y se decide al dar el `.env`.


## Adenda 3 · 2026-08-21 — Postgres entra al mapa: `tablas` y el tier total

**La pregunta de Santiago**: «¿cómo está funcionando el control de acceso por
usuario (copiloto) a Postgres? ¿a ese nivel también estamos aprovechando la
arquitectura de acceso?».

**Lo que había** (verificado en la DB viva): un rol PG por copiloto
(`ikigai_<empleado>` LOGIN, `NOBYPASSRLS`, `CONNECTION LIMIT 5`) miembro de
`ikigai_copiloto_base` — SELECT en todo el schema menos el **tier sensible**
(runtime LLM, `project_*_configs`, compensación, `identities`: 003 §2b) —
y `ikigai_tier_compensacion` (004) devuelto a los ejecutivos. Seis altas
reales (Lorenzo, Juan Camilo, Pablo, Luis David, David Castaño, Marisol); los
otros 13 forks no tienen rol PG ni `.env`. **No aprovechaba el mapa**: los
tiers estaban hardcodeados en `crear_alta.sh` (`ejecutivo → compensacion`) y la
membresía nombrada en la 004. Consecuencia medida: `acceso.json` decía
`ejecutivo: dominios:*` (pasa `bash/vturb`) y Postgres respondía `permission
denied for table project_vturb_video_configs` con el DSN real de Lorenzo — la
cerca de la adenda 1 se había probado en un clon sin `.env`, no en el camino
completo.

**Decisión (Santiago)**: «por ahora los roles **Ejecutivo** y **Technology**
tienen acceso a **todas** las tablas, pero solamente esos roles».

**Cómo quedó**:
- `catalog/migrations/007_tier_total.sql` (aplicada): rol `ikigai_tier_total`
  NOLOGIN con SELECT sobre todas las tablas del schema (+ default privileges
  para las futuras) y política RLS `tier_total FOR SELECT USING(true)` en las
  89 tablas con RLS. **Solo lectura** — las escrituras siguen siendo las del
  `copiloto_base`. Membresía al aplicar: Lorenzo, Juan Camilo, Pablo. Incluye,
  declarado, el runtime LLM (`llmrouter_api_keys`) e `identities`; dejar el
  runtime fuera es un `REVOKE` de 14 tablas si se decide.
- `docs/roles/acceso.json` gana la clave **`tablas`** (`"*"` → `tier_total`;
  lista → `tier_<nombre>`; sin clave → solo base). Tercer consumidor:
  `forja/bash/fleet/crear_alta.sh` la lee del clon del copiloto al dar de alta,
  y **re-ejecutar re-sincroniza** (concede los tiers del rol, revoca los que ya
  no le tocan); el chequeo del tier sensible se invierte cuando el rol tiene
  `tier_total`. Ya no hay hardcode de rol en forja.
- `slices.md` §4 lleva la excepción vigente; §5 describe el consumidor PG.

**Verificado**: con el DSN real de Lorenzo, en su clon: `bash/vturb/auth_status.sh`
→ `auth ok` en los dos proyectos; `bash/finance/comisiones.sh` lista; `INSERT`
en `project_crm_configs` → `permission denied`. `has_table_privilege` de Luis
David (director-comercial) sobre `project_crm_configs` → `f`.

**Lo que sigue abierto**: cambiar `tablas` en el mapa no mueve a los copilotos
ya dados de alta sin re-correr `crear_alta.sh` (que rota credenciales) o un
GRANT/REVOKE del operador — falta un `sync_tiers.sh` que solo re-sincronice
membresías. Y la Etapa 2 de `slices.md` (un slice RLS por rol de negocio)
sigue sin construirse: todo copiloto con alta ve toda la org menos el tier
sensible.

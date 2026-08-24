# Revisión de propuestas — diseño (2026-08-24)

UI de rol **Technology** para revisar, desde el navegador, dos colas de
propuestas que hoy solo viven en prosa o en una consulta:

1. **Propuestas de tareas de las reuniones** — lo que `meeting-to-tasks` deja
   en `backups/meeting-tasks/<meeting>.md` desde el 21-ago (`744e998f`,
   `92d6cef4`). Se decide, tarea por tarea, cuál **entra** al cerebro y cuál
   **se queda**.
2. **Tareas sin arquetipo** — las tareas del cerebro con `archetype_id IS NULL`
   (22 abiertas, 43 en total al 2026-08-24), cada una con un **arquetipo
   propuesto** y sus alternativas, para aceptarlo o elegir otro.

Regla que sostiene todo: **el viz es el visor; la UI marca, la conversación
ejecuta.** La UI escribe únicamente marcas de curaduría en una sqlite local
(patrón exacto del botón *Merge* del cruce y de *Aprobar/Rechazar* de la Mesa
de Despacho). Nada aquí toca Postgres: lo marcado lo ejecuta después un script
desde la conversación, con `--dry-run` antes.

## 1. Fuente estructurada: el JSON gemelo del backup

El `.md` es prosa para humanos y cambia de forma entre corridas; no se parsea.
El skill `meeting-to-tasks` pasa a escribir, junto al `.md`, un
**`backups/meeting-tasks/<meeting-id>.json`** — el gemelo estructurado (la misma
jugada que la procedencia de tareas: columna estructurada + comentario humano).

```json
{
  "meeting": "92d6cef4-5b23-487b-8d4d-9bab969a5d29",
  "fecha": "2026-08-24",
  "nombre": "Daily planeación semana Ikigai",
  "md": "92d6cef4.md",
  "propuestas": [
    {
      "ref": "A1", "seccion": "A",
      "contrato": { "...forma exacta de create_task.sh (title, project, priority,
                     due_date, assignee[], source_meeting, archetype, slots{},
                     comments[]?)..." },
      "vence_estimada": false,
      "evidencia": "«vamos pendiente de los ajustes…»",
      "comentario": "Es el remate de la landing de Roberto (744e998f §B2).",
      "relacionadas": ["674f7f7b"],
      "depende_de": ["A7"]
    },
    {
      "ref": "B1", "seccion": "B",
      "titulo": "Escribir el VSL tipo clase co-presentado",
      "pregunta": "≡ cdb9249d — ¿agrego a Lorenzo como co-asignado?",
      "accion_sugerida": "comentario + reassign --add",
      "relacionadas": ["cdb9249d"],
      "contrato": null
    }
  ]
}
```

- `contrato` de §A es **byte-válido para `create_task.sh`** (se verifica con
  `--dry-run` al cargar; una propuesta que no valida se carga igual pero con
  `valida=0` y el error, para que se vea y se corrija en el JSON).
- §B viaja con `contrato: null` y su `pregunta`: se decide igual, pero el
  ejecutor nunca crea una fila §B — esas se resuelven en conversación
  (comentario, cierre, reasignación).
- Los dos JSON existentes (`744e998f`, `92d6cef4`) los genera el cerebro
  **una vez, en conversación**, desde sus `.md`. En adelante los escribe el skill.

## 2. Base local `propuestas_reuniones` (`data/sqlite/`)

```
lotes       meeting_id PK · meeting_corto · archivo · fecha · nombre · cargado_en · n_a · n_b
propuestas  n PK · meeting_id FK · ref · seccion A|B · titulo · proyecto · prioridad
            · vence · vence_estimada · asignados (json) · arquetipo · slots (json)
            · evidencia · comentario · pregunta · relacionadas (json) · depende_de (json)
            · contrato (json) · valida 0|1 · error_validacion
            · decision NULL|entra|se_queda · decision_nota · decidida_en
            · creada_id (uuid, sellado por el ejecutor) · creada_en
arquetipos  task_id PK · titulo · proyecto · sugerido · score · alternativas (json)
            · decision (id de arquetipo | 'ninguno') · decision_nota · decidida_en
            · aplicado_en
```

`lotes.meeting_id` es la llave de idempotencia: **un backup cargado no se vuelve
a ofrecer**. Las filas con `decision` se pueden cambiar mientras no tengan
`creada_id`/`aplicado_en` — una vez ejecutadas se congelan (misma regla que las
filas `resuelta=1` del cruce).

## 3. Scripts

Locales (`bash/localdb/`, helpers de `sqlite.sh`):

| Script | Qué hace |
|---|---|
| `propuestas_backups.sh [--desde D] [--json]` | Read-only. Lista los `backups/meeting-tasks/*.json` con fecha ≥ `--desde` (default 2026-08-21) y la marca `cargado` (existe en `lotes`). Fuente viz `propuestas_backups`. |
| `propuesta_cargar.sh <meeting-id\|prefijo> [--json]` **[WRITE local]** | Lee el JSON, valida cada contrato §A con `create_task.sh --dry-run`, inserta lote + filas en una txn. **Se niega si el lote ya existe** (por eso el botón desaparece). Crea la db si no existe. |
| `propuestas.sh [--lote M] [--seccion A\|B] [--decision D] [--json]` | Read-only. Las propuestas como filas (todas las columnas). Fuente viz `propuestas`. |
| `propuesta_mark.sh <n> --decision entra\|se_queda\|ninguna [--nota "…"] [--json]` **[WRITE local]** | La marca. Guardrail: se niega sobre filas con `creada_id`. |
| `arquetipo_mark.sh <task-id> --arquetipo A_.__\|ninguno [--nota] [--json]` **[WRITE local]** | La marca de la vista 2 (upsert en `arquetipos`; valida el id contra el catálogo). Guardrail: se niega si `aplicado_en`. |

Postgres, read-only (`bash/tasks/`):

| Script | Qué hace |
|---|---|
| `relacionadas.sh --titulo T --project P [--archetype A] [--assignee N] [--ids a,b] [--limit N] [--json]` | Tareas del cerebro relacionadas con una propuesta, cada fila con `motivo` y `score`: **citada** (id en `--ids`, score 100) · **mismo arquetipo + proyecto** (+40) · **mismo dueño** (+20) · **palabras del título** (Jaccard sobre tokens ≥4 letras sin stopwords, ×40). Abiertas antes que cerradas. Fuente viz `tareas_relacionadas`. |
| `sin_arquetipo.sh [--project P] [--open] [--json]` | Tareas con `archetype_id IS NULL` + **arquetipo propuesto**: para cada tarea, top-3 por dos señales sumadas y declaradas en `motivo`: (a) **léxica contra el catálogo** (`catalog/sop-archetypes.json`: verbo ×2, nombre, nombre del SOP; tokens normalizados por prefijo de 5) y (b) **vecinos ya etiquetados** (las tareas con arquetipo cuyo título comparte tokens; el arquetipo más votado, ponderado por similitud). `score` 0-100; bajo 25 se declara `sugerido=null` («sin propuesta») antes que inventar. Fuente viz `tareas_sin_arquetipo`. |

Ejecutores, desde la conversación (`bash/tasks/`, **[WRITE pg]**):

| Script | Qué hace |
|---|---|
| `crear_de_propuestas.sh [--lote M] [--n LIST] [--dry-run] [--json]` | Gemelo de `merge_from_cruce.sh`: por cada fila §A con `decision='entra'` y sin `creada_id`, `create_task.sh` con el `contrato` guardado; sella `creada_id`/`creada_en`. Las `se_queda` no se tocan; las §B se listan como «pendientes de conversación». |
| `aplicar_arquetipos.sh [--dry-run] [--json]` | Por cada fila de `arquetipos` con `decision` ≠ `ninguno` y sin `aplicado_en`: `set_archetype.sh <task> <A> --method human`; sella `aplicado_en`. ⚠️ Recuerda la regla del catálogo: re-etiquetar mueve el puntero, **no** reescribe el contrato IO. |

## 4. La UI: componente `revision-propuestas` (rol technology)

Spec `viz/specs/roles/technology/revision-propuestas.json` → page
`viz/pages/revision-propuestas.js`. Dos vistas conmutadas por `?vista=` (señal +
URL, como `localdb` con `?db=`), ambas **master-detail** (mismo patrón que el
Editor de IO: lista a la izquierda, panel SSE a la derecha):

**Vista «Propuestas de reuniones»**
- Barra superior: los backups de `propuestas_backups` como tarjetas; botón
  **Cargar** solo en los no cargados (act → `propuesta_cargar.sh`); los cargados
  muestran fecha de carga y conteos A/B.
- Maestro: filas de `propuestas` — ref, sección, título, proyecto, prioridad,
  vence (con «est.»), dueños, arquetipo, decisión (badge), ✓ si `creada_id`.
  Filtros cliente: lote · proyecto · sección · decisión.
- Detalle (`blocks/propuesta-detail.js`, frag `panel`): el contrato completo
  (título, proyecto, prioridad, vence, dueños, arquetipo + slots, evidencia,
  comentario, `pregunta` si §B, error de validación si `valida=0`), botones
  **Entra / Se queda** (act `mark` → `propuesta_mark.sh`) + nota, y el bloque
  **Relacionadas** en dos capas: *en este lote* (`depende_de` + hermanas de
  mismo proyecto+arquetipo, sin llamada a Postgres) y *en el cerebro*
  (`tareas_relacionadas`, con motivo y score, id corto copiable).

**Vista «Sin arquetipo»**
- Maestro: filas de `tareas_sin_arquetipo` — id corto, título, proyecto, estado,
  dueños, **arquetipo propuesto** (id + nombre + score) y la decisión local si
  existe. Filtro: solo abiertas (default) · proyecto.
- Detalle (`blocks/arquetipo-detail.js`, frag `panel`): el detalle de la tarea
  reutilizando `renderTaskDetail` del bloque `task-detail` (solo lectura) +
  el bloque **Arquetipo propuesto**: el sugerido con su motivo, las
  alternativas con score, un select con todo el catálogo para elegir otro, y
  botones **Aceptar / Ninguno** (act `mark` → `arquetipo_mark.sh`).

Furniture obligatoria (viz/CLAUDE.md): overlay de carga sobre tabla y panel,
`data-indicator`, señales sembradas, clases del DS (`.btn`, `.badge`, `.tbl`),
sin hex. Los writes declarados en `manifest.writes` de cada bloque.

## 5. Flujo de datos

```
meeting-to-tasks ─► <id>.md + <id>.json ─► [UI: Cargar] propuesta_cargar.sh ─► sqlite
UI: Entra/Se queda ─► propuesta_mark.sh ─► sqlite ─► [conversación] crear_de_propuestas.sh ─► Postgres
Postgres (sin arquetipo) ─► sin_arquetipo.sh (+catálogo) ─► UI ─► arquetipo_mark.sh ─► sqlite
                                                            ─► [conversación] aplicar_arquetipos.sh ─► Postgres
```

## 6. Errores

- Backup sin `.json` (solo `.md`) → aparece en la barra como «sin gemelo
  estructurado», sin botón; lo genera el cerebro.
- Contrato que no pasa `--dry-run` → se carga con `valida=0` + el error; el
  detalle lo muestra en rojo y el ejecutor lo salta declarándolo.
- Postgres caído → la vista 2 y el bloque «en el cerebro» muestran el error en
  un `alert-neg`; la vista 1 (local) sigue funcionando.
- Script de marca falla (guardrail) → el error se pinta en el panel, nunca se
  traga (mismo manejo que `cruce.js`).

## 7. Pruebas

- `node --test` para la lógica pura extraída a `viz/lib/`: tokenizador +
  Jaccard compartido por la UI (hermanas del lote) — `viz/lib/similitud.js`.
- Los scripts: `--dry-run` de `propuesta_cargar.sh` sobre los dos JSON reales;
  `relacionadas.sh` contra una propuesta con ids citados (deben salir con
  score 100); `sin_arquetipo.sh` sobre las 22 abiertas, revisadas a ojo en
  conversación (el matcher es heurístico y se declara así).
- Manual en el navegador: cargar un lote, decidir dos filas, ver relacionadas,
  cambiar de vista, aceptar un arquetipo, verificar que el botón *Cargar* no
  vuelve.

## 8. Fuera de alcance (deliberado)

- Editar el contrato desde la UI (se edita el JSON, o tras crear, con
  `/revisar-tarea-io`).
- Ejecutar en Postgres desde el navegador.
- Embeddings: la columna `activity_archetypes.embedding` existe y está vacía;
  el matcher léxico + vecinos es el primer peldaño declarado en el catálogo
  (rule → embedding → LLM). Cuando haya embeddings, `sin_arquetipo.sh` cambia
  por dentro y la UI no.

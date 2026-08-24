# Revisión de propuestas — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Una UI de rol `technology` (patrón master-detail, como el «Editor de IO») que carga los backups de propuestas de tareas ≥ 2026-08-21 en una sqlite local, deja decidir tarea por tarea si **entra** o **se queda** (mostrando tareas relacionadas), y en una segunda vista lista las tareas del cerebro **sin arquetipo** con el arquetipo propuesto para aceptarlo.

**Architecture:** «El viz es el visor; la UI marca, la conversación ejecuta.» Los backups ganan un gemelo JSON (`<meeting>.json`) que el skill `meeting-to-tasks` escribe; scripts `bash/localdb/` cargan y marcan en `data/sqlite/propuestas_reuniones.db`; dos scripts read-only de `bash/tasks/` calculan relacionadas y arquetipos propuestos contra Postgres; una página `viz/pages/revision-propuestas.js` compone el patrón `master-detail` con dos pares de bloques (uno por vista); dos ejecutores **[WRITE pg]** aplican lo marcado desde la conversación.

**Tech Stack:** bash + sqlite3 (3.45) + python3 (stdlib, para scoring y JSON) + jq 1.7 · Node stdlib (viz, Datastar 1.0 colon-syntax, SSE) · `node --test` para la lógica pura.

**Spec:** `docs/superpowers/specs/2026-08-24-revision-propuestas-design.md`

## Global Constraints

- Datos solo por `bash/ --json`; **nunca SQL en el viz**. Cada write de un bloque va declarado en `manifest.writes` (ctx.run lanza si no).
- Scripts locales: `source bash/lib/sqlite.sh`; `sqlite_ro` por defecto, `sqlite_rw` solo en scripts **[WRITE local]**; db por *nombre* (`propuestas_reuniones`), jamás por ruta. Scripts Postgres read-only: `source bash/lib/common.sh` + `psql_ro`/`emit`.
- Convención de salida de los scripts de write: progreso a stderr/stdout y **una línea JSON final** `{ok, …}` con `--json`; en error `{ok:false,error}` + exit ≠ 0 (así lo parsea `viz/lib/actions.js`).
- Datastar 1.0 **con dos puntos**: `data-on:click`, `data-bind`, `data-indicator:loading`, `@get`/`@post`. Señales con `data-bind` sembradas en `data-signals`.
- Tema: clases del DS (`.btn .btn-primary .btn-xs`, `.badge badge-pos|neg|cau|brand|neutral`, `.tbl`, `.alert alert-neg`, `.select`, `.check`), nunca hex; en `<style>` crudo solo tokens semánticos (`var(--text-2)`).
- Furniture obligatoria: overlay de carga sobre tabla (`data-indicator:<signal>`) y sobre panel (`data-indicator:loading`).
- Tras editar `viz/`: `npm run viz:restart`.
- Commits: mensajes en español, estilo del repo (`viz(revision): …`, `localdb: …`, `tasks: …`), trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Ningún ejecutor **[WRITE pg]** se corre contra Postgres en este plan salvo con `--dry-run`.

---

## File map

| Path | Responsabilidad |
|---|---|
| `backups/meeting-tasks/744e998f.json`, `92d6cef4.json` | Gemelos estructurados de los dos backups (Task 1). |
| `bash/localdb/propuestas_schema.sql` | DDL idempotente de la db local (Task 2). |
| `bash/localdb/propuestas_backups.sh` | Lista los backups ≥ fecha con `cargado` (Task 2). |
| `bash/localdb/propuesta_cargar.sh` | [WRITE local] carga un JSON → lote + propuestas (Task 2). |
| `bash/localdb/propuestas.sh` | Filas de `propuestas` (Task 2). |
| `bash/localdb/propuesta_mark.sh` | [WRITE local] decisión entra/se_queda (Task 2). |
| `bash/localdb/arquetipo_mark.sh`, `arquetipo_marcas.sh` | [WRITE local] marca de arquetipo + su lectura (Task 2). |
| `bash/tasks/relacionadas.sh` | Tareas del cerebro relacionadas con un título/proyecto (Task 3). |
| `bash/tasks/sin_arquetipo.sh` | Tareas sin arquetipo + propuesto (Task 4). |
| `viz/lib/similitud.js` + `viz/test/similitud.test.js` | Tokenizador + Jaccard (Task 5). |
| `viz/lib/datasources.js` | 5 fuentes nuevas (Task 5). |
| `viz/blocks/propuestas-table.js`, `propuesta-detail.js` | Vista 1 (Task 6). |
| `viz/blocks/arquetipos-table.js`, `arquetipo-detail.js` | Vista 2 (Task 6). |
| `viz/pages/revision-propuestas.js` | La página: elige bloques por `vista`, act `cargar` (Task 6). |
| `viz/specs/roles/technology/revision-propuestas.json` | El spec de rol (Task 6). |
| `bash/tasks/crear_de_propuestas.sh`, `aplicar_arquetipos.sh` | [WRITE pg] ejecutores (Task 7). |
| `.claude/skills/meeting-to-tasks/SKILL.md`, `CLAUDE.md`, `viz/README.md` | Docs (Task 8). |

## Contratos compartidos (léelos antes de cualquier tarea)

**JSON gemelo** (`backups/meeting-tasks/<id8>.json`):
```json
{ "meeting": "<uuid completo>", "meeting_corto": "<8>", "fecha": "YYYY-MM-DD",
  "nombre": "…", "md": "<id8>.md",
  "propuestas": [
    { "ref": "A1", "seccion": "A",
      "contrato": { "title": "…", "project": "Andrea Torres", "priority": "High",
                    "due_date": "2026-08-24", "assignee": ["Jhonatan Rengifo"],
                    "source_meeting": "92d6cef4", "archetype": "A7.6",
                    "slots": { "pagina": "…", "cambio": "…", "proyecto": "Andrea Torres" },
                    "comments": [ { "text": "…" } ] },
      "vence_estimada": false, "evidencia": "«…»", "comentario": "…",
      "relacionadas": ["674f7f7b"], "depende_de": ["A7"] },
    { "ref": "B1", "seccion": "B", "contrato": null,
      "titulo": "…", "pregunta": "…", "accion_sugerida": "…",
      "relacionadas": ["cdb9249d"], "depende_de": [] }
  ] }
```
Para §A `titulo` se toma de `contrato.title`. `assignee` usa nombres canónicos o el prefijo de id cuando el nombre es ambiguo (`ece00919` Lucho). `slots.proyecto` siempre presente cuando el arquetipo lo declara.

**Fila de `propuestas.sh --json`** (todas las columnas de la tabla + `lote_nombre`, `lote_fecha`, `meeting_corto`): `asignados`, `slots`, `relacionadas`, `depende_de`, `contrato` viajan como **strings JSON** (sqlite `-json` no los expande); el consumidor hace `JSON.parse`.

**Fila de `relacionadas.sh --json`**: `{id, id_full, title, status, project, assignees, archetype, due, score, motivo}` ordenadas por score desc; `motivo` = texto `"citada"`, `"mismo arquetipo A9.2 + proyecto"`, `"mismo dueño"`, `"título 0.43"` unidos por `" · "`.

**Fila de `sin_arquetipo.sh --json`**: `{id, id_full, title, status, priority, due, project, assignees, sugerido, sugerido_nombre, sugerido_sop, score, motivo, alternativas}` con `alternativas` = **string JSON** de `[{id, nombre, sop, score, motivo}]` (máx. 3, incluye al sugerido en primer lugar). `sugerido` es `null` cuando `score < 25`.

**Marcas**: `propuesta_mark.sh <n> --decision entra|se_queda|ninguna [--nota T] --json` → `{ok, n, decision, decision_nota, decidida_en}`. `arquetipo_mark.sh <task-id|prefijo8> --arquetipo A_.__|ninguno [--nota T] --json` → `{ok, task_id, decision, decision_nota, decidida_en}`. `arquetipo_marcas.sh --json` → `[{task_id, decision, decision_nota, decidida_en, aplicado_en}]`.

**Fuentes viz** (ids exactos): `propuestas_backups`, `propuestas`, `arquetipo_marcas`, `tareas_relacionadas`, `tareas_sin_arquetipo`.

**Señales / params** de la página: `vista` (`propuestas`|`arquetipos`), vista 1: `lote`, `proyecto`, `seccion`, `decision`; vista 2: `project`, `open`.

---

### Task 1: Los dos JSON gemelos (LLM, en conversación — no delegar a un parser)

**Files:**
- Create: `backups/meeting-tasks/744e998f.json`, `backups/meeting-tasks/92d6cef4.json`

**Interfaces:**
- Consumes: los `.md` homónimos, el skill `meeting-to-tasks` (mapa de apodos, reglas de slots), `catalog/sop-archetypes.json` (slots por arquetipo).
- Produces: los dos archivos con el **contrato JSON gemelo** de arriba; los consume `propuesta_cargar.sh` (Task 2).

- [ ] **Step 1: Generar `92d6cef4.json`** — 23 propuestas §A (A1–A14, A17–A24; los huecos A15/A16 no existen: el md los remite a §B) + 8 de §B (B1–B8 = los numerales 1–8 de «§B — A tu criterio»). `meeting` = `92d6cef4-5b23-487b-8d4d-9bab969a5d29`, `fecha` = `2026-08-24`. Cada §A: `contrato` completo, `relacionadas` con los ids de 8 que el texto cita (p.ej. A19 → `["255c66b6"]`, A20 → `["6f82166b","955abeb4"]`, A22 → `["3f8f9914","e26b9130"]`), `depende_de` con las cadenas declaradas (A8→[A7], A10→[A9], A3→[A2], A22→[A23]…). `vence_estimada: true` donde el md dice «(est.)». Dueños ambiguos por prefijo: Lucho `ece00919`.
- [ ] **Step 2: Generar `744e998f.json`** — 5 propuestas §A (A1–A5) + 9 de §B (B1–B9). `meeting` = el uuid completo (obtenerlo con `bash bash/meetings/meetings.sh --limit 6 --json | jq -r '.[]|select(.id|startswith("744e998f"))|.id'` — si `meetings.sh --json` solo trae 8 chars, usar `bash bash/meetings/meeting_show.sh 744e998f | head -3`). `fecha` = `2026-08-21`.
- [ ] **Step 3: Validar forma** — `jq -e '.propuestas|length' backups/meeting-tasks/92d6cef4.json` → 31; `jq -e '.propuestas|length' backups/meeting-tasks/744e998f.json` → 14; `jq -e '[.propuestas[]|select(.seccion=="A")|.contrato|has("title") and has("project") and has("due_date") and has("archetype")]|all'` → `true` en ambos.
- [ ] **Step 4: Validar contratos contra Postgres** — por cada §A: `jq -c '.propuestas[]|select(.seccion=="A")|.contrato' <json> | while read -r c; do printf '%s' "$c" | bash bash/tasks/create_task.sh - --dry-run >/dev/null 2>&1 || echo "FALLA: $(printf '%s' "$c" | jq -r .title)"; done`. Corregir en el JSON lo que falle (nombre no resuelto, slot faltante).
- [ ] **Step 5: Commit** — `git add backups/meeting-tasks/*.json && git commit -m "backups(meeting-tasks): gemelos JSON de las propuestas 744e998f y 92d6cef4 — la forma estructurada que carga la UI de revisión"`.

---

### Task 2: La db local y sus cinco scripts (`bash/localdb/`)

**Files:**
- Create: `bash/localdb/propuestas_schema.sql`, `bash/localdb/propuestas_backups.sh`, `bash/localdb/propuesta_cargar.sh`, `bash/localdb/propuestas.sh`, `bash/localdb/propuesta_mark.sh`, `bash/localdb/arquetipo_mark.sh`, `bash/localdb/arquetipo_marcas.sh`

**Interfaces:**
- Consumes: `bash/lib/sqlite.sh` (`db_path`, `require_db`, `sqlite_ro`, `sqlite_rw`, `sql_str`, `LOCALDB_DIR`, `REPO_ROOT`), `bash/tasks/create_task.sh --dry-run`, `catalog/sop-archetypes.json`, los JSON de Task 1.
- Produces: db `propuestas_reuniones`; los JSON de salida del bloque «Contratos compartidos».

- [ ] **Step 1: DDL** — `bash/localdb/propuestas_schema.sql`:
```sql
-- Esquema de la db local `propuestas_reuniones` (idempotente). Lo aplica
-- propuesta_cargar.sh en cada corrida; crear la db = correr esto sobre un
-- archivo nuevo. Dos colas de curaduría: propuestas de reuniones (lotes +
-- propuestas) y arquetipos propuestos para tareas sin etiqueta (arquetipos).
CREATE TABLE IF NOT EXISTS lotes (
  meeting_id    TEXT PRIMARY KEY,
  meeting_corto TEXT NOT NULL,
  archivo       TEXT NOT NULL,
  fecha         TEXT,
  nombre        TEXT,
  cargado_en    TEXT NOT NULL,
  n_a           INTEGER NOT NULL DEFAULT 0,
  n_b           INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS propuestas (
  n                INTEGER PRIMARY KEY AUTOINCREMENT,
  meeting_id       TEXT NOT NULL REFERENCES lotes(meeting_id),
  ref              TEXT NOT NULL,
  seccion          TEXT NOT NULL CHECK (seccion IN ('A','B')),
  titulo           TEXT NOT NULL,
  proyecto         TEXT,
  prioridad        TEXT,
  vence            TEXT,
  vence_estimada   INTEGER NOT NULL DEFAULT 0,
  asignados        TEXT,   -- json array
  arquetipo        TEXT,
  slots            TEXT,   -- json object
  evidencia        TEXT,
  comentario       TEXT,
  pregunta         TEXT,   -- solo §B
  accion_sugerida  TEXT,   -- solo §B
  relacionadas     TEXT,   -- json array de ids (8)
  depende_de       TEXT,   -- json array de refs del mismo lote
  contrato         TEXT,   -- json: la forma exacta de create_task.sh (null en §B)
  valida           INTEGER NOT NULL DEFAULT 1,
  error_validacion TEXT,
  decision         TEXT CHECK (decision IN ('entra','se_queda')),
  decision_nota    TEXT,
  decidida_en      TEXT,
  creada_id        TEXT,   -- uuid de la tarea creada por crear_de_propuestas.sh
  creada_en        TEXT,
  UNIQUE (meeting_id, ref)
);
CREATE TABLE IF NOT EXISTS arquetipos (
  task_id       TEXT PRIMARY KEY,  -- uuid completo
  decision      TEXT NOT NULL,     -- id de arquetipo (A1.2) o 'ninguno'
  decision_nota TEXT,
  decidida_en   TEXT NOT NULL,
  aplicado_en   TEXT
);
```

- [ ] **Step 2: `propuestas_backups.sh`** — read-only, sin Postgres:
```bash
#!/usr/bin/env bash
# Los backups de propuestas de tareas (backups/meeting-tasks/) que la UI de
# revisión puede cargar: uno por reunión, con su gemelo JSON si existe y la
# marca `cargado` (ya tiene lote en la sqlite local `propuestas_reuniones`).
# READ-ONLY. Fuente viz `propuestas_backups`.
#
# Usage: propuestas_backups.sh [--desde YYYY-MM-DD] [--json]
#   --desde  fecha mínima de la REUNIÓN (default 2026-08-21). Un backup con
#            solo .md (sin gemelo) usa la fecha de modificación del archivo.
#   --json   [{meeting_id, meeting_corto, archivo, json, fecha, nombre, n_a,
#             n_b, cargado, cargado_en}]
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"

DESDE="2026-08-21"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --desde) DESDE="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
[[ "$DESDE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "--desde espera YYYY-MM-DD" >&2; exit 2; }

DIR="$REPO_ROOT/backups/meeting-tasks"
DBP="$(db_path propuestas_reuniones)"
lotes="[]"
[[ -f "$DBP" ]] && lotes="$(sqlite_ro "$DBP" -json "SELECT meeting_id, meeting_corto, cargado_en FROM lotes;" | { read -r -d '' x || true; printf '%s' "${x:-[]}"; })"

# Un objeto por .md; el gemelo .json aporta fecha/nombre/conteos; sin gemelo
# la fecha es la del archivo (mtime) y json=0.
items=""
for md in "$DIR"/*.md; do
  base="$(basename "$md" .md)"
  [[ "$base" =~ ^[0-9a-f]{8} ]] || continue          # los lotes históricos (2026-07-…) no son por reunión
  corto="${base:0:8}"
  js="$DIR/$base.json"
  if [[ -f "$js" ]]; then
    item="$(jq -c --arg archivo "$base.md" --arg corto "$corto" '{meeting_id:.meeting, meeting_corto:$corto, archivo:$archivo, json:1, fecha:.fecha, nombre:.nombre, n_a:([.propuestas[]|select(.seccion=="A")]|length), n_b:([.propuestas[]|select(.seccion=="B")]|length)}' "$js")"
  else
    fecha="$(date -r "$md" +%F)"
    item="$(jq -cn --arg archivo "$base.md" --arg corto "$corto" --arg fecha "$fecha" '{meeting_id:null, meeting_corto:$corto, archivo:$archivo, json:0, fecha:$fecha, nombre:null, n_a:0, n_b:0}')"
  fi
  items+="${items:+,}$item"
done
out="$(jq -c --arg desde "$DESDE" --argjson lotes "$lotes" '
  [ .[] | select(.fecha >= $desde)
        | . as $b | ($lotes | map(select(.meeting_corto == $b.meeting_corto)) | first) as $l
        | . + {cargado: (if $l then 1 else 0 end), cargado_en: ($l.cargado_en // null)} ]
  | sort_by(.fecha) | reverse' <<<"[$items]")"
if [[ "$FORMAT" == "json" ]]; then printf '%s\n' "$out"
else jq -r '["corto","fecha","json","cargado","A","B","nombre"], (.[]|[.meeting_corto,.fecha,.json,.cargado,.n_a,.n_b,(.nombre//"—")]) | @tsv' <<<"$out" | column -t -s $'\t'; fi
```

- [ ] **Step 3: Probar** — `bash bash/localdb/propuestas_backups.sh --json | jq .` → 2 objetos (`744e998f`, `92d6cef4`) con `json:1`, `cargado:0`; `--desde 2026-08-01` añade `2ea7176d` (`json:0`) y `dcaec561`. Sin db todavía: no debe fallar.

- [ ] **Step 4: `propuesta_cargar.sh`** [WRITE local]:
```bash
#!/usr/bin/env bash
# [WRITE local] Cargar UN backup de propuestas (su gemelo JSON) en la sqlite
# local `propuestas_reuniones`: una fila en `lotes` + una por propuesta.
# Idempotente por reunión: si el lote ya existe se NIEGA (la UI deja de
# ofrecer el botón). Cada contrato §A se valida con create_task.sh --dry-run
# (nombres, proyecto, arquetipo, slots); el que falla se carga igual con
# valida=0 + el error, para que se vea y se corrija en el JSON.
#
# Usage: propuesta_cargar.sh <meeting-id|prefijo8> [--dry-run] [--json]
#   --json  {ok, meeting_id, n_a, n_b, invalidas:[ref…]}
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"
cd "$REPO_ROOT"

ID=""; DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    -*) echo "Argumento desconocido: $1" >&2; exit 2 ;;
    *) ID="$1"; shift ;;
  esac
done
fail() { if [[ "$FORMAT" == json ]]; then jq -cn --arg e "$1" '{ok:false,error:$e}'; else echo "$1" >&2; fi; exit "${2:-1}"; }
[[ "$ID" =~ ^[0-9a-f]{8} ]] || fail "Falta <meeting-id|prefijo8>" 2
corto="${ID:0:8}"
JS="backups/meeting-tasks/$corto.json"
[[ -f "$JS" ]] || fail "No existe $JS — el backup no tiene gemelo estructurado (lo genera el cerebro desde el .md)"

DBP="$(db_path propuestas_reuniones)"; mkdir -p "$LOCALDB_DIR"
sqlite_rw "$DBP" < bash/localdb/propuestas_schema.sql
meeting="$(jq -r .meeting "$JS")"
if [[ -n "$(sqlite_ro "$DBP" "SELECT 1 FROM lotes WHERE meeting_id=$(sql_str "$meeting") OR meeting_corto=$(sql_str "$corto");")" ]]; then
  fail "El lote $corto ya está cargado — un backup se carga una sola vez"
fi

# Validar cada contrato §A contra Postgres (dry-run: nada se escribe).
declare -A ERR
while IFS=$'\t' read -r ref c; do
  if ! msg="$(printf '%s' "$c" | bash bash/tasks/create_task.sh - --dry-run 2>&1 >/dev/null)"; then
    ERR["$ref"]="$(printf '%s' "$msg" | tail -5 | tr '\n' ' ')"
  fi
done < <(jq -r '.propuestas[]|select(.seccion=="A")|[.ref,(.contrato|tojson)]|@tsv' "$JS")

# Un solo INSERT por propuesta, generado con jq (todo pasa por sql_str, nunca
# concatenado a mano).
sql="BEGIN;
INSERT INTO lotes (meeting_id, meeting_corto, archivo, fecha, nombre, cargado_en, n_a, n_b) VALUES (
  $(sql_str "$meeting"), $(sql_str "$corto"), $(sql_str "$corto.md"),
  $(sql_str "$(jq -r '.fecha//""' "$JS")"), $(sql_str "$(jq -r '.nombre//""' "$JS")"),
  datetime('now'),
  $(jq '[.propuestas[]|select(.seccion=="A")]|length' "$JS"), $(jq '[.propuestas[]|select(.seccion=="B")]|length' "$JS"));
"
while IFS=$'\t' read -r ref seccion titulo proyecto prioridad vence vest asign arq slots evid com preg accs rel dep contrato; do
  err="${ERR[$ref]:-}"; valida=1; [[ -n "$err" ]] && valida=0
  sql+="INSERT INTO propuestas (meeting_id, ref, seccion, titulo, proyecto, prioridad, vence, vence_estimada, asignados, arquetipo, slots, evidencia, comentario, pregunta, accion_sugerida, relacionadas, depende_de, contrato, valida, error_validacion) VALUES (
    $(sql_str "$meeting"), $(sql_str "$ref"), $(sql_str "$seccion"), $(sql_str "$titulo"), $(sql_str "$proyecto"), $(sql_str "$prioridad"), $(sql_str "$vence"), $vest,
    $(sql_str "$asign"), $(sql_str "$arq"), $(sql_str "$slots"), $(sql_str "$evid"), $(sql_str "$com"), $(sql_str "$preg"), $(sql_str "$accs"),
    $(sql_str "$rel"), $(sql_str "$dep"), $( [[ "$contrato" == null ]] && echo NULL || sql_str "$contrato" ), $valida, $( [[ -n "$err" ]] && sql_str "$err" || echo NULL ));
"
done < <(jq -r '.propuestas[] | [
  .ref, .seccion, (.contrato.title // .titulo // ""), (.contrato.project // ""), (.contrato.priority // ""),
  (.contrato.due_date // ""), (if .vence_estimada then 1 else 0 end),
  ((.contrato.assignee // []) | tojson), (.contrato.archetype // ""), ((.contrato.slots // {}) | tojson),
  (.evidencia // ""), (.comentario // ""), (.pregunta // ""), (.accion_sugerida // ""),
  ((.relacionadas // []) | tojson), ((.depende_de // []) | tojson),
  (if .contrato == null then "null" else (.contrato | tojson) end) ] | @tsv' "$JS")
sql+=$([[ "$DRY" == 1 ]] && echo "ROLLBACK;" || echo "COMMIT;")
sqlite_rw "$DBP" "$sql"

inval="$(printf '%s\n' "${!ERR[@]}" 2>/dev/null | grep . | jq -R . | jq -sc .)"
if [[ "$FORMAT" == json ]]; then
  jq -cn --arg m "$meeting" --argjson na "$(jq '[.propuestas[]|select(.seccion=="A")]|length' "$JS")" --argjson nb "$(jq '[.propuestas[]|select(.seccion=="B")]|length' "$JS")" --argjson inv "${inval:-[]}" --argjson dry "$DRY" '{ok:true, meeting_id:$m, n_a:$na, n_b:$nb, invalidas:$inv, dry_run:($dry==1)}'
else
  echo "Lote $corto cargado: $(jq '[.propuestas[]|select(.seccion=="A")]|length' "$JS") §A + $(jq '[.propuestas[]|select(.seccion=="B")]|length' "$JS") §B; inválidas: ${inval:-[]}$([[ "$DRY" == 1 ]] && echo ' (dry-run, rollback)')"
fi
```
⚠️ `@tsv` escapa tabs/newlines como `\t`/`\n` literales dentro de los campos — al insertar, los campos de texto largos (evidencia, contrato) llegan con esas secuencias. Para no corromper el JSON del contrato: en el `read`, tras leer, aplicar `contrato="$(printf '%b' "$contrato")"` **solo** si el campo contiene `\\` (y lo mismo a `evid`/`com`/`preg`/`slots`/`asign`). Alternativa más simple y preferida: en vez de `@tsv`, usar `jq -c '.propuestas[]'` (una línea JSON por propuesta) y extraer cada campo con `jq -r` dentro del bucle — más lento (31 × 15 llamadas a jq) pero sin escapes. Elegir la alternativa simple.

- [ ] **Step 5: Probar la carga** — `bash bash/localdb/propuesta_cargar.sh 744e998f --dry-run --json` → `ok:true, n_a:5, n_b:9`; luego sin `--dry-run`; repetir → `{ok:false, error:"El lote 744e998f ya está cargado…"}` y exit 1. `bash bash/localdb/db_table.sh propuestas_reuniones propuestas --limit 3` muestra filas. `propuestas_backups.sh --json` ahora marca `cargado:1` para 744e998f. Cargar también `92d6cef4`.

- [ ] **Step 6: `propuestas.sh`** — read-only:
```bash
#!/usr/bin/env bash
# Las propuestas de tareas cargadas en la sqlite local `propuestas_reuniones`
# como filas (todas las columnas + lote_nombre/lote_fecha/meeting_corto).
# READ-ONLY. Fuente viz `propuestas`. Los campos json (asignados, slots,
# relacionadas, depende_de, contrato) viajan como STRING json.
#
# Usage: propuestas.sh [--lote M] [--seccion A|B] [--decision entra|se_queda|pendiente] [--json]
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"
LOTE=""; SEC=""; DEC=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lote) LOTE="$2"; shift 2 ;;
    --seccion) SEC="$2"; shift 2 ;;
    --decision) DEC="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$SEC" || "$SEC" =~ ^[AB]$ ]] || { echo "--seccion A|B" >&2; exit 2; }
[[ -z "$DEC" || "$DEC" =~ ^(entra|se_queda|pendiente)$ ]] || { echo "--decision entra|se_queda|pendiente" >&2; exit 2; }
[[ -z "$LOTE" || "$LOTE" =~ ^[0-9a-f-]{8,36}$ ]] || { echo "--lote espera un id de reunión" >&2; exit 2; }
DBP="$(db_path propuestas_reuniones)"
[[ -f "$DBP" ]] || { [[ "$FORMAT" == json ]] && echo "[]" || echo "Sin lotes cargados todavía"; exit 0; }
w="1=1"
[[ -n "$LOTE" ]] && w="$w AND p.meeting_id LIKE $(sql_str "${LOTE:0:8}%")"
[[ -n "$SEC" ]] && w="$w AND p.seccion=$(sql_str "$SEC")"
[[ "$DEC" == pendiente ]] && w="$w AND p.decision IS NULL"
[[ "$DEC" =~ ^(entra|se_queda)$ ]] && w="$w AND p.decision=$(sql_str "$DEC")"
SQL="SELECT p.*, l.nombre AS lote_nombre, l.fecha AS lote_fecha, l.meeting_corto
     FROM propuestas p JOIN lotes l ON l.meeting_id=p.meeting_id
     WHERE $w ORDER BY l.fecha DESC, p.seccion, CAST(substr(p.ref,2) AS INTEGER)"
if [[ "$FORMAT" == json ]]; then out="$(sqlite_ro "$DBP" -json "$SQL;")"; printf '%s\n' "${out:-[]}"
else sqlite_ro "$DBP" -header -column "SELECT p.n, l.meeting_corto lote, p.ref, p.seccion s, substr(p.titulo,1,60) titulo, p.proyecto, p.prioridad, p.vence, coalesce(p.decision,'—') decision, substr(coalesce(p.creada_id,''),1,8) creada FROM propuestas p JOIN lotes l ON l.meeting_id=p.meeting_id WHERE $w ORDER BY l.fecha DESC, p.seccion, CAST(substr(p.ref,2) AS INTEGER);"; fi
```

- [ ] **Step 7: `propuesta_mark.sh`** [WRITE local] — patrón `despacho_mark.sh`:
```bash
#!/usr/bin/env bash
# [WRITE local] La decisión sobre UNA propuesta: entra (se creará en el
# cerebro), se_queda (no), ninguna (borra la decisión). Único write de la
# vista «Propuestas» de la UI de revisión (patrón cruce_mark.sh). Guardrail:
# una propuesta ya creada (creada_id) se congela.
#
# Usage: propuesta_mark.sh <n> --decision entra|se_queda|ninguna [--nota "…"] [--json]
#   --json  {ok, n, decision, decision_nota, decidida_en}
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"
N=""; DEC=""; NOTA=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --decision) DEC="$2"; shift 2 ;;
    --nota) NOTA="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    -*) echo "Argumento desconocido: $1" >&2; exit 2 ;;
    *) N="$1"; shift ;;
  esac
done
fail() { if [[ "$FORMAT" == json ]]; then jq -cn --arg e "$1" '{ok:false,error:$e}'; else echo "$1" >&2; fi; exit "${2:-1}"; }
[[ "$N" =~ ^[0-9]+$ ]] || fail "Falta <n> (propuestas.n)" 2
[[ "$DEC" =~ ^(entra|se_queda|ninguna)$ ]] || fail "--decision entra|se_queda|ninguna" 2
DBP="$(require_db propuestas_reuniones)"
row="$(sqlite_ro "$DBP" "SELECT coalesce(creada_id,'')||'|'||seccion FROM propuestas WHERE n=$N;")"
[[ -n "$row" ]] || fail "No existe la propuesta n=$N"
[[ "${row%%|*}" == "" ]] || fail "La propuesta n=$N ya fue creada en el cerebro (${row%%|*}) — se congela"
if [[ "$DEC" == ninguna ]]; then
  sqlite_rw "$DBP" "UPDATE propuestas SET decision=NULL, decision_nota=NULL, decidida_en=NULL WHERE n=$N;"
else
  sqlite_rw "$DBP" "UPDATE propuestas SET decision=$(sql_str "$DEC"), decision_nota=$( [[ -n "$NOTA" ]] && sql_str "$NOTA" || echo NULL ), decidida_en=datetime('now') WHERE n=$N;"
fi
out="$(sqlite_ro "$DBP" -json "SELECT n, decision, decision_nota, decidida_en FROM propuestas WHERE n=$N;")"
if [[ "$FORMAT" == json ]]; then jq -c '.[0] + {ok:true}' <<<"$out"; else jq -r '.[0]|"n=\(.n) decision=\(.decision//"—") nota=\(.decision_nota//"")"' <<<"$out"; fi
```

- [ ] **Step 8: `arquetipo_mark.sh` + `arquetipo_marcas.sh`**:
```bash
#!/usr/bin/env bash
# [WRITE local] La decisión sobre el arquetipo de UNA tarea sin etiqueta:
# el id elegido (validado contra catalog/sop-archetypes.json) o 'ninguno'.
# Único write de la vista «Sin arquetipo» de la UI de revisión. Se aplica en
# Postgres después, desde la conversación, con bash/tasks/aplicar_arquetipos.sh.
# Guardrail: una marca ya aplicada (aplicado_en) se congela.
#
# Usage: arquetipo_mark.sh <task-id|prefijo8> --arquetipo A_.__|ninguno [--nota "…"] [--json]
#   --json  {ok, task_id, decision, decision_nota, decidida_en}
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"
cd "$REPO_ROOT"
ID=""; ARQ=""; NOTA=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --arquetipo) ARQ="$2"; shift 2 ;;
    --nota) NOTA="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    -*) echo "Argumento desconocido: $1" >&2; exit 2 ;;
    *) ID="$1"; shift ;;
  esac
done
fail() { if [[ "$FORMAT" == json ]]; then jq -cn --arg e "$1" '{ok:false,error:$e}'; else echo "$1" >&2; fi; exit "${2:-1}"; }
[[ "$ID" =~ ^[0-9a-f]{8}(-[0-9a-f-]{27})?$ ]] || fail "Falta <task-id|prefijo8>" 2
[[ -n "$ARQ" ]] || fail "Falta --arquetipo" 2
if [[ "$ARQ" != ninguno ]]; then
  jq -e --arg a "$ARQ" '.archetypes[]|select(.id==$a)' catalog/sop-archetypes.json >/dev/null || fail "Arquetipo desconocido en el catálogo: $ARQ"
fi
# El id completo se resuelve en Postgres solo si llegó un prefijo (la marca
# se guarda por uuid completo, que es lo que pide set_archetype.sh).
if [[ ${#ID} -eq 8 ]]; then
  source bash/lib/common.sh
  full="$(psql_ro -t -A -c "SELECT id FROM tasks WHERE id::text LIKE '$ID%';")"
  [[ "$(grep -c . <<<"$full")" -eq 1 ]] || fail "Prefijo $ID ambiguo o inexistente en tasks"
  ID="$full"
fi
DBP="$(db_path propuestas_reuniones)"; mkdir -p "$LOCALDB_DIR"
sqlite_rw "$DBP" < bash/localdb/propuestas_schema.sql
ap="$(sqlite_ro "$DBP" "SELECT coalesce(aplicado_en,'') FROM arquetipos WHERE task_id=$(sql_str "$ID");")"
[[ -z "$ap" ]] || fail "La marca de $ID ya fue aplicada ($ap) — se congela"
sqlite_rw "$DBP" "INSERT INTO arquetipos (task_id, decision, decision_nota, decidida_en) VALUES ($(sql_str "$ID"), $(sql_str "$ARQ"), $( [[ -n "$NOTA" ]] && sql_str "$NOTA" || echo NULL ), datetime('now'))
  ON CONFLICT(task_id) DO UPDATE SET decision=excluded.decision, decision_nota=excluded.decision_nota, decidida_en=excluded.decidida_en;"
out="$(sqlite_ro "$DBP" -json "SELECT task_id, decision, decision_nota, decidida_en FROM arquetipos WHERE task_id=$(sql_str "$ID");")"
if [[ "$FORMAT" == json ]]; then jq -c '.[0] + {ok:true}' <<<"$out"; else jq -r '.[0]|"\(.task_id[0:8]) → \(.decision)"' <<<"$out"; fi
```
`arquetipo_marcas.sh [--json]`: read-only, `SELECT task_id, decision, decision_nota, decidida_en, aplicado_en FROM arquetipos ORDER BY decidida_en DESC` (`[]` si la db no existe).

- [ ] **Step 9: Probar marcas** — `propuesta_mark.sh 1 --decision entra --nota "prueba" --json` → ok; `--decision ninguna` → limpia. `arquetipo_mark.sh 0b5f4859 --arquetipo A6.8 --json` → ok con uuid completo; `--arquetipo Z9.9` → error catálogo; `arquetipo_marcas.sh --json` → 1 fila. Luego limpiar la marca de prueba: `bash bash/localdb/db_exec.sh propuestas_reuniones "DELETE FROM arquetipos;"`.

- [ ] **Step 10: Commit** — `git add bash/localdb/propuesta* bash/localdb/arquetipo_mark* bash/localdb/arquetipo_marcas.sh && git commit -m "localdb: db propuestas_reuniones — cargar backups de propuestas, marcar entra/se_queda y arquetipo (patrón cruce_mark)"`.

---

### Task 3: `bash/tasks/relacionadas.sh`

**Files:**
- Create: `bash/tasks/relacionadas.sh`

**Interfaces:**
- Consumes: `common.sh` (`psql_ro`, `ASSIGNEES_SQL`), python3 stdlib.
- Produces: la fila `{id, id_full, title, status, project, assignees, archetype, due, score, motivo}`.

- [ ] **Step 1: Escribir el script**
```bash
#!/usr/bin/env bash
# Tareas del cerebro relacionadas con UNA propuesta (o con cualquier título):
# cada fila trae `score` (0-100) y `motivo` declarado. Señales, sumadas:
#   citada (id en --ids)                      100
#   mismo arquetipo + mismo proyecto           40
#   mismo dueño (algún asignado coincide)      20
#   palabras del título (Jaccard, tokens ≥4 letras sin stopwords) ×40
# Abiertas antes que cerradas a igual score. READ-ONLY. Fuente viz
# `tareas_relacionadas` (el bloque «Relacionadas» del panel de la UI).
#
# Usage: relacionadas.sh --titulo T [--project P] [--archetype A] [--assignee "N, M"] [--ids a,b] [--limit N] [--json]
#   --ids     prefijos (8) citados en la propuesta: entran con score 100 aunque sean de otro proyecto
#   --limit   default 12 (0 = todas con score > 0)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
TITULO=""; PROJECT=""; ARQ=""; ASSIGNEE=""; IDS=""; LIMIT=12
while [[ $# -gt 0 ]]; do
  case "$1" in
    --titulo) TITULO="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --archetype) ARQ="$2"; shift 2 ;;
    --assignee) ASSIGNEE="$2"; shift 2 ;;
    --ids) IDS="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$TITULO" ]] || { echo "Falta --titulo" >&2; exit 2; }
[[ "$LIMIT" =~ ^[0-9]+$ ]] || { echo "--limit numérico" >&2; exit 2; }
[[ -z "$IDS" || "$IDS" =~ ^[0-9a-f]{8}(,[0-9a-f]{8})*$ ]] || { echo "--ids: prefijos de 8 separados por coma" >&2; exit 2; }
esc() { printf '%s' "$1" | sed "s/'/''/g"; }
# Candidatas: todas las del proyecto (abiertas y cerradas) + las citadas.
w="false"
[[ -n "$PROJECT" ]] && w="pr.name ILIKE '%$(esc "$PROJECT")%'"
[[ -n "$IDS" ]] && w="$w OR t.id::text ~ '^($(echo "$IDS" | sed 's/,/|/g'))'"
cand="$(psql_ro -t -A -c "SELECT coalesce(json_agg(row_to_json(q)),'[]') FROM (
  SELECT t.id::text AS id_full, t.title, t.status::text AS status, t.priority::text AS priority,
         to_char(t.due_date,'YYYY-MM-DD') AS due, pr.name AS project, $ASSIGNEES_SQL AS assignees,
         t.archetype_id AS archetype
  FROM tasks t LEFT JOIN projects pr ON pr.id=t.project_id WHERE $w) q;")"
python3 - "$TITULO" "$ARQ" "$ASSIGNEE" "$IDS" "$LIMIT" "$FORMAT" <<'PY' <<<"$cand"
import sys, json, re, unicodedata
titulo, arq, assignee, ids, limit, fmt = sys.argv[1:7]
cand = json.load(sys.stdin)
STOP = set("para con como esta este esto ese esa del los las una unos unas por que del sobre desde hasta entre hacer tarea tareas nueva nuevo".split())
def norm(s):
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode().lower()
    return {w[:5] for w in re.findall(r"[a-z0-9]+", s) if len(w) >= 4 and w not in STOP}
def jacc(a, b): return len(a & b) / len(a | b) if a and b else 0.0
T = norm(titulo); cited = set(ids.split(",")) if ids else set()
owners = {o.strip().lower() for o in assignee.split(",") if o.strip()}
out = []
for c in cand:
    score, motivo = 0.0, []
    if c["id_full"][:8] in cited: score += 100; motivo.append("citada")
    if arq and c.get("archetype") == arq: score += 40; motivo.append(f"mismo arquetipo {arq} + proyecto")
    cown = {o.strip().lower() for o in (c.get("assignees") or "").split(",") if o.strip()}
    if owners and cown & owners: score += 20; motivo.append("mismo dueño")
    j = jacc(T, norm(c["title"]))
    if j >= 0.15: score += 40 * j; motivo.append(f"título {j:.2f}")
    if score > 0:
        out.append({**c, "id": c["id_full"][:8], "score": round(score), "motivo": " · ".join(motivo),
                    "_open": c["status"] not in ("completed", "cancelled")})
out.sort(key=lambda r: (-r["score"], not r["_open"], r["title"]))
for r in out: r.pop("_open")
if int(limit): out = out[: int(limit)]
if fmt == "json": print(json.dumps(out, ensure_ascii=False))
else:
    for r in out: print(f'{r["id"]}  {r["score"]:>3}  {r["status"]:<12} {r["title"][:60]:<60}  {r["motivo"]}')
PY
```
- [ ] **Step 2: Probar** — `bash bash/tasks/relacionadas.sh --titulo "Ejecutar la venta pública orgánica de David: 10 días de historias" --project "David Guerrero" --archetype A9.1 --assignee "Santiago Ruiz" --ids 255c66b6 --json | jq '.[0:3]'` → la primera fila es `255c66b6` con score ≥ 100 y motivo que empieza por `citada`. Sin `--ids` la misma aparece por título/dueño con score < 100.
- [ ] **Step 3: Commit** — `git add bash/tasks/relacionadas.sh && git commit -m "tasks: relacionadas.sh — tareas del cerebro relacionadas con una propuesta, con score y motivo declarados"`.

---

### Task 4: `bash/tasks/sin_arquetipo.sh`

**Files:**
- Create: `bash/tasks/sin_arquetipo.sh`

**Interfaces:**
- Consumes: `common.sh`, `catalog/sop-archetypes.json`, python3.
- Produces: la fila `{id, id_full, title, status, priority, due, project, assignees, sugerido, sugerido_nombre, sugerido_sop, score, motivo, alternativas}` (`alternativas` = string JSON).

- [ ] **Step 1: Escribir el script**
```bash
#!/usr/bin/env bash
# Tareas sin arquetipo (tasks.archetype_id IS NULL) con el ARQUETIPO PROPUESTO
# y sus alternativas — el primer peldaño del matcher del catálogo (rule →
# embedding → LLM). Dos señales sumadas y declaradas en `motivo`:
#   léxica   tokens del título (prefijo 5, sin stopwords) contra verbo (×2),
#            nombre del arquetipo y nombre de su SOP, del catálogo JSON
#   vecinos  las tareas YA etiquetadas cuyo título se parece (Jaccard ≥ 0.2):
#            su arquetipo vota, ponderado por la similitud
# score 0-100; bajo 25 no se propone nada (sugerido=null) antes que inventar.
# READ-ONLY. Fuente viz `tareas_sin_arquetipo`.
#
# Usage: sin_arquetipo.sh [--project P] [--open] [--json]
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
PROJECT=""; OPEN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --open) OPEN=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
esc() { printf '%s' "$1" | sed "s/'/''/g"; }
w="t.archetype_id IS NULL"
[[ -n "$PROJECT" ]] && w="$w AND pr.name ILIKE '%$(esc "$PROJECT")%'"
[[ "$OPEN" == 1 ]] && w="$w AND $OPEN_PRED"
sin="$(psql_ro -t -A -c "SELECT coalesce(json_agg(row_to_json(q)),'[]') FROM (
  SELECT t.id::text AS id_full, t.title, t.status::text AS status, t.priority::text AS priority,
         to_char(t.due_date,'YYYY-MM-DD') AS due, pr.name AS project, $ASSIGNEES_SQL AS assignees
  FROM tasks t LEFT JOIN projects pr ON pr.id=t.project_id WHERE $w
  ORDER BY t.due_date NULLS LAST) q;")"
con="$(psql_ro -t -A -c "SELECT coalesce(json_agg(row_to_json(q)),'[]') FROM (
  SELECT t.title, t.archetype_id AS archetype FROM tasks t WHERE t.archetype_id IS NOT NULL) q;")"
python3 - "$REPO_ROOT/catalog/sop-archetypes.json" "$FORMAT" <<'PY' <<<"$(jq -cn --argjson sin "$sin" --argjson con "$con" '{sin:$sin,con:$con}')"
import sys, json, re, unicodedata
from collections import defaultdict
cat = json.load(open(sys.argv[1])); fmt = sys.argv[2]
data = json.load(sys.stdin); sin, con = data["sin"], data["con"]
sops = {s["code"]: s["name"] for s in cat["sops"]}
STOP = set("para con como esta este esto ese esa del los las una unos unas por que sobre desde hasta entre hacer crear tarea tareas".split())
def norm(s):
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode().lower()
    return {w[:5] for w in re.findall(r"[a-z0-9]+", s) if len(w) >= 4 and w not in STOP}
def jacc(a, b): return len(a & b) / len(a | b) if a and b else 0.0
arcs = [{"id": a["id"], "nombre": a["name"], "sop": a["sop"], "sop_nombre": sops.get(a["sop"], ""),
         "verb": norm(a.get("verb", "")), "name": norm(a["name"]), "sopn": norm(sops.get(a["sop"], ""))} for a in cat["archetypes"]]
tagged = [(norm(c["title"]), c["archetype"]) for c in con]
out = []
for t in sin:
    T = norm(t["title"]); scores = defaultdict(float); why = defaultdict(list)
    for a in arcs:
        lex = 2 * len(T & a["verb"]) + len(T & a["name"]) + 0.5 * len(T & a["sopn"])
        if lex: scores[a["id"]] += min(60, lex * 15); why[a["id"]].append(f"léxica {lex:g}")
    votes = defaultdict(float)
    for nt, arc in tagged:
        j = jacc(T, nt)
        if j >= 0.2: votes[arc] += j
    for arc, v in votes.items():
        scores[arc] += min(60, v * 60); why[arc].append(f"vecinos {v:.2f}")
    alts = sorted(scores.items(), key=lambda kv: -kv[1])[:3]
    byid = {a["id"]: a for a in arcs}
    alts = [{"id": k, "nombre": byid[k]["nombre"], "sop": byid[k]["sop"], "score": round(min(100, v)), "motivo": " · ".join(why[k])} for k, v in alts if k in byid]
    top = alts[0] if alts and alts[0]["score"] >= 25 else None
    out.append({**t, "id": t["id_full"][:8], "sugerido": top and top["id"], "sugerido_nombre": top and top["nombre"],
                "sugerido_sop": top and top["sop"], "score": top["score"] if top else 0,
                "motivo": top["motivo"] if top else "sin propuesta (score < 25)", "alternativas": json.dumps(alts, ensure_ascii=False)})
if fmt == "json": print(json.dumps(out, ensure_ascii=False))
else:
    for r in out: print(f'{r["id"]}  {r["status"]:<11} {(r["sugerido"] or "—"):<6} {r["score"]:>3}  {r["title"][:58]:<58}  {r["motivo"]}')
PY
```
- [ ] **Step 2: Probar** — `bash bash/tasks/sin_arquetipo.sh --open` → 22 filas; `--json | jq '.[0]'` trae `alternativas` como string parseable (`jq '.[0].alternativas|fromjson'`). Revisar a ojo 5 sugerencias: p.ej. «Estructurar sistema de gamificación…» debe proponer algo de S11/S12 o quedar sin propuesta — el matcher es heurístico y se declara así; lo importante es que el score y el motivo sean legibles.
- [ ] **Step 3: Commit** — `git add bash/tasks/sin_arquetipo.sh && git commit -m "tasks: sin_arquetipo.sh — tareas sin arquetipo con el arquetipo propuesto (léxico + vecinos), score y motivo"`.

---

### Task 5: `viz/lib/similitud.js` + fuentes en `datasources.js`

**Files:**
- Create: `viz/lib/similitud.js`, `viz/test/similitud.test.js`
- Modify: `viz/lib/datasources.js` (antes del cierre de `SOURCES`)

**Interfaces:**
- Produces: `tokens(text) → Set<string>`, `jaccard(a: Set, b: Set) → number`; las 5 fuentes.

- [ ] **Step 1: Test que falla** — `viz/test/similitud.test.js`:
```js
const { test } = require("node:test");
const assert = require("node:assert");
const { tokens, jaccard } = require("../lib/similitud");

test("tokens: normaliza acentos, quita cortas y stopwords, recorta a prefijo 5", () => {
  const t = tokens("Diseñar las diapositivas de la clase enfocadas en la oferta");
  assert.deepStrictEqual([...t].sort(), ["clase", "diapo", "disen", "enfoc", "ofert"]);
});
test("jaccard: 0 con vacíos, 1 idénticos, proporción si comparten", () => {
  assert.strictEqual(jaccard(new Set(), new Set(["a"])), 0);
  assert.strictEqual(jaccard(tokens("Escribir el VSL"), tokens("Escribir el VSL")), 1);
  const j = jaccard(tokens("Escribir los mensajes de calentamiento"), tokens("Programar los mensajes de calentamiento"));
  assert.ok(j > 0.4 && j < 1, `j=${j}`);
});
```
- [ ] **Step 2: Correr** — `node --test viz/test/similitud.test.js` → FAIL (módulo no existe).
- [ ] **Step 3: Implementar** — `viz/lib/similitud.js`:
```js
// similitud — tokenizador + Jaccard compartidos por la UI de revisión (las
// «hermanas» de un lote se calculan aquí, sin ir a Postgres). Misma regla que
// bash/tasks/relacionadas.sh y sin_arquetipo.sh: minúsculas sin acentos,
// palabras de ≥4 letras que no sean stopwords, recortadas a prefijo 5 (un
// stemming pobre pero honesto: «mensajes»/«mensaje», «programar»/«programa»).
const STOP = new Set("para con como esta este esto ese esa del los las una unos unas por que sobre desde hasta entre hacer crear tarea tareas".split(" "));

function tokens(text) {
  const s = String(text || "").normalize("NFKD").replace(/[̀-ͯ]/g, "").toLowerCase();
  const out = new Set();
  for (const w of s.match(/[a-z0-9]+/g) || []) if (w.length >= 4 && !STOP.has(w)) out.add(w.slice(0, 5));
  return out;
}
function jaccard(a, b) {
  if (!a.size || !b.size) return 0;
  let inter = 0;
  for (const x of a) if (b.has(x)) inter++;
  return inter / (a.size + b.size - inter);
}
module.exports = { tokens, jaccard };
```
- [ ] **Step 4: Correr** — `node --test viz/test/similitud.test.js` → PASS.
- [ ] **Step 5: Fuentes** — añadir en `viz/lib/datasources.js`, dentro de `SOURCES`, tras `intercepciones_drift`:
```js
  // --- Revisión de propuestas (UI de rol technology) -----------------------
  // Los backups de propuestas de tareas (backups/meeting-tasks/) con su gemelo
  // JSON y la marca «cargado» en la sqlite local; sin cache (la barra debe
  // reflejar la carga recién hecha).
  propuestas_backups: {
    label: "Propuestas — backups cargables",
    script: "bash/localdb/propuestas_backups.sh",
    emits: "rows",
    args: { desde: "--desde" },
  },
  propuestas: {
    label: "Propuestas de tareas (sqlite local)",
    script: "bash/localdb/propuestas.sh",
    emits: "rows",
    args: { lote: "--lote", seccion: "--seccion", decision: "--decision" },
  },
  arquetipo_marcas: {
    label: "Marcas de arquetipo (sqlite local)",
    script: "bash/localdb/arquetipo_marcas.sh",
    emits: "rows",
    args: {},
  },
  // Postgres, read-only: relacionadas de una propuesta y la cola sin arquetipo.
  tareas_relacionadas: {
    label: "Tareas relacionadas (score + motivo)",
    script: "bash/tasks/relacionadas.sh",
    emits: "rows",
    args: { titulo: "--titulo", project: "--project", archetype: "--archetype", assignee: "--assignee", ids: "--ids", limit: "--limit" },
  },
  tareas_sin_arquetipo: {
    label: "Tareas sin arquetipo + propuesto",
    script: "bash/tasks/sin_arquetipo.sh",
    emits: "rows",
    args: { project: "--project", open: { flag: "--open", bool: true } },
  },
```
- [ ] **Step 6: Verificar** — `node -e "const {fetchSource}=require('./viz/lib/datasources');console.log(fetchSource('propuestas_backups').rows.length)"` → 2.
- [ ] **Step 7: Commit** — `git add viz/lib/similitud.js viz/test/similitud.test.js viz/lib/datasources.js && git commit -m "viz(revision): similitud.js (tokens+jaccard, con test) y las 5 fuentes de la UI de revisión"`.

---

### Task 6: La página y sus cuatro bloques

**Files:**
- Create: `viz/blocks/propuestas-table.js`, `viz/blocks/propuesta-detail.js`, `viz/blocks/arquetipos-table.js`, `viz/blocks/arquetipo-detail.js`, `viz/pages/revision-propuestas.js`, `viz/specs/roles/technology/revision-propuestas.json`

**Interfaces:**
- Consumes: `patterns/master-detail` (`render(ui, {master:{block,source}, detail:{block}})`; contrato del master: `signals(p)`, `regetQS`, `controls(p, reget)`, `prepare?`, `table(rows, wire)`, `counter(n)`, `headerExtra`, `manifest:{slot:'master', consumes:'rows', indicator, overridable}`; contrato del detail: `manifest:{slot:'detail', frag, width, selSignal, writes?}`, `frags.<frag>(ctx)` con `ctx.params.get("id")`, `acts` con `ctx.run(script, args)`), `blocks/task-detail` (`renderTaskDetail(id)`), `lib/similitud`, `lib/kit` (`escape, selectCtl, checkCtl`), `lib/store`, `lib/datasources.fetchSource`.
- Produces: page id `revision-propuestas`; block ids `propuestas-table`, `propuesta-detail`, `arquetipos-table`, `arquetipo-detail`.

- [ ] **Step 1: `propuestas-table.js`** (master, vista 1). Señales `{vista:'propuestas', pLote, pProy, pSec, pDec}`; `regetQS` = `'vista=propuestas&lote='+$pLote+'&proyecto='+encodeURIComponent($pProy)+'&seccion='+$pSec+'&decision='+$pDec`; `controls(p, reget)` = **el conmutador de vista** (dos `button.btn btn-xs` que hacen `@get('/ui/'+<ui.id>+'?vista=propuestas')` / `?vista=arquetipos` — el id de la UI no llega a `controls`; usar `$vista='arquetipos'; ` + un reget propio: el patrón pasa `reget` construido desde `regetQS`, así que basta `data-on:click="$vista='arquetipos'; ${reget}"` si `regetQS` empieza por `'vista='+$vista+…`. **Hacerlo así**: `regetQS = "'vista='+$vista+'&lote='+…"` y `signals(p).vista = p.vista || 'propuestas'`) + **la barra de backups**: `fetchSource("propuestas_backups").rows` como tarjetas (`div.card`): corto · fecha · nombre · `n_a`/`n_b`; si `cargado` → `badge badge-pos` «cargado {cargado_en}»; si `!json` → `badge badge-neutral` «sin gemelo JSON»; si `json && !cargado` → `<button class="btn btn-primary btn-xs" data-on:click="@post('/c/revision-propuestas/act/cargar?ui='+encodeURIComponent(location.pathname.split('/').pop())+'&meeting=<corto>')" data-indicator:loadingprop>Cargar</button>` — ⚠️ mejor: `controls` recibe `p`; el patrón no da `ui.id`, así que el page envuelve el bloque: `{...propuestasTable, controls:(p,reget)=>propuestasTable.controls(p,reget,ui.id)}` y el tercer argumento se usa en el `@post`. Luego los filtros: `selectCtl("pLote", …, [["","Lote: todos"], ...lotes desde las filas], reget, "loadingprop")`, `pProy` (proyectos desde filas), `pSec` (`A`/`B`), `pDec` (`pendiente`/`entra`/`se_queda`). `prepare(rows,p)`: filtra en JS por `pProy` (el resto ya lo filtra el script). `table(rows, wire)`: `table.tbl` con columnas ref · sección (badge) · título · proyecto · prio (`priorityDot`) · vence (+ `est.` en `text-[10px]` si `vence_estimada`) · dueños (`JSON.parse(asignados).join(", ")`) · arquetipo (`code`) · **decisión**: `<span id="dec-${n}">${decisionBadge(r)}</span>` con `decisionBadge` exportada: `entra`→`badge-pos`, `se_queda`→`badge-neutral`, sin decisión→`badge-cau` «pendiente», `creada_id`→`badge-brand` «✓ creada {8}`; `valida==0`→ `badge-neg` «inválida» al lado. `counter(n)` = `${n} propuesta(s)`. `manifest:{slot:'master', consumes:'rows', indicator:'loadingprop', overridable:['vista','lote','proyecto','seccion','decision']}`. `wire.rowAttrs(r)` va en `<tr>`; el id de fila = `r.n` (el patrón usa `r.id` → **añadir en `prepare` `id: String(r.n)`** a cada fila).
- [ ] **Step 2: `propuesta-detail.js`** (detail, vista 1). `manifest:{slot:'detail', frag:'panel', width:'34rem', selSignal:'selectedProp', writes:[MARK]}` con `MARK="bash/localdb/propuesta_mark.sh"`. `frags.panel(ctx)`: `n = ctx.params.get("id")`; vacío → `panelShell('<p>Selecciona una propuesta…</p>')` con `id="task-detail"` (⚠️ el patrón exige que el fragmento interno tenga **un id fijo que el frag reemplaza**; usar `id="prop-detail"` en todo este bloque — el patrón no lo fija, solo morphs por id). Con `n`: `fetchSource("propuestas").rows.find(r=>String(r.n)===n)`; render: cabecera (cerrar `data-on:click="$detailOpen=false; $selectedProp=''"`, título, badges sección/prioridad/decisión `id="decp-${n}"`), `dl` (proyecto, vence + est., dueños, arquetipo + nombre — buscar en el catálogo vía `require("../../catalog/sop-archetypes.json")`, lote), **slots** como `dl` pequeño, **evidencia** en `blockquote` (`var(--text-2)`), **comentario**, §B: **pregunta** en `alert alert-cau` + `accion_sugerida`; `valida==0` → `alert alert-neg` con `error_validacion`; **decisión**: `<input data-bind="_nota_${n}" class="input" placeholder="nota (opcional)">` sembrada en `data-signals` + botones `btn btn-primary btn-xs` «Entra» → `@post('/c/propuesta-detail/act/mark?n=${n}&d=entra&nota='+encodeURIComponent($_nota_${n}))`, `btn btn-xs` «Se queda» (`d=se_queda`), y si hay decisión un enlace «quitar» (`d=ninguna`); todos con `data-indicator:loading`; si `creada_id` → sin botones, badge brand + id copiable (patrón `idCopiable` de cruce.js). **Relacionadas**: (1) *En este lote*: `depende_de` resueltas a hermanas por `ref` + hermanas con `jaccard(tokens(titulo), tokens(h.titulo)) ≥ 0.25` o mismo `arquetipo`+`proyecto` (excluyéndose a sí misma), lista `ref · título · decisión`; (2) *En el cerebro*: `fetchSource("tareas_relacionadas", {titulo, project: proyecto, archetype: arquetipo, assignee: asignados.join(","), ids: relacionadas.join(","), limit: "10"})` en try/catch → filas `id (copiable) · badge estado · título · motivo · score`; error → `alert alert-neg`. `acts.mark(ctx)`: `r = ctx.run(MARK, [n, "--decision", d, ...(nota?["--nota",nota]:[])])`; devuelve **dos patches**: el panel re-renderizado (con el error en `alert-neg` si `r.ok===false`) y `<span id="dec-${n}">…</span>` con el badge nuevo (importando `decisionBadge` de `propuestas-table`).
- [ ] **Step 3: `arquetipos-table.js`** (master, vista 2). Señales `{vista:'arquetipos', aProy, aOpen}`; `regetQS = "'vista='+$vista+'&project='+encodeURIComponent($aProy)+'&open='+$aOpen"`; `controls`: conmutador de vista (mismo markup que en vista 1, con `$vista='propuestas'; reget`), `selectCtl("aProy", …, proyectos de `fetchSource("projects")`, reget, "loadingarq")`, `checkCtl("aOpen","Solo abiertas", reget, {indicator:"loadingarq", checked: p.open!=="false"})`. `prepare(rows,p)`: cruza con `fetchSource("arquetipo_marcas").rows` (map por `task_id`) → añade `marca` a cada fila; `id = r.id`. `table`: id corto (`code`) · título · proyecto · estado (badge) · dueños · **propuesto**: `code` id + nombre + `badge` con score (≥60 `badge-pos`, 25-59 `badge-cau`, null `badge-neutral` «sin propuesta») · **decisión** `<span id="arq-${id}">${marcaBadge(r.marca)}</span>` (`marcaBadge` exportada: sin marca→`—`; `ninguno`→`badge-neutral`; id→`badge-pos` con el id; `aplicado_en`→`badge-brand` «✓ aplicada»). `manifest:{slot:'master', consumes:'rows', indicator:'loadingarq', overridable:['vista','project','open']}`.
- [ ] **Step 4: `arquetipo-detail.js`** (detail, vista 2). `manifest:{slot:'detail', frag:'panel', width:'30rem', selSignal:'selectedArq', writes:[AMARK]}` con `AMARK="bash/localdb/arquetipo_mark.sh"`. `frags.panel(ctx)`: `id8 = ctx.params.get("id")`; vacío → estado vacío; con id: **arriba** el bloque «Arquetipo propuesto»: fila de `fetchSource("tareas_sin_arquetipo").rows` (sin filtro, buscar por `id`) → sugerido (id, nombre, SOP, score, motivo) + alternativas (`JSON.parse(alternativas)`) como lista con botón «Aceptar» por alternativa (`@post('/c/arquetipo-detail/act/mark?id=${id8}&a=${alt.id}')`), un `select.select` `data-bind="_arq_${id8}"` con todo el catálogo (`A1.1 — nombre`, agrupado por SOP con `<optgroup>`) sembrado con el sugerido + botón «Elegir este» (`@post('…?id=${id8}&a='+$_arq_${id8})`), botón «Ninguno» (`a=ninguno`), y la marca actual si existe (de `arquetipo_marcas`); si `aplicado_en` → sin botones. ⚠️ Regla del catálogo en un `p.text-xs`: «etiquetar mueve el puntero; no reescribe el contrato IO». **Debajo**, el detalle de la tarea reutilizando `renderTaskDetail(id8)` de `blocks/task-detail` — pero ese devuelve su propio `panelShell` con `id="task-detail"` y botón cerrar que limpia `$selectedTask`; extraer solo el interior: `renderTaskDetail(id8).replace(/^<div id="task-detail"[^>]*>/, "").replace(/<\/div>$/, "")` y reemplazar `$selectedTask=''` por `$selectedArq=''`. Envolver todo en `<div id="arq-detail" class="w-[30rem] h-full overflow-y-auto">`. `acts.mark(ctx)`: `ctx.run(AMARK, [id8, "--arquetipo", a])` → dos patches: el panel y `<span id="arq-${id8}">…</span>`.
- [ ] **Step 5: `pages/revision-propuestas.js`**:
```js
// revision-propuestas page — la mesa de revisión del rol technology sobre dos
// colas de PROPUESTAS: (1) las tareas que las reuniones proponen (los backups
// de meeting-to-tasks, cargados a la sqlite local `propuestas_reuniones`) y
// (2) las tareas del cerebro sin arquetipo, con el arquetipo propuesto.
// Dos instancias del patrón master-detail conmutadas por `vista`. La UI solo
// MARCA (sqlite local, patrón Merge del cruce); la ejecución en Postgres es de
// crear_de_propuestas.sh / aplicar_arquetipos.sh, desde la conversación.
// Spec: docs/superpowers/specs/2026-08-24-revision-propuestas-design.md
const pattern = require("../patterns/master-detail");
const propuestasTable = require("../blocks/propuestas-table");
const propuestaDetail = require("../blocks/propuesta-detail");
const arquetiposTable = require("../blocks/arquetipos-table");
const arquetipoDetail = require("../blocks/arquetipo-detail");
const { escape } = require("../lib/kit");
const store = require("../lib/store");

const CARGAR = "bash/localdb/propuesta_cargar.sh";

function render(ui, aviso) {
  const vista = (ui.params && ui.params.vista) === "arquetipos" ? "arquetipos" : "propuestas";
  const slots = vista === "arquetipos"
    ? { master: { block: arquetiposTable, source: "tareas_sin_arquetipo", params: { open: "1" } }, detail: { block: arquetipoDetail } }
    : { master: { block: { ...propuestasTable, controls: (p, reget) => propuestasTable.controls(p, reget, ui.id, aviso) }, source: "propuestas" }, detail: { block: propuestaDetail } };
  return pattern.render(ui, slots);
}

const acts = {
  // Cargar un backup a la sqlite local; re-renderiza la página entera (#pane)
  // para que la barra deje de ofrecer el botón y la tabla traiga el lote.
  cargar: (ctx) => {
    const ui = store.get(ctx.params.get("ui") || "");
    if (!ui) return `<section id="pane" class="p-6 text-sm text-red-600">UI desconocida.</section>`;
    const r = ctx.run(CARGAR, [ctx.params.get("meeting") || ""]);
    return render({ ...ui, params: { ...(ui.params || {}), vista: "propuestas" } }, r && r.ok === false ? r.error : null);
  },
};

module.exports = {
  id: "revision-propuestas",
  render: (ui) => render(ui, null),
  acts,
  manifest: {
    consumes: "rows",
    overridable: [...new Set([...propuestasTable.manifest.overridable, ...arquetiposTable.manifest.overridable])],
    writes: [CARGAR],
  },
};
```
`propuestasTable.controls(p, reget, uiId, aviso)` pinta `aviso` (si viene) como `alert alert-neg` encima de la barra.
- [ ] **Step 6: Spec de rol** — `viz/specs/roles/technology/revision-propuestas.json`:
```json
{
  "id": "revision-propuestas",
  "name": "Revisión de propuestas",
  "component": "revision-propuestas",
  "source": "propuestas",
  "params": { "vista": "propuestas" },
  "scope": "role",
  "role": "technology",
  "created_at": "2026-08-24T00:00:00.000Z"
}
```
- [ ] **Step 7: Arrancar y probar** — `npm run viz:restart`; `curl -s localhost:4317/u/revision-propuestas | grep -c "Cargar"` → ≥1 antes de cargar (o 0 si los dos lotes ya están cargados de la Task 2 — en ese caso, `bash bash/localdb/db_exec.sh propuestas_reuniones "DELETE FROM propuestas WHERE meeting_id LIKE '744e998f%'; DELETE FROM lotes WHERE meeting_corto='744e998f';"` para probar el botón). `curl -s "localhost:4317/u/revision-propuestas?vista=arquetipos" | grep -c "Sin arquetipo\|sin propuesta"` → ≥1. `curl -s "localhost:4317/c/propuesta-detail/frag/panel?id=1"` → contiene «Relacionadas». `curl -s -X POST "localhost:4317/c/propuesta-detail/act/mark?n=1&d=entra"` → contiene `id="dec-1"`. `curl -s -X POST "localhost:4317/c/arquetipo-detail/act/mark?id=0b5f4859&a=A6.8"` → `id="arq-0b5f4859"`; luego `bash bash/localdb/arquetipo_mark.sh 0b5f4859 --arquetipo ninguno` o `db_exec.sh … "DELETE FROM arquetipos"` para limpiar. Revisar en el navegador ambos modos (claro/oscuro) y que el panel se abra al clic.
- [ ] **Step 8: Commit** — `git add viz/blocks/propuestas-table.js viz/blocks/propuesta-detail.js viz/blocks/arquetipos-table.js viz/blocks/arquetipo-detail.js viz/pages/revision-propuestas.js viz/specs/roles/technology/revision-propuestas.json && git commit -m "viz(revision): UI «Revisión de propuestas» (rol technology) — propuestas de reuniones con relacionadas + tareas sin arquetipo con propuesto; solo marca local"`.

---

### Task 7: Los ejecutores `[WRITE pg]` (solo `--dry-run` en este plan)

**Files:**
- Create: `bash/tasks/crear_de_propuestas.sh`, `bash/tasks/aplicar_arquetipos.sh`

**Interfaces:**
- Consumes: sqlite `propuestas_reuniones`, `create_task.sh` (imprime una tabla psql cuya fila de datos empieza por el uuid: capturar con `grep -oE '^ *[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | tr -d ' ' | head -1`), `set_archetype.sh <id> <A> --method human`.

- [ ] **Step 1: `crear_de_propuestas.sh`**:
```bash
#!/usr/bin/env bash
# WRITE (Postgres + sqlite local): ejecutar lo que la UI de revisión marcó
# como «entra» — el gemelo de merge_from_cruce.sh para las propuestas de
# reuniones. Por cada fila §A con decision='entra', valida=1 y sin creada_id:
# create_task.sh con el contrato GUARDADO en la sqlite (una txn por tarea),
# y sella creada_id/creada_en en la fila. Las §B nunca se crean (se listan
# como pendientes de conversación); las «se_queda» no se tocan.
#
# Usage: crear_de_propuestas.sh [--lote M] [--n LIST] [--dry-run] [--json]
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/sqlite.sh"
LOTE=""; NL=""; DRY=0; JSON=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lote) LOTE="$2"; shift 2 ;;
    --n) NL="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --json) JSON=1; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$NL" || "$NL" =~ ^[0-9]+(,[0-9]+)*$ ]] || { echo "--n: enteros separados por coma" >&2; exit 2; }
DBP="$(require_db propuestas_reuniones)"
w="seccion='A' AND decision='entra' AND creada_id IS NULL"
[[ -n "$LOTE" ]] && w="$w AND meeting_id LIKE $(sql_str "${LOTE:0:8}%")"
[[ -n "$NL" ]] && w="$w AND n IN ($NL)"
creadas=0; saltadas=0
while IFS= read -r row; do
  n="$(jq -r .n <<<"$row")"; ref="$(jq -r .ref <<<"$row")"; valida="$(jq -r .valida <<<"$row")"
  if [[ "$valida" != 1 ]]; then echo "n=$n $ref: contrato inválido — saltada ($(jq -r .error_validacion <<<"$row"))" >&2; saltadas=$((saltadas+1)); continue; fi
  out="$(jq -r .contrato <<<"$row" | bash bash/tasks/create_task.sh - $([[ "$DRY" == 1 ]] && echo --dry-run) 2>&1)" || { echo "n=$n $ref: create_task.sh falló: $out" >&2; saltadas=$((saltadas+1)); continue; }
  id="$(grep -oE '^ *[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' <<<"$out" | tr -d ' ' | head -1)"
  if [[ "$DRY" == 0 ]]; then
    [[ -n "$id" ]] || { echo "n=$n $ref: no pude leer el id creado de la salida" >&2; exit 1; }
    sqlite_rw "$DBP" "UPDATE propuestas SET creada_id=$(sql_str "$id"), creada_en=datetime('now') WHERE n=$n;"
  fi
  creadas=$((creadas+1))
  [[ "$JSON" == 1 ]] && jq -cn --argjson n "$n" --arg ref "$ref" --arg id "${id:-}" --argjson dry "$DRY" '{n:$n, ref:$ref, task_id:$id, dry_run:($dry==1)}' || echo "n=$n $ref → ${id:-(dry-run)}"
done < <(sqlite_ro "$DBP" -json "SELECT n, ref, valida, error_validacion, contrato FROM propuestas WHERE $w ORDER BY n;" | jq -c '.[]?')
pendB="$(sqlite_ro "$DBP" "SELECT count(*) FROM propuestas WHERE seccion='B' AND decision='entra';")"
[[ "$JSON" == 1 ]] && jq -cn --argjson c "$creadas" --argjson s "$saltadas" --argjson b "$pendB" --argjson dry "$DRY" '{ok:true, creadas:$c, saltadas:$s, seccion_b_pendientes:$b, dry_run:($dry==1)}' || echo "creadas=$creadas saltadas=$saltadas · §B marcadas «entra» pendientes de conversación: $pendB$([[ "$DRY" == 1 ]] && echo ' (dry-run)')"
```
- [ ] **Step 2: `aplicar_arquetipos.sh`** — misma forma: filas de `arquetipos` con `decision<>'ninguno' AND aplicado_en IS NULL`; por cada una `bash bash/tasks/set_archetype.sh "$task_id" "$decision" --method human $([[ $DRY == 1 ]] && echo --dry-run)`; sin dry-run sella `aplicado_en=datetime('now')`. Cabecera con la advertencia: «re-etiquetar mueve el puntero, no reescribe el contrato IO».
- [ ] **Step 3: Probar en seco** — marcar una propuesta (`propuesta_mark.sh <n de A1 de 744e998f> --decision entra`), correr `bash bash/tasks/crear_de_propuestas.sh --dry-run` → 1 línea `→ (dry-run)`, sqlite sin `creada_id`; `bash bash/tasks/aplicar_arquetipos.sh --dry-run` con una marca → 1 línea. **No correr sin `--dry-run`.** Deshacer la marca de prueba (`--decision ninguna`).
- [ ] **Step 4: Commit** — `git add bash/tasks/crear_de_propuestas.sh bash/tasks/aplicar_arquetipos.sh && git commit -m "tasks: crear_de_propuestas.sh + aplicar_arquetipos.sh — los ejecutores de lo que marca la UI de revisión (gemelos de merge_from_cruce)"`.

---

### Task 8: Skill + documentación

**Files:**
- Modify: `.claude/skills/meeting-to-tasks/SKILL.md` (sección «### 4. Propose for review»), `CLAUDE.md` (tabla Tasks domain, tabla Localdb domain, lista de componentes del viz), `viz/README.md` (catálogo de componentes)

- [ ] **Step 1: Skill** — en «### 4. Propose for review», tras el párrafo del `.md`, añadir:
```markdown
**And its structured twin.** Alongside the `.md`, write
`backups/meeting-tasks/<meeting-id8>.json` — the same proposal as data, which
is what the viz «Revisión de propuestas» UI loads (`propuesta_cargar.sh`):
`{meeting, meeting_corto, fecha, nombre, md, propuestas[]}` where each §A entry
is `{ref, seccion:"A", contrato:{…exact create_task.sh shape…}, vence_estimada,
evidencia, comentario, relacionadas:[id8…], depende_de:[ref…]}` and each §B
entry is `{ref, seccion:"B", contrato:null, titulo, pregunta, accion_sugerida,
relacionadas, depende_de}`. The `.md` is for the human; the `.json` is the
contract — validate every §A `contrato` with `create_task.sh - --dry-run`
before saving. The two files must agree (same refs, same count).
```
- [ ] **Step 2: CLAUDE.md** — filas nuevas: en **Tasks domain**: `relacionadas.sh`, `sin_arquetipo.sh`, `crear_de_propuestas.sh` **[WRITE]**, `aplicar_arquetipos.sh` **[WRITE]`; en **Localdb domain**: `propuestas_backups.sh`, `propuesta_cargar.sh` **[WRITE]**, `propuestas.sh`, `propuesta_mark.sh` **[WRITE]**, `arquetipo_mark.sh` **[WRITE]**, `arquetipo_marcas.sh` — con una línea de intención cada una (cuándo usarla, qué guardrail sostiene) y el párrafo de la db: «`propuestas_reuniones` — las dos colas de curaduría de la UI de rol technology «Revisión de propuestas»; la UI marca, `crear_de_propuestas.sh`/`aplicar_arquetipos.sh` ejecutan; un backup se carga una sola vez; el gemelo JSON lo escribe `meeting-to-tasks`». En la lista de componentes del viz añadir `revision-propuestas`. Viz sources: `propuestas_backups`, `propuestas`, `arquetipo_marcas`, `tareas_relacionadas`, `tareas_sin_arquetipo`.
- [ ] **Step 3: viz/README.md** — una entrada en el catálogo de componentes con la misma frase.
- [ ] **Step 4: Commit** — `git add .claude/skills/meeting-to-tasks/SKILL.md CLAUDE.md viz/README.md && git commit -m "docs: UI Revisión de propuestas — skill escribe el gemelo JSON; scripts y fuentes en el manual"`.

---

## Self-review

- **Cobertura del spec:** §1 JSON gemelo → T1 + T8; §2 db → T2; §3 scripts locales → T2, Postgres read-only → T3/T4, ejecutores → T7; §4 UI (dos vistas, barra de backups, botones, relacionadas en dos capas, reutilización de `renderTaskDetail`) → T5/T6; §5 flujo → T6/T7; §6 errores (sin gemelo, inválida, Postgres caído, guardrail) → T2 (`valida`/negativa), T6 (alerts); §7 pruebas → cada task; §8 fuera de alcance respetado.
- **Placeholders:** ninguno; el Step 2 de T7 describe `aplicar_arquetipos.sh` por referencia a T7 Step 1 pero con las diferencias exactas (tabla, condición, comando) — aceptable porque el ejecutor lee el Step 1 en el mismo task.
- **Consistencia de nombres:** fuentes (`propuestas_backups`, `propuestas`, `arquetipo_marcas`, `tareas_relacionadas`, `tareas_sin_arquetipo`) idénticas en T5 y T6; señales `selectedProp`/`selectedArq`; ids de patch `dec-<n>` / `arq-<id8>`; scripts `propuesta_mark.sh`/`arquetipo_mark.sh` en `manifest.writes` de sus bloques y `propuesta_cargar.sh` en el de la página.

#!/usr/bin/env bash
# ingest_notion.sh <classified.json> [--project NAME] [--limit N] [--only-open] [--yes]  **[WRITE]**
#
# Ingest Notion tasks (from a classified.json produced by the ontology pilot) into
# ikigaigm.tasks, as ONE transaction. Each row is born with:
#   - provenance: source_type='notion', source_url (Notion page), source_external_id
#     (Notion page id) — see migration 002 / task-provenance.
#   - archetype tag: archetype_id + archetype_match_method='llm' + confidence.
#   - status/priority mapped from the Notion fields; due_date = Notion `fecha` (may be null).
#
# Scope (v1): TAG + PROVENANCE only — NO IO contract instantiation and NO assignees
# (Notion names don't map cleanly to the team; materialize both in a later pass).
#
# DEDUP: skips any row whose source_external_id already exists (idempotent, re-runnable).
# SAFE BY DEFAULT: previews + ROLLBACK unless --yes is passed.
#
#   classified.json : array of {id(notion), url, tarea, estado, fecha, archetype_id, confidence}
#   --project NAME  : project to attach (default "David Guerrero")
#   --limit N       : only the first N rows (for testing)
#   --only-open     : skip Notion tasks whose estado is Done/Archivo
#   --yes           : actually COMMIT (otherwise dry-run rollback)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

CLASSIFIED=""; PROJECT="David Guerrero"; LIMIT=""; ONLY_OPEN=""; COMMIT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2;;
    --limit) LIMIT="$2"; shift 2;;
    --only-open) ONLY_OPEN=1; shift;;
    --yes) COMMIT=1; shift;;
    -h|--help) sed -n '2,24p' "$0"; exit 0;;
    *) CLASSIFIED="$1"; shift;;
  esac
done
[[ -z "$CLASSIFIED" ]] && { echo "usage: ingest_notion.sh <classified.json> [--project N] [--limit N] [--only-open] [--yes]" >&2; exit 2; }
[[ -f "$CLASSIFIED" ]] || { echo "no existe: $CLASSIFIED" >&2; exit 1; }

# Build the ingest payload (map status/priority, keep provenance + archetype).
payload="$(LIMIT="$LIMIT" ONLY_OPEN="$ONLY_OPEN" CLASSIFIED="$CLASSIFIED" python3 - <<'PY'
import json, os
d = json.load(open(os.environ["CLASSIFIED"]))
limit = os.environ.get("LIMIT") or ""
only_open = os.environ.get("ONLY_OPEN")
STATUS = {"Done": "completed", "Archivo": "cancelled", "In Progress": "in_progress", "On Time": "pending"}
PRIORITY = {"Urgente": "High", "Importante": "Medium"}
out = []
for r in d:
    est = r.get("estado")
    if only_open and est in ("Done", "Archivo"):
        continue
    ext = r.get("id")
    if not ext or not (r.get("tarea") or "").strip():
        continue  # skip empty-title / id-less rows
    out.append({
        "title": r["tarea"].strip(),
        "priority": PRIORITY.get(r.get("prioridad"), "Medium"),
        "due_date": r.get("fecha"),           # may be null
        "status": STATUS.get(est, "pending"),
        "archetype": r.get("archetype_id") or "",
        "confidence": str(r.get("confidence") or ""),
        "url": r.get("url") or "",
        "external_id": ext,
    })
if limit:
    out = out[: int(limit)]
print(json.dumps(out, ensure_ascii=False))
PY
)"
n_payload="$(node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(0,"utf8")).length))' <<<"$payload")"
echo "payload: $n_payload tareas candidatas (proyecto: $PROJECT)" >&2

end="COMMIT"; [[ -z "$COMMIT" ]] && end="ROLLBACK"
psql_rw -v payload="$payload" -v proj="$PROJECT" <<SQL
BEGIN;
WITH pl AS (SELECT :'payload'::jsonb AS arr),
proj AS (SELECT id FROM ikigaigm.projects
          WHERE name ILIKE '%'||:'proj'||'%' OR id::text LIKE :'proj'||'%' LIMIT 1),
rows AS (
  SELECT e FROM pl, jsonb_array_elements((SELECT arr FROM pl)) e
),
ins AS (
  INSERT INTO ikigaigm.tasks
    (title, project_id, priority, due_date, status,
     archetype_id, archetype_match_method, archetype_confidence,
     source_type, source_url, source_external_id)
  SELECT r.e->>'title',
         (SELECT id FROM proj),
         (r.e->>'priority')::ikigaigm.task_priority,
         nullif(r.e->>'due_date','')::timestamptz,
         (r.e->>'status')::ikigaigm.task_status,
         nullif(r.e->>'archetype',''),
         CASE WHEN nullif(r.e->>'archetype','') IS NOT NULL THEN 'llm' END,
         nullif(r.e->>'confidence',''),
         'notion', nullif(r.e->>'url',''), r.e->>'external_id'
  FROM rows r
  WHERE NOT EXISTS (
    SELECT 1 FROM ikigaigm.tasks t WHERE t.source_external_id = r.e->>'external_id')
  RETURNING id
)
SELECT (SELECT count(*) FROM rows)                          AS candidatas,
       (SELECT count(*) FROM ins)                           AS insertadas,
       (SELECT count(*) FROM rows) - (SELECT count(*) FROM ins) AS ya_existian_skip;
-- distribución de lo que quedaría por estado/archetype (post-insert, dentro del txn)
SELECT status, count(*) FROM ikigaigm.tasks
  WHERE source_type='notion' GROUP BY status ORDER BY 2 DESC;
$end;
SQL

[[ -z "$COMMIT" ]] && echo "(dry-run: ROLLBACK — nada escrito. Añade --yes para confirmar.)" >&2
exit 0

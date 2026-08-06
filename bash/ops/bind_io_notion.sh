#!/usr/bin/env bash
# bind_io_notion.sh <notion-rows.json> [--dry-run] [--yes]  **[WRITE]**
#
# Bind the Drive folders that a Notion task carries to the task's IO contract:
# ❌Drive Crudo -> the INPUT that expects the raw material, ✅Drive Editado ->
# the OUTPUT that delivers the edited piece. Third step of the Notion pipeline,
# AFTER the IO rows exist:
#
#   ingest_notion.sh  ->  materialize_io.sh  ->  bind_io_notion.sh
#
# Design + rationale: docs/io-bindings-drive.md
#
# MATCHING RULE (v1, by io_type — fails loud, never guesses):
#   drive_crudo   -> the task's single input  with io_type `video_asset`
#   drive_editado -> the task's single output with io_type `video_asset`/`ad_creative`
# If the rule matches 0 or >1 rows, that side is SKIPPED and reported.
#
# Each bound row gets its artifact_type retyped to `drive_file` and the jsonb
# shallow-merged with {file_id, url, _resolved:{title,url}}. `_resolved` is a
# render cache filled here via bash/google/drive_file.sh; if the backend fails
# the binding still persists (the chip degrades to the file_id).
#
# IDEMPOTENT: a row already bound to the same file_id is left untouched.
# SAFE BY DEFAULT: previews + ROLLBACK unless --yes.
#
#   <notion-rows.json>  rows from bash/notion/project_tasks.sh (needs the
#                       `files`-as-urls extractor, i.e. drive_* are lists)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

SRC=""; COMMIT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) COMMIT=1; shift;;
    --dry-run) COMMIT=""; shift;;
    -h|--help) sed -n '2,30p' "$0"; exit 0;;
    *) SRC="$1"; shift;;
  esac
done
[[ -z "$SRC" ]] && { echo "usage: bind_io_notion.sh <notion-rows.json> [--dry-run] [--yes]" >&2; exit 2; }
[[ -f "$SRC" ]] || { echo "no existe: $SRC" >&2; exit 1; }

# 1) Collect (external_id, side, file_id, url) from the Notion rows.
pairs="$(SRC="$SRC" python3 - <<'PY'
import json, os, re
rows = json.load(open(os.environ["SRC"]))
ID = re.compile(r"/(?:folders|d)/([A-Za-z0-9_-]{10,})")

def artifact_for(url):
    """The concrete artifact type comes from the URL shape, not from the field:
    Notion's ❌Drive Crudo / ✅Drive Editado mix folders, loose files AND Google
    Docs/Sheets in the same property."""
    if "docs.google.com/document" in url:      return "google_doc"
    if "docs.google.com/spreadsheets" in url:  return "google_sheet"
    if "docs.google.com/presentation" in url:  return "web_url"   # no slides type yet
    return "drive_file"

out = []
for r in rows:
    ext = r.get("id")
    if not ext:
        continue
    for side, key in (("input", "drive_crudo"), ("output", "drive_editado")):
        for f in (r.get(key) or []):
            if not isinstance(f, dict):
                continue          # old extractor emitted a count -> nothing to bind
            if f.get("hosted"):
                continue          # Notion-hosted url expires; never persist it
            url = f.get("url") or ""
            m = ID.search(url)
            if not m:
                continue
            out.append({"external_id": ext, "side": side, "file_id": m.group(1),
                        "url": url, "artifact": artifact_for(url)})
            break                 # one folder per side
print(json.dumps(out, ensure_ascii=False))
PY
)"
n_pairs="$(python3 -c 'import json,sys; print(len(json.loads(sys.stdin.read())))' <<<"$pairs")"
echo "carpetas de Drive encontradas en el JSON: $n_pairs" >&2
[[ "$n_pairs" == "0" ]] && { echo "nada que enganchar." >&2; exit 0; }

# 2) Resolve each file_id -> {title,url} via the mkt backend (render cache).
#    Failure here is non-fatal: the binding persists without _resolved.
resolved="$(python3 -c 'import json,sys; print("\n".join(sorted({p["file_id"] for p in json.loads(sys.stdin.read())})))' <<<"$pairs" \
  | while read -r fid; do
      [[ -z "$fid" ]] && continue
      if meta="$(bash "$(dirname "$0")/../google/drive_file.sh" "$fid" --json 2>/dev/null)"; then
        python3 -c '
import json,sys
fid, raw = sys.argv[1], sys.stdin.read()
try:
    d = json.loads(raw)
    print(json.dumps({"file_id": fid, "title": d.get("name"), "url": d.get("webViewLink")}, ensure_ascii=False))
except Exception:
    pass' "$fid" <<<"$meta"
      fi
    done | python3 -c 'import json,sys; print(json.dumps([json.loads(l) for l in sys.stdin if l.strip()], ensure_ascii=False))')"
echo "resueltos contra Drive: $(python3 -c 'import json,sys; print(len(json.loads(sys.stdin.read())))' <<<"$resolved")/$(python3 -c 'import json,sys; print(len({p["file_id"] for p in json.loads(sys.stdin.read())}))' <<<"$pairs")" >&2

# 3) Merge pairs + resolved into the payload the SQL consumes.
payload="$(PAIRS="$pairs" RES="$resolved" python3 - <<'PY'
import json, os
pairs = json.loads(os.environ["PAIRS"]); res = {r["file_id"]: r for r in json.loads(os.environ["RES"])}
for p in pairs:
    r = res.get(p["file_id"])
    ref = {"file_id": p["file_id"], "url": p["url"]}
    if r and (r.get("title") or r.get("url")):
        ref["_resolved"] = {"title": r.get("title"), "url": r.get("url") or p["url"]}
    p["ref"] = ref
print(json.dumps(pairs, ensure_ascii=False))
PY
)"

end="COMMIT"; [[ -z "$COMMIT" ]] && end="ROLLBACK"
# The payload rides in the SQL text over stdin (dollar-quoted), NOT as a psql
# -v variable: a few hundred bindings blow past ARG_MAX on the psql argv.
psql_rw -v ON_ERROR_STOP=1 <<SQL
BEGIN;
CREATE TEMP TABLE _pl ON COMMIT DROP AS
SELECT e->>'external_id' AS external_id, e->>'side' AS side,
       e->>'file_id' AS file_id, (e->'ref')::jsonb AS ref,
       (SELECT id FROM artifact_types WHERE name = e->>'artifact') AS art_id
FROM jsonb_array_elements(\$pl\$${payload}\$pl\$::jsonb) e;

-- Resolve each pair to exactly ONE io row (0 or >1 => not resolved => skipped).
CREATE TEMP TABLE _tgt ON COMMIT DROP AS
SELECT p.*, t.id AS task_id,
  -- min(id) + HAVING count(*)=1 => the id when the rule matches EXACTLY one
  -- row, and no row (NULL) when it matches 0 or >1. Never guesses.
  CASE WHEN p.side='input' THEN (
        SELECT min(i.id::text)::uuid FROM task_inputs i
          JOIN io_types it ON it.id=i.io_type_id
         WHERE i.task_id=t.id AND it.name='video_asset'
        HAVING count(*)=1)
       ELSE (
        SELECT min(o.id::text)::uuid FROM task_outputs o
          JOIN io_types it ON it.id=o.io_type_id
         WHERE o.task_id=t.id AND it.name IN ('video_asset','ad_creative')
        HAVING count(*)=1)
  END AS io_id
FROM _pl p JOIN tasks t ON t.source_external_id = p.external_id;

-- Converges on BOTH the reference and the artifact type: a row already bound to
-- the same file_id but mistyped still gets corrected.
UPDATE task_inputs i
   SET artifact_reference = coalesce(i.artifact_reference,'{}'::jsonb) || g.ref,
       artifact_type_id   = g.art_id
  FROM _tgt g
 WHERE g.side='input' AND g.io_id = i.id
   AND (coalesce(i.artifact_reference->>'file_id','') IS DISTINCT FROM g.file_id
     OR i.artifact_type_id IS DISTINCT FROM g.art_id);

UPDATE task_outputs o
   SET deliverable_reference = coalesce(o.deliverable_reference,'{}'::jsonb) || g.ref,
       artifact_type_id      = g.art_id
  FROM _tgt g
 WHERE g.side='output' AND g.io_id = o.id
   AND (coalesce(o.deliverable_reference->>'file_id','') IS DISTINCT FROM g.file_id
     OR o.artifact_type_id IS DISTINCT FROM g.art_id);

SELECT (SELECT count(*) FROM _pl)                                AS pares_en_payload,
       (SELECT count(*) FROM _tgt)                               AS con_tarea_en_db,
       (SELECT count(*) FROM _tgt WHERE io_id IS NOT NULL)       AS con_fila_io_resuelta,
       (SELECT count(*) FROM _tgt WHERE io_id IS NULL)           AS sin_resolver_skip;

\echo '-- pares sin fila IO resoluble (regla 0 o >1) --'
SELECT g.side, left(t.title,52) AS tarea, t.archetype_id
  FROM _tgt g JOIN tasks t ON t.id=g.task_id
 WHERE g.io_id IS NULL LIMIT 10;
$end;
SQL

[[ -z "$COMMIT" ]] && echo "(dry-run: ROLLBACK — nada escrito. Añade --yes para confirmar.)" >&2

#!/usr/bin/env bash
# Set (or clear) the activity archetype tag on a task. WRITE, transactional,
# --dry-run rolls back. Validates the archetype exists in the catalog.
#
# Usage:
#   set_archetype.sh <task-id|prefix> <archetype-id>   [--method rule|embedding|llm|human] [--confidence X] [--dry-run]
#   set_archetype.sh <task-id|prefix> --clear           [--dry-run]
#
# Default --method is 'human'. The SOP/macro-process follow automatically via
# activity_archetypes → sops → macro_processes.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

tref="${1:-}" aref="${2:-}"
[[ -z "$tref" || "$tref" == "-h" || "$tref" == "--help" ]] && { sed -n '2,13p' "$0"; exit 0; }
[[ -z "$aref" ]] && { echo "Missing <archetype-id> or --clear; see -h" >&2; exit 2; }
shift 2 || true
method="human" conf="" dry="" clear=""
[[ "$aref" == "--clear" ]] && clear=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --method) method="$2"; shift 2 ;;
    --confidence) conf="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Resolve the task (exactly one).
tid="$(psql_ro -t -A -c "SELECT id FROM ikigaigm.tasks WHERE id::text LIKE '${tref//\'/\'\'}%'")"
n="$(printf '%s\n' "$tid" | grep -c . || true)"
if [[ "$n" -ne 1 ]]; then echo "Task ref '$tref' resolved to $n tasks (need 1)." >&2; exit 1; fi

# Validate archetype unless clearing.
if [[ -z "$clear" ]]; then
  ok="$(psql_ro -t -A -c "SELECT count(*) FROM ikigaigm.activity_archetypes WHERE id='${aref//\'/\'\'}'")"
  [[ "$ok" == "1" ]] || { echo "Unknown archetype '$aref' (not in catalog)." >&2; exit 1; }
fi

end="COMMIT"; [[ -n "$dry" ]] && end="ROLLBACK"
set_sql="archetype_id='${aref//\'/\'\'}', archetype_match_method='${method//\'/\'\'}', archetype_confidence=$( [[ -n "$conf" ]] && echo "'${conf//\'/\'\'}'" || echo "archetype_confidence" )"
[[ -n "$clear" ]] && set_sql="archetype_id=NULL, archetype_match_method=NULL, archetype_confidence=NULL"

psql_rw -v tid="$tid" <<SQL
BEGIN;
\echo '==== BEFORE ===='
SELECT t.id, left(t.title,48) AS title, t.archetype_id, a.sop_code, s.macro_process_code AS macro
FROM ikigaigm.tasks t
LEFT JOIN ikigaigm.activity_archetypes a ON a.id=t.archetype_id
LEFT JOIN ikigaigm.sops s ON s.code=a.sop_code
WHERE t.id = :'tid'::uuid;

UPDATE ikigaigm.tasks SET $set_sql WHERE id = :'tid'::uuid;

\echo '==== AFTER ===='
SELECT t.id, left(t.title,48) AS title, t.archetype_id, a.sop_code, s.macro_process_code AS macro, t.archetype_match_method AS method
FROM ikigaigm.tasks t
LEFT JOIN ikigaigm.activity_archetypes a ON a.id=t.archetype_id
LEFT JOIN ikigaigm.sops s ON s.code=a.sop_code
WHERE t.id = :'tid'::uuid;
$end;
SQL

[[ -n "$dry" ]] && echo "(dry-run: rolled back, nothing written)"
exit 0

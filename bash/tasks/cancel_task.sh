#!/usr/bin/env bash
# Cancel a task (status='cancelled'), optionally recording that it was merged into
# another task. WRITE, transactional, --dry-run rolls back. Leaves a comment trail
# on both the cancelled task and (if --into) the survivor, so the merge is auditable.
#
# Usage:
#   cancel_task.sh <id|prefix> [--into <id|prefix>] [--reason "text"] [--dry-run]
#
# The agentic follow-up loop ignores cancelled tasks. Nothing is deleted.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

tref="${1:-}"
[[ -z "$tref" || "$tref" == "-h" || "$tref" == "--help" ]] && { sed -n '2,10p' "$0"; exit 0; }
shift || true
into="" reason="" dry=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --into) into="$2"; shift 2 ;;
    --reason) reason="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

resolve_task() { # echoes the single full id for a prefix, errors otherwise
  local ref="$1" ids n
  ids="$(psql_ro -t -A -c "SELECT id FROM tasks WHERE id::text LIKE '${ref//\'/\'\'}%'")"
  n="$(printf '%s\n' "$ids" | grep -c . || true)"
  [[ "$n" -eq 1 ]] || { echo "Task ref '$ref' resolved to $n tasks (need 1)." >&2; return 1; }
  printf '%s' "$ids"
}

tid="$(resolve_task "$tref")" || exit 1
iid=""; [[ -n "$into" ]] && { iid="$(resolve_task "$into")" || exit 1; }

end="COMMIT"; [[ -n "$dry" ]] && end="ROLLBACK"
psql_rw -v tid="$tid" -v iid="$iid" -v reason="$reason" <<SQL
BEGIN;
\echo '==== BEFORE ===='
SELECT left(id::text,8) AS id, status, left(title,52) AS title FROM tasks WHERE id = :'tid'::uuid;

UPDATE tasks SET status='cancelled'::task_status WHERE id = :'tid'::uuid;

-- comment trail on the cancelled task
INSERT INTO task_comments (task_id, author_name, text)
SELECT :'tid'::uuid, 'cancel_task',
       'Cancelada'
       || CASE WHEN nullif(:'iid','') IS NOT NULL
               THEN ' — fusionada en '||left(:'iid',8)||' ('||coalesce((SELECT title FROM tasks WHERE id=:'iid'::uuid),'?')||')'
               ELSE '' END
       || CASE WHEN nullif(:'reason','') IS NOT NULL THEN '. '||:'reason' ELSE '' END;

-- comment trail on the survivor (if any)
INSERT INTO task_comments (task_id, author_name, text)
SELECT :'iid'::uuid, 'cancel_task',
       'Absorbe la tarea '||left(:'tid',8)||' ('||coalesce((SELECT title FROM tasks WHERE id=:'tid'::uuid),'?')||') por fusión.'
WHERE nullif(:'iid','') IS NOT NULL;

\echo '==== AFTER ===='
SELECT left(id::text,8) AS id, status, left(title,52) AS title FROM tasks WHERE id = :'tid'::uuid;
$end;
SQL

[[ -n "$dry" ]] && echo "(dry-run: rolled back, nothing written)"
exit 0

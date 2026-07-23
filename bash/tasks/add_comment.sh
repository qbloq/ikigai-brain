#!/usr/bin/env bash
# Add a comment to a task's comment trail. WRITE, transactional, --dry-run rolls
# back. Prints before/after (the task's comment count + the inserted row), so the
# addition is auditable. Nothing is deleted or overwritten.
#
# Usage:
#   add_comment.sh <id|prefix> --text "comment text" [--author NAME] [--dry-run] [--json]
#
# --author defaults to 'note'. Use it to attribute the comment (e.g. a skill name
# or a person). --json emits {task_id, comment_id, author, text} for viz re-render.
# Common use: record a cross-reference/decision on an existing task (e.g. a merge
# candidate found via the meeting pipeline) without creating a duplicate task.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

tref="${1:-}"
[[ -z "$tref" || "$tref" == "-h" || "$tref" == "--help" ]] && { sed -n '2,13p' "$0"; exit 0; }
shift || true
text="" author="note" dry="" json=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --text)    text="$2"; shift 2 ;;
    --author)  author="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    --json)    json=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$text" ]] && { echo "--text is required." >&2; exit 2; }

resolve_task() { # echoes the single full id for a prefix, errors otherwise
  local ref="$1" ids n
  ids="$(psql_ro -t -A -c "SELECT id FROM tasks WHERE id::text LIKE '${ref//\'/\'\'}%'")"
  n="$(printf '%s\n' "$ids" | grep -c . || true)"
  [[ "$n" -eq 1 ]] || { echo "Task ref '$ref' resolved to $n tasks (need 1)." >&2; return 1; }
  printf '%s' "$ids"
}

tid="$(resolve_task "$tref")" || exit 1
end="COMMIT"; [[ -n "$dry" ]] && end="ROLLBACK"

if [[ -n "$json" ]]; then
  psql_rw -t -A -v tid="$tid" -v author="$author" -v text="$text" <<SQL
BEGIN;
INSERT INTO task_comments (task_id, author_name, text)
VALUES (:'tid'::uuid, :'author', :'text')
RETURNING json_build_object('task_id', left(task_id::text,8), 'comment_id', id,
                            'author', author_name, 'text', text);
$end;
SQL
  [[ -n "$dry" ]] && echo "(dry-run: rolled back, nothing written)" >&2
  exit 0
fi

psql_rw -v tid="$tid" -v author="$author" -v text="$text" <<SQL
BEGIN;
\echo '==== TASK ===='
SELECT left(id::text,8) AS id, status, left(title,56) AS title FROM tasks WHERE id = :'tid'::uuid;
\echo '==== BEFORE (comment count) ===='
SELECT count(*) AS comments FROM task_comments WHERE task_id = :'tid'::uuid;

INSERT INTO task_comments (task_id, author_name, text)
VALUES (:'tid'::uuid, :'author', :'text');

\echo '==== ADDED ===='
SELECT author_name, left(text,80) AS text, created_at
  FROM task_comments
 WHERE task_id = :'tid'::uuid ORDER BY created_at DESC LIMIT 1;
$end;
SQL

[[ -n "$dry" ]] && echo "(dry-run: rolled back, nothing written)"
exit 0

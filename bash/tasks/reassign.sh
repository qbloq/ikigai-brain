#!/usr/bin/env bash
# Reassign a task's assignees. WRITE operation (uses psql_rw). Always runs in a
# transaction and prints before/after; pass --dry-run to preview and roll back.
#
# Members are given as an id-prefix (e.g. e6fea6f1) or a person name fragment
# (e.g. "Tony Vidal"). Name fragments must resolve to exactly one team member.
#
# Usage (pick ONE operation):
#   reassign.sh <task_id|prefix> --from <member> --to <member>   # swap one
#   reassign.sh <task_id|prefix> --add <member>                  # add one
#   reassign.sh <task_id|prefix> --remove <member>               # remove one
#   reassign.sh <task_id|prefix> --set <member>[,<member>...]    # replace all
#   [--dry-run]   preview only, no commit
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

[[ $# -lt 1 ]] && { sed -n '2,18p' "$0"; exit 2; }
task_arg="$1"; shift
op="" from="" to="" member="" setlist="" dry=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)    from="$2"; shift 2 ;;
    --to)      to="$2"; shift 2 ;;
    --add)     op="add"; member="$2"; shift 2 ;;
    --remove)  op="remove"; member="$2"; shift 2 ;;
    --set)     op="set"; setlist="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$from$to" ]] && op="swap"

# Resolve task
task_arg="${task_arg//\'/}"
tid="$(psql_ro -t -A -c "SELECT id FROM ikigaigm.tasks WHERE id::text LIKE '${task_arg}%' LIMIT 2;")"
[[ -z "$tid" ]] && { echo "No task matches: $task_arg" >&2; exit 1; }
[[ "$(printf '%s\n' "$tid" | grep -c .)" -gt 1 ]] && { echo "Task prefix '$task_arg' is ambiguous." >&2; exit 1; }

# Build the UPDATE expression for assignee
case "$op" in
  swap)
    [[ -z "$from" || -z "$to" ]] && { echo "--from and --to are both required" >&2; exit 2; }
    f="$(resolve_member "$from")" || exit 1
    t="$(resolve_member "$to")"   || exit 1
    expr="array_replace(assignee, '$f'::uuid, '$t'::uuid)" ;;
  add)
    m="$(resolve_member "$member")" || exit 1
    expr="(SELECT CASE WHEN '$m'::uuid = ANY(coalesce(assignee,'{}')) THEN assignee
                       ELSE array_append(coalesce(assignee,'{}'::uuid[]), '$m'::uuid) END)" ;;
  remove)
    m="$(resolve_member "$member")" || exit 1
    expr="array_remove(assignee, '$m'::uuid)" ;;
  set)
    [[ -z "$setlist" ]] && { echo "--set needs a comma-separated list" >&2; exit 2; }
    arr=""
    IFS=',' read -ra parts <<< "$setlist"
    for p in "${parts[@]}"; do
      p="$(echo "$p" | sed 's/^ *//;s/ *$//')"
      [[ -z "$p" ]] && continue
      mid="$(resolve_member "$p")" || exit 1
      arr+="'$mid'::uuid,"
    done
    expr="ARRAY[${arr%,}]" ;;
  *) echo "Specify an operation: --from/--to, --add, --remove or --set" >&2; exit 2 ;;
esac

# Resolved-names view of a task's assignees, for before/after.
show_sql="SELECT $ASSIGNEES_SQL AS assignees, $ROLES_SQL AS roles
          FROM ikigaigm.tasks t WHERE t.id='$tid'"

end="COMMIT"; [[ -n "$dry" ]] && end="ROLLBACK"

psql_rw <<SQL
BEGIN;
\echo '--- BEFORE ---'
$show_sql;
UPDATE ikigaigm.tasks SET assignee = $expr, updated_at = now() WHERE id = '$tid';
\echo '--- AFTER ---'
$show_sql;
$end;
SQL

[[ -n "$dry" ]] && echo "(dry-run: rolled back, no changes committed)"

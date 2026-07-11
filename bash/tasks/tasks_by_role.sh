#!/usr/bin/env bash
# List tasks filtered by the ROLE of their assignees, resolving the
# assignee[] -> team_members -> team_roles chain. Supports the same filters
# as tasks.sh. Output includes a `roles` column.
#
# Usage:
#   tasks_by_role.sh [--role NAME] [--status S] [--priority P] [--project NAME]
#                    [--assignee NAME] [--open] [--limit N] [--json]
#
#   --role NAME     role name fragment (e.g. Copy, Estratega, "Project Manager")
#                   omit to list all tasks with their roles shown
#   --status S      pending | in_progress | completed | blocked | cancelled
#   --priority P    Low | Medium | High
#   --project NAME  project name fragment (e.g. Ikigai)
#   --assignee NAME person name fragment (e.g. David)
#   --open          only tasks not completed/cancelled
#   --limit N       cap rows (default 50; use 0 for no limit)
#   --json          JSON array output
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

role="" status="" priority="" project="" assignee="" open="" limit="50"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)     role="$2"; shift 2 ;;
    --status)   status="$2"; shift 2 ;;
    --priority) priority="$2"; shift 2 ;;
    --project)  project="$2"; shift 2 ;;
    --assignee) assignee="$2"; shift 2 ;;
    --open)     open=1; shift ;;
    --limit)    limit="$2"; shift 2 ;;
    --json)     FORMAT=json; shift ;;
    -h|--help)  sed -n '2,21p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

esc() { printf '%s' "${1//\'/\'\'}"; }
where="true"
[[ -n "$status" ]]   && where="$where AND t.status = '$(esc "$status")'"
[[ -n "$priority" ]] && where="$where AND t.priority = '$(esc "$priority")'"
[[ -n "$open" ]]     && where="$where AND $OPEN_PRED"
if [[ -n "$project" ]]; then
  pid="$(resolve_project "$project")"
  [[ -z "$pid" ]] && { echo "No project matches: $project" >&2; exit 1; }
  where="$where AND t.project_id = '$pid'"
fi
if [[ -n "$role" ]]; then
  where="$where AND EXISTS (SELECT 1 FROM unnest(t.assignee) aid
    JOIN ikigaigm.team_members tm ON tm.id=aid
    LEFT JOIN ikigaigm.team_roles tr ON tr.id=tm.role_id
    WHERE tr.name ILIKE '%$(esc "$role")%')"
fi
if [[ -n "$assignee" ]]; then
  where="$where AND EXISTS (SELECT 1 FROM unnest(t.assignee) aid
    JOIN ikigaigm.team_members tm ON tm.id=aid
    LEFT JOIN ikigaigm.users u ON u.id=tm.user_id
    LEFT JOIN ikigaigm.persons p ON p.person_id=u.person_id
    WHERE (coalesce(p.name,'')||' '||coalesce(p.lastname,'')) ILIKE '%$(esc "$assignee")%')"
fi

[[ "$limit" == "0" ]] && limit=""
lim=""; [[ -n "$limit" ]] && lim="LIMIT $limit"

emit "SELECT left(t.id::text,8)               AS id,
       t.title,
       t.status::text                    AS status,
       t.priority::text                  AS priority,
       to_char(t.due_date,'YYYY-MM-DD')  AS due,
       pr.name                           AS project,
       $ROLES_SQL                        AS roles,
       $ASSIGNEES_SQL                    AS assignees
FROM ikigaigm.tasks t
LEFT JOIN ikigaigm.projects pr ON pr.id = t.project_id
WHERE $where
ORDER BY t.due_date NULLS LAST, t.priority DESC
$lim"

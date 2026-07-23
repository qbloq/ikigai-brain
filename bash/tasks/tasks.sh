#!/usr/bin/env bash
# List tasks with optional filters.
#
# Usage:
#   tasks.sh [--status S] [--priority P] [--project NAME] [--assignee NAME]
#            [--due W] [--open] [--limit N] [--json]
#
#   --status S      pending | in_progress | completed | blocked | cancelled
#   --priority P    Low | Medium | High
#   --project NAME  project name fragment
#   --assignee NAME person name fragment (e.g. David)
#   --due W         due window: today|tomorrow|yesterday|this-week|next-week|overdue
#   --open          only tasks not completed/cancelled
#   --limit N       cap rows (default 50; use 0 for no limit)
#   --json          JSON array output
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

status="" priority="" project="" assignee="" due="" open="" limit="50"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --status)   status="$2"; shift 2 ;;
    --priority) priority="$2"; shift 2 ;;
    --project)  project="$2"; shift 2 ;;
    --assignee) assignee="$2"; shift 2 ;;
    --due)      due="$2"; shift 2 ;;
    --open)     open=1; shift ;;
    --limit)    limit="$2"; shift 2 ;;
    --json)     FORMAT=json; shift ;;
    -h|--help)  sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

esc() { printf '%s' "${1//\'/\'\'}"; }
where="true"
[[ -n "$status" ]]   && where="$where AND t.status = '$(esc "$status")'"
[[ -n "$priority" ]] && where="$where AND t.priority = '$(esc "$priority")'"
[[ -n "$open" ]]     && where="$where AND $OPEN_PRED"
if [[ -n "$due" ]]; then
  case "$due" in
    today)     due_pred="t.due_date::date = current_date" ;;
    tomorrow)  due_pred="t.due_date::date = current_date + 1" ;;
    yesterday) due_pred="t.due_date::date = current_date - 1" ;;
    this-week) due_pred="t.due_date::date BETWEEN date_trunc('week',current_date)::date AND (date_trunc('week',current_date)+interval '6 days')::date" ;;
    next-week) due_pred="t.due_date::date BETWEEN (date_trunc('week',current_date)+interval '7 days')::date AND (date_trunc('week',current_date)+interval '13 days')::date" ;;
    overdue)   due_pred="t.due_date::date < current_date" ;;
    *) echo "Unknown --due window: $due" >&2; exit 2 ;;
  esac
  where="$where AND t.due_date IS NOT NULL AND ($due_pred)"
fi
if [[ -n "$project" ]]; then
  pid="$(resolve_project "$project")"
  [[ -z "$pid" ]] && { echo "No project matches: $project" >&2; exit 1; }
  where="$where AND t.project_id = '$pid'"
fi
if [[ -n "$assignee" ]]; then
  where="$where AND EXISTS (SELECT 1 FROM unnest(t.assignee) aid
    JOIN team_members tm ON tm.id=aid
    LEFT JOIN users u ON u.id=tm.user_id
    LEFT JOIN persons p ON p.person_id=u.person_id
    WHERE (coalesce(p.name,'')||' '||coalesce(p.lastname,'')) ILIKE '%$(esc "$assignee")%')"
fi

[[ "$limit" == "0" ]] && limit=""
emit "$(tasks_select "$where" "t.due_date NULLS LAST, t.priority DESC" "$limit")"

#!/usr/bin/env bash
# List tasks by due date. Dates are evaluated in America/Bogota time.
#
# Usage:
#   tasks_due.sh --today | --tomorrow | --yesterday
#                --this-week | --next-week | --overdue
#                --from YYYY-MM-DD --to YYYY-MM-DD
#   [--all]   include completed/cancelled (default: only open tasks)
#   [--json]  JSON array output
#
# Week = Monday..Sunday. --overdue = open tasks whose due date is before today.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

mode="" from="" to="" all=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --today|--tomorrow|--yesterday|--this-week|--next-week|--overdue)
      mode="${1#--}"; shift ;;
    --from) from="$2"; shift 2 ;;
    --to)   to="$2"; shift 2 ;;
    --all)  all=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$mode" in
  today)     pred="t.due_date::date = current_date" ;;
  tomorrow)  pred="t.due_date::date = current_date + 1" ;;
  yesterday) pred="t.due_date::date = current_date - 1" ;;
  this-week) pred="t.due_date::date BETWEEN date_trunc('week',current_date)::date AND (date_trunc('week',current_date)+interval '6 days')::date" ;;
  next-week) pred="t.due_date::date BETWEEN (date_trunc('week',current_date)+interval '7 days')::date AND (date_trunc('week',current_date)+interval '13 days')::date" ;;
  overdue)   pred="t.due_date::date < current_date" ;;
  "")
    [[ -z "$from$to" ]] && { echo "Specify a window (e.g. --today, --this-week, --overdue, or --from/--to)" >&2; exit 2; }
    pred="true"
    [[ -n "$from" ]] && pred="$pred AND t.due_date::date >= '${from//\'/}'"
    [[ -n "$to" ]]   && pred="$pred AND t.due_date::date <= '${to//\'/}'" ;;
esac

where="t.due_date IS NOT NULL AND ($pred)"
# Overdue is meaningless for done tasks; force open there.
if [[ "$mode" == "overdue" || -z "$all" ]]; then
  where="$where AND $OPEN_PRED"
fi

emit "$(tasks_select "$where" "t.due_date NULLS LAST, t.priority DESC" "")"

#!/usr/bin/env bash
# Aggregate task counts. Default groups by status; pick a dimension.
#
# Usage:  task_stats.sh [--by status|priority|project|assignee] [--open] [--json]
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

by="status" open=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --by) by="$2"; shift 2 ;;
    --open) open=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

filter="true"; [[ -n "$open" ]] && filter="$OPEN_PRED"

case "$by" in
  status)   emit "SELECT t.status::text AS status, count(*) AS tasks FROM tasks t WHERE $filter GROUP BY 1 ORDER BY 2 DESC" ;;
  priority) emit "SELECT t.priority::text AS priority, count(*) AS tasks FROM tasks t WHERE $filter GROUP BY 1 ORDER BY 2 DESC" ;;
  project)  emit "SELECT coalesce(pr.name,'(none)') AS project, count(*) AS tasks
              FROM tasks t LEFT JOIN projects pr ON pr.id=t.project_id
              WHERE $filter GROUP BY 1 ORDER BY 2 DESC" ;;
  assignee) emit "SELECT trim(coalesce(p.name,'')||' '||coalesce(p.lastname,'')) AS assignee, count(*) AS tasks
              FROM tasks t, unnest(t.assignee) aid
              JOIN team_members tm ON tm.id=aid
              LEFT JOIN users u ON u.id=tm.user_id
              LEFT JOIN persons p ON p.person_id=u.person_id
              WHERE $filter GROUP BY 1 ORDER BY 2 DESC" ;;
  *) echo "Unknown --by: $by (use status|priority|project|assignee)" >&2; exit 2 ;;
esac

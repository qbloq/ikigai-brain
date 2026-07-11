#!/usr/bin/env bash
# Flatten action items from team-meeting reports across meetings — a coordination
# view of who-owes-what coming out of the team meetings.
#
# Usage:
#   meeting_action_items.sh [--since YYYY-MM-DD] [--priority P]
#                           [--assignee NAME] [--limit N] [--json]
#
#   --since DATE    only meetings on/after this scheduled date
#   --priority P    High | Medium | Low (matches the report's priority text)
#   --assignee NAME match against the action item's assignedTo (fragment)
#   --limit N       cap rows (default 60; 0 = no cap)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

since="" priority="" assignee="" limit="60"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)    since="$2"; shift 2 ;;
    --priority) priority="$2"; shift 2 ;;
    --assignee) assignee="$2"; shift 2 ;;
    --limit)    limit="$2"; shift 2 ;;
    --json)     FORMAT=json; shift ;;
    -h|--help)  sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

esc() { printf '%s' "${1//\'/\'\'}"; }
where="m.meeting_type='team'"
[[ -n "$since" ]]    && where="$where AND m.scheduled_start_time::date >= '${since//\'/}'"
[[ -n "$priority" ]] && where="$where AND ai->>'priority' ILIKE '$(esc "$priority")'"
[[ -n "$assignee" ]] && where="$where AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(ai->'assignedTo') x WHERE x ILIKE '%$(esc "$assignee")%')"

[[ "$limit" == "0" ]] && limit=""
lim=""; [[ -n "$limit" ]] && lim="LIMIT $limit"

emit "SELECT to_char(m.scheduled_start_time,'YYYY-MM-DD') AS date,
  left(m.id::text,8) AS meeting,
  ai->>'priority' AS priority,
  (SELECT string_agg(x,', ') FROM jsonb_array_elements_text(ai->'assignedTo') x) AS assigned_to,
  ai->>'dueDate' AS due,
  ai->>'task' AS task
FROM ikigaigm.meetings m
JOIN ikigaigm.meeting_reports mr ON mr.meeting_id=m.id
CROSS JOIN LATERAL jsonb_array_elements(mr.report->'actionItems') ai
WHERE $where
ORDER BY m.scheduled_start_time DESC
$lim"

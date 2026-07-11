#!/usr/bin/env bash
# List team meetings (meeting_type='team') — the team's coordination meetings.
# Columns: id, start, status, project, rep (has report), tr (has transcript), name.
#
# Usage:
#   meetings.sh [--status S] [--project NAME] [--from YYYY-MM-DD] [--to YYYY-MM-DD]
#               [--has-report] [--has-transcript] [--limit N] [--json]
#
#   --status S        scheduled | completed | ended | cancelled | processing | ...
#   --project NAME    project name fragment
#   --from / --to     filter by scheduled start date (Bogota tz)
#   --has-report      only meetings that have a report
#   --has-transcript  only meetings that have a transcript
#   --limit N         cap rows (default 30; 0 = no cap)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

status="" project="" from="" to="" hasrep="" hastr="" limit="30"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --status)         status="$2"; shift 2 ;;
    --project)        project="$2"; shift 2 ;;
    --from)           from="$2"; shift 2 ;;
    --to)             to="$2"; shift 2 ;;
    --has-report)     hasrep=1; shift ;;
    --has-transcript) hastr=1; shift ;;
    --limit)          limit="$2"; shift 2 ;;
    --json)           FORMAT=json; shift ;;
    -h|--help)        sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

esc() { printf '%s' "${1//\'/\'\'}"; }
where="m.meeting_type='team'"
[[ -n "$status" ]] && where="$where AND m.status = '$(esc "$status")'"
[[ -n "$from" ]]   && where="$where AND m.scheduled_start_time::date >= '${from//\'/}'"
[[ -n "$to" ]]     && where="$where AND m.scheduled_start_time::date <= '${to//\'/}'"
[[ -n "$hasrep" ]] && where="$where AND EXISTS (SELECT 1 FROM ikigaigm.meeting_reports r WHERE r.meeting_id=m.id)"
[[ -n "$hastr" ]]  && where="$where AND EXISTS (SELECT 1 FROM ikigaigm.meeting_transcripts x WHERE x.meeting_id=m.id)"
if [[ -n "$project" ]]; then
  pid="$(resolve_project "$project")"
  [[ -z "$pid" ]] && { echo "No project matches: $project" >&2; exit 1; }
  where="$where AND m.project_id = '$pid'"
fi

[[ "$limit" == "0" ]] && limit=""
lim=""; [[ -n "$limit" ]] && lim="LIMIT $limit"

emit "SELECT left(m.id::text,8) AS id,
  to_char(m.scheduled_start_time,'YYYY-MM-DD HH24:MI') AS start,
  m.status,
  coalesce(pr.name,'—') AS project,
  CASE WHEN EXISTS (SELECT 1 FROM ikigaigm.meeting_reports r WHERE r.meeting_id=m.id) THEN 'Y' ELSE '' END AS rep,
  CASE WHEN EXISTS (SELECT 1 FROM ikigaigm.meeting_transcripts x WHERE x.meeting_id=m.id) THEN 'Y' ELSE '' END AS tr,
  m.name
FROM ikigaigm.meetings m
LEFT JOIN ikigaigm.projects pr ON pr.id=m.project_id
WHERE $where
ORDER BY m.scheduled_start_time DESC NULLS LAST
$lim"

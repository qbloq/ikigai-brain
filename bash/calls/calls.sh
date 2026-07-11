#!/usr/bin/env bash
# List SALES CALLS (meeting_type='call') — the closers' work product, invisible
# to the team-scoped bash/meetings/ suite. Each analyzed call has a report
# (lead, resultado, probabilidad, score del closer). The CLOSER is resolved
# through the CRM trace: meetings.event->booking->contact_id =
# crm_contacts.ghl_contact_id → crm_opportunities (tiebreak: same project,
# then latest) → user_id → users → persons.
#
# Usage:
#   calls.sh [--status S] [--result R] [--project NAME] [--program P] [--closer NAME]
#            [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--reported] [--sin-closer]
#            [--limit N] [--json]
#
#   --status S      scheduled | completed | ended | cancelled | processing | ...
#   --result R      callStatus fragment (Closed Won / Follow-up / Rescheduled / ...)
#   --project NAME  project (client) name fragment
#   --program P     program fragment (Premium Mastermind, Alquimia, ...)
#   --closer NAME   resolved closer name fragment
#   --from / --to   scheduled date range (Bogota tz)
#   --reported      only calls that have an analysis report
#   --sin-closer    reported calls whose closer could NOT be resolved (the
#                   S8.2 data-hygiene queue: contact without opportunity/user)
#   --limit N       cap rows (default 30; 0 = no cap)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

status="" result="" project="" program="" closer="" from="" to="" reported="" sincloser="" limit="30"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --status)     status="$2"; shift 2 ;;
    --result)     result="$2"; shift 2 ;;
    --project)    project="$2"; shift 2 ;;
    --program)    program="$2"; shift 2 ;;
    --closer)     closer="$2"; shift 2 ;;
    --from)       from="$2"; shift 2 ;;
    --to)         to="$2"; shift 2 ;;
    --reported)   reported=1; shift ;;
    --sin-closer) sincloser=1; shift ;;
    --limit)      limit="$2"; shift 2 ;;
    --json)       FORMAT=json; shift ;;
    -h|--help)    sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

esc() { printf '%s' "${1//\'/\'\'}"; }
where="m.meeting_type='call'"
[[ -n "$status" ]]    && where="$where AND m.status = '$(esc "$status")'"
[[ -n "$result" ]]    && where="$where AND r.report->'generalInformation'->>'callStatus' ILIKE '%$(esc "$result")%'"
[[ -n "$program" ]]   && where="$where AND coalesce(r.report->'generalInformation'->>'program', split_part(m.name,' - ',2)) ILIKE '%$(esc "$program")%'"
[[ -n "$closer" ]]    && where="$where AND cl.closer ILIKE '%$(esc "$closer")%'"
[[ -n "$from" ]]      && where="$where AND m.scheduled_start_time::date >= '${from//\'/}'"
[[ -n "$to" ]]        && where="$where AND m.scheduled_start_time::date <= '${to//\'/}'"
[[ -n "$reported" ]]  && where="$where AND r.meeting_id IS NOT NULL"
[[ -n "$sincloser" ]] && where="$where AND r.meeting_id IS NOT NULL AND cl.closer IS NULL"
if [[ -n "$project" ]]; then
  pid="$(resolve_project "$project")"
  [[ -z "$pid" ]] && { echo "No project matches: $project" >&2; exit 1; }
  where="$where AND m.project_id = '$pid'"
fi

[[ "$limit" == "0" ]] && limit=""
lim=""; [[ -n "$limit" ]] && lim="LIMIT $limit"

emit "SELECT left(m.id::text,8) AS id,
  to_char(m.scheduled_start_time,'YYYY-MM-DD HH24:MI') AS start,
  coalesce(r.report->'generalInformation'->>'leadName', split_part(m.name,' - ',1)) AS lead,
  coalesce(r.report->'generalInformation'->>'program', split_part(m.name,' - ',2)) AS program,
  coalesce(pr.name,'—') AS project,
  coalesce(cl.closer,'—') AS closer,
  m.status,
  coalesce(r.report->'generalInformation'->>'callStatus','') AS result,
  coalesce(r.report->'leadProfile'->'predictionsAndRecommendations'->'closingProbability'->>'percentage','') AS prob,
  coalesce(r.report->'performanceInsights'->'finalCloserEvaluation'->>'overallScore','') AS score
FROM ikigaigm.meetings m
LEFT JOIN ikigaigm.projects pr ON pr.id=m.project_id
LEFT JOIN ikigaigm.meeting_reports r ON r.meeting_id=m.id
LEFT JOIN LATERAL (
  SELECT trim(regexp_replace(p.name||' '||coalesce(p.lastname,''),'\s+',' ','g')) AS closer
  FROM ikigaigm.crm_contacts c
  JOIN ikigaigm.crm_opportunities o ON o.contact_id=c.id
  JOIN ikigaigm.users u ON u.id=o.user_id
  JOIN ikigaigm.persons p ON p.person_id=u.person_id
  WHERE c.ghl_contact_id = m.event->'booking'->>'contact_id'
  ORDER BY (o.project_id = m.project_id) DESC, o.created_date DESC NULLS LAST
  LIMIT 1
) cl ON true
WHERE $where
ORDER BY m.scheduled_start_time DESC NULLS LAST
$lim"

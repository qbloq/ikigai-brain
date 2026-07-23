#!/usr/bin/env bash
# Aggregate performance over ANALYZED sales calls (those with a report): calls,
# wins (Closed Won), win rate, average closing probability and average closer
# score, grouped by closer (default), result, program, project or week.
# The Director Comercial's KPI view — per-closer effectiveness.
#
# Usage:
#   call_stats.sh [--by closer|result|program|project|week] [--project NAME]
#                 [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--json]
#
#   --by DIM        grouping dimension (default: closer)
#   --project NAME  restrict to one project (client)
#   --from / --to   scheduled date range (Bogota tz)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

by="closer" project="" from="" to=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --by)      by="$2"; shift 2 ;;
    --project) project="$2"; shift 2 ;;
    --from)    from="$2"; shift 2 ;;
    --to)      to="$2"; shift 2 ;;
    --json)    FORMAT=json; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$by" in
  closer)  dim="coalesce(cl.closer,'(sin resolver)')" ;;
  result)  dim="coalesce(r.report->'generalInformation'->>'callStatus','—')" ;;
  program) dim="coalesce(r.report->'generalInformation'->>'program','—')" ;;
  project) dim="coalesce(pr.name,'—')" ;;
  week)    dim="to_char(date_trunc('week', m.scheduled_start_time),'YYYY-MM-DD')" ;;
  *) echo "--by inválido: '$by' (closer|result|program|project|week)" >&2; exit 2 ;;
esac

where="m.meeting_type='call' AND r.meeting_id IS NOT NULL"
[[ -n "$from" ]] && where="$where AND m.scheduled_start_time::date >= '${from//\'/}'"
[[ -n "$to" ]]   && where="$where AND m.scheduled_start_time::date <= '${to//\'/}'"
if [[ -n "$project" ]]; then
  pid="$(resolve_project "$project")"
  [[ -z "$pid" ]] && { echo "No project matches: $project" >&2; exit 1; }
  where="$where AND m.project_id = '$pid'"
fi

emit "SELECT $dim AS $by,
  count(*) AS calls,
  count(*) FILTER (WHERE r.report->'generalInformation'->>'callStatus' ILIKE 'closed won%') AS won,
  round(100.0 * count(*) FILTER (WHERE r.report->'generalInformation'->>'callStatus' ILIKE 'closed won%') / count(*), 1) AS win_pct,
  round(avg(nullif(r.report->'leadProfile'->'predictionsAndRecommendations'->'closingProbability'->>'percentage','')::numeric), 1) AS prob_avg,
  round(avg(nullif(r.report->'performanceInsights'->'finalCloserEvaluation'->>'overallScore','')::numeric), 1) AS score_avg
FROM meetings m
LEFT JOIN projects pr ON pr.id=m.project_id
JOIN meeting_reports r ON r.meeting_id=m.id
LEFT JOIN LATERAL (
  SELECT trim(regexp_replace(p.name||' '||coalesce(p.lastname,''),'\s+',' ','g')) AS closer
  FROM crm_contacts c
  JOIN crm_opportunities o ON o.contact_id=c.id
  JOIN users u ON u.id=o.user_id
  JOIN persons p ON p.person_id=u.person_id
  WHERE c.ghl_contact_id = m.event->'booking'->>'contact_id'
  ORDER BY (o.project_id = m.project_id) DESC, o.created_date DESC NULLS LAST
  LIMIT 1
) cl ON true
WHERE $where
GROUP BY 1
ORDER BY calls DESC"

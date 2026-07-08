#!/usr/bin/env bash
# Flatten OBJECTIONS across sales-call reports — the client's voice, one row
# per objection with how the closer answered and what the AI suggested. This
# is the feedback loop into narrative/copy work (S1) and objection-protocol
# design (S12.2 — the Director Comercial's SOP).
#
# Usage:
#   call_objections.sh [--project NAME] [--closer NAME] [--status overcome|pending]
#                      [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--limit N] [--json]
#
#   --status S      objection status fragment (Overcome / Not Overcome / ...)
#   --closer NAME   resolved closer name fragment
#   --limit N       cap rows (default 50; 0 = no cap)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

project="" closer="" ostatus="" from="" to="" limit="50"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) project="$2"; shift 2 ;;
    --closer)  closer="$2"; shift 2 ;;
    --status)  ostatus="$2"; shift 2 ;;
    --from)    from="$2"; shift 2 ;;
    --to)      to="$2"; shift 2 ;;
    --limit)   limit="$2"; shift 2 ;;
    --json)    FORMAT=json; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

esc() { printf '%s' "${1//\'/\'\'}"; }
where="m.meeting_type='call'"
[[ -n "$closer" ]]  && where="$where AND cl.closer ILIKE '%$(esc "$closer")%'"
[[ -n "$ostatus" ]] && where="$where AND o.value->>'status' ILIKE '%$(esc "$ostatus")%'"
[[ -n "$from" ]]    && where="$where AND m.scheduled_start_time::date >= '${from//\'/}'"
[[ -n "$to" ]]      && where="$where AND m.scheduled_start_time::date <= '${to//\'/}'"
if [[ -n "$project" ]]; then
  pid="$(resolve_project "$project")"
  [[ -z "$pid" ]] && { echo "No project matches: $project" >&2; exit 1; }
  where="$where AND m.project_id = '$pid'"
fi

[[ "$limit" == "0" ]] && limit=""
lim=""; [[ -n "$limit" ]] && lim="LIMIT $limit"

emit "SELECT left(m.id::text,8) AS call,
  to_char(m.scheduled_start_time,'YYYY-MM-DD') AS fecha,
  coalesce(r.report->'generalInformation'->>'leadName', split_part(m.name,' - ',1)) AS lead,
  coalesce(cl.closer,'—') AS closer,
  coalesce(o.value->>'status','—') AS status,
  o.value->>'objection' AS objection,
  o.value->>'closerResponse' AS closer_response,
  o.value->>'aiSuggestion' AS ai_suggestion
FROM ikigaigm.meetings m
JOIN ikigaigm.meeting_reports r ON r.meeting_id=m.id
CROSS JOIN LATERAL jsonb_array_elements(
  coalesce(r.report->'objectionsAndInsights'->'objectionHandling'->'objections','[]'::jsonb)
) o(value)
LEFT JOIN LATERAL (
  SELECT trim(regexp_replace(p.name||' '||coalesce(p.lastname,''),'\s+',' ','g')) AS closer
  FROM ikigaigm.crm_contacts c
  JOIN ikigaigm.crm_opportunities op ON op.contact_id=c.id
  JOIN ikigaigm.users u ON u.id=op.user_id
  JOIN ikigaigm.persons p ON p.person_id=u.person_id
  WHERE c.ghl_contact_id = m.event->'booking'->>'contact_id'
  ORDER BY (op.project_id = m.project_id) DESC, op.created_date DESC NULLS LAST
  LIMIT 1
) cl ON true
WHERE $where
ORDER BY m.scheduled_start_time DESC
$lim"

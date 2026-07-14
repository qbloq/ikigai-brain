#!/usr/bin/env bash
# CRM pipeline view over GHL opportunities: distribution across the pipeline's
# stages (resolved from crm_pipelines.stages jsonb, in board order), by status,
# by month, or the raw opportunity list. Caveat: open opportunities carry
# monetary_value ≈ 0 in this CRM — counts are meaningful, forecast value isn't;
# won value IS real.
#
# Usage:
#   pipeline.sh [--by stage|status|month|closer] [--list]
#               [--project NAME] [--status S] [--stage FRAG]
#               [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--limit N] [--json]
#
#   --by DIM       aggregate dimension (default: stage, in pipeline order)
#   --list         row list instead of aggregates (lead, stage, status, value)
#   --status S     open | won | lost | abandoned
#   --stage FRAG   filter by stage name fragment (list mode)
#   --from / --to  opportunity created_date window (default: all history)
#   --limit N      list mode only; default 100, 0 = no cap
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

by="stage" list=0 project="" status="" stage="" from="" to="" limit=100
while [[ $# -gt 0 ]]; do
  case "$1" in
    --by)      by="$2"; shift 2 ;;
    --list)    list=1; shift ;;
    --project) project="$2"; shift 2 ;;
    --status)  status="$2"; shift 2 ;;
    --stage)   stage="$2"; shift 2 ;;
    --from)    from="$2"; shift 2 ;;
    --to)      to="$2"; shift 2 ;;
    --limit)   limit="$2"; shift 2 ;;
    --json)    FORMAT=json; shift ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Stage name + board position resolved from the pipeline's stages jsonb.
STAGE_SQL="(SELECT s.elem->>'name' FROM jsonb_array_elements(pl.stages) s(elem)
            WHERE s.elem->>'id' = o.ghl_stage_id)"
STAGE_POS="(SELECT (s.elem->>'position')::int FROM jsonb_array_elements(pl.stages) s(elem)
            WHERE s.elem->>'id' = o.ghl_stage_id)"
CLOSER_SQL="(SELECT trim(coalesce(p.name,'')||' '||coalesce(p.lastname,''))
             FROM ikigaigm.users u JOIN ikigaigm.persons p ON p.person_id=u.person_id
             WHERE u.id = o.user_id)"

where="true"
[[ -n "$status" ]] && where="$where AND o.status = '${status//\'/\'\'}'"
[[ -n "$stage" ]]  && where="$where AND $STAGE_SQL ILIKE '%${stage//\'/\'\'}%'"
[[ -n "$from" ]]   && where="$where AND o.created_date::date >= '${from//\'/}'"
[[ -n "$to" ]]     && where="$where AND o.created_date::date <= '${to//\'/}'"
if [[ -n "$project" ]]; then
  pid="$(resolve_project "$project")"
  [[ -z "$pid" ]] && { echo "No project matches: $project" >&2; exit 1; }
  where="$where AND o.project_id = '$pid'"
fi

FROMJOIN="FROM ikigaigm.crm_opportunities o
LEFT JOIN ikigaigm.crm_pipelines pl ON pl.id = o.pipeline_id
LEFT JOIN ikigaigm.projects pr ON pr.id = o.project_id"

if [[ "$list" == 1 ]]; then
  lim=""; [[ "$limit" != 0 ]] && lim="LIMIT $limit"
  emit "SELECT left(o.id::text, 8)              AS id,
         left(coalesce(o.name,'—'), 36)         AS opportunity,
         coalesce(pr.name,'—')                  AS project,
         coalesce($STAGE_SQL,'—')               AS stage,
         o.status,
         o.monetary_value                       AS value,
         coalesce($CLOSER_SQL, o.assigned_to)   AS assigned,
         to_char(o.created_date,'YYYY-MM-DD')   AS created,
         to_char(o.last_status_change_at,'YYYY-MM-DD') AS last_change
  $FROMJOIN
  WHERE $where
  ORDER BY o.created_date DESC
  $lim"
else
  case "$by" in
    stage)
      emit "SELECT coalesce(pr.name,'—') AS project,
             coalesce($STAGE_SQL,'(sin stage)') AS stage,
             count(*) AS opps,
             count(*) FILTER (WHERE o.status='open')  AS open,
             count(*) FILTER (WHERE o.status='won')   AS won,
             count(*) FILTER (WHERE o.status='lost')  AS lost,
             count(*) FILTER (WHERE o.status='abandoned') AS abandoned,
             round(coalesce(sum(o.monetary_value) FILTER (WHERE o.status='won'),0)) AS won_value
      $FROMJOIN
      WHERE $where
      GROUP BY pr.name, 2, $STAGE_POS
      ORDER BY pr.name, $STAGE_POS NULLS LAST" ;;
    status)
      emit "SELECT o.status, count(*) AS opps,
             round(coalesce(sum(o.monetary_value),0)) AS value,
             round(100.0*count(*)/sum(count(*)) OVER (), 1) AS pct
      $FROMJOIN WHERE $where GROUP BY 1 ORDER BY opps DESC" ;;
    month)
      emit "SELECT to_char(date_trunc('month', o.created_date),'YYYY-MM') AS month,
             count(*) AS created,
             count(*) FILTER (WHERE o.status='won') AS won,
             round(100.0*count(*) FILTER (WHERE o.status='won')/count(*), 1) AS win_pct,
             round(coalesce(sum(o.monetary_value) FILTER (WHERE o.status='won'),0)) AS won_value
      $FROMJOIN WHERE $where GROUP BY 1 ORDER BY 1" ;;
    closer)
      emit "SELECT coalesce($CLOSER_SQL,'(sin asignar)') AS closer,
             count(*) AS opps,
             count(*) FILTER (WHERE o.status='won') AS won,
             round(100.0*count(*) FILTER (WHERE o.status='won')/count(*), 1) AS win_pct,
             round(coalesce(sum(o.monetary_value) FILTER (WHERE o.status='won'),0)) AS won_value
      $FROMJOIN WHERE $where GROUP BY 1 ORDER BY won_value DESC" ;;
    *) echo "--by inválido: '$by' (stage|status|month|closer)" >&2; exit 2 ;;
  esac
fi

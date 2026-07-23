#!/usr/bin/env bash
# Aggregate Meta ads performance over ad_insights_daily: spend, impressions,
# clicks, CTR, CPC, CPM, purchases, purchase value, ROAS and CPA — grouped by
# campaign (default), adset, ad, day, week, project or account. Ratios are
# recomputed from the summed columns, never averaged from daily ratios.
#
# Usage:
#   ad_stats.sh [--by campaign|adset|ad|day|week|project|account]
#               [--project NAME] [--account ID] [--campaign ID|NAME]
#               [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--limit N] [--json]
#
#   --by DIM         grouping dimension (default: campaign)
#   --project NAME   restrict to one project (client), via account mapping
#   --account ID     restrict to one ad account
#   --campaign TOK   restrict to one campaign (id prefix or name fragment);
#                    natural companion of --by adset / --by ad
#   --from / --to    date window (default: current month, Bogota tz)
#   --limit N        default 50; 0 = no cap
#
# Every row carries the account currency (`cur`) and rows group per currency —
# COP and USD never blend into one number.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

by="campaign" project="" account="" campaign="" limit=50
from="$(TZ="$TZ_DEFAULT" date +%Y-%m-01)"
to="$(TZ="$TZ_DEFAULT" date +%Y-%m-%d)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --by)       by="$2"; shift 2 ;;
    --project)  project="$2"; shift 2 ;;
    --account)  account="$2"; shift 2 ;;
    --campaign) campaign="$2"; shift 2 ;;
    --from)     from="$2"; shift 2 ;;
    --to)       to="$2"; shift 2 ;;
    --limit)    limit="$2"; shift 2 ;;
    --json)     FORMAT=json; shift ;;
    -h|--help)  sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

order="spend DESC"
case "$by" in
  campaign) dim="coalesce(c.name,'—')" ;;
  adset)    dim="coalesce(s.name,'—')" ;;
  ad)       dim="coalesce(ad.name,'—')" ;;
  day)      dim="to_char(d.date_start,'YYYY-MM-DD')"; order="1" ;;
  week)     dim="to_char(date_trunc('week', d.date_start),'YYYY-MM-DD')"; order="1" ;;
  project)  dim="coalesce(pr.name,'(sin mapear)')" ;;
  account)  dim="a.name" ;;
  *) echo "--by inválido: '$by' (campaign|adset|ad|day|week|project|account)" >&2; exit 2 ;;
esac

where="d.date_start BETWEEN '${from//\'/}' AND '${to//\'/}'"
[[ -n "$account" ]] && where="$where AND d.ad_account_id = '${account//\'/\'\'}'"
if [[ -n "$project" ]]; then
  pid="$(resolve_project "$project")"
  [[ -z "$pid" ]] && { echo "No project matches: $project" >&2; exit 1; }
  where="$where AND map.project_id = '$pid'"
fi
if [[ -n "$campaign" ]]; then
  esc="${campaign//\'/\'\'}"
  where="$where AND (d.campaign_id LIKE '${esc}%' OR c.name ILIKE '%${esc}%')"
fi
lim=""; [[ "$limit" != 0 ]] && lim="LIMIT $limit"

emit "SELECT $dim AS $by,
       a.currency                                   AS cur,
       round(sum(d.spend),2)                        AS spend,
       sum(d.impressions)                           AS impr,
       sum(d.clicks)                                AS clicks,
       round(100.0*sum(d.clicks)/nullif(sum(d.impressions),0), 2) AS ctr_pct,
       round(sum(d.spend)/nullif(sum(d.clicks),0), 2)             AS cpc,
       round(1000.0*sum(d.spend)/nullif(sum(d.impressions),0), 2) AS cpm,
       sum(d.landing_page_views)                    AS lpv,
       sum(d.purchases)                             AS purchases,
       round(sum(d.purchase_value),2)               AS purchase_value,
       round(sum(d.purchase_value)/nullif(sum(d.spend),0), 2)     AS roas,
       round(sum(d.spend)/nullif(sum(d.purchases),0), 2)          AS cpa
FROM ikigaigm.ad_insights_daily d
JOIN ikigaigm.ad_accounts a ON a.id = d.ad_account_id
LEFT JOIN ikigaigm.campaigns c ON c.id = d.campaign_id
LEFT JOIN ikigaigm.ad_sets s ON s.id = d.ad_set_id
LEFT JOIN ikigaigm.ads ad ON ad.id = d.ad_id
LEFT JOIN ikigaigm.project_ad_account_mappings map ON map.ad_account_id = d.ad_account_id
LEFT JOIN ikigaigm.projects pr ON pr.id = map.project_id
WHERE $where
GROUP BY 1, a.currency
ORDER BY $order
$lim"

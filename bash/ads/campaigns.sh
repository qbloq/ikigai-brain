#!/usr/bin/env bash
# List Meta ad campaigns with resolved project (via ad-account mapping),
# account currency, budget and period performance. Read-only.
#
# Usage:
#   campaigns.sh [--status S] [--active] [--project NAME] [--account ID]
#                [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--with-spend]
#                [--limit N] [--json]
#
#   --status S      Meta status (ACTIVE | PAUSED | ...)
#   --active        shortcut for --status ACTIVE
#   --project NAME  restrict to one project (client), via account mapping
#   --account ID    restrict to one ad account
#   --from / --to   performance window (default: current month, Bogota tz)
#   --with-spend    only campaigns with spend > 0 in the window
#   --limit N       default 50; 0 = no cap
#
# Money columns (budget, spend, purchase_value) are in the ACCOUNT'S currency
# (`cur`) — COP and USD coexist, never sum across rows with different `cur`.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

status="" project="" account="" with_spend=0 limit=50
from="$(TZ="$TZ_DEFAULT" date +%Y-%m-01)"
to="$(TZ="$TZ_DEFAULT" date +%Y-%m-%d)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --status)     status="$2"; shift 2 ;;
    --active)     status="ACTIVE"; shift ;;
    --project)    project="$2"; shift 2 ;;
    --account)    account="$2"; shift 2 ;;
    --from)       from="$2"; shift 2 ;;
    --to)         to="$2"; shift 2 ;;
    --with-spend) with_spend=1; shift ;;
    --limit)      limit="$2"; shift 2 ;;
    --json)       FORMAT=json; shift ;;
    -h|--help)    sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

where="true"
[[ -n "$status" ]]  && where="$where AND c.status = upper('${status//\'/\'\'}')"
[[ -n "$account" ]] && where="$where AND c.ad_account_id = '${account//\'/\'\'}'"
if [[ -n "$project" ]]; then
  pid="$(resolve_project "$project")"
  [[ -z "$pid" ]] && { echo "No project matches: $project" >&2; exit 1; }
  where="$where AND map.project_id = '$pid'"
fi
[[ "$with_spend" == 1 ]] && where="$where AND coalesce(i.spend,0) > 0"
lim=""; [[ "$limit" != 0 ]] && lim="LIMIT $limit"

emit "SELECT c.id,
       left(c.name, 44)                        AS campaign,
       coalesce(pr.name,'—')                   AS project,
       a.currency                              AS cur,
       c.status,
       c.daily_budget                          AS budget_d,
       coalesce(i.spend,0)                     AS spend,
       coalesce(i.purchases,0)                 AS purchases,
       coalesce(i.purchase_value,0)            AS purchase_value,
       CASE WHEN coalesce(i.spend,0) > 0
            THEN round(coalesce(i.purchase_value,0) / i.spend, 2) END AS roas,
       to_char(i.last_day,'YYYY-MM-DD')        AS last_data
FROM ikigaigm.campaigns c
JOIN ikigaigm.ad_accounts a ON a.id = c.ad_account_id
LEFT JOIN ikigaigm.project_ad_account_mappings map ON map.ad_account_id = c.ad_account_id
LEFT JOIN ikigaigm.projects pr ON pr.id = map.project_id
LEFT JOIN LATERAL (
  SELECT round(sum(d.spend),2)          AS spend,
         sum(d.purchases)               AS purchases,
         round(sum(d.purchase_value),2) AS purchase_value,
         max(d.date_start)              AS last_day
  FROM ikigaigm.ad_insights_daily d
  WHERE d.campaign_id = c.id
    AND d.date_start BETWEEN '${from//\'/}' AND '${to//\'/}'
) i ON true
WHERE $where
ORDER BY coalesce(i.spend,0) DESC, c.status, c.updated_time DESC
$lim"

#!/usr/bin/env bash
# Full detail of ONE Meta campaign: header (account, project, status, budget),
# window totals, per-adset and top-ads breakdowns, and the daily series.
#
# Usage:
#   ad_detail.sh <campaign-id|prefix|name-fragment>
#                [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--days N] [--json]
#
#   --from / --to   window (default: the campaign's whole life)
#   --days N        daily series shows the last N days WITH data (default 14)
#   --json          one JSON object {campaign, totals, adsets[], ads[], daily[]}
#
# Money is in the account's currency (shown in the header). Read-only.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

tok="" from="2000-01-01" days=14
to="$(TZ="$TZ_DEFAULT" date +%Y-%m-%d)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)    from="$2"; shift 2 ;;
    --to)      to="$2"; shift 2 ;;
    --days)    days="$2"; shift 2 ;;
    --json)    FORMAT=json; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) tok="$1"; shift ;;
  esac
done
[[ -n "$tok" ]] || { echo "Usage: ad_detail.sh <campaign-id|prefix|name-fragment>" >&2; exit 2; }

esc="${tok//\'/\'\'}"
rows="$(psql_ro -t -A -F'|' -c "
  SELECT c.id, c.name, c.status FROM ikigaigm.campaigns c
  WHERE c.id LIKE '${esc}%' OR c.name ILIKE '%${esc}%'
  ORDER BY c.updated_time DESC")"
[[ -n "$rows" ]] || { echo "No campaign matches '$tok'" >&2; exit 1; }
n="$(printf '%s\n' "$rows" | grep -c .)"
if [[ "$n" -gt 1 ]]; then
  { echo "'$tok' is ambiguous ($n matches):"
    printf '%s\n' "$rows" | awk -F'|' '{printf "   %s  %-52s %s\n", $1, substr($2,1,52), $3}'
    echo "Refine the name or pass the id."; } >&2
  exit 1
fi
cid="$(printf '%s\n' "$rows" | cut -d'|' -f1)"

f="${from//\'/}" t="${to//\'/}"

HEADER_SQL="SELECT c.id, c.name AS campaign, c.status, c.objective,
       a.name AS account, a.currency AS cur, coalesce(pr.name,'—') AS project,
       c.daily_budget AS budget_d, c.lifetime_budget,
       to_char(c.start_time,'YYYY-MM-DD') AS started,
       to_char(c.stop_time,'YYYY-MM-DD')  AS stopped
FROM ikigaigm.campaigns c
JOIN ikigaigm.ad_accounts a ON a.id = c.ad_account_id
LEFT JOIN ikigaigm.project_ad_account_mappings map ON map.ad_account_id = c.ad_account_id
LEFT JOIN ikigaigm.projects pr ON pr.id = map.project_id
WHERE c.id = '$cid'"

# Shared aggregate column list over ad_insights_daily alias d.
AGG="round(sum(d.spend),2)                        AS spend,
     sum(d.impressions)                           AS impr,
     sum(d.clicks)                                AS clicks,
     round(100.0*sum(d.clicks)/nullif(sum(d.impressions),0), 2) AS ctr_pct,
     round(sum(d.spend)/nullif(sum(d.clicks),0), 2)             AS cpc,
     round(1000.0*sum(d.spend)/nullif(sum(d.impressions),0), 2) AS cpm,
     sum(d.purchases)                             AS purchases,
     round(sum(d.purchase_value),2)               AS purchase_value,
     round(sum(d.purchase_value)/nullif(sum(d.spend),0), 2)     AS roas"
IN_WINDOW="d.campaign_id = '$cid' AND d.date_start BETWEEN '$f' AND '$t'"

TOTALS_SQL="SELECT to_char(min(d.date_start),'YYYY-MM-DD') AS first_day,
       to_char(max(d.date_start),'YYYY-MM-DD') AS last_day, $AGG
FROM ikigaigm.ad_insights_daily d WHERE $IN_WINDOW"

ADSETS_SQL="SELECT coalesce(s.name,'—') AS adset, s.status, s.daily_budget AS budget_d,
       s.optimization_goal, $AGG
FROM ikigaigm.ad_insights_daily d
LEFT JOIN ikigaigm.ad_sets s ON s.id = d.ad_set_id
WHERE $IN_WINDOW
GROUP BY s.id, s.name, s.status, s.daily_budget, s.optimization_goal
ORDER BY sum(d.spend) DESC"

ADS_SQL="SELECT left(coalesce(ad.name,'—'), 56) AS ad, ad.status, $AGG
FROM ikigaigm.ad_insights_daily d
LEFT JOIN ikigaigm.ads ad ON ad.id = d.ad_id
WHERE $IN_WINDOW
GROUP BY ad.id, ad.name, ad.status
ORDER BY sum(d.spend) DESC
LIMIT 15"

DAILY_SQL="SELECT to_char(d.date_start,'YYYY-MM-DD') AS day, $AGG
FROM ikigaigm.ad_insights_daily d
WHERE $IN_WINDOW
GROUP BY d.date_start
ORDER BY d.date_start DESC
LIMIT ${days//\'/}"

if [[ "$FORMAT" == "json" ]]; then
  psql_ro -t -A -c "SELECT json_build_object(
    'campaign', (SELECT row_to_json(_h) FROM ($HEADER_SQL) _h),
    'totals',   (SELECT row_to_json(_t) FROM ($TOTALS_SQL) _t),
    'adsets',   (SELECT coalesce(json_agg(row_to_json(_s)), '[]'::json) FROM ($ADSETS_SQL) _s),
    'ads',      (SELECT coalesce(json_agg(row_to_json(_a)), '[]'::json) FROM ($ADS_SQL) _a),
    'daily',    (SELECT coalesce(json_agg(row_to_json(_d)), '[]'::json)
                 FROM (SELECT * FROM ($DAILY_SQL) _x ORDER BY day) _d)
  );"
else
  echo "== Campaña =="
  psql_ro -x -c "$HEADER_SQL;"
  echo; echo "== Totales ($f → $t) =="
  psql_ro -c "$TOTALS_SQL;"
  echo; echo "== Ad sets =="
  psql_ro -c "$ADSETS_SQL;"
  echo; echo "== Top ads (por gasto, máx 15) =="
  psql_ro -c "$ADS_SQL;"
  echo; echo "== Serie diaria (últimos $days días con data) =="
  psql_ro -c "SELECT * FROM ($DAILY_SQL) _d ORDER BY day;"
fi

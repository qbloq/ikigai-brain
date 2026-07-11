#!/usr/bin/env bash
# Financial KPI dashboard for one project over a date range (cash-collected
# model). Emits the full set of KPIs the cards view renders. Read-only,
# scoped to ikigaigm, dates evaluated in America/Bogota.
#
# Usage:  dashboard.sh [--project NAME] [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--json]
#   defaults: --project "David Guerrero", current calendar month.
#
# KPIs (see docs): ingresos brutos = cuotas pagadas en el período (1ª + ≥2);
# venta_programas = valor de contrato de planes iniciados; pauta = ad spend;
# costos = comisiones de cierre + gastos; reparto vía revenue_share_rules.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

project="David Guerrero"
from="$(TZ="$TZ_DEFAULT" date +%Y-%m-01)"
to="$(TZ="$TZ_DEFAULT" date -d "$(TZ="$TZ_DEFAULT" date +%Y-%m-01) +1 month -1 day" +%Y-%m-%d)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) project="$2"; shift 2 ;;
    --from)    from="$2"; shift 2 ;;
    --to)      to="$2"; shift 2 ;;
    --json)    FORMAT=json; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

pid="$(resolve_project "$project")"
[[ -n "$pid" ]] || { echo "No project matched: $project" >&2; exit 1; }

# One single-row CTE `m` holds every KPI (raw + derived). row_to_json(m) is the
# object the viz component consumes; `SELECT * FROM m` (expanded) is the human view.
read -r -d '' BODY <<'SQL' || true
WITH params AS (
  SELECT :'proj'::uuid AS pid, :'d1'::date AS d1, :'d2'::date AS d2
),
inst AS (   -- installments collected (cash) in the period, for this project
  SELECT i.installment_number AS n, i.paid_amount AS amt
  FROM ikigaigm.installments i
  JOIN ikigaigm.payment_plans pp ON pp.plan_id = i.plan_id
  JOIN params ON pp.project_id = params.pid
  WHERE i.payment_date IS NOT NULL
    AND i.payment_date::date BETWEEN params.d1 AND params.d2
),
agg_inst AS (
  SELECT
    count(*) FILTER (WHERE n = 1)                          AS nuevas_n,
    coalesce(sum(amt) FILTER (WHERE n = 1), 0)             AS nuevas_amt,
    count(*) FILTER (WHERE n >= 2)                         AS cuotas_n,
    coalesce(sum(amt) FILTER (WHERE n >= 2), 0)            AS cuotas_amt
  FROM inst
),
ventaprog AS (   -- bookings: contract value of plans started in the period
  SELECT coalesce(sum(pp.original_amount), 0) AS venta_programas
  FROM ikigaigm.payment_plans pp JOIN params ON pp.project_id = params.pid
  WHERE pp.start_date BETWEEN params.d1 AND params.d2
),
pauta AS (   -- ad spend + Meta-reported purchase value (via ad-account mapping)
  SELECT coalesce(sum(a.spend), 0)          AS pauta,
         coalesce(sum(a.purchase_value), 0) AS purchase_value
  FROM ikigaigm.ad_insights_daily a
  JOIN ikigaigm.project_ad_account_mappings map ON map.ad_account_id = a.ad_account_id
  JOIN params ON map.project_id = params.pid
  WHERE a.date_start BETWEEN params.d1 AND params.d2
),
comis AS (   -- closing commissions tied to installments collected in the period
  SELECT coalesce(sum(cp.payout_amount_base), 0) AS comisiones
  FROM ikigaigm.commission_payouts cp
  JOIN ikigaigm.installments i ON i.installment_id = cp.installment_id
  JOIN params ON cp.project_id = params.pid
  WHERE i.payment_date::date BETWEEN params.d1 AND params.d2
),
gastos AS (
  SELECT coalesce(sum(e.amount_base), 0) AS gastos
  FROM ikigaigm.expenses e JOIN params ON e.project_id = params.pid
  WHERE e.expense_date BETWEEN params.d1 AND params.d2
),
leads AS (
  SELECT count(*) AS leads
  FROM ikigaigm.crm_opportunities o JOIN params ON o.project_id = params.pid
  WHERE o.created_date::date BETWEEN params.d1 AND params.d2
),
shares AS (   -- revenue-share split active in the period (Ikigai vs project owner)
  SELECT
    coalesce(max(rsr.share_pct) FILTER (WHERE p.name ILIKE '%ikigai%'), 0)     AS ikigai_share,
    coalesce(max(rsr.share_pct) FILTER (WHERE p.name NOT ILIKE '%ikigai%'), 0) AS owner_share,
    coalesce(max(trim(coalesce(p.name,'')||' '||coalesce(p.lastname,'')))
             FILTER (WHERE p.name NOT ILIKE '%ikigai%'), 'Socio')              AS owner_name
  FROM ikigaigm.revenue_share_rules rsr
  LEFT JOIN ikigaigm.users u ON u.id = rsr.user_id
  LEFT JOIN ikigaigm.persons p ON p.person_id = u.person_id
  JOIN params ON rsr.project_id = params.pid
  WHERE rsr.effective_from <= params.d2
    AND (rsr.effective_to IS NULL OR rsr.effective_to >= params.d1)
),
base AS (
  SELECT :'projname'::text AS project, :'d1'::date AS period_from, :'d2'::date AS period_to,
         agg_inst.*, ventaprog.*, pauta.*, comis.*, gastos.*, leads.*, shares.*
  FROM agg_inst, ventaprog, pauta, comis, gastos, leads, shares
),
m AS (
  SELECT
    project, period_from, period_to,
    -- unidades / ingresos
    nuevas_n, round(nuevas_amt, 2) AS nuevas_amt,
    cuotas_n, round(cuotas_amt, 2) AS cuotas_amt,
    (nuevas_n + cuotas_n)                       AS num_ventas,
    round(nuevas_amt + cuotas_amt, 2)           AS ingresos_brutos,
    round((nuevas_amt + cuotas_amt) / nullif(nuevas_n + cuotas_n, 0), 2) AS ticket_promedio,
    round(venta_programas, 2)                   AS venta_programas,
    -- costos / pauta
    round(comisiones, 2)                        AS comisiones,
    round(gastos, 2)                            AS gastos,
    round(comisiones + gastos, 2)               AS costos,
    round(pauta, 2)                             AS pauta,
    -- resultados
    round((nuevas_amt + cuotas_amt) - (comisiones + gastos), 2)                 AS ingreso_neto,
    round((nuevas_amt + cuotas_amt) - (comisiones + gastos) - pauta, 2)         AS profit_post_pauta,
    round(((nuevas_amt + cuotas_amt) - (comisiones + gastos) - pauta)
          / nullif(nuevas_amt + cuotas_amt, 0), 4)                              AS margen,
    -- reparto
    owner_name,
    round((((nuevas_amt + cuotas_amt) - (comisiones + gastos) - pauta) * ikigai_share), 2) AS neto_ikigai,
    round((((nuevas_amt + cuotas_amt) - (comisiones + gastos) - pauta) * owner_share), 2)  AS neto_owner,
    -- eficiencia de pauta
    round((nuevas_amt + cuotas_amt) / nullif(pauta, 0), 2)  AS roas,
    round(purchase_value / nullif(pauta, 0), 2)             AS roas_funnel,
    leads,
    round(pauta / nullif(leads, 0), 2)                      AS cpl
  FROM base
)
SQL

# NOTE: psql interpolates :'vars' only from a file/stdin, not from -c. Feed via stdin.
if [[ "$FORMAT" == "json" ]]; then
  printf '%s\nSELECT row_to_json(m) FROM m;\n' "$BODY" \
    | psql_ro -t -A -v proj="$pid" -v projname="$project" -v d1="$from" -v d2="$to"
else
  printf '%s\nSELECT * FROM m;\n' "$BODY" \
    | psql_ro -x -v proj="$pid" -v projname="$project" -v d1="$from" -v d2="$to"
fi

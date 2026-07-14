#!/usr/bin/env bash
# Executive portfolio: the dashboard.sh KPI model for ALL projects side by
# side, one row per project plus a TOTAL row. Cash-collected model (same
# formulas as bash/metrics/dashboard.sh): ingresos = cuotas cobradas en el
# período; venta_programas = valor de contrato de planes iniciados; costos =
# comisiones (por cuota cobrada) + gastos; profit = ingresos − costos − pauta.
#
# Usage:  portfolio.sh [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--json]
#   default window: current calendar month (Bogota).
#
# All money is USD except `pauta_cop` (COP ad accounts: Andrea/Floppy), which
# is reported apart and NOT subtracted from profit — only `pauta_usd` is.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

from="$(TZ="$TZ_DEFAULT" date +%Y-%m-01)"
to="$(TZ="$TZ_DEFAULT" date +%Y-%m-%d)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)    from="$2"; shift 2 ;;
    --to)      to="$2"; shift 2 ;;
    --json)    FORMAT=json; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
d1="${from//\'/}" d2="${to//\'/}"

emit "WITH inst AS (
  SELECT pp.project_id, i.installment_number AS n, i.paid_amount AS amt
  FROM ikigaigm.installments i
  JOIN ikigaigm.payment_plans pp ON pp.plan_id = i.plan_id
  WHERE i.payment_date IS NOT NULL
    AND i.payment_date::date BETWEEN '$d1' AND '$d2'
),
per_project AS (
  SELECT p.name AS project,
    coalesce((SELECT count(*) FROM inst WHERE inst.project_id=p.id AND n=1),0)  AS nuevas_n,
    coalesce((SELECT sum(amt) FROM inst WHERE inst.project_id=p.id AND n=1),0)  AS nuevas_amt,
    coalesce((SELECT count(*) FROM inst WHERE inst.project_id=p.id AND n>=2),0) AS cuotas_n,
    coalesce((SELECT sum(amt) FROM inst WHERE inst.project_id=p.id AND n>=2),0) AS cuotas_amt,
    coalesce((SELECT sum(pp.original_amount) FROM ikigaigm.payment_plans pp
              WHERE pp.project_id=p.id AND pp.start_date BETWEEN '$d1' AND '$d2'),0) AS venta_programas,
    coalesce((SELECT sum(cp.payout_amount_base) FROM ikigaigm.commission_payouts cp
              JOIN ikigaigm.installments i2 ON i2.installment_id = cp.installment_id
              WHERE cp.project_id=p.id AND i2.payment_date::date BETWEEN '$d1' AND '$d2'),0) AS comisiones,
    coalesce((SELECT sum(e.amount_base) FROM ikigaigm.expenses e
              WHERE e.project_id=p.id AND e.expense_date BETWEEN '$d1' AND '$d2'),0) AS gastos,
    coalesce((SELECT sum(d.spend) FROM ikigaigm.ad_insights_daily d
              JOIN ikigaigm.project_ad_account_mappings map ON map.ad_account_id=d.ad_account_id
              JOIN ikigaigm.ad_accounts a ON a.id=d.ad_account_id
              WHERE map.project_id=p.id AND a.currency='USD'
                AND d.date_start BETWEEN '$d1' AND '$d2'),0) AS pauta_usd,
    coalesce((SELECT sum(d.spend) FROM ikigaigm.ad_insights_daily d
              JOIN ikigaigm.project_ad_account_mappings map ON map.ad_account_id=d.ad_account_id
              JOIN ikigaigm.ad_accounts a ON a.id=d.ad_account_id
              WHERE map.project_id=p.id AND a.currency='COP'
                AND d.date_start BETWEEN '$d1' AND '$d2'),0) AS pauta_cop,
    coalesce((SELECT count(*) FROM ikigaigm.crm_opportunities o
              WHERE o.project_id=p.id AND o.created_date::date BETWEEN '$d1' AND '$d2'),0) AS leads
  FROM ikigaigm.projects p
),
with_total AS (
  SELECT 0 AS ord, * FROM per_project
  UNION ALL
  SELECT 1, '— TOTAL —', sum(nuevas_n), sum(nuevas_amt), sum(cuotas_n), sum(cuotas_amt),
         sum(venta_programas), sum(comisiones), sum(gastos), sum(pauta_usd), sum(pauta_cop), sum(leads)
  FROM per_project
)
SELECT project,
       nuevas_n, cuotas_n,
       round(nuevas_amt + cuotas_amt, 2)                          AS ingresos,
       round(venta_programas, 2)                                  AS venta_prog,
       round(comisiones, 2)                                       AS comisiones,
       round(gastos, 2)                                           AS gastos,
       round(nuevas_amt + cuotas_amt - comisiones - gastos, 2)    AS ingreso_neto,
       round(pauta_usd, 2)                                        AS pauta_usd,
       round(pauta_cop, 0)                                        AS pauta_cop,
       round(nuevas_amt + cuotas_amt - comisiones - gastos - pauta_usd, 2) AS profit,
       round(100 * (nuevas_amt + cuotas_amt - comisiones - gastos - pauta_usd)
             / nullif(nuevas_amt + cuotas_amt, 0), 1)              AS margen_pct,
       round((nuevas_amt + cuotas_amt) / nullif(pauta_usd, 0), 2) AS roas_real,
       leads,
       round(pauta_usd / nullif(leads, 0), 2)                     AS cpl_usd
FROM with_total
ORDER BY ord, ingresos DESC"

#!/usr/bin/env bash
# ventas_diarias.sh — LA SERIE DIARIA de un proyecto: una fila por día de la
# ventana con el dinero que entró (caja), la pauta del día (USD), los leads y
# las ganadas del CRM y los planes iniciados. Es el «ventas diarias» del
# dashboard comercial (qué día vendimos más, cómo va la semana, cash vs pauta
# por día) con las mismas reglas que dashboard.sh/embudo.sh:
#   - caja = installments pagadas por payment_date (día Bogotá); nuevas = cuota 1,
#     cuotas = n≥2 — nunca el pixel ni el valor del contrato.
#   - pauta = ad_insights_daily vía project_ad_account_mappings, SOLO USD (la COP
#     no entra a los ratios); roas_dia = cash / spend del MISMO día, que es una
#     lectura de ritmo, no de atribución (el cash de hoy viene de pauta de antes).
#   - leads = crm_opportunities.created_date; ganadas = won por
#     last_status_change_at; planes = payment_plans.start_date sin Cancelled.
#   - la serie termina HOY aunque --to sea futuro: no se inventan días.
#
# Uso: ventas_diarias.sh --project NAME [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--json]
#   default: el mes calendario en curso (Bogotá). Read-only. Emite filas
#   (fuente viz `ventas_diarias`, UI ejecutivo `ventas-diarias`).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

project=""
from="$(TZ="$TZ_DEFAULT" date +%Y-%m-01)"
_y="$(TZ="$TZ_DEFAULT" date +%Y)" _m="$(TZ="$TZ_DEFAULT" date +%m)"
case "${_m#0}" in
  4|6|9|11) _d=30 ;;
  2) _d=28; (( (_y % 4 == 0 && _y % 100 != 0) || _y % 400 == 0 )) && _d=29 ;;
  *) _d=31 ;;
esac
to="${_y}-${_m}-${_d}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) project="$2"; shift 2 ;;
    --from)    from="$2"; shift 2 ;;
    --to)      to="$2"; shift 2 ;;
    --json)    FORMAT=json; shift ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$project" ]] || { echo "Falta --project NAME" >&2; exit 2; }
for d in "$from" "$to"; do
  [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "Fecha inválida: $d (YYYY-MM-DD)" >&2; exit 2; }
done
pid="$(resolve_project "$project")"
[[ -n "$pid" ]] || { echo "No project matched: $project" >&2; exit 1; }
[[ "$pid" =~ ^[0-9a-f-]{36}$ ]] || { echo "pid raro: $pid" >&2; exit 1; }

emit "WITH params AS (
  SELECT '$pid'::uuid AS pid, '$from'::date AS d1, least('$to'::date, current_date) AS d2
),
dias AS (SELECT generate_series(d1, d2, interval '1 day')::date AS dia FROM params),
inst AS (
  SELECT i.payment_date::date AS dia, i.installment_number AS n, i.paid_amount AS amt
  FROM installments i
  JOIN payment_plans pp ON pp.plan_id = i.plan_id
  JOIN params ON pp.project_id = params.pid
  WHERE i.payment_date IS NOT NULL AND i.payment_date::date BETWEEN params.d1 AND params.d2
),
caja AS (
  SELECT dia,
         count(*) FILTER (WHERE n = 1)              AS nuevas_n,
         coalesce(sum(amt) FILTER (WHERE n = 1), 0) AS nuevas_amt,
         count(*) FILTER (WHERE n >= 2)             AS cuotas_n,
         coalesce(sum(amt) FILTER (WHERE n >= 2), 0) AS cuotas_amt
  FROM inst GROUP BY 1
),
pauta AS (
  SELECT a.date_start AS dia, sum(a.spend) AS spend, sum(a.purchases) AS compras_pixel
  FROM ad_insights_daily a
  JOIN ad_accounts aa ON aa.id = a.ad_account_id
  JOIN project_ad_account_mappings map ON map.ad_account_id = a.ad_account_id
  JOIN params ON map.project_id = params.pid
  WHERE aa.currency = 'USD' AND a.date_start BETWEEN params.d1 AND params.d2
  GROUP BY 1
),
leads AS (
  SELECT o.created_date::date AS dia, count(*) AS n
  FROM crm_opportunities o JOIN params ON o.project_id = params.pid
  WHERE o.created_date::date BETWEEN params.d1 AND params.d2 GROUP BY 1
),
ganadas AS (
  SELECT o.last_status_change_at::date AS dia, count(*) AS n
  FROM crm_opportunities o JOIN params ON o.project_id = params.pid
  WHERE o.status = 'won' AND o.last_status_change_at::date BETWEEN params.d1 AND params.d2 GROUP BY 1
),
planes AS (
  SELECT pp.start_date AS dia, count(*) AS n, coalesce(sum(pp.original_amount), 0) AS contrato
  FROM payment_plans pp JOIN params ON pp.project_id = params.pid
  WHERE pp.plan_status <> 'Cancelled' AND pp.start_date BETWEEN params.d1 AND params.d2 GROUP BY 1
)
SELECT to_char(d.dia, 'YYYY-MM-DD')                                   AS dia,
       extract(isodow FROM d.dia)::int                                 AS dow,
       (ARRAY['lun','mar','mié','jue','vie','sáb','dom'])[extract(isodow FROM d.dia)::int] AS dia_semana,
       coalesce(c.nuevas_n, 0)                                         AS nuevas_n,
       round(coalesce(c.nuevas_amt, 0), 2)                             AS nuevas_amt,
       coalesce(c.cuotas_n, 0)                                         AS cuotas_n,
       round(coalesce(c.cuotas_amt, 0), 2)                             AS cuotas_amt,
       coalesce(c.nuevas_n, 0) + coalesce(c.cuotas_n, 0)               AS pagos,
       round(coalesce(c.nuevas_amt, 0) + coalesce(c.cuotas_amt, 0), 2) AS cash,
       round(coalesce(p.spend, 0), 2)                                  AS spend_usd,
       coalesce(p.compras_pixel, 0)                                    AS compras_pixel,
       coalesce(l.n, 0)                                                AS leads,
       coalesce(g.n, 0)                                                AS ganadas,
       coalesce(pl.n, 0)                                               AS planes,
       round(coalesce(pl.contrato, 0), 2)                              AS contrato,
       CASE WHEN coalesce(p.spend, 0) > 0
            THEN round((coalesce(c.nuevas_amt, 0) + coalesce(c.cuotas_amt, 0)) / p.spend, 2) END AS roas_dia
FROM dias d
LEFT JOIN caja c    ON c.dia = d.dia
LEFT JOIN pauta p   ON p.dia = d.dia
LEFT JOIN leads l   ON l.dia = d.dia
LEFT JOIN ganadas g ON g.dia = d.dia
LEFT JOIN planes pl ON pl.dia = d.dia
ORDER BY d.dia"

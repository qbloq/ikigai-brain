#!/usr/bin/env bash
# conversion_real.sh — la TABLA DE VERDAD: una fila por llamada con su desenlace
# en PLATA, no en `callStatus`.
#
# Existe porque hasta hoy la "conversión" del dominio de llamadas se leía de
# `generalInformation.callStatus` — texto libre con 131 valores distintos para
# 230 reportes, clasificado por heurística. La verdad sobre el dinero vive en
# `installments`, y esta es la cadena que la alcanza:
#
#   meetings.event->booking->>contact_id = payment_plans.customer_id
#                                        → installments (status='Paid')
#
# Dos guardias que hacen honesta la atribución:
#
#   1. VENTANA TEMPORAL (--dias, default 30). El join es por CONTACTO, así que
#      un plan creado ANTES de la llamada es un cliente que ya existía, no una
#      conversión de esta llamada. Solo cuentan los planes creados entre la
#      fecha de la llamada y +N días (el cierre real se sella con la primera
#      cuota, días después de la llamada).
#   2. ATRIBUCIÓN ÚNICA. Un contacto puede tener varias llamadas; el plan se
#      atribuye a la llamada MÁS CERCANA que lo precede, no a todas. Sin esto
#      una sola venta inflaría el numerador de tres llamadas distintas.
#
# `convirtio` exige además ≥1 cuota PAGADA: un plan creado sin plata que entre
# no es una venta. `pagado` es lo efectivamente cobrado (USD; la moneda va en
# su columna — nunca se suma entre monedas).
#
# Read-only. Uso:
#   conversion_real.sh [--dias N] [--solo-convertidas|--solo-no-convertidas]
#                      [--con-transcript] [--min-chars N] [--project N]
#                      [--from D] [--to D] [--limit N] [--json]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../lib/common.sh"

dias=30 filtro="" solo_tr="" min_chars=0 proyecto="" desde="" hasta="" limite=200
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dias) dias="$2"; shift 2 ;;
    --solo-convertidas) filtro="conv"; shift ;;
    --solo-no-convertidas) filtro="noconv"; shift ;;
    --con-transcript) solo_tr=1; shift ;;
    --min-chars) min_chars="$2"; solo_tr=1; shift 2 ;;
    --project) proyecto="$2"; shift 2 ;;
    --from) desde="$2"; shift 2 ;;
    --to) hasta="$2"; shift 2 ;;
    --limit) limite="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "flag desconocido: $1 (ver -h)" >&2; exit 2 ;;
  esac
done

w_conv=""
case "$filtro" in
  conv)   w_conv="AND a.convirtio" ;;
  noconv) w_conv="AND NOT a.convirtio" ;;
esac
w_tr="";     [[ -n "$solo_tr" ]] && w_tr="AND c.chars >= ${min_chars:-1}"
w_proj="";   [[ -n "$proyecto" ]] && w_proj="AND pr.name ILIKE '%${proyecto//\'/\'\'}%'"
w_desde="";  [[ -n "$desde" ]] && w_desde="AND c.fecha >= '${desde//\'/}'::date"
w_hasta="";  [[ -n "$hasta" ]] && w_hasta="AND c.fecha <= '${hasta//\'/}'::date"
lim="";      [[ "$limite" != "0" ]] && lim="LIMIT $limite"

sql="
WITH c AS (
  SELECT m.id, m.event->'booking'->>'contact_id' AS contact_id,
         (coalesce(m.actual_start_time, m.scheduled_start_time) AT TIME ZONE 'America/Bogota')::date AS fecha,
         m.project_id,
         coalesce(length(mt.transcript), 0) AS chars,
         mr.meeting_id IS NOT NULL AS analizada
  FROM meetings m
  LEFT JOIN meeting_transcripts mt ON mt.meeting_id = m.id
  LEFT JOIN meeting_reports mr ON mr.meeting_id = m.id
  WHERE m.meeting_type = 'call'
), planes AS (
  -- Cada plan se ata a UNA llamada: la más cercana que lo precede dentro de la
  -- ventana. DISTINCT ON hace la atribución única (guardia 2).
  SELECT DISTINCT ON (p.plan_id)
         p.plan_id, c.id AS meeting_id, p.created_at::date AS plan_creado,
         p.original_amount, p.currency, p.plan_status,
         (p.created_at::date - c.fecha) AS dias_despues
  FROM payment_plans p
  JOIN c ON c.contact_id = p.customer_id
        AND p.created_at::date BETWEEN c.fecha AND c.fecha + ${dias}
  ORDER BY p.plan_id, c.fecha DESC
), a AS (
  SELECT c.id, pl.plan_id, pl.plan_creado, pl.dias_despues,
         pl.original_amount, pl.currency, pl.plan_status,
         coalesce((SELECT count(*) FROM installments i
                   WHERE i.plan_id = pl.plan_id AND i.status = 'Paid'), 0) AS cuotas_pagadas,
         coalesce((SELECT sum(i.paid_amount) FROM installments i
                   WHERE i.plan_id = pl.plan_id AND i.status = 'Paid'), 0) AS pagado,
         EXISTS (SELECT 1 FROM installments i
                 WHERE i.plan_id = pl.plan_id AND i.status = 'Paid') AS convirtio
  FROM c LEFT JOIN planes pl ON pl.meeting_id = c.id
)
SELECT left(c.id::text, 8) AS id8, c.fecha, pr.name AS proyecto,
       c.chars, c.analizada,
       a.convirtio, a.dias_despues AS dias, a.cuotas_pagadas AS cuotas,
       -- OJO a la diferencia, que no es cosmética:
       --   precio_plan = lo VENDIDO (original_amount). Independiente del tiempo.
       --   pagado      = lo COBRADO hasta hoy. Crece con la antigüedad de la
       --                 llamada, así que sirve para el binario pero NO como
       --                 magnitud comparable entre cohortes.
       round(a.original_amount, 2) AS precio_plan,
       round(a.pagado, 2) AS pagado,
       CASE WHEN a.original_amount > 0
            THEN round(a.pagado / a.original_amount, 2) END AS frac_pagada,
       a.currency AS cur, a.plan_status AS plan,
       c.id AS meeting_id
FROM c JOIN a ON a.id = c.id
LEFT JOIN projects pr ON pr.id = c.project_id
WHERE true $w_conv $w_tr $w_proj $w_desde $w_hasta
ORDER BY c.fecha DESC
$lim"

emit "$sql"

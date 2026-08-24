#!/usr/bin/env bash
# cohorte_mora.sh — LA LISTA de estudiantes de una cohorte (por fecha de inicio
# del plan) que NO están pagando, con su segmento de reactivación calculado por
# reglas declaradas. Entregable de la tarea 9f249dbe (arquetipo A12.4) en forma
# consultable: se recalcula contra datos vivos, no es una foto.
#
# Reglas que sostiene (las mismas del plan de reactivación, docs/…):
#   · cohorte      = start_date del plan dentro de la ventana (no la fecha de pago)
#   · en mora      = al menos una cuota con due_date < hoy y status ∉ (Paid, Cancelled)
#   · días de mora = hoy − due_date de la cuota vencida MÁS VIEJA. Nunca desde
#                    installments.status: esa columna jamás escribe «Overdue».
#   · freno        = número de la primera cuota vencida sin pagar («se frenó en la N»)
#   · segmento     (ver SEGMENTOS abajo): por días de mora y proporción del plan pagada
#   · contacto     = crm_contacts por ghl_contact_id = payment_plans.customer_id;
#                    closer = dueño de la oportunidad más reciente de ese contacto
#
# SEGMENTOS (orden de evaluación; el primero que aplica gana):
#   S1 fresca     días ≤ 30                     → cobro fallido probable: link de pago
#   S2 reciente   días ≤ 90                     → llamada del closer que vendió
#   S3 avanzado   pagó ≥ 50 % de las cuotas     → retención 1:1 + oferta de cierre
#   S4 temprana   (el resto: < 50 % y > 90 d)   → diagnóstico primero, decisión después
# Verificado 2026-08-22 contra el plan de reactivación: 2 / 7 / 12 / 14 alumnos,
# USD 738 / 10.020 / 10.947 / 28.912 — idénticos al Doc.
#
# Uso: cohorte_mora.sh --project NAME [--desde YYYY-MM-DD] [--hasta YYYY-MM-DD]
#                      [--contexto] [--json]
#   --desde/--hasta  ventana de start_date (default: 2026-02-01 → 2026-03-31)
#   --contexto       en vez de la lista: una fila por cohorte mensual (alumnos,
#                    en mora, %) desde 2025-12, para leer la cohorte en su contexto
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
project="" desde="2026-02-01" hasta="2026-03-31" contexto=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) project="$2"; shift 2 ;;
    --desde) desde="$2"; shift 2 ;;
    --hasta) hasta="$2"; shift 2 ;;
    --contexto) contexto=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$project" ]] || { echo "Falta --project NAME" >&2; exit 2; }
for d in "$desde" "$hasta"; do [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "fecha inválida: $d" >&2; exit 2; }; done
pe="${project//\'/\'\'}"

if [[ "$contexto" == 1 ]]; then
  sql="
WITH pl AS (
  SELECT pp.plan_id, to_char(pp.start_date,'YYYY-MM') cohorte,
         EXISTS (SELECT 1 FROM installments i WHERE i.plan_id=pp.plan_id AND i.status NOT IN ('Paid','Cancelled') AND i.due_date < current_date) en_mora
  FROM payment_plans pp JOIN projects p ON p.id=pp.project_id
  WHERE p.name ILIKE '${pe}%' AND pp.start_date >= '2025-12-01')
SELECT cohorte, count(*) alumnos, count(*) FILTER (WHERE en_mora) en_mora,
       round(100.0*count(*) FILTER (WHERE en_mora)/count(*),0) pct,
       (cohorte BETWEEN to_char('${desde}'::date,'YYYY-MM') AND to_char('${hasta}'::date,'YYYY-MM')) es_la_cohorte
FROM pl GROUP BY 1 ORDER BY 1"
else
  sql="
WITH pl AS (
  SELECT pp.plan_id, pp.customer_id, pp.customer_name, pp.start_date::date inicio, pp.original_amount contrato,
         pp.number_of_installments cuotas_plan, coalesce(pr.name,'—') programa
  FROM payment_plans pp JOIN projects p ON p.id=pp.project_id LEFT JOIN products pr ON pr.id=pp.product_uuid
  WHERE p.name ILIKE '${pe}%' AND pp.start_date::date BETWEEN '${desde}' AND '${hasta}'),
cu AS (
  SELECT i.plan_id,
         count(*) cuotas,
         count(*) FILTER (WHERE i.status='Paid') pagadas,
         sum(i.paid_amount) FILTER (WHERE i.status='Paid') cobrado,
         count(*) FILTER (WHERE i.status NOT IN ('Paid','Cancelled') AND i.due_date < current_date) vencidas,
         sum(i.scheduled_amount) FILTER (WHERE i.status NOT IN ('Paid','Cancelled') AND i.due_date < current_date) pendiente,
         min(i.due_date) FILTER (WHERE i.status NOT IN ('Paid','Cancelled') AND i.due_date < current_date) primer_vencida,
         min(i.installment_number) FILTER (WHERE i.status NOT IN ('Paid','Cancelled') AND i.due_date < current_date) freno
  FROM installments i JOIN pl ON pl.plan_id=i.plan_id GROUP BY 1),
base AS (
  SELECT pl.*, cu.cuotas, cu.pagadas, coalesce(cu.cobrado,0) cobrado, cu.vencidas, cu.pendiente, cu.freno,
         (current_date - cu.primer_vencida) dias_mora,
         round(1.0*cu.pagadas/nullif(cu.cuotas,0),2) pct_pagado
  FROM pl JOIN cu ON cu.plan_id=pl.plan_id WHERE cu.vencidas > 0)
SELECT
  CASE WHEN b.dias_mora <= 30 THEN 'S1'
       WHEN b.dias_mora <= 90 THEN 'S2'
       WHEN b.pct_pagado >= 0.5 THEN 'S3'
       ELSE 'S4' END segmento,
  trim(regexp_replace(coalesce(nullif(trim(b.customer_name),''), c.first_name||' '||coalesce(c.last_name,'')),'\s+',' ','g')) alumno,
  b.programa, b.inicio, b.contrato, b.cuotas, b.pagadas, b.pct_pagado, b.freno, b.vencidas,
  b.pendiente, b.cobrado, b.dias_mora,
  c.email, c.phone,
  (c.id IS NOT NULL) en_crm,
  cl.closer,
  b.plan_id
FROM base b
LEFT JOIN crm_contacts c ON c.ghl_contact_id = b.customer_id::text
LEFT JOIN LATERAL (
  SELECT trim(regexp_replace(p.name||' '||coalesce(p.lastname,''),'\s+',' ','g')) closer
  FROM crm_opportunities o JOIN users u ON u.id=o.user_id JOIN persons p ON p.person_id=u.person_id
  WHERE o.contact_id = c.id ORDER BY o.created_date DESC NULLS LAST LIMIT 1) cl ON true
ORDER BY segmento, b.pendiente DESC"
fi
emit "$sql"

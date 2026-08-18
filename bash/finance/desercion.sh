#!/usr/bin/env bash
# desercion.sh — LA MEDICIÓN del impago y la deserción de cuotas, como un solo
# objeto JSON. Es el entregable de la tarea fb7a1c26 (arquetipo A12.8) en forma
# consultable: el instrumento que se puede volver a correr, no una foto.
#
# El hallazgo que le da forma: la deserción NO está repartida, está concentrada
# en el NÚMERO de cuota. Casi todos pagan la primera; la segunda la paga siete
# de cada diez. Eso pasa después de entregar el primer mes — no es un problema
# de cobranza, es el cliente decidiendo que no sigue.
#
# Y la trampa que obliga a cruzar dos ejes: leída SOLO por cohorte de venta, la
# tasa de cobro dice lo contrario de lo que pasa. Los planes recientes apenas
# llegaron a la cuota 1, que la paga el 99%, así que aparecen «cobrando mejor».
# Toda tasa aquí se calcula sobre cuotas YA VENCIDAS y se reporta contra los dos
# ejes (cohorte y número de cuota), nunca contra la cohorte sola.
#
# Uso: desercion.sh [--project NAME] [--desde YYYY-MM-DD] [--corte YYYY-MM-DD] [--json]
#
#   --desde D   inicio de la ventana del DINERO vencido. Default 2025-12-01:
#               la cuota impaga más antigua venció el 2025-12-09, así que
#               diciembre captura el universo entero. Se fija explícito en vez
#               de dejarlo implícito porque un total sin ventana declarada no se
#               puede reproducir ni comparar contra sí mismo el mes que viene.
#   --corte D   frontera arrastre histórico / deterioro nuevo, por FECHA DE
#               INICIO DEL PLAN. Sin default a propósito: es la entrada E2 de la
#               tarea, una decisión humana que no está en la base. Sin ella el
#               objeto reporta arrastre=null, y así debe verse.
#
# Read-only. Alimenta la fuente `desercion` del viz. Siempre emite JSON.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

project="" desde="2025-12-01" corte=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) project="$2"; shift 2 ;;
    --desde)   desde="$2"; shift 2 ;;
    --corte)   corte="$2"; shift 2 ;;
    --json)    shift ;;   # siempre JSON; se acepta por simetría
    -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

for d in "$desde" ${corte:+"$corte"}; do
  [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "Fecha inválida: '$d' (espero YYYY-MM-DD)" >&2; exit 2; }
done

pfilter="p.project_id IS NOT NULL"
pname="(todos los proyectos)"
if [[ -n "$project" ]]; then
  pid="$(resolve_project "$project")"
  [[ -z "$pid" ]] && { echo "No project matches: $project" >&2; exit 1; }
  pfilter="p.project_id = '$pid'"
  pname="$project"
fi

# corte vacío -> NULL en SQL; con valor -> literal date. La rama sin decidir
# tiene que producir null y no una fecha inventada: es lo que hace visible que
# E2 todavía no se firmó.
cortesql="NULL::date"
[[ -n "$corte" ]] && cortesql="date '$corte'"

psql_ro -t -A -c "
WITH base AS (
  SELECT p.plan_id, p.start_date, p.customer_name,
         i.installment_number, i.due_date, i.status,
         i.scheduled_amount,
         i.scheduled_amount - coalesce(i.paid_amount,0) AS pendiente
  FROM payment_plans p
  JOIN installments i ON i.plan_id = p.plan_id
  WHERE $pfilter
),
-- Cuotas ya vencidas: el denominador honesto. Una cuota que aún no vence no es
-- impago, y contarla como tal hunde cualquier tasa. Sin filtro de ventana: la
-- curva y las cohortes se calculan sobre TODA la historia.
venc AS (SELECT * FROM base WHERE due_date < current_date),
-- El dinero vencido sin cobrar, dentro de la ventana declarada.
imp AS (SELECT * FROM venc WHERE status <> 'Paid' AND due_date >= date '$desde'),
-- Los planes que no se pueden atribuir a ningún proyecto. NO entran a ningún
-- cálculo de arriba y por eso se reportan aparte: un excluido callado es la
-- diferencia entre una medición y un número bonito.
excl AS (
  SELECT count(DISTINCT p.plan_id) AS planes, count(*) AS cuotas,
         coalesce(sum(i.scheduled_amount - coalesce(i.paid_amount,0)),0) AS usd
  FROM payment_plans p JOIN installments i ON i.plan_id = p.plan_id
  WHERE p.project_id IS NULL AND i.status <> 'Paid' AND i.due_date < current_date
)
SELECT json_build_object(
  'meta', json_build_object(
     'proyecto',        '$pname',
     'corte',           to_char(current_date,'YYYY-MM-DD'),
     'desde',           '$desde',
     'corte_arrastre',  to_char($cortesql,'YYYY-MM-DD'),
     'ventana_dinero',  'el total vencido cuenta cuotas con vencimiento entre $desde y hoy',
     'ventana_curva',   'la curva y las cohortes usan TODA la historia de cuotas ya vencidas, sin ventana',
     'regla',           'toda tasa se calcula sobre cuotas YA VENCIDAS (due_date < hoy); una cuota que aun no vence no es impago'),

  -- El total, con sus dos lecturas. Dan respuestas opuestas y ese es el punto.
  'total', (SELECT json_build_object(
     'cuotas', count(*), 'planes', count(DISTINCT plan_id), 'usd', coalesce(sum(pendiente),0)) FROM imp),

  -- Lectura 1: por cuándo venció la cuota. Es la que trae cobranza.sh y la que
  -- hace ver el problema como nuevo.
  'por_vencimiento', coalesce((SELECT json_agg(t ORDER BY t.mes) FROM (
     SELECT to_char(due_date,'YYYY-MM') AS mes, count(*) AS cuotas,
            sum(pendiente) AS usd,
            round(100.0*sum(pendiente)/nullif((SELECT sum(pendiente) FROM imp),0),1) AS pct
     FROM imp GROUP BY 1) t), '[]'::json),

  -- Lectura 2: por cuándo se vendió el plan. Una cuota vence tarde aunque el
  -- cliente sea viejo, así que este eje es el único que puede ver arrastre.
  'por_cohorte', coalesce((SELECT json_agg(t ORDER BY t.cohorte) FROM (
     SELECT to_char(start_date,'YYYY-MM') AS cohorte, count(DISTINCT plan_id) AS planes,
            count(*) AS cuotas, sum(pendiente) AS usd,
            round(100.0*sum(pendiente)/nullif((SELECT sum(pendiente) FROM imp),0),1) AS pct
     FROM imp GROUP BY 1) t), '[]'::json),

  -- LA CURVA: el hallazgo. Deserción por número de cuota, con su n en cada
  -- punto — un promedio único la escondería.
  'curva', coalesce((SELECT json_agg(t ORDER BY t.cuota_n) FROM (
     SELECT installment_number AS cuota_n, count(*) AS debidas,
            count(*) FILTER (WHERE status = 'Paid') AS pagadas,
            round(100.0*count(*) FILTER (WHERE status = 'Paid')/count(*),1) AS pct_cobrado,
            sum(pendiente) FILTER (WHERE status <> 'Paid') AS sin_cobrar
     FROM venc GROUP BY 1) t), '[]'::json),

  -- Cohortes ajustadas por madurez: la tasa de cobro real de cada mes de venta,
  -- más hasta qué cuota alcanzó a llegar EN PROMEDIO. Sin esa última columna la
  -- comparación entre cohortes miente, y por eso viaja pegada al número.
  -- Promedio y no máximo: un solo plan adelantado inflaría el máximo y haría
  -- ver madura una cohorte que apenas va en la primera cuota.
  'cohortes', coalesce((SELECT json_agg(t ORDER BY t.cohorte) FROM (
     SELECT to_char(start_date,'YYYY-MM') AS cohorte, count(DISTINCT plan_id) AS planes,
            count(*) AS debidas, count(*) FILTER (WHERE status = 'Paid') AS pagadas,
            round(100.0*count(*) FILTER (WHERE status = 'Paid')/count(*),1) AS pct_cobrado,
            round(avg(installment_number),1) AS cuota_prom,
            coalesce(sum(pendiente) FILTER (WHERE status <> 'Paid'),0) AS sin_cobrar
     FROM venc GROUP BY 1) t), '[]'::json),

  -- Arrastre vs deterioro nuevo: null mientras E2 no se decida.
  'arrastre', CASE WHEN $cortesql IS NULL THEN NULL ELSE (
     SELECT json_build_object(
       'corte', to_char($cortesql,'YYYY-MM-DD'),
       'arrastre', json_build_object(
          'planes', count(DISTINCT plan_id) FILTER (WHERE start_date < $cortesql),
          'cuotas', count(*) FILTER (WHERE start_date < $cortesql),
          'usd',    coalesce(sum(pendiente) FILTER (WHERE start_date < $cortesql),0)),
       'nuevo', json_build_object(
          'planes', count(DISTINCT plan_id) FILTER (WHERE start_date >= $cortesql),
          'cuotas', count(*) FILTER (WHERE start_date >= $cortesql),
          'usd',    coalesce(sum(pendiente) FILTER (WHERE start_date >= $cortesql),0)))
     FROM imp) END,

  'excluidos', (SELECT json_build_object(
     'planes', planes, 'cuotas', cuotas, 'usd', usd,
     'motivo', 'planes sin project_id: no se pueden atribuir a un proyecto') FROM excl)
)::text;"

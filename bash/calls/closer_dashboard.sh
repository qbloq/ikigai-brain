#!/usr/bin/env bash
# closer_dashboard.sh — EL DASHBOARD de un closer como un solo objeto JSON:
# la capa de OPERACIÓN de docs/lead-score.md §5, la que el Director Comercial
# ve y el closer no. Reúne lo que hoy vive en cuatro scripts:
#
#   llamadas   sus llamadas analizadas, con el resultado CANÓNICO (la
#              clasificación de lead_profile.sh — ganada+compromiso = conversión;
#              el ILIKE 'closed won%' de call_stats.sh subcuenta) y sus tramos
#              BANT (ceros excluidos: sin transcript ≠ mal calificado).
#   cola       BANT ≥ 70 que quedó en seguimiento y nunca cerró — el dinero
#              sobre la mesa, la aplicación inmediata del score. El corazón
#              sigue siendo ≥ 81 (el tramo que convierte ~39%; cola_n cuenta
#              solo esos); el borde 70-80 viaja en las mismas filas y la UI
#              lo distingue por fondo.
#   coaching   su evaluación por llamada (score, fortalezas, mejoras, coaching)
#              y sus objeciones recientes — esto SÍ es del closer.
#   ventas     el cash REAL: payment_plans.user_id ES el closer (el cliente va
#              en customer_id/customer_name), installments es la verdad del
#              dinero, commission_payouts su comisión. Todo USD.
#   comparativo  serie mensual del closer (los 3 meses que terminan en el mes
#              de --to, o el actual): llamadas, conversión, venta y cash — la
#              materia de las gráficas de cierre del viz. closers[] carga
#              además venta_usd por closer (el leaderboard).
#
# Sin --closer toma el de más llamadas analizadas en la ventana. El objeto
# incluye `closers[]` (llamadas + ventas por closer) para poblar el selector.
#
# --closer-id <uuid de users.id> es la IDENTIDAD EXACTA y tiene PRECEDENCIA
# sobre --closer (que queda ignorado). Existe porque el nombre no identifica:
# el JWT trae solo el nombre de pila y `ILIKE '%David%'` le entregaba a David
# Guerrero el dashboard entero de Luis David Flórez. Con --closer-id las cuatro
# secciones (llamadas, planes, cash, comisiones) filtran por igualdad de uuid;
# el nombre que se reporta se resuelve DESDE ese id. --closer (ILIKE) se
# conserva para el dropdown libre del Director Comercial.
#
# Uso: closer_dashboard.sh [--closer FRAG | --closer-id UUID] [--project NAME]
#                          [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--json]
# Read-only; siempre emite JSON. Alimenta la fuente `closer_dashboard` del viz.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

closer="" closer_id="" project="" from="" to=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --closer)     closer="$2"; shift 2 ;;
    --closer-id)  closer_id="$2"; shift 2 ;;
    --project) project="$2"; shift 2 ;;
    --from)    from="$2"; shift 2 ;;
    --to)      to="$2"; shift 2 ;;
    --json)    shift ;;   # siempre JSON; se acepta por simetría
    -h|--help) sed -n '2,31p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# La identidad exacta gana: con --closer-id el fragmento de nombre se descarta
# entero (no se combina — combinar dejaría al nombre volver a filtrar).
if [[ -n "$closer_id" ]]; then
  [[ "$closer_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] \
    || { echo "--closer-id debe ser un uuid de users.id: '$closer_id'" >&2; exit 2; }
  closer=""
fi

frag="${closer//\'/\'\'}"
from="${from//\'/}" to="${to//\'/}"

# Los predicados de selección: por uuid exacto (identidad) o por nombre (ILIKE).
if [[ -n "$closer_id" ]]; then
  selpred="p.closer_uid = '$closer_id'::uuid"
  planpred="a.closer_uid = '$closer_id'::uuid"
  comipred="cp.user_id = '$closer_id'::uuid"
  cmppred="c.closer_uid = '$closer_id'::uuid"
  cashpred="pp.user_id = '$closer_id'::uuid"
  closer_expr="(SELECT trim(regexp_replace(pi.name||' '||coalesce(pi.lastname,''),'\s+',' ','g'))
                FROM users ui JOIN persons pi ON pi.person_id = ui.person_id
                WHERE ui.id = '$closer_id'::uuid)"
else
  selpred="p.closer ILIKE '%'||pick.frag||'%'"
  planpred="a.closer ILIKE '%'||pick.frag||'%'"
  comipred="coalesce(nullif(trim(regexp_replace(coalesce(pe3.name,'')||' '||coalesce(pe3.lastname,''),'\s+',' ','g')),''), cp.contractor_name)
               ILIKE '%'||pick.frag||'%'"
  cmppred="c.closer ILIKE '%'||pick.frag||'%'"
  cashpred="trim(regexp_replace(pe5.name||' '||coalesce(pe5.lastname,''),'\s+',' ','g')) ILIKE '%'||pick.frag||'%'"
  closer_expr="(SELECT closer FROM sel GROUP BY 1 ORDER BY count(*) DESC LIMIT 1)"
fi

# Cada dominio filtra la ventana por SU fecha natural: llamadas por agenda,
# planes por inicio, cobros por pago, comisiones por creación.
mwhere="m.meeting_type='call' AND r.meeting_id IS NOT NULL"
pwhere="true" cwhere="true" iwhere=""
[[ -n "$from" ]] && { mwhere="$mwhere AND m.scheduled_start_time::date >= '$from'"
                      pwhere="$pwhere AND pp.start_date >= '$from'"
                      cwhere="$cwhere AND cp.created_at::date >= '$from'"
                      iwhere="$iwhere AND i.payment_date >= '$from'"; }
[[ -n "$to" ]]   && { mwhere="$mwhere AND m.scheduled_start_time::date <= '$to'"
                      pwhere="$pwhere AND pp.start_date <= '$to'"
                      cwhere="$cwhere AND cp.created_at::date <= '$to'"
                      iwhere="$iwhere AND i.payment_date <= '$to'"; }
cmpproj_m="" cmpproj_p=""
if [[ -n "$project" ]]; then
  pid="$(resolve_project "$project")"
  [[ -z "$pid" ]] && { echo "No project matches: $project" >&2; exit 1; }
  mwhere="$mwhere AND m.project_id = '$pid'"
  pwhere="$pwhere AND pp.project_id = '$pid'"
  cwhere="$cwhere AND cp.project_id = '$pid'"
  cmpproj_m="AND m.project_id = '$pid'"
  cmpproj_p="AND pp.project_id = '$pid'"
fi

psql_ro -t -A -c "
WITH base AS (
  SELECT m.id, m.scheduled_start_time AS ts, pr.name AS proyecto,
         coalesce(r.report->'generalInformation'->>'leadName', split_part(m.name,' - ',1)) AS lead,
         coalesce(r.report->'generalInformation'->>'program',  split_part(m.name,' - ',2)) AS programa,
         coalesce(r.report->'generalInformation'->>'callStatus','') AS st,
         coalesce(nullif(regexp_replace(coalesce(r.report->'leadProfile'->'bantAnalysis'->'need'->>'score',''),'[^0-9]','','g'),'')::numeric,0)      AS need,
         coalesce(nullif(regexp_replace(coalesce(r.report->'leadProfile'->'bantAnalysis'->'budget'->>'score',''),'[^0-9]','','g'),'')::numeric,0)    AS budget,
         coalesce(nullif(regexp_replace(coalesce(r.report->'leadProfile'->'bantAnalysis'->'timeline'->>'score',''),'[^0-9]','','g'),'')::numeric,0)  AS timeline,
         coalesce(nullif(regexp_replace(coalesce(r.report->'leadProfile'->'bantAnalysis'->'authority'->>'score',''),'[^0-9]','','g'),'')::numeric,0) AS authority,
         nullif(regexp_replace(coalesce(r.report->'performanceInsights'->'finalCloserEvaluation'->>'overallScore',''),'[^0-9.]','','g'),'')::numeric AS score,
         nullif(regexp_replace(coalesce(r.report->'leadProfile'->'predictionsAndRecommendations'->'closingProbability'->>'percentage',''),'[^0-9.]','','g'),'')::numeric AS prob,
         r.report->'performanceInsights'->'finalCloserEvaluation' AS eval,
         r.report->'objectionsAndInsights'->'objectionHandling'->'objections' AS objs,
         cl.closer, cl.closer_uid
  FROM meetings m
  JOIN call_report_vigente r ON r.meeting_id = m.id
  LEFT JOIN projects pr ON pr.id = m.project_id
  LEFT JOIN LATERAL (
    SELECT trim(regexp_replace(p.name||' '||coalesce(p.lastname,''),'\s+',' ','g')) AS closer,
           u.id AS closer_uid
    FROM crm_contacts c
    JOIN crm_opportunities o2 ON o2.contact_id = c.id
    JOIN users u   ON u.id = o2.user_id
    JOIN persons p ON p.person_id = u.person_id
    WHERE c.ghl_contact_id = m.event->'booking'->>'contact_id'
    ORDER BY (o2.project_id = m.project_id) DESC, o2.created_date DESC NULLS LAST
    LIMIT 1) cl ON true
  WHERE $mwhere
),
p AS (
  SELECT base.*, (need+budget+timeline+authority)/4.0 AS bant,
         CASE
           WHEN st ~* '^closed( |-|/|\()|^closed\$' THEN 'ganada'
           WHEN st ~* '(committ|compromiso|deposit (paid|made|secured)|partial (payment|close)|pre-closed|payment plan initiated|initiated purchase|^reserved|^cerrado)' THEN 'compromiso'
           WHEN st ~* '(follow-?up|seguimiento|pending|decision)' THEN 'seguimiento'
           WHEN st ~* 'unqualified' THEN 'no calificado'
           WHEN st ~* 'no ?show'    THEN 'no asistió'
           ELSE 'sin data'
         END AS resultado
  FROM base
),
pick AS (
  SELECT coalesce(nullif('$frag',''),
           (SELECT closer FROM p WHERE closer IS NOT NULL GROUP BY 1 ORDER BY count(*) DESC LIMIT 1)) AS frag
),
sel AS (SELECT p.* FROM p, pick WHERE $selpred),
v   AS (SELECT * FROM sel WHERE bant > 0),   -- universo válido: BANT distinto de cero
allplans AS (
  SELECT pp.plan_id, pp.customer_name, pp.start_date, pp.original_amount, pp.currency,
         pp.plan_status, pr2.name AS proyecto,
         trim(regexp_replace(pe.name||' '||coalesce(pe.lastname,''),'\s+',' ','g')) AS closer,
         pp.user_id AS closer_uid
  FROM payment_plans pp
  JOIN users u2   ON u2.id = pp.user_id
  JOIN persons pe ON pe.person_id = u2.person_id
  LEFT JOIN projects pr2 ON pr2.id = pp.project_id
  WHERE $pwhere
),
selplans AS (SELECT a.* FROM allplans a, pick WHERE $planpred),
cash AS (
  SELECT i.paid_amount
  FROM installments i JOIN selplans sp ON sp.plan_id = i.plan_id
  WHERE coalesce(i.paid_amount,0) > 0 $iwhere
),
selcomi AS (
  SELECT cp.payout_amount, cp.status
  FROM commission_payouts cp
  LEFT JOIN users u3   ON u3.id = cp.user_id
  LEFT JOIN persons pe3 ON pe3.person_id = u3.person_id
  JOIN pick ON $comipred
  WHERE $cwhere
),
-- Serie mensual del comparativo: los 3 meses calendario que terminan en el mes
-- de --to (o el actual). Independiente de la ventana from/to a propósito — el
-- comparativo mira hacia atrás aunque la ventana sea el mes corriente.
cmpanchor AS (SELECT date_trunc('month', coalesce(nullif('$to','')::date, current_date))::date AS m0),
cmpcalls AS (
  SELECT date_trunc('month', m.scheduled_start_time)::date AS mes,
         coalesce(r.report->'generalInformation'->>'callStatus','') AS st,
         cl.closer, cl.closer_uid
  FROM meetings m
  JOIN call_report_vigente r ON r.meeting_id = m.id
  LEFT JOIN LATERAL (
    SELECT trim(regexp_replace(p.name||' '||coalesce(p.lastname,''),'\s+',' ','g')) AS closer,
           u.id AS closer_uid
    FROM crm_contacts c2
    JOIN crm_opportunities o2 ON o2.contact_id = c2.id
    JOIN users u   ON u.id = o2.user_id
    JOIN persons p ON p.person_id = u.person_id
    WHERE c2.ghl_contact_id = m.event->'booking'->>'contact_id'
    ORDER BY (o2.project_id = m.project_id) DESC, o2.created_date DESC NULLS LAST
    LIMIT 1) cl ON true
  CROSS JOIN cmpanchor
  WHERE m.meeting_type='call'
    AND m.scheduled_start_time >= cmpanchor.m0 - interval '2 months'
    AND m.scheduled_start_time <  cmpanchor.m0 + interval '1 month'
    $cmpproj_m
),
cmpsel AS (
  SELECT c.mes,
         CASE
           WHEN c.st ~* '^closed( |-|/|\()|^closed\$' THEN 'ganada'
           WHEN c.st ~* '(committ|compromiso|deposit (paid|made|secured)|partial (payment|close)|pre-closed|payment plan initiated|initiated purchase|^reserved|^cerrado)' THEN 'compromiso'
           ELSE 'otra'
         END AS resultado
  FROM cmpcalls c, pick WHERE $cmppred
),
cmpplans AS (
  SELECT date_trunc('month', pp.start_date)::date AS mes, pp.original_amount,
         trim(regexp_replace(pe4.name||' '||coalesce(pe4.lastname,''),'\s+',' ','g')) AS closer,
         pp.user_id AS closer_uid
  FROM payment_plans pp
  JOIN users u4   ON u4.id = pp.user_id
  JOIN persons pe4 ON pe4.person_id = u4.person_id
  CROSS JOIN cmpanchor
  WHERE pp.start_date >= cmpanchor.m0 - interval '2 months'
    AND pp.start_date <  cmpanchor.m0 + interval '1 month'
    $cmpproj_p
),
cmpselplans AS (SELECT a.* FROM cmpplans a, pick WHERE $planpred),
cmpcash AS (
  SELECT date_trunc('month', i.payment_date)::date AS mes, i.paid_amount
  FROM installments i
  JOIN payment_plans pp ON pp.plan_id = i.plan_id
  JOIN users u5   ON u5.id = pp.user_id
  JOIN persons pe5 ON pe5.person_id = u5.person_id
  CROSS JOIN cmpanchor
  CROSS JOIN pick
  WHERE coalesce(i.paid_amount,0) > 0
    AND i.payment_date >= cmpanchor.m0 - interval '2 months'
    AND i.payment_date <  cmpanchor.m0 + interval '1 month'
    AND ($cashpred)
    $cmpproj_p
)
SELECT json_build_object(
  'corte',   to_char(current_date,'YYYY-MM-DD'),
  'closer',  $closer_expr,
  'periodo', json_build_object('from', nullif('$from',''), 'to', nullif('$to','')),
  'closers', coalesce((SELECT json_agg(t ORDER BY coalesce(t.llamadas,0) DESC, coalesce(t.ventas,0) DESC) FROM (
      SELECT closer, c.llamadas, s.ventas, s.venta_usd
      FROM (SELECT closer, count(*) AS llamadas FROM p WHERE closer IS NOT NULL GROUP BY 1) c
      FULL OUTER JOIN (SELECT closer, count(*) AS ventas,
                              coalesce(round(sum(original_amount)),0)::int AS venta_usd
                       FROM allplans GROUP BY 1) s USING (closer)) t), '[]'::json),
  'kpis', json_build_object(
    'llamadas',       (SELECT count(*) FROM sel),
    'con_bant',       (SELECT count(*) FROM v),
    'convirtio',      (SELECT count(*) FROM v WHERE resultado IN ('ganada','compromiso')),
    'conv_pct',       (SELECT round(100.0*count(*) FILTER (WHERE resultado IN ('ganada','compromiso'))/nullif(count(*),0),1) FROM v),
    'en_seguimiento', (SELECT count(*) FROM v WHERE resultado='seguimiento'),
    'score_prom',     (SELECT round(avg(score),1) FROM sel),
    'prob_prom',      (SELECT round(avg(prob),1)  FROM sel),
    'bant_prom',      (SELECT round(avg(bant))::int FROM v),
    'cola_n',         (SELECT count(*) FROM v WHERE bant >= 81 AND resultado='seguimiento')),
  'ventas', json_build_object(
    'planes',          (SELECT count(*) FROM selplans),
    'venta_usd',       (SELECT coalesce(round(sum(original_amount)),0) FROM selplans),
    'cash_usd',        (SELECT coalesce(round(sum(paid_amount)),0) FROM cash),
    'comisiones_usd',  (SELECT coalesce(round(sum(payout_amount)),0) FROM selcomi),
    'comisiones_pend_usd', (SELECT coalesce(round(sum(payout_amount)),0) FROM selcomi WHERE status <> 'paid'),
    'recientes', coalesce((SELECT json_agg(t) FROM (
        SELECT left(sp.plan_id::text,8) AS id, sp.customer_name AS cliente,
               to_char(sp.start_date,'YYYY-MM-DD') AS inicio, round(sp.original_amount)::int AS monto,
               sp.plan_status AS estado, sp.proyecto,
               (SELECT coalesce(round(sum(i.paid_amount)),0)::int FROM installments i WHERE i.plan_id = sp.plan_id) AS cobrado
        FROM selplans sp ORDER BY sp.start_date DESC NULLS LAST LIMIT 10) t), '[]'::json)),
  'tramos', coalesce((SELECT json_agg(t ORDER BY t.tramo DESC) FROM (
      SELECT CASE WHEN bant >= 81 THEN '81-100' WHEN bant >= 61 THEN '61-80'
                  WHEN bant >= 41 THEN '41-60'  WHEN bant >= 21 THEN '21-40'
                  ELSE '0-20' END AS tramo,
             count(*) AS llamadas,
             count(*) FILTER (WHERE resultado IN ('ganada','compromiso')) AS convirtio,
             round(100.0*count(*) FILTER (WHERE resultado IN ('ganada','compromiso'))/count(*),1) AS conv_pct,
             count(*) FILTER (WHERE resultado='seguimiento') AS en_seguimiento
      FROM v GROUP BY 1) t), '[]'::json),
  'cola', coalesce((SELECT json_agg(t ORDER BY t.bant DESC, t.fecha DESC) FROM (
      SELECT left(id::text,8) AS id, to_char(ts,'YYYY-MM-DD') AS fecha, lead, programa, proyecto,
             round(bant)::int AS bant, st AS status
      FROM v WHERE bant >= 70 AND resultado='seguimiento') t), '[]'::json),
  'comparativo', coalesce((SELECT json_agg(t ORDER BY t.mes) FROM (
      SELECT to_char(gs.mes,'YYYY-MM') AS mes,
             (SELECT count(*) FROM cmpsel s WHERE s.mes = gs.mes) AS llamadas,
             (SELECT count(*) FROM cmpsel s WHERE s.mes = gs.mes AND s.resultado IN ('ganada','compromiso')) AS convirtio,
             (SELECT coalesce(round(sum(a2.original_amount)),0)::int FROM cmpselplans a2 WHERE a2.mes = gs.mes) AS venta_usd,
             (SELECT coalesce(round(sum(cc.paid_amount)),0)::int FROM cmpcash cc WHERE cc.mes = gs.mes) AS cash_usd
      FROM (SELECT generate_series((SELECT m0 FROM cmpanchor) - interval '2 months',
                                   (SELECT m0 FROM cmpanchor), '1 month')::date AS mes) gs) t), '[]'::json),
  'coaching', coalesce((SELECT json_agg(t) FROM (
      SELECT left(id::text,8) AS id, to_char(ts,'YYYY-MM-DD') AS fecha, lead, resultado, score,
             eval->'strengths'->'items'           AS fortalezas,
             eval->'areasForImprovement'->'items' AS mejoras,
             eval->'coachingRecommendation'       AS coaching
      FROM sel WHERE score IS NOT NULL ORDER BY ts DESC LIMIT 8) t), '[]'::json),
  'objeciones', coalesce((SELECT json_agg(t) FROM (
      SELECT left(s.id::text,8) AS id, to_char(s.ts,'YYYY-MM-DD') AS fecha, s.lead,
             o.value->>'status' AS status, o.value->>'objection' AS objecion,
             o.value->>'closerResponse' AS respuesta, o.value->>'aiSuggestion' AS sugerencia
      FROM sel s CROSS JOIN LATERAL jsonb_array_elements(coalesce(s.objs,'[]'::jsonb)) o(value)
      ORDER BY s.ts DESC LIMIT 15) t), '[]'::json)
)::text;"

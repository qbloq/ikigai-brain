#!/usr/bin/env bash
# embudo.sh — EL CRUCE del embudo completo de un proyecto, como un solo objeto
# JSON: pauta (Meta) → VSL (VTurb) → leads/etapas (CRM) → llamadas (meetings)
# → ventas y cash (payment_plans/installments) → cuotas (la serie del cobro).
#
# Nació de la alineación DG 2026-08-19 (meeting b3f06835): el dashboard de
# Juanca no cuadraba porque cada peldaño venía de una fuente distinta y dos de
# ellas (el Excel comercial) arrastraban leads viejos. Aquí cada bloque declara
# su fuente, los cruces entre fuentes van en `conciliacion`, y lo que no está
# instrumentado se reporta como hueco (`sin_instrumentar`), nunca se inventa.
#
# Reglas que este script sostiene:
#   - Los leads del mes salen del CRM (created_date en ventana), NO de ningún
#     Excel — la corrección acordada en la reunión.
#   - La verdad del dinero es installments/payment_plans; el purchase_value de
#     Meta viaja como `*_pixel` para poder medir la brecha, no como verdad.
#   - CAC real y ROAS real se calculan SOLO contra pauta USD (los proyectos
#     COP no mezclan monedas; portfolio.sh hace lo mismo).
#   - meetings.scheduled_start_time se lee con RELOJ LITERAL (quirk
#     Bogotá-como-UTC, ver CLAUDE.md).
#   - VTurb es un API externo: si falla, el bloque `vsl` sale null con motivo,
#     y el resto del objeto se emite igual.
#
# Uso: embudo.sh --project NAME [--from YYYY-MM-DD] [--to YYYY-MM-DD]
#                [--meses N] [--json]
#   --project  OBLIGATORIO (el núcleo no presupone proyecto)
#   --meses    profundidad de las series mensuales (default 6)
#   defaults de fechas: el mes calendario en curso (America/Bogota).
#
# Read-only. Alimenta la fuente `embudo` del viz. Siempre emite JSON.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

project="" meses=6
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
    --meses)   meses="$2"; shift 2 ;;
    --json)    shift ;;   # siempre JSON; se acepta por simetría
    -h|--help) sed -n '2,31p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$project" ]] || { echo "Falta --project NAME" >&2; exit 2; }
for d in "$from" "$to"; do
  [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "Fecha inválida: '$d'" >&2; exit 2; }
done
[[ "$meses" =~ ^[0-9]+$ ]] || { echo "--meses debe ser entero" >&2; exit 2; }
pid="$(resolve_project "$project")"
[[ -n "$pid" ]] || { echo "No project matched: $project" >&2; exit 1; }

# ---------- 1/3: todo lo que vive en Postgres, en UNA consulta ----------
read -r -d '' BODY <<'SQL' || true
WITH params AS (
  SELECT :'proj'::uuid AS pid, :'d1'::date AS d1, :'d2'::date AS d2, :meses::int AS meses
),
-- Los leads de la VENTANA con su atribución resuelta (utm de custom_fields,
-- misma resolución de bash/crm/leads.sh) y su etapa actual.
lw AS (
  SELECT o.id, o.status, o.created_date::date AS creada, c.ghl_contact_id,
         coalesce(st.name,'—') AS etapa, utm.src, utm.camp
  FROM crm_opportunities o
  JOIN params ON o.project_id = params.pid
             AND o.created_date::date BETWEEN params.d1 AND params.d2
  LEFT JOIN crm_contacts c ON c.id = o.contact_id
  LEFT JOIN crm_pipelines pl ON pl.id = o.pipeline_id
  LEFT JOIN LATERAL (
    SELECT s->>'name' AS name FROM jsonb_array_elements(pl.stages) s
    WHERE s->>'id' = o.ghl_stage_id LIMIT 1) st ON true
  LEFT JOIN LATERAL (
    SELECT max(CASE WHEN cf.name = 'utm_source'   THEN nullif(x->>'value','') END) AS src,
           max(CASE WHEN cf.name = 'utm_campaign' THEN nullif(x->>'value','') END) AS camp
    FROM jsonb_array_elements(coalesce(c.custom_fields,'[]'::jsonb)) x
    JOIN crm_custom_fields cf
      ON cf.ghl_field_id = x->>'id' AND cf.project_id = o.project_id
    WHERE cf.name IN ('utm_source','utm_campaign')) utm ON true
),
-- El dinero de cada lead: el primer plan del contacto creado entre el lead y
-- +60 días (misma guardia temporal de conversion_real.sh: un plan anterior al
-- lead es un cliente que ya existía, no una conversión de esta campaña).
lw_cash AS (
  SELECT l.id, l.camp, l.status, v.plan_id, v.original_amount, v.cash
  FROM lw l
  LEFT JOIN LATERAL (
    SELECT pp.plan_id, pp.original_amount,
           coalesce((SELECT sum(i.paid_amount) FROM installments i
                     WHERE i.plan_id = pp.plan_id AND i.payment_date IS NOT NULL),0) AS cash
    FROM payment_plans pp
    WHERE l.ghl_contact_id IS NOT NULL
      AND pp.customer_id = l.ghl_contact_id
      AND pp.created_at::date BETWEEN l.creada AND l.creada + 60
    ORDER BY pp.created_at LIMIT 1) v ON true
),
-- Gasto por campaña de la ventana (para el CPL real por UTM).
sp AS (
  SELECT cmp.name, aa.currency AS cur, round(sum(d.spend),2) AS spend
  FROM ad_insights_daily d
  JOIN ad_accounts aa ON aa.id = d.ad_account_id
  JOIN campaigns cmp ON cmp.id = d.campaign_id
  JOIN project_ad_account_mappings map ON map.ad_account_id = d.ad_account_id
  JOIN params ON map.project_id = params.pid
  WHERE d.date_start BETWEEN params.d1 AND params.d2
  GROUP BY 1, 2
),
-- Llamadas de la ventana, con reloj LITERAL (Bogotá etiquetada como UTC).
calls AS (
  SELECT m.id,
         (SELECT length(t.transcript) FROM meeting_transcripts t
          WHERE t.meeting_id = m.id LIMIT 1) AS tlen,
         EXISTS (SELECT 1 FROM call_report_vigente v WHERE v.meeting_id = m.id) AS analizada
  FROM meetings m
  JOIN params ON m.project_id = params.pid
  WHERE m.meeting_type = 'call'
    AND (m.scheduled_start_time AT TIME ZONE 'UTC')::date BETWEEN params.d1 AND params.d2
),
-- Los meses de las series (los últimos :meses, terminando en el mes de d2).
mss AS (
  SELECT (date_trunc('month', (SELECT d2 FROM params))::date
          - (interval '1 month' * g))::date AS m0
  FROM generate_series((SELECT meses FROM params) - 1, 0, -1) g
),
inst_win AS (   -- cash de la ventana (mismo modelo de dashboard.sh)
  SELECT i.installment_number AS n, i.paid_amount AS amt, pp.plan_status
  FROM installments i JOIN payment_plans pp ON pp.plan_id = i.plan_id
  JOIN params ON pp.project_id = params.pid
  WHERE i.payment_date IS NOT NULL
    AND i.payment_date::date BETWEEN params.d1 AND params.d2
),
-- Los planes iniciados en la ventana, cada uno con la oportunidad del CRM que
-- lo respalda (won primero, luego la más reciente) — para explicar el último
-- eslabón: ¿de qué cohorte de lead viene cada venta? Medido 2026-08-21 en DG:
-- 34 planes = 21 won de leads del mes + 7 rezagados (leads previos) + 2 que
-- pagaron con la opp aún `open` (higiene CRM) + 4 cancelados (1 duplicado +
-- 3 PRUEBA con $10 «pagados»). Sin este desglose la UI mostraba 34 vs 21 como
-- si fuera discrepancia.
plw AS (
  SELECT pp.plan_id, pp.plan_status, pp.original_amount,
         o.status AS opp_status, o.created_date::date AS opp_creada
  FROM payment_plans pp JOIN params ON pp.project_id = params.pid
  LEFT JOIN LATERAL (
    SELECT o.status, o.created_date
    FROM crm_opportunities o JOIN crm_contacts c ON c.id = o.contact_id
    WHERE c.ghl_contact_id = pp.customer_id AND o.project_id = params.pid
    ORDER BY (o.status = 'won') DESC, o.created_date DESC LIMIT 1) o ON true
  WHERE pp.start_date BETWEEN params.d1 AND params.d2
),
plv AS (SELECT * FROM plw WHERE plan_status <> 'Cancelled')   -- los que cuentan
SELECT json_build_object(
  'meta', json_build_object(
     'proyecto', :'projname', 'desde', :'d1', 'hasta', :'d2',
     'generado', to_char(now() AT TIME ZONE 'America/Bogota','YYYY-MM-DD HH24:MI'),
     'regla_leads', 'los leads salen del CRM (created_date en ventana), no de ningún Excel',
     'regla_dinero', 'la verdad del dinero es installments/payment_plans; lo de Meta viaja como *_pixel',
     'regla_monedas', 'CAC real y ROAS real solo contra pauta USD; la pauta COP se reporta aparte sin ratios'),

  'pauta', (SELECT coalesce(json_agg(t ORDER BY t.spend DESC),'[]'::json) FROM (
     SELECT aa.currency AS cur, round(sum(d.spend),2) AS spend,
            sum(d.impressions) AS impresiones, sum(d.clicks) AS clics,
            sum(d.link_clicks) AS clics_link, sum(d.landing_page_views) AS aterrizajes,
            sum(d.purchases) AS compras_pixel, round(sum(d.purchase_value),2) AS valor_pixel,
            round(sum(d.clicks)::numeric / nullif(sum(d.impressions),0) * 100, 2) AS ctr,
            round(sum(d.spend) / nullif(sum(d.clicks),0), 2) AS cpc,
            round(sum(d.spend) / nullif(sum(d.impressions),0) * 1000, 2) AS cpm,
            to_char(max(d.date_start),'YYYY-MM-DD') AS ultimo_dato
     FROM ad_insights_daily d
     JOIN ad_accounts aa ON aa.id = d.ad_account_id
     JOIN project_ad_account_mappings map ON map.ad_account_id = d.ad_account_id
     JOIN params ON map.project_id = params.pid
     WHERE d.date_start BETWEEN params.d1 AND params.d2
     GROUP BY 1) t),

  'crm', json_build_object(
     'leads',      (SELECT count(*) FROM lw),
     'pagados',    (SELECT count(*) FROM lw WHERE camp IS NOT NULL),
     'organicos',  (SELECT count(*) FROM lw WHERE camp IS NULL),
     'ganadas',    (SELECT count(*) FROM lw WHERE status = 'won'),
     'por_etapa',  (SELECT coalesce(json_agg(t ORDER BY t.n DESC),'[]'::json) FROM (
                      SELECT etapa, count(*) AS n,
                             count(*) FILTER (WHERE status='won') AS ganadas
                      FROM lw GROUP BY 1) t),
     'llamadas', json_build_object(
        'total',          (SELECT count(*) FROM calls),
        'con_transcript', (SELECT count(*) FROM calls WHERE tlen >= 2000),
        'analizadas',     (SELECT count(*) FROM calls WHERE analizada))),

  'ventas', json_build_object(
     'planes_iniciados', (SELECT count(*) FROM plv),
     'valor_contrato',   (SELECT round(coalesce(sum(original_amount),0),2) FROM plv),
     'planes_por_origen', (SELECT json_build_object(
        'won_lead_ventana', count(*) FILTER (WHERE opp_status='won' AND opp_creada BETWEEN (SELECT d1 FROM params) AND (SELECT d2 FROM params)),
        'won_lead_previo',  count(*) FILTER (WHERE opp_status='won' AND opp_creada < (SELECT d1 FROM params)),
        'opp_abierta',      count(*) FILTER (WHERE opp_status IS NOT NULL AND opp_status <> 'won'),
        'sin_opp',          count(*) FILTER (WHERE opp_status IS NULL),
        'nota', 'won_lead_ventana es la cohorte comparable con crm.ganadas; won_lead_previo son rezagados (leads de meses anteriores que compraron ahora); opp_abierta = pagaron y el CRM no los movió a venta (higiene)')
        FROM plv),
     'excluidos', (SELECT json_build_object(
        'planes_cancelados', count(*),
        'valor_contrato', round(coalesce(sum(original_amount),0),2),
        'motivo', 'plan_status=Cancelled: duplicados y pruebas no son ventas; no entran a planes_iniciados ni a valor_contrato')
        FROM plw WHERE plan_status = 'Cancelled'),
     'cash_en_cancelados', (SELECT round(coalesce(sum(amt),0),2) FROM inst_win WHERE plan_status = 'Cancelled'),
     'primeras_cuotas',  (SELECT count(*) FROM inst_win WHERE n = 1),
     'cash_nuevas',      (SELECT round(coalesce(sum(amt) FILTER (WHERE n = 1),0),2) FROM inst_win),
     'cash_cuotas',      (SELECT round(coalesce(sum(amt) FILTER (WHERE n >= 2),0),2) FROM inst_win),
     'cash_total',       (SELECT round(coalesce(sum(amt),0),2) FROM inst_win),
     'mezcla_planes',    (SELECT coalesce(json_agg(t ORDER BY t.n DESC),'[]'::json) FROM (
                            -- OJO al join: products.id (uuid) = pp.product_uuid.
                            -- El product_id de texto es el id de GHL y solo casa
                            -- en ~1/3 de los planes (medido 2026-08-20: 127 vs 362).
                            SELECT coalesce(pr.name,'— sin producto') AS producto, count(*) AS n,
                                   round(sum(pp.original_amount),2) AS valor_contrato
                            FROM payment_plans pp
                            LEFT JOIN products pr ON pr.id = pp.product_uuid
                            JOIN params ON pp.project_id = params.pid
                            WHERE pp.start_date BETWEEN params.d1 AND params.d2
                              AND pp.plan_status <> 'Cancelled'
                            GROUP BY 1) t),
     'mezcla_crm',       (SELECT coalesce(json_agg(t ORDER BY t.n DESC),'[]'::json) FROM (
                            SELECT etapa, count(*) AS n FROM lw
                            WHERE status = 'won' GROUP BY 1) t)),

  'cuotas', json_build_object(
     'nota', 'la medición mensual acordada en la reunión del 19: cuánto entra, cuántos planes pagan de los que deben, quiénes empiezan y quiénes dejan',
     'serie', (SELECT coalesce(json_agg(t ORDER BY t.mes),'[]'::json) FROM (
        SELECT to_char(m0,'YYYY-MM') AS mes,
               cobr.cobrado, cobr.cobrado_cuotas,
               round(cobr.cobrado_cuotas / greatest(1, least(
                  (m0 + interval '1 month')::date - m0,
                  (current_date - m0) + 1)), 2) AS prom_dia_cuotas,
               round(cobr.cobrado / greatest(1, least(
                  (m0 + interval '1 month')::date - m0,
                  (current_date - m0) + 1)), 2) AS prom_dia,
               deb.planes_debian, deb.planes_pagaron,
               round(100.0 * deb.planes_pagaron / nullif(deb.planes_debian,0), 1) AS pct_pagando,
               emp.empiezan, dej.dejan
        FROM mss
        LEFT JOIN LATERAL (
           SELECT round(coalesce(sum(i.paid_amount),0),2) AS cobrado,
                  round(coalesce(sum(i.paid_amount) FILTER (WHERE i.installment_number >= 2),0),2) AS cobrado_cuotas
           FROM installments i JOIN payment_plans pp ON pp.plan_id = i.plan_id
           JOIN params ON pp.project_id = params.pid
           WHERE i.payment_date IS NOT NULL
             AND date_trunc('month', i.payment_date::date) = m0) cobr ON true
        LEFT JOIN LATERAL (
           SELECT count(DISTINCT pp.plan_id) AS planes_debian,
                  count(DISTINCT pp.plan_id) FILTER (WHERE i.status = 'Paid') AS planes_pagaron
           FROM installments i JOIN payment_plans pp ON pp.plan_id = i.plan_id
           JOIN params ON pp.project_id = params.pid
           WHERE date_trunc('month', i.due_date) = m0
             AND i.due_date < current_date) deb ON true
        LEFT JOIN LATERAL (
           SELECT count(DISTINCT pp.plan_id) AS empiezan
           FROM installments i JOIN payment_plans pp ON pp.plan_id = i.plan_id
           JOIN params ON pp.project_id = params.pid
           WHERE i.installment_number = 1 AND i.payment_date IS NOT NULL
             AND date_trunc('month', i.payment_date::date) = m0) emp ON true
        LEFT JOIN LATERAL (
           -- «dejan»: planes con cuota vencida ese mes sin pagar, que SÍ habían
           -- pagado algo antes — el cliente que venía pagando y paró.
           SELECT count(DISTINCT pp.plan_id) AS dejan
           FROM installments i JOIN payment_plans pp ON pp.plan_id = i.plan_id
           JOIN params ON pp.project_id = params.pid
           WHERE date_trunc('month', i.due_date) = m0
             AND i.due_date < current_date AND i.status <> 'Paid'
             AND EXISTS (SELECT 1 FROM installments i2
                         WHERE i2.plan_id = pp.plan_id AND i2.payment_date IS NOT NULL
                           AND i2.payment_date::date < m0)) dej ON true) t)),

  'atribucion', (SELECT coalesce(json_agg(t ORDER BY t.leads DESC),'[]'::json) FROM (
     SELECT coalesce(l.camp,'— sin atribución (orgánico/directo)') AS campana,
            count(*) AS leads,
            count(*) FILTER (WHERE l.status = 'won') AS ganadas,
            count(lc.plan_id) AS planes,
            round(coalesce(sum(lc.original_amount),0),2) AS valor_contrato,
            round(coalesce(sum(lc.cash),0),2) AS cash,
            max(sp.spend) AS spend, max(sp.cur) AS cur,
            round(max(sp.spend) / nullif(count(*),0), 2) AS cpl_real
     FROM lw l
     LEFT JOIN lw_cash lc ON lc.id = l.id
     LEFT JOIN sp ON sp.name = l.camp
     GROUP BY 1) t),

  'series', (SELECT coalesce(json_agg(t ORDER BY t.mes),'[]'::json) FROM (
     SELECT to_char(m0,'YYYY-MM') AS mes,
            pa.spend_usd, pa.spend_cop,
            ld.leads, pl.planes, ca.cash,
            round(pa.spend_usd / nullif(pl.planes,0), 2) AS cac_real,
            round(ca.cash / nullif(pa.spend_usd,0), 2) AS roas_real
     FROM mss
     LEFT JOIN LATERAL (
        SELECT round(coalesce(sum(d.spend) FILTER (WHERE aa.currency='USD'),0),2) AS spend_usd,
               round(coalesce(sum(d.spend) FILTER (WHERE aa.currency='COP'),0),2) AS spend_cop
        FROM ad_insights_daily d
        JOIN ad_accounts aa ON aa.id = d.ad_account_id
        JOIN project_ad_account_mappings map ON map.ad_account_id = d.ad_account_id
        JOIN params ON map.project_id = params.pid
        WHERE date_trunc('month', d.date_start) = m0) pa ON true
     LEFT JOIN LATERAL (
        SELECT count(*) AS leads FROM crm_opportunities o JOIN params ON o.project_id = params.pid
        WHERE date_trunc('month', o.created_date::date) = m0) ld ON true
     LEFT JOIN LATERAL (
        SELECT count(*) AS planes FROM payment_plans pp JOIN params ON pp.project_id = params.pid
        WHERE date_trunc('month', pp.start_date) = m0) pl ON true
     LEFT JOIN LATERAL (
        SELECT round(coalesce(sum(i.paid_amount),0),2) AS cash
        FROM installments i JOIN payment_plans pp ON pp.plan_id = i.plan_id
        JOIN params ON pp.project_id = params.pid
        WHERE i.payment_date IS NOT NULL
          AND date_trunc('month', i.payment_date::date) = m0) ca ON true) t),

  'frescura', json_build_object(
     'ads_ultimo_dato', (SELECT to_char(max(d.date_start),'YYYY-MM-DD')
        FROM ad_insights_daily d
        JOIN project_ad_account_mappings map ON map.ad_account_id = d.ad_account_id
        JOIN params ON map.project_id = params.pid),
     'crm_ultima_ingesta', (SELECT to_char(max(created_at),'YYYY-MM-DD') FROM crm_contacts),
     'crm_ultima_opp', (SELECT to_char(max(o.created_date),'YYYY-MM-DD')
        FROM crm_opportunities o JOIN params ON o.project_id = params.pid),
     'ultima_llamada', (SELECT to_char(max((m.scheduled_start_time AT TIME ZONE 'UTC')::date),'YYYY-MM-DD')
        FROM meetings m JOIN params ON m.project_id = params.pid
        WHERE m.meeting_type = 'call'),
     'ultimo_pago', (SELECT to_char(max(i.payment_date::date),'YYYY-MM-DD')
        FROM installments i JOIN payment_plans pp ON pp.plan_id = i.plan_id
        JOIN params ON pp.project_id = params.pid
        WHERE i.payment_date IS NOT NULL),
     'nota_crm', 'crm_ultima_ingesta es la corrida del ingestor (pagina de a 100, disparado a mano): si lleva días quieta, los leads del CRM subcuentan — julio perdió 202 así')
)::text
SQL

PG_JSON="$(printf '%s\n' "$BODY" \
  | psql_ro -t -A -v proj="$pid" -v projname="$project" -v d1="$from" -v d2="$to" -v meses="$meses")"

# ---------- 2/3: VTurb (API externo — su falla no tumba el objeto) ----------
VT_JSON="null" VT_ERR=""
if VT_OUT="$("$(dirname "$0")/../vturb/analitica.sh" --project "$project" --from "$from" --to "$to" --json 2>&1)"; then
  VT_JSON="$VT_OUT"
else
  VT_ERR="$(printf '%s' "$VT_OUT" | tail -1)"
fi

# ---------- 3/3: fusión + derivados + conciliación (stdlib) ----------
PG_JSON="$PG_JSON" VT_JSON="$VT_JSON" VT_ERR="$VT_ERR" python3 - <<'PY'
import json, os, datetime

obj = json.loads(os.environ["PG_JSON"])
vt_raw, vt_err = os.environ["VT_JSON"], os.environ["VT_ERR"]

# --- VSL (VTurb): agregado + por-video, sin histogramas (payload) ---
vsl = None
try:
    vt = json.loads(vt_raw) if vt_raw and vt_raw != "null" else None
except json.JSONDecodeError:
    vt, vt_err = None, (vt_err or "respuesta VTurb no es JSON")
if vt and vt.get("videos"):
    vids = []
    tot = {"impresiones": 0, "plays": 0, "pasaron_pitch": 0, "cta_clicks": 0, "terminaron": 0}
    for v in vt["videos"]:
        vids.append({k: v.get(k) for k in (
            "video_id", "titulo", "duracion", "impresiones_unicas", "plays_unicos",
            "tasa_play", "ret_25", "ret_50", "ret_75", "tasa_fin",
            "pasaron_pitch", "tasa_pitch", "cta_clicks", "avg_visto_seg", "engagement_rate")})
        tot["impresiones"] += v.get("impresiones_unicas") or 0
        tot["plays"] += v.get("plays_unicos") or 0
        tot["pasaron_pitch"] += v.get("pasaron_pitch") or 0
        tot["cta_clicks"] += v.get("cta_clicks") or 0
        tot["terminaron"] += v.get("terminaron") or 0
    pct = lambda a, b: round(100.0 * a / b, 1) if b else None
    vsl = {"fuente": "vturb (live)", "ventana": vt.get("ventana"),
           "total": {**tot,
                     "tasa_play": pct(tot["plays"], tot["impresiones"]),
                     "tasa_pitch": pct(tot["pasaron_pitch"], tot["plays"]),
                     "tasa_cta": pct(tot["cta_clicks"], tot["plays"])},
           "videos": vids}
obj["vsl"] = vsl if vsl else {"error": vt_err or "sin datos VTurb para el proyecto", "fuente": "vturb (live)"}

# --- derivados de la ventana (solo USD, regla de monedas) ---
pauta_usd = next((p for p in obj.get("pauta", []) if p.get("cur") == "USD"), None)
v = obj.get("ventas", {})
spend = float(pauta_usd["spend"]) if pauta_usd else 0.0
planes = v.get("planes_iniciados") or 0
cash = float(v.get("cash_total") or 0)
obj["kpis"] = {
    "spend_usd": round(spend, 2),
    "leads": obj.get("crm", {}).get("leads"),
    "cpl_real": round(spend / obj["crm"]["leads"], 2) if spend and obj.get("crm", {}).get("leads") else None,
    "planes_iniciados": planes,
    "cac_real": round(spend / planes, 2) if spend and planes else None,
    "cash_total": cash,
    "roas_real": round(cash / spend, 2) if spend else None,
    "roas_pixel": (round(float(pauta_usd["valor_pixel"]) / spend, 2)
                   if pauta_usd and spend and pauta_usd.get("valor_pixel") else None),
    "nota": "CAC real = pauta USD / planes iniciados · ROAS real = cash cobrado / pauta USD (el pixel viaja aparte)",
}

# --- conciliación: los handoffs entre fuentes, con delta calculado ---
conc = []
def fila(handoff, a_label, a, b_label, b, nota):
    delta = (b - a) if (a is not None and b is not None) else None
    pct = round(100.0 * b / a, 1) if a and b is not None else None
    conc.append({"handoff": handoff, "a": a_label, "valor_a": a,
                 "b": b_label, "valor_b": b, "delta": delta, "pct_traspaso": pct, "nota": nota})

if pauta_usd and vsl and vsl.get("total"):
    fila("pauta → página", "aterrizajes Meta (LPV)", pauta_usd.get("aterrizajes"),
         "impresiones del player (VTurb)", vsl["total"]["impresiones"],
         "si el player ve MENOS que los LPV: gente que aterriza y no llega a cargar el player (velocidad/página rota); si ve MÁS: la página recibe tráfico que Meta no pagó (orgánico, remarketing, directo)")
if vsl and vsl.get("total"):
    fila("página → formulario", "clics al CTA (VTurb)", vsl["total"]["cta_clicks"],
         "leads creados (CRM)", obj.get("crm", {}).get("leads"),
         "cuántos clics al botón terminaron en lead; aquí vive la fuga de la pregunta del capital")
crm_won = obj.get("crm", {}).get("ganadas")
origen = v.get("planes_por_origen") or {}
fila("ventas: pixel vs caja", "compras pixel (Meta)",
     int(pauta_usd["compras_pixel"]) if pauta_usd and pauta_usd.get("compras_pixel") is not None else None,
     "planes iniciados (caja, sin cancelados)", planes,
     "el pixel atribuye, la caja cobra; si difieren mucho, hay ventas sin plan o pixel sobre-atribuyendo")
fila("ventas: CRM vs caja (misma cohorte)", "ganadas CRM de leads de la ventana", crm_won,
     "planes de esos mismos leads", origen.get("won_lead_ventana"),
     "peras con peras: el resto de los planes son rezagados (" + str(origen.get("won_lead_previo", "—"))
     + " de leads previos), opps aún abiertas (" + str(origen.get("opp_abierta", "—"))
     + ", higiene CRM) o sin opp (" + str(origen.get("sin_opp", "—")) + ")")
fila("caja: contrato vs cobro", "valor contrato (planes)", v.get("valor_contrato"),
     "cash cobrado", cash,
     "lo firmado vs lo que entró; la brecha es cartera por cobrar de las ventas de la ventana")
obj["conciliacion"] = conc

# --- frescura: lags + alertas ---
f = obj.get("frescura", {})
hoy = datetime.date.today()
def lag(k):
    s = f.get(k)
    if not s: return None
    try: return (hoy - datetime.date.fromisoformat(s)).days
    except ValueError: return None
f["ads_lag_dias"] = lag("ads_ultimo_dato")
f["crm_ingesta_lag_dias"] = lag("crm_ultima_ingesta")
f["vturb"] = "ok (live)" if vsl and not vsl.get("error") else f"error: {vt_err or 'sin datos'}"
alertas = []
if (f.get("crm_ingesta_lag_dias") or 0) > 7:
    alertas.append(f"el ingestor CRM lleva {f['crm_ingesta_lag_dias']} días sin correr: los leads del CRM subcuentan (correr node scripts/backfill-ghl.js)")
if (f.get("ads_lag_dias") or 0) > 3:
    alertas.append(f"los insights de Meta atrasan {f['ads_lag_dias']} días: el spend de los últimos días está incompleto")
if vsl and vsl.get("error"):
    alertas.append("VTurb no respondió: el tramo VSL del embudo viene vacío en esta corrida")
cc = float(v.get("cash_en_cancelados") or 0)
exc = v.get("excluidos") or {}
if cc > 0:
    alertas.append(f"${cc:,.0f} cobrados en planes CANCELADOS dentro de la ventana ({exc.get('planes_cancelados', 0)} planes: duplicados/pruebas) — están dentro de cash_total; si son pruebas, hay que borrarlas en la app")
f["alertas"] = alertas
obj["frescura"] = f

obj["sin_instrumentar"] = [
    {"tramo": "velocidad de carga de la página", "estado": "sin fuente (no hay PageSpeed en la base); la reunión la mide a mano: 60→53, objetivo 80"},
    {"tramo": "embudo orgánico (ManyChat/DM)", "estado": "las etiquetas de ManyChat apenas se están montando (tarea de Lucho→Juanca del 19-ago)"},
]

print(json.dumps(obj, ensure_ascii=False))
PY

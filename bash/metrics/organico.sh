#!/usr/bin/env bash
# organico.sh — EL EMBUDO ORGÁNICO de un proyecto, en un objeto: los leads del
# CRM que NO llegaron por pauta (ni campaña en la atribución nativa de GHL ni
# utm_campaign del formulario), clasificados por CANAL DE ENTRADA — la serie de
# YouTube (y su módulo), los lead magnets, el survey orgánico, el survey del
# VSL sin pauta, masterclass, low ticket, aplicación premium, referidos — con
# la sesión que registró GHL (Social media · Referral · Direct traffic), su
# conversión (won, planes ≤60 d, contrato, cash) y, al lado, la PAUTA DE MARCA
# del mismo mes (follow-me / seguidores / video: los anuncios `tipo=marca` de
# anuncios.sh) para leer el costo de lo «gratis». Hueco #3 del contraste con
# el dashboard comercial (Kaizen 2026-08-20).
#
# Lo que este script NO hace y lo declara: no cuenta suscriptores/DMs de
# ManyChat. Medido el 2026-08-21 (bash/manychat/README.md): el API no lista
# suscriptores, los de Instagram no traen email/teléfono (0/8 por
# findBySystemField) y por nombre matchea 14/79 con falsos positivos
# probables. Lo que sí da, y aquí viaja como `manychat.mapa`, es el vocabulario
# de tags del flujo (nuevo seguidor → quiz → pide asesoría → serie YT módulos
# → lead magnets → grupo VIP): el MAPA del embudo orgánico sin sus conteos. La
# llave exacta (que el flujo escriba ig_username/subscriber id en el contacto
# de GHL) es un pedido pendiente.
#
# Reglas:
#   - orgánico = lead del CRM (created_date en ventana) SIN campaña por ninguna
#     de las dos fuentes (misma regla de embudo.sh/leads.sh). Es «no pagado»,
#     no «llegó solo»: la pauta de marca y el contenido pagan parte de esto.
#   - canal = regex sobre lower(ghl_source) (el formulario de entrada que GHL
#     guarda) y, si el form no dice, sobre los tags del contacto (moduloNyt,
#     leadmagnetN, quiz…); la sesión de GHL va aparte (dice cómo llegó al
#     form, no qué form).
#   - dinero = primer plan del contacto ≤60 d del lead, cuotas pagadas (misma
#     guardia de embudo.sh). `roas_vs_marca` = cash orgánico / pauta de marca
#     USD del mismo mes: HEURÍSTICO y declarado (la pauta de marca no es la
#     única causa del orgánico, y el orgánico de hoy viene de seguidores de
#     meses atrás).
#
# Uso: organico.sh --project NAME [--from D] [--to D] [--meses N] [--json]
#   default: mes en curso (Bogotá); --meses N = serie mensual (default 6).
#   Siempre emite JSON. Read-only: Postgres (psql_ro) + GET a ManyChat
#   (solo page/getTags, si hay MANYCHAT_TOKEN_DG o MANYCHAT_TOKEN_B en .env).
#   Fuente viz `embudo_organico` → page `organico` (UI ejecutivo `embudo-organico`).
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 1
source bash/lib/common.sh

project="" meses=6
from="$(TZ="$TZ_DEFAULT" date +%Y-%m-01)"
_y="$(TZ="$TZ_DEFAULT" date +%Y)" _m="$(TZ="$TZ_DEFAULT" date +%m)"
case "${_m#0}" in 4|6|9|11) _d=30 ;; 2) _d=28; (( (_y % 4 == 0 && _y % 100 != 0) || _y % 400 == 0 )) && _d=29 ;; *) _d=31 ;; esac
to="${_y}-${_m}-${_d}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) project="$2"; shift 2 ;;
    --from)    from="$2"; shift 2 ;;
    --to)      to="$2"; shift 2 ;;
    --meses)   meses="$2"; shift 2 ;;
    --json)    shift ;;
    -h|--help) sed -n '2,43p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$project" ]] || { echo "Falta --project NAME" >&2; exit 2; }
for d in "$from" "$to"; do [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "Fecha inválida: $d" >&2; exit 2; }; done
[[ "$meses" =~ ^[0-9]+$ ]] || { echo "--meses debe ser entero" >&2; exit 2; }
pid="$(resolve_project "$project")"; [[ -n "$pid" ]] || { echo "No project matched: $project" >&2; exit 1; }

read -r -d '' BODY <<'SQL' || true
WITH params AS (SELECT :'proj'::uuid AS pid, :'d1'::date AS d1, :'d2'::date AS d2, :meses::int AS meses),
-- Todos los leads desde el inicio de la serie (la ventana y los meses atrás),
-- con su atribución (dos fuentes), formulario, tags y sesión de GHL.
base AS (
  SELECT o.id, o.status, o.created_date::date AS creada, c.ghl_contact_id,
         date_trunc('month', o.created_date)::date AS mes,
         (ca.name IS NOT NULL OR utm.camp IS NOT NULL OR coalesce(c.attr_ad_id ~ '^[0-9]+$', false)) AS pagado,
         lower(coalesce(c.ghl_source,'')) AS form,
         coalesce(c.tags,'{}') AS tags,
         coalesce(coalesce(c.last_attribution_source, c.attribution_source)->>'sessionSource','(sin sesión)') AS sesion
  FROM crm_opportunities o
  JOIN params ON o.project_id = params.pid
             AND o.created_date::date >= (date_trunc('month', params.d1) - (params.meses - 1) * interval '1 month')::date
             AND o.created_date::date <= params.d2
  LEFT JOIN crm_contacts c ON c.id = o.contact_id
  LEFT JOIN campaigns ca ON ca.id = c.attr_campaign_id
  LEFT JOIN LATERAL (
    SELECT max(CASE WHEN cf.name = 'utm_campaign' THEN nullif(x->>'value','') END) AS camp
    FROM jsonb_array_elements(coalesce(c.custom_fields,'[]'::jsonb)) x
    JOIN crm_custom_fields cf ON cf.ghl_field_id = x->>'id' AND cf.project_id = o.project_id
    WHERE cf.name = 'utm_campaign') utm ON true
),
-- El canal de entrada: primero el formulario, si no dice, los tags.
canal AS (
  SELECT b.*,
    CASE
      -- primero el FORMULARIO (lo que creó el lead), después los tags (lo que vio antes)
      WHEN b.form ~ 'serie yt' THEN 'serie_youtube'
      WHEN b.form ~ 'lead magnet' THEN 'lead_magnet'
      WHEN b.form ~ 'david bala' THEN 'referido_bala'
      WHEN b.form ~ 'masterclass' THEN 'masterclass'
      WHEN b.form ~ 'low ticket|payment_link' THEN 'low_ticket'
      WHEN b.form ~ 'premium|aplicaci|calendario|agenda tu llamada|setter' THEN 'aplicacion_premium'
      WHEN b.form ~ 'org[aá]nico' THEN 'survey_organico'
      WHEN b.form ~ 'survey mastermind - vsl' THEN 'survey_vsl_sin_pauta'
      WHEN b.form ~ '^survey mastermind' THEN 'survey_organico'
      WHEN b.form <> '' THEN 'otro_formulario'
      WHEN EXISTS (SELECT 1 FROM unnest(b.tags) t WHERE t ~ '^modulo[0-9]+yt$') THEN 'serie_youtube'
      WHEN EXISTS (SELECT 1 FROM unnest(b.tags) t WHERE t ~ '^leadmagnet[0-9]+$') THEN 'lead_magnet'
      WHEN 'lt' = ANY(b.tags) THEN 'low_ticket'
      WHEN 'lleno encuesta organico' = ANY(b.tags) OR 'lleno encuesta' = ANY(b.tags) THEN 'survey_organico'
      ELSE 'sin_formulario'
    END AS canal,
    -- el módulo de la serie de YouTube (del form «Form serie YT M5» o del tag moduloNyt): el escalón
    coalesce(substring(b.form from 'serie yt m([0-9]+)'),
             (SELECT max(substring(t from '^modulo([0-9]+)yt$')) FROM unnest(b.tags) t WHERE t ~ '^modulo[0-9]+yt$')) AS modulo_yt
  FROM base b
),
-- El dinero de cada lead (misma guardia de embudo.sh: primer plan ≤60 d).
cash AS (
  SELECT l.id, v.plan_id, v.original_amount, v.cash
  FROM canal l
  LEFT JOIN LATERAL (
    SELECT pp.plan_id, pp.original_amount,
           coalesce((SELECT sum(i.paid_amount) FROM installments i
                     WHERE i.plan_id = pp.plan_id AND i.payment_date IS NOT NULL),0) AS cash
    FROM payment_plans pp
    WHERE l.ghl_contact_id IS NOT NULL AND pp.customer_id = l.ghl_contact_id
      AND pp.created_at::date BETWEEN l.creada AND l.creada + 60
    ORDER BY pp.created_at LIMIT 1) v ON true
),
lc AS (SELECT c.*, k.plan_id, k.original_amount, k.cash FROM canal c LEFT JOIN cash k ON k.id = c.id),
w AS (SELECT * FROM lc, params WHERE creada BETWEEN params.d1 AND params.d2),
-- Pauta de MARCA por mes (misma regla de anuncios.sh: objetivo de marca, o
-- anuncios con ≥50 clics al link y LPV ≤ 2% — tráfico al perfil, no a la landing).
ads_m AS (
  SELECT date_trunc('month', d.date_start)::date AS mes, d.ad_id, aa.currency AS cur,
         sum(d.spend) AS spend,
         (c.objective IN ('OUTCOME_AWARENESS','OUTCOME_ENGAGEMENT','POST_ENGAGEMENT','PAGE_LIKES','VIDEO_VIEWS','REACH','BRAND_AWARENESS')
          OR (sum(d.link_clicks) >= 50 AND sum(d.landing_page_views) <= 0.02*sum(d.link_clicks))) AS marca
  FROM ad_insights_daily d
  JOIN project_ad_account_mappings map ON map.ad_account_id = d.ad_account_id
  JOIN params ON map.project_id = params.pid
  JOIN ad_accounts aa ON aa.id = d.ad_account_id
  LEFT JOIN campaigns c ON c.id = d.campaign_id
  WHERE d.date_start >= (date_trunc('month', params.d1) - (params.meses - 1) * interval '1 month')::date
    AND d.date_start <= params.d2
  GROUP BY 1, 2, 3, c.objective
),
marca_m AS (
  SELECT mes,
         round(coalesce(sum(spend) FILTER (WHERE marca AND cur='USD'),0),2) AS marca_usd,
         round(coalesce(sum(spend) FILTER (WHERE marca AND cur='COP'),0),2) AS marca_cop,
         round(coalesce(sum(spend) FILTER (WHERE NOT marca AND cur='USD'),0),2) AS adquisicion_usd,
         count(DISTINCT ad_id) FILTER (WHERE marca) AS ads_marca
  FROM ads_m GROUP BY 1
),
mss AS (SELECT generate_series(date_trunc('month', params.d1) - (params.meses - 1) * interval '1 month', date_trunc('month', params.d1), interval '1 month')::date AS m0 FROM params)
SELECT json_build_object(
  'meta', json_build_object(
     'proyecto', :'projname', 'desde', :'d1', 'hasta', :'d2', 'meses', (SELECT meses FROM params),
     'generado', to_char(now() AT TIME ZONE 'America/Bogota','YYYY-MM-DD HH24:MI'),
     'regla_organico', 'lead del CRM (created_date en ventana) sin campaña ni en la atribución nativa de GHL (crm_contacts.attr_campaign_id) ni en el utm_campaign del formulario, y sin ad_id de Meta — es «no pagado», no «llegó solo»',
     'regla_canal', 'canal = regex sobre el formulario de entrada (ghl_source) y, si no dice, sobre los tags del contacto (moduloNyt, leadmagnetN, lleno encuesta organico…); la sesión de GHL (Social media · Referral · Direct) va aparte',
     'regla_dinero', 'primer plan del contacto ≤60 d del lead; cash = cuotas pagadas (misma guardia de embudo.sh)',
     'regla_marca', 'pauta de marca = anuncios tipo=marca de anuncios.sh (objetivo de marca o LPV ≤2% de los clics); roas_vs_marca = cash orgánico / marca USD del mes — heurístico: el orgánico de hoy viene de seguidores de meses atrás y la marca no es su única causa'),
  'resumen', (SELECT json_build_object(
     'leads_total', count(*),
     'organicos', count(*) FILTER (WHERE NOT pagado),
     'pagados', count(*) FILTER (WHERE pagado),
     'pct_organico', round(100.0 * count(*) FILTER (WHERE NOT pagado) / nullif(count(*),0), 1),
     'won', count(*) FILTER (WHERE NOT pagado AND status = 'won'),
     'planes', count(plan_id) FILTER (WHERE NOT pagado),
     'contrato', round(coalesce(sum(original_amount) FILTER (WHERE NOT pagado),0),2),
     'cash', round(coalesce(sum(cash) FILTER (WHERE NOT pagado),0),2),
     'tasa_plan', round(100.0 * count(plan_id) FILTER (WHERE NOT pagado) / nullif(count(*) FILTER (WHERE NOT pagado),0), 1),
     'tasa_plan_pagados', round(100.0 * count(plan_id) FILTER (WHERE pagado) / nullif(count(*) FILTER (WHERE pagado),0), 1),
     'cash_pagados', round(coalesce(sum(cash) FILTER (WHERE pagado),0),2),
     'marca_usd', (SELECT round(coalesce(sum(marca_usd),0),2) FROM marca_m WHERE mes BETWEEN date_trunc('month',(SELECT d1 FROM params)) AND (SELECT d2 FROM params)),
     'marca_cop', (SELECT round(coalesce(sum(marca_cop),0),2) FROM marca_m WHERE mes BETWEEN date_trunc('month',(SELECT d1 FROM params)) AND (SELECT d2 FROM params)),
     'ads_marca', (SELECT coalesce(sum(ads_marca),0) FROM marca_m WHERE mes BETWEEN date_trunc('month',(SELECT d1 FROM params)) AND (SELECT d2 FROM params)))
     FROM w),
  'canales', (SELECT coalesce(json_agg(t ORDER BY t.leads DESC),'[]'::json) FROM (
     SELECT canal, count(*) AS leads,
            count(*) FILTER (WHERE status='won') AS won,
            count(plan_id) AS planes,
            round(coalesce(sum(original_amount),0),2) AS contrato,
            round(coalesce(sum(cash),0),2) AS cash,
            round(100.0 * count(plan_id) / nullif(count(*),0), 1) AS tasa_plan,
            (SELECT json_agg(json_build_object('sesion', s.sesion, 'n', s.n) ORDER BY s.n DESC)
               FROM (SELECT sesion, count(*) AS n FROM w w2 WHERE NOT w2.pagado AND w2.canal = w.canal GROUP BY 1) s) AS sesiones,
            (SELECT json_agg(json_build_object('form', f.form, 'n', f.n) ORDER BY f.n DESC)
               FROM (SELECT form, count(*) AS n FROM w w3 WHERE NOT w3.pagado AND w3.canal = w.canal GROUP BY 1 ORDER BY 2 DESC LIMIT 6) f) AS formularios
     FROM w WHERE NOT pagado GROUP BY canal) t),
  'serie_youtube', (SELECT coalesce(json_agg(t ORDER BY t.modulo),'[]'::json) FROM (
     SELECT coalesce(modulo_yt,'?') AS modulo, count(*) AS leads,
            count(*) FILTER (WHERE status='won') AS won, count(plan_id) AS planes, round(coalesce(sum(cash),0),2) AS cash
     FROM w WHERE NOT pagado AND canal = 'serie_youtube' GROUP BY 1) t),
  'sesiones', (SELECT coalesce(json_agg(t ORDER BY t.leads DESC),'[]'::json) FROM (
     SELECT sesion, count(*) AS leads, count(*) FILTER (WHERE status='won') AS won, count(plan_id) AS planes, round(coalesce(sum(cash),0),2) AS cash
     FROM w WHERE NOT pagado GROUP BY 1) t),
  'series', (SELECT coalesce(json_agg(t ORDER BY t.mes),'[]'::json) FROM (
     SELECT to_char(m0,'YYYY-MM') AS mes,
            (SELECT count(*) FROM lc WHERE lc.mes = m0) AS leads,
            (SELECT count(*) FROM lc WHERE lc.mes = m0 AND NOT pagado) AS organicos,
            (SELECT count(*) FROM lc WHERE lc.mes = m0 AND pagado) AS pagados,
            (SELECT count(plan_id) FROM lc WHERE lc.mes = m0 AND NOT pagado) AS planes_organicos,
            (SELECT round(coalesce(sum(cash),0),2) FROM lc WHERE lc.mes = m0 AND NOT pagado) AS cash_organico,
            (SELECT count(plan_id) FROM lc WHERE lc.mes = m0 AND pagado) AS planes_pagados,
            (SELECT round(coalesce(sum(cash),0),2) FROM lc WHERE lc.mes = m0 AND pagado) AS cash_pagado,
            (SELECT count(*) FROM lc WHERE lc.mes = m0 AND NOT pagado AND canal = 'serie_youtube') AS serie_youtube,
            coalesce(mm.marca_usd,0) AS marca_usd, coalesce(mm.adquisicion_usd,0) AS adquisicion_usd,
            round((SELECT coalesce(sum(cash),0) FROM lc WHERE lc.mes = m0 AND NOT pagado) / nullif(mm.marca_usd,0), 2) AS roas_vs_marca
     FROM mss LEFT JOIN marca_m mm ON mm.mes = m0) t)
)
SQL
OBJ="$(psql_ro -t -A -v proj="$pid" -v projname="$project" -v d1="$from" -v d2="$to" -v meses="$meses" <<<"$BODY")"

# ---------- ManyChat: solo el MAPA del flujo (tags), nunca conteos ----------
MC_TAGS='null'; MC_ERR=''
tok="${MANYCHAT_TOKEN_DG:-${MANYCHAT_TOKEN_B:-}}"
if [[ -n "$tok" ]]; then
  MC_TAGS="$(curl -s --max-time 10 -H @<(printf 'Authorization: Bearer %s\n' "$tok") "https://api.manychat.com/fb/page/getTags" 2>/dev/null \
    | python3 -c "import json,sys
try:
    d=json.load(sys.stdin); print(json.dumps([t['name'] for t in d.get('data',[])], ensure_ascii=False))
except Exception as e:
    print('null')" || echo null)"
  [[ "$MC_TAGS" == "null" ]] && MC_ERR="ManyChat no respondió"
else
  MC_ERR="sin MANYCHAT_TOKEN_DG/MANYCHAT_TOKEN_B en .env"
fi

OBJ="$OBJ" MC_TAGS="$MC_TAGS" MC_ERR="$MC_ERR" python3 - <<'PY'
import json, os
obj = json.loads(os.environ["OBJ"])
tags = json.loads(os.environ["MC_TAGS"]) if os.environ["MC_TAGS"] else None
r = obj.get("resumen") or {}
r["roas_vs_marca"] = round(float(r["cash"]) / float(r["marca_usd"]), 2) if r.get("marca_usd") and float(r["marca_usd"]) > 0 else None
r["costo_por_lead_organico_vs_marca"] = round(float(r["marca_usd"]) / r["organicos"], 2) if r.get("organicos") and r.get("marca_usd") and float(r["marca_usd"]) > 0 else None
obj["resumen"] = r
obj["manychat"] = {
    "disponible": tags is not None,
    "error": os.environ["MC_ERR"] or None,
    "mapa": tags or [],
    "nota": "solo el vocabulario del flujo (tags de la cuenta de operación de Instagram): el API no lista suscriptores ni da conteos por tag; los de IG no traen email/teléfono y por nombre matchea ~18% con falsos positivos — por eso este bloque no cuenta DMs ni setters. Llave pendiente: que el flujo escriba ig_username/subscriber id en el contacto de GHL.",
}
mc_estado = (f"ManyChat CONECTADO ({len(tags)} tags de la cuenta de operación)" if tags is not None else "ManyChat sin conexión (" + (os.environ["MC_ERR"] or "?") + ")")
obj["sin_instrumentar"] = [
    mc_estado + " — pero su API no lista suscriptores ni cuenta DMs/setters, y no hay llave con el CRM (los suscriptores de IG no traen email/teléfono): lo que se ve es el MAPA del flujo, no su volumen. Pedido: que el flujo escriba ig_username/subscriber_id en el contacto de GHL",
    "vistas/suscriptores de YouTube por módulo: la serie se ve solo desde el lead que llega al form",
    "seguidores nuevos por día (Meta/IG): los follow-me ads se leen por su gasto, no por el seguidor que trajeron",
]
print(json.dumps(obj, ensure_ascii=False))
PY

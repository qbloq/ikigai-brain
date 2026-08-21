#!/usr/bin/env bash
# angulos.sh — los ÁNGULOS GANADORES de la pauta de un proyecto, en un objeto:
# qué campaña trae leads/planes/caja (atribución UTM, misma regla de
# bash/metrics/embudo.sh), con qué COPY se compró cada clic (familias de cuerpo
# de anuncio, desde la caché de creativos_sync.sh) y a qué landing manda cada
# anuncio — con el H1 que esa landing muestra HOY, leído en vivo.
#
# Nació de la alineación DG 2026-08-19 (meeting b3f06835): «testear titulares
# en la página del VSL para subir play rate y retención», y el insumo que la
# misma reunión definió — «rastrear de qué campañas y anuncios vienen los
# calificados y las ventas para validar los ángulos ganadores». El titular
# nuevo le habla al ángulo que ya compró el clic; esta fuente pone los dos
# lados juntos (el ángulo del anuncio y el titular vigente de la página) para
# que el quiebre de message-match se VEA, y alimenta la UI `angulos` (rol
# Ejecutivo), cuyos titulares propuestos viven en params del spec.
#
# Reglas que sostiene:
#   - la caja es installments/payment_plans (pixel viaja como *_pixel);
#   - la atribución por campaña es la NATIVA de GHL (crm_contacts.attr_campaign_id,
#     último toque; Marketico la persiste desde 2026-08-21) con fallback al
#     utm_campaign del formulario — misma regla que embudo.sh; y la caja por
#     ANUNCIO es real: attr_ad_id → anuncios.sh (leads/planes/cash por ad), así
#     que la caja de una familia de copy es la SUMA de la de sus anuncios, no
#     un reparto proporcional (hasta el 21 era estimado y se declaraba);
#   - el H1 de la landing se lee en vivo (curl, 10 s, tolerante): si la página
#     no responde, `h1` viene null con el error declarado — nunca inventado.
#
# Uso: angulos.sh --project NAME [--from D] [--to D] [--min-spend X] [--sin-web] [--json]
#   default ventana = mes en curso (Bogotá); --min-spend default 50 (USD/COP
#   según cuenta); --sin-web no consulta las landings. Siempre emite JSON.
#   Read-only: Postgres (psql_ro) + sqlite ro + GET a las landings públicas.
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 1
source bash/lib/common.sh

project="" min_spend="50" sin_web=0
from="$(TZ="$TZ_DEFAULT" date +%Y-%m-01)"
_y="$(TZ="$TZ_DEFAULT" date +%Y)" _m="$(TZ="$TZ_DEFAULT" date +%m)"
case "${_m#0}" in 4|6|9|11) _d=30 ;; 2) _d=28; (( (_y % 4 == 0 && _y % 100 != 0) || _y % 400 == 0 )) && _d=29 ;; *) _d=31 ;; esac
to="${_y}-${_m}-${_d}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)   project="$2"; shift 2 ;;
    --from)      from="$2"; shift 2 ;;
    --to)        to="$2"; shift 2 ;;
    --min-spend) min_spend="$2"; shift 2 ;;
    --sin-web)   sin_web=1; shift ;;
    --json)      shift ;;
    -h|--help)   sed -n '2,31p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$project" ]] || { echo "Falta --project NAME" >&2; exit 2; }
for d in "$from" "$to"; do [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "Fecha inválida: $d" >&2; exit 2; }; done
[[ "$min_spend" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "--min-spend debe ser número" >&2; exit 2; }
pid="$(resolve_project "$project")"; [[ -n "$pid" ]] || { echo "No project matched: $project" >&2; exit 1; }

# ---------- 1/3: atribución por campaña (Postgres) — CTEs gemelas de embudo.sh ----------
read -r -d '' BODY <<'SQL' || true
WITH params AS (SELECT :'proj'::uuid AS pid, :'d1'::date AS d1, :'d2'::date AS d2),
lw AS (
  SELECT o.id, o.status, o.created_date::date AS creada, c.ghl_contact_id,
         coalesce(ca.name, caa.name, CASE WHEN c.attr_ad_id ~ '^[0-9]+$' THEN '— pauta sin campaña resuelta (ad fuera de las cuentas mapeadas)' END, utm.camp) AS camp,
         coalesce(ca.name, caa.name, CASE WHEN c.attr_ad_id ~ '^[0-9]+$' THEN '— pauta sin campaña resuelta (ad fuera de las cuentas mapeadas)' END) AS camp_ghl, utm.camp AS camp_form
  FROM crm_opportunities o
  JOIN params ON o.project_id = params.pid
             AND o.created_date::date BETWEEN params.d1 AND params.d2
  LEFT JOIN crm_contacts c ON c.id = o.contact_id
  LEFT JOIN campaigns ca ON ca.id = c.attr_campaign_id
  LEFT JOIN ads ad_ ON ad_.id = c.attr_ad_id AND c.attr_ad_id ~ '^[0-9]+$'
  LEFT JOIN campaigns caa ON caa.id = ad_.campaign_id
  LEFT JOIN LATERAL (
    SELECT max(CASE WHEN cf.name = 'utm_campaign' THEN nullif(x->>'value','') END) AS camp
    FROM jsonb_array_elements(coalesce(c.custom_fields,'[]'::jsonb)) x
    JOIN crm_custom_fields cf ON cf.ghl_field_id = x->>'id' AND cf.project_id = o.project_id
    WHERE cf.name = 'utm_campaign') utm ON true
),
lw_cash AS (
  SELECT l.id, l.camp, l.status, v.plan_id, v.original_amount, v.cash
  FROM lw l
  LEFT JOIN LATERAL (
    SELECT pp.plan_id, pp.original_amount,
           coalesce((SELECT sum(i.paid_amount) FROM installments i
                     WHERE i.plan_id = pp.plan_id AND i.payment_date IS NOT NULL),0) AS cash
    FROM payment_plans pp
    WHERE l.ghl_contact_id IS NOT NULL AND pp.customer_id = l.ghl_contact_id
      AND pp.plan_status <> 'Cancelled'
      AND pp.created_at::date BETWEEN l.creada AND l.creada + 60
    ORDER BY pp.created_at LIMIT 1) v ON true
),
sp AS (
  SELECT cmp.name, aa.currency AS cur, round(sum(d.spend),2) AS spend,
         sum(d.landing_page_views) AS lpv, sum(d.link_clicks) AS clics_link
  FROM ad_insights_daily d
  JOIN ad_accounts aa ON aa.id = d.ad_account_id
  JOIN campaigns cmp ON cmp.id = d.campaign_id
  JOIN project_ad_account_mappings map ON map.ad_account_id = d.ad_account_id
  JOIN params ON map.project_id = params.pid
  WHERE d.date_start BETWEEN params.d1 AND params.d2
  GROUP BY 1, 2
)
SELECT json_build_object(
  'campanas', (SELECT coalesce(json_agg(t ORDER BY t.cash DESC, t.planes DESC, t.leads DESC),'[]'::json) FROM (
     SELECT coalesce(l.camp, sp.name) AS campana,
            (l.camp IS NULL) AS sin_atribucion,
            count(l.id) AS leads,
            count(l.id) FILTER (WHERE l.status = 'won') AS ganadas,
            count(lc.plan_id) AS planes,
            round(coalesce(sum(lc.original_amount),0),2) AS valor_contrato,
            round(coalesce(sum(lc.cash),0),2) AS cash,
            max(sp.spend) AS spend, max(sp.cur) AS cur, max(sp.lpv) AS lpv, max(sp.clics_link) AS clics_link,
            round(max(sp.spend) / nullif(count(l.id),0), 2) AS cpl_real,
            round(max(sp.spend) / nullif(count(lc.plan_id),0), 2) AS cac_real,
            round(coalesce(sum(lc.cash),0) / nullif(max(sp.spend),0), 2) AS roas_real,
            count(l.id) FILTER (WHERE l.camp_ghl IS NOT NULL) AS leads_ghl,
            count(l.id) FILTER (WHERE l.camp_ghl IS NULL AND l.camp_form IS NOT NULL) AS leads_solo_form
     FROM lw l
     LEFT JOIN lw_cash lc ON lc.id = l.id
     FULL JOIN sp ON sp.name = l.camp
     GROUP BY coalesce(l.camp, sp.name), (l.camp IS NULL)) t),
  'totales', json_build_object(
     'leads', (SELECT count(*) FROM lw),
     'leads_atribuidos', (SELECT count(*) FROM lw WHERE camp IS NOT NULL),
     'leads_ghl', (SELECT count(*) FROM lw WHERE camp_ghl IS NOT NULL),
     'leads_solo_form', (SELECT count(*) FROM lw WHERE camp_ghl IS NULL AND camp_form IS NOT NULL),
     'ganadas', (SELECT count(*) FROM lw WHERE status = 'won'),
     'planes', (SELECT count(plan_id) FROM lw_cash),
     'cash', (SELECT round(coalesce(sum(cash),0),2) FROM lw_cash),
     'spend_usd', (SELECT round(coalesce(sum(spend),0),2) FROM sp WHERE cur = 'USD'),
     'spend_cop', (SELECT round(coalesce(sum(spend),0),2) FROM sp WHERE cur = 'COP'))
)
SQL
ATTR="$(psql_ro -t -A -v proj="$pid" -v d1="$from" -v d2="$to" <<<"$BODY")"

# ---------- 2/3: anuncios con copy + landing (Meta + caché local) ----------
ADS="$(bash/ads/anuncios.sh --project "$project" --from "$from" --to "$to" --tipo adquisicion --min-spend "$min_spend" --limit 0 --json 2>/dev/null || echo '[]')"

# ---------- 3/3: merge + H1 en vivo de cada landing ----------
ATTR="$ATTR" ADS="$ADS" PROJ="$project" D1="$from" D2="$to" MINSP="$min_spend" SINWEB="$sin_web" python3 - <<'PY'
import json, os, re, html, subprocess, collections, datetime, zoneinfo
attr = json.loads(os.environ["ATTR"]); ads = json.loads(os.environ["ADS"] or "[]")
camps = attr.get("campanas", []); tot = attr.get("totales", {})

def r2(x): return None if x is None else round(float(x), 2)

# --- anuncios por campaña
by_camp = collections.defaultdict(list)
for a in ads: by_camp[a.get("campana")].append(a)
for c in camps:
    if c.get("campana") is None: c["campana"] = "— sin atribución (orgánico · referral · directo)"
    if c["campana"] == "{{campaign.name}}": c["alerta"] = "macro de UTM sin resolver: un anuncio manda utm_campaign literal"
    c["anuncios"] = sorted(by_camp.get(c["campana"], []), key=lambda a: -float(a.get("spend") or 0))
    c["n_anuncios"] = len(c["anuncios"])
# campañas que tienen anuncios pero ni lead ni gasto agregado (no debería pasar) se ignoran

# --- familias de copy (el ángulo con que se compró el clic)
def norm(t):
    t = (t or "").lower()
    t = re.sub(r"[^\w\sáéíóúñü]", " ", t)          # emojis/puntuación fuera
    return re.sub(r"\s+", " ", t).strip()[:80]
fam = collections.OrderedDict()
for a in ads:
    key = norm(a.get("cuerpo")) or f"(sin copy) {a.get('anuncio')}"
    f = fam.setdefault(key, {"gancho": None, "cuerpo": a.get("cuerpo"), "titulos": collections.Counter(),
        "anuncios": [], "spend": 0.0, "lpv": 0, "clics_link": 0, "impr": 0, "compras_pixel": 0, "valor_pixel": 0.0,
        "hook_w": 0.0, "hold_w": 0.0, "w": 0.0, "campanas": collections.Counter(),
        "leads": 0, "won": 0, "planes": 0, "contrato": 0.0, "cash": 0.0, "landings": collections.Counter()})
    if f["gancho"] is None:
        first = next((ln.strip() for ln in (a.get("cuerpo") or "").splitlines() if ln.strip()), None)
        f["gancho"] = first or a.get("anuncio")
    sp = float(a.get("spend") or 0)
    f["anuncios"].append({"anuncio": a.get("anuncio"), "campana": a.get("campana"), "spend": a.get("spend"),
        "lpv": a.get("lpv"), "hook_pct": a.get("hook_pct"), "hold_pct": a.get("hold_pct"), "compras": a.get("compras"),
        "cpa": a.get("cpa"), "miniatura": a.get("miniatura"), "enlace": a.get("enlace"), "estado": a.get("estado"),
        "leads": a.get("leads"), "planes": a.get("planes"), "cash": a.get("cash"), "roas_real": a.get("roas_real")})
    f["spend"] += sp; f["lpv"] += int(a.get("lpv") or 0); f["clics_link"] += int(a.get("clics_link") or 0)
    f["impr"] += int(a.get("impr") or 0); f["compras_pixel"] += int(a.get("compras") or 0); f["valor_pixel"] += float(a.get("valor_pixel") or 0)
    if a.get("hook_pct") is not None: f["hook_w"] += float(a["hook_pct"]) * sp; f["w"] += sp
    if a.get("hold_pct") is not None: f["hold_w"] += float(a["hold_pct"]) * sp
    if a.get("titulo"): f["titulos"][a["titulo"]] += 1
    f["campanas"][a.get("campana")] += 1
    if a.get("enlace"): f["landings"][a["enlace"]] += 1
    # caja REAL del anuncio (anuncios.sh: leads del CRM con attr_ad_id → plan ≤60 d → cuotas)
    f["leads"] += int(a.get("leads") or 0); f["won"] += int(a.get("won") or 0); f["planes"] += int(a.get("planes") or 0)
    f["contrato"] += float(a.get("contrato") or 0); f["cash"] += float(a.get("cash") or 0)
angulos = []
for key, f in fam.items():
    angulos.append({
        "gancho": f["gancho"], "cuerpo": f["cuerpo"],
        "titulo_anuncio": (f["titulos"].most_common(1) or [(None, 0)])[0][0],
        "n_anuncios": len(f["anuncios"]), "spend": r2(f["spend"]), "impr": f["impr"], "clics_link": f["clics_link"], "lpv": f["lpv"],
        "hook_pct": r2(f["hook_w"] / f["w"]) if f["w"] else None, "hold_pct": r2(f["hold_w"] / f["w"]) if f["w"] else None,
        "compras_pixel": f["compras_pixel"], "valor_pixel": r2(f["valor_pixel"]),
        "cpa_pixel": r2(f["spend"] / f["compras_pixel"]) if f["compras_pixel"] else None,
        "leads": f["leads"], "won": f["won"], "planes": f["planes"], "contrato": r2(f["contrato"]), "cash": r2(f["cash"]),
        "cpl_real": r2(f["spend"] / f["leads"]) if f["leads"] else None,
        "cac_real": r2(f["spend"] / f["planes"]) if f["planes"] else None,
        "roas_real": r2(f["cash"] / f["spend"]) if f["spend"] else None,
        "campanas": [k for k, _ in f["campanas"].most_common()],
        "landings": [k for k, _ in f["landings"].most_common()],
        "anuncios": f["anuncios"],
    })
angulos.sort(key=lambda x: (-(x["cash"] or 0), -(x["planes"] or 0), -(x["leads"] or 0), -(x["spend"] or 0)))

# --- landings: a dónde manda la pauta, y qué titular muestra HOY
lands = collections.OrderedDict()
for a in ads:
    u = a.get("enlace")
    if not u: continue
    L = lands.setdefault(u, {"url": u, "n_anuncios": 0, "spend": 0.0, "lpv": 0, "compras_pixel": 0, "campanas": collections.Counter()})
    L["n_anuncios"] += 1; L["spend"] += float(a.get("spend") or 0); L["lpv"] += int(a.get("lpv") or 0)
    L["compras_pixel"] += int(a.get("compras") or 0); L["campanas"][a.get("campana")] += 1
def leer_h1(url):
    try:
        out = subprocess.run(["curl", "-sL", "--max-time", "10", "-A", "Mozilla/5.0 (cerebro angulos.sh)", url],
                             capture_output=True, text=True, errors="ignore", timeout=15)
        s = out.stdout
        if not s: return {"h1": None, "title": None, "error": "sin respuesta"}
        def clean(x): return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", "", x))).strip()
        h1 = [clean(m) for m in re.findall(r"<h1[^>]*>(.*?)</h1>", s, re.S | re.I)]
        h1 = [h for h in h1 if h]
        t = re.search(r"<title>(.*?)</title>", s, re.S | re.I)
        return {"h1": h1[0] if h1 else None, "h1_todos": h1[:5], "title": clean(t.group(1)) if t else None, "error": None}
    except Exception as e:
        return {"h1": None, "title": None, "error": str(e)[:120]}
landings = []
for u, L in lands.items():
    row = {"url": u, "n_anuncios": L["n_anuncios"], "spend": r2(L["spend"]), "lpv": L["lpv"], "compras_pixel": L["compras_pixel"],
           "campanas": [k for k, _ in L["campanas"].most_common()]}
    row.update(leer_h1(u) if os.environ["SINWEB"] != "1" else {"h1": None, "title": None, "error": "--sin-web"})
    landings.append(row)
landings.sort(key=lambda x: -(x["spend"] or 0))
sin_enlace = sum(1 for a in ads if not a.get("enlace"))

tz = zoneinfo.ZoneInfo("America/Bogota")
out = {
  "meta": {"proyecto": os.environ["PROJ"], "desde": os.environ["D1"], "hasta": os.environ["D2"], "min_spend": float(os.environ["MINSP"]),
           "generado": datetime.datetime.now(tz).strftime("%Y-%m-%d %H:%M"),
           "regla_atribucion": "campaña del lead = atribución nativa de GHL (crm_contacts.attr_campaign_id, último toque) con fallback al utm_campaign del formulario; anuncio = attr_ad_id (GHL). Lead = oportunidad del CRM en la ventana; plan ≤60 d; caja = cuotas pagadas",
           "regla_angulo": "leads/planes/caja de una familia de copy = SUMA de los de sus anuncios (caja real por anuncio desde 2026-08-21, ya no reparto proporcional); un lead cuyo ad no gastó en la ventana no cae en ninguna familia",
           "regla_h1": "el titular vigente se lee en vivo de la landing al generar (curl); si falla, viene null con error",
           "fuente_copy": "caché local data/sqlite/ads_creativos.db (creativos_sync.sh, Graph API)"},
  "totales": {**tot, "cpl_real": r2(float(tot.get("spend_usd") or 0) / tot["leads_atribuidos"]) if tot.get("leads_atribuidos") else None,
              "cac_real": r2(float(tot.get("spend_usd") or 0) / tot["planes"]) if tot.get("planes") else None,
              "roas_real": r2(float(tot.get("cash") or 0) / float(tot["spend_usd"])) if float(tot.get("spend_usd") or 0) else None,
              "anuncios": len(ads), "anuncios_con_copy": sum(1 for a in ads if a.get("cuerpo")), "anuncios_sin_enlace": sin_enlace,
              "leads_con_anuncio": (ads[0].get("cob_leads_con_ad") if ads else None),
              "leads_anuncio_en_ventana": (ads[0].get("cob_leads_ad_en_ventana") if ads else None)},
  "campanas": camps, "angulos": angulos, "landings": landings,
}
print(json.dumps(out, ensure_ascii=False, default=str))
PY

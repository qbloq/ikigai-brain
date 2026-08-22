#!/usr/bin/env bash
# followme.sh — los FOLLOW-ME ADS (la pauta de MARCA) de un proyecto medidos en
# lo que Meta sí reporta por anuncio: visitas al perfil de Instagram,
# conversaciones de DM iniciadas, likes/reacciones, reproducciones — por
# campaña y por día, con su costo unitario — más la serie de SEGUIDORES que
# construimos nosotros con fotos diarias (seguidores_snapshot.sh). Es la capa
# que le faltaba al embudo orgánico: el costo del «orgánico» antes del lead.
#
# Por qué así (medido 2026-08-21):
#   - Las campañas follow-me están optimizadas a PROFILE_VISIT con destino
#     INSTAGRAM_PROFILE (página «David Guerrero FX» → IG davidguerrero.pro) o a
#     CONVERSATIONS con destino INSTAGRAM_DIRECT. Meta reporta por anuncio
#     `link_click` (= visita al perfil cuando el destino es el perfil),
#     `onsite_conversion.messaging_conversation_started_7d`,
#     `onsite_conversion.post_net_like`, `video_view`… pero NO «follows».
#   - Los follows solo viven en IG Insights (`follower_count` diario), y el
#     token de identities no trae instagram_basic/instagram_manage_insights
#     (error #10). Pedido: docs/marketico-pedido-instagram-insights.md. Mientras,
#     seguidores_snapshot.sh guarda el total diario y aquí se resta.
#   - La lista de campañas «marca» es la MISMA de anuncios.sh --tipo marca
#     (objetivo de marca o LPV ≤2% de los clics): una sola regla en el repo.
#
# Uso: followme.sh --project NAME [--from D] [--to D] [--json]
#   default: mes en curso (Bogotá). Siempre emite JSON. Read-only: GET a Meta
#   (token de identities, por header, jamás argv) + sqlite ro de las fotos.
#   Cerca por rol (bash/lib/acceso.sh, dominio `meta`).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../lib/common.sh"
source "$here/../lib/sqlite.sh"
source "$here/../lib/acceso.sh"
require_acceso meta

project=""
from="$(TZ="$TZ_DEFAULT" date +%Y-%m-01)"
_y="$(TZ="$TZ_DEFAULT" date +%Y)" _m="$(TZ="$TZ_DEFAULT" date +%m)"
case "${_m#0}" in 4|6|9|11) _d=30 ;; 2) _d=28; (( (_y % 4 == 0 && _y % 100 != 0) || _y % 400 == 0 )) && _d=29 ;; *) _d=31 ;; esac
to="${_y}-${_m}-${_d}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) project="$2"; shift 2 ;;
    --from)    from="$2"; shift 2 ;;
    --to)      to="$2"; shift 2 ;;
    --json)    shift ;;
    -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$project" ]] || { echo "Falta --project NAME" >&2; exit 2; }
for d in "$from" "$to"; do [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "Fecha inválida: $d" >&2; exit 2; }; done
pid="$(resolve_project "$project")"; [[ -n "$pid" ]] || { echo "No project matched: $project" >&2; exit 1; }
hoy="$(TZ="$TZ_DEFAULT" date +%F)"; [[ "$to" > "$hoy" ]] && to_q="$hoy" || to_q="$to"

tok="$(psql_ro -t -A -c "SELECT access_token FROM identities
  WHERE provider LIKE 'facebook%' AND expiry_date > extract(epoch FROM now())
  ORDER BY expiry_date DESC LIMIT 1")"
[[ -n "$tok" ]] || { echo "Sin token de Meta vigente en identities (provider facebook*)." >&2; exit 1; }
accts="$(psql_ro -t -A -c "SELECT string_agg(a.id, ',') FROM ad_accounts a JOIN project_ad_account_mappings m ON m.ad_account_id = a.id WHERE m.project_id = '$pid'")"
[[ -n "$accts" ]] || { echo "El proyecto no tiene cuentas publicitarias mapeadas." >&2; exit 1; }
# la regla de «marca» es la de anuncios.sh: ids de campaña + nombre
MARCA="$("$here/anuncios.sh" --project "$project" --from "$from" --to "$to" --tipo marca --json 2>/dev/null || echo '[]')"
FOTOS="$(sqlite_ro "$(db_path ig_seguidores)" -json "SELECT fecha, ig_id, username, page, followers FROM fotos ORDER BY ig_id, fecha" 2>/dev/null || echo '[]')"

META_TOKEN="$tok" ACCTS="$accts" D1="$from" D2="$to_q" MARCA="$MARCA" FOTOS="$FOTOS" PROJ="$project" python3 - <<'PY'
import json, os, sys, urllib.request, urllib.parse, collections, datetime, zoneinfo
tok = os.environ["META_TOKEN"]; G = "https://graph.facebook.com/v21.0"
def get(url):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}"})
    with urllib.request.urlopen(req, timeout=60) as r: return json.load(r)
def paged(path, params):
    url = f"{G}/{path}?{urllib.parse.urlencode(params)}"; out = []
    while url:
        d = get(url); out += d.get("data", []); url = (d.get("paging") or {}).get("next")
    return out
marca = json.loads(os.environ["MARCA"] or "[]")
marca_ids = {str(a["campaign_id"]) for a in marca if a.get("campaign_id")}
marca_spend_db = collections.defaultdict(float)
for a in marca: marca_spend_db[str(a["campaign_id"])] += float(a.get("spend") or 0)
errores = []; camps = {}; serie = collections.defaultdict(lambda: collections.Counter()); destinos = collections.defaultdict(set); goals = collections.defaultdict(set)
for acct in os.environ["ACCTS"].split(","):
    act = acct if acct.startswith("act_") else "act_" + acct
    try:
        for s in paged(f"{act}/adsets", {"fields": "campaign_id,destination_type,optimization_goal", "limit": 500}):
            destinos[str(s["campaign_id"])].add(s.get("destination_type") or "UNDEFINED"); goals[str(s["campaign_id"])].add(s.get("optimization_goal") or "")
        rows = paged(f"{act}/insights", {"level": "campaign", "fields": "campaign_id,campaign_name,objective,spend,impressions,reach,actions",
                     "time_increment": 1, "time_range": json.dumps({"since": os.environ["D1"], "until": os.environ["D2"]}), "limit": 500})
        for r in rows:
            cid = str(r["campaign_id"])
            if cid not in marca_ids: continue
            a = {x["action_type"]: float(x["value"]) for x in r.get("actions", [])}
            perfil = "INSTAGRAM_PROFILE" in destinos.get(cid, set()) or "PROFILE_VISIT" in goals.get(cid, set())
            dm = "INSTAGRAM_DIRECT" in destinos.get(cid, set()) or "MESSENGER" in destinos.get(cid, set()) or "CONVERSATIONS" in goals.get(cid, set())
            m = {"spend": float(r.get("spend") or 0), "impresiones": int(r.get("impressions") or 0), "alcance": int(r.get("reach") or 0),
                 "visitas_perfil": a.get("link_click", 0.0) if perfil else 0.0,
                 "clics_link": a.get("link_click", 0.0),
                 "conversaciones_dm": a.get("onsite_conversion.messaging_conversation_started_7d", 0.0),
                 "likes": a.get("onsite_conversion.post_net_like", a.get("post_reaction", 0.0)),
                 "guardados": a.get("onsite_conversion.post_save", 0.0),
                 "video_views": a.get("video_view", 0.0)}
            c = camps.setdefault(cid, {"campaign_id": cid, "campana": r["campaign_name"], "objetivo": r.get("objective"),
                 "destino": "perfil" if perfil else ("dm" if dm else ("video" if "THRUPLAY" in goals.get(cid, set()) or "VIDEO_VIEWS" in (r.get("objective") or "") else "otro")),
                 "spend": 0.0, "impresiones": 0, "alcance": 0, "visitas_perfil": 0.0, "clics_link": 0.0, "conversaciones_dm": 0.0, "likes": 0.0, "guardados": 0.0, "video_views": 0.0, "dias": 0})
            for k, v in m.items(): c[k] += v
            c["dias"] += 1
            s = serie[r["date_start"]]
            for k in ("spend", "visitas_perfil", "conversaciones_dm", "likes", "video_views"): s[k] += m[k]
    except Exception as e:
        errores.append({"cuenta": act, "error": str(e)[:160]})
def r2(x): return None if x is None else round(float(x), 2)
def unit(spend, n): return r2(spend / n) if n else None
out_c = []
for c in camps.values():
    c["spend"] = r2(c["spend"]); c["spend_db"] = r2(marca_spend_db.get(c["campaign_id"]))
    c["costo_visita"] = unit(c["spend"], c["visitas_perfil"]); c["costo_conversacion"] = unit(c["spend"], c["conversaciones_dm"]); c["costo_like"] = unit(c["spend"], c["likes"])
    c["cpm"] = r2(1000 * c["spend"] / c["impresiones"]) if c["impresiones"] else None
    for k in ("visitas_perfil", "clics_link", "conversaciones_dm", "likes", "guardados", "video_views"): c[k] = int(c[k])
    out_c.append(c)
out_c.sort(key=lambda c: -(c["spend"] or 0))
tot = collections.Counter()
for c in out_c:
    for k in ("spend", "impresiones", "alcance", "visitas_perfil", "conversaciones_dm", "likes", "guardados", "video_views"): tot[k] += c[k] or 0
totales = {k: (r2(v) if k == "spend" else int(v)) for k, v in tot.items()}
totales.update({"campanas": len(out_c), "costo_visita": unit(tot["spend"], tot["visitas_perfil"]), "costo_conversacion": unit(tot["spend"], tot["conversaciones_dm"]), "costo_like": unit(tot["spend"], tot["likes"]),
                "spend_marca_db": r2(sum(marca_spend_db.values())), "campanas_marca_sin_insights": sorted(marca_ids - set(camps))})
serie_out = [{"dia": d, "spend": r2(v["spend"]), "visitas_perfil": int(v["visitas_perfil"]), "conversaciones_dm": int(v["conversaciones_dm"]), "likes": int(v["likes"]), "video_views": int(v["video_views"])} for d, v in sorted(serie.items())]
# --- seguidores: nuestras fotos diarias
fotos = json.loads(os.environ["FOTOS"] or "[]")
cuentas = collections.OrderedDict()
for f in fotos: cuentas.setdefault(f["ig_id"], {"ig_id": f["ig_id"], "username": f["username"], "page": f["page"], "fotos": []})["fotos"].append(f)
seg = []
for c in cuentas.values():
    fs = c["fotos"]; serie_s = []
    for i, f in enumerate(fs):
        prev = fs[i - 1] if i else None
        dias = (datetime.date.fromisoformat(f["fecha"]) - datetime.date.fromisoformat(prev["fecha"])).days if prev else None
        serie_s.append({"fecha": f["fecha"], "followers": f["followers"], "nuevos": (f["followers"] - prev["followers"]) if prev and f["followers"] is not None and prev["followers"] is not None else None, "dias": dias})
    en_ventana = [s for s in serie_s if os.environ["D1"] <= s["fecha"] <= os.environ["D2"] and s["nuevos"] is not None]
    seg.append({"ig_id": c["ig_id"], "username": c["username"], "page": c["page"], "followers_hoy": fs[-1]["followers"], "primera_foto": fs[0]["fecha"], "ultima_foto": fs[-1]["fecha"], "fotos": len(fs),
                "nuevos_en_ventana": sum(s["nuevos"] for s in en_ventana) if en_ventana else None, "serie": serie_s})
tz = zoneinfo.ZoneInfo("America/Bogota")
print(json.dumps({
  "meta": {"proyecto": os.environ["PROJ"], "desde": os.environ["D1"], "hasta": os.environ["D2"], "generado": datetime.datetime.now(tz).strftime("%Y-%m-%d %H:%M"),
           "regla_marca": "campañas = las de anuncios.sh --tipo marca (objetivo de marca o LPV ≤2% de los clics); métricas del Graph API a nivel campaña×día (actions)",
           "regla_visitas": "visita al perfil = link_click de campañas con destino INSTAGRAM_PROFILE / meta PROFILE_VISIT; conversación DM = onsite_conversion.messaging_conversation_started_7d; like = post_net_like",
           "regla_seguidores": "Meta no reporta follows por anuncio y el token no tiene instagram_manage_insights: los seguidores son FOTOS diarias del total (seguidores_snapshot.sh) restadas entre sí — el histórico empieza el día de la primera foto",
           "errores_meta": errores},
  "totales": totales, "campanas": out_c, "serie": serie_out,
  "seguidores": {"disponible": bool(seg), "cuentas": seg, "costo_por_seguidor": (r2(tot["spend"] / sum(c["nuevos_en_ventana"] for c in seg if c["nuevos_en_ventana"])) if any(c["nuevos_en_ventana"] for c in seg) else None),
                 "nota": "heurístico: los seguidores nuevos del día no son solo de la pauta (contenido, YouTube, referidos); la foto diaria resta hoy − ayer, y la pauta del mes se divide entre los nuevos del mismo mes"},
}, ensure_ascii=False))
PY

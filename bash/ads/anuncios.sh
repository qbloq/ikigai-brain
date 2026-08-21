#!/usr/bin/env bash
# anuncios.sh — UNA FILA POR ANUNCIO de un proyecto en la ventana: el creativo
# como unidad de análisis (lo que el equipo mira en la «plataforma de Bala»),
# con sus métricas de Meta a nivel de ad y, si la caché local la tiene, la
# MINIATURA del creativo. Hueco #2 del contraste con el dashboard comercial
# (2026-08-21): ad_stats.sh --by ad ya agregaba por anuncio pero sin tipo
# (marca vs adquisición), sin hook/hold y sin imagen.
#
# Columnas por anuncio: campaña, adset, objetivo, tipo, estado, spend, impr,
# alcance, clics al link, CTR link, CPC, CPM, LPV, tasa LPV, plays (vv) y
# cuartiles vv25/50/75/100, hook % (vv25/vv), hold % (vv75/vv25), fin %
# (vv100/vv), compras y valor del PIXEL, ROAS pixel, CPA, primer/último día
# con datos, miniatura (o null).
#
# Reglas:
#   - ROAS/compras son del PIXEL (lo que Meta atribuye), no caja: la caja por
#     anuncio no existe todavía porque el CRM no trae utm_content/ad id — hasta
#     entonces esta vista mide creativos, no dinero cobrado.
#   - `tipo`: marca = objetivo de campaña de awareness/engagement/likes/video,
#     O BIEN anuncios con clics al link que casi no llegan a la landing
#     (LPV ≤ 2% de los clics, con ≥50 clics): las campañas de seguidores con
#     objetivo TRAFFIC mandan al perfil de IG, no a la página — «no llevan
#     tráfico a la landing» medido, no adivinado por el nombre. El resto =
#     adquisición.
#   - hook/hold/fin: `video_views` de Meta aquí es PLAYS (autoplay, ≈95% de las
#     impresiones), no 3 segundos, así que no sirve como hook. Se usan los
#     cuartiles: hook = vistas al 25% / plays (¿engancha el primer cuarto?),
#     hold = vistas al 75% / vistas al 25% (de los enganchados, cuántos llegan
#     a tres cuartos), fin = vistas al 100% / plays. Null si no es video.
#   - Monedas por cuenta (`cur`); nunca se suman entre monedas.
#   - La miniatura sale de la caché local data/sqlite/ads_creativos.db, que
#     llena creativos_sync.sh (GET al Graph API con el token de identities).
#     Sin caché → null; el lector pinta un placeholder. Las URLs de Meta
#     expiran: la caché se refresca entera en cada sync.
#
# Uso: anuncios.sh --project NAME [--from D] [--to D] [--tipo adquisicion|marca|todos]
#                  [--campaign TOK] [--min-spend X] [--limit N] [--json]
#   default: mes en curso (Bogotá), tipo todos, min-spend 0, sin límite.
#   Read-only (Postgres + sqlite ro). Fuente viz `ad_anuncios` → page `anuncios`.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../lib/common.sh"
source "$here/../lib/sqlite.sh"

project="" tipo="todos" campaign="" min_spend="0" limit="0"
from="$(TZ="$TZ_DEFAULT" date +%Y-%m-01)"
_y="$(TZ="$TZ_DEFAULT" date +%Y)" _m="$(TZ="$TZ_DEFAULT" date +%m)"
case "${_m#0}" in 4|6|9|11) _d=30 ;; 2) _d=28; (( (_y % 4 == 0 && _y % 100 != 0) || _y % 400 == 0 )) && _d=29 ;; *) _d=31 ;; esac
to="${_y}-${_m}-${_d}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)   project="$2"; shift 2 ;;
    --from)      from="$2"; shift 2 ;;
    --to)        to="$2"; shift 2 ;;
    --tipo)      tipo="$2"; shift 2 ;;
    --campaign)  campaign="$2"; shift 2 ;;
    --min-spend) min_spend="$2"; shift 2 ;;
    --limit)     limit="$2"; shift 2 ;;
    --json)      FORMAT=json; shift ;;
    -h|--help)   sed -n '2,31p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$project" ]] || { echo "Falta --project NAME" >&2; exit 2; }
for d in "$from" "$to"; do [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "Fecha inválida: $d" >&2; exit 2; }; done
[[ "$tipo" =~ ^(adquisicion|marca|todos)$ ]] || { echo "--tipo inválido: $tipo (adquisicion|marca|todos)" >&2; exit 2; }
[[ "$min_spend" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "--min-spend debe ser número" >&2; exit 2; }
[[ "$limit" =~ ^[0-9]+$ ]] || { echo "--limit debe ser entero" >&2; exit 2; }
pid="$(resolve_project "$project")"
[[ -n "$pid" ]] || { echo "No project matched: $project" >&2; exit 1; }
[[ "$pid" =~ ^[0-9a-f-]{36}$ ]] || { echo "pid raro: $pid" >&2; exit 1; }

MARCA_OBJ="('OUTCOME_AWARENESS','OUTCOME_ENGAGEMENT','POST_ENGAGEMENT','PAGE_LIKES','VIDEO_VIEWS','REACH','BRAND_AWARENESS')"
where_tipo=""
case "$tipo" in
  marca)       where_tipo="WHERE tipo = 'marca'" ;;
  adquisicion) where_tipo="WHERE tipo = 'adquisicion'" ;;
esac
where_camp=""
if [[ -n "$campaign" ]]; then esc="${campaign//\'/\'\'}"; where_camp="AND (d.campaign_id LIKE '${esc}%' OR c.name ILIKE '%${esc}%')"; fi
lim=""; [[ "$limit" != 0 ]] && lim="LIMIT $limit"

SQL="WITH params AS (SELECT '$pid'::uuid AS pid, '$from'::date AS d1, '$to'::date AS d2),
agg AS (
SELECT d.ad_id,
       coalesce(ad.name, '—')                    AS anuncio,
       coalesce(c.name, '—')                     AS campana,
       d.campaign_id,
       coalesce(s.name, '—')                     AS adset,
       c.objective                               AS objetivo,
       CASE WHEN c.objective IN $MARCA_OBJ
                 OR (sum(d.link_clicks) >= 50 AND sum(d.landing_page_views) <= 0.02*sum(d.link_clicks))
            THEN 'marca' ELSE 'adquisicion' END AS tipo,
       ad.status                                 AS estado,
       a.currency                                AS cur,
       round(sum(d.spend),2)                     AS spend,
       sum(d.impressions)                        AS impr,
       sum(d.reach)                              AS alcance,
       sum(d.link_clicks)                        AS clics_link,
       round(100.0*sum(d.link_clicks)/nullif(sum(d.impressions),0), 2)  AS ctr_link,
       round(sum(d.spend)/nullif(sum(d.link_clicks),0), 2)              AS cpc,
       round(1000.0*sum(d.spend)/nullif(sum(d.impressions),0), 2)       AS cpm,
       sum(d.landing_page_views)                 AS lpv,
       round(100.0*sum(d.landing_page_views)/nullif(sum(d.link_clicks),0), 1) AS tasa_lpv,
       sum(d.video_views)                        AS vv,
       sum(d.video_views_25_percent)             AS vv25,
       sum(d.video_views_50_percent)             AS vv50,
       sum(d.video_views_75_percent)             AS vv75,
       sum(d.video_views_100_percent)            AS vv100,
       round(100.0*sum(d.video_views_25_percent)/nullif(sum(d.video_views),0), 1)  AS hook_pct,
       round(100.0*sum(d.video_views_75_percent)/nullif(sum(d.video_views_25_percent),0), 1) AS hold_pct,
       round(100.0*sum(d.video_views_100_percent)/nullif(sum(d.video_views),0), 1) AS fin_pct,
       sum(d.purchases)                          AS compras,
       round(sum(d.purchase_value),2)            AS valor_pixel,
       round(sum(d.purchase_value)/nullif(sum(d.spend),0), 2)  AS roas_pixel,
       round(sum(d.spend)/nullif(sum(d.purchases),0), 2)       AS cpa,
       to_char(min(d.date_start),'YYYY-MM-DD')   AS primer_dia,
       to_char(max(d.date_start),'YYYY-MM-DD')   AS ultimo_dia
FROM ad_insights_daily d
JOIN project_ad_account_mappings map ON map.ad_account_id = d.ad_account_id
JOIN params ON map.project_id = params.pid
JOIN ad_accounts a   ON a.id = d.ad_account_id
LEFT JOIN ads ad     ON ad.id = d.ad_id
LEFT JOIN ad_sets s  ON s.id = d.ad_set_id
LEFT JOIN campaigns c ON c.id = d.campaign_id
WHERE d.date_start BETWEEN params.d1 AND params.d2 $where_camp
GROUP BY d.ad_id, ad.name, c.name, d.campaign_id, s.name, c.objective, ad.status, a.currency
HAVING sum(d.spend) >= $min_spend
)
SELECT * FROM agg $where_tipo ORDER BY spend DESC $lim"

rows="$(psql_ro -t -A -c "SELECT coalesce(json_agg(row_to_json(_q)), '[]'::json) FROM ($SQL) _q;")"
cache="$(db_path ads_creativos)"

ROWS="$rows" CACHE="$cache" FORMAT="$FORMAT" python3 - <<'PY'
import json, os, sqlite3
rows = json.loads(os.environ["ROWS"])
cache = os.environ["CACHE"]
thumbs = {}
if os.path.exists(cache):
    try:
        con = sqlite3.connect(f"file:{cache}?mode=ro", uri=True)
        have = {r[1] for r in con.execute("PRAGMA table_info(creativos)")}
        extra = ", titulo, cuerpo, enlace" if "enlace" in have else ", NULL, NULL, NULL"   # cachés previas al copy
        for ad_id, cid, th, img, ot, ft, ti, cu, en in con.execute(f"SELECT ad_id, creative_id, thumbnail_url, image_url, object_type, fetched_at{extra} FROM creativos"):
            thumbs[str(ad_id)] = {"creative_id": cid, "miniatura": th or img, "tipo_creativo": ot, "miniatura_at": ft, "titulo": ti, "cuerpo": cu, "enlace": en}
        con.close()
    except sqlite3.Error:
        pass
for r in rows:
    t = thumbs.get(str(r.get("ad_id"))) or {}
    r["creative_id"] = t.get("creative_id"); r["miniatura"] = t.get("miniatura")
    r["tipo_creativo"] = t.get("tipo_creativo"); r["miniatura_at"] = t.get("miniatura_at")
    r["titulo"] = t.get("titulo"); r["cuerpo"] = t.get("cuerpo"); r["enlace"] = t.get("enlace")   # copy + landing (solo --json; la tabla no los imprime)
if os.environ["FORMAT"] == "json":
    print(json.dumps(rows, ensure_ascii=False)); raise SystemExit
cols = ["anuncio","campana","tipo","estado","cur","spend","impr","clics_link","ctr_link","cpm","lpv","hook_pct","hold_pct","compras","valor_pixel","roas_pixel","cpa","miniatura"]
def f(v):
    if v is None: return "—"
    return str(v)[:44]
w = {c: max(len(c), *(len(f(r.get(c))) for r in rows)) if rows else len(c) for c in cols}
print("  ".join(c.ljust(w[c]) for c in cols)); print("  ".join("-"*w[c] for c in cols))
for r in rows: print("  ".join(f(r.get(c)).ljust(w[c]) for c in cols))
print(f"({len(rows)} anuncios · miniaturas en caché: {sum(1 for r in rows if r.get('miniatura'))})")
PY

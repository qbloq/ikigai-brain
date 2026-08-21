#!/usr/bin/env bash
# creativos_sync.sh — llena/refresca la CACHÉ LOCAL de miniaturas de anuncios
# (data/sqlite/ads_creativos.db) desde el Graph API de Meta.  [WRITE local]
#
# Por qué existe: `ads.ad_creative_id` está vacío en toda la tabla (el ingestor
# no lo trae) y la imagen del creativo no vive en la DB. Se resuelve ad →
# creative → thumbnail_url con una lectura al Graph API, en lotes de 50 ids
# (`/?ids=a,b,c&fields=creative{thumbnail_url,…}`), y se guarda aquí para que
# anuncios.sh (read-only) la pueda unir. Desde 2026-08-21 trae también el COPY
# del creativo (`titulo`/`cuerpo`: title/body u object_story_spec) — el ángulo
# con que se compró el clic, insumo de bash/ads/angulos.sh (UI de titulares). Las URLs de Meta expiran, así que
# cada corrida refresca TODOS los anuncios de la ventana (110 ads = 3 GETs).
#
# Credencial: el user token de `identities` (provider 'facebook' o
# 'facebook:<quien>'), el de vencimiento más lejano que siga vigente — va a
# curl por header desde stdin, jamás argv ni impreso. Cerca por rol
# (bash/lib/acceso.sh, dominio `meta`): cerebro y roles con `fuentes:"*"`.
# Solo GET contra Meta; la única escritura es la sqlite local.
#
# Uso: creativos_sync.sh --project NAME [--from D] [--to D] [--min-spend X]
#                        [--dry-run] [--json]
#   default ventana = mes en curso. --dry-run consulta Meta pero no escribe.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../lib/common.sh"
source "$here/../lib/sqlite.sh"
source "$here/../lib/acceso.sh"
require_acceso meta

project="" min_spend="0" dry=0
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
    --dry-run)   dry=1; shift ;;
    --json)      FORMAT=json; shift ;;
    -h|--help)   sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$project" ]] || { echo "Falta --project NAME" >&2; exit 2; }
for d in "$from" "$to"; do [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "Fecha inválida: $d" >&2; exit 2; }; done
[[ "$min_spend" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "--min-spend debe ser número" >&2; exit 2; }
pid="$(resolve_project "$project")"; [[ -n "$pid" ]] || { echo "No project matched: $project" >&2; exit 1; }
[[ "$pid" =~ ^[0-9a-f-]{36}$ ]] || { echo "pid raro: $pid" >&2; exit 1; }

# ── 1. token vigente (nunca a stdout/argv)
tok="$(psql_ro -t -A -c "SELECT access_token FROM identities
  WHERE provider LIKE 'facebook%' AND access_token IS NOT NULL
    AND expiry_date > extract(epoch FROM now())
  ORDER BY expiry_date DESC LIMIT 1")"
[[ -n "$tok" ]] || { echo "Sin token de Meta vigente en identities (provider facebook*) — renovar la identidad." >&2; exit 1; }

# ── 2. anuncios con gasto en la ventana
mapfile -t ids < <(psql_ro -t -A -c "SELECT d.ad_id FROM ad_insights_daily d
  JOIN project_ad_account_mappings map ON map.ad_account_id = d.ad_account_id
  WHERE map.project_id = '$pid' AND d.date_start BETWEEN '$from' AND '$to'
  GROUP BY d.ad_id HAVING sum(d.spend) >= $min_spend ORDER BY sum(d.spend) DESC")
(( ${#ids[@]} )) || { echo "Sin anuncios con gasto en $from..$to para $project" >&2; exit 0; }

# ── 3. Graph API en lotes de 50
GRAPH="${META_GRAPH_BASE:-https://graph.facebook.com/v21.0}"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
: > "$tmp"
ok=0 fail=0
for ((i=0; i<${#ids[@]}; i+=50)); do
  batch=("${ids[@]:i:50}")
  idlist="$(IFS=,; echo "${batch[*]}")"
  # title/body/object_story_spec = el COPY del anuncio (el ángulo con que se
  # compró el clic) — desde 2026-08-21 se cachea también, para la UI de ángulos.
  code="$(curl -g -sS --max-time 40 "$GRAPH/?ids=$idlist&fields=id,name,creative{id,thumbnail_url,image_url,object_type,title,body,object_story_spec}" \
    -H @<(printf 'Authorization: Bearer %s\n' "$tok") -o "$tmp.b" -w '%{http_code}' || echo 000)"
  if [[ "$code" == 200 ]]; then ok=$((ok+1)); cat "$tmp.b" >> "$tmp"; echo >> "$tmp"
  else fail=$((fail+1)); echo "lote $((i/50+1)): HTTP $code $(head -c 200 "$tmp.b")" >&2; fi
done
rm -f "$tmp.b"

# ── 4. upsert en sqlite (una txn) + log
db="$(db_path ads_creativos)"
mkdir -p "$(dirname "$db")"
RES="$(TMP="$tmp" DB="$db" DRY="$dry" PROJ="$project" FROM="$from" TO="$to" N="${#ids[@]}" OK="$ok" FAIL="$fail" python3 - <<'PY'
import json, os, sqlite3, datetime
rows = []
for line in open(os.environ["TMP"], encoding="utf-8"):
    line = line.strip()
    if not line: continue
    try: d = json.loads(line)
    except Exception: continue
    for ad_id, o in d.items():
        if not isinstance(o, dict): continue
        c = o.get("creative") or {}
        # El copy: title/body del creativo; si vienen vacíos (video/carrusel),
        # el object_story_spec trae message/title/name del post.
        oss = c.get("object_story_spec") or {}
        inner = oss.get("video_data") or oss.get("link_data") or oss.get("photo_data") or {}
        titulo = c.get("title") or inner.get("title") or inner.get("name") or None
        cuerpo = c.get("body") or inner.get("message") or None
        cta = (inner.get("call_to_action") or {}).get("value") or {}
        enlace = inner.get("link") or cta.get("link") or None   # la landing a la que manda el anuncio
        rows.append((str(ad_id), c.get("id"), c.get("thumbnail_url"), c.get("image_url"), c.get("object_type"), o.get("name"), titulo, cuerpo, enlace))
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
dry = os.environ["DRY"] == "1"
con = sqlite3.connect(os.environ["DB"])
con.executescript("""
CREATE TABLE IF NOT EXISTS creativos (ad_id TEXT PRIMARY KEY, creative_id TEXT, thumbnail_url TEXT, image_url TEXT,
  object_type TEXT, nombre TEXT, fetched_at TEXT, titulo TEXT, cuerpo TEXT, enlace TEXT);
CREATE TABLE IF NOT EXISTS corridas (id INTEGER PRIMARY KEY, corrida_at TEXT, proyecto TEXT, desde TEXT, hasta TEXT,
  anuncios INTEGER, con_miniatura INTEGER, lotes_ok INTEGER, lotes_fail INTEGER, dry INTEGER);
""")
# Migración suave de cachés anteriores al copy (2026-08-21): columnas nuevas.
have = {r[1] for r in con.execute("PRAGMA table_info(creativos)")}
for col in ("titulo", "cuerpo", "enlace"):
    if col not in have: con.execute(f"ALTER TABLE creativos ADD COLUMN {col} TEXT")
con.execute("BEGIN")
if not dry:
    con.executemany("""INSERT INTO creativos(ad_id, creative_id, thumbnail_url, image_url, object_type, nombre, titulo, cuerpo, enlace, fetched_at)
      VALUES (?,?,?,?,?,?,?,?,?,?) ON CONFLICT(ad_id) DO UPDATE SET creative_id=excluded.creative_id,
      thumbnail_url=excluded.thumbnail_url, image_url=excluded.image_url, object_type=excluded.object_type,
      nombre=excluded.nombre, titulo=excluded.titulo, cuerpo=excluded.cuerpo, enlace=excluded.enlace, fetched_at=excluded.fetched_at""", [r + (now,) for r in rows])
con.execute("INSERT INTO corridas(corrida_at, proyecto, desde, hasta, anuncios, con_miniatura, lotes_ok, lotes_fail, dry) VALUES (?,?,?,?,?,?,?,?,?)",
  (now, os.environ["PROJ"], os.environ["FROM"], os.environ["TO"], int(os.environ["N"]), sum(1 for r in rows if r[2] or r[3]), int(os.environ["OK"]), int(os.environ["FAIL"]), 1 if dry else 0))
con.commit(); con.close()
print(json.dumps({"proyecto": os.environ["PROJ"], "desde": os.environ["FROM"], "hasta": os.environ["TO"], "anuncios": int(os.environ["N"]),
  "resueltos": len(rows), "con_miniatura": sum(1 for r in rows if r[2] or r[3]), "con_copy": sum(1 for r in rows if r[7]), "lotes_ok": int(os.environ["OK"]), "lotes_fail": int(os.environ["FAIL"]),
  "dry_run": dry, "db": os.environ["DB"]}, ensure_ascii=False))
PY
)"
if [[ "$FORMAT" == json ]]; then echo "$RES"; else
  echo "$RES" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("\n".join(f"{k:14} {v}" for k,v in d.items()))'
fi

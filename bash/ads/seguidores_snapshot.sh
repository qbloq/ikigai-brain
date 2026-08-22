#!/usr/bin/env bash
# seguidores_snapshot.sh — [WRITE local] la FOTO DIARIA de seguidores de las
# cuentas de Instagram de un proyecto → sqlite data/sqlite/ig_seguidores.db.
#
# Existe porque el token de Meta de `identities` (el login de Marketico) no
# trae `instagram_basic`/`instagram_manage_insights`, así que IG Insights
# (`follower_count` por día, `follows_and_unfollows`) responde «(#10)
# Application does not have permission» — pero `pages_show_list` sí deja leer
# el TOTAL de seguidores de cada cuenta IG business hoy
# (`me/accounts?fields=instagram_business_account{followers_count}`). Una foto
# por día, restada contra la anterior, es la serie de seguidores nuevos que
# IG no nos deja pedir hacia atrás: el histórico empieza el día que esto
# empieza a correr (pedido de scopes: docs/marketico-pedido-instagram-insights.md).
#
# Tabla `fotos(fecha, ig_id, username, page_id, page, followers, media_count,
# tomada_at)` con PK (fecha, ig_id): correr dos veces el mismo día = upsert
# (queda la última). `corridas` deja el log. La caché es LOCAL a cada máquina
# (como ads_creativos.db): en el publicador corre el cron pm2 `seguidores-cron`.
#
# Uso: seguidores_snapshot.sh [--project N] [--dry-run] [--json]
#   --project N  solo las cuentas IG de las páginas mapeadas a ese proyecto
#                (por nombre de página/IG; default: todas las del token).
#   Cerca por rol (bash/lib/acceso.sh, dominio `meta`). Solo GET a Meta; la
#   única escritura es la sqlite local.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../lib/common.sh"
source "$here/../lib/sqlite.sh"
source "$here/../lib/acceso.sh"
require_acceso meta

project="" DRY=0 FORMAT="${FORMAT:-table}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) project="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --json)    FORMAT=json; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

tok="$(psql_ro -t -A -c "SELECT access_token FROM identities
  WHERE provider LIKE 'facebook%' AND expiry_date > extract(epoch FROM now())
  ORDER BY expiry_date DESC LIMIT 1")"
[[ -n "$tok" ]] || { echo "Sin token de Meta vigente en identities (provider facebook*) — renovar la identidad." >&2; exit 1; }

db="$(db_path ig_seguidores)"
mkdir -p "$(dirname "$db")"
sqlite_rw "$db" <<'SQL'
CREATE TABLE IF NOT EXISTS fotos (
  fecha TEXT NOT NULL, ig_id TEXT NOT NULL, username TEXT, page_id TEXT, page TEXT,
  followers INTEGER, media_count INTEGER, tomada_at TEXT NOT NULL,
  PRIMARY KEY (fecha, ig_id));
CREATE TABLE IF NOT EXISTS corridas (at TEXT NOT NULL, cuentas INTEGER, ok INTEGER, error TEXT);
SQL

META_TOKEN="$tok" PROJECT="$project" DRY="$DRY" DB="$db" FORMAT="$FORMAT" python3 - <<'PY'
import json, os, sqlite3, sys, urllib.request, urllib.parse, datetime, zoneinfo
tok = os.environ["META_TOKEN"]; proj = (os.environ["PROJECT"] or "").lower(); dry = os.environ["DRY"] == "1"
G = "https://graph.facebook.com/v21.0"
def get(path):
    req = urllib.request.Request(f"{G}/{path}", headers={"Authorization": f"Bearer {tok}"})
    with urllib.request.urlopen(req, timeout=30) as r: return json.load(r)
tz = zoneinfo.ZoneInfo("America/Bogota"); now = datetime.datetime.now(tz)
fecha = now.strftime("%Y-%m-%d"); tomada = now.strftime("%Y-%m-%d %H:%M")
try:
    d = get("me/accounts?fields=id,name,instagram_business_account{id,username,followers_count,media_count}&limit=100")
except Exception as e:
    con = sqlite3.connect(os.environ["DB"]); con.execute("INSERT INTO corridas VALUES (?,?,?,?)", (tomada, 0, 0, str(e)[:200])); con.commit()
    print(f"Meta no respondió: {e}", file=sys.stderr); sys.exit(1)
rows = []
for p in d.get("data", []):
    ig = p.get("instagram_business_account")
    if not ig: continue
    if proj and proj.split()[0] not in p["name"].lower() and proj.split()[0] not in (ig.get("username") or "").lower(): continue
    rows.append((fecha, str(ig["id"]), ig.get("username"), str(p["id"]), p["name"], ig.get("followers_count"), ig.get("media_count"), tomada))
if not dry:
    con = sqlite3.connect(os.environ["DB"])
    con.executemany("INSERT INTO fotos VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(fecha, ig_id) DO UPDATE SET username=excluded.username, page=excluded.page, followers=excluded.followers, media_count=excluded.media_count, tomada_at=excluded.tomada_at", rows)
    con.execute("INSERT INTO corridas VALUES (?,?,?,?)", (tomada, len(rows), 1, None)); con.commit()
    # la serie: seguidores nuevos = foto de hoy − foto anterior de la misma cuenta
    prev = {r[0]: r[1] for r in con.execute("SELECT ig_id, followers FROM fotos f WHERE fecha = (SELECT max(fecha) FROM fotos f2 WHERE f2.ig_id = f.ig_id AND f2.fecha < ?)", (fecha,))}
else:
    prev = {}
out = [{"fecha": r[0], "ig_id": r[1], "username": r[2], "page": r[4], "followers": r[5], "media_count": r[6],
        "nuevos_vs_foto_anterior": (r[5] - prev[r[1]]) if (r[5] is not None and r[1] in prev and prev[r[1]] is not None) else None} for r in rows]
if os.environ["FORMAT"] == "json":
    print(json.dumps({"fecha": fecha, "dry_run": dry, "db": os.environ["DB"], "cuentas": out}, ensure_ascii=False)); sys.exit()
print(f"{'[dry-run] ' if dry else ''}foto {fecha} · {len(out)} cuenta(s) IG → {os.environ['DB']}")
for r in out: print(f"  {r['username']:<24} {r['followers']:>9,} seguidores  (página: {r['page']})" + (f"  Δ vs foto anterior: {r['nuevos_vs_foto_anterior']:+,}" if r['nuevos_vs_foto_anterior'] is not None else "  (primera foto)"))
PY

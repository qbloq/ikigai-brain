#!/usr/bin/env bash
# Lo último que entró (o cambió) en el Drive de la org, ordenado por fecha.
#
# Usage:
#   drive_recent.sh [--days N] [--from D] [--to D] [--modified] [--docs]
#                   [--type T] [--folder FRAG] [--owner FRAG] [--exclude FRAG]
#                   [--with-folders] [--by day|type|owner|folder] [--limit N] [--json]
#
#   --days N       ventana hacia atrás desde hoy (default 14)
#   --from/--to    ventana explícita (YYYY-MM-DD, --to inclusivo); anulan --days
#   --modified     usar modified_time en vez de created_time (qué se TOCÓ,
#                  no qué nació) — filtra y ordena por esa columna
#   --docs         solo documentos (Docs/Sheets/Slides/Forms/PDF/Office/CSV):
#                  quita el material bruto, que es el 80% del Drive
#   --type T       doc|sheet|slide|form|pdf|folder|video|image|audio, o
#                  cualquier etiqueta amigable (ver drive_ls.sh / index/stats)
#   --folder FRAG  la ruta contiene FRAG (p.ej. "Andrea Torres")
#   --owner FRAG   el owner contiene FRAG
#   --exclude FRAG la ruta NO contiene FRAG (p.ej. "Meet Recordings")
#   --with-folders incluir carpetas (por defecto solo archivos)
#   --by …         agregado en vez de filas: por día, tipo, owner o carpeta raíz
#   --limit N      filas mostradas (default 50; 0 = sin tope)
#
# La ventana y el orden los resuelve el backend (createdAfter/modifiedAfter +
# sort); los filtros de ruta/owner/familia y los agregados se aplican local
# sobre la ventana traída.
#
# El índice es un CACHÉ que se refresca a mano (`node src/scripts/indexDrive.js`
# en el backend), así que la frescura se imprime SIEMPRE, a stderr: sin ella un
# índice viejo se lee como "no hubo actividad". Con más de 48h, avisa fuerte.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/common.sh"

urlenc() { python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1"; }

days=14 from="" to="" modified=0 docs=0 type="" folder="" owner="" exclude=""
with_folders=0 by="" limit=50
while [[ $# -gt 0 ]]; do
  case "$1" in
    --days)         days="$2"; shift 2 ;;
    --from)         from="$2"; shift 2 ;;
    --to)           to="$2"; shift 2 ;;
    --modified)     modified=1; shift ;;
    --docs)         docs=1; shift ;;
    --type)         type="$2"; shift 2 ;;
    --folder)       folder="$2"; shift 2 ;;
    --owner)        owner="$2"; shift 2 ;;
    --exclude)      exclude="$2"; shift 2 ;;
    --with-folders) with_folders=1; shift ;;
    --by)           by="$2"; shift 2 ;;
    --limit)        limit="$2"; shift 2 ;;
    --json)         FORMAT=json; shift ;;
    -h|--help)      sed -n '2,31p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1 (see -h)" >&2; exit 1 ;;
  esac
done

case "$by" in ''|day|dia|día|type|tipo|owner|folder|carpeta) ;;
  *) echo "drive_recent: --by desconocido: '$by' (day|type|owner|folder)" >&2; exit 1 ;;
esac

field="created"; [[ "$modified" == 1 ]] && field="modified"

# --- Ventana, en la zona de la org (el backend compara timestamptz) ---------
read -r after before < <(python3 - "$days" "$from" "$to" "${BRAIN_TZ:-America/Bogota}" <<'PY'
import sys
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

days, frm, to, tzname = sys.argv[1:5]
tz = ZoneInfo(tzname)
midnight = datetime.now(tz).replace(hour=0, minute=0, second=0, microsecond=0)
at = lambda d: datetime.fromisoformat(d).replace(tzinfo=tz)

if frm or to:
    a = at(frm) if frm else midnight - timedelta(days=3650)
    # --to es inclusivo para quien lo escribe; el filtro es < el día siguiente.
    b = at(to) + timedelta(days=1) if to else midnight + timedelta(days=1)
else:
    a = midnight - timedelta(days=int(days))
    b = midnight + timedelta(days=1)
print(a.isoformat(), b.isoformat())
PY
)

# --- El backend debe entender el contrato nuevo ------------------------------
# Express IGNORA los query params que no conoce: contra un backend sin desplegar
# el filtro por fecha se evaporaría y /drive/index respondería la RAÍZ como si
# fuera el drive entero. Antes que devolver un subconjunto disfrazado de
# respuesta, se para aquí. /drive/index/status llegó en el mismo cambio, así que
# su presencia es la señal de que los params de fecha existen.
if ! status_json="$(mapi GET "/drive/index/status" 2>/dev/null)"; then
  cat >&2 <<'MSG'
drive_recent: el backend todavía no expone GET /drive/index/status.
Este script necesita el filtro por fecha + sort de /drive/index; sin ellos el
backend contestaría solo la raíz del Drive (~1k de 17k items) SIN avisar, que
es peor que no contestar.
Despliega en google-meet-express: src/routes/drive.js + src/services/agenticoService.js
(contrato: apis/mkt/drive.openapi.json).
MSG
  exit 4
fi

python3 - "$status_json" >&2 <<'PY'
import json, sys
s = json.loads(sys.argv[1])
age = s.get("age_hours")
synced = (s.get("synced_at") or "?")[:16].replace("T", " ")
print(f'índice: {s.get("items", "?")} items · último sync {synced} '
      f'(hace {age if age is not None else "?"}h)')
if age is not None and age > 48:
    print(f'⚠  el índice lleva {age}h sin refrescarse — lo más nuevo del Drive NO está aquí.')
    print('   refréscalo en el backend: node src/scripts/indexDrive.js --no-json')
PY

# --- Traer la ventana completa (paginando) ----------------------------------
# Los filtros de ruta/owner/--docs se aplican local, así que hay que traer la
# ventana entera antes de recortar. Tope duro para que una ventana enorme no se
# vuelva cientos de requests; si se alcanza, se dice (un tope callado se lee
# como "eso es todo").
PAGE=1000; MAX_PAGES=10
tmpf="$(mktemp)"; trap 'rm -f "$tmpf"' EXIT
: > "$tmpf"

# Solo las etiquetas exactas se filtran en el servidor; los atajos por familia
# (video/image/audio) no son etiquetas y se resuelven local, sobre mime_type.
label=""
case "${type,,}" in
  doc|docs)     label="Google Doc" ;;
  sheet|sheets) label="Google Sheet" ;;
  slide|slides) label="Google Slides" ;;
  form|forms)   label="Google Form" ;;
  pdf)          label="PDF" ;;
  folder)       label="Folder" ;;
  ''|video|image|imagen|audio) label="" ;;
  *)            label="$type" ;;
esac

folder_flag="&isFolder=false"
{ [[ "$with_folders" == 1 ]] || [[ "${type,,}" == "folder" ]]; } && folder_flag=""

q="${field}After=$(urlenc "$after")&${field}Before=$(urlenc "$before")"
q="$q&sort=${field}_time:desc&limit=$PAGE${folder_flag}${label:+&type=$(urlenc "$label")}"

offset=0; pages=0; truncated=0
while (( pages < MAX_PAGES )); do
  n="$(mapi GET "/drive/index?$q&offset=$offset" | python3 -c '
import json, sys
d = json.load(sys.stdin)
out = open(sys.argv[1], "a")
for it in d.get("items", []):
    out.write(json.dumps(it, ensure_ascii=False) + "\n")
print(len(d.get("items", [])))
' "$tmpf")"
  pages=$((pages + 1))
  (( n < PAGE )) && break
  offset=$((offset + PAGE))
  (( pages == MAX_PAGES )) && truncated=1
done
(( truncated )) && echo "⚠  ventana recortada a $((MAX_PAGES * PAGE)) items — acótala con --from/--to o --type." >&2

# --- Filtrar, agregar y renderizar ------------------------------------------
python3 - "$FORMAT" "$tmpf" "$by" "$limit" "$docs" "${type,,}" "$folder" "$owner" \
         "$exclude" "$with_folders" "${field}_time" "${BRAIN_TZ:-America/Bogota}" <<'PY'
import json, sys
from collections import Counter, defaultdict
from datetime import datetime
from zoneinfo import ZoneInfo

(fmt, path, by, limit, docs, type_, folder, owner, exclude, with_folders,
 stamp, tzname) = sys.argv[1:13]
limit, docs, with_folders = int(limit), docs == "1", with_folders == "1"
tz = ZoneInfo(tzname)

rows = [json.loads(l) for l in open(path) if l.strip()]

# Un "documento" es algo que se lee, no material bruto: nativos de Google
# (menos carpetas y shortcuts), PDF, Office y CSV. text/plain queda fuera a
# propósito — en este Drive son transcripciones automáticas de Meet.
def is_doc(m):
    return ((m.startswith("application/vnd.google-apps.")
             and m not in ("application/vnd.google-apps.folder",
                           "application/vnd.google-apps.shortcut"))
            or m in ("application/pdf", "application/msword", "text/csv")
            or m.startswith("application/vnd.openxmlformats-officedocument."))

FAMILY = {"video": "video/", "image": "image/", "imagen": "image/", "audio": "audio/"}

def keep(it):
    mime, p = it.get("mime_type") or "", it.get("path") or ""
    if docs and not is_doc(mime):
        return False
    if type_ in FAMILY and not mime.startswith(FAMILY[type_]):
        return False
    if folder and folder.lower() not in p.lower():
        return False
    if owner and owner.lower() not in (it.get("owner") or "").lower():
        return False
    if exclude and exclude.lower() in p.lower():
        return False
    return True

rows = [r for r in rows if keep(r)]

def local(it):
    """El instante del item en la zona de la org (el backend devuelve UTC)."""
    raw = it.get(stamp)
    if not raw:
        return None
    return datetime.fromisoformat(raw.replace("Z", "+00:00")).astimezone(tz)

def root_folder(it):
    """La carpeta de primer nivel que contiene al item.

    path = "/[external]/1. David Guerrero/…/archivo" → "1. David Guerrero".
    Con solo dos segmentos el archivo cuelga de la raíz y no hay carpeta que
    nombrar: devolver parts[1] ahí imprimiría el nombre del propio archivo.
    """
    parts = [s for s in (it.get("path") or "").split("/") if s]
    return parts[1] if len(parts) > 2 else "(raíz)"

# --- Agregados -------------------------------------------------------------
if by in ("day", "dia", "día"):
    agg = defaultdict(lambda: [0, 0])  # día -> [archivos, carpetas]
    for it in rows:
        d = local(it)
        if d:
            agg[d.date().isoformat()][1 if it.get("is_folder") else 0] += 1
    if with_folders:
        out = [{"dia": k, "archivos": v[0], "carpetas": v[1]}
               for k, v in sorted(agg.items(), reverse=True)]
    else:
        # Sin carpetas en alcance, una columna "carpetas" clavada en 0 miente.
        out = [{"dia": k, "items": v[0]} for k, v in sorted(agg.items(), reverse=True)]
elif by in ("type", "tipo"):
    c = Counter(it.get("type") or "?" for it in rows)
    size = defaultdict(int)
    for it in rows:
        size[it.get("type") or "?"] += it.get("size") or 0
    def pretty(n):
        for unit in ("B", "KB", "MB", "GB", "TB"):
            if n < 1024:
                return f"{n:.0f} {unit}"
            n /= 1024
        return f"{n:.0f} PB"
    out = [{"type": t, "items": n, "peso": pretty(size[t])} for t, n in c.most_common()]
elif by == "owner":
    c = Counter(it.get("owner") or "—" for it in rows)
    last = {}
    for it in rows:
        d, o = local(it), it.get("owner") or "—"
        if d and (o not in last or d > last[o]):
            last[o] = d
    out = [{"owner": o, "items": n,
            "ultimo": last[o].date().isoformat() if o in last else ""}
           for o, n in c.most_common()]
elif by in ("folder", "carpeta"):
    c = Counter(root_folder(it) for it in rows)
    last = {}
    for it in rows:
        d, f = local(it), root_folder(it)
        if d and (f not in last or d > last[f]):
            last[f] = d
    out = [{"carpeta": f, "items": n,
            "ultimo": last[f].date().isoformat() if f in last else ""}
           for f, n in c.most_common()]
else:
    out = [{
        "cuando": local(it).strftime("%m-%d %H:%M") if local(it) else "",
        "type": it.get("type") or "?",
        "nombre": it.get("name") or "",
        "carpeta": root_folder(it),
        "owner": it.get("owner") or "—",
        "link": it.get("web_view_link") or "",
    } for it in rows]

if limit:
    out = out[:limit]

# --- Salida ----------------------------------------------------------------
if fmt == "json":
    print(json.dumps(out, indent=2, ensure_ascii=False))
    sys.exit()
if not out:
    print("(sin resultados en la ventana)")
    sys.exit()

# El link va en --json, no en la tabla: es lo único que no cabe en pantalla.
cols = [c for c in out[0] if c != "link"]
disp = [{c: (str(r[c])[:50] + "…" if len(str(r[c])) > 51 else str(r[c])) for c in cols}
        for r in out]
w = {c: max(len(c), *(len(d[c]) for d in disp)) for c in cols}
print("  ".join(c.ljust(w[c]) for c in cols))
print("  ".join("-" * w[c] for c in cols))
for d in disp:
    print("  ".join(d[c].ljust(w[c]) for c in cols))
print(f"({len(out)} filas)")
PY

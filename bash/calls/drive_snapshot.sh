#!/usr/bin/env bash
# WRITE (local): snapshot de la carpeta «Closer Calls» del Drive cruzada contra
# los call meetings de Postgres, persistido en la sqlite local `closer_calls`.
#
# Cada corrida RECONSTRUYE la tabla `archivos` completa (es un snapshot, no un
# log): un archivo del Drive por fila, con tamaño y fecha de creación, y el
# meeting resuelto con su status, su contacto (CRM) y el resultado de la
# llamada (`call_meeting_results.results->>'result'`) + el callStatus del
# reporte vigente. La tabla `corridas` guarda el historial de recálculos.
#
# El cruce es una cascada, cada archivo registra su `match_method`:
#   1. drive_file_id   meetings.drive_file_id = file_id (exacto)
#   2. meet_code       nombre tipo `xxx-xxxx-xxx` → spaces.meeting_code
#   3. nombre          nombre del archivo = meetings.name (normalizado); si hay
#      /nombre+fecha   varios, gana el más cercano en el tiempo
#   4. prefijo(+fecha) «Van Camargo (fecha GMT-5)» → prefijo de meetings.name
#   5. sin_match       queda con NULLs — la cola de higiene
#
# ⚠️ Fechas: el created_time del Drive es UTC real; scheduled_start_time guarda
# hora BOGOTÁ etiquetada como UTC (ver CLAUDE.md) — la comparación se hace en
# reloj de pared Bogotá, y así se guardan (`creado_bogota`, `agenda_bogota`).
#
# Lee el ÍNDICE del Drive (no el listado live, que topa en 100 y no trae
# fechas). Si el índice está viejo, correr antes: bash/google/drive_sync.sh --wait
#
# Uso: drive_snapshot.sh [--folder NOMBRE|ID] [--db NAME] [--dry-run] [--json]
#   --folder   carpeta del Drive (default: Closer Calls)
#   --db       db local destino (default: closer_calls)
#   --dry-run  calcula y reporta, pero hace ROLLBACK
#   --json     resumen como objeto JSON
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../lib/common.sh"          # psql_ro (.env, Postgres RO)
source "$here/../google/lib/common.sh"   # mapi, resolve_folder (backend mkt)
source "$here/../lib/sqlite.sh"          # db_path, sqlite_ro

FOLDER="Closer Calls"
DB="closer_calls"
dry=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --folder) FOLDER="$2"; shift 2 ;;
    --db)     DB="$2"; shift 2 ;;
    --dry-run) dry="--dry-run"; shift ;;
    --json)   FORMAT=json; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

tmpd="$(mktemp -d)"; trap 'rm -rf "$tmpd"' EXIT

# ── 1. Drive: hijos directos de la carpeta, desde el índice (trae fechas y size)
fid="$(resolve_folder "$FOLDER")"
mapi GET "/drive/index/status" > "$tmpd/status.json" 2>/dev/null || echo '{}' > "$tmpd/status.json"
mapi GET "/drive/index?parentId=$fid&limit=1000&sort=created_time:asc" > "$tmpd/drive.json"

# frescura del índice a stderr (mismo criterio que drive_recent.sh)
python3 - "$tmpd/status.json" >&2 <<'PY' || true
import json,sys,datetime as dt
try:
    s=json.load(open(sys.argv[1])); ts=s.get('last_synced_at') or s.get('lastSyncedAt') or (s.get('last_run') or {}).get('finished_at')
    if ts:
        t=dt.datetime.fromisoformat(ts.replace('Z','+00:00'))
        h=(dt.datetime.now(dt.timezone.utc)-t).total_seconds()/3600
        print(f"índice: sync {t:%Y-%m-%d %H:%M} UTC (hace {h:.0f}h)")
        if h>48: print("⚠  índice >48h — refréscalo: bash/google/drive_sync.sh --wait")
except Exception: pass
PY

# ── 2. Postgres: todos los call meetings con sus llaves de cruce y el contexto
psql_ro -t -A -c "
SELECT coalesce(json_agg(t), '[]'::json) FROM (
  SELECT m.id, m.name, m.status, m.drive_file_id,
         s.meeting_code,
         to_char(m.scheduled_start_time AT TIME ZONE 'UTC','YYYY-MM-DD HH24:MI') AS agenda_bogota,
         m.event->'booking'->>'contact_id' AS contact_id,
         c.nombre AS contact_nombre, c.email AS contact_email,
         res.results->>'result' AS resultado,
         v.report->'generalInformation'->>'callStatus' AS call_status_reporte,
         v.fuente AS reporte_fuente
  FROM meetings m
  LEFT JOIN spaces s ON s.id = m.space_id
  LEFT JOIN LATERAL (
    SELECT trim(coalesce(cc.first_name,'')||' '||coalesce(cc.last_name,'')) AS nombre, cc.email
    FROM crm_contacts cc
    WHERE cc.ghl_contact_id = m.event->'booking'->>'contact_id'
    ORDER BY (cc.project_id = m.project_id) DESC NULLS LAST, cc.created_at DESC
    LIMIT 1
  ) c ON true
  LEFT JOIN call_meeting_results res ON res.meeting_id = m.id
  LEFT JOIN call_report_vigente v ON v.meeting_id = m.id
  WHERE m.meeting_type = 'call'
) t;" > "$tmpd/meetings.json"

# ── 3. Cruce + SQL del snapshot
GENERADO_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)" FOLDER_ID="$fid" FOLDER_NAME="$FOLDER" \
python3 - "$tmpd/drive.json" "$tmpd/meetings.json" "$tmpd/snapshot.sql" "$tmpd/resumen.json" <<'PY'
import json, os, re, sys, datetime as dt
from collections import defaultdict

drive = json.load(open(sys.argv[1]))
files = [f for f in (drive.get('items', drive) or []) if not f.get('is_folder')]
meets = json.load(open(sys.argv[2]))

def norm(s): return re.sub(r'\s+', ' ', (s or '')).strip().lower()

by_fid  = {m['drive_file_id']: m for m in meets if m.get('drive_file_id')}
by_code = defaultdict(list)
by_name = defaultdict(list)
for m in meets:
    if m.get('meeting_code'): by_code[m['meeting_code']].append(m)
    by_name[norm(m['name'])].append(m)

CODE_RE = re.compile(r'^([a-z]{3}-[a-z]{4}-[a-z]{3})')
DATE_RE = re.compile(r'\((\d{4}-\d{2}-\d{2} \d{2}:\d{2})(?::\d{2})? GMT-5\)\s*$')

def agenda_dt(m):
    try: return dt.datetime.strptime(m['agenda_bogota'], '%Y-%m-%d %H:%M')
    except Exception: return None

def nearest(cands, ref):
    if len(cands) == 1: return cands[0], False
    if ref is None: return cands[0], True
    scored = sorted(cands, key=lambda m: abs((agenda_dt(m) - ref).total_seconds()) if agenda_dt(m) else 1e18)
    return scored[0], True

def q(v):
    if v is None or v == '': return 'NULL'
    return "'" + str(v).replace("'", "''") + "'"

rows, metodos, sin_match = [], defaultdict(int), []
for f in files:
    name = f['name']
    created = dt.datetime.fromisoformat(f['created_time'])
    creado_bogota = (created.astimezone(dt.timezone.utc) - dt.timedelta(hours=5)).strftime('%Y-%m-%d %H:%M')
    ref = dt.datetime.strptime(creado_bogota, '%Y-%m-%d %H:%M')
    base = name
    dm = DATE_RE.search(name)
    if dm:
        ref = dt.datetime.strptime(dm.group(1), '%Y-%m-%d %H:%M')
        base = name[:dm.start()].strip()

    m, method = None, 'sin_match'
    cm = CODE_RE.match(name)
    if f['file_id'] in by_fid:
        m, method = by_fid[f['file_id']], 'drive_file_id'
    elif cm and by_code.get(cm.group(1)):
        m, amb = nearest(by_code[cm.group(1)], ref); method = 'meet_code'
    elif by_name.get(norm(base)):
        m, amb = nearest(by_name[norm(base)], ref)
        method = 'nombre+fecha' if amb else 'nombre'
    elif len(norm(base)) >= 5:
        pref = [x for k, v in by_name.items() if k.startswith(norm(base)) for x in v]
        if pref:
            m, amb = nearest(pref, ref)
            method = 'prefijo+fecha' if amb else 'prefijo'
    if m is None: sin_match.append(name)
    metodos[method] += 1

    size = f.get('size')
    rows.append((
        q(f['file_id']), q(name), size if size is not None else 'NULL',
        (round(size/1048576, 1) if size else 'NULL'),
        q(f['created_time']), q(creado_bogota), q(f.get('web_view_link')),
        q(m and m['id']), q(method), q(m and m['name']), q(m and m['status']),
        q(m and m['agenda_bogota']), q(m and m['contact_id']),
        q(m and m['contact_nombre']), q(m and m['contact_email']),
        q(m and m['resultado']), q(m and m['call_status_reporte']),
        q(m and m['reporte_fuente']),
    ))

gen = os.environ['GENERADO_AT']
sql = ["""
CREATE TABLE IF NOT EXISTS archivos (
  file_id             TEXT PRIMARY KEY,
  nombre              TEXT NOT NULL,
  size_bytes          INTEGER,
  size_mb             REAL,
  creado_utc          TEXT,
  creado_bogota       TEXT,
  link                TEXT,
  meeting_id          TEXT,
  match_method        TEXT,
  meeting_name        TEXT,
  meeting_status      TEXT,
  agenda_bogota       TEXT,
  contact_id          TEXT,
  contact_nombre      TEXT,
  contact_email       TEXT,
  resultado           TEXT,
  call_status_reporte TEXT,
  reporte_fuente      TEXT,
  snapshot_at         TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS corridas (
  corrida     INTEGER PRIMARY KEY AUTOINCREMENT,
  generado_at TEXT NOT NULL,
  carpeta     TEXT,
  folder_id   TEXT,
  total       INTEGER,
  con_meeting INTEGER,
  sin_match   INTEGER,
  por_metodo  TEXT
);
DELETE FROM archivos;"""]
for r in rows:
    sql.append("INSERT INTO archivos VALUES (%s,%s);" % (','.join(str(x) for x in r), q(gen)))
con = len(files) - len(sin_match)
sql.append("INSERT INTO corridas (generado_at,carpeta,folder_id,total,con_meeting,sin_match,por_metodo) VALUES (%s,%s,%s,%d,%d,%d,%s);"
           % (q(gen), q(os.environ['FOLDER_NAME']), q(os.environ['FOLDER_ID']),
              len(files), con, len(sin_match), q(json.dumps(metodos, ensure_ascii=False))))
open(sys.argv[3], 'w').write('\n'.join(sql) + '\n')
json.dump({'generado_at': gen, 'carpeta': os.environ['FOLDER_NAME'], 'total': len(files),
           'con_meeting': con, 'sin_match': sin_match, 'por_metodo': dict(metodos)},
          open(sys.argv[4], 'w'), ensure_ascii=False)
PY

# ── 4. Persistir (una transacción; --dry-run reporta y rollbackea)
"$here/../localdb/db_exec.sh" "$DB" - --create $dry < "$tmpd/snapshot.sql" >&2

# ── 5. Resumen
if [[ "$FORMAT" == json ]]; then
  cat "$tmpd/resumen.json"; echo
else
  python3 - "$tmpd/resumen.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
print(f"snapshot «{r['carpeta']}» — {r['total']} archivos · {r['con_meeting']} con meeting · {len(r['sin_match'])} sin match")
for k, v in sorted(r['por_metodo'].items(), key=lambda x: -x[1]):
    print(f"  {k:<15} {v}")
if r['sin_match']:
    print("sin match:")
    for n in r['sin_match']: print(f"  · {n}")
PY
fi
[[ -n "$dry" ]] && echo "(dry-run: nada quedó escrito)" >&2 || true

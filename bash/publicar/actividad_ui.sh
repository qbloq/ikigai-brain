#!/usr/bin/env bash
# actividad_ui.sh <slug> [--desde YYYY-MM-DD] [--user FRAG] [--limit N] [--json]
# La bitácora de actividad de una UI publicada, leída del registro del
# publicador (tabla visitas): quién entró, qué página pidió y qué escrituras
# hizo por el relay /mkt (desde 2026-08-20 la ruta trae «MÉTODO path → status»,
# así que un `POST …/confirm → 200` ES un reporte confirmado). Read-only.
#
# La hora del registro es UTC (datetime('now') de sqlite); acá se muestra
# también en America/Bogota. Default: últimas 48h, máx 200 filas.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

SLUG="" DESDE="" UFRAG="" LIMIT=200 FORMAT=text
while [[ $# -gt 0 ]]; do
  case "$1" in
    --desde) DESDE="$2"; shift 2 ;;
    --user)  UFRAG="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --json)  FORMAT=json; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    -*) echo "Argumento desconocido: $1" >&2; exit 2 ;;
    *) SLUG="$1"; shift ;;
  esac
done
[[ -n "$SLUG" ]] || { echo "Falta el slug (p. ej. resolver-ventas)" >&2; exit 2; }
[[ "$SLUG" =~ ^[a-z0-9-]+$ ]] || { echo "Slug inválido" >&2; exit 2; }
[[ "$LIMIT" =~ ^[0-9]+$ ]] || { echo "--limit debe ser entero" >&2; exit 2; }
[[ -z "$DESDE" || "$DESDE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "--desde debe ser YYYY-MM-DD" >&2; exit 2; }

COND="slug=$(sql_lit "$SLUG")"
if [[ -n "$DESDE" ]]; then COND+=" AND ts >= $(sql_lit "$DESDE")"; else COND+=" AND ts >= datetime('now','-48 hours')"; fi
[[ -n "$UFRAG" ]] && COND+=" AND lower(coalesce(email,'')) LIKE $(sql_lit "%${UFRAG,,}%")"

ROWS="$(printf 'SELECT ts, email, ruta FROM visitas WHERE %s ORDER BY ts DESC LIMIT %s;' "$COND" "$LIMIT" | remote_sql -json | tr -d '\n')"
[[ -z "$ROWS" ]] && ROWS='[]'

printf '%s' "$ROWS" | python3 -c "
import json, sys, datetime, zoneinfo
rows = json.loads(sys.stdin.read() or '[]')
bog = zoneinfo.ZoneInfo('America/Bogota')
def clasifica(ruta):
    r = ruta or ''
    if ' → ' in r:
        pre, status = r.rsplit(' → ', 1)
        ok = status.strip().startswith('2')
        if '/confirm' in pre:        return ('reporte_confirm', ok)
        if 'payment-plans' in pre and pre.startswith('POST'): return ('plan_directo', ok)
        if '/receipt' in pre:        return ('comprobante', ok)
        if 'installments' in pre and pre.startswith('PUT'):   return ('cuota_actualizada', ok)
        if '/products' in pre:       return ('catalogo', ok)
        return ('relay', ok)
    return ('pagina', True)
out = []
for r in rows:
    tipo, ok = clasifica(r.get('ruta'))
    ts = r.get('ts') or ''
    try:
        local = datetime.datetime.fromisoformat(ts).replace(tzinfo=datetime.timezone.utc).astimezone(bog).strftime('%Y-%m-%d %H:%M')
    except Exception:
        local = ts
    out.append({'ts_bogota': local, 'email': r.get('email'), 'tipo': tipo, 'ok': ok, 'ruta': r.get('ruta')})
if '$FORMAT' == 'json':
    print(json.dumps(out, ensure_ascii=False))
else:
    if not out: print('Sin actividad en la ventana.')
    for r in out:
        marca = '' if r['ok'] else '  ⚠ FALLÓ'
        print(f\"{r['ts_bogota']}  {(r['email'] or '?'):32.32}  {r['tipo']:17} {r['ruta'][:80]}{marca}\")
"

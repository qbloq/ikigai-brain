#!/usr/bin/env bash
# entrantes.sh — los agendamientos de GHL que recibió el Cerebro (tabla
# `entrantes` de intercepciones.db) una vez Marketico pasó a modo forward.
# Read-only, local-first: reusa la lib de bash/intercepciones/ (misma db,
# mismo remoto root@api:/apps/hermetico) para que la resolución local/ssh sea
# IDÉNTICA a la de log.sh — SQL siempre por stdin, nunca en el argv remoto.
# Dominio nuevo bash/agenda/ (flujo de agendamiento GHL→Cerebro→Meet).
#
# uso: entrantes.sh [--desde YYYY-MM-DD] [--solo-errores] [--limit N] [--json]
set -euo pipefail
source "$(dirname "$0")/../intercepciones/lib.sh"

DESDE=""; SOLO_ERR=0; LIMIT=30; FORMAT=table
while [[ $# -gt 0 ]]; do
  case "$1" in
    --desde) DESDE="$2"; shift 2 ;;
    --solo-errores) SOLO_ERR=1; shift ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "flag desconocido: $1" >&2; exit 1 ;;
  esac
done

W="1=1"
[[ -n "$DESDE" ]] && W="$W AND recibido_at >= $(sql_lit "$DESDE")"
(( SOLO_ERR )) && W="$W AND accion = 'error'"

# Sanitizar --limit: solo dígitos, default a 30 si vacío, pero preservar 0 (sin cap)
LIMIT_CLEAN="${LIMIT//[^0-9]/}"
if [[ "$LIMIT" == "0" ]]; then
  LIM=""
elif [[ -z "$LIMIT_CLEAN" ]]; then
  LIM="LIMIT 30"
else
  LIM="LIMIT $LIMIT_CLEAN"
fi

SQL="SELECT id, recibido_at, appointment_id, calendar_id, rol, estado_cita,
       contacto, email, start_time, accion, resultado, error, duracion_ms
     FROM entrantes WHERE $W ORDER BY id DESC $LIM;"

if [[ "$FORMAT" == "json" ]]; then
  OUT="$(echo "$SQL" | int_sql -json)"
  printf '%s' "${OUT:-[]}"
else
  OUT="$(echo "$SQL" | int_sql -json)"
  printf '%s' "${OUT:-[]}" | python3 -c '
import json, sys
rows = json.load(sys.stdin)
if not rows:
    print("sin entrantes")
    raise SystemExit
for r in rows:
    print("%4s %s %-15s %-8s %-20s %s" % (
        r["id"], r["recibido_at"][:19], r["accion"],
        r.get("rol") or "-", (r.get("contacto") or "")[:20],
        (r.get("error") or r.get("resultado") or "")[:60],
    ))
'
fi

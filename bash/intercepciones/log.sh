#!/usr/bin/env bash
# Log del webhook interceptado — qué reportó Marketico de cada /crm.
# Read-only; local si la db está en este checkout, ssh si no (lib.sh).
# uso: log.sh [--desde YYYY-MM-DD] [--solo-errores] [--limit N] [--json]
set -euo pipefail
source "$(dirname "$0")/lib.sh"

DESDE=""; SOLO_ERR=0; LIMIT=50; FORMAT=table
while [[ $# -gt 0 ]]; do
  case "$1" in
    --desde) DESDE="$2"; shift 2 ;;
    --solo-errores) SOLO_ERR=1; shift ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "flag desconocido: $1" >&2; exit 1 ;;
  esac
done

W="1=1"
[[ -n "$DESDE" ]] && W="$W AND recibido_at >= $(sql_lit "$DESDE")"
(( SOLO_ERR )) && W="$W AND ok = 0"
LIM=""; [[ "$LIMIT" != "0" ]] && LIM="LIMIT ${LIMIT//[^0-9]/}"

SQL="SELECT id, recibido_at, appointment_id, estado_cita, contacto, email,
       start_time, ok, resultado, error, duracion_ms
     FROM crm_webhook WHERE $W ORDER BY recibido_at DESC $LIM;"

if [[ "$FORMAT" == "json" ]]; then echo "$SQL" | int_sql -json
else echo -e ".mode column\n.headers on\n$SQL" | int_sql; fi

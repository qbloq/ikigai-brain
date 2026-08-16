#!/usr/bin/env bash
# Drift de agenda vigente — las discrepancias DB↔GHL de la ÚLTIMA corrida de
# cada calendario (las corridas viejas son historia, no cola). Read-only.
# uso: drift.sh [--historia] [--json]
set -euo pipefail
source "$(dirname "$0")/lib.sh"

HISTORIA=0; FORMAT=table
while [[ $# -gt 0 ]]; do
  case "$1" in
    --historia) HISTORIA=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "flag desconocido: $1" >&2; exit 1 ;;
  esac
done

if (( HISTORIA )); then
  SQL="SELECT id, corrida_at, proyecto, ghl_total, db_total, coinciden,
         discrepancias, estado, detalle
       FROM corridas ORDER BY corrida_at DESC LIMIT 200;"
else
  SQL="WITH ultimas AS (
         SELECT max(id) AS id FROM corridas WHERE estado='ok' GROUP BY ghl_calendar_id)
       SELECT d.corrida_id, c.corrida_at, c.proyecto, d.tipo,
              d.appointment_id, d.meeting_id, d.detalle
       FROM drift d JOIN corridas c ON c.id = d.corrida_id
       WHERE d.corrida_id IN (SELECT id FROM ultimas)
       ORDER BY c.proyecto, d.tipo;"
fi

if [[ "$FORMAT" == "json" ]]; then echo "$SQL" | int_sql -json
else echo -e ".mode column\n.headers on\n$SQL" | int_sql; fi

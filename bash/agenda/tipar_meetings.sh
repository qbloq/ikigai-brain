#!/usr/bin/env bash
# tipar_meetings.sh — [WRITE pg] sella meetings.ghl_calendar_id leyendo de GHL
# el calendario de cada appointment (GET /calendars/events/appointments/{id}).
# Backfill de la migración 008 para reuniones ya existentes; hacia adelante lo
# sella bash/agenda/entrante.sh al crear. Solo toca filas con la columna NULL
# y appointment conocido; por defecto las de los últimos 14 días + futuras.
# uso: tipar_meetings.sh [--desde YYYY-MM-DD] [--dry-run] [--json]
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck disable=SC1091
source bash/ghl/lib/common.sh   # trae también common.sh (psql)

DESDE="$(date -d '14 days ago' +%F 2>/dev/null || date -v-14d +%F)"; DRY=0; JSON=0
while [[ $# -gt 0 ]]; do case "$1" in
  --desde) DESDE="$2"; shift 2 ;; --dry-run) DRY=1; shift ;; --json) JSON=1; shift ;;
  -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -8; exit 0 ;;
  *) echo "flag desconocido: $1" >&2; exit 2 ;; esac; done

read -r PID _ < <(ghl_resolve_project "David Guerrero"); ghl_load_creds "$PID"

FILAS="$(psql_ro -t -A -F$'\t' -c "
  SELECT left(id::text,36), event->'booking'->>'appointment_id'
  FROM meetings
  WHERE meeting_type='call' AND ghl_calendar_id IS NULL
    AND event->'booking'->>'appointment_id' IS NOT NULL
    AND scheduled_start_time >= '$DESDE'::timestamptz")"
N=0; OK=0; SINCAL=0
while IFS=$'\t' read -r MID APPT; do
  [[ -z "$MID" ]] && continue; N=$((N+1))
  CAL=""
  for intento in 1 2 3; do
    CAL="$(ghl_api "/calendars/events/appointments/$APPT" 2>/dev/null \
      | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["appointment"].get("calendarId") or "")
except Exception: print("")')" && [[ -n "$CAL" ]] && break
  done
  if [[ -z "$CAL" ]] || [[ ! "$CAL" =~ ^[A-Za-z0-9_-]+$ ]]; then
    SINCAL=$((SINCAL+1)); echo "  $MID $APPT: sin calendario en GHL (borrado o error)" >&2; continue
  fi
  if (( DRY )); then echo "  [dry-run] $MID ← $CAL"; else
    CAL_ESC="${CAL//\'/\'\'}"
    # UPDATE con psql "$DATABASE_URL" directo (no psql_ro): este es un
    # backfill [WRITE pg] declarado, el helper de solo-lectura no aplica —
    # la convención de la casa para los scripts WRITE del repo.
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -c "UPDATE ikigaigm.meetings SET ghl_calendar_id='$CAL_ESC' WHERE id='$MID' AND ghl_calendar_id IS NULL"
  fi; OK=$((OK+1))
done <<< "$FILAS"
echo "{\"revisadas\": $N, \"selladas\": $OK, \"sin_calendario\": $SINCAL, \"dry_run\": $DRY}"

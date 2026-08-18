#!/usr/bin/env bash
# Appointments (calendar events) de UN calendario GHL en una ventana — la
# sonda del lado FUENTE para la reconciliación de agenda del interceptor
# (bash/intercepciones/reconciliar_agenda.sh). Read-only, como todo bash/ghl/.
#
# Contrato GHL verificado en vivo (2026-08-16, calendario David Guerrero
# bFFbTpMillO1n35FuDmv): GET /calendars/events exige Version: 2021-04-15 y
# startTime/endTime en epoch MILLIS; responde {"events":[{id,
# appointmentStatus, title, startTime ISO+offset (p.ej. "-05:00"), endTime,
# contactId, calendarId, ...}]} — confirma exactamente lo asumido en el brief.
# Nota aparte: GHL también manda un campo duplicado mal escrito
# "appoinmentStatus" (sin la 'i') con el mismo valor — se ignora, se lee
# "appointmentStatus".
#
# uso: appointments.sh (--project FRAG | --project-id UUID) [--calendar ID]
#                      [--desde N] [--hasta N] [--limit N] [--json]
#   --calendar  default: el ghl_calendar_id activo del proyecto en crm_calendars
#   --desde/--hasta  días relativos a hoy (default: -1 y 30)
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
export GHL_API_VERSION=2021-04-15   # los endpoints de calendars viven en esta versión

FORMAT=table; PROJECT=""; PROJECT_ID=""; CALENDAR=""; DESDE=-1; HASTA=30; LIMIT=0
usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --project-id) PROJECT_ID="$2"; shift 2 ;;
    --calendar) CALENDAR="$2"; shift 2 ;;
    --desde) DESDE="$2"; shift 2 ;;
    --hasta) HASTA="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) usage ;;
    *) echo "flag desconocido: $1" >&2; usage 1 ;;
  esac
done

if [[ -z "$PROJECT_ID" ]]; then
  [[ -z "$PROJECT" ]] && { echo "falta --project o --project-id" >&2; usage 1; }
  read -r PROJECT_ID _ < <(ghl_resolve_project "$PROJECT")
fi
ghl_load_creds "$PROJECT_ID"

if [[ -z "$CALENDAR" ]]; then
  CALENDAR="$(psql_ro -t -A -c "SELECT ghl_calendar_id FROM crm_calendars
    WHERE project_id='${PROJECT_ID//\'/\'\'}' AND is_active LIMIT 1;")"
  [[ -z "$CALENDAR" ]] && { echo "el proyecto no tiene calendario activo en crm_calendars" >&2; exit 1; }
fi

DESDE_MS="$(python3 -c "import time,sys; print(int((time.time()+int(sys.argv[1])*86400)*1000))" "$DESDE")"
HASTA_MS="$(python3 -c "import time,sys; print(int((time.time()+int(sys.argv[1])*86400)*1000))" "$HASTA")"

ghl_api "/calendars/events$(ghl_qs locationId "$GHL_LOCATION" calendarId "$CALENDAR" \
    startTime "$DESDE_MS" endTime "$HASTA_MS")" \
  | python3 -c '
import json, sys
lim = int(sys.argv[1])
evs = (json.load(sys.stdin).get("events") or [])
evs.sort(key=lambda e: e.get("startTime") or "")
if lim > 0: evs = evs[:lim]
json.dump(evs, sys.stdout)' "$LIMIT" \
  | ghl_render "id:id,estado:appointmentStatus,titulo:title,inicio:startTime,contacto:contactId"

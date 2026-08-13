#!/usr/bin/env bash
# Llamadas de venta AGENDADAS de un día, resueltas por closer — la agenda que
# alimenta los escenarios WhatsApp de los closers (saludo 07:00, recordatorio
# 45 min antes, apertura post-llamada). Read-only.
#
# El closer se resuelve con la MISMA traza CRM de bash/calls/ (booking
# contact_id → crm_contacts → crm_opportunities → users → persons); una llamada
# sin traza sale con closer NULL — visible, no descartada.
#
# ⚠️ ZONA HORARIA (verificado 2026-08-13 contra el histograma de horas y una
# llamada real): meetings.scheduled_start_time guarda la HORA BOGOTÁ etiquetada
# como UTC (jornada 07-20 en el reloj crudo). Por eso aquí se lee el reloj
# LITERAL (AT TIME ZONE 'UTC' extrae el naive tal cual) y NO se convierte —
# convertir a America/Bogota corría todo 5 horas hacia atrás.
#
# Usage: agenda.sh [--fecha YYYY-MM-DD] [--closer FRAG] [--todas] [--json]
#   --fecha    default: hoy (America/Bogota)
#   --closer   filtra por fragmento del nombre del closer
#   --todas    incluye canceladas (default: las excluye)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

FECHA=""; CLOSER=""; TODAS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fecha) FECHA="$2"; shift 2 ;;
    --closer) CLOSER="$2"; shift 2 ;;
    --todas) TODAS=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$FECHA" ]] && FECHA="$(TZ=America/Bogota date +%F)"
[[ "$FECHA" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "--fecha debe ser YYYY-MM-DD" >&2; exit 2; }

WHERE="m.meeting_type='call'
  AND (m.scheduled_start_time AT TIME ZONE 'UTC')::date = '$FECHA'::date"
[[ "$TODAS" == "0" ]] && WHERE="$WHERE AND m.status NOT IN ('cancelled')"
if [[ -n "$CLOSER" ]]; then
  C_ESC="${CLOSER//\'/''}"
  WHERE="$WHERE AND cl.closer ILIKE '%$C_ESC%'"
fi

emit "SELECT left(m.id::text,8) AS id,
  to_char(m.scheduled_start_time AT TIME ZONE 'UTC','HH24:MI') AS hora,
  regexp_replace(m.name, ' *[-|–] *.*$', '') AS lead,
  cl.closer,
  m.meet_url,
  m.status,
  to_char(m.scheduled_start_time AT TIME ZONE 'UTC','YYYY-MM-DD') AS fecha,
  to_char(coalesce(m.scheduled_end_time, m.scheduled_start_time + interval '1 hour')
          AT TIME ZONE 'UTC','HH24:MI') AS fin
FROM meetings m
LEFT JOIN LATERAL (
  SELECT nullif(trim(coalesce(p.name,'')||' '||coalesce(p.lastname,'')),'') AS closer
  FROM crm_contacts c
  JOIN crm_opportunities o ON o.contact_id=c.id
  JOIN users u ON u.id=o.user_id
  JOIN persons p ON p.person_id=u.person_id
  WHERE c.ghl_contact_id = m.event->'booking'->>'contact_id'
  ORDER BY (o.project_id = m.project_id) DESC NULLS LAST, o.created_date DESC
  LIMIT 1
) cl ON true
WHERE $WHERE
ORDER BY m.scheduled_start_time"

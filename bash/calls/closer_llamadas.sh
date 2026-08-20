#!/usr/bin/env bash
# closer_llamadas.sh — TODAS las llamadas de un closer, una fila por meeting,
# con los dos indicadores de captura: transcript (usable = ≥2000 chars, el piso
# conocido — la mitad de las filas de transcript son basura de ~210 chars) y
# reporte (la fuente vigente: cerebro/gemini vía call_report_vigente).
# Alimenta la fuente viz `closer_llamadas` (la UI publicada «Llamadas del
# closer») y el guard del relay de transcript del publicador (--meeting).
#
# Identidad igual que closer_dashboard.sh: --closer-id <users.id> es EXACTA y
# tiene precedencia sobre --closer (fragmento ILIKE, para el DC). Sin ninguno,
# emite todos los closers (la vista del Director Comercial).
#
# --meeting <uuid|prefijo> filtra a UNA llamada — con --closer-id actúa de
# guard: fila vacía = esa llamada no es de ese closer (o no existe).
#
# ⚠️ tz: scheduled_start_time guarda hora Bogotá etiquetada UTC — reloj LITERAL.
#
# Uso: closer_llamadas.sh [--closer FRAG | --closer-id UUID] [--meeting ID]
#                         [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--limit N] [--json]
# Read-only. --limit default 200; 0 = sin tope.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

closer="" closer_id="" meeting="" from="" to="" status="" limit=200
while [[ $# -gt 0 ]]; do
  case "$1" in
    --closer)    closer="$2"; shift 2 ;;
    --closer-id) closer_id="$2"; shift 2 ;;
    --meeting)   meeting="$2"; shift 2 ;;
    --status)    status="$2"; shift 2 ;;
    --from)      from="$2"; shift 2 ;;
    --to)        to="$2"; shift 2 ;;
    --limit)     limit="$2"; shift 2 ;;
    --json)      FORMAT=json; shift ;;
    -h|--help)   sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ "$limit" =~ ^[0-9]+$ ]] || { echo "--limit debe ser entero" >&2; exit 2; }

WHERE="m.meeting_type='call'"
if [[ -n "$closer_id" ]]; then
  [[ "$closer_id" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo "--closer-id debe ser uuid" >&2; exit 2; }
  WHERE="$WHERE AND cl.closer_uid = '$closer_id'::uuid"
elif [[ -n "$closer" ]]; then
  C_ESC="${closer//\'/''}"
  WHERE="$WHERE AND cl.closer ILIKE '%$C_ESC%'"
fi
if [[ -n "$meeting" ]]; then
  M_ESC="${meeting//\'/''}"
  WHERE="$WHERE AND m.id::text LIKE '$M_ESC%'"
fi
if [[ -n "$status" ]]; then
  # acepta lista separada por comas: --status completed,confirmed → IN (…)
  [[ "$status" =~ ^[a-z_]+(,[a-z_]+)*$ ]] || { echo "--status inválido: $status" >&2; exit 2; }
  WHERE="$WHERE AND m.status IN ('${status//,/\',\'}')"
fi
from="${from//\'/}" to="${to//\'/}"
[[ -n "$from" ]] && WHERE="$WHERE AND (m.scheduled_start_time AT TIME ZONE 'UTC')::date >= '$from'"
[[ -n "$to" ]]   && WHERE="$WHERE AND (m.scheduled_start_time AT TIME ZONE 'UTC')::date <= '$to'"
LIM=""; [[ "$limit" != "0" ]] && LIM="LIMIT $limit"

emit "SELECT m.id,
  left(m.id::text,8) AS id8,
  to_char(m.scheduled_start_time AT TIME ZONE 'UTC','YYYY-MM-DD') AS fecha,
  to_char(m.scheduled_start_time AT TIME ZONE 'UTC','HH24:MI')    AS hora,
  regexp_replace(m.name, ' *[-|–] *.*$', '') AS lead,
  nullif(split_part(m.name,' - ',2),'') AS programa,
  pr.name AS proyecto,
  m.status,
  cl.closer,
  coalesce(length(t.transcript),0) AS tr_chars,
  (coalesce(length(t.transcript),0) >= 2000) AS tr_usable,
  v.fuente AS reporte
FROM meetings m
LEFT JOIN projects pr ON pr.id = m.project_id
LEFT JOIN meeting_transcripts t ON t.meeting_id = m.id
LEFT JOIN call_report_vigente v ON v.meeting_id = m.id
LEFT JOIN LATERAL (
  SELECT trim(regexp_replace(p.name||' '||coalesce(p.lastname,''),'\s+',' ','g')) AS closer,
         u.id AS closer_uid
  FROM crm_contacts c
  JOIN crm_opportunities o ON o.contact_id = c.id
  JOIN users u   ON u.id = o.user_id
  JOIN persons p ON p.person_id = u.person_id
  WHERE c.ghl_contact_id = m.event->'booking'->>'contact_id'
  ORDER BY (o.project_id = m.project_id) DESC, o.created_date DESC NULLS LAST
  LIMIT 1) cl ON true
WHERE $WHERE
ORDER BY m.scheduled_start_time DESC
$LIM"

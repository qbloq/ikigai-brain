#!/usr/bin/env bash
# Llamadas cuyo transcript ya está y todavía no tienen reporte DEL CEREBRO.
# Read-only. Es la COLA del pipeline de generación: lo que este script lista es
# exactamente lo que `generar_pendientes.sh` va a mandar a generar.
#
# EL DISPARADOR ES EL TRANSCRIPT, NO EL ESTADO (medido 2026-08-13):
#   · `meetings.status` no sirve como señal de «la llamada terminó»: hay
#     llamadas con transcript en `completed`, en `ended` y una que seguía
#     `in_progress` al día siguiente.
#   · La fila de `meeting_transcripts` aparece entre +4 min y +90 min del inicio
#     — o sea, prácticamente al colgar. Ese SÍ es el evento.
#   · Pero la mitad de las filas son BASURA: ~210-220 caracteres (el modo de
#     fallo que llenó producción de BANT en cero). Las de verdad pesan 23k-70k.
#     Por eso el piso de --min-chars, que es el mismo del skill.
#   · Cobertura real: solo 25-40% de las llamadas que ocurren dejan transcript.
#     Esta cola NO es el universo de llamadas del día — es el subconjunto que se
#     puede analizar. El mensaje post-llamada a ciegas (escenario 3) sigue
#     haciendo falta para el resto.
#
# ⚠️ `scheduled_start_time` guarda hora BOGOTÁ etiquetada UTC (se lee literal);
# `meeting_transcripts.created_at` sí es timestamptz de verdad (se convierte).
#
# Usage: reportes_pendientes.sh [--desde N] [--min-chars N] [--con-closer]
#                               [--limit N] [--json]
#   --desde N      solo transcripts creados en los últimos N días (default 7;
#                  0 = sin límite — sirve para la primera pasada histórica)
#   --min-chars N  piso de transcript usable (default 2000)
#   --con-closer   solo las que resolvieron closer (las que pueden generar mensaje)
set -euo pipefail
cd "$(dirname "$0")/../.."
source bash/lib/common.sh

DESDE=7; MIN=2000; CON_CLOSER=0; LIMIT=50
while [[ $# -gt 0 ]]; do
  case "$1" in
    --desde) DESDE="$2"; shift 2 ;;
    --min-chars) MIN="$2"; shift 2 ;;
    --con-closer) CON_CLOSER=1; shift ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ "$DESDE" =~ ^[0-9]+$ && "$MIN" =~ ^[0-9]+$ && "$LIMIT" =~ ^[0-9]+$ ]] || {
  echo "--desde/--min-chars/--limit deben ser enteros" >&2; exit 2; }

WHERE="m.meeting_type='call'
  AND length(t.transcript) >= $MIN
  AND cr.meeting_id IS NULL"
[[ "$DESDE" != "0" ]] && WHERE="$WHERE AND t.created_at >= now() - interval '$DESDE days'"
[[ "$CON_CLOSER" == "1" ]] && WHERE="$WHERE AND cl.closer IS NOT NULL"
LIM=""; [[ "$LIMIT" != "0" ]] && LIM="LIMIT $LIMIT"

emit "SELECT left(m.id::text,8) AS id,
  m.id::text AS uuid,
  to_char(m.scheduled_start_time AT TIME ZONE 'UTC','YYYY-MM-DD') AS fecha,
  to_char(m.scheduled_start_time AT TIME ZONE 'UTC','HH24:MI') AS hora,
  regexp_replace(m.name, ' *[-|–] *.*\$', '') AS lead,
  cl.closer,
  length(t.transcript) AS chars,
  to_char(t.created_at AT TIME ZONE 'America/Bogota','MM-DD HH24:MI') AS tr_listo,
  (SELECT count(*) FROM ikigaigm.call_reports_gemini g WHERE g.meeting_id=m.id) AS tenia_gemini
FROM meetings m
JOIN meeting_transcripts t ON t.meeting_id = m.id
LEFT JOIN ikigaigm.call_reports cr ON cr.meeting_id = m.id
LEFT JOIN LATERAL (
  SELECT nullif(trim(coalesce(p.name,'')||' '||coalesce(p.lastname,'')),'') AS closer
  FROM crm_contacts c
  JOIN crm_opportunities o ON o.contact_id=c.id
  LEFT JOIN users u ON u.id=o.user_id
  LEFT JOIN persons p ON p.person_id=u.person_id
  WHERE c.ghl_contact_id = m.event->'booking'->>'contact_id'
  ORDER BY (o.project_id = m.project_id) DESC NULLS LAST, o.created_date DESC
  LIMIT 1
) cl ON true
WHERE $WHERE
ORDER BY t.created_at DESC
$LIM"

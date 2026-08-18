#!/usr/bin/env bash
# El bucle S10 acta→tablero, medido: por cada reunión de equipo con transcript,
# cuántos compromisos dejó el acta (`report->'actionItems'`) contra cuántas
# tareas nacieron de ella (`tasks.source_meeting_id`). Read-only.
#
# Usage:
#   action_items_gap.sh [--days N] [--since YYYY-MM-DD] [--pendientes]
#                       [--project NAME] [--limit N] [--json]
#   --days N      ventana hacia atrás (default 60)
#   --since D     fecha explícita; gana sobre --days
#   --pendientes  sólo lo que la automatización debe procesar (sin reporte o
#                 con reporte y cero tareas) — la COLA DE ENTRADA de la Routine
#   --project NAME  fragmento del nombre del proyecto de la reunión
#   --limit N     tope de filas (default 40; 0 = sin tope)
#
# DOS USOS, UNA CONSULTA. El pipeline reunión→tareas (skills transcript-to-report
# → meeting-to-tasks) hoy se corre a mano y va a dispararse por una Claude
# Routine al generarse el transcript. Una Routine por cron no reacciona a
# eventos: pregunta "¿qué quedó sin procesar?" — exactamente esta consulta. Así
# que este script es a la vez el disparador de la automatización y la tarjeta
# S10 de la torre de control del Project Manager. En régimen normal, `--pendientes`
# devuelve cero filas.
#
# `estado` por reunión:
#   sin_reporte  hay transcript y no hay reporte      → Stage 1 no corrió/falló
#   sin_tareas   hay reporte y cero tareas            → Stage 2-3 no corrió/falló
#   parcial      hay tareas, pero menos que compromisos
#   ok           tareas >= compromisos
#
# `horas_a_tarea` = latencia transcript → primera tarea asentada: el SLA real de
# la Routine. Sube antes de romperse.
#
# CAVEAT — el gap es un LÍMITE SUPERIOR, no fuga confirmada. Un compromiso puede
# haberse resuelto sobre una tarea que ya existía (el camino de dedup escribe un
# comentario con add_comment.sh, no una tarea nueva), y un acta puede repetir el
# mismo compromiso en dos ítems. Léelo como cola a triar, no como veredicto.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

days=60 since="" pendientes="" project="" limit="40"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --days)       days="$2"; shift 2 ;;
    --since)      since="$2"; shift 2 ;;
    --pendientes) pendientes=1; shift ;;
    --project)    project="$2"; shift 2 ;;
    --limit)      limit="$2"; shift 2 ;;
    --json)       FORMAT=json; shift ;;
    -h|--help)    sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ "$days" =~ ^[0-9]+$ ]] || { echo "--days espera un entero, no '$days'" >&2; exit 2; }
[[ -z "$since" || "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "--since espera YYYY-MM-DD, no '$since'" >&2; exit 2; }
[[ "$limit" =~ ^[0-9]+$ ]] || { echo "--limit espera un entero, no '$limit'" >&2; exit 2; }

desde="now() - interval '$days days'"
[[ -n "$since" ]] && desde="date '$since'"

where="m.meeting_type = 'team' AND m.scheduled_start_time > $desde"
if [[ -n "$project" ]]; then
  pid="$(resolve_project "$project")"
  [[ -n "$pid" ]] || { echo "No project matched: $project" >&2; exit 1; }
  where="$where AND m.project_id = '$pid'"
fi

lim=""
[[ "$limit" != "0" ]] && lim="LIMIT $limit"

# Sólo reuniones CON transcript: sin materia prima no hay nada que procesar, y
# meterlas inflaría el gap con reuniones que el pipeline nunca podría cerrar.
sql="SELECT left(m.id::text, 8)                          AS id,
       to_char(m.scheduled_start_time, 'YYYY-MM-DD')     AS fecha,
       coalesce(pr.name, '—')                            AS proyecto,
       left(m.name, 46)                                  AS reunion,
       x.items                                           AS compromisos,
       x.tareas,
       greatest(x.items - x.tareas, 0)                   AS gap,
       CASE WHEN r.meeting_id IS NULL       THEN 'sin_reporte'
            WHEN x.tareas = 0               THEN 'sin_tareas'
            WHEN x.tareas < x.items         THEN 'parcial'
            ELSE 'ok' END                                AS estado,
       round(extract(epoch FROM x.primera_tarea - mt.created_at) / 3600.0, 1) AS horas_a_tarea
  FROM meetings m
  JOIN meeting_transcripts mt ON mt.meeting_id = m.id
  LEFT JOIN meeting_reports r ON r.meeting_id = m.id
  LEFT JOIN projects pr ON pr.id = m.project_id
  CROSS JOIN LATERAL (
    SELECT jsonb_array_length(coalesce(r.report->'actionItems', '[]'::jsonb)) AS items,
           (SELECT count(*)      FROM tasks t WHERE t.source_meeting_id = m.id) AS tareas,
           (SELECT min(t.created_at) FROM tasks t WHERE t.source_meeting_id = m.id) AS primera_tarea
  ) x
 WHERE $where"

[[ -n "$pendientes" ]] && sql="$sql AND (r.meeting_id IS NULL OR x.tareas = 0)"

emit "$sql ORDER BY m.scheduled_start_time DESC $lim"

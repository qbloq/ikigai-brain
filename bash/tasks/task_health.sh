#!/usr/bin/env bash
# Salud del sistema de tareas — el objeto que alimenta la torre de control del
# Project Manager (una llamada, una pantalla). Read-only.
#
# Usage:  task_health.sh [--stale N] [--project NAME] [--json]
#   --stale N      umbral de "estancada" en días sin movimiento (default 14)
#   --project NAME acota TODO el objeto a un proyecto (fragmento del nombre)
#   --json         un objeto JSON (el resto de la capa emite arrays; este emite
#                  un record, como bash/metrics/dashboard.sh)
#
# Emite cuatro bloques, que son las cuatro franjas de la torre:
#   ESTADO   abiertas · vencidas (+%) · estancadas · sin fecha · vence hoy/semana
#   RITMO    cerradas 7d/30d · % a tiempo · ciclo mediano   ← ver "regimen" abajo
#   HAND-OFF carga[]  — por persona: abiertas, vencidas, estancadas, antigüedad
#   FÁBRICA  macros[] — abiertas por macro-proceso (arquetipo→SOP→macro)
#   HIGIENE  sin arquetipo · sin outputs · el gap S10 actas→tareas
#
# RITMO — honestidad de la medición. Antes de la migración 003 el sistema no
# sellaba el instante de cierre: `updated_at` de las completadas trae dos fechas
# de sync masivo y `created_at` de 294 tareas es el día en que se importaron de
# Notion. Por eso TODA métrica de ritmo se calcula sólo sobre `completed_at IS
# NOT NULL` (lo cerrado bajo el régimen nuevo) y el objeto expone `ritmo_desde`
# = el primer cierre sellado, o null si todavía no hay ninguno. Un consumidor
# que vea `ritmo_desde: null` debe decir "aún no se mide", nunca "cero".
# El ciclo mediano además exige que la tarea haya NACIDO bajo el régimen
# (created_at >= REGIMEN_DESDE), porque para las importadas created_at es la
# fecha de importación y el ciclo saldría inflado.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

# Día en que se aplicó catalog/migrations/003_task_completed_at.sql — la
# frontera entre "created_at es la fecha de importación" y "created_at es real".
REGIMEN_DESDE="2026-07-27"

stale=14 project=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --stale)   stale="$2"; shift 2 ;;
    --project) project="$2"; shift 2 ;;
    --json)    FORMAT=json; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ "$stale" =~ ^[0-9]+$ ]] || { echo "--stale espera un número entero de días, no '$stale'" >&2; exit 2; }

pfilter="true"
if [[ -n "$project" ]]; then
  pid="$(resolve_project "$project")"
  [[ -n "$pid" ]] || { echo "No project matched: $project" >&2; exit 1; }
  pfilter="t.project_id = '$pid'"
fi

# El gap S10 sólo tiene sentido a nivel org (una reunión no es de un proyecto en
# el mismo sentido que una tarea), así que no se filtra por proyecto.
read -r -d '' BODY <<SQL || true
WITH abiertas AS (
  SELECT t.* FROM tasks t WHERE $OPEN_PRED AND $pfilter
),
estado AS (
  SELECT count(*)                                                          AS abiertas,
         count(*) FILTER (WHERE t.status = 'in_progress')                   AS en_curso,
         count(*) FILTER (WHERE t.due_date::date < current_date)            AS vencidas,
         count(*) FILTER (WHERE t.updated_at < now() - interval '$stale days') AS estancadas,
         count(*) FILTER (WHERE t.due_date IS NULL)                         AS sin_fecha,
         count(*) FILTER (WHERE t.due_date::date = current_date)            AS vence_hoy,
         count(*) FILTER (WHERE t.due_date::date BETWEEN current_date
                            AND (date_trunc('week', current_date) + interval '6 days')::date) AS vence_semana,
         count(*) FILTER (WHERE t.archetype_id IS NULL)                     AS sin_arquetipo,
         count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM task_outputs o WHERE o.task_id = t.id)) AS sin_outputs
    FROM abiertas t
),
ritmo AS (
  SELECT count(*) FILTER (WHERE t.completed_at >= now() - interval '7 days')  AS cerradas_7d,
         count(*) FILTER (WHERE t.completed_at >= now() - interval '30 days') AS cerradas_30d,
         min(t.completed_at)::date                                            AS ritmo_desde,
         round(avg(CASE WHEN t.completed_at >= now() - interval '30 days' AND t.due_date IS NOT NULL
                        THEN (t.completed_at::date <= t.due_date::date)::int END)::numeric, 3) AS pct_a_tiempo_30d,
         percentile_cont(0.5) WITHIN GROUP (
           ORDER BY CASE WHEN t.created_at::date >= date '$REGIMEN_DESDE'
                         THEN extract(epoch FROM t.completed_at - t.created_at) / 86400 END
         )                                                                     AS ciclo_mediano_dias
    FROM tasks t
   WHERE t.completed_at IS NOT NULL AND $pfilter
),
s10 AS (
  -- El bucle acta→tablero: reuniones de equipo con transcript en los últimos
  -- 60 días, cuántas no dejaron ninguna tarea y cuántos compromisos quedaron
  -- sin tablero. Detalle por reunión: bash/meetings/action_items_gap.sh
  SELECT count(*)                                                   AS reuniones_60d,
         count(*) FILTER (WHERE r.meeting_id IS NULL)               AS sin_reporte,
         count(*) FILTER (WHERE r.meeting_id IS NOT NULL AND x.tareas = 0) AS sin_procesar,
         coalesce(sum(greatest(x.items - x.tareas, 0)), 0)          AS compromisos_sin_tablero
    FROM meetings m
    JOIN meeting_transcripts mt ON mt.meeting_id = m.id
    LEFT JOIN meeting_reports r ON r.meeting_id = m.id
    CROSS JOIN LATERAL (
      SELECT jsonb_array_length(coalesce(r.report->'actionItems', '[]'::jsonb)) AS items,
             (SELECT count(*) FROM tasks t2 WHERE t2.source_meeting_id = m.id)  AS tareas
    ) x
   WHERE m.meeting_type = 'team'
     AND m.scheduled_start_time > now() - interval '60 days'
),
carga AS (
  SELECT trim(coalesce(p.name,'') || ' ' || coalesce(p.lastname,'')) AS persona,
         count(*)                                                     AS abiertas,
         count(*) FILTER (WHERE t.due_date::date < current_date)      AS vencidas,
         count(*) FILTER (WHERE t.updated_at < now() - interval '$stale days') AS estancadas,
         round(percentile_cont(0.5) WITHIN GROUP (
           ORDER BY extract(epoch FROM now() - t.updated_at) / 86400)::numeric, 0) AS dias_sin_mover
    FROM abiertas t, unnest(t.assignee) aid
    JOIN team_members tm ON tm.id = aid
    LEFT JOIN users u ON u.id = tm.user_id
    LEFT JOIN persons p ON p.person_id = u.person_id
   GROUP BY 1
   HAVING trim(coalesce(p.name,'') || ' ' || coalesce(p.lastname,'')) <> ''
   ORDER BY 2 DESC
),
macros AS (
  SELECT mp.code, mp.name,
         count(*) FILTER (WHERE $OPEN_PRED) AS abiertas,
         count(*)                            AS total
    FROM tasks t
    JOIN activity_archetypes a ON a.id = t.archetype_id
    JOIN sops s ON s.code = a.sop_code
    JOIN macro_processes mp ON mp.code = s.macro_process_code
   WHERE $pfilter
   GROUP BY 1, 2
  HAVING count(*) FILTER (WHERE $OPEN_PRED) > 0
   ORDER BY 3 DESC
)
SQL

KPIS="SELECT e.*,
        round(e.vencidas::numeric / nullif(e.abiertas,0), 3) AS pct_vencidas,
        r.cerradas_7d, r.cerradas_30d, r.ritmo_desde, r.pct_a_tiempo_30d,
        round(r.ciclo_mediano_dias::numeric, 1) AS ciclo_mediano_dias,
        g.reuniones_60d, g.sin_reporte, g.sin_procesar, g.compromisos_sin_tablero,
        $stale AS umbral_estancada,
        '${project:-toda la org}'::text AS alcance
       FROM estado e CROSS JOIN ritmo r CROSS JOIN s10 g"

if [[ "$FORMAT" == "json" ]]; then
  printf '%s\nSELECT row_to_json(o) FROM (SELECT k.*, (SELECT coalesce(json_agg(c),%s) FROM carga c) AS carga, (SELECT coalesce(json_agg(m),%s) FROM macros m) AS macros FROM (%s) k) o;\n' \
    "$BODY" "'[]'::json" "'[]'::json" "$KPIS" | psql_ro -t -A
else
  printf '%s\n%s;\n' "$BODY" "$KPIS" | psql_ro -x
  printf '%s\nSELECT * FROM carga;\n' "$BODY" | psql_ro
  printf '%s\nSELECT * FROM macros;\n' "$BODY" | psql_ro
fi

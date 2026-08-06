#!/usr/bin/env bash
# lead_score_model.sh — EL MODELO de score de leads como un solo objeto JSON.
# Es el entregable de la tarea 767605d8 (arquetipo A6.8) en forma consultable:
# lo que docs/lead-score.md argumenta en prosa, esto lo emite en datos.
#
# Reúne los DOS scores, que existen en momentos distintos y sirven para cosas
# distintas (ese es el hallazgo central del modelo):
#
#   PRE-llamada   la encuesta de calificación que el lead responde al agendar,
#                 en crm_contacts.custom_fields. Existe ANTES de asignar, así
#                 que es la única que puede ordenar la cola y decidir quién
#                 confirma.
#   POST-llamada  el BANT que el analizador deriva del transcript. Existe solo
#                 DESPUÉS, así que no puede priorizar a quién llamar — solo a
#                 quién perseguir.
#
# Las normalizaciones (ceros excluidos, resultado canónico) son las de
# lead_profile.sh, que es la FUENTE DE VERDAD; aquí se agregan para la vista.
#
# Uso: lead_score_model.sh [--project NAME] [--json]   (siempre emite JSON)
# Read-only. Alimenta la fuente `lead_score` del viz.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

project=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) project="$2"; shift 2 ;;
    --json)    shift ;;   # siempre JSON; se acepta por simetría
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

pfilter="true"
if [[ -n "$project" ]]; then
  pid="$(resolve_project "$project")"
  [[ -z "$pid" ]] && { echo "No project matches: $project" >&2; exit 1; }
  pfilter="m.project_id = '$pid'"
  ofilter="o.project_id = '$pid'"
else
  ofilter="true"
fi

psql_ro -t -A -c "
WITH b AS (
  SELECT m.id, m.scheduled_start_time AS ts,
         coalesce(r.report->'generalInformation'->>'callStatus','') AS st,
         initcap(trim(regexp_replace(lower(coalesce(
           r.report->'leadProfile'->'intelligentSegmentation'->'archetype'->>'name','')),'\s+',' ','g'))) AS arq,
         coalesce(nullif(regexp_replace(coalesce(r.report->'leadProfile'->'bantAnalysis'->'need'->>'score',''),'[^0-9]','','g'),'')::numeric,0)      AS need,
         coalesce(nullif(regexp_replace(coalesce(r.report->'leadProfile'->'bantAnalysis'->'budget'->>'score',''),'[^0-9]','','g'),'')::numeric,0)    AS budget,
         coalesce(nullif(regexp_replace(coalesce(r.report->'leadProfile'->'bantAnalysis'->'timeline'->>'score',''),'[^0-9]','','g'),'')::numeric,0)  AS timeline,
         coalesce(nullif(regexp_replace(coalesce(r.report->'leadProfile'->'bantAnalysis'->'authority'->>'score',''),'[^0-9]','','g'),'')::numeric,0) AS authority,
         cl.closer
  FROM meetings m
  JOIN meeting_reports r ON r.meeting_id = m.id
  LEFT JOIN LATERAL (
    SELECT trim(regexp_replace(p.name||' '||coalesce(p.lastname,''),'\s+',' ','g')) AS closer
    FROM crm_contacts c
    JOIN crm_opportunities o2 ON o2.contact_id = c.id
    JOIN users u   ON u.id = o2.user_id
    JOIN persons p ON p.person_id = u.person_id
    WHERE c.ghl_contact_id = m.event->'booking'->>'contact_id'
    ORDER BY (o2.project_id = m.project_id) DESC, o2.created_date DESC NULLS LAST
    LIMIT 1) cl ON true
  WHERE m.meeting_type='call' AND $pfilter
),
p AS (
  SELECT b.*, (need+budget+timeline+authority)/4.0 AS score,
         CASE
           WHEN st ~* '^closed( |-|/|\()|^closed\$' THEN 'ganada'
           WHEN st ~* '(committ|compromiso|deposit (paid|made|secured)|partial (payment|close)|pre-closed|payment plan initiated|initiated purchase|^reserved|^cerrado)' THEN 'compromiso'
           WHEN st ~* '(follow-?up|seguimiento|pending|decision)' THEN 'seguimiento'
           WHEN st ~* 'unqualified' THEN 'no calificado'
           WHEN st ~* 'no ?show'    THEN 'no asistió'
           ELSE 'sin data'
         END AS resultado,
         coalesce(nullif(concat_ws(' + ',
           CASE WHEN arq ~* 'emotional'           THEN 'Emocional' END,
           CASE WHEN arq ~* 'novice'              THEN 'Novato' END,
           CASE WHEN arq ~* 'inexperienced'       THEN 'Inexperto' END,
           CASE WHEN arq ~* '(^|[^n])experienced' THEN 'Experimentado' END), ''), '(sin determinar)') AS rasgo
  FROM b
),
v AS (SELECT * FROM p WHERE score > 0),   -- el universo válido: BANT distinto de cero
enc AS (
  SELECT c.id AS contact_id, o.status,
         max(CASE WHEN cf.name ILIKE '%al menos \$1.500%'                THEN nullif(x->>'value','') END) AS presupuesto,
         max(CASE WHEN cf.name ILIKE '%situación te encuentras actualmente%' THEN nullif(x->>'value','') END) AS disposicion
  FROM crm_contacts c
  JOIN crm_opportunities o ON o.contact_id = c.id AND $ofilter
  JOIN LATERAL jsonb_array_elements(coalesce(c.custom_fields,'[]'::jsonb)) x ON true
  JOIN crm_custom_fields cf ON cf.ghl_field_id = x->>'id' AND cf.project_id = o.project_id
  GROUP BY 1,2
)
SELECT json_build_object(
  'corte', to_char(current_date,'YYYY-MM-DD'),
  'meta', (SELECT json_build_object(
      'reportes',      (SELECT count(*) FROM p),
      'con_bant',      (SELECT count(*) FROM v),
      'bant_cero',     (SELECT count(*) FROM p WHERE score = 0),
      'con_encuesta',  (SELECT count(*) FROM enc WHERE presupuesto IS NOT NULL OR disposicion IS NOT NULL),
      'corte_util',    80)),
  -- POST-llamada: la validación del score contra el resultado real.
  'tramos', coalesce((SELECT json_agg(t ORDER BY t.tramo DESC) FROM (
      SELECT CASE WHEN score >= 81 THEN '81-100' WHEN score >= 61 THEN '61-80'
                  WHEN score >= 41 THEN '41-60'  WHEN score >= 21 THEN '21-40'
                  ELSE '0-20' END AS tramo,
             count(*) AS llamadas,
             count(*) FILTER (WHERE resultado IN ('ganada','compromiso')) AS convirtio,
             round(100.0*count(*) FILTER (WHERE resultado IN ('ganada','compromiso'))/count(*),1) AS conv_pct,
             count(*) FILTER (WHERE resultado='seguimiento') AS en_seguimiento
      FROM v GROUP BY 1) t), '[]'::json),
  -- Los subgrupos, colapsados a rasgo base.
  'rasgos', coalesce((SELECT json_agg(t ORDER BY t.llamadas DESC) FROM (
      SELECT rasgo, count(*) AS llamadas, round(avg(score))::int AS bant_prom,
             count(*) FILTER (WHERE resultado IN ('ganada','compromiso')) AS convirtio,
             round(100.0*count(*) FILTER (WHERE resultado IN ('ganada','compromiso'))/count(*),1) AS conv_pct
      FROM v GROUP BY 1) t), '[]'::json),
  -- PRE-llamada: las dos preguntas de la encuesta que discriminan.
  'presupuesto', coalesce((SELECT json_agg(t ORDER BY t.cierre_pct DESC) FROM (
      SELECT presupuesto AS respuesta, count(*) AS leads,
             count(*) FILTER (WHERE status='won') AS ganados,
             round(100.0*count(*) FILTER (WHERE status='won')/count(*),1) AS cierre_pct
      FROM enc WHERE presupuesto IS NOT NULL GROUP BY 1 HAVING count(*) >= 10) t), '[]'::json),
  'disposicion', coalesce((SELECT json_agg(t ORDER BY t.cierre_pct DESC) FROM (
      SELECT disposicion AS respuesta, count(*) AS leads,
             count(*) FILTER (WHERE status='won') AS ganados,
             round(100.0*count(*) FILTER (WHERE status='won')/count(*),1) AS cierre_pct
      FROM enc WHERE disposicion IS NOT NULL GROUP BY 1 HAVING count(*) >= 10) t), '[]'::json),
  -- La cola accionable: BANT alto que nunca cerró.
  'cola', coalesce((SELECT json_agg(t ORDER BY t.n DESC) FROM (
      SELECT coalesce(closer,'(sin resolver)') AS closer, count(*) AS n
      FROM v WHERE score >= 81 AND resultado='seguimiento' GROUP BY 1) t), '[]'::json),
  'cola_total', (SELECT count(*) FROM v WHERE score >= 81 AND resultado='seguimiento')
)::text;"

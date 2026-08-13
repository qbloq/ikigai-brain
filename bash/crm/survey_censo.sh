#!/usr/bin/env bash
# survey_censo.sh — el CENSO del survey de calificación: cada pregunta de
# crm_custom_fields con su cobertura real, la distribución de sus respuestas y
# la conversión A PLATA por respuesta. Un solo objeto JSON.
#
# Es la generalización sistemática de docs/lead-score.md §3: aquel eligió a
# mano las dos preguntas que discriminan; este mide TODO el instrumento, que es
# el baseline sin el cual ningún A/B de survey se puede leer. La salud de cada
# pregunta se lee en dos números:
#
#   planitud  — % de la respuesta modal. Una pregunta donde (casi) todos
#               contestan lo mismo no puede discriminar (es el `need` a 95 del
#               experimento BANT, versión formulario).
#   spread    — max−min de conversión entre respuestas con n≥20. Una pregunta
#               plana en conversión tampoco ordena, por variada que sea.
#
# La VERDAD es plata, no `status='won'` ni `callStatus`: un contacto convirtió
# si tiene un payment_plan con ≥1 cuota Paid, CREADO en o después de su primera
# oportunidad (un plan anterior es un cliente que ya existía, no una conversión
# del lead — misma guardia que conversion_real.sh, anclada a la oportunidad
# porque aquí el universo son leads, no llamadas).
#
# ⚠️ Al leer: «sin responder» NO es una categoría comparable entre preguntas
# (poblaciones y épocas distintas — ver docs/lead-score.md). Por eso cada
# pregunta se mide SOLO sobre quienes la respondieron, y la cobertura va aparte.
#
# Read-only. Uso: survey_censo.sh [--project N] [--json]
# Alimenta la fuente `survey_censo` del viz (emite object).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

project=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) project="$2"; shift 2 ;;
    --json)    shift ;;   # siempre JSON; se acepta por simetría
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

pfilter="true"
if [[ -n "$project" ]]; then
  pid="$(resolve_project "$project")"
  [[ -z "$pid" ]] && { echo "No project matches: $project" >&2; exit 1; }
  pfilter="c.project_id = '$pid'"
fi

psql_ro -t -A -c "
WITH con AS (
  -- El universo: cada contacto del espejo con su primera oportunidad (ancla
  -- temporal) y su desenlace en plata.
  SELECT c.id, c.ghl_contact_id, c.project_id,
         (SELECT min(o.created_date)::date FROM crm_opportunities o
           WHERE o.contact_id = c.id) AS primera_opp,
         c.custom_fields
  FROM crm_contacts c
  WHERE $pfilter
), pago AS (
  SELECT con.id,
         EXISTS (
           SELECT 1 FROM payment_plans p
           JOIN installments i ON i.plan_id = p.plan_id AND i.status = 'Paid'
           WHERE p.customer_id = con.ghl_contact_id
             AND p.created_at::date >= coalesce(con.primera_opp, '1900-01-01'::date)
         ) AS pago
  FROM con
), resp AS (
  -- Una fila por contacto×pregunta respondida, con el valor normalizado
  -- (algunos vienen como array JSON — ['\"…\"'] — de los picklist de GHL).
  SELECT con.id AS contact_id, con.project_id, cf.ghl_field_id,
         cf.name AS campo, cf.data_type, cf.position,
         cf.name ~* '^(utm_|scor_|assign to user)' AS es_meta,
         CASE WHEN f->>'value' ~ '^\[\".*\"\]\$'
              THEN (SELECT string_agg(e, ' | ') FROM jsonb_array_elements_text((f->>'value')::jsonb) e)
              ELSE f->>'value' END AS valor,
         pg.pago
  FROM con
  JOIN pago pg ON pg.id = con.id
  CROSS JOIN LATERAL jsonb_array_elements(coalesce(con.custom_fields,'[]'::jsonb)) f
  JOIN crm_custom_fields cf ON cf.ghl_field_id = f->>'id' AND cf.project_id = con.project_id
  WHERE nullif(f->>'value','') IS NOT NULL
), vals AS (
  -- La distribución de cada pregunta, con conversión por valor.
  SELECT project_id, ghl_field_id, valor, count(*) AS n,
         count(*) FILTER (WHERE pago) AS pagaron
  FROM resp GROUP BY 1,2,3
), pregunta AS (
  SELECT r.project_id, r.ghl_field_id,
         max(r.campo) AS campo, max(r.data_type) AS data_type,
         max(r.position) AS position, bool_or(r.es_meta) AS es_meta,
         count(DISTINCT r.contact_id) AS respondidas,
         count(DISTINCT r.contact_id) FILTER (WHERE r.pago) AS pagaron,
         count(DISTINCT r.valor) AS n_valores
  FROM resp r GROUP BY 1,2
), stats AS (
  SELECT p.*,
         round(100.0 * (SELECT max(v.n) FROM vals v
            WHERE v.ghl_field_id = p.ghl_field_id AND v.project_id = p.project_id)
            / p.respondidas, 1) AS planitud_pct,
         round(100.0 * p.pagaron / p.respondidas, 1) AS conv_resp_pct,
         -- spread: solo entre valores con n≥20 — con menos, la diferencia es ruido
         (SELECT round(max(100.0*v.pagaron/v.n) - min(100.0*v.pagaron/v.n), 1)
            FROM vals v
           WHERE v.ghl_field_id = p.ghl_field_id AND v.project_id = p.project_id
             AND v.n >= 20
          HAVING count(*) >= 2) AS spread_pp
  FROM pregunta p
), catalogo AS (
  -- TODAS las preguntas del catálogo, también las que nadie respondió: el
  -- censo de preguntas muertas es parte del hallazgo.
  SELECT cf.project_id, cf.ghl_field_id, cf.name AS campo, cf.data_type,
         cf.position, cf.name ~* '^(utm_|scor_|assign to user)' AS es_meta
  FROM crm_custom_fields cf
  WHERE EXISTS (SELECT 1 FROM con WHERE con.project_id = cf.project_id)
)
SELECT json_build_object(
  'corte', to_char(current_date,'YYYY-MM-DD'),
  'meta', (SELECT json_build_object(
      'contactos', (SELECT count(*) FROM con),
      'con_encuesta', (SELECT count(DISTINCT contact_id) FROM resp WHERE NOT es_meta),
      'conv_global_pct', (SELECT round(100.0*count(*) FILTER (WHERE pago)/count(*),1) FROM pago),
      'conv_con_encuesta_pct', (SELECT round(100.0*count(*) FILTER (WHERE pg.pago)/count(*),1)
         FROM (SELECT DISTINCT contact_id FROM resp WHERE NOT es_meta) r
         JOIN pago pg ON pg.id = r.contact_id),
      'preguntas_total', (SELECT count(*) FROM catalogo WHERE NOT es_meta),
      'preguntas_vivas', (SELECT count(*) FROM stats WHERE NOT es_meta AND respondidas >= 30))),
  'proyectos', coalesce((SELECT json_agg(pj ORDER BY pj.contactos DESC) FROM (
    SELECT pr.name AS proyecto,
           (SELECT count(*) FROM con WHERE con.project_id = pr.id) AS contactos,
           coalesce((SELECT json_agg(q ORDER BY q.respondidas DESC, q.position NULLS LAST) FROM (
             SELECT s.campo, s.data_type, s.es_meta, s.position, s.respondidas, s.n_valores,
                    round(100.0*s.respondidas /
                      nullif((SELECT count(*) FROM con WHERE con.project_id = pr.id),0),1) AS cobertura_pct,
                    s.planitud_pct, s.conv_resp_pct, s.spread_pp,
                    (SELECT json_agg(vv ORDER BY vv.n DESC) FROM (
                       SELECT v.valor, v.n, v.pagaron,
                              round(100.0*v.pagaron/v.n,1) AS conv_pct
                       FROM vals v
                       WHERE v.ghl_field_id = s.ghl_field_id AND v.project_id = pr.id
                       ORDER BY v.n DESC LIMIT 12) vv) AS valores,
                    greatest(s.n_valores - 12, 0) AS valores_omitidos
             FROM stats s WHERE s.project_id = pr.id) q), '[]'::json) AS preguntas,
           coalesce((SELECT json_agg(m ORDER BY m.position NULLS LAST) FROM (
             SELECT c2.campo, c2.data_type, c2.position
             FROM catalogo c2
             WHERE c2.project_id = pr.id AND NOT c2.es_meta
               AND NOT EXISTS (SELECT 1 FROM stats s
                  WHERE s.ghl_field_id = c2.ghl_field_id AND s.project_id = pr.id)) m),
             '[]'::json) AS muertas
    FROM projects pr
    WHERE EXISTS (SELECT 1 FROM con WHERE con.project_id = pr.id)) pj), '[]'::json)
)::text;"

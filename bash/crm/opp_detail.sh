#!/usr/bin/env bash
# opp_detail.sh — todo lo que sabemos de UNA oportunidad y su contacto, como un
# solo objeto JSON. Es el gemelo de detalle de sin_dueno.sh / pipeline.sh --list,
# pensado para el panel derecho del viz (fuente `crm_opp_detail`).
#
# Incluye los custom_fields del contacto tal cual vienen de GHL: ahí es donde
# suele quedar la huella del formulario de entrada, que es lo que hace falta
# para entender por dónde llegó un lead que nadie tomó.
#
# Uso: opp_detail.sh <id|prefijo> [--json]   (siempre emite JSON)
# Read-only.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

# El posicional puede venir en cualquier posición: el viz arma el argv con
# --json primero (buildArgs), y a mano se escribe al revés.
ref=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) shift ;;   # siempre JSON; se acepta por simetría con el resto
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) [[ -n "$ref" ]] && { echo "Sobra el argumento '$1'." >&2; exit 2; }; ref="$1"; shift ;;
  esac
done
[[ -z "$ref" ]] && { sed -n '2,12p' "$0"; exit 0; }

esc="${ref//\'/\'\'}"

psql_ro -t -A -c "
SELECT coalesce(row_to_json(q)::text, '{}') FROM (
  SELECT left(o.id::text,8)                        AS id,
         o.ghl_opportunity_id                      AS ghl_id,
         o.name                                    AS lead,
         o.status                                  AS estado,
         o.monetary_value                          AS valor,
         to_char(o.created_date,'YYYY-MM-DD HH24:MI') AS creada,
         to_char(o.last_status_change_at,'YYYY-MM-DD HH24:MI') AS ultimo_cambio,
         (CURRENT_DATE - o.created_date::date)     AS dias,
         pr.name                                   AS proyecto,
         pl.ghl_pipeline_name                      AS pipeline,
         coalesce(st.name,'—')                     AS etapa,
         o.assigned_to                             AS ghl_assigned_to,
         CASE WHEN o.user_id IS NULL THEN 'sin dueño' ELSE
              coalesce(nullif(trim(coalesce(pe.name,'')||' '||coalesce(pe.lastname,'')),''),'—') END AS dueno,
         -- contacto
         c.ghl_contact_id                          AS contacto_ghl_id,
         coalesce(nullif(trim(coalesce(c.first_name,'')||' '||coalesce(c.last_name,'')),''),'—') AS contacto,
         c.email, c.phone                          AS telefono,
         coalesce(array_to_string(c.tags,', '),'—') AS tags,
         -- Los custom_fields de GHL vienen como [{id,value}] con el id opaco.
         -- crm_custom_fields tiene el catálogo, así que aquí salen ya con su
         -- pregunta: es el survey de calificación que respondió el lead, más
         -- las utm_* de atribución.
         (SELECT coalesce(jsonb_agg(jsonb_build_object(
                   'campo', coalesce(cf.name, f->>'id'),
                   'valor', f->>'value') ORDER BY cf.position NULLS LAST), '[]'::jsonb)
            FROM jsonb_array_elements(coalesce(c.custom_fields,'[]'::jsonb)) f
            LEFT JOIN crm_custom_fields cf
              ON cf.ghl_field_id = f->>'id' AND cf.project_id = o.project_id
           WHERE nullif(f->>'value','') IS NOT NULL) AS campos_personalizados,
         to_char(c.created_at,'YYYY-MM-DD')        AS contacto_ingerido,
         -- ¿este contacto tuvo llamadas agendadas?
         (SELECT count(*) FROM meetings m
           WHERE m.meeting_type='call'
             AND m.event->'booking'->>'contact_id' = c.ghl_contact_id) AS llamadas,
         -- ¿tiene otras oportunidades, quizá sí asignadas?
         (SELECT count(*) FROM crm_opportunities o2
           WHERE o2.contact_id = c.id AND o2.id <> o.id) AS otras_opps
  FROM crm_opportunities o
  JOIN projects pr         ON pr.id = o.project_id
  LEFT JOIN crm_contacts c ON c.id  = o.contact_id
  LEFT JOIN crm_pipelines pl ON pl.id = o.pipeline_id
  LEFT JOIN users u        ON u.id  = o.user_id
  LEFT JOIN persons pe     ON pe.person_id = u.person_id
  LEFT JOIN LATERAL (
    SELECT s->>'name' AS name FROM jsonb_array_elements(pl.stages) s
    WHERE s->>'id' = o.ghl_stage_id LIMIT 1) st ON true
  WHERE o.id::text LIKE '${esc}%'
  LIMIT 1) q;"

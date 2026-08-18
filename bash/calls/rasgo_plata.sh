#!/usr/bin/env bash
# rasgo_plata.sh — ¿el RASGO del lead (arquetipo del reporte) convierte a PLATA?
#
# Verifica contra dinero real el hallazgo que antes solo existía contra
# `callStatus`: qué rasgos de arquetipo separan la conversión. Dos decisiones
# metodológicas que son el punto del script:
#
#   1. PRESENCIA del rasgo, no combos. Los combos («Emocional + Novato») parten
#      la muestra en celdas de n chico; aquí cada rasgo se mide con-vs-sin.
#      El rasgo sale de la normalización canónica de lead_profile.sh (43
#      etiquetas libres → 4 rasgos): el test-retest mostró que el rasgo
#      PRIMARIO es reproducible; la etiqueta fina no.
#   2. La conversión es la de conversion_real.sh, no callStatus: plan de pago
#      con ≥1 cuota Paid, creado entre la llamada y +30 días (ventana), plan
#      atribuido solo a la llamada más cercana que lo precede (atribución
#      única).
#
# `--control` responde el confound obvio («Emocional convierte más solo porque
# trae BANT más alto»): parte el universo por tramo BANT y compara Emocional
# vs no-Emocional dentro del tramo 81-100, donde el BANT promedio de ambos
# grupos es ~idéntico. Si la diferencia persiste ahí, el rasgo aporta señal
# encima del puntaje.
#
# Universo: llamadas analizadas con BANT real (score>0; los ceros-literales
# son llamadas sin transcript utilizable, no leads malos). ⚠️ Las tasas son
# por LLAMADA ANALIZADA — un universo ya filtrado y sesgado hacia arriba:
# sirven para compararse entre sí, no como tasas absolutas del embudo.
# Verificado 2026-08-11: Emocional 53.8% vs 31.1% (Fisher p=0.006); en el
# tramo 81-100 (BANT prom 87.9 vs 87.5): 71.9% vs 45.5%.
#
# Read-only. Uso: rasgo_plata.sh [--control] [--dias N] [--project N] [--json]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../lib/common.sh"

modo="rasgos" dias=30 proyecto=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --control) modo="control"; shift ;;
    --dias) dias="$2"; shift 2 ;;
    --project) proyecto="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "flag desconocido: $1 (ver -h)" >&2; exit 2 ;;
  esac
done

w_proj="true"
if [[ -n "$proyecto" ]]; then
  pid="$(resolve_project "$proyecto")"
  [[ -z "$pid" ]] && { echo "No project matches: $proyecto" >&2; exit 1; }
  w_proj="m.project_id = '$pid'"
fi

base="
WITH b AS (
  SELECT m.id, m.event->'booking'->>'contact_id' AS contact_id,
         (coalesce(m.actual_start_time, m.scheduled_start_time) AT TIME ZONE 'America/Bogota')::date AS fecha,
         initcap(trim(regexp_replace(lower(coalesce(
           r.report->'leadProfile'->'intelligentSegmentation'->'archetype'->>'name','')),'\s+',' ','g'))) AS arq,
         ( coalesce(nullif(regexp_replace(coalesce(r.report->'leadProfile'->'bantAnalysis'->'need'->>'score',''),'[^0-9]','','g'),'')::numeric,0)
         + coalesce(nullif(regexp_replace(coalesce(r.report->'leadProfile'->'bantAnalysis'->'budget'->>'score',''),'[^0-9]','','g'),'')::numeric,0)
         + coalesce(nullif(regexp_replace(coalesce(r.report->'leadProfile'->'bantAnalysis'->'timeline'->>'score',''),'[^0-9]','','g'),'')::numeric,0)
         + coalesce(nullif(regexp_replace(coalesce(r.report->'leadProfile'->'bantAnalysis'->'authority'->>'score',''),'[^0-9]','','g'),'')::numeric,0) )/4.0 AS score
  FROM meetings m JOIN call_reports_gemini r ON r.meeting_id = m.id
  WHERE m.meeting_type='call' AND $w_proj
), planes AS (
  SELECT DISTINCT ON (p.plan_id) p.plan_id, b.id AS meeting_id
  FROM payment_plans p
  JOIN b ON b.contact_id = p.customer_id
        AND p.created_at::date BETWEEN b.fecha AND b.fecha + ${dias}
  ORDER BY p.plan_id, b.fecha DESC
), v AS (
  SELECT b.*,
         EXISTS (SELECT 1 FROM planes pl JOIN installments i
                 ON i.plan_id = pl.plan_id AND i.status='Paid'
                 WHERE pl.meeting_id = b.id) AS pago,
         b.arq ~* 'emotional' AS emocional,
         b.arq ~* 'novice' AS novato,
         b.arq ~* 'inexperienced' AS inexperto,
         b.arq ~* '(^|[^n])experienced|professional|scaling' AS experimentado
  FROM b WHERE b.score > 0
)"

if [[ "$modo" == "control" ]]; then
  sql="$base
SELECT CASE WHEN score>=81 THEN '81-100' ELSE '<=80' END AS tramo,
       CASE WHEN emocional THEN 'Emocional' ELSE 'no emocional' END AS grupo,
       count(*) AS llamadas, count(*) FILTER (WHERE pago) AS pagaron,
       round(100.0*count(*) FILTER (WHERE pago)/count(*),1) AS conv_pct,
       round(avg(score),1) AS bant_prom
FROM v GROUP BY 1,2 ORDER BY 1 DESC,2"
else
  sql="$base
SELECT rasgo,
       con_n AS con_rasgo, con_plata AS pagaron,
       round(100.0*con_plata/nullif(con_n,0),1) AS conv_pct,
       sin_n AS sin_rasgo, sin_plata AS sin_pagaron,
       round(100.0*sin_plata/nullif(sin_n,0),1) AS sin_conv_pct
FROM (
  SELECT 'Emocional' AS rasgo,
    count(*) FILTER (WHERE emocional) AS con_n, count(*) FILTER (WHERE emocional AND pago) AS con_plata,
    count(*) FILTER (WHERE NOT emocional) AS sin_n, count(*) FILTER (WHERE NOT emocional AND pago) AS sin_plata FROM v
  UNION ALL SELECT 'Novato',
    count(*) FILTER (WHERE novato), count(*) FILTER (WHERE novato AND pago),
    count(*) FILTER (WHERE NOT novato), count(*) FILTER (WHERE NOT novato AND pago) FROM v
  UNION ALL SELECT 'Inexperto',
    count(*) FILTER (WHERE inexperto), count(*) FILTER (WHERE inexperto AND pago),
    count(*) FILTER (WHERE NOT inexperto), count(*) FILTER (WHERE NOT inexperto AND pago) FROM v
  UNION ALL SELECT 'Experimentado',
    count(*) FILTER (WHERE experimentado), count(*) FILTER (WHERE experimentado AND pago),
    count(*) FILTER (WHERE NOT experimentado), count(*) FILTER (WHERE NOT experimentado AND pago) FROM v
) t"
fi

emit "$sql"

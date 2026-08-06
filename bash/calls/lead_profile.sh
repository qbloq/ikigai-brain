#!/usr/bin/env bash
# lead_profile.sh — el PERFIL DEL LEAD que ya vive dentro de cada reporte de
# llamada, extraído, normalizado y agregable. Resuelve tres tareas que en
# realidad son una sola pieza de trabajo:
#
#   a869c57a  mapear los perfiles de lead y estandarizar los subgrupos
#   d98fef30  criterios BANT de calificación (1-5 por ítem, promedio)
#   767605d8  lead score interno 0-100 para priorizar
#
# Nada de esto hay que inventarlo: el analizador de llamadas ya escribe
# `leadProfile.bantAnalysis` (4 scores 0-100) y
# `leadProfile.intelligentSegmentation` (arquetipo + prioridad) en cada
# reporte. Lo que faltaba era normalizarlo y poder contarlo.
#
# TRES NORMALIZACIONES, todas declaradas aquí y por tanto auditables:
#
#   1. SIN ANALIZAR ≠ MAL CALIFICADO. 66 de 230 reportes traen los cuatro
#      scores BANT en cero literal — son llamadas sin transcript utilizable,
#      no leads malos. Se EXCLUYEN por defecto; cualquier promedio que las
#      incluya subestima todo. `--incluir-sin-analizar` las trae de vuelta.
#
#   2. ARQUETIPO CANÓNICO. El analizador escribe texto libre, así que
#      "Novice Trader", "novice trader" y "Novice trader" son tres etiquetas
#      para un arquetipo. Se bajan a minúscula, se colapsan los espacios y se
#      unifican los separadores (/, -, |) — los compuestos ("Novice Trader /
#      Emotional Trader") se respetan como categoría propia, porque el lead
#      que cae en dos sí es distinto del que cae en uno.
#
#   3. RESULTADO CANÓNICO. `callStatus` es texto libre: 131 valores distintos
#      para 230 llamadas. `call_stats.sh` cuenta ganadas con ILIKE
#      'closed won%' y por eso se le escapan "Closed/Won", "Closed - Payment
#      Initiated" y "Cerrado Pendiente Pago". Aquí se clasifica en 7 baldes
#      por señal más fuerte primero (dinero > seguimiento > descarte). Es una
#      heurística, no una verdad: la verdad del dinero está en `installments`.
#
# Uso:
#   lead_profile.sh [--by base|arquetipo|tramo|prioridad|closer|resultado]
#                   [--project NAME] [--closer NAME] [--arquetipo FRAG]
#                   [--from YYYY-MM-DD] [--to YYYY-MM-DD]
#                   [--incluir-sin-analizar] [--limit N] [--json]
#
#   sin --by        una fila por llamada analizada: el BANT en 0-100 y en la
#                   escala 1-5 por ítem (n/b/t/a), arquetipo, prioridad
#   --by tramo      distribución del score BANT por tramo vs resultado
#                   — la validación de que el score sirve para priorizar
#   --by base       LOS CUATRO RASGOS: Novato · Emocional · Inexperto ·
#                   Experimentado, y sus combinaciones. Es el mapa de
#                   subgrupos utilizable (43 etiquetas → 10 filas)
#   --by arquetipo  el detalle con calificativo, sin colapsar a rasgo base
#   --limit N       tope de filas (default 40 en detalle; 0 = sin tope)
# Read-only.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

by="" project="" closer="" arq="" from="" to="" ceros="" limit=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --by)         by="$2"; shift 2 ;;
    --project)    project="$2"; shift 2 ;;
    --closer)     closer="$2"; shift 2 ;;
    --arquetipo)  arq="$2"; shift 2 ;;
    --from)       from="$2"; shift 2 ;;
    --to)         to="$2"; shift 2 ;;
    --incluir-sin-analizar) ceros=1; shift ;;
    --limit)      limit="$2"; shift 2 ;;
    --json)       FORMAT=json; shift ;;
    -h|--help)    sed -n '2,51p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

esc() { printf '%s' "${1//\'/\'\'}"; }

# --- El CTE base: un reporte de llamada convertido en perfil de lead --------
# `bant` y `seg` se traen por LATERAL para no repetir la ruta del jsonb en
# cada columna. Los scores se castean con nullif+regexp: el analizador a veces
# escribe el score como string y a veces mete texto donde va un número.
#
# OJO al editar: esto es una cadena de bash entre comillas dobles, así que
# aquí adentro no puede aparecer ni una comilla doble (cierra la cadena) ni un
# backtick (lo ejecuta como comando) — ni siquiera dentro de un comentario SQL,
# que bash no distingue del resto. Para citar, «comillas angulares».

BASE="
WITH b AS (
  SELECT m.id,
         m.scheduled_start_time                       AS ts,
         m.project_id,
         coalesce(pr.name,'—')                        AS proyecto,
         coalesce(r.report->'generalInformation'->>'leadName',
                  split_part(m.name,' - ',1))         AS lead,
         coalesce(r.report->'generalInformation'->>'callStatus','') AS st,
         cl.closer,
         seg->'archetype'->>'name'                    AS arq_crudo,
         seg->'priorityClassification'->>'priority'   AS prioridad,
         nullif(regexp_replace(coalesce(seg->>'buyerPersonaMatch',''),'[^0-9]','','g'),'')::numeric AS match_persona,
         nullif(regexp_replace(coalesce(bant->'need'->>'score',''),'[^0-9]','','g'),'')::numeric      AS need,
         nullif(regexp_replace(coalesce(bant->'budget'->>'score',''),'[^0-9]','','g'),'')::numeric    AS budget,
         nullif(regexp_replace(coalesce(bant->'timeline'->>'score',''),'[^0-9]','','g'),'')::numeric  AS timeline,
         nullif(regexp_replace(coalesce(bant->'authority'->>'score',''),'[^0-9]','','g'),'')::numeric AS authority
  FROM meetings m
  JOIN meeting_reports r ON r.meeting_id = m.id
  LEFT JOIN projects pr  ON pr.id = m.project_id
  LEFT JOIN LATERAL (SELECT r.report->'leadProfile'->'bantAnalysis' AS bant,
                            r.report->'leadProfile'->'intelligentSegmentation' AS seg) j ON true
  LEFT JOIN LATERAL (
    SELECT trim(regexp_replace(p.name||' '||coalesce(p.lastname,''),'\\s+',' ','g')) AS closer
    FROM crm_contacts c
    JOIN crm_opportunities o ON o.contact_id = c.id
    JOIN users u   ON u.id = o.user_id
    JOIN persons p ON p.person_id = u.person_id
    WHERE c.ghl_contact_id = m.event->'booking'->>'contact_id'
    ORDER BY (o.project_id = m.project_id) DESC, o.created_date DESC NULLS LAST
    LIMIT 1) cl ON true
  WHERE m.meeting_type = 'call'
),
p AS (
  SELECT b.*,
         (coalesce(need,0)+coalesce(budget,0)+coalesce(timeline,0)+coalesce(authority,0))/4.0 AS score,
         -- Normalización 1: sin analizar ≠ mal calificado.
         (coalesce(need,0)+coalesce(budget,0)+coalesce(timeline,0)+coalesce(authority,0)) = 0 AS sin_analizar,
         -- Normalización 2: el arquetipo canónico.
         coalesce(nullif(initcap(trim(regexp_replace(
             regexp_replace(lower(coalesce(arq_crudo,'')), '\\s*[/|]\\s*|\\s+-\\s+', ' / ', 'g'),
             '\\s+', ' ', 'g'))), ''), '(sin determinar)') AS arquetipo_raw,
         -- Normalización 3: el resultado canónico, señal más fuerte primero.
         CASE
           WHEN st ~* '^closed( |-|/|\\()|^closed\$'                       THEN 'ganada'
           WHEN st ~* '(committ|compromiso|deposit (paid|made|secured)|partial (payment|close)|pre-closed|payment plan initiated|initiated purchase|^reserved|^cerrado)' THEN 'compromiso'
           WHEN st ~* '(follow-?up|seguimiento|pending|decision)'          THEN 'seguimiento'
           WHEN st ~* 'unqualified'                                        THEN 'no calificado'
           WHEN st ~* 'no ?show'                                           THEN 'no asistió'
           WHEN st ~* '(no data|no utterance|no transcri|transcription|unanalyz|incomplete|undetermined|analysis impossible|no content|technical (issue|error)|unable to determine|interrupted)' THEN 'sin data'
           ELSE 'otro'
         END AS resultado
  FROM b
),
q AS (
  SELECT p.*,
         CASE WHEN arquetipo_raw ~* '^(n / a|na|undetermined|unknown|sin determinar)\$'
              THEN '(sin determinar)' ELSE arquetipo_raw END AS arquetipo
  FROM p
),
lp AS (
  -- Segundo nivel de normalización: el ARQUETIPO BASE. Aun canonizado, el
  -- analizador produce 43 etiquetas porque le cuelga calificativos al
  -- arquetipo: «Novice Trader (Struggling For Consistency)», «Emotional
  -- Trader With Trauma». Debajo de esa cola hay solo cuatro rasgos, y un
  -- lead puede tener varios — de ahí el '+' en vez de una categoría plana.
  -- El calificativo NO se tira: sigue en «arquetipo», que es donde vive el
  -- matiz que el closer usa en la llamada.
  -- Ojo con 'inexperienced': contiene 'experienced', así que el rasgo
  -- Experimentado exige que no venga precedido de 'n'.
  SELECT q.*,
         coalesce(nullif(concat_ws(' + ',
           CASE WHEN arquetipo ~* 'emotional'          THEN 'Emocional' END,
           CASE WHEN arquetipo ~* 'novice'             THEN 'Novato' END,
           CASE WHEN arquetipo ~* 'inexperienced'      THEN 'Inexperto' END,
           CASE WHEN arquetipo ~* '(^|[^n])experienced' THEN 'Experimentado' END
         ), ''), '(sin determinar)') AS base
  FROM q
)
"

where="true"
[[ -z "$ceros" ]]     && where="$where AND NOT sin_analizar"
[[ -n "$closer" ]]    && where="$where AND closer ILIKE '%$(esc "$closer")%'"
[[ -n "$arq" ]]       && where="$where AND arquetipo ILIKE '%$(esc "$arq")%'"
[[ -n "$from" ]]      && where="$where AND ts::date >= '${from//\'/}'"
[[ -n "$to" ]]        && where="$where AND ts::date <= '${to//\'/}'"
if [[ -n "$project" ]]; then
  pid="$(resolve_project "$project")"
  [[ -z "$pid" ]] && { echo "No project matches: $project" >&2; exit 1; }
  where="$where AND project_id = '$pid'"
fi

# `ganada` y `compromiso` se suman como conversión: en este negocio el cierre
# real se sella con la primera cuota, que puede caer días después de la
# llamada. Contar solo `ganada` subestima al closer; contar `seguimiento`
# como conversión lo inflaría.
CONV="count(*) FILTER (WHERE resultado IN ('ganada','compromiso'))"

case "$by" in
  "")
    [[ -z "$limit" ]] && limit=40
    [[ "$limit" == "0" ]] && limit=""
    lim=""; [[ -n "$limit" ]] && lim="LIMIT $limit"
    emit "$BASE
      SELECT left(id::text,8) AS id,
             to_char(ts,'YYYY-MM-DD') AS fecha,
             lead, coalesce(closer,'—') AS closer,
             arquetipo,
             round(score)::int AS bant,
             greatest(1, ceil(coalesce(need,0)/20.0))::int      AS n,
             greatest(1, ceil(coalesce(budget,0)/20.0))::int    AS b,
             greatest(1, ceil(coalesce(timeline,0)/20.0))::int  AS t,
             greatest(1, ceil(coalesce(authority,0)/20.0))::int AS a,
             coalesce(prioridad,'—') AS prioridad,
             resultado
      FROM lp WHERE $where
      ORDER BY score DESC, ts DESC
      $lim" ;;
  tramo)
    emit "$BASE
      SELECT CASE WHEN score >= 81 THEN '81-100'
                  WHEN score >= 61 THEN '61-80'
                  WHEN score >= 41 THEN '41-60'
                  WHEN score >= 21 THEN '21-40'
                  ELSE '0-20' END AS bant,
             count(*) AS llamadas,
             $CONV AS convirtio,
             round(100.0 * $CONV / count(*), 1) AS conv_pct,
             count(*) FILTER (WHERE resultado='ganada')      AS ganadas,
             count(*) FILTER (WHERE resultado='seguimiento') AS seguimiento,
             round(avg(match_persona)) AS match_persona
      FROM lp WHERE $where
      GROUP BY 1 ORDER BY 1 DESC" ;;
  base|arquetipo|prioridad|closer|resultado)
    case "$by" in
      base)      dim="base" ;;
      arquetipo) dim="arquetipo" ;;
      prioridad) dim="coalesce(prioridad,'—')" ;;
      closer)    dim="coalesce(closer,'(sin resolver)')" ;;
      resultado) dim="resultado" ;;
    esac
    [[ "$limit" == "0" || -z "$limit" ]] && lim="" || lim="LIMIT $limit"
    emit "$BASE
      SELECT $dim AS $by,
             count(*) AS llamadas,
             round(avg(score))::int AS bant_prom,
             $CONV AS convirtio,
             round(100.0 * $CONV / count(*), 1) AS conv_pct,
             round(avg(match_persona)) AS match_persona
      FROM lp WHERE $where
      GROUP BY 1 ORDER BY 2 DESC
      $lim" ;;
  *) echo "--by inválido: '$by' (base|arquetipo|tramo|prioridad|closer|resultado)" >&2; exit 2 ;;
esac

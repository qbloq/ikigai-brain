#!/usr/bin/env bash
# facets.sh — el universo de valores por los que se puede filtrar `leads.sh`:
# dueños y etapas, cada uno con cuántos leads tiene.
#
# Existe porque las opciones de un filtro NO pueden salir de las filas ya
# filtradas: al elegir un dueño desaparecerían las etapas sin resultados y el
# select se iría cerrando sobre sí mismo. Esto es data de referencia — cambia
# cuando cambia el equipo o el tablero, no con cada consulta — así que la fuente
# del viz la sirve cacheada.
#
# Emite filas planas `{tipo, valor, n}` con tipo ∈ {dueno, etapa} para que un
# solo shell-out pueble los dos controles.
#
# Uso: facets.sh [--project N] [--from D] [--json]
# Read-only.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

PROJECT="" FROM=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:?}"; shift 2 ;;
    --from) FROM="${2:?}"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

esc() { printf '%s' "${1//\'/\'\'}"; }
where="true"
[[ -n "$PROJECT" ]] && where="$where AND pr.name ILIKE '%$(esc "$PROJECT")%'"
[[ -n "$FROM"    ]] && where="$where AND o.created_date >= '$(esc "$FROM")'"

emit "
WITH base AS (
  SELECT o.*, pr.name AS proyecto,
         coalesce(nullif(trim(coalesce(pe.name,'')||' '||coalesce(pe.lastname,'')),''),'sin-dueno') AS dueno,
         st.name AS etapa
  FROM crm_opportunities o
  JOIN projects pr ON pr.id = o.project_id
  LEFT JOIN users u    ON u.id = o.user_id
  LEFT JOIN persons pe ON pe.person_id = u.person_id
  LEFT JOIN crm_pipelines pl ON pl.id = o.pipeline_id
  LEFT JOIN LATERAL (
    SELECT s->>'name' AS name, (s->>'position')::int AS pos
    FROM jsonb_array_elements(pl.stages) s
    WHERE s->>'id' = o.ghl_stage_id LIMIT 1) st ON true
  WHERE $where
)
SELECT 'dueno' AS tipo, dueno AS valor, count(*) AS n, row_number() OVER (ORDER BY count(*) DESC) AS orden
FROM base GROUP BY 1,2
UNION ALL
-- Las etapas salen en el orden del tablero, no por volumen: así el filtro se
-- lee como el pipeline (NUEVO LEAD → … → GANADA) y no como un ranking.
SELECT 'etapa', coalesce(etapa,'—'), count(*),
       coalesce(min((SELECT (s->>'position')::int FROM crm_pipelines pl2,
                     jsonb_array_elements(pl2.stages) s
                     WHERE s->>'name' = base.etapa LIMIT 1)), 99)
FROM base GROUP BY 2
ORDER BY 1, 4"

#!/usr/bin/env bash
# sin_dueno.sh — oportunidades del CRM que NADIE tomó, con su contacto al lado.
#
# `crm_opportunities.user_id` sale de `assigned_to` (el id del usuario en GHL).
# Cuando GHL no trae dueño, la oportunidad queda huérfana: existe, tiene lead y
# etapa, y no hay closer responsable. En julio de 2026 eso fue el 43% del mes
# (237 de 552), verificado contra la fuente — no es un fallo de mapeo nuestro:
# de esas 237, CERO traían `assigned_to` en GHL (`bash/ghl/`).
#
# Este script las lista con el contacto pegado (nombre, email, teléfono, tags),
# que es lo que hace falta para poder repartirlas o rastrear por dónde entraron.
#
# Read-only. Ver también: pipeline.sh (el tablero), bash/ghl/gap.sh (la fuente).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

usage() {
  sed -n '2,14p' "$0"
  cat <<'EOF'

Uso: sin_dueno.sh [--project N] [--status S] [--stage FRAG] [--from D] [--to D]
                  [--con-contacto] [--sin-contacto] [--limit N] [--json]

  --project N      proyecto (fragmento del nombre)
  --status S       open | won | lost | abandoned
  --stage FRAG     fragmento del nombre de la etapa
  --from / --to    ventana sobre created_date (la fecha real de GHL)
  --con-contacto   solo las que tienen contacto espejado
  --sin-contacto   solo las que NO lo tienen (el contacto nunca se ingirió)
  --limit N        default 200; 0 = sin tope
EOF
}

PROJECT="" STATUS="" STAGE="" FROM="" TO="" LIMIT=200 CONTACT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:?}"; shift 2 ;;
    --status) STATUS="${2:?}"; shift 2 ;;
    --stage) STAGE="${2:?}"; shift 2 ;;
    --from) FROM="${2:?}"; shift 2 ;;
    --to) TO="${2:?}"; shift 2 ;;
    --con-contacto) CONTACT="si"; shift ;;
    --sin-contacto) CONTACT="no"; shift ;;
    --limit) LIMIT="${2:?}"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

esc() { printf '%s' "${1//\'/\'\'}"; }
where="o.user_id IS NULL"
[[ -n "$PROJECT" ]] && where="$where AND pr.name ILIKE '%$(esc "$PROJECT")%'"
[[ -n "$STATUS"  ]] && where="$where AND o.status = '$(esc "$STATUS")'"
[[ -n "$FROM"    ]] && where="$where AND o.created_date >= '$(esc "$FROM")'"
[[ -n "$TO"      ]] && where="$where AND o.created_date < ('$(esc "$TO")'::date + 1)"
[[ "$CONTACT" == "si" ]] && where="$where AND c.id IS NOT NULL"
[[ "$CONTACT" == "no" ]] && where="$where AND c.id IS NULL"
[[ -n "$STAGE"   ]] && where="$where AND st.name ILIKE '%$(esc "$STAGE")%'"

lim=""; [[ "$LIMIT" != "0" ]] && lim="LIMIT $((LIMIT))"

emit "
SELECT left(o.id::text,8)                                   AS id,
       o.name                                               AS lead,
       coalesce(st.name,'—')                                AS etapa,
       o.status                                             AS estado,
       to_char(o.created_date,'YYYY-MM-DD')                 AS creada,
       (CURRENT_DATE - o.created_date::date)                AS dias,
       coalesce(nullif(trim(coalesce(c.first_name,'')||' '||coalesce(c.last_name,'')),''),'—') AS contacto,
       coalesce(c.email,'—')                                AS email,
       coalesce(c.phone,'—')                                AS telefono,
       coalesce(array_to_string(c.tags,', '),'—')           AS tags,
       pr.name                                              AS proyecto
FROM crm_opportunities o
JOIN projects pr        ON pr.id = o.project_id
LEFT JOIN crm_contacts c ON c.id = o.contact_id
LEFT JOIN crm_pipelines pl ON pl.id = o.pipeline_id
LEFT JOIN LATERAL (
  SELECT s->>'name' AS name FROM jsonb_array_elements(pl.stages) s
  WHERE s->>'id' = o.ghl_stage_id LIMIT 1) st ON true
WHERE $where
ORDER BY o.created_date DESC NULLS LAST
$lim"

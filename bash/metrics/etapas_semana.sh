#!/usr/bin/env bash
# etapas_semana.sh — EL REPORTE SEMANAL POR ETAPA del embudo orgánico: una fila
# por semana (lunes) con los leads orgánicos que entraron esa semana y cuántos
# de ellos llevan cada etiqueta de etapa en el CRM. Entregable de la tarea
# 3f8f9914 (criterios «conteo por etapa y por semana» y «reproducible»).
#
# Por qué se mide en el CRM y no en ManyChat: el API de ManyChat no lista
# suscriptores ni cuenta por etiqueta (bash/manychat/README.md). Lo que sí
# existe es el puente ManyChat → GHL que ya escribe tags en el contacto
# (`modulo3yt`, `leadmagnet1`, `quiz`…), así que la regla es: la etiqueta de
# etapa se pone en ManyChat, viaja al contacto de GHL, y AQUÍ se cuenta.
#
# Reglas heredadas de organico.sh (una sola definición de orgánico y de etapa):
#   · orgánico = lead del CRM sin campaña en la atribución de GHL, sin
#                utm_campaign en el formulario y sin ad_id de Meta
#   · etapas   = tags del contacto: calificado cc · no calificado + descalificado
#                cc · agenda* + llamada agendada pm/confirmada/por confirmar ·
#                no se conectó + no contesta · venta
#   · con_ig   = el contacto trae usuario de Instagram (campos «¿Cuál es tu
#                usuario de Instagram?» / «¿Cuál es tu Instagram?») — la llave
#                para cruzar la conversación de DM con la venta
#   · cobertura = % de la semana con ALGUNA etiqueta de calificación. Manda
#                sobre los conteos: poca cobertura = no se trabajó o se trabajó
#                sin etiquetar, no «canal malo».
#
# Uso: etapas_semana.sh --project NAME [--desde YYYY-MM-DD] [--hasta YYYY-MM-DD]
#                       [--incluir-pauta] [--json]
#   default: desde 2026-07-01 hasta hoy · solo orgánicos (--incluir-pauta suma
#   una columna `pauta` con los leads pagados de la semana, para escala)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
project="" desde="2026-07-01" hasta="" pauta=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) project="$2"; shift 2 ;;
    --desde) desde="$2"; shift 2 ;;
    --hasta) hasta="$2"; shift 2 ;;
    --incluir-pauta) pauta=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$project" ]] || { echo "Falta --project NAME" >&2; exit 2; }
[[ -z "$hasta" ]] && hasta="$(TZ=America/Bogota date +%F)"
for d in "$desde" "$hasta"; do [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "fecha inválida: $d" >&2; exit 2; }; done
pe="${project//\'/\'\'}"
emit "
WITH o AS (
  SELECT date_trunc('week', o.created_date)::date semana, coalesce(c.tags,'{}') tags,
         (ca.id IS NOT NULL OR utm.camp IS NOT NULL OR coalesce(c.attr_ad_id ~ '^[0-9]+\$', false)) pagado,
         EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(c.custom_fields,'[]'::jsonb)) x
                 JOIN crm_custom_fields cf ON cf.ghl_field_id = x->>'id'
                 WHERE cf.name ILIKE '%instagram%' AND coalesce(x->>'value','') <> '') con_ig
  FROM crm_opportunities o
  JOIN crm_contacts c ON c.id = o.contact_id
  JOIN projects p ON p.id = o.project_id
  LEFT JOIN campaigns ca ON ca.id = c.attr_campaign_id
  LEFT JOIN LATERAL (
    SELECT max(nullif(x->>'value','')) camp
    FROM jsonb_array_elements(coalesce(c.custom_fields,'[]'::jsonb)) x
    JOIN crm_custom_fields cf ON cf.ghl_field_id = x->>'id'
    WHERE cf.name = 'utm_campaign') utm ON true
  WHERE p.name ILIKE '${pe}%' AND o.created_date::date BETWEEN '${desde}' AND '${hasta}')
SELECT semana,
  count(*) FILTER (WHERE NOT pagado) leads,
  $([[ $pauta == 1 ]] && echo "count(*) FILTER (WHERE pagado) pauta,")
  count(*) FILTER (WHERE NOT pagado AND con_ig) con_ig,
  round(100.0*count(*) FILTER (WHERE NOT pagado AND con_ig)/nullif(count(*) FILTER (WHERE NOT pagado),0),0) pct_ig,
  count(*) FILTER (WHERE NOT pagado AND tags && ARRAY['calificado cc','no calificado','descalificado cc']) con_etapa,
  round(100.0*count(*) FILTER (WHERE NOT pagado AND tags && ARRAY['calificado cc','no calificado','descalificado cc'])/nullif(count(*) FILTER (WHERE NOT pagado),0),0) cobertura,
  count(*) FILTER (WHERE NOT pagado AND 'calificado cc' = ANY(tags)) calificados,
  count(*) FILTER (WHERE NOT pagado AND tags && ARRAY['no calificado','descalificado cc']) no_calificados,
  count(*) FILTER (WHERE NOT pagado AND EXISTS (SELECT 1 FROM unnest(tags) t WHERE t LIKE 'agenda%' OR t IN ('llamada agendada pm','llamada confirmada','llamada por confirmar'))) agendo,
  count(*) FILTER (WHERE NOT pagado AND tags && ARRAY['no se conectó','no contesta']) no_conecto,
  count(*) FILTER (WHERE NOT pagado AND 'venta' = ANY(tags)) venta
FROM o GROUP BY 1 ORDER BY 1"

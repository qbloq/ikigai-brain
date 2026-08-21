#!/usr/bin/env bash
# leads.sh — los leads del CRM como FILAS, con su dueño, su procedencia y su
# contacto al lado. `pipeline.sh` da el tablero agregado; esto da la lista.
#
# Lo que lo hace distinto de `pipeline.sh --list` es la ATRIBUCIÓN, con dos
# fuentes (desde 2026-08-21, misma regla que embudo.sh/angulos.sh): la NATIVA
# de GHL que Marketico persiste en crm_contacts (attr_campaign_id/attr_ad_id,
# último toque — la que trae el navegador del lead) y, de fallback, el
# utm_source/utm_campaign del formulario (custom_fields contra
# `crm_custom_fields`). Cada fila dice si el lead llegó por pauta, de qué
# campaña y de qué ANUNCIO, o por qué sesión (Social media / Referral / Direct)
# y formulario entró si no hay pauta.
#
# `--dueno sin-dueno` es el caso que le dio origen: `crm_opportunities.user_id`
# sale de `assigned_to` de GHL, y cuando GHL no trae dueño la oportunidad queda
# huérfana — existe, tiene lead y etapa, y ningún closer responsable. En julio
# de 2026 eso fue el 43% del mes (237 de 552), verificado contra la fuente: de
# esas 237, CERO traían `assigned_to` en GHL (`bash/ghl/`).
#
# Read-only. Ver también: pipeline.sh (el tablero), bash/ghl/gap.sh (la fuente).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

usage() {
  sed -n '2,14p' "$0"
  cat <<'EOF'

Uso: leads.sh [--dueno LISTA] [--project N] [--status S] [--stage FRAG]
              [--from D] [--to D] [--pagado|--organico] [--limit N] [--json]

  --dueno LISTA    dueños separados por coma; cada uno es un fragmento del
                   nombre. El token especial `sin-dueno` trae los huérfanos.
                   Ej: --dueno sin-dueno          (los que nadie tomó)
                       --dueno "Carlos,sin-dueno" (los de Carlos + huérfanos)
  --sin-dueno      atajo de --dueno sin-dueno
  --project N      proyecto (fragmento del nombre)
  --status S       open | won | lost | abandoned
  --stage FRAG     fragmento del nombre de la etapa
  --from / --to    ventana sobre created_date (la fecha real de GHL)
  --dias-min N     solo los que llevan N días o más desde que se crearon
                   (los que ya se enfriaron)
  --pagado         solo los atribuidos a una campaña (GHL o utm del form)
  --organico       solo los que NO (orgánico, referral, directo)
  --con-contacto   solo los que tienen contacto espejado
  --sin-contacto   solo los que NO lo tienen (el contacto nunca se ingirió)
  --limit N        default 200; 0 = sin tope
EOF
}

PROJECT="" STATUS="" STAGE="" FROM="" TO="" LIMIT=200 CONTACT="" PAGADO="" DUENO="" DIASMIN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:?}"; shift 2 ;;
    --status) STATUS="${2:?}"; shift 2 ;;
    --stage) STAGE="${2:?}"; shift 2 ;;
    --from) FROM="${2:?}"; shift 2 ;;
    --to) TO="${2:?}"; shift 2 ;;
    --dueno) DUENO="${2:?}"; shift 2 ;;
    --dias-min) DIASMIN="${2:?}"; shift 2 ;;
    --sin-dueno) DUENO="sin-dueno"; shift ;;
    --con-contacto) CONTACT="si"; shift ;;
    --sin-contacto) CONTACT="no"; shift ;;
    --pagado) PAGADO="si"; shift ;;
    --organico) PAGADO="no"; shift ;;
    --limit) LIMIT="${2:?}"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

esc() { printf '%s' "${1//\'/\'\'}"; }
where="true"

# --dueno: una lista OR de fragmentos de nombre, donde `sin-dueno` no es un
# nombre sino la ausencia de uno. Se arma como un solo paréntesis para que
# convivan «los de Carlos» y «los que nadie tomó» en la misma consulta.
if [[ -n "$DUENO" ]]; then
  ors=""
  IFS=',' read -ra parts <<< "$DUENO"
  for raw in "${parts[@]}"; do
    tok="$(printf '%s' "$raw" | sed 's/^ *//; s/ *$//')"
    [[ -z "$tok" ]] && continue
    if [[ "$tok" == "sin-dueno" || "$tok" == "sin dueño" ]]; then
      cond="o.user_id IS NULL"
    else
      cond="trim(coalesce(pe.name,'')||' '||coalesce(pe.lastname,'')) ILIKE '%$(esc "$tok")%'"
    fi
    ors="${ors:+$ors OR }$cond"
  done
  [[ -n "$ors" ]] && where="$where AND ($ors)"
fi
[[ -n "$PROJECT" ]] && where="$where AND pr.name ILIKE '%$(esc "$PROJECT")%'"
[[ -n "$STATUS"  ]] && where="$where AND o.status = '$(esc "$STATUS")'"
[[ -n "$FROM"    ]] && where="$where AND o.created_date >= '$(esc "$FROM")'"
[[ -n "$TO"      ]] && where="$where AND o.created_date < ('$(esc "$TO")'::date + 1)"
[[ "$CONTACT" == "si" ]] && where="$where AND c.id IS NOT NULL"
[[ "$CONTACT" == "no" ]] && where="$where AND c.id IS NULL"
[[ -n "$STAGE"   ]] && where="$where AND st.name ILIKE '%$(esc "$STAGE")%'"
[[ -n "$DIASMIN" ]] && where="$where AND (CURRENT_DATE - o.created_date::date) >= $((DIASMIN))"
[[ "$PAGADO" == "si" ]] && where="$where AND (coalesce(ca.name, caa.name, utm.camp) IS NOT NULL OR c.attr_ad_id ~ '^[0-9]+$')"
[[ "$PAGADO" == "no" ]] && where="$where AND coalesce(ca.name, caa.name, utm.camp) IS NULL AND NOT coalesce(c.attr_ad_id ~ '^[0-9]+$', false)"

lim=""; [[ "$LIMIT" != "0" ]] && lim="LIMIT $((LIMIT))"

emit "
SELECT left(o.id::text,8)                                   AS id,
       o.name                                               AS lead,
       coalesce(st.name,'—')                                AS etapa,
       o.status                                             AS estado,
       to_char(o.created_date,'YYYY-MM-DD')                 AS creada,
       (CURRENT_DATE - o.created_date::date)                AS dias,
       coalesce(nullif(trim(coalesce(pe.name,'')||' '||coalesce(pe.lastname,'')),''),'—') AS dueno,
       coalesce(nullif(trim(coalesce(c.first_name,'')||' '||coalesce(c.last_name,'')),''),'—') AS contacto,
       coalesce(c.email,'—')                                AS email,
       coalesce(c.phone,'—')                                AS telefono,
       coalesce(array_to_string(c.tags,', '),'—')           AS tags,
       -- Atribución: un lead atribuido a una campaña llegó por pauta, o sea
       -- que lo PAGAMOS. Es la diferencia entre un lead sin dueño y plata
       -- quemada, así que viaja como dato (origen + campaña + anuncio), no
       -- como bandera. origen = utm_source del form si lo hay; si no, la
       -- sesión que registró GHL (pauta sin form → 'fb', o Social media /
       -- Referral / Direct traffic para lo no pagado).
       coalesce(utm.src,
                CASE WHEN coalesce(ca.name, caa.name) IS NOT NULL OR c.attr_ad_id ~ '^[0-9]+$' THEN 'fb' END,
                coalesce(c.last_attribution_source, c.attribution_source)->>'sessionSource',
                '—')                                         AS origen,
       coalesce(ca.name, caa.name, utm.camp,
                CASE WHEN c.attr_ad_id ~ '^[0-9]+$' THEN '— pauta sin campaña resuelta (ad fuera de las cuentas mapeadas)' END, '—') AS campana,
       coalesce(ad.name, CASE WHEN c.attr_ad_id ~ '^[0-9]+$' THEN '(ad ' || c.attr_ad_id || ' no mapeado)' END, '—') AS anuncio,
       coalesce(c.ghl_source, '—')                          AS formulario,
       pr.name                                              AS proyecto
FROM crm_opportunities o
JOIN projects pr        ON pr.id = o.project_id
LEFT JOIN crm_contacts c ON c.id = o.contact_id
LEFT JOIN campaigns ca   ON ca.id = c.attr_campaign_id
LEFT JOIN ads ad         ON ad.id = c.attr_ad_id AND c.attr_ad_id ~ '^[0-9]+$'
LEFT JOIN campaigns caa  ON caa.id = ad.campaign_id
LEFT JOIN crm_pipelines pl ON pl.id = o.pipeline_id
LEFT JOIN users u        ON u.id = o.user_id
LEFT JOIN persons pe     ON pe.person_id = u.person_id
LEFT JOIN LATERAL (
  SELECT s->>'name' AS name FROM jsonb_array_elements(pl.stages) s
  WHERE s->>'id' = o.ghl_stage_id LIMIT 1) st ON true
LEFT JOIN LATERAL (
  SELECT max(CASE WHEN cf.name = 'utm_source'   THEN nullif(x->>'value','') END) AS src,
         max(CASE WHEN cf.name = 'utm_campaign' THEN nullif(x->>'value','') END) AS camp
  FROM jsonb_array_elements(coalesce(c.custom_fields,'[]'::jsonb)) x
  JOIN crm_custom_fields cf
    ON cf.ghl_field_id = x->>'id' AND cf.project_id = o.project_id
  WHERE cf.name IN ('utm_source','utm_campaign')) utm ON true
WHERE $where
ORDER BY o.created_date DESC NULLS LAST
$lim"

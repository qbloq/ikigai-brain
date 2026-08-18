#!/usr/bin/env bash
# gap.sh — measure the mirror against the source.
#
# `crm_contacts` / `crm_opportunities` are supposed to be a copy of what lives
# in GHL. Every closer metric in this repo (call_stats.sh, pipeline.sh, the
# whole Director Comercial layer) reads the copy and trusts it. This script is
# the only thing that checks that trust: it asks GHL how many records exist per
# location and puts that next to what we actually hold.
#
# With --ids it goes further and diffs the identifiers themselves, so the
# answer stops being "we are short by N" and becomes a list of what is missing.
# That costs one API page per 100 records, so it is opt-in.
source "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Uso: gap.sh [--project NOMBRE] [--ids] [--json]

Compara el CRM en GHL contra el espejo en la base:

  --project N   solo ese proyecto (fragmento del nombre)
  --ids         además de contar, baja los ids de GHL y lista cuántos faltan
                en la base (recorre toda la paginación — lento)
  --json        salida machine-readable

Solo lee: ni escribe en GHL ni en la base.
EOF
}

PROJECT=""; WITH_IDS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:?}"; shift 2 ;;
    --ids) WITH_IDS=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -n "$PROJECT" ]]; then
  targets="$(ghl_resolve_project "$PROJECT" | while IFS=$'\t' read -r pid name; do
    ghl_projects | awk -F'\t' -v p="$pid" '$1==p'; done)"
else
  targets="$(ghl_projects)"
fi

rows="[]"
while IFS=$'\t' read -r pid name loc status; do
  [[ -z "$pid" ]] && continue
  ghl_load_creds "$pid"

  ghl_ct="$(ghl_api "/contacts/$(ghl_qs locationId "$GHL_LOCATION" limit 1)" \
    | python3 -c 'import json,sys; print((json.load(sys.stdin).get("meta") or {}).get("total",0))')"
  ghl_op="$(ghl_api "/opportunities/search$(ghl_qs location_id "$GHL_LOCATION" limit 1)" \
    | python3 -c 'import json,sys; print((json.load(sys.stdin).get("meta") or {}).get("total",0))')"

  db="$(psql_ro -t -A -F$'\t' -c "
    SELECT (SELECT count(*) FROM crm_contacts      WHERE project_id='${pid}'),
           (SELECT count(*) FROM crm_opportunities WHERE project_id='${pid}');")"
  db_ct="$(cut -f1 <<<"$db")"; db_op="$(cut -f2 <<<"$db")"

  missing_op=""
  if (( WITH_IDS )); then
    echo "· ${name}: recorriendo las ${ghl_op} oportunidades de GHL…" >&2
    ghl_ids="$(mktemp)"; db_ids="$(mktemp)"
    ghl_fetch_all "/opportunities/search" opportunities location_id \
      | python3 -c 'import json,sys; [print(o["id"]) for o in json.load(sys.stdin) if o.get("id")]' >"$ghl_ids"
    psql_ro -t -A -c "SELECT ghl_opportunity_id FROM crm_opportunities WHERE project_id='${pid}';" >"$db_ids"
    missing_op="$(comm -23 <(sort -u "$ghl_ids") <(sort -u "$db_ids") | grep -c . || true)"
    rm -f "$ghl_ids" "$db_ids"
  fi

  rows="$(python3 -c '
import json, sys
rows = json.loads(sys.argv[1])
name, gc, dc, go, do_, miss = sys.argv[2:8]
gc, dc, go, do_ = int(gc), int(dc), int(go), int(do_)
rows.append({
  "proyecto": name,
  "contactos_ghl": gc, "contactos_db": dc,
  "cobertura_contactos": (f"{100*dc/gc:.0f}%" if gc else "—"),
  "opps_ghl": go, "opps_db": do_,
  "cobertura_opps": (f"{100*do_/go:.0f}%" if go else "—"),
  **({"opps_faltantes": miss} if miss else {}),
})
json.dump(rows, sys.stdout)' "$rows" "$name" "$ghl_ct" "$db_ct" "$ghl_op" "$db_op" "$missing_op")"
  unset GHL_TOKEN
done <<<"$targets"

cols='proyecto:proyecto,contactos_ghl:contactos_ghl,contactos_db:contactos_db,cobertura:cobertura_contactos,opps_ghl:opps_ghl,opps_db:opps_db,cobertura_opps:cobertura_opps'
(( WITH_IDS )) && cols="$cols,opps_faltantes:opps_faltantes"
printf '%s' "$rows" | ghl_render "$cols"

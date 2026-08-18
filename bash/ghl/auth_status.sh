#!/usr/bin/env bash
# auth_status.sh — which projects have a GHL integration, and does it answer?
#
# Prints one row per configured project with a LIVE probe against the API:
# whether the token authenticates, and how many contacts/opportunities GHL
# reports for that location. Those totals are the reference the mirror in
# `crm_contacts` / `crm_opportunities` is supposed to match — gap.sh does the
# comparison, this just proves the credentials work.
source "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Uso: auth_status.sh [--json]

Estado de la integración GHL por proyecto, con sonda en vivo:
  proyecto · location · estado guardado · token · contactos y oportunidades en GHL

Solo lee. Los tokens salen de project_crm_configs y nunca se imprimen.
EOF
}

for a in "$@"; do
  case "$a" in
    --json) FORMAT=json ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $a" >&2; exit 2 ;;
  esac
done

rows="[]"
while IFS=$'\t' read -r pid name loc status; do
  [[ -z "$pid" ]] && continue
  ghl_load_creds "$pid" >/dev/null 2>&1 || { auth="sin credenciales"; ct=""; op=""; }
  if [[ -n "${GHL_TOKEN:-}" ]]; then
    if out="$(ghl_api "/contacts/$(ghl_qs locationId "$GHL_LOCATION" limit 1)" 2>/dev/null)"; then
      auth="ok"
      ct="$(python3 -c 'import json,sys; print((json.load(sys.stdin).get("meta") or {}).get("total","?"))' <<<"$out")"
      if out2="$(ghl_api "/opportunities/search$(ghl_qs location_id "$GHL_LOCATION" limit 1)" 2>/dev/null)"; then
        op="$(python3 -c 'import json,sys; print((json.load(sys.stdin).get("meta") or {}).get("total","?"))' <<<"$out2")"
      else
        op="error"
      fi
    else
      auth="FALLA"; ct=""; op=""
    fi
  fi
  rows="$(python3 -c '
import json, sys
rows = json.loads(sys.argv[1])
rows.append(dict(zip(["proyecto","location","estado_db","auth","contactos_ghl","opps_ghl"], sys.argv[2:])))
json.dump(rows, sys.stdout)' "$rows" "$name" "${loc:0:12}…" "$status" "$auth" "$ct" "$op")"
  unset GHL_TOKEN
done < <(ghl_projects)

printf '%s' "$rows" | ghl_render 'proyecto:proyecto,location:location,estado_db:estado_db,auth:auth,contactos_ghl:contactos_ghl,opps_ghl:opps_ghl'

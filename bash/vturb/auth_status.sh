#!/usr/bin/env bash
# auth_status.sh — which projects have a VTurb integration, and does it answer?
#
# One row per configured project with a LIVE probe against the API: whether the
# token authenticates (GET /players/list, the lightest authenticated call) and
# how many players VTurb reports. The DB `estado_db` column is what Marketico
# last recorded; the probe is the truth of right now.
source "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Uso: auth_status.sh [--json]

Estado de la integración VTurb por proyecto, con sonda en vivo:
  proyecto · estado guardado · conectado desde · token · players en VTurb

Solo lee. Los tokens salen de project_vturb_video_configs y nunca se imprimen.
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
while IFS=$'\t' read -r pid name status since; do
  [[ -z "$pid" ]] && continue
  auth="sin credenciales"; players=""
  if vturb_load_creds "$pid" >/dev/null 2>&1; then
    if out="$(vturb_api_get "/players/list" 2>/dev/null)"; then
      auth="ok"
      players="$(python3 -c '
import json, sys
d = json.load(sys.stdin)
rows = d if isinstance(d, list) else (d.get("players") or d.get("videos") or [])
print(len(rows))' <<<"$out")"
    else
      auth="FALLA"
    fi
  fi
  rows="$(python3 -c '
import json, sys
rows = json.loads(sys.argv[1])
rows.append(dict(zip(["proyecto","estado_db","conectado_desde","auth","players_vturb"], sys.argv[2:])))
json.dump(rows, sys.stdout)' "$rows" "$name" "$status" "$since" "$auth" "$players")"
  unset VTURB_TOKEN
done < <(vturb_projects)

printf '%s' "$rows" | vturb_render 'proyecto:proyecto,estado_db:estado_db,conectado_desde:conectado_desde,auth:auth,players_vturb:players_vturb'

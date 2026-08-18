#!/usr/bin/env bash
# contacts.sh — contacts straight from GHL, past the mirror.
#
# The mirror in `crm_contacts` only holds contacts the ingestor happened to
# bring; a call whose booking points at any other contact cannot resolve its
# closer. This is how you look one up by hand — and how you confirm whether a
# missing contact is genuinely absent upstream or just never ingested.
source "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Uso: contacts.sh --project NOMBRE [--query TEXTO] [--limit N] [--id GHL_ID] [--missing] [--json]

  --project N   proyecto (fragmento del nombre) — obligatorio
  --query T     BUSCAR por nombre, email o teléfono (POST /contacts/search).
                Es la vía correcta para «¿existe este contacto?»: una llamada
                en vez de paginar miles. Ignora --missing.
  --limit N     máximo de contactos (default 20; 0 = todos, pagina de a 100)
  --id ID       un contacto puntual por su id de GHL (ignora --limit)
  --missing     solo los que NO están en el espejo (crm_contacts)
  --json        salida machine-readable

Solo lee: --query usa POST porque así expone GHL la búsqueda, pero no crea ni
modifica nada (ver ghl_api_search en lib/common.sh).
EOF
}

PROJECT=""; LIMIT=20; ONE=""; ONLY_MISSING=0; QUERY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:?}"; shift 2 ;;
    --query) QUERY="${2:?}"; shift 2 ;;
    --limit) LIMIT="${2:?}"; shift 2 ;;
    --id) ONE="${2:?}"; shift 2 ;;
    --missing) ONLY_MISSING=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$PROJECT" ]] && { usage >&2; exit 2; }

IFS=$'\t' read -r pid name < <(ghl_resolve_project "$PROJECT")
ghl_load_creds "$pid"

if [[ -n "$ONE" ]]; then
  items="$(ghl_api "/contacts/$ONE" | python3 -c 'import json,sys; d=json.load(sys.stdin); json.dump([d.get("contact") or d], sys.stdout)')"
elif [[ -n "$QUERY" ]]; then
  body="$(python3 -c '
import json, sys
lim = int(sys.argv[3])
json.dump({"locationId": sys.argv[1], "query": sys.argv[2],
           "pageLimit": lim if lim > 0 else 100}, sys.stdout)' \
    "$GHL_LOCATION" "$QUERY" "$LIMIT")"
  items="$(ghl_api_search "/contacts/search" "$body" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if isinstance(d, dict):
    items = d.get("contacts") or []
    if d.get("total") is not None:
        print("total en GHL: %s" % d["total"], file=sys.stderr)
else:
    items = d or []
json.dump(items, sys.stdout)')"
else
  fetch_cap="$LIMIT"
  (( ONLY_MISSING )) && fetch_cap=0
  items="$(ghl_fetch_all "/contacts/" contacts locationId "$fetch_cap")"
  if (( ONLY_MISSING )); then
    have="$(mktemp)"
    psql_ro -t -A -c "SELECT ghl_contact_id FROM crm_contacts WHERE project_id='${pid}';" >"$have"
    items="$(python3 -c '
import json, sys
have = {l.strip() for l in open(sys.argv[1]) if l.strip()}
n = int(sys.argv[2])
out = [c for c in json.load(sys.stdin) if c.get("id") not in have]
json.dump(out[:n] if n > 0 else out, sys.stdout)' "$have" "$LIMIT" <<<"$items")"
    rm -f "$have"
  fi
fi

printf '%s' "$items" | ghl_render 'id:id,nombre:contactName,email:email,telefono:phone,fuente:source,creado:dateAdded'

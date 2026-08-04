#!/usr/bin/env bash
# opportunities.sh — opportunities straight from GHL, past the mirror.
#
# `bash/crm/pipeline.sh` reads the copy in the database; this reads the source.
# Use it when the copy is suspect: to see stages and owners the mirror never
# ingested, or to check whether an opportunity that is missing downstream ever
# existed upstream.
source "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Uso: opportunities.sh --project NOMBRE [--limit N] [--status S] [--missing] [--json]

  --project N   proyecto (fragmento del nombre) — obligatorio
  --limit N     máximo de oportunidades (default 20; 0 = todas, pagina de a 100)
  --status S    filtra por estado: open | won | lost | abandoned
  --missing     solo las que NO están en el espejo (crm_opportunities)
  --json        salida machine-readable

Solo lee.
EOF
}

PROJECT=""; LIMIT=20; STATUS=""; ONLY_MISSING=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:?}"; shift 2 ;;
    --limit) LIMIT="${2:?}"; shift 2 ;;
    --status) STATUS="${2:?}"; shift 2 ;;
    --missing) ONLY_MISSING=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$PROJECT" ]] && { usage >&2; exit 2; }

IFS=$'\t' read -r pid name < <(ghl_resolve_project "$PROJECT")
ghl_load_creds "$pid"

# --missing needs the full set before it can subtract; a plain listing does not.
fetch_cap="$LIMIT"
(( ONLY_MISSING )) && fetch_cap=0

items="$(ghl_fetch_all "/opportunities/search" opportunities location_id "$fetch_cap")"

if (( ONLY_MISSING )); then
  have="$(mktemp)"
  psql_ro -t -A -c "SELECT ghl_opportunity_id FROM crm_opportunities WHERE project_id='${pid}';" >"$have"
  items="$(python3 -c '
import json, sys
have = {l.strip() for l in open(sys.argv[1]) if l.strip()}
n = int(sys.argv[2])
out = [o for o in json.load(sys.stdin) if o.get("id") not in have]
json.dump(out[:n] if n > 0 else out, sys.stdout)' "$have" "$LIMIT" <<<"$items")"
  rm -f "$have"
fi

if [[ -n "$STATUS" ]]; then
  items="$(python3 -c '
import json, sys
s = sys.argv[1].lower()
json.dump([o for o in json.load(sys.stdin) if (o.get("status") or "").lower() == s], sys.stdout)' "$STATUS" <<<"$items")"
fi

printf '%s' "$items" | ghl_render 'id:id,nombre:name,estado:status,valor:monetaryValue,etapa:pipelineStageId,dueño:assignedTo,creada:createdAt'

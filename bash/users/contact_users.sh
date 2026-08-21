#!/usr/bin/env bash
# contact_users.sh — list the users assignable to contacts (GET /api/contacts/users).
source "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<EOF
Usage: contact_users.sh [--json]

List the users the CRM offers as contact owners: {id, full_name}. Read-only.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) FORMAT=json; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
done

read -r -d '' _SHAPE_PY <<'PY' || true
import json, sys
raw = sys.stdin.read()
if not raw.strip(): sys.exit(1)
rows = json.loads(raw) or []
out = [{"id": (r.get("id") or "")[:8], "full_name": (r.get("full_name") or "").strip()}
       for r in rows]
json.dump(out, sys.stdout, ensure_ascii=False)
PY

mkt_data GET /api/contacts/users | python3 -c "$_SHAPE_PY" | render id full_name

#!/usr/bin/env bash
# create_user.sh — WRITE: create a Marketico user (POST /api/users/).
source "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<EOF
Usage: create_user.sh --name N --email E --password P [--lastname L] [--phone T] [--dry-run] [--json]

WRITE — creates one user via POST /api/users/.
  --name / --lastname / --email / --phone / --password   the user's fields
  --dry-run   print the request payload and send NOTHING
  --json      machine-readable output (the API response + the created row)

Prints the payload before sending and the resulting user row after.
EOF
}

NAME="" LASTNAME="" EMAIL="" PHONE="" PASSWORD="" DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --lastname) LASTNAME="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --phone) PHONE="$2"; shift 2 ;;
    --password) PASSWORD="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
done
[[ -z "$NAME" || -z "$EMAIL" || -z "$PASSWORD" ]] && {
  echo "create_user.sh: --name, --email and --password are required" >&2; usage >&2; exit 1; }

read -r -d '' _PAYLOAD_PY <<'PY' || true
import json, sys
name, lastname, email, phone, password = sys.argv[1:6]
body = {"name": name, "email": email, "password": password}
if lastname: body["lastname"] = lastname
if phone: body["phone"] = phone
json.dump(body, sys.stdout, ensure_ascii=False)
PY

PAYLOAD="$(python3 -c "$_PAYLOAD_PY" "$NAME" "$LASTNAME" "$EMAIL" "$PHONE" "$PASSWORD")"

if [[ "$FORMAT" != "json" ]]; then
  echo "== POST /api/users/ payload (password redacted):"
  printf '%s' "$PAYLOAD" | python3 -c 'import json,sys; b=json.load(sys.stdin); b["password"]="***"; print(json.dumps(b, indent=2, ensure_ascii=False))'
fi

if [[ "$DRY" -eq 1 ]]; then
  echo "-- dry-run: nothing sent." >&2
  exit 0
fi

RESP="$(mkt_data POST /api/users/ -d "$PAYLOAD")"

if [[ "$FORMAT" == "json" ]]; then
  printf '%s\n' "$RESP"
else
  echo "== created:"
  mkt_data GET /api/users/ | shape_users | python3 -c '
import json, sys
email = sys.argv[1].lower()
rows = [r for r in (json.load(sys.stdin) or []) if (r.get("email") or "").lower() == email]
json.dump(rows, sys.stdout, ensure_ascii=False)
' "$EMAIL" | render id name lastname email phone disabled created
fi

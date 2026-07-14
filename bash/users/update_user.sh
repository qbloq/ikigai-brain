#!/usr/bin/env bash
# update_user.sh — WRITE: update one Marketico user (PATCH /api/users/{id}).
source "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<EOF
Usage: update_user.sh <id|prefix|name> [--name N] [--lastname L] [--email E]
                      [--phone T] [--disable|--enable] [--dry-run] [--json]

WRITE — updates one user via PATCH /api/users/{id}. The user may be referenced
by full id, id prefix, or a name/email fragment (errors on ambiguity).
  --disable / --enable   toggle the disabled flag
  --dry-run              print before-row + payload and send NOTHING
  --json                 machine-readable output

Prints the user row before and after the change.
EOF
}

[[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]] && { usage; exit 0; }
REF="$1"; shift

NAME="" LASTNAME="" EMAIL="" PHONE="" DISABLED="" DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --lastname) LASTNAME="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --phone) PHONE="$2"; shift 2 ;;
    --disable) DISABLED="true"; shift ;;
    --enable) DISABLED="false"; shift ;;
    --dry-run) DRY=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
done
[[ -z "$NAME$LASTNAME$EMAIL$PHONE$DISABLED" ]] && {
  echo "update_user.sh: nothing to change (pass at least one field flag)" >&2; usage >&2; exit 1; }

ID="$(resolve_user "$REF")"

read -r -d '' _PAYLOAD_PY <<'PY' || true
import json, sys
name, lastname, email, phone, disabled = sys.argv[1:6]
body = {}
if name: body["name"] = name
if lastname: body["lastname"] = lastname
if email: body["email"] = email
if phone: body["phone"] = phone
if disabled: body["disabled"] = (disabled == "true")
json.dump(body, sys.stdout, ensure_ascii=False)
PY

PAYLOAD="$(python3 -c "$_PAYLOAD_PY" "$NAME" "$LASTNAME" "$EMAIL" "$PHONE" "$DISABLED")"

if [[ "$FORMAT" != "json" ]]; then
  echo "== before:"
  user_row "$ID" | python3 -c 'import json,sys; json.dump([json.load(sys.stdin)], sys.stdout)' | shape_users | render id name lastname email phone disabled created
  echo "== PATCH /api/users/$ID payload:"
  printf '%s' "$PAYLOAD" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))'
fi

if [[ "$DRY" -eq 1 ]]; then
  echo "-- dry-run: nothing sent." >&2
  exit 0
fi

RESP="$(mkt_data PATCH "/api/users/$ID" -d "$PAYLOAD")"

if [[ "$FORMAT" == "json" ]]; then
  printf '%s\n' "$RESP"
else
  echo "== after:"
  user_row "$ID" | python3 -c 'import json,sys; json.dump([json.load(sys.stdin)], sys.stdout)' | shape_users | render id name lastname email phone disabled created
fi

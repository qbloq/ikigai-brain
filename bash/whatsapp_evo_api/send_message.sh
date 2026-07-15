#!/bin/bash
# send_message.sh — Send a WhatsApp text message to the closer via Evolution API
# Uses $PHONE_NUMBER (from env or --to flag) as the recipient.
# Run from workspace root (where .env lives).
#
# Required flags:
#   --message   TEXT    message body to send
#
# Optional flags:
#   --to        NUMBER  recipient phone number (e.g. 15551234567); overrides $PHONE_NUMBER
#   --dry-run           print payload without sending

source .env

TO="${PHONE_NUMBER:-}"
MESSAGE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --to)      TO="$2";         shift 2 ;;
    --message) MESSAGE="$2";    shift 2 ;;
    --dry-run) DRY_RUN=true;    shift 1 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$TO" ]]; then
  echo "Error: recipient not set. Pass --to NUMBER or set \$PHONE_NUMBER in .env" >&2
  exit 1
fi

if [[ -z "$MESSAGE" ]]; then
  echo "Error: --message TEXT is required" >&2
  exit 1
fi

PAYLOAD=$(python3 -c "
import json, sys
print(json.dumps({'number': sys.argv[1], 'text': sys.argv[2]}))
" "$TO" "$MESSAGE")

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[dry-run] POST ${EVOLUTION_API_URL}/message/sendText/${EVOLUTION_API_INSTANCE}"
  echo "[dry-run] Payload: $PAYLOAD"
  exit 0
fi

RESPONSE=$(curl -s -X POST \
  "${EVOLUTION_API_URL}/message/sendText/${EVOLUTION_API_INSTANCE}" \
  -H "apikey: ${EVOLUTION_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

echo "$RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    msg_id = (data.get('key') or {}).get('id') or data.get('id') or data.get('messageId')
    status = data.get('status', 'unknown')
    if msg_id:
        print(f'Sent  id={msg_id}  status={status}')
    else:
        print(json.dumps(data, indent=2))
except Exception:
    print(sys.stdin.read())
"

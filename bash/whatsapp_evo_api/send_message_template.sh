#!/bin/bash
# send_message_template.sh — Render a named template with data and send via WhatsApp.
# Delegates rendering to templates/<name>/render.py, then calls send_message.sh.
#
# Usage (run from workspace root):
#   bash bash/whatsapp_evo_api/send_message_template.sh \
#       --template morning_calls \
#       --data "$(bash bash/calls/calls_today.sh)" \
#       [--dry-run]
#
# Flags:
#   --template NAME   Template id — must match a directory under templates/
#   --data TEXT       Raw output from the data source script
#   --dry-run         Print rendered message without sending

source .env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE_NAME=""
DATA=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --template) TEMPLATE_NAME="$2"; shift 2 ;;
    --data)     DATA="$2";          shift 2 ;;
    --dry-run)  DRY_RUN=true;       shift 1 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$TEMPLATE_NAME" ]] && { echo "Error: --template NAME is required" >&2; exit 1; }

TEMPLATE_DIR="$WORKSPACE_ROOT/templates/$TEMPLATE_NAME"
[[ ! -d "$TEMPLATE_DIR" ]]        && { echo "Error: template not found: $TEMPLATE_DIR" >&2; exit 1; }
[[ ! -f "$TEMPLATE_DIR/render.py" ]] && { echo "Error: render.py missing in $TEMPLATE_DIR" >&2; exit 1; }

TMP_DATA=$(mktemp)
printf '%s' "$DATA" > "$TMP_DATA"
trap "rm -f '$TMP_DATA'" EXIT

RENDERED=$(python3 "$TEMPLATE_DIR/render.py" "$TMP_DATA")
rc=$?
[[ $rc -ne 0 || -z "$RENDERED" ]] && { echo "Error: rendering failed" >&2; exit 1; }

if [[ "$DRY_RUN" == "true" ]]; then
    printf '\n[dry-run] Template: %s\n---\n%s\n---\n' "$TEMPLATE_NAME" "$RENDERED"
    exit 0
fi

bash "$SCRIPT_DIR/send_message.sh" --message "$RENDERED"

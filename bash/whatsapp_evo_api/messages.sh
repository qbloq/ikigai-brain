#!/bin/bash
# messages.sh — Fetch WhatsApp messages for the closer from whatsapp_messages table
# Filters by remote_jid = <PHONE_NUMBER>@s.whatsapp.net and project_id.
# Run from workspace root (where .env lives).
#
# Flags:
#   --phone       NUMBER  override $PHONE_NUMBER
#   --limit       N       cap rows (default: 50)
#   --date-after  DATE    timestamp::date >= DATE
#   --date-before DATE    timestamp::date <= DATE
#   --inbound           only messages from the closer (from_me = false)
#   --outbound          only messages sent by the agent (from_me = true)

source .env

PHONE="${PHONE_NUMBER:-}"
LIMIT=50
WHERES="project_id = '${PROJECT_ID}'::uuid"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phone)       PHONE="$2";                                                       shift 2 ;;
    --limit)       LIMIT="$2";                                                       shift 2 ;;
    --date-after)  WHERES="${WHERES} AND timestamp::date >= '${2}'";                 shift 2 ;;
    --date-before) WHERES="${WHERES} AND timestamp::date <= '${2}'";                 shift 2 ;;
    --inbound)     WHERES="${WHERES} AND from_me = false";                           shift 1 ;;
    --outbound)    WHERES="${WHERES} AND from_me = true";                            shift 1 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PHONE" ]]; then
  echo "Error: PHONE_NUMBER not set. Pass --phone NUMBER or set \$PHONE_NUMBER in .env" >&2
  exit 1
fi

REMOTE_JID="${PHONE}@s.whatsapp.net"
WHERES="${WHERES} AND remote_jid = '${REMOTE_JID}'"

psql "$DATABASE_URL" -c "
SELECT to_char(timestamp, 'YYYY-MM-DD HH24:MI') AS at,
       CASE WHEN from_me THEN 'OUT' ELSE 'IN ' END AS dir,
       message_type,
       text
FROM ikigaigm.whatsapp_messages
WHERE ${WHERES}
ORDER BY timestamp DESC
LIMIT ${LIMIT};"

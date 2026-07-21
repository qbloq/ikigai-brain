#!/bin/bash
# last_inbound.sh — Return the latest message AUTHORED BY THE HUMAN (not by Coco)
# in a WhatsApp conversation, read live from the Evolution API (/chat/findMessages).
#
# Why the API and not the DB: ikigaigm.whatsapp_messages is not currently being
# populated (no Evolution webhook), so the Evolution API is the source of truth.
#
# "Authored by the human" = NOT (fromMe AND source == "web"):
#   - Real contact  → their replies are fromMe=false.
#   - Self-test     → messaging the instance's OWN number makes every message
#                     fromMe=true, but Coco's API sends carry source="web" while
#                     messages typed on the phone carry source="ios"/"android".
#                     So we exclude only Coco's own API sends.
#
# --since scopes to messages AFTER a moment (the greeting / the prior capture),
# so a stale older human message is never mistaken for a fresh reply. Without it,
# the latest human message in the whole thread is returned.
#
# Output (stdout): one compact JSON object, or the literal `null`:
#   {"evolution_message_id":"3EB0..","id":"cmq..","text":"Si claro",
#    "timestamp":"2026-06-18T01:10:00Z","from_me":false,"source":"ios"}
#
# Flags:
#   --jid   JID    conversation remoteJid (default: ${PHONE_NUMBER}@s.whatsapp.net)
#   --since TS     only messages strictly after TS (unix epoch seconds, or an ISO
#                  timestamp like 2026-06-18T01:00:00Z)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$WORKSPACE_ROOT"
# shellcheck disable=SC1091
source .env

JID="${PHONE_NUMBER:-}@s.whatsapp.net"
SINCE_EPOCH=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jid)   JID="$2"; shift 2 ;;
    --since)
      if [[ "$2" =~ ^[0-9]+$ ]]; then SINCE_EPOCH="$2"
      else
        # ISO → epoch sin `date -d` (GNU-only); python3 cubre BSD/macOS
        SINCE_EPOCH="$(date -u -d "$2" +%s 2>/dev/null \
          || python3 -c 'import sys,datetime as d
t=d.datetime.fromisoformat(sys.argv[1].replace("Z","+00:00"))
if t.tzinfo is None: t=t.replace(tzinfo=d.timezone.utc)
print(int(t.timestamp()))' "$2" 2>/dev/null || echo 0)"
      fi
      shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done
[[ "$JID" == "@s.whatsapp.net" ]] && { echo "Error: PHONE_NUMBER not set and no --jid given" >&2; exit 1; }

curl -s --max-time 20 -X POST \
  -H "apikey: ${EVOLUTION_API_KEY}" -H "Content-Type: application/json" \
  "${EVOLUTION_API_URL}/chat/findMessages/${EVOLUTION_API_INSTANCE}" \
  -d "{\"where\":{\"key\":{\"remoteJid\":\"${JID}\"}}}" \
| python3 -c '
import sys, json, datetime
since = int(sys.argv[1]) if len(sys.argv) > 1 else 0
raw = sys.stdin.read()
try:
    d = json.loads(raw) if raw.strip() else {}
except Exception:
    print("null"); sys.exit(0)

recs = (d.get("messages") or {}).get("records") or []

def text(m):
    msg = m.get("message") or {}
    return (msg.get("conversation")
            or (msg.get("extendedTextMessage") or {}).get("text")
            or (msg.get("imageMessage") or {}).get("caption")
            or m.get("messageType") or "")

def is_human(m):
    k = m.get("key") or {}
    return not (k.get("fromMe") and m.get("source") == "web")

human = [m for m in recs
         if is_human(m) and (m.get("messageTimestamp") or 0) > since]
if not human:
    print("null"); sys.exit(0)

m = max(human, key=lambda x: x.get("messageTimestamp") or 0)
k = m.get("key") or {}
ts = m.get("messageTimestamp") or 0
print(json.dumps({
    "evolution_message_id": k.get("id"),
    "id": m.get("id"),
    "text": text(m),
    "timestamp": datetime.datetime.fromtimestamp(ts, datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "from_me": bool(k.get("fromMe")),
    "source": m.get("source"),
}, ensure_ascii=False, separators=(",", ":")))
' "$SINCE_EPOCH"

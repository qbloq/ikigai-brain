#!/usr/bin/env bash
# users.sh — list Marketico users (GET /api/users/).
source "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<EOF
Usage: users.sh [--q FRAG] [--disabled|--enabled] [--json]

List Marketico users. Read-only.
  --q FRAG     filter by name/lastname/email fragment (case-insensitive)
  --disabled   only disabled users
  --enabled    only enabled users
  --json       machine-readable output
EOF
}

Q="" STATE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --q) Q="$2"; shift 2 ;;
    --disabled) STATE="true"; shift ;;
    --enabled) STATE="false"; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
done

read -r -d '' _FILTER_PY <<'PY' || true
import json, sys
q = sys.argv[1].lower()
state = sys.argv[2]
raw = sys.stdin.read()
if not raw.strip(): sys.exit(1)
rows = json.loads(raw) or []
if q:
    rows = [r for r in rows
            if q in ("%s %s %s" % (r.get("name") or "", r.get("lastname") or "",
                                   r.get("email") or "")).lower()]
if state:
    rows = [r for r in rows if r.get("disabled") is (state == "true")]
json.dump(rows, sys.stdout, ensure_ascii=False)
PY

mkt_data GET /api/users/ | shape_users \
  | python3 -c "$_FILTER_PY" "$Q" "$STATE" \
  | render id name lastname email phone disabled created

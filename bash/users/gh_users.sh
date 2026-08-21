#!/usr/bin/env bash
# gh_users.sh — list GoHighLevel users of one location (GET /api/gh/users).
source "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<EOF
Usage: gh_users.sh --location LOCATION_ID [--json]

List the GoHighLevel (CRM) users of one GHL location. Read-only.
  --location ID   the GHL locationId (required by the API)
  --json          machine-readable output
EOF
}

LOCATION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --location) LOCATION="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
done
[[ -z "$LOCATION" ]] && { echo "gh_users.sh: --location is required" >&2; usage >&2; exit 1; }

mkt_data GET "/api/gh/users?locationId=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$LOCATION")" \
  | render

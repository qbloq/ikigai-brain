#!/usr/bin/env bash
# List Marketico users straight from the `users` table (name/lastname/email
# resolved via persons, phone = users.phone_number — the WhatsApp-linked
# number). Read-only, DB-direct (unlike users.sh, which mirrors the API).
#
# Usage:  usuarios_db.sh [--json]
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

emit "SELECT left(u.id::text,8) AS id,
       trim(coalesce(p.name,'')||' '||coalesce(p.lastname,'')) AS name,
       u.email, u.phone_number AS phone, u.disabled,
       to_char(u.created_at,'YYYY-MM-DD') AS created
FROM users u
LEFT JOIN persons p ON p.person_id=u.person_id
ORDER BY name"

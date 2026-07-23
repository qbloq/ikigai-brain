#!/usr/bin/env bash
# List team members with resolved name, role, team and contact.
# Useful to know the universe of possible task assignees.
#
# Usage:  team.sh [--team NAME] [--json]
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

team="" ; while [[ $# -gt 0 ]]; do
  case "$1" in
    --team) team="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

where="true"
[[ -n "$team" ]] && where="tm_team.name ILIKE '%${team//\'/}%'"

emit "SELECT left(tm.id::text,8) AS member_id,
       trim(coalesce(p.name,'')||' '||coalesce(p.lastname,'')) AS name,
       tr.name AS role, tm_team.name AS team,
       coalesce(u.email, p.email) AS email, tm.whatsapp
FROM team_members tm
LEFT JOIN teams tm_team ON tm_team.id=tm.team_id
LEFT JOIN team_roles tr ON tr.id=tm.role_id
LEFT JOIN users u ON u.id=tm.user_id
LEFT JOIN persons p ON p.person_id=u.person_id
WHERE $where
ORDER BY team, name"

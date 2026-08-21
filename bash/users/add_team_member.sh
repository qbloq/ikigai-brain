#!/usr/bin/env bash
# add_team_member.sh — WRITE: make an app user a member of a team with a role
# (one ikigaigm.team_members row). The Marketico users API stops at the account
# (users/persons); membership is what makes a person an ASSIGNEE — tasks.assignee[]
# holds team_members.id, not users.id — and what bash/lib/acceso.sh, the role
# layers and the WhatsApp onboarding key on. Same WRITE policy as set_ghl.sh:
# psql_rw, one transaction, before/after, --dry-run rolls back.
#
# Usage: add_team_member.sh <id|prefix|name|email> --team T --role R [--whatsapp N] [--dry-run] [--json]
#   --team T      team name (exact, e.g. "Ikigai"; see bash/tasks/team.sh)
#   --role R      role name within that team (exact, e.g. "Líder de servicio");
#                 roles are duplicated per team, so the pair team+role resolves it
#   --whatsapp N  digits with country code, no '+' (optional; what the WhatsApp
#                 escenarios dial — leave it out rather than inventing one)
#
# Refuses if the user is already a member of that team (one row per user×team;
# to change the role, fix it by hand for now — no update path here yet).
source "$(dirname "$0")/lib/common.sh"      # resolve_user (Marketico API)
source "$(dirname "$0")/../lib/common.sh"   # psql_rw / psql_ro (Postgres, ikigaigm)

usage() { sed -n '2,19p' "$0"; }
[[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]] && { usage; exit 0; }
REF="$1"; shift
TEAM="" ROLE="" WA="" DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --team) TEAM="$2"; shift 2 ;;
    --role) ROLE="$2"; shift 2 ;;
    --whatsapp) WA="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
done
[[ -z "$TEAM" || -z "$ROLE" ]] && { echo "add_team_member.sh: --team and --role are required" >&2; usage >&2; exit 1; }
if [[ -n "$WA" && ! "$WA" =~ ^[0-9]{8,15}$ ]]; then
  echo "add_team_member.sh: --whatsapp must be digits only with country code (got '$WA')" >&2; exit 1
fi

UID_="$(resolve_user "$REF")"

# Resolve team + role (exactly one each) and check membership — read-only.
chk="$(psql_ro -t -A -F'|' -v team="$TEAM" -v role="$ROLE" -v uid="$UID_" <<'SQL'
SELECT (SELECT count(*) FROM teams WHERE name = :'team'),
       (SELECT count(*) FROM team_roles tr JOIN teams te ON te.id=tr.team_id WHERE te.name = :'team' AND tr.name = :'role'),
       (SELECT count(*) FROM team_members tm JOIN teams te ON te.id=tm.team_id WHERE te.name = :'team' AND tm.user_id = :'uid'::uuid);
SQL
)"
IFS='|' read -r n_team n_role n_member <<< "$chk"
[[ "$n_team" == "1" ]] || { echo "team '$TEAM' resolved to $n_team rows (need 1) — see bash/tasks/team.sh" >&2; exit 1; }
[[ "$n_role" == "1" ]] || { echo "role '$ROLE' in team '$TEAM' resolved to $n_role rows (need 1)" >&2; exit 1; }
[[ "$n_member" == "0" ]] || { echo "user ${UID_:0:8} is already a member of team '$TEAM' — nothing to add" >&2; exit 1; }

FINISH="COMMIT"; [[ "$DRY" -eq 1 ]] && FINISH="ROLLBACK"
ROW_SQL="SELECT tm.id, te.name AS team, tr.name AS role, tm.whatsapp, u.email
         FROM team_members tm JOIN teams te ON te.id=tm.team_id
         LEFT JOIN team_roles tr ON tr.id=tm.role_id JOIN users u ON u.id=tm.user_id
         WHERE tm.user_id = '$UID_'"

out="$(psql_rw -v team="$TEAM" -v role="$ROLE" -v uid="$UID_" -v wa="$WA" <<SQL
BEGIN;
\echo '==== BEFORE (memberships of the user) ===='
$ROW_SQL;
INSERT INTO team_members (id, team_id, user_id, role_id, whatsapp, created_at, updated_at)
SELECT gen_random_uuid(), te.id, :'uid'::uuid, tr.id, nullif(:'wa',''), now(), now()
FROM teams te JOIN team_roles tr ON tr.team_id=te.id
WHERE te.name = :'team' AND tr.name = :'role';
\echo '==== AFTER ===='
$ROW_SQL;
$FINISH;
SQL
)"
if [[ "$FORMAT" == "json" ]]; then
  psql_ro -t -A -c "SELECT coalesce(json_agg(r),'[]') FROM ($ROW_SQL) r"
else
  printf '%s\n' "$out"
  [[ "$DRY" -eq 1 ]] && echo "-- dry-run: rolled back, nothing written."
fi
exit 0

#!/usr/bin/env bash
# set_ghl.sh — WRITE: bind a user's GoHighLevel identity.
# The Marketico users API does not expose users.integrations / users.crm_id,
# so this script writes them directly (psql_rw) — same WRITE policy as the
# rest of bash/: one transaction, before/after, --dry-run rolls back.
#
# users.integrations (jsonb) = { "<ghl_location_id>": "<ghl_user_id>", ... }
# users.crm_id (text)        = the user's primary GHL user id.
source "$(dirname "$0")/lib/common.sh"      # resolve_user (Marketico API)
source "$(dirname "$0")/../lib/common.sh"   # psql_rw (Postgres, ikigaigm)

usage() {
  cat <<EOF
Usage: set_ghl.sh <id|prefix|name|email> --location LOC --ghl-user GID
                  [--primary] [--remove] [--dry-run] [--json]

WRITE — merges {LOC: GID} into users.integrations for one user.
  --location LOC   GHL location id (e.g. UBREqrQ6n5QEC8lFmyGt — see
                   project_crm_configs.location_id for the known ones)
  --ghl-user GID   the user's GHL user id in that location
  --primary        also set users.crm_id = GID
  --remove         delete the LOC key instead (ignores --ghl-user)
  --dry-run        run the txn and ROLLBACK
  --json           emit the resulting row as JSON

Prints the user's email/crm_id/integrations before and after.
EOF
}

[[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]] && { usage; exit 0; }
REF="$1"; shift

LOC="" GID="" PRIMARY=0 REMOVE=0 DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --location) LOC="$2"; shift 2 ;;
    --ghl-user) GID="$2"; shift 2 ;;
    --primary) PRIMARY=1; shift ;;
    --remove) REMOVE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
done
[[ -z "$LOC" ]] && { echo "set_ghl.sh: --location is required" >&2; usage >&2; exit 1; }
[[ "$REMOVE" -eq 0 && -z "$GID" ]] && { echo "set_ghl.sh: --ghl-user is required (or pass --remove)" >&2; usage >&2; exit 1; }

ID="$(resolve_user "$REF")"
LOC_ESC="${LOC//\'/\'\'}" GID_ESC="${GID//\'/\'\'}"

SET_SQL="integrations = coalesce(integrations, '{}'::jsonb) || jsonb_build_object('$LOC_ESC', '$GID_ESC')"
[[ "$REMOVE" -eq 1 ]] && SET_SQL="integrations = coalesce(integrations, '{}'::jsonb) - '$LOC_ESC'"
[[ "$PRIMARY" -eq 1 ]] && SET_SQL="$SET_SQL, crm_id = '$GID_ESC'"

FINISH="COMMIT"
[[ "$DRY" -eq 1 ]] && FINISH="ROLLBACK"

ROW_SQL="SELECT u.email, u.crm_id, u.integrations FROM ikigaigm.users u WHERE u.id = '$ID'"

if [[ "$FORMAT" == "json" ]]; then
  psql_rw -t -A <<SQL
BEGIN;
UPDATE ikigaigm.users SET $SET_SQL, updated_at = now() WHERE id = '$ID';
SELECT row_to_json(_q) FROM ($ROW_SQL) _q;
$FINISH;
SQL
else
  psql_rw <<SQL
BEGIN;
\\echo == before:
$ROW_SQL;
UPDATE ikigaigm.users SET $SET_SQL, updated_at = now() WHERE id = '$ID';
\\echo == after:
$ROW_SQL;
$FINISH;
SQL
  [[ "$DRY" -eq 1 ]] && echo "-- dry-run: rolled back." >&2
fi

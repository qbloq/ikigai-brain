#!/usr/bin/env bash
# auth_status.sh [--json]
#
# Read-only. Show the Google identity the scripts run as: the identities row
# (email, scopes, expiry) plus a live tokeninfo check against Google.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/common.sh"

for a in "$@"; do
  case "$a" in
    --json) FORMAT=json;;
    -h|--help) sed -n '2,5p' "$0"; exit 0;;
    *) echo "unknown arg: $a" >&2; exit 1;;
  esac
done

row="$(_psql_ro -t -A -F$'\t' -c "
  SELECT email, scope, expiry_date,
         to_char(to_timestamp(expiry_date/1000) AT TIME ZONE 'America/Bogota', 'YYYY-MM-DD HH24:MI') AS expira,
         (to_timestamp(expiry_date/1000) > now()) AS vigente,
         to_char(updated_at AT TIME ZONE 'America/Bogota', 'YYYY-MM-DD HH24:MI') AS actualizado
  FROM ikigaigm.identities
  WHERE provider = '${GOOGLE_IDENTITY_PROVIDER//\'/\'\'}'
  ORDER BY updated_at DESC LIMIT 1;")"
[[ -z "$row" ]] && { echo "no identities row for provider='$GOOGLE_IDENTITY_PROVIDER'" >&2; exit 1; }

live="null"
if google_token 2>/dev/null; then
  live="$(curl -sS --get "https://www.googleapis.com/oauth2/v3/tokeninfo" \
    --data-urlencode "access_token=$GOOGLE_TOKEN" || echo null)"
fi

ROW="$row" LIVE="$live" python3 - "$FORMAT" <<'PY'
import json, os, sys
fmt = sys.argv[1]
email, scope, expiry_ms, expira, vigente, actualizado = os.environ["ROW"].split("\t")
try:
    live = json.loads(os.environ["LIVE"])
except json.JSONDecodeError:
    live = None
info = {
    "provider_email": email,
    "vigente": vigente == "t",
    "expira_bogota": expira,
    "actualizado_bogota": actualizado,
    "scopes": scope.split(),
    "tokeninfo": {"expires_in_s": int(live["expires_in"]), "scopes_ok": True} if live and "expires_in" in live else None,
}
if fmt == "json":
    print(json.dumps(info, indent=2, ensure_ascii=False))
else:
    print(f"cuenta      {email}")
    print(f"vigente     {'sí' if info['vigente'] else 'NO — token vencido'}")
    print(f"expira      {expira} (Bogotá)")
    print(f"actualizado {actualizado} (Bogotá)")
    if info["tokeninfo"]:
        print(f"tokeninfo   OK, expira en {info['tokeninfo']['expires_in_s']}s")
    else:
        print("tokeninfo   sin verificación en vivo (token vencido o sin red)")
    print("scopes:")
    for s in info["scopes"]:
        print(f"  - {s}")
PY

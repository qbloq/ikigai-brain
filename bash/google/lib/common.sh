#!/usr/bin/env bash
# Common helpers for bash/google/ read-only Google API scripts (Drive/Docs/Sheets).
# Source from any script: source "$(dirname "$0")/lib/common.sh"
#
# Read-only: these scripts only ever GET from the Google APIs. They never
# create, update, or delete anything in Drive/Docs/Sheets.
#
# Auth: the OAuth access token lives in ikigaigm.identities (provider='google').
# The backend keeps that row fresh (it refreshes the token when it uses it);
# we have no client_id/client_secret locally, so we cannot refresh it ourselves.
# If the token is expired the scripts fail with a clear message instead.
set -euo pipefail

GOOGLE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GOOGLE_DIR="$(cd "$GOOGLE_LIB_DIR/.." && pwd)"
REPO_ROOT="$(cd "$GOOGLE_DIR/../.." && pwd)"

# --- Load DATABASE_URL from .env (token source is the DB) -------------------
if [[ -z "${DATABASE_URL:-}" && -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi
: "${DATABASE_URL:?DATABASE_URL not set (expected in $REPO_ROOT/.env)}"

FORMAT="${FORMAT:-table}"

# Which identities row to use (there is also a stale 'google1').
GOOGLE_IDENTITY_PROVIDER="${GOOGLE_IDENTITY_PROVIDER:-google}"

_psql_ro() {
  PGOPTIONS="-c default_transaction_read_only=on -c search_path=ikigaigm,public" \
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 --pset pager=off "$@"
}

# The DB round-trip for the token costs ~0.8s, so a fresh token is cached in a
# user-only temp file until 60s before expiry (the viz explorer fires several
# API calls per render). Delete the file to force a re-read from the DB.
GOOGLE_TOKEN_CACHE="${GOOGLE_TOKEN_CACHE:-${TMPDIR:-/tmp}/hermetico-google-token-$(id -u)}"

# google_token : loads GOOGLE_TOKEN / GOOGLE_EMAIL / GOOGLE_EXPIRY from the
# file cache or the identities row, erroring if the token is already expired
# (60s margin).
google_token() {
  [[ -n "${GOOGLE_TOKEN:-}" ]] && return 0
  local now ctok cexp cemail
  now="$(date +%s)"
  if [[ -f "$GOOGLE_TOKEN_CACHE" ]]; then
    IFS=$'\t' read -r ctok cexp cemail < "$GOOGLE_TOKEN_CACHE" || true
    if [[ -n "${ctok:-}" && "${cexp:-0}" =~ ^[0-9]+$ ]] && (( cexp / 1000 > now + 60 )); then
      GOOGLE_TOKEN="$ctok" GOOGLE_EXPIRY="$cexp" GOOGLE_EMAIL="${cemail:-}"
      export GOOGLE_TOKEN GOOGLE_EXPIRY GOOGLE_EMAIL
      return 0
    fi
  fi
  local row
  row="$(_psql_ro -t -A -F$'\t' -c "
    SELECT access_token, expiry_date, email
    FROM ikigaigm.identities
    WHERE provider = '${GOOGLE_IDENTITY_PROVIDER//\'/\'\'}'
    ORDER BY updated_at DESC LIMIT 1;")"
  [[ -z "$row" ]] && { echo "google: no identities row for provider='$GOOGLE_IDENTITY_PROVIDER'" >&2; return 1; }
  GOOGLE_TOKEN="$(cut -f1 <<<"$row")"
  GOOGLE_EXPIRY="$(cut -f2 <<<"$row")"
  GOOGLE_EMAIL="$(cut -f3 <<<"$row")"
  [[ -z "$GOOGLE_TOKEN" ]] && { echo "google: identities row has no access_token" >&2; return 1; }
  if [[ -n "$GOOGLE_EXPIRY" ]] && (( GOOGLE_EXPIRY / 1000 <= now + 60 )); then
    echo "google: token vencido ($(date -d "@$((GOOGLE_EXPIRY / 1000))" '+%Y-%m-%d %H:%M %Z'))." >&2
    echo "El backend lo refresca al usarlo (bot de meetings); reintenta en unos minutos" >&2
    echo "o re-autentica Google en la app. No hay client_secret local para refrescarlo aquí." >&2
    return 1
  fi
  (umask 077; printf '%s\t%s\t%s\n' "$GOOGLE_TOKEN" "$GOOGLE_EXPIRY" "$GOOGLE_EMAIL" > "$GOOGLE_TOKEN_CACHE")
  export GOOGLE_TOKEN GOOGLE_EXPIRY GOOGLE_EMAIL
}

# gapi <METHOD> <url> [curl-args...] : authenticated call, JSON (or bytes) on
# stdout. Non-2xx exits 1 with the API error on stderr.
gapi() {
  local method="$1" url="$2"; shift 2
  google_token
  local tmp code
  tmp="$(mktemp)"
  code="$(curl -sS -X "$method" "$url" \
    -H "Authorization: Bearer ${GOOGLE_TOKEN}" \
    -o "$tmp" -w '%{http_code}' "$@")" || { rm -f "$tmp"; return 1; }
  if [[ "$code" != 2* ]]; then
    echo "google api HTTP $code ($url):" >&2
    head -c 500 "$tmp" >&2; echo >&2
    rm -f "$tmp"
    return 1
  fi
  cat "$tmp"
  rm -f "$tmp"
}

# gid <id-or-url> : extract a Drive file/folder id from a raw id or any
# docs.google.com / drive.google.com URL (/d/<id>, /folders/<id>, ?id=<id>).
gid() {
  local raw="$1" id=""
  id="$(printf '%s' "$raw" | grep -oE '/(d|folders|file/d)/[A-Za-z0-9_-]{10,}' | head -n1 | grep -oE '[A-Za-z0-9_-]{10,}$' || true)"
  [[ -z "$id" ]] && id="$(printf '%s' "$raw" | grep -oE '[?&]id=[A-Za-z0-9_-]{10,}' | head -n1 | sed 's/^.*id=//' || true)"
  if [[ -z "$id" && "$raw" =~ ^[A-Za-z0-9_-]{10,}$ ]]; then id="$raw"; fi
  [[ -z "$id" ]] && { echo "gid: no Google file id found in '$raw'" >&2; return 1; }
  printf '%s\n' "$id"
}

# q_escape <text> : escape single quotes for Drive query strings.
q_escape() { printf '%s' "$1" | sed "s/'/\\\\'/g"; }

# resolve_folder <id|url|name-fragment> : echoes a folder id. Tries id/url
# first; otherwise searches folders by name, erroring on no/ambiguous match.
resolve_folder() {
  local tok="$1" id
  if id="$(gid "$tok" 2>/dev/null)"; then printf '%s\n' "$id"; return 0; fi
  local frag q rows n
  frag="$(q_escape "$tok")"
  q="mimeType='application/vnd.google-apps.folder' and trashed=false and name contains '$frag'"
  rows="$(gapi GET "https://www.googleapis.com/drive/v3/files?pageSize=10&fields=files(id,name)" \
    --get --data-urlencode "q=$q" | python3 -c '
import json, sys
for f in json.load(sys.stdin).get("files", []):
    print(f["id"] + "\t" + f["name"])')"
  if [[ -z "$rows" ]]; then echo "resolve_folder: no folder matches '$tok'" >&2; return 1; fi
  n="$(grep -c . <<<"$rows")"
  if (( n > 1 )); then
    { echo "resolve_folder: '$tok' is ambiguous ($n matches):"
      awk -F'\t' '{printf "   %s  %s\n", $1, $2}' <<<"$rows"
      echo "Pass the folder id or a more specific name."; } >&2
    return 1
  fi
  cut -f1 <<<"$rows"
}

DRIVE_API="https://www.googleapis.com/drive/v3"
SHEETS_API="https://sheets.googleapis.com/v4"
DOCS_API="https://docs.googleapis.com/v1"

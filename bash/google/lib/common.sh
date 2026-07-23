#!/usr/bin/env bash
# Common helpers for bash/google/ — read-only Drive access via the mkt API
# (Meetico backend, contract: apis/mkt/drive.openapi.json). Source from any
# script: source "$(dirname "$0")/lib/common.sh"
#
# The backend OWNS the org's Google identity (token, refresh, index); these
# scripts never see Google credentials and never touch the database. Two modes,
# picked from the environment at load:
#
#   copiloto : CEREBRO_API + CEREBRO_TOKEN  → forja-proxy ($CEREBRO_API/v1/mkt)
#              — el proxy inyecta el JWT de servicio de la org y audita la llamada
#   cerebro  : MEETICO_BASE + MEETICO_JWT_TOKEN → directo al backend
#              (el mismo par que usa el viz para el bind — .viz/lib/meetico.js)
#
# Read-only: these scripts only ever GET. The one write in the API contract
# (PATCH rename) is deliberately not wrapped.
set -euo pipefail

GOOGLE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$GOOGLE_LIB_DIR/../../.." && pwd)"

# --- Load .env (CEREBRO_* / MEETICO_* live there) ---------------------------
if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

FORMAT="${FORMAT:-table}"

# --- Mode selection ----------------------------------------------------------
if [[ -n "${CEREBRO_API:-}" && -n "${CEREBRO_TOKEN:-}" ]]; then
  MKT_MODE="proxy"
  MKT_BASE="${CEREBRO_API%/}/v1/mkt"
  MKT_BEARER="$CEREBRO_TOKEN"
elif [[ -n "${MEETICO_JWT_TOKEN:-}" ]]; then
  : "${MEETICO_BASE:?MEETICO_BASE not set (la URL del backend mkt va en .env — p.ej. https://<org>gm.meetico.parallelo.ai)}"
  MKT_MODE="directo"
  MKT_BASE="${MEETICO_BASE%/}"
  MKT_BEARER="$MEETICO_JWT_TOKEN"
else
  echo "google: sin credenciales — se necesita CEREBRO_API+CEREBRO_TOKEN (copiloto)" >&2
  echo "o MEETICO_BASE+MEETICO_JWT_TOKEN (cerebro) en el .env" >&2
  exit 1
fi
export MKT_MODE MKT_BASE

# mapi <METHOD> <path> [curl-args...] : authenticated call to the mkt API,
# JSON on stdout. Non-2xx exits 1 with the API error on stderr. A 404 that is
# an Express "Cannot GET/POST" (route missing) gets its own message: the
# endpoint exists in the contract but the backend hasn't deployed it yet.
mapi() {
  local method="$1" path="$2"; shift 2
  local tmp code
  tmp="$(mktemp)"
  code="$(curl -sS -X "$method" "$MKT_BASE$path" \
    -H "Authorization: Bearer ${MKT_BEARER}" \
    -o "$tmp" -w '%{http_code}' "$@")" || { rm -f "$tmp"; return 1; }
  if [[ "$code" == "404" ]] && grep -q '<pre>Cannot ' "$tmp"; then
    echo "mkt api: el backend aún no expone $method $path" >&2
    echo "(está en el contrato apis/mkt/drive.openapi.json — pendiente de deploy en Meetico)" >&2
    rm -f "$tmp"; return 1
  fi
  if [[ "$code" != 2* ]]; then
    echo "mkt api HTTP $code ($path):" >&2
    head -c 500 "$tmp" >&2; echo >&2
    rm -f "$tmp"
    return 1
  fi
  cat "$tmp"
  rm -f "$tmp"
}

# gid <id-or-url> : extract a Drive file/folder id from a raw id or any
# docs.google.com / drive.google.com URL (/d/<id>, /folders/<id>, ?id=<id>).
# Local regex — no API call. (POST /drive/resolve is the server-side twin.)
gid() {
  local raw="$1" id=""
  id="$(printf '%s' "$raw" | grep -oE '/(d|folders|file/d)/[A-Za-z0-9_-]{10,}' | head -n1 | grep -oE '[A-Za-z0-9_-]{10,}$' || true)"
  [[ -z "$id" ]] && id="$(printf '%s' "$raw" | grep -oE '[?&]id=[A-Za-z0-9_-]{10,}' | head -n1 | sed 's/^.*id=//' || true)"
  if [[ -z "$id" && "$raw" =~ ^[A-Za-z0-9_-]{10,}$ ]]; then id="$raw"; fi
  [[ -z "$id" ]] && { echo "gid: no Google file id found in '$raw'" >&2; return 1; }
  printf '%s\n' "$id"
}

# resolve_folder <id|url|name-fragment> : echoes a folder id. Tries id/url
# first; otherwise searches folders by name in the Drive index, erroring on
# no/ambiguous match (or telling you the index isn't deployed yet).
resolve_folder() {
  local tok="$1" id
  if id="$(gid "$tok" 2>/dev/null)"; then printf '%s\n' "$id"; return 0; fi
  local rows n
  rows="$(mapi GET "/drive/index?isFolder=true&limit=10" --get --data-urlencode "search=$tok" | python3 -c '
import json, sys
for it in json.load(sys.stdin).get("items", []):
    print(it["file_id"] + "\t" + it["name"])')" || {
    echo "resolve_folder: la búsqueda por nombre necesita el índice del backend; mientras, pasa el id o la URL de la carpeta." >&2
    return 1
  }
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

#!/usr/bin/env bash
# Common helpers for bash/users/ — Marketico Users API scripts.
# Source from any script: source "$(dirname "$0")/lib/common.sh"
#
# Auth: MARKETICO_JWT_TOKEN in .env. Base URL: MARKETICO_URL (default
# https://ikigaigm.api.parallelo.ai, the marketicoBase of apis/mkt/*.openapi).
# Read scripts only ever GET. Write scripts (create_user.sh, update_user.sh)
# are clearly marked WRITE, print before/after and support --dry-run.
# Deliberately independent of bash/lib/common.sh (no Postgres involved).
set -euo pipefail

USERS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERS_DIR="$(cd "$USERS_LIB_DIR/.." && pwd)"
REPO_ROOT="$(cd "$USERS_DIR/../.." && pwd)"

# --- Load token from .env ---------------------------------------------------
if [[ -z "${MARKETICO_JWT_TOKEN:-}" && -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi
: "${MARKETICO_JWT_TOKEN:?MARKETICO_JWT_TOKEN not set (expected in $REPO_ROOT/.env)}"
MARKETICO_URL="${MARKETICO_URL:-https://ikigaigm.api.parallelo.ai}"

# --- Output format ----------------------------------------------------------
# Set FORMAT=json (or pass --json, handled by scripts) for machine output.
FORMAT="${FORMAT:-table}"

# mkt_api <METHOD> <path> [curl-args...] : raw API call, JSON body on stdout.
mkt_api() {
  local method="$1" path="$2"; shift 2
  curl -sS -m 30 -X "$method" "${MARKETICO_URL}${path}" \
    -H "Authorization: Bearer ${MARKETICO_JWT_TOKEN}" \
    -H "Content-Type: application/json" \
    "$@"
}

# --- Python snippets (heredocs keep quoting sane and stdin free) ------------
read -r -d '' _UNWRAP_PY <<'PY' || true
import json, sys
raw = sys.stdin.read()
try:
    resp = json.loads(raw)
except ValueError:
    sys.stderr.write("marketico: non-JSON response: %s\n" % raw[:400]); sys.exit(1)
if isinstance(resp, dict) and "success" in resp:
    if not resp.get("success"):
        sys.stderr.write("marketico: %s\n" % (resp.get("message") or json.dumps(resp))); sys.exit(1)
    json.dump(resp.get("data"), sys.stdout, ensure_ascii=False)
else:
    json.dump(resp, sys.stdout, ensure_ascii=False)
PY

read -r -d '' _RENDER_PY <<'PY' || true
import json, sys
cols = sys.argv[1:]
raw = sys.stdin.read()
if not raw.strip(): sys.exit(1)
rows = json.loads(raw)
if rows is None: rows = []
if isinstance(rows, dict): rows = [rows]
if not cols:
    cols = list(rows[0].keys()) if rows else []
def cell(r, c):
    v = r.get(c, "")
    return "" if v is None else str(v)
w = {c: max([len(c)] + [len(cell(r, c)) for r in rows]) for c in cols}
print("  ".join(c.ljust(w[c]) for c in cols))
print("  ".join("-" * w[c] for c in cols))
for r in rows:
    print("  ".join(cell(r, c).ljust(w[c]) for c in cols))
print("(%d rows)" % len(rows))
PY

read -r -d '' _SHAPE_USERS_PY <<'PY' || true
import json, sys
out = []
raw = sys.stdin.read()
if not raw.strip(): sys.exit(1)
for u in (json.loads(raw) or []):
    out.append({
        "id": (u.get("id") or "")[:8],
        "name": u.get("name"), "lastname": u.get("lastname"),
        "email": u.get("user_email") or u.get("person_email"),
        "phone": u.get("phone") or u.get("phone_number"),
        "disabled": u.get("disabled"),
        "created": (u.get("created_at") or "")[:10],
    })
json.dump(out, sys.stdout, ensure_ascii=False)
PY

read -r -d '' _RESOLVE_PY <<'PY' || true
import json, sys
tok = sys.argv[1].lower()
raw = sys.stdin.read()
if not raw.strip(): sys.exit(1)
users = json.loads(raw) or []
m = [u for u in users if (u.get("id") or "").lower().startswith(tok)]
if not m:
    m = [u for u in users
         if tok in ("%s %s" % (u.get("name") or "", u.get("lastname") or "")).lower()
         or tok in (u.get("user_email") or "").lower()]
if len(m) == 1:
    print(m[0]["id"]); sys.exit(0)
if not m:
    sys.stderr.write("resolve_user: no match for '%s'\n" % sys.argv[1]); sys.exit(1)
sys.stderr.write("resolve_user: '%s' is ambiguous (%d matches):\n" % (sys.argv[1], len(m)))
for u in m:
    sys.stderr.write("   %s  %s %s  %s\n" % (u["id"][:8], u.get("name") or "",
                     u.get("lastname") or "", u.get("user_email") or ""))
sys.stderr.write("Refine the name or pass an id prefix.\n")
sys.exit(1)
PY

read -r -d '' _USER_ROW_PY <<'PY' || true
import json, sys
uid = sys.argv[1]
raw = sys.stdin.read()
if not raw.strip(): sys.exit(1)
for u in (json.loads(raw) or []):
    if u.get("id") == uid:
        json.dump(u, sys.stdout, ensure_ascii=False); sys.exit(0)
sys.stderr.write("user_row: user %s not found\n" % uid); sys.exit(1)
PY

# mkt_data <METHOD> <path> [curl-args...] : call, unwrap the {success,data}
# envelope. Errors (with the API's message) when success != true.
mkt_data() {
  mkt_api "$@" | python3 -c "$_UNWRAP_PY"
}

# render [col...] : stdin = JSON array (or object) → aligned table with a row
# count, or raw JSON passthrough when FORMAT=json. No cols = all keys.
render() {
  if [[ "$FORMAT" == "json" ]]; then cat; echo; return; fi
  python3 -c "$_RENDER_PY" "$@"
}

# shape_users : stdin = raw users array → listing rows (short id, ISO day).
shape_users() {
  python3 -c "$_SHAPE_USERS_PY"
}

# resolve_user <token> : echoes the full user id for an id-prefix, a name
# fragment or an email fragment. Errors (listing candidates) on no/ambiguous
# match. One GET of the full list (there is no GET /api/users/{id}).
resolve_user() {
  mkt_data GET /api/users/ | python3 -c "$_RESOLVE_PY" "$1"
}

# user_row <full-id> : echoes one user object (from the list) or errors.
user_row() {
  mkt_data GET /api/users/ | python3 -c "$_USER_ROW_PY" "$1"
}

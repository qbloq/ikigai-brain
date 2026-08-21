#!/usr/bin/env bash
# Common helpers for bash/ghl/ — read-only access to the GoHighLevel API v2.
# Source from any script: source "$(dirname "$0")/lib/common.sh"
#
# WHY THIS DOMAIN EXISTS
# The org's CRM lives in GHL and is mirrored into `crm_contacts` /
# `crm_opportunities` by an ingestor we do not control. That mirror is the
# only thing every other script reads, so when it drifts, every closer metric
# drifts with it. These scripts talk to GHL directly for ONE purpose: to
# measure the mirror against the source. They are a probe, not a second
# ingestion path — nothing here writes to the database.
#
# CREDENTIALS — read the policy before extending this
# Unlike bash/google/ (where the backend owns the identity and the scripts
# never see a token), the GHL Private Integration Tokens live in the database,
# in `project_crm_configs.api_key_encrypted` — one per project, plaintext
# despite the column name. That means anything able to read the org's Postgres
# can read them, so this layer is deliberately fenced:
#
#   - fenced by ROLE: bash/lib/acceso.sh decides which copilot roles may use
#     it (ejecutivo = total; the rest refused) — forks inherit this code, but
#     not the credentials unless their role says so;
#   - read-only: every call is a GET, and the DB connection is psql_ro;
#   - the token never reaches argv — it is handed to curl over stdin via
#     `--config -`, so it cannot be read from the process list.
#
# Moving the credentials behind the backend (the bash/google/ pattern) is the
# right end state; until then, this fence is what keeps them from spreading.
set -euo pipefail

GHL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$GHL_LIB_DIR/../../lib/common.sh"

# --- Cerca por rol -----------------------------------------------------------
# identidad.md: a repo carrying copilot.json is an employee's fork. Whether a
# fork may use THIS domain is decided by its role, in ONE place for every
# credential-bearing domain: bash/lib/acceso.sh (ejecutivo = total; the rest
# is refused with exit 3 and pointed at the mirror, bash/crm/).
# shellcheck disable=SC1091
source "$GHL_LIB_DIR/../../lib/acceso.sh"
require_acceso ghl

GHL_BASE="${GHL_BASE:-https://services.leadconnectorhq.com}"
GHL_API_VERSION="${GHL_API_VERSION:-2021-07-28}"

# --- Credential resolution ---------------------------------------------------
# ghl_projects : one row per project with a GHL config — id, name, location,
# connection_status. Never selects the token.
ghl_projects() {
  psql_ro -t -A -F$'\t' -c "
    SELECT c.project_id, p.name, coalesce(c.location_id,''), coalesce(c.connection_status,'')
    FROM project_crm_configs c
    JOIN projects p ON p.id = c.project_id
    WHERE c.provider = 'ghl' AND c.api_key_encrypted IS NOT NULL
    ORDER BY p.name;"
}

# ghl_resolve_project <name-fragment> : echoes "<project_id>\t<name>" for the
# single project matching the fragment. Errors on no match or ambiguity — the
# same contract as resolve_member in the tasks layer.
ghl_resolve_project() {
  local frag="$1" rows n
  rows="$(ghl_projects | awk -F'\t' -v f="${frag,,}" 'tolower($2) ~ f {print $1 "\t" $2}')"
  if [[ -z "$rows" ]]; then
    echo "ghl: ningún proyecto con CRM configurado coincide con '$frag'." >&2
    echo "Disponibles: $(ghl_projects | cut -f2 | paste -sd', ')" >&2
    return 1
  fi
  n="$(grep -c . <<<"$rows")"
  if (( n > 1 )); then
    echo "ghl: '$frag' es ambiguo ($n coincidencias): $(cut -f2 <<<"$rows" | paste -sd', ')" >&2
    return 1
  fi
  printf '%s\n' "$rows"
}

# ghl_load_creds <project_id> : sets GHL_LOCATION and GHL_TOKEN for the calls
# that follow. GHL_TOKEN is never printed and never passed on a command line.
ghl_load_creds() {
  local pid="$1" row
  row="$(psql_ro -t -A -F$'\t' -c "
    SELECT coalesce(location_id,''), coalesce(api_key_encrypted,'')
    FROM project_crm_configs
    WHERE provider='ghl' AND project_id='${pid//\'/\'\'}' LIMIT 1;")"
  GHL_LOCATION="$(cut -f1 <<<"$row")"
  GHL_TOKEN="$(cut -f2 <<<"$row")"
  if [[ -z "$GHL_LOCATION" || -z "$GHL_TOKEN" ]]; then
    echo "ghl: el proyecto no tiene location_id o token en project_crm_configs." >&2
    return 1
  fi
  export GHL_LOCATION
}

# --- HTTP --------------------------------------------------------------------
# ghl_api <path-with-query> : authenticated GET, JSON on stdout. The token goes
# to curl through stdin (--config -) so it stays out of `ps`. Non-2xx exits 1
# with the API's error body, truncated.
ghl_api() {
  local path="$1" tmp code
  tmp="$(mktemp)"
  code="$(printf 'url = "%s"\nheader = "Authorization: Bearer %s"\nheader = "Version: %s"\nheader = "Accept: application/json"\n' \
      "$GHL_BASE$path" "$GHL_TOKEN" "$GHL_API_VERSION" \
    | curl -sS --config - -o "$tmp" -w '%{http_code}')" || { rm -f "$tmp"; return 1; }
  if [[ "$code" != 2* ]]; then
    echo "ghl api HTTP $code — ${path%%\?*}" >&2
    head -c 400 "$tmp" >&2; echo >&2
    [[ "$code" == "401" || "$code" == "403" ]] && \
      echo "(token inválido o sin scope para este location — revisa la integración privada en GHL)" >&2
    rm -f "$tmp"; return 1
  fi
  cat "$tmp"; rm -f "$tmp"
}

# ghl_api_search <path> <json-body> : the ONE non-GET call of this layer.
#
# GHL's contact search lives at POST /contacts/search: it is a *fetch* whose
# criteria travel in the body because they don't fit a query string. It creates
# nothing and mutates nothing — the layer stays read-only in effect, and the
# fence («solo GET») is relaxed here on purpose, by decision of the repo owner
# (2026-08-14), so that looking one contact up doesn't require pulling 2.000.
# Any endpoint that WRITES stays out, POST or not.
#
# Same token discipline as ghl_api: token and body both reach curl off `argv`
# (config on stdin, body from a 0600 temp file).
ghl_api_search() {
  local path="$1" body="$2" tmp body_f code
  tmp="$(mktemp)"; body_f="$(mktemp)"
  chmod 600 "$body_f"; printf '%s' "$body" >"$body_f"
  code="$(printf 'url = "%s"\nrequest = "POST"\nheader = "Authorization: Bearer %s"\nheader = "Version: %s"\nheader = "Accept: application/json"\nheader = "Content-Type: application/json"\ndata = "@%s"\n' \
      "$GHL_BASE$path" "$GHL_TOKEN" "$GHL_API_VERSION" "$body_f" \
    | curl -sS --config - -o "$tmp" -w '%{http_code}')" || { rm -f "$tmp" "$body_f"; return 1; }
  rm -f "$body_f"
  if [[ "$code" != 2* ]]; then
    echo "ghl search HTTP $code — $path" >&2
    head -c 400 "$tmp" >&2; echo >&2
    rm -f "$tmp"; return 1
  fi
  cat "$tmp"; rm -f "$tmp"
}

# ghl_qs <k> <v> [<k> <v> ...] : url-encoded query string, leading '?'.
ghl_qs() {
  python3 -c '
import sys, urllib.parse
a = sys.argv[1:]
print("?" + urllib.parse.urlencode(list(zip(a[::2], a[1::2]))) if a else "")' "$@"
}

# --- Paged fetch -------------------------------------------------------------
# ghl_fetch_all <endpoint> <items-key> <location-param> [max] : walks GHL's
# pagination and emits ONE json array of every item, on stdout. `max` caps the
# item count (0/absent = no cap).
#
# This helper is the whole point of the domain: GHL pages at 100, and an
# ingestor that stops after the first page is exactly the failure we are
# chasing. Paging is driven by meta.startAfter/startAfterId, falling back to
# meta.nextPageUrl, and stops when a page comes back short or repeats.
ghl_fetch_all() {
  local endpoint="$1" key="$2" locparam="$3" max="${4:-0}"
  local dir page=0 got=0 after="" after_id="" out step n new_id new_after qs
  dir="$(mktemp -d)"
  trap 'rm -rf "$dir"' RETURN
  while :; do
    if [[ -n "$after_id" ]]; then
      qs="$(ghl_qs "$locparam" "$GHL_LOCATION" limit 100 startAfterId "$after_id" startAfter "$after")"
    else
      qs="$(ghl_qs "$locparam" "$GHL_LOCATION" limit 100)"
    fi
    out="$(ghl_api "$endpoint$qs")" || return 1
    printf '%s' "$out" >"$dir/$(printf '%04d' "$page").json"
    step="$(python3 -c '
import json, sys
d = json.load(sys.stdin)
meta = d.get("meta") or {}
print(len(d.get(sys.argv[1]) or []))
print(meta.get("startAfterId") or "")
print(meta.get("startAfter") or "")' "$key" <<<"$out")"
    n="$(sed -n 1p <<<"$step")"
    new_id="$(sed -n 2p <<<"$step")"
    new_after="$(sed -n 3p <<<"$step")"
    got=$(( got + n ))
    page=$(( page + 1 ))
    (( n < 100 )) && break                        # short page = last page
    [[ -z "$new_id" || "$new_id" == "$after_id" ]] && break   # no cursor / no progress
    (( max > 0 && got >= max )) && break
    after_id="$new_id"; after="$new_after"
  done
  python3 -c '
import glob, json, os, sys
key, d, m = sys.argv[1], sys.argv[2], int(sys.argv[3])
items, seen = [], set()
for f in sorted(glob.glob(os.path.join(d, "*.json"))):
    with open(f) as fh:
        for it in (json.load(fh).get(key) or []):
            i = it.get("id")
            if i in seen: continue      # pages can overlap on the cursor row
            seen.add(i); items.append(it)
if m > 0: items = items[:m]
json.dump(items, sys.stdout)' "$key" "$dir" "$max"
}

# --- Rendering ---------------------------------------------------------------
# ghl_render <col:path,col:path,...> : reads a JSON array on stdin. FORMAT=json
# passes it through untouched; otherwise prints an aligned table, resolving
# dotted paths (e.g. contact.name) against each item.
ghl_render() {
  if [[ "$FORMAT" == "json" ]]; then cat; return; fi
  python3 -c '
import json, sys
spec = [s.split(":", 1) for s in sys.argv[1].split(",")]
items = json.load(sys.stdin)
if not isinstance(items, list): items = [items]
def get(o, path):
    for p in path.split("."):
        if isinstance(o, dict): o = o.get(p)
        elif isinstance(o, list): o = o[int(p)] if p.isdigit() and int(p) < len(o) else None
        else: return None
    if o is None: return ""
    if isinstance(o, (dict, list)): return json.dumps(o, ensure_ascii=False)[:40]
    return str(o)
rows = [[get(it, p) for _, p in spec] for it in items]
heads = [h for h, _ in spec]
w = [max(len(heads[i]), *(len(r[i]) for r in rows)) if rows else len(heads[i]) for i in range(len(heads))]
print(" | ".join(h.ljust(w[i]) for i, h in enumerate(heads)))
print("-+-".join("-" * x for x in w))
for r in rows:
    print(" | ".join(c.ljust(w[i]) for i, c in enumerate(r)))
print(f"({len(rows)} filas)")' "$1"
}

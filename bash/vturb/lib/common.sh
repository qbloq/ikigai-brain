#!/usr/bin/env bash
# Common helpers for bash/vturb/ — read-only access to the VTurb Analytics API.
# Source from any script: source "$(dirname "$0")/lib/common.sh"
#
# WHY THIS DOMAIN EXISTS
# The org's VSLs are hosted on VTurb (the video provider selected in Marketico:
# `projects.video_provider_key='vturb'`). Marketico proxies VTurb's analytics
# for its funnel, but that surface is per-project UI plumbing. These scripts
# talk to VTurb's Analytics API directly — the video at the source: catalog of
# players, unique plays/views per date window, and the per-second retention
# curve. Nothing here writes anywhere (the API itself exposes no mutations).
#
# CREDENTIALS — read the policy before extending this
# Like bash/ghl/, the tokens live in the database in plaintext:
# `project_vturb_video_configs.api_key_encrypted` (the column name lies), one
# per project. Anything able to read the org's Postgres can read them, so the
# layer is fenced the same way:
#
#   - fenced by ROLE: bash/lib/acceso.sh decides which copilot roles may use
#     it (ejecutivo = total; the rest refused);
#   - read-only in effect: VTurb's read surface uses POST for its two stats
#     endpoints (/sessions/stats, /times/user_engagement) because the criteria
#     travel in a body — they fetch, they mutate nothing. The fence here is
#     therefore «solo consultas», not «solo GETs»; any endpoint that WRITES
#     stays out, whatever its verb;
#   - the token never reaches argv — it is handed to curl over stdin via
#     `--config -`, so it cannot be read from the process list.
#
# API reference: https://vturb.gitbook.io/analytics-api/pt
#   Base host : https://analytics.vturb.net
#   Auth      : headers `X-Api-Token: <key>` + `X-Api-Version: v1`
#   Dates     : 'YYYY-MM-DD HH:MM:SS' + a `timezone` param. We send
#               America/Bogota (the house timezone) — unlike Marketico's
#               proxy, which sends UTC wall-clock.
set -euo pipefail

VTURB_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$VTURB_LIB_DIR/../../lib/common.sh"

# --- Cerca por rol -----------------------------------------------------------
# identidad.md: a repo carrying copilot.json is an employee's fork. Whether a
# fork may use THIS domain is decided by its role, in ONE place for every
# credential-bearing domain: bash/lib/acceso.sh (ejecutivo = total; the rest
# is refused with exit 3 — the proxy-Mkt fallback for them is still pending).
# shellcheck disable=SC1091
source "$VTURB_LIB_DIR/../../lib/acceso.sh"
require_acceso vturb

VTURB_BASE="${VTURB_BASE:-https://analytics.vturb.net}"
VTURB_API_VERSION="${VTURB_API_VERSION:-v1}"
VTURB_TZ="${VTURB_TZ:-America/Bogota}"

# --- Credential resolution ---------------------------------------------------
# vturb_projects : one row per project with a VTurb config — id, name,
# connection_status, connected_at. Never selects the token.
vturb_projects() {
  psql_ro -t -A -F$'\t' -c "
    SELECT c.project_id, p.name, coalesce(c.connection_status,''),
           coalesce(to_char(c.connected_at AT TIME ZONE 'America/Bogota', 'YYYY-MM-DD'),'')
    FROM project_vturb_video_configs c
    JOIN projects p ON p.id = c.project_id
    WHERE c.api_key_encrypted IS NOT NULL
    ORDER BY p.name;"
}

# vturb_resolve_project <name-fragment> : echoes "<project_id>\t<name>" for the
# single project matching the fragment. Errors on no match or ambiguity.
vturb_resolve_project() {
  local frag="$1" rows n
  rows="$(vturb_projects | awk -F'\t' -v f="$(printf '%s' "$frag" | tr '[:upper:]' '[:lower:]')" 'tolower($2) ~ f {print $1 "\t" $2}')"
  if [[ -z "$rows" ]]; then
    echo "vturb: ningún proyecto con VTurb configurado coincide con '$frag'." >&2
    echo "Disponibles: $(vturb_projects | cut -f2 | paste -sd', ')" >&2
    return 1
  fi
  n="$(grep -c . <<<"$rows")"
  if (( n > 1 )); then
    echo "vturb: '$frag' es ambiguo ($n coincidencias): $(cut -f2 <<<"$rows" | paste -sd', ')" >&2
    return 1
  fi
  printf '%s\n' "$rows"
}

# vturb_load_creds <project_id> : sets VTURB_TOKEN for the calls that follow.
# Never printed, never passed on a command line.
vturb_load_creds() {
  local pid="$1"
  VTURB_TOKEN="$(psql_ro -t -A -c "
    SELECT api_key_encrypted FROM project_vturb_video_configs
    WHERE project_id='${pid//\'/\'\'}' AND api_key_encrypted IS NOT NULL LIMIT 1;")"
  if [[ -z "$VTURB_TOKEN" ]]; then
    echo "vturb: el proyecto no tiene token en project_vturb_video_configs." >&2
    return 1
  fi
}

# vturb_selections <project_id> : the project's curated selections from OUR
# database (Marketico's `project_vturb_video_selections`) as a JSON array of
# {video_id, titulo, duracion, seleccionado}. The duration stored here is the
# input the retention endpoint requires.
vturb_selections() {
  local pid="$1"
  psql_ro -t -A -c "
    SELECT coalesce(json_agg(json_build_object(
             'video_id', video_id,
             'titulo', coalesce(video_title,'(sin título)'),
             'duracion', video_duration,
             'seleccionado', to_char(created_at AT TIME ZONE 'America/Bogota','YYYY-MM-DD'))
           ORDER BY created_at DESC), '[]')
    FROM project_vturb_video_selections
    WHERE project_id='${pid//\'/\'\'}';"
}

# --- HTTP --------------------------------------------------------------------
# vturb_api_get <path> : authenticated GET, JSON on stdout. Token via stdin
# config. Non-2xx exits 1 with the API's error body, truncated.
vturb_api_get() {
  local path="$1" tmp code
  tmp="$(mktemp)"
  code="$(printf 'url = "%s"\nheader = "X-Api-Token: %s"\nheader = "X-Api-Version: %s"\nheader = "Accept: application/json"\n' \
      "$VTURB_BASE$path" "$VTURB_TOKEN" "$VTURB_API_VERSION" \
    | curl -sS -m 30 --config - -o "$tmp" -w '%{http_code}')" || { rm -f "$tmp"; return 1; }
  if [[ "$code" != 2* ]]; then
    echo "vturb api HTTP $code — $path" >&2
    head -c 400 "$tmp" >&2; echo >&2
    [[ "$code" == "401" || "$code" == "403" ]] && \
      echo "(token inválido — probar con auth_status.sh)" >&2
    rm -f "$tmp"; return 1
  fi
  cat "$tmp"; rm -f "$tmp"
}

# vturb_api_post <path> <json-body> : read-only fetch whose criteria travel in
# the body (see the fence note above). Token and body reach curl off argv.
vturb_api_post() {
  local path="$1" body="$2" tmp body_f code
  tmp="$(mktemp)"; body_f="$(mktemp)"
  chmod 600 "$body_f"; printf '%s' "$body" >"$body_f"
  code="$(printf 'url = "%s"\nrequest = "POST"\nheader = "X-Api-Token: %s"\nheader = "X-Api-Version: %s"\nheader = "Accept: application/json"\nheader = "Content-Type: application/json"\ndata = "@%s"\n' \
      "$VTURB_BASE$path" "$VTURB_TOKEN" "$VTURB_API_VERSION" "$body_f" \
    | curl -sS -m 30 --config - -o "$tmp" -w '%{http_code}')" || { rm -f "$tmp" "$body_f"; return 1; }
  rm -f "$body_f"
  if [[ "$code" != 2* ]]; then
    echo "vturb api HTTP $code — $path" >&2
    head -c 400 "$tmp" >&2; echo >&2
    rm -f "$tmp"; return 1
  fi
  cat "$tmp"; rm -f "$tmp"
}

# --- Dates -------------------------------------------------------------------
# vturb_window <from> <to> : validates YYYY-MM-DD inputs and echoes
# "<from> 00:00:00\t<to> 23:59:59" in VTurb's expected format. Empty inputs
# default to the current month (Bogota), like the ads domain.
vturb_window() {
  local from="$1" to="$2"
  python3 -c '
import sys, datetime, zoneinfo
frm, to = sys.argv[1], sys.argv[2]
today = datetime.datetime.now(zoneinfo.ZoneInfo("America/Bogota")).date()
if not frm: frm = today.replace(day=1).isoformat()
if not to: to = today.isoformat()
for d in (frm, to):
    try: datetime.date.fromisoformat(d)
    except ValueError:
        sys.stderr.write(f"vturb: fecha inválida {d!r} (se espera YYYY-MM-DD)\n"); sys.exit(2)
print(f"{frm} 00:00:00\t{to} 23:59:59")' "$from" "$to"
}

# --- Rendering ---------------------------------------------------------------
# vturb_render <col:path,...> : JSON array on stdin → aligned table, or
# passthrough under FORMAT=json. Same contract as ghl_render.
vturb_render() {
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

FORMAT="${FORMAT:-table}"

#!/usr/bin/env bash
# Common helpers for bash/notion/ read-only Notion API scripts.
# Source from any script: source "$(dirname "$0")/lib/common.sh"
#
# Read-only: these scripts only ever GET / POST-query the Notion API. They never
# create, update, or delete Notion content. Output goes to stdout (JSON) or to
# docs/ when a script distills to markdown.
set -euo pipefail

NOTION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTION_DIR="$(cd "$NOTION_LIB_DIR/.." && pwd)"
REPO_ROOT="$(cd "$NOTION_DIR/../.." && pwd)"

# --- Credential: proxy mode or direct mode ----------------------------------
# Two modes:
#   proxy  — CEREBRO_API + CEREBRO_TOKEN in .env: calls go through the
#            brain's API; the org's Notion token lives on the SERVER, never
#            on this machine. This is how copilots run.
#   direct — NOTION=ntn_... in .env: the brain/operator with its own token.
# Proxy mode wins when both are configured.
if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi
NOTION_TOKEN="${NOTION_TOKEN:-${NOTION:-}}"
NOTION_VERSION="${NOTION_VERSION:-2022-06-28}"
if [[ -n "${CEREBRO_API:-}" && -n "${CEREBRO_TOKEN:-}" ]]; then
  NOTION_API="${CEREBRO_API%/}/v1/notion/v1"
  NOTION_AUTH="$CEREBRO_TOKEN"
else
  : "${NOTION_TOKEN:?Notion sin credencial: falta NOTION=ntn_... o el par CEREBRO_API+CEREBRO_TOKEN en $REPO_ROOT/.env}"
  NOTION_API="https://api.notion.com/v1"
  NOTION_AUTH="$NOTION_TOKEN"
fi

# notion_api <METHOD> <path> [curl-args...] : raw API call, returns JSON on stdout.
# path is relative to the Notion v1 API (e.g. /pages/<id>, /blocks/<id>/children)
# and works identically in both modes — the proxy injects Notion-Version and
# the org token server-side (the extra header here is harmless passthrough).
notion_api() {
  local method="$1" path="$2"; shift 2
  curl -sS -X "$method" "${NOTION_API}${path}" \
    -H "Authorization: Bearer ${NOTION_AUTH}" \
    -H "Notion-Version: ${NOTION_VERSION}" \
    -H "Content-Type: application/json" \
    "$@"
}

# to_uuid <id-or-url> : extract the 32-hex Notion id and dash it into a UUID.
# Accepts raw ids, dashed uuids, or any URL containing a trailing 32-hex id.
to_uuid() {
  local raw="$1" hex
  hex="$(printf '%s' "$raw" | grep -oE '[0-9a-fA-F]{32}' | tail -n1)"
  if [[ -z "$hex" ]]; then
    # already dashed?
    hex="$(printf '%s' "$raw" | grep -oiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | tail -n1 | tr -d -)"
  fi
  [[ -z "$hex" ]] && { echo "to_uuid: no Notion id found in '$raw'" >&2; return 1; }
  printf '%s-%s-%s-%s-%s\n' "${hex:0:8}" "${hex:8:4}" "${hex:12:4}" "${hex:16:4}" "${hex:20:12}" | tr 'A-F' 'a-f'
}

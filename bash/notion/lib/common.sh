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

# --- Load token from .env ---------------------------------------------------
# .env holds NOTION=ntn_... (the integration's internal token).
if [[ -z "${NOTION_TOKEN:-}" && -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi
NOTION_TOKEN="${NOTION_TOKEN:-${NOTION:-}}"
: "${NOTION_TOKEN:?NOTION token not set (expected NOTION=ntn_... in $REPO_ROOT/.env)}"

NOTION_VERSION="${NOTION_VERSION:-2022-06-28}"
NOTION_API="https://api.notion.com/v1"

# notion_api <METHOD> <path> [curl-args...] : raw API call, returns JSON on stdout.
# path is relative to NOTION_API (e.g. /pages/<id>, /blocks/<id>/children).
notion_api() {
  local method="$1" path="$2"; shift 2
  curl -sS -X "$method" "${NOTION_API}${path}" \
    -H "Authorization: Bearer ${NOTION_TOKEN}" \
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

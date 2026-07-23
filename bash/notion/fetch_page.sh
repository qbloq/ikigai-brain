#!/usr/bin/env bash
# fetch_page.sh <page-id|url> [--out FILE] [--json|--blocks|--raw]
#
# Read-only. Distill a Notion page to Markdown (properties + recursive block
# tree, inline child-databases rendered as tables). Prints to stdout, or writes
# to --out. Modes:
#   (default)  markdown page
#   --blocks   raw block tree JSON
#   --raw      page object JSON
#   --db       treat the id as a database and dump its rows as a table
#
# Token: NOTION=ntn_... in .env (see lib/common.sh).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/common.sh"

mode="page"; out=""; id=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2;;
    --blocks) mode="blocks"; shift;;
    --raw) mode="raw-page"; shift;;
    --db) mode="db"; shift;;
    --search) mode="search"; shift;;
    -h|--help) sed -n '2,15p' "$0"; exit 0;;
    *) id="$1"; shift;;
  esac
done
[[ -z "$id" ]] && { echo "usage: fetch_page.sh <page-id|url> [--out FILE] [--blocks|--raw|--db]" >&2; exit 1; }

export NOTION_TOKEN NOTION_VERSION
if [[ -n "$out" ]]; then
  python3 "$HERE/lib/notion.py" "$mode" "$id" > "$out"
  echo "wrote $out" >&2
else
  python3 "$HERE/lib/notion.py" "$mode" "$id"
fi

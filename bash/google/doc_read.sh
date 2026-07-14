#!/usr/bin/env bash
# doc_read.sh <id|url> [--out FILE] [--txt] [--raw] [--json]
#
# Read-only. Distill a Google Doc to Markdown (Drive export). Prints to
# stdout, or writes to --out. Modes:
#   (default)  markdown export (via Drive — always available)
#   --txt      plain-text export (via Drive)
#   --raw      Docs API document JSON — requires docs.googleapis.com enabled
#              in the OAuth project (disabled today; md/txt cover reading)
#   --json     wrap the export as {"id","markdown"} (the viz `gdoc` source)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/common.sh"

mode="md"; out=""; ref=""; json=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2;;
    --txt) mode="txt"; shift;;
    --raw) mode="raw"; shift;;
    --json) json=1; shift;;
    -h|--help) sed -n '2,11p' "$0"; exit 0;;
    *) ref="$1"; shift;;
  esac
done
[[ -z "$ref" ]] && { echo "usage: doc_read.sh <id|url> [--out FILE] [--txt|--raw]" >&2; exit 1; }
id="$(gid "$ref")"

fetch() {
  case "$mode" in
    md)  gapi GET "$DRIVE_API/files/$id/export" --get --data-urlencode "mimeType=text/markdown";;
    txt) gapi GET "$DRIVE_API/files/$id/export" --get --data-urlencode "mimeType=text/plain";;
    raw) gapi GET "$DOCS_API/documents/$id";;
  esac
}

if (( json )); then
  fetch | DOC_ID="$id" python3 -c 'import json, os, sys; print(json.dumps({"id": os.environ["DOC_ID"], "markdown": sys.stdin.read()}, ensure_ascii=False))'
elif [[ -n "$out" ]]; then
  fetch > "$out"
  echo "wrote $out" >&2
else
  fetch
  echo
fi

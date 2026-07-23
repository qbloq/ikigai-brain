#!/usr/bin/env bash
# doc_read.sh <id|url> [--out FILE] [--txt] [--json]
#
# Read-only. Read a Google Doc via the mkt API (GET /drive/files/:id/content).
# Prints to stdout, or writes to --out. Modes:
#   (default)  markdown  (?format=markdown — export Drive del backend)
#   --txt      plain text (?format=text)
#   --json     wrap as {"id","markdown"} (the viz `gdoc` source)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/common.sh"

mode="markdown"; out=""; ref=""; json=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2;;
    --txt) mode="text"; shift;;
    --raw) echo "doc_read: --raw (Docs API JSON) no existe vía el backend; usa el markdown" >&2; exit 1;;
    --json) json=1; shift;;
    -h|--help) sed -n '2,9p' "$0"; exit 0;;
    *) ref="$1"; shift;;
  esac
done
[[ -z "$ref" ]] && { echo "usage: doc_read.sh <id|url> [--out FILE] [--txt] [--json]" >&2; exit 1; }
id="$(gid "$ref")"

# El content llega como DriveArtifactContent {exists, content_text, …}
fetch() {
  mapi GET "/drive/files/$id/content?format=$mode" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if not d.get("exists", True):
    sys.stderr.write("doc_read: el archivo no existe o no es accesible\n"); sys.exit(1)
if d.get("content_text") is None:
    sys.stderr.write("doc_read: sin texto extraible (mime: %s)\n" % d.get("mime", "?")); sys.exit(1)
sys.stdout.write(d["content_text"])'
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

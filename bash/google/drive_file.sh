#!/usr/bin/env bash
# drive_file.sh <id|url> [--json]
#
# Read-only. Metadata of one Drive file via the mkt API (GET /drive/files/:id).
# --json dumps the API object untouched (keys estilo Google: id, name,
# mimeType, createdTime, webViewLink, …).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/common.sh"

ref=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) FORMAT=json; shift;;
    -h|--help) sed -n '2,6p' "$0"; exit 0;;
    *) ref="$1"; shift;;
  esac
done
[[ -z "$ref" ]] && { echo "usage: drive_file.sh <id|url> [--json]" >&2; exit 1; }
id="$(gid "$ref")"

meta="$(mapi GET "/drive/files/$id")"

if [[ "$FORMAT" == "json" ]]; then
  printf '%s\n' "$meta" | python3 -m json.tool
  exit 0
fi

META="$meta" python3 - <<'PY'
import json, os
f = json.loads(os.environ["META"])
owner = (f.get("owners") or [{}])[0]
rows = [
    ("id", f.get("id", "")),
    ("name", f.get("name", "")),
    ("mime", f.get("mimeType", "")),
    ("size", f.get("size") or "—"),
    ("created", f.get("createdTime", "")),
    ("modified", f.get("modifiedTime", "") or "—"),
    ("owner", f"{owner.get('displayName','')} <{owner.get('emailAddress','')}>" if owner else "—"),
    ("url", f.get("webViewLink", "")),
]
if f.get("videoMediaMetadata"):
    v = f["videoMediaMetadata"]
    rows.append(("video", f"{v.get('width','?')}×{v.get('height','?')} · {v.get('durationMillis','?')}ms"))
for k, v in rows:
    print(f"{k:<13} {v}")
PY

#!/usr/bin/env bash
# drive_file.sh <id|url> [--json]
#
# Read-only. Metadata of one Drive file: name, type, size, dates, owner,
# parent folder, link. --json dumps the raw API object.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/common.sh"

ref=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) FORMAT=json; shift;;
    -h|--help) sed -n '2,5p' "$0"; exit 0;;
    *) ref="$1"; shift;;
  esac
done
[[ -z "$ref" ]] && { echo "usage: drive_file.sh <id|url> [--json]" >&2; exit 1; }
id="$(gid "$ref")"

meta="$(gapi GET "$DRIVE_API/files/$id?fields=id,name,mimeType,size,createdTime,modifiedTime,owners(displayName,emailAddress),lastModifyingUser(displayName),parents,webViewLink,trashed,shortcutDetails")"

if [[ "$FORMAT" == "json" ]]; then
  printf '%s\n' "$meta" | python3 -m json.tool
  exit 0
fi

META="$meta" python3 - <<'PY'
import json, os
f = json.loads(os.environ["META"])
owner = (f.get("owners") or [{}])[0]
rows = [
    ("id", f["id"]),
    ("name", f.get("name", "")),
    ("mime", f.get("mimeType", "")),
    ("size", f.get("size", "—")),
    ("created", f.get("createdTime", "")),
    ("modified", f.get("modifiedTime", "")),
    ("owner", f"{owner.get('displayName','')} <{owner.get('emailAddress','')}>"),
    ("last edit by", (f.get("lastModifyingUser") or {}).get("displayName", "")),
    ("parents", ", ".join(f.get("parents", []))),
    ("trashed", str(f.get("trashed", False)).lower()),
    ("url", f.get("webViewLink", "")),
]
if "shortcutDetails" in f:
    rows.append(("shortcut →", f["shortcutDetails"].get("targetId", "")))
for k, v in rows:
    print(f"{k:<13} {v}")
PY

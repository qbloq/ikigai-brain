#!/usr/bin/env bash
# drive_ls.sh [--folder ID|url|name] [--q FRAG] [--type doc|sheet|slide|folder|pdf|MIME]
#             [--trashed] [--limit N] [--json]
#
# Read-only. List/search Drive files, newest-modified first. Filters compose:
#   --folder   only direct children of that folder (id, url, or unique name fragment)
#   --q        name contains FRAG
#   --type     shorthand (doc/sheet/slide/folder/pdf) or a raw MIME type
#   --trashed  include trashed files (excluded by default)
#   --limit    max rows (default 30, max 100)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/common.sh"

folder=""; frag=""; type=""; trashed=0; limit=30
while [[ $# -gt 0 ]]; do
  case "$1" in
    --folder) folder="$2"; shift 2;;
    --q) frag="$2"; shift 2;;
    --type) type="$2"; shift 2;;
    --trashed) trashed=1; shift;;
    --limit) limit="$2"; shift 2;;
    --json) FORMAT=json; shift;;
    -h|--help) sed -n '2,11p' "$0"; exit 0;;
    *) echo "unknown arg: $1 (see -h)" >&2; exit 1;;
  esac
done
(( limit > 100 )) && limit=100

case "$type" in
  doc) mime="application/vnd.google-apps.document";;
  sheet) mime="application/vnd.google-apps.spreadsheet";;
  slide) mime="application/vnd.google-apps.presentation";;
  folder) mime="application/vnd.google-apps.folder";;
  pdf) mime="application/pdf";;
  "") mime="";;
  *) mime="$type";;
esac

q=""
(( trashed )) || q="trashed=false"
[[ -n "$mime" ]] && q="${q:+$q and }mimeType='$mime'"
[[ -n "$frag" ]] && q="${q:+$q and }name contains '$(q_escape "$frag")'"
if [[ -n "$folder" ]]; then
  fid="$(resolve_folder "$folder")"
  q="${q:+$q and }'$fid' in parents"
fi

tmpf="$(mktemp)"; trap 'rm -f "$tmpf"' EXIT
gapi GET "$DRIVE_API/files?pageSize=$limit&orderBy=modifiedTime%20desc&fields=files(id,name,mimeType,modifiedTime,size,owners(emailAddress),webViewLink)" \
  ${q:+--get --data-urlencode "q=$q"} > "$tmpf"
python3 - "$FORMAT" "$tmpf" <<'PY'
import json, sys

SHORT = {
    "application/vnd.google-apps.document": "doc",
    "application/vnd.google-apps.spreadsheet": "sheet",
    "application/vnd.google-apps.presentation": "slide",
    "application/vnd.google-apps.folder": "folder",
    "application/vnd.google-apps.shortcut": "shortcut",
    "application/pdf": "pdf",
}
files = json.load(open(sys.argv[2])).get("files", [])
rows = [{
    "id": f["id"],
    "name": f["name"],
    "type": SHORT.get(f.get("mimeType", ""), f.get("mimeType", "?").split("/")[-1]),
    "modified": f.get("modifiedTime", "")[:16].replace("T", " "),
    "size": f.get("size", ""),
    "owner": (f.get("owners") or [{}])[0].get("emailAddress", ""),
    "url": f.get("webViewLink", ""),
} for f in files]

if sys.argv[1] == "json":
    print(json.dumps(rows, indent=2, ensure_ascii=False))
    sys.exit()
if not rows:
    print("(sin resultados)")
    sys.exit()
cols = ["id", "name", "type", "modified", "owner"]
disp = [{c: (r[c][:48] + "…" if len(r[c]) > 49 else r[c]) for c in cols} for r in rows]
w = {c: max(len(c), *(len(d[c]) for d in disp)) for c in cols}
print("  ".join(c.ljust(w[c]) for c in cols))
print("  ".join("-" * w[c] for c in cols))
for d in disp:
    print("  ".join(d[c].ljust(w[c]) for c in cols))
print(f"({len(rows)} files)")
PY

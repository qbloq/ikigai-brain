#!/usr/bin/env bash
# drive_ls.sh [--folder ID|url|name] [--q FRAG] [--type doc|sheet|slide|folder|pdf|MIME]
#             [--limit N] [--json]
#
# Read-only. List/search the org's Drive via the mkt API:
#   --folder   direct children of that folder (live: GET /drive/contents)
#   --q        name search across the whole drive (index: GET /drive/index)
#   --type     shorthand (doc/sheet/slide/folder/pdf), friendly label, or MIME
#   --limit    max rows (default 30, max 100)
# Sin --folder ni --q: top-level del índice; si el índice no está desplegado,
# cae a la raíz live (/drive/contents).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/common.sh"

folder=""; frag=""; type=""; limit=30
while [[ $# -gt 0 ]]; do
  case "$1" in
    --folder) folder="$2"; shift 2;;
    --q) frag="$2"; shift 2;;
    --type) type="$2"; shift 2;;
    --trashed) echo "drive_ls: --trashed no está soportado vía el backend (se ignora)" >&2; shift;;
    --limit) limit="$2"; shift 2;;
    --json) FORMAT=json; shift;;
    -h|--help) sed -n '2,12p' "$0"; exit 0;;
    *) echo "unknown arg: $1 (see -h)" >&2; exit 1;;
  esac
done
(( limit > 100 )) && limit=100

# shorthand → MIME (live contents) y → etiqueta amigable (índice)
case "$type" in
  doc)    mime="application/vnd.google-apps.document";  label="Google Doc";;
  sheet)  mime="application/vnd.google-apps.spreadsheet"; label="Google Sheet";;
  slide)  mime="application/vnd.google-apps.presentation"; label="Google Slides";;
  folder) mime="application/vnd.google-apps.folder";    label="Folder";;
  pdf)    mime="application/pdf";                       label="PDF";;
  "")     mime=""; label="";;
  *)      mime="$type"; label="$type";;
esac

tmpf="$(mktemp)"; trap 'rm -f "$tmpf"' EXIT
shape="files"   # files = DriveFile[] (contents) · index = DriveIndexPage

if [[ -n "$folder" ]]; then
  fid="$(resolve_folder "$folder")"
  mapi GET "/drive/contents?folderId=$fid${mime:+&mimeType=$mime}" > "$tmpf"
elif [[ -n "$frag" ]]; then
  shape="index"
  mapi GET "/drive/index?limit=$limit${label:+&type=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$label")}" \
    --get --data-urlencode "search=$frag" > "$tmpf"
else
  # top-level: índice si existe; si no, la raíz live
  if ! { shape="index"; mapi GET "/drive/index?limit=$limit${label:+&type=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$label")}" > "$tmpf" 2>/dev/null; }; then
    shape="files"
    mapi GET "/drive/contents${mime:+?mimeType=$mime}" > "$tmpf"
  fi
fi

python3 - "$FORMAT" "$tmpf" "$shape" "$limit" <<'PY'
import json, sys

SHORT = {
    "application/vnd.google-apps.document": "doc",
    "application/vnd.google-apps.spreadsheet": "sheet",
    "application/vnd.google-apps.presentation": "slide",
    "application/vnd.google-apps.folder": "folder",
    "application/vnd.google-apps.shortcut": "shortcut",
    "application/pdf": "pdf",
}
LABEL_SHORT = {
    "Google Doc": "doc", "Google Sheet": "sheet", "Google Slides": "slide",
    "Folder": "folder", "PDF": "pdf", "Shortcut": "shortcut",
}
fmt, path, shape, limit = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
data = json.load(open(path))
if shape == "index":
    rows = [{
        "id": it["file_id"],
        "name": it.get("name", ""),
        "type": LABEL_SHORT.get(it.get("type", ""), (it.get("mime_type") or "?").split("/")[-1]) if not it.get("is_folder") else "folder",
        "modified": (it.get("modified_time") or "")[:16].replace("T", " "),
        "size": str(it.get("size") or ""),
        "owner": it.get("owner") or "",
        "url": it.get("web_view_link") or "",
    } for it in data.get("items", [])]
else:
    rows = [{
        "id": f["id"],
        "name": f.get("name", ""),
        "type": SHORT.get(f.get("mimeType", ""), f.get("mimeType", "?").split("/")[-1]),
        "modified": (f.get("modifiedTime") or "")[:16].replace("T", " "),
        "size": str(f.get("size") or ""),
        "owner": ((f.get("owners") or [{}])[0].get("emailAddress", "")) if f.get("owners") else "",
        "url": f.get("webViewLink", ""),
    } for f in data][:limit]

if fmt == "json":
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

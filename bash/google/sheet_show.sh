#!/usr/bin/env bash
# sheet_show.sh <id|url> [--json]
#
# Read-only. Metadata of one Google Sheet: title + its tabs with dimensions.
# Use sheet_read.sh to pull a tab's values.
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
[[ -z "$ref" ]] && { echo "usage: sheet_show.sh <id|url> [--json]" >&2; exit 1; }
id="$(gid "$ref")"

tmpf="$(mktemp)"; errf="$(mktemp)"; trap 'rm -f "$tmpf" "$errf"' EXIT
if ! gapi GET "$SHEETS_API/spreadsheets/$id?fields=properties(title),spreadsheetUrl,sheets(properties(sheetId,title,index,gridProperties(rowCount,columnCount)))" >"$tmpf" 2>"$errf"; then
  if grep -q 'SERVICE_DISABLED\|has not been used' "$errf"; then
    { echo "sheet_show: el API de Sheets está deshabilitado en el proyecto OAuth (no se pueden"
      echo "listar pestañas). Habilita sheets.googleapis.com en Google Cloud, o usa"
      echo "sheet_read.sh, que cae a Drive export CSV (primera pestaña)."; } >&2
  else
    cat "$errf" >&2
  fi
  exit 1
fi
python3 - "$FORMAT" "$tmpf" <<'PY'
import json, sys
s = json.load(open(sys.argv[2]))
tabs = [{
    "index": p["index"],
    "title": p["title"],
    "sheet_id": p["sheetId"],
    "rows": p.get("gridProperties", {}).get("rowCount", 0),
    "cols": p.get("gridProperties", {}).get("columnCount", 0),
} for p in (sh["properties"] for sh in s.get("sheets", []))]
if sys.argv[1] == "json":
    print(json.dumps({"title": s["properties"]["title"], "url": s.get("spreadsheetUrl", ""), "tabs": tabs},
                     indent=2, ensure_ascii=False))
else:
    print(f"title  {s['properties']['title']}")
    print(f"url    {s.get('spreadsheetUrl', '')}")
    print(f"tabs   ({len(tabs)}):")
    for t in tabs:
        print(f"  [{t['index']}] {t['title']}  ({t['rows']}×{t['cols']})")
PY

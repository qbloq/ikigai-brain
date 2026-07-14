#!/usr/bin/env bash
# sheet_read.sh <id|url> [--tab NAME] [--range A1:D50] [--limit N] [--raw] [--json]
#
# Read-only. Values of one Google Sheet tab (first tab by default), rendered
# as an aligned table treating row 1 as the header. --limit caps data rows
# (default 50; 0 = no cap). --json emits an array of objects keyed by the
# header row; --raw emits the API's values matrix untouched.
#
# Fallback: if the Sheets API is disabled in the OAuth project, the FIRST tab
# is pulled as CSV via the Drive export API (--tab/--range unavailable there).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/common.sh"

ref=""; tab=""; range=""; limit=50; raw=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tab) tab="$2"; shift 2;;
    --range) range="$2"; shift 2;;
    --limit) limit="$2"; shift 2;;
    --raw) raw=1; shift;;
    --json) FORMAT=json; shift;;
    -h|--help) sed -n '2,11p' "$0"; exit 0;;
    *) ref="$1"; shift;;
  esac
done
[[ -z "$ref" ]] && { echo "usage: sheet_read.sh <id|url> [--tab NAME] [--range A1] [--limit N] [--json]" >&2; exit 1; }
id="$(gid "$ref")"

errf="$(mktemp)"; tmpf="$(mktemp)"
trap 'rm -f "$errf" "$tmpf"' EXIT

sheets_api_disabled() { grep -q 'SERVICE_DISABLED\|has not been used' "$errf"; }

kind="api"
if [[ -z "$tab" ]]; then
  if meta="$(gapi GET "$SHEETS_API/spreadsheets/$id?fields=sheets(properties(title,index))" 2>"$errf")"; then
    tab="$(printf '%s' "$meta" | python3 -c 'import json,sys; print(json.load(sys.stdin)["sheets"][0]["properties"]["title"])')"
  elif sheets_api_disabled; then
    kind="csv"
  else
    cat "$errf" >&2; exit 1
  fi
fi

if [[ "$kind" == "api" ]]; then
  a1="'${tab//\'/\'\'}'${range:+!$range}"
  enc="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$a1")"
  if ! gapi GET "$SHEETS_API/spreadsheets/$id/values/$enc?valueRenderOption=FORMATTED_VALUE" >"$tmpf" 2>"$errf"; then
    sheets_api_disabled && kind="csv" || { cat "$errf" >&2; exit 1; }
  fi
fi

if [[ "$kind" == "csv" ]]; then
  if [[ -n "$tab" || -n "$range" ]]; then
    { echo "sheet_read: el API de Sheets está deshabilitado en el proyecto OAuth, y el fallback"
      echo "CSV (Drive export) solo alcanza la PRIMERA pestaña, sin --tab/--range."
      echo "Habilita sheets.googleapis.com en el proyecto de Google Cloud para el modo completo."; } >&2
    exit 1
  fi
  echo "sheet_read: Sheets API deshabilitado — usando Drive export CSV (primera pestaña)" >&2
  gapi GET "$DRIVE_API/files/$id/export" --get --data-urlencode "mimeType=text/csv" >"$tmpf"
fi

if (( raw )); then
  if [[ "$kind" == "api" ]]; then python3 -m json.tool "$tmpf"; else cat "$tmpf"; fi
  exit 0
fi

python3 - "$FORMAT" "$limit" "$tmpf" "$kind" <<'PY'
import csv, json, sys
fmt, limit, path, kind = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
if kind == "api":
    values = json.load(open(path)).get("values", [])
else:
    values = [list(r) for r in csv.reader(open(path, newline=""))]
if not values:
    print("[]" if fmt == "json" else "(hoja vacía)")
    sys.exit()
header = [h.strip() or f"col{i+1}" for i, h in enumerate(values[0])]
data = values[1:]
total = len(data)
if limit > 0:
    data = data[:limit]
rows = [{header[i]: (r[i] if i < len(r) else "") for i in range(len(header))} for r in data]

if fmt == "json":
    print(json.dumps(rows, indent=2, ensure_ascii=False))
    sys.exit()
disp = [[str(r.get(h, "")).replace("\n", " ") for h in header] for r in rows]
disp = [[c[:38] + "…" if len(c) > 39 else c for c in row] for row in disp]
w = [max(len(header[i]), *(len(row[i]) for row in disp)) if disp else len(header[i]) for i in range(len(header))]
print("  ".join(header[i].ljust(w[i]) for i in range(len(header))))
print("  ".join("-" * w[i] for i in range(len(header))))
for row in disp:
    print("  ".join(row[i].ljust(w[i]) for i in range(len(header))))
extra = f", mostrando {len(rows)}" if len(rows) < total else ""
print(f"({total} filas{extra})")
PY

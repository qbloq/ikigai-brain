#!/usr/bin/env bash
# sheet_read.sh <id|url> [--limit N] [--raw] [--json]
#
# Read-only. Values of one Google Sheet via the mkt API — el backend exporta
# la PRIMERA pestaña como CSV (GET /drive/files/:id/content). Rendered as an
# aligned table treating row 1 as the header. --limit caps data rows (default
# 50; 0 = no cap). --json emits an array of objects keyed by the header row;
# --raw emits the CSV untouched.
#
# --tab/--range: no disponibles vía el backend (exporta la primera pestaña).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/common.sh"

ref=""; limit=50; raw=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tab|--range)
      { echo "sheet_read: --tab/--range no están disponibles vía el backend (exporta la"
        echo "primera pestaña como CSV). Pídelo a Meetico si lo necesitas."; } >&2
      exit 1;;
    --limit) limit="$2"; shift 2;;
    --raw) raw=1; shift;;
    --json) FORMAT=json; shift;;
    -h|--help) sed -n '2,10p' "$0"; exit 0;;
    *) ref="$1"; shift;;
  esac
done
[[ -z "$ref" ]] && { echo "usage: sheet_read.sh <id|url> [--limit N] [--raw] [--json]" >&2; exit 1; }
id="$(gid "$ref")"

tmpf="$(mktemp)"; trap 'rm -f "$tmpf"' EXIT
mapi GET "/drive/files/$id/content" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if not d.get("exists", True):
    sys.stderr.write("sheet_read: el archivo no existe o no es accesible\n"); sys.exit(1)
if d.get("content_text") is None:
    sys.stderr.write("sheet_read: sin contenido extraible (mime: %s)\n" % d.get("mime", "?")); sys.exit(1)
sys.stdout.write(d["content_text"])' > "$tmpf"

if (( raw )); then
  cat "$tmpf"
  exit 0
fi

python3 - "$FORMAT" "$limit" "$tmpf" <<'PY'
import csv, json, sys
fmt, limit, path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
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

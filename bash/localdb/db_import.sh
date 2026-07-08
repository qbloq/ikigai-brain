#!/usr/bin/env bash
# WRITE: import a CSV file (header row expected) into a table of one LOCAL
# SQLite database. New table → created from the header; existing table →
# appended (header skipped); --replace drops it first. One transaction.
#
# Usage: db_import.sh <db> <file.csv> [--table T] [--replace] [--create] [--dry-run] [--json]
#   <db>        db name in data/sqlite/ (no path, .db optional)
#   <file.csv>  path to the CSV (first row = column names)
#   --table T   target table (default: the file's basename, sanitized)
#   --replace   DROP the table first (full reload instead of append)
#   --create    allow creating the .db file if it doesn't exist yet
#   --dry-run   import, report counts, then ROLLBACK
#   --json      {ok, db, table, rows_before, rows_after, imported, dry_run}
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"

db="" csv="" tbl="" replace=0 create=0 dry=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --table) tbl="$2"; shift 2 ;;
    --replace) replace=1; shift ;;
    --create) create=1; shift ;;
    --dry-run) dry=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) if [[ -z "$db" ]]; then db="$1"; else csv="$1"; fi; shift ;;
  esac
done
[[ -n "$db" && -n "$csv" ]] || { echo "Usage: db_import.sh <db> <file.csv> [--table T] [--replace] [--create] [--dry-run] [--json]" >&2; exit 2; }
[[ -f "$csv" ]] || { echo "No existe el archivo: $csv" >&2; exit 1; }
csv="$(realpath "$csv")"
[[ "$csv" != *'"'* ]] || { echo "La ruta del CSV no puede contener comillas dobles" >&2; exit 2; }

if [[ -z "$tbl" ]]; then
  tbl="$(basename "$csv")"; tbl="${tbl%.*}"; tbl="$(printf '%s' "$tbl" | tr -c 'A-Za-z0-9_' '_')"
fi
[[ "$tbl" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "Nombre de tabla inválido: '$tbl'" >&2; exit 2; }

if [[ "$create" == 1 ]]; then
  p="$(db_path "$db")"
  mkdir -p "$LOCALDB_DIR"
else
  p="$(require_db "$db")"
fi

exists="$(sqlite_ro "$p" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name = $(sql_str "$tbl");" 2>/dev/null || echo 0)"
before=0
if [[ "$exists" == "1" && "$replace" == 0 ]]; then
  before="$(sqlite_ro "$p" "SELECT count(*) FROM $(sql_ident "$tbl");")"
fi

drop=""; [[ "$replace" == 1 && "$exists" == "1" ]] && drop="DROP TABLE $(sql_ident "$tbl");"
# .import creates the table from the header when it doesn't exist; when it
# does, --skip 1 drops the header row. Both are plain INSERTs → transactional.
skip=""; [[ "$exists" == "1" && "$replace" == 0 ]] && skip="--skip 1 "
final="COMMIT"; [[ "$dry" == 1 ]] && final="ROLLBACK"

out="$(sqlite_rw "$p" <<SQL
BEGIN;
$drop
.import --csv ${skip}"$csv" $tbl
SELECT '__after=' || count(*) FROM $(sql_ident "$tbl");
$final;
SQL
)"
after="$(printf '%s\n' "$out" | sed -n 's/^__after=//p' | tail -1)"
imported=$(( ${after:-0} - before ))

if [[ "$FORMAT" == "json" ]]; then
  printf '{"ok":true,"db":"%s","table":"%s","rows_before":%s,"rows_after":%s,"imported":%s,"dry_run":%s}\n' \
    "${db%.db}" "$tbl" "$before" "${after:-0}" "$imported" "$([[ $dry == 1 ]] && echo true || echo false)"
else
  echo "OK: $imported fila(s) importada(s) a '${db%.db}'.$tbl ($before → ${after:-0})$([[ $dry == 1 ]] && echo ' — DRY RUN, rollback')"
fi

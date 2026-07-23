#!/usr/bin/env bash
# Show the schema of one local SQLite database: every table/view with its
# columns (name, type, pk, notnull) and row count.
#
# Usage: db_schema.sh <db> [--table T] [--json]
#   <db>       db name in data/sqlite/ (no path, .db optional)
#   --table T  only this table/view
#   --json     [{table, rows, columns:[{name,type,notnull,pk}]}]
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"

db="" only=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --table) only="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) db="$1"; shift ;;
  esac
done
[[ -n "$db" ]] || { echo "Usage: db_schema.sh <db> [--table T] [--json]" >&2; exit 2; }
p="$(require_db "$db")"

tables() {
  if [[ -n "$only" ]]; then
    sqlite_ro "$p" "SELECT name FROM sqlite_master WHERE type IN ('table','view') AND name = $(sql_str "$only");" | grep . \
      || { echo "La tabla '$only' no existe en '$db'" >&2; exit 1; }
  else
    sqlite_ro "$p" "$TABLES_SQL;"
  fi
}

if [[ "$FORMAT" == "json" ]]; then
  out=""
  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    rows="$(sqlite_ro "$p" "SELECT count(*) FROM $(sql_ident "$t");" 2>/dev/null)" || rows="null"
    item="$(sqlite_ro "$p" "SELECT json_object(
      'table', $(sql_str "$t"),
      'rows', ${rows:-null},
      'columns', (SELECT json_group_array(json_object(
                    'name', name, 'type', type, 'notnull', \"notnull\", 'pk', pk))
                  FROM pragma_table_info($(sql_str "$t"))));")"
    out+="${out:+,}$item"
  done < <(tables)
  printf '[%s]\n' "$out"
else
  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    rows="$(sqlite_ro "$p" "SELECT count(*) FROM $(sql_ident "$t");" 2>/dev/null)" || rows="?"
    echo "== $t ($rows filas)"
    sqlite_ro "$p" -cmd ".mode column" -cmd ".headers on" \
      "SELECT name, type, \"notnull\", pk FROM pragma_table_info($(sql_str "$t"));"
    echo
  done < <(tables)
fi

#!/usr/bin/env bash
# Print the rows of ONE table/view of a local SQLite database. The table name
# is validated against sqlite_master (exact match) and identifier-quoted, so
# nothing arbitrary ever becomes SQL — this is the viz `localdb_table` source.
#
# Usage: db_table.sh <db> <table> [--limit N] [--json]
#   --limit N  cap rows (default 500; 0 = no cap)
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"

db="" tbl="" limit=500
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) limit="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) if [[ -z "$db" ]]; then db="$1"; else tbl="$1"; fi; shift ;;
  esac
done
[[ -n "$db" && -n "$tbl" ]] || { echo "Usage: db_table.sh <db> <table> [--limit N] [--json]" >&2; exit 2; }
[[ "$limit" =~ ^[0-9]+$ ]] || { echo "--limit must be a number" >&2; exit 2; }
p="$(require_db "$db")"

exists="$(sqlite_ro "$p" "SELECT count(*) FROM sqlite_master WHERE type IN ('table','view') AND name = $(sql_str "$tbl");")"
if [[ "$exists" != "1" ]]; then
  { echo "La tabla '$tbl' no existe en '$db'"
    echo "Tablas: $(sqlite_ro "$p" "$TABLES_SQL;" | paste -sd, -)"; } >&2
  exit 1
fi

lim=""; [[ "$limit" -gt 0 ]] && lim=" LIMIT $limit"
q="SELECT * FROM $(sql_ident "$tbl")$lim;"
if [[ "$FORMAT" == "json" ]]; then
  json_or_empty "$(sqlite_ro "$p" -json "$q")"
else
  sqlite_ro "$p" -cmd ".mode column" -cmd ".headers on" "$q"
fi

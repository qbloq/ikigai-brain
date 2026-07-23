#!/usr/bin/env bash
# Run a read-only SQL query against one LOCAL SQLite database. The connection
# is opened read-only + safe mode, so writes and shell dot-commands are
# rejected by the engine — inline SQL is fine here (it's the user's own local
# data, and nothing can mutate). Contrast with run_io_query.sh, which serves
# the shared Postgres and therefore only runs SQL already persisted in a DB
# row; when the viz uses THIS script (`localdb_query` source), the query comes
# from the saved UI spec, never from the browser.
#
# Usage: db_query.sh <db> [SQL|-] [--limit N] [--json]
#   <db>       db name in data/sqlite/ (no path, .db optional)
#   SQL | -    the query; '-' (or nothing piped) reads it from stdin
#   --limit N  cap rows by wrapping in a subquery (default 500; 0 = raw query,
#              use it for PRAGMA/EXPLAIN or multi-statement scripts)
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"

db="" sql_arg="" limit=500
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) limit="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    --) shift ;;
    -) sql_arg="-"; shift ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) if [[ -z "$db" ]]; then db="$1"; else sql_arg="$1"; fi; shift ;;
  esac
done
[[ -n "$db" ]] || { echo "Usage: db_query.sh <db> [SQL|-] [--limit N] [--json]" >&2; exit 2; }
[[ "$limit" =~ ^[0-9]+$ ]] || { echo "--limit must be a number" >&2; exit 2; }
p="$(require_db "$db")"

q="$(read_sql "$sql_arg")"
[[ -n "${q// /}" ]] || { echo "Falta el SQL (argumento o stdin)" >&2; exit 2; }
reject_dotcmds "$q"
q="$(strip_trailing_semi "$q")"

[[ "$limit" -gt 0 ]] && q="SELECT * FROM (
$q
) LIMIT $limit"

if [[ "$FORMAT" == "json" ]]; then
  json_or_empty "$(sqlite_ro "$p" -json "$q;")"
else
  sqlite_ro "$p" -cmd ".mode column" -cmd ".headers on" "$q;"
fi

#!/usr/bin/env bash
# WRITE: execute SQL (DDL/DML) against one LOCAL SQLite database, in ONE
# transaction. This is how a local db is created, filled and evolved — and the
# hook for external syncs (a cron/script pipes INSERTs here). Local dbs only:
# it can't touch Postgres.
#
# Usage: db_exec.sh <db> [SQL|-] [--create] [--dry-run] [--json]
#   <db>       db name in data/sqlite/ (no path, .db optional)
#   SQL | -    the statements; '-' (or nothing) reads them from stdin
#   --create   allow creating the .db file if it doesn't exist yet
#   --dry-run  run everything, report changes, then ROLLBACK
#   --json     {ok, db, changes, tables, dry_run}
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"

db="" sql_arg="" create=0 dry=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --create) create=1; shift ;;
    --dry-run) dry=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    --) shift ;;
    -) sql_arg="-"; shift ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) if [[ -z "$db" ]]; then db="$1"; else sql_arg="$1"; fi; shift ;;
  esac
done
[[ -n "$db" ]] || { echo "Usage: db_exec.sh <db> [SQL|-] [--create] [--dry-run] [--json]" >&2; exit 2; }

if [[ "$create" == 1 ]]; then
  p="$(db_path "$db")"
  mkdir -p "$LOCALDB_DIR"
else
  p="$(require_db "$db")"
fi

q="$(read_sql "$sql_arg")"
[[ -n "${q// /}" ]] || { echo "Falta el SQL (argumento o stdin)" >&2; exit 2; }
reject_dotcmds "$q"
q="$(strip_trailing_semi "$q")"

final="COMMIT"; [[ "$dry" == 1 ]] && final="ROLLBACK"
# -bail (in sqlite_rw) stops at the first failing statement; the process exits
# without COMMIT, so a partial transaction is never persisted.
out="$(sqlite_rw "$p" <<SQL
BEGIN;
$q;
SELECT '__changes=' || total_changes();
$final;
SQL
)"
changes="$(printf '%s\n' "$out" | sed -n 's/^__changes=//p' | tail -1)"
tables="$(sqlite_ro "$p" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';" 2>/dev/null || echo 0)"
# Rest of the output (any user SELECTs) passes through in table mode.
user_out="$(printf '%s\n' "$out" | grep -v '^__changes=' || true)"

if [[ "$FORMAT" == "json" ]]; then
  printf '{"ok":true,"db":"%s","changes":%s,"tables":%s,"dry_run":%s}\n' \
    "${db%.db}" "${changes:-0}" "$tables" "$([[ $dry == 1 ]] && echo true || echo false)"
else
  [[ -n "$user_out" ]] && printf '%s\n' "$user_out"
  echo "OK: ${changes:-0} fila(s) afectada(s) en '${db%.db}' ($tables tabla(s))$([[ $dry == 1 ]] && echo ' — DRY RUN, rollback')"
fi

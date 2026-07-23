#!/usr/bin/env bash
# Execute the SQL persisted in one IO row's artifact binding (reference.query)
# and print its result — the concrete DATA of a "SQL Results" artifact. This is
# the sql resolver: an input/output typed sql_query IS its query's result set.
#
# Read-only by policy (psql_ro) plus its own guardrails: statement_timeout 10s
# and a row cap. Only runs SQL with provenance — the query must already live in
# the DB row (persisted via update_task_io.sh --ref-merge); nothing inline.
#
# Usage: run_io_query.sh <io_id|prefix> [--limit N] [--json]
#   <io_id>    task_inputs.id or task_outputs.id (uuid or prefix)
#   --limit N  cap rows (default 500; 0 = no cap)
#   --json     emit a JSON array of rows (what the viz io_query source consumes)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

io="" limit=500
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) limit="$2"; shift 2 ;;
    --json)  FORMAT=json; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) io="$1"; shift ;;
  esac
done
[[ -n "$io" ]] || { echo "Usage: run_io_query.sh <io_id|prefix> [--limit N] [--json]" >&2; exit 2; }
[[ "$limit" =~ ^[0-9]+$ ]] || { echo "--limit must be a number" >&2; exit 2; }

esc="${io//\'/\'\'}"
query="$(psql_ro -t -A -c "
  SELECT coalesce(
    (SELECT artifact_reference->>'query'    FROM task_inputs  WHERE id::text LIKE '${esc}%' LIMIT 1),
    (SELECT deliverable_reference->>'query' FROM task_outputs WHERE id::text LIKE '${esc}%' LIMIT 1)
  );")"
if [[ -z "$query" ]]; then
  echo "El IO '$io' no existe o no tiene un query SQL vinculado (reference.query)" >&2
  exit 1
fi
# Strip trailing whitespace and the final semicolon so the query can be wrapped.
query="$(printf '%s' "$query" | sed -e 's/[[:space:]]*$//')"
query="${query%;}"

lim=""; [[ "$limit" -gt 0 ]] && lim="LIMIT $limit"
if [[ "$FORMAT" == "json" ]]; then
  PGOPTIONS="$PGOPTIONS -c statement_timeout=10s" psql_ro -t -A <<SQL
SELECT coalesce(json_agg(row_to_json(_q)), '[]'::json)
FROM (SELECT * FROM (
$query
) _raw $lim) _q;
SQL
else
  PGOPTIONS="$PGOPTIONS -c statement_timeout=10s" psql_ro <<SQL
SELECT * FROM (
$query
) _raw $lim;
SQL
fi

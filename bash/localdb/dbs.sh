#!/usr/bin/env bash
# List the user's local SQLite databases (data/sqlite/*.db): name, size,
# last-modified and tables with row counts.
#
# Usage: dbs.sh [--json]
#   --json   [{db, size_kb, modified, tables:[{name, rows}]}] — what the viz
#            `localdbs` source (and its explorer page) consumes in one fetch.
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ "$FORMAT" == "json" ]]; then
  out=""
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    p="$LOCALDB_DIR/$name.db"
    size_kb=$(( ($(stat -c %s "$p") + 1023) / 1024 ))
    modified="$(date -r "$p" +%Y-%m-%dT%H:%M)"
    tables="$(tables_json "$p")"
    # name is regex-validated ([A-Za-z0-9_-]) → safe to printf into JSON.
    out+="${out:+,}$(printf '{"db":"%s","size_kb":%s,"modified":"%s","tables":%s}' "$name" "$size_kb" "$modified" "$tables")"
  done < <(list_db_names)
  printf '[%s]\n' "$out"
else
  names="$(list_db_names)"
  if [[ -z "$names" ]]; then
    echo "No hay bases locales en $LOCALDB_DIR"
    echo "Crea una con: bash/localdb/db_exec.sh <nombre> --create 'CREATE TABLE …'"
    exit 0
  fi
  printf '%-28s %8s %8s  %-16s %s\n' "db" "tablas" "KB" "modificada" "tablas (filas)"
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    p="$LOCALDB_DIR/$name.db"
    size_kb=$(( ($(stat -c %s "$p") + 1023) / 1024 ))
    modified="$(date -r "$p" +'%Y-%m-%d %H:%M')"
    detail=""
    n=0
    while IFS= read -r t; do
      [[ -n "$t" ]] || continue
      rows="$(sqlite_ro "$p" "SELECT count(*) FROM $(sql_ident "$t");" 2>/dev/null)" || rows="?"
      detail+="${detail:+, }$t($rows)"
      n=$((n + 1))
    done < <(sqlite_ro "$p" "$TABLES_SQL;")
    printf '%-28s %8s %8s  %-16s %s\n' "$name" "$n" "$size_kb" "$modified" "$detail"
  done <<< "$names"
fi

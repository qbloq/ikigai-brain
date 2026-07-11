#!/usr/bin/env bash
# Common helpers for bash/localdb/ scripts — the user's LOCAL SQLite databases.
# Source this from any script: source "$(dirname "$0")/../lib/sqlite.sh"
#
# Deliberately independent of common.sh: local DBs must work without .env or
# any Postgres connectivity. Same conventions otherwise (FORMAT/--json, set -e).
#
# Policy mirror of the Postgres layer:
#   sqlite_ro  — read-only connection (-readonly -safe), the default
#   sqlite_rw  — writable connection; WRITE scripts opt in explicitly
# All databases live in ONE whitelisted directory (data/sqlite/, git-ignored;
# override with LOCALDB_DIR). Scripts accept db *names*, never paths.
set -euo pipefail

SQLITE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SQLITE_LIB_DIR/../.." && pwd)"
LOCALDB_DIR="${LOCALDB_DIR:-$REPO_ROOT/data/sqlite}"

FORMAT="${FORMAT:-table}"

command -v sqlite3 >/dev/null || { echo "sqlite3 no está instalado" >&2; exit 1; }

# db_path <name> : validates a db NAME (no paths — [A-Za-z0-9_-], optional .db
# suffix stripped) and echoes its absolute path under LOCALDB_DIR.
db_path() {
  local name="${1%.db}"
  if [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
    echo "Nombre de base inválido: '$1' (usa letras/números/_/-, sin rutas)" >&2
    return 2
  fi
  printf '%s/%s.db\n' "$LOCALDB_DIR" "$name"
}

# require_db <name> : db_path + existence check; lists available DBs on miss.
require_db() {
  local p
  p="$(db_path "$1")" || return 2
  if [[ ! -f "$p" ]]; then
    { echo "La base '${1%.db}' no existe en $LOCALDB_DIR"
      echo "Disponibles: $(list_db_names | paste -sd, -)"
      echo "Créala con: bash/localdb/db_exec.sh ${1%.db} --create 'CREATE TABLE …'"; } >&2
    return 1
  fi
  printf '%s\n' "$p"
}

# list_db_names : one db name per line (empty if the dir doesn't exist yet).
list_db_names() {
  [[ -d "$LOCALDB_DIR" ]] || return 0
  find "$LOCALDB_DIR" -maxdepth 1 -name '*.db' -printf '%f\n' 2>/dev/null | sed 's/\.db$//' | sort
}

# sqlite_ro <db_path> [sql] : read-only + safe mode (no .shell/.import/ATTACH),
# 3s busy timeout. The engine itself rejects writes (mode=ro at open).
sqlite_ro() {
  local p="$1"; shift
  sqlite3 -readonly -safe -bail -cmd ".timeout 3000" "$p" "$@"
}

# sqlite_rw <db_path> [sql] : writable connection for WRITE scripts. -bail stops
# at the first error, so an open transaction dies uncommitted (auto-rollback).
sqlite_rw() {
  local p="$1"; shift
  sqlite3 -bail -cmd ".timeout 3000" "$p" "$@"
}

# reject_dotcmds <sql> : refuse input containing sqlite3 shell dot-commands
# (.shell, .output, …). We only ever accept SQL, never shell-script lines.
reject_dotcmds() {
  if printf '%s\n' "$1" | grep -Eq '^[[:space:]]*\.'; then
    echo "Solo se acepta SQL — los comandos punto (.import, .shell, …) no están permitidos" >&2
    return 2
  fi
}

# read_sql <arg> : SQL from the positional arg, or stdin when it's '-'/empty.
read_sql() {
  local arg="${1:-}"
  if [[ -z "$arg" || "$arg" == "-" ]]; then cat; else printf '%s' "$arg"; fi
}

# strip_trailing_semi <sql> : trailing whitespace + final ';' removed, so the
# query can be wrapped in a LIMIT subquery (same trick as run_io_query.sh).
strip_trailing_semi() {
  local q
  q="$(printf '%s' "$1" | sed -e 's/[[:space:]]*$//')"
  printf '%s' "${q%;}"
}

# sql_ident <name> / sql_str <val> : SQL identifier / string-literal quoting.
sql_ident() { printf '"%s"' "${1//\"/\"\"}"; }
sql_str()   { printf "'%s'" "${1//\'/\'\'}"; }

TABLES_SQL="SELECT name FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY name"

# tables_json <db_path> : JSON array [{name, rows}] of the db's tables/views
# (rows = null when a count fails, e.g. a view over a dropped table). All JSON
# is composed by SQLite itself (json_object), never by string-pasting names.
tables_json() {
  local p="$1" t rows item items=""
  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    rows="$(sqlite_ro "$p" "SELECT count(*) FROM $(sql_ident "$t");" 2>/dev/null)" || rows="null"
    item="$(sqlite_ro "$p" "SELECT json_object('name',$(sql_str "$t"),'rows',${rows:-null});")"
    items+="${items:+,}$item"
  done < <(sqlite_ro "$p" "$TABLES_SQL;")
  printf '[%s]' "$items"
}

# json_or_empty <output> : sqlite3 -json prints NOTHING for zero rows — normalize to [].
json_or_empty() { printf '%s\n' "${1:-[]}"; }

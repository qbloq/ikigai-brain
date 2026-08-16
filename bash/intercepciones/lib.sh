#!/usr/bin/env bash
# Helpers del dominio intercepciones — la sqlite del interceptor
# (data/sqlite/intercepciones.db). LOCAL-FIRST: si la db existe en este
# checkout (caso servidor api, donde escriben el hook y el cron) se usa
# sqlite3 directo; si no, por ssh al servidor (caso cerebro). El SQL viaja
# SIEMPRE por stdin — jamás en el argv del remoto. Patrón: bash/publicar/lib.sh.
set -euo pipefail
INT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$INT_LIB_DIR/../.." && pwd)"

INT_SSH="${INTERCEPCIONES_SSH:-root@api}"
INT_DIR="${INTERCEPCIONES_DIR:-/apps/hermetico}"
INT_DB_LOCAL="${INTERCEPCIONES_DB:-$REPO_ROOT/data/sqlite/intercepciones.db}"
INT_DB_REMOTA="$INT_DIR/data/sqlite/intercepciones.db"

# sql_lit <v> : literal SQL con comillas escapadas.
sql_lit() { printf "'%s'" "${1//\'/\'\'}"; }

# int_es_local : ¿la db vive en este checkout? (el override INTERCEPCIONES_DB
# también cuenta como local — así los tests apuntan a un archivo temporal).
int_es_local() { [[ -n "${INTERCEPCIONES_DB:-}" || -f "$INT_DB_LOCAL" ]]; }

# int_sql [-json] : ejecuta el SQL de stdin en la db del interceptor.
int_sql() {
  local flags=(); [[ "${1:-}" == "-json" ]] && flags=(-json)
  if int_es_local; then
    mkdir -p "$(dirname "$INT_DB_LOCAL")"
    sqlite3 "${flags[@]}" "$INT_DB_LOCAL"
  else
    ssh "$INT_SSH" "mkdir -p '$INT_DIR/data/sqlite' && sqlite3 ${flags[*]:-} '$INT_DB_REMOTA'"
  fi
}

# ensure_schema : aplica el DDL idempotente (silencioso: WAL responde «wal»).
ensure_schema() { int_sql < "$INT_LIB_DIR/schema.sql" >/dev/null; }

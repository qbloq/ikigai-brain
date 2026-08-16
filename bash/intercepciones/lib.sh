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
# También es local si estamos parados en el checkout del servidor ($REPO_ROOT == $INT_DIR).
int_es_local() { [[ -n "${INTERCEPCIONES_DB:-}" || -f "$INT_DB_LOCAL" || "$REPO_ROOT" == "$INT_DIR" ]]; }

# int_sql [-json] : ejecuta el SQL de stdin en la db del interceptor.
# Antepone PRAGMA foreign_keys=ON a cada conexión para enforcement de FK.
# -bail: sin él el CLI de sqlite3 IMPRIME el error y SIGUE, así que una txn
# con un statement fallido comitea a medias — y bajo concurrencia un
# (SELECT max(id) FROM …) colgaría filas de la corrida de otro proceso.
# -cmd '.timeout 5000': busy timeout de 5 s — el hook (viz/hooks.js) y el cron
# escriben la MISMA db, y sin esto el segundo muere al instante con
# «database is locked» en vez de esperar el fsync del otro. Va como dot-command
# y NO como PRAGMA a propósito: `PRAGMA busy_timeout=5000` IMPRIME su valor
# (con -json, un `[{"timeout":5000}]` extra que rompe a quien parsea stdout);
# `.timeout` es silencioso.
int_sql() {
  local flags=(); [[ "${1:-}" == "-json" ]] && flags=(-json)
  if int_es_local; then
    mkdir -p "$(dirname "$INT_DB_LOCAL")"
    { printf 'PRAGMA foreign_keys=ON;\n'; cat; } | sqlite3 -bail -cmd '.timeout 5000' "${flags[@]}" "$INT_DB_LOCAL"
  else
    ssh "$INT_SSH" "mkdir -p '$INT_DIR/data/sqlite' && { printf 'PRAGMA foreign_keys=ON;\n'; cat; } | sqlite3 -bail -cmd '.timeout 5000' ${flags[*]:-} '$INT_DB_REMOTA'"
  fi
}

# ensure_schema : aplica el DDL idempotente (silencioso: WAL responde «wal»).
ensure_schema() { int_sql < "$INT_LIB_DIR/schema.sql" >/dev/null; }

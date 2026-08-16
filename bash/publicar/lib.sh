#!/usr/bin/env bash
# Helpers del dominio publicar — operan el registro REMOTO del publicador
# (viz/publish.js) por ssh. El sql viaja por stdin (jamás argv del remoto).
set -euo pipefail
PUBLICAR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$PUBLICAR_LIB_DIR/../.." && pwd)"

PUB_SSH="${PUBLICAR_SSH:-root@api}"
PUB_DIR="${PUBLICAR_DIR:-/apps/hermetico}"
PUB_DB="$PUB_DIR/data/sqlite/publicaciones.db"
PUB_URL="${PUBLICAR_URL:-https://app.ikigaigm.parallelo.ai}"

# sql_lit <v> : literal SQL con comillas escapadas.
sql_lit() { printf "'%s'" "${1//\'/\'\'}"; }

# remote_sql [-json] : ejecuta el SQL de stdin en el registro remoto.
remote_sql() {
  local flags=(); [[ "${1:-}" == "-json" ]] && flags=(-json)
  ssh "$PUB_SSH" "mkdir -p '$PUB_DIR/data/sqlite' && sqlite3 ${flags[*]:-} '$PUB_DB'"
}

# ensure_schema : aplica el schema idempotente antes de cualquier escritura.
ensure_schema() { remote_sql < "$PUBLICAR_LIB_DIR/schema.sql"; }

# spec_local <id> : el spec JSON (una línea) desde el store del viz, o falla.
spec_local() {
  node -e '
    const s = require(process.argv[1] + "/viz/lib/store").get(process.argv[2]);
    if (!s) { console.error("Spec no encontrado: " + process.argv[2]); process.exit(1); }
    const { _layer, _file, ...clean } = s;
    console.log(JSON.stringify(clean));
  ' "$REPO_ROOT" "$1"
}

# validar_spec <json> : validateSpec del viz; imprime errores y falla si hay.
validar_spec() {
  node -e '
    const v = require(process.argv[1] + "/viz/lib/components").validateSpec(JSON.parse(process.argv[2]));
    for (const e of v.errors) console.error("ERROR: " + e);
    if (v.errors.length) process.exit(1);
  ' "$REPO_ROOT" "$1"
}

# codigo_nuevo : 10 chars base62 aleatorios.
codigo_nuevo() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c 10; }

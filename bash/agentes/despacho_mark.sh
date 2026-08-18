#!/usr/bin/env bash
# [WRITE local] Marca UNA fila de la cola de despacho: aprobar o rechazar.
# Es el único write detrás del botón de la Mesa de Despacho (patrón
# cruce_mark.sh). Guardrail: solo filas 'pendiente' se pueden marcar; las
# demás documentan una decisión y se congelan.
#
# Usage: despacho_mark.sh <n> (--aprobar | --rechazar) [--nota "…"] [--json]
set -euo pipefail
cd "$(dirname "$0")/../.."
source bash/lib/sqlite.sh

N=""; ACCION=""; NOTA=""; FORMAT=text
while [[ $# -gt 0 ]]; do
  case "$1" in
    --aprobar)  ACCION=aprobado; shift ;;
    --rechazar) ACCION=rechazado; shift ;;
    --nota) NOTA="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) [[ -z "$N" ]] && N="$1" || { echo "Unknown arg: $1" >&2; exit 2; }; shift ;;
  esac
done

[[ "$N" =~ ^[0-9]+$ ]] || { echo "Falta <n> numérico (columna n de despachos.sh)" >&2; exit 2; }
[[ -n "$ACCION" ]] || { echo "Falta --aprobar o --rechazar" >&2; exit 2; }

DB="$LOCALDB_DIR/mesa_despacho.db"
[[ -f "$DB" ]] || { echo "No existe $DB" >&2; exit 1; }

estado="$(sqlite3 -readonly "$DB" "SELECT estado FROM despachos WHERE n=$N;")"
[[ -n "$estado" ]] || { echo "No existe la fila n=$N" >&2; exit 1; }
if [[ "$estado" != "pendiente" ]]; then
  echo "Guardrail: la fila n=$N ya está '$estado' — las decisiones tomadas se congelan." >&2
  exit 1
fi

sqlite_rw "$DB" "UPDATE despachos SET estado=$(sql_str "$ACCION"), nota=$(sql_str "$NOTA"), marcado_at=datetime('now','localtime') WHERE n=$N AND estado='pendiente';"

if [[ "$FORMAT" == "json" ]]; then
  sqlite3 -readonly -json "$DB" "SELECT n, substr(recado_id,1,8) recado, estado, nota, para, que FROM despachos WHERE n=$N;"
else
  sqlite3 -readonly -header -column "$DB" "SELECT n, substr(recado_id,1,8) recado, estado, nota FROM despachos WHERE n=$N;"
fi

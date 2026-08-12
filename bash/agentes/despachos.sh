#!/usr/bin/env bash
# La cola de despacho del cerebro (sqlite local `mesa_despacho`): cada recado
# cosechado con su ESTADO (pendiente|aprobado|rechazado|ejecutado|fallido).
# READ-ONLY — las marcas se hacen con despacho_mark.sh, la ejecución con
# despachar.sh.
#
# Usage: despachos.sh [--estado E] [--limit N] [--json]
#   --json  [{n,recado_id,fecha,de,para,que,urgencia,contexto,propuesta,
#             estado,nota,destino_numero,ejecutado_at}] — fuente viz `iki_despachos`.
set -euo pipefail
cd "$(dirname "$0")/../.."
source bash/lib/sqlite.sh

FORMAT=text; ESTADO=""; LIMIT=100
while [[ $# -gt 0 ]]; do
  case "$1" in
    --estado) ESTADO="$2"; shift 2 ;;
    --limit)  LIMIT="$2"; shift 2 ;;
    --json)   FORMAT=json; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ "$LIMIT" =~ ^[0-9]+$ ]] || { echo "--limit debe ser numérico" >&2; exit 2; }
[[ -z "$ESTADO" || "$ESTADO" =~ ^[a-z]+$ ]] || { echo "--estado inválido" >&2; exit 2; }

DB="$LOCALDB_DIR/mesa_despacho.db"
[[ -f "$DB" ]] || { echo "No existe $DB — corre sync_despachos.sh primero" >&2; exit 1; }

WHERE=""; [[ -n "$ESTADO" ]] && WHERE="WHERE estado = '$ESTADO'"
LIM=""; [[ "$LIMIT" != "0" ]] && LIM="LIMIT $LIMIT"
SQL="SELECT n, substr(recado_id,1,8) AS recado, fecha_recado AS fecha, de, para,
            que, urgencia, contexto, propuesta, estado, coalesce(nota,'') AS nota,
            coalesce(destino_numero,'') AS destino_numero,
            coalesce(ejecutado_at,'') AS ejecutado_at
     FROM despachos $WHERE
     ORDER BY (estado='pendiente') DESC, (estado='aprobado') DESC, fecha_recado DESC $LIM;"

if [[ "$FORMAT" == "json" ]]; then
  out="$(sqlite3 -readonly -json "$DB" "$SQL" 2>/dev/null)" || out=""
  printf '%s\n' "${out:-[]}"
else
  sqlite3 -readonly -header -column "$DB" "SELECT n, substr(recado_id,1,8) recado, estado, de, para, substr(que,1,44) que, urgencia FROM despachos $WHERE ORDER BY (estado='pendiente') DESC, fecha_recado DESC $LIM;"
fi

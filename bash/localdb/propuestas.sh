#!/usr/bin/env bash
# Las propuestas de tareas cargadas en la sqlite local `propuestas_reuniones`
# como filas (todas las columnas + lote_nombre/lote_fecha/meeting_corto).
# READ-ONLY. Fuente viz `propuestas`. Los campos json (asignados, slots,
# relacionadas, depende_de, contrato) viajan como STRING json.
#
# Usage: propuestas.sh [--lote M] [--seccion A|B] [--decision entra|se_queda|pendiente] [--json]
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"
LOTE=""; SEC=""; DEC=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lote) LOTE="$2"; shift 2 ;;
    --seccion) SEC="$2"; shift 2 ;;
    --decision) DEC="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$SEC" || "$SEC" =~ ^[AB]$ ]] || { echo "--seccion A|B" >&2; exit 2; }
[[ -z "$DEC" || "$DEC" =~ ^(entra|se_queda|pendiente)$ ]] || { echo "--decision entra|se_queda|pendiente" >&2; exit 2; }
[[ -z "$LOTE" || "$LOTE" =~ ^[0-9a-f-]{8,36}$ ]] || { echo "--lote espera un id de reunión" >&2; exit 2; }
DBP="$(db_path propuestas_reuniones)"
[[ -f "$DBP" ]] || { [[ "$FORMAT" == json ]] && echo "[]" || echo "Sin lotes cargados todavía"; exit 0; }
w="1=1"
[[ -n "$LOTE" ]] && w="$w AND p.meeting_id LIKE $(sql_str "${LOTE:0:8}%")"
[[ -n "$SEC" ]] && w="$w AND p.seccion=$(sql_str "$SEC")"
[[ "$DEC" == pendiente ]] && w="$w AND p.decision IS NULL"
[[ "$DEC" =~ ^(entra|se_queda)$ ]] && w="$w AND p.decision=$(sql_str "$DEC")"
SQL="SELECT p.*, l.nombre AS lote_nombre, l.fecha AS lote_fecha, l.meeting_corto
     FROM propuestas p JOIN lotes l ON l.meeting_id=p.meeting_id
     WHERE $w ORDER BY l.fecha DESC, p.seccion, CAST(substr(p.ref,2) AS INTEGER)"
if [[ "$FORMAT" == json ]]; then out="$(sqlite_ro "$DBP" -json "$SQL;")"; printf '%s\n' "${out:-[]}"
else sqlite_ro "$DBP" -header -column "SELECT p.n, l.meeting_corto lote, p.ref, p.seccion s, substr(p.titulo,1,60) titulo, p.proyecto, p.prioridad, p.vence, coalesce(p.decision,'—') decision, substr(coalesce(p.creada_id,''),1,8) creada FROM propuestas p JOIN lotes l ON l.meeting_id=p.meeting_id WHERE $w ORDER BY l.fecha DESC, p.seccion, CAST(substr(p.ref,2) AS INTEGER);"; fi

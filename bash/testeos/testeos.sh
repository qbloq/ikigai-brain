#!/usr/bin/env bash
# testeos.sh — el HISTÓRICO de testeos del embudo, como filas. Read-only.
#
# El registro que la alineación DG 2026-08-19 pidió: cada testeo con sus
# métricas iniciales y finales congeladas (snapshots de bash/metrics/embudo.sh)
# y su desenlace. Las escrituras viven en testeo_abrir.sh / testeo_cerrar.sh;
# esta lista es el visor (y alimenta la fuente `testeos` del viz, que muestra
# el id corto como handle para dictar en conversación).
#
# Uso: testeos.sh [--estado en_curso|cerrado|abortado] [--step S]
#                 [--project N] [--limit N] [--json]
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"

DB=testeos
estado="" step="" project="" limit=50
while [[ $# -gt 0 ]]; do
  case "$1" in
    --estado)  estado="$2"; shift 2 ;;
    --step)    step="$2"; shift 2 ;;
    --project) project="$2"; shift 2 ;;
    --limit)   limit="$2"; shift 2 ;;
    --json)    FORMAT=json; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
[[ "$limit" =~ ^[0-9]+$ ]] || { echo "--limit debe ser entero (0 = sin tope)" >&2; exit 2; }

p="$(db_path "$DB")"
if [[ ! -f "$p" ]]; then
  echo "Aún no hay testeos registrados (la base nace con el primer testeo_abrir.sh)." >&2
  [[ "$FORMAT" == json ]] && echo "[]"
  exit 0
fi

esc() { printf '%s' "$1" | sed "s/'/''/g"; }
where="1=1"
[[ -n "$estado"  ]] && where="$where AND estado='$(esc "$estado")'"
[[ -n "$step"    ]] && where="$where AND step='$(esc "$step")'"
[[ -n "$project" ]] && where="$where AND proyecto LIKE '%$(esc "$project")%'"
lim=""; [[ "$limit" != 0 ]] && lim="LIMIT $limit"

Q="SELECT id, proyecto, step, variable, coalesce(metrica,'—') AS metrica,
          estado, abierto_en, coalesce(cerrado_en,'—') AS cerrado_en,
          valor_inicial, valor_final, delta,
          coalesce(resultado,'—') AS resultado, coalesce(decision,'') AS decision
   FROM testeos WHERE $where
   ORDER BY (estado='en_curso') DESC, abierto_en DESC $lim"

if [[ "$FORMAT" == json ]]; then
  json_or_empty "$(sqlite_ro "$p" -json "$Q")"
else
  sqlite_ro "$p" -column -header "$Q"
fi

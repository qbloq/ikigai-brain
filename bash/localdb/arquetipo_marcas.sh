#!/usr/bin/env bash
# Las marcas de arquetipo tomadas en la sqlite local `propuestas_reuniones`
# (tabla `arquetipos`): una fila por tarea sin etiqueta ya decidida, con su
# `aplicado_en` si bash/tasks/aplicar_arquetipos.sh ya la llevó a Postgres.
# READ-ONLY. Fuente viz de la vista «Sin arquetipo» de la UI de revisión.
#
# Usage: arquetipo_marcas.sh [--json]
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
DBP="$(db_path propuestas_reuniones)"
[[ -f "$DBP" ]] || { [[ "$FORMAT" == json ]] && echo "[]" || echo "Sin marcas todavía"; exit 0; }
SQL="SELECT task_id, decision, decision_nota, decidida_en, aplicado_en FROM arquetipos ORDER BY decidida_en DESC"
if [[ "$FORMAT" == json ]]; then out="$(sqlite_ro "$DBP" -json "$SQL;")"; json_or_empty "$out"
else sqlite_ro "$DBP" -header -column "SELECT substr(task_id,1,8) task, decision, coalesce(decision_nota,'') nota, decidida_en, coalesce(aplicado_en,'—') aplicado FROM arquetipos ORDER BY decidida_en DESC;"; fi

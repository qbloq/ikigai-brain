#!/usr/bin/env bash
# WRITE (Postgres + sqlite local): aplicar en Postgres las marcas de
# arquetipo que la UI de revisión dejó en la sqlite — el gemelo de
# crear_de_propuestas.sh, pero para las tareas sin arquetipo. Por cada fila
# de `arquetipos` con decision<>'ninguno' y sin aplicado_en: set_archetype.sh
# <task_id> <decision> --method human, y sella aplicado_en en la fila. Las
# marcas 'ninguno' no se aplican (no hay nada que setear en Postgres).
# ⚠️ Re-etiquetar mueve el puntero (tasks.archetype_id), NO reescribe el
# contrato IO — la tarea conserva los inputs/outputs/criterios de la
# plantilla vieja (o ninguno) hasta que su contrato se re-instancie aparte.
#
# Usage: aplicar_arquetipos.sh [--task ID|prefijo8] [--dry-run] [--json]
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/sqlite.sh"
cd "$REPO_ROOT"
TASK=""; DRY=0; JSON=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) TASK="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --json) JSON=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
DBP="$(require_db propuestas_reuniones)"
w="decision<>'ninguno' AND aplicado_en IS NULL"
[[ -n "$TASK" ]] && w="$w AND task_id LIKE $(sql_str "${TASK}%")"
aplicadas=0; saltadas=0
while IFS= read -r row; do
  task_id="$(jq -r .task_id <<<"$row")"; decision="$(jq -r .decision <<<"$row")"
  out="$(bash bash/tasks/set_archetype.sh "$task_id" "$decision" --method human $([[ "$DRY" == 1 ]] && echo --dry-run) 2>&1)" || { echo "task=${task_id:0:8} $decision: set_archetype.sh falló: $out" >&2; saltadas=$((saltadas+1)); continue; }
  if [[ "$DRY" == 0 ]]; then
    sqlite_rw "$DBP" "UPDATE arquetipos SET aplicado_en=datetime('now') WHERE task_id=$(sql_str "$task_id");"
  fi
  aplicadas=$((aplicadas+1))
  if [[ "$JSON" == 1 ]]; then
    jq -cn --arg id "$task_id" --arg a "$decision" --argjson dry "$DRY" '{task_id:$id, arquetipo:$a, dry_run:($dry==1)}'
  else
    echo "${task_id:0:8} → $decision"
  fi
done < <(sqlite_ro "$DBP" -json "SELECT task_id, decision FROM arquetipos WHERE $w ORDER BY decidida_en;" | jq -c '.[]?')
if [[ "$JSON" == 1 ]]; then
  jq -cn --argjson a "$aplicadas" --argjson s "$saltadas" --argjson dry "$DRY" '{ok:true, aplicadas:$a, saltadas:$s, dry_run:($dry==1)}'
else
  echo "aplicadas=$aplicadas saltadas=$saltadas$([[ "$DRY" == 1 ]] && echo ' (dry-run)')"
fi

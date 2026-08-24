#!/usr/bin/env bash
# WRITE (Postgres + sqlite local): ejecutar lo que la UI de revisión marcó
# como «entra» — el gemelo de merge_from_cruce.sh para las propuestas de
# reuniones. Por cada fila §A con decision='entra', valida=1 y sin creada_id:
# create_task.sh con el contrato GUARDADO en la sqlite (una txn por tarea),
# y sella creada_id/creada_en en la fila. Las §B nunca se crean (se listan
# como pendientes de conversación); las «se_queda» no se tocan.
#
# Usage: crear_de_propuestas.sh [--lote M] [--n LIST] [--dry-run] [--json]
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/sqlite.sh"
LOTE=""; NL=""; DRY=0; JSON=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lote) LOTE="$2"; shift 2 ;;
    --n) NL="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --json) JSON=1; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$NL" || "$NL" =~ ^[0-9]+(,[0-9]+)*$ ]] || { echo "--n: enteros separados por coma" >&2; exit 2; }
DBP="$(require_db propuestas_reuniones)"
w="seccion='A' AND decision='entra' AND creada_id IS NULL"
[[ -n "$LOTE" ]] && w="$w AND meeting_id LIKE $(sql_str "${LOTE:0:8}%")"
[[ -n "$NL" ]] && w="$w AND n IN ($NL)"
creadas=0; saltadas=0
while IFS= read -r row; do
  n="$(jq -r .n <<<"$row")"; ref="$(jq -r .ref <<<"$row")"; valida="$(jq -r .valida <<<"$row")"
  if [[ "$valida" != 1 ]]; then echo "n=$n $ref: contrato inválido — saltada ($(jq -r .error_validacion <<<"$row"))" >&2; saltadas=$((saltadas+1)); continue; fi
  out="$(jq -r .contrato <<<"$row" | bash bash/tasks/create_task.sh - $([[ "$DRY" == 1 ]] && echo --dry-run) 2>&1)" || { echo "n=$n $ref: create_task.sh falló: $out" >&2; saltadas=$((saltadas+1)); continue; }
  id="$(grep -oE '^ *[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' <<<"$out" | tr -d ' ' | head -1)"
  if [[ "$DRY" == 0 ]]; then
    [[ -n "$id" ]] || { echo "n=$n $ref: no pude leer el id creado de la salida" >&2; exit 1; }
    sqlite_rw "$DBP" "UPDATE propuestas SET creada_id=$(sql_str "$id"), creada_en=datetime('now') WHERE n=$n;"
  fi
  creadas=$((creadas+1))
  [[ "$JSON" == 1 ]] && jq -cn --argjson n "$n" --arg ref "$ref" --arg id "${id:-}" --argjson dry "$DRY" '{n:$n, ref:$ref, task_id:$id, dry_run:($dry==1)}' || echo "n=$n $ref → ${id:-(dry-run)}"
done < <(sqlite_ro "$DBP" -json "SELECT n, ref, valida, error_validacion, contrato FROM propuestas WHERE $w ORDER BY n;" | jq -c '.[]?')
pendB="$(sqlite_ro "$DBP" "SELECT count(*) FROM propuestas WHERE seccion='B' AND decision='entra';")"
[[ "$JSON" == 1 ]] && jq -cn --argjson c "$creadas" --argjson s "$saltadas" --argjson b "$pendB" --argjson dry "$DRY" '{ok:true, creadas:$c, saltadas:$s, seccion_b_pendientes:$b, dry_run:($dry==1)}' || echo "creadas=$creadas saltadas=$saltadas · §B marcadas «entra» pendientes de conversación: $pendB$([[ "$DRY" == 1 ]] && echo ' (dry-run)')"

#!/usr/bin/env bash
# [WRITE local] La decisión sobre el arquetipo de UNA tarea sin etiqueta:
# el id elegido (validado contra catalog/sop-archetypes.json) o 'ninguno'.
# Único write de la vista «Sin arquetipo» de la UI de revisión. Se aplica en
# Postgres después, desde la conversación, con bash/tasks/aplicar_arquetipos.sh.
# Guardrail: una marca ya aplicada (aplicado_en) se congela.
#
# Usage: arquetipo_mark.sh <task-id|prefijo8> --arquetipo A_.__|ninguno [--nota "…"] [--json]
#   --json  {ok, task_id, decision, decision_nota, decidida_en}
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"
cd "$REPO_ROOT"
ID=""; ARQ=""; NOTA=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --arquetipo) ARQ="$2"; shift 2 ;;
    --nota) NOTA="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    -*) echo "Argumento desconocido: $1" >&2; exit 2 ;;
    *) ID="$1"; shift ;;
  esac
done
fail() { if [[ "$FORMAT" == json ]]; then jq -cn --arg e "$1" '{ok:false,error:$e}'; else echo "$1" >&2; fi; exit "${2:-1}"; }
[[ "$ID" =~ ^[0-9a-f]{8}(-[0-9a-f-]{27})?$ ]] || fail "Falta <task-id|prefijo8>" 2
[[ -n "$ARQ" ]] || fail "Falta --arquetipo" 2
if [[ "$ARQ" != ninguno ]]; then
  jq -e --arg a "$ARQ" '.archetypes[]|select(.id==$a)' catalog/sop-archetypes.json >/dev/null || fail "Arquetipo desconocido en el catálogo: $ARQ"
fi
# El id completo se resuelve en Postgres solo si llegó un prefijo (la marca
# se guarda por uuid completo, que es lo que pide set_archetype.sh).
if [[ ${#ID} -eq 8 ]]; then
  source bash/lib/common.sh
  full="$(psql_ro -t -A -c "SELECT id FROM tasks WHERE id::text LIKE '$ID%';")"
  [[ "$(grep -c . <<<"$full")" -eq 1 ]] || fail "Prefijo $ID ambiguo o inexistente en tasks"
  ID="$full"
fi
DBP="$(db_path propuestas_reuniones)"; mkdir -p "$LOCALDB_DIR"
sqlite_rw "$DBP" < bash/localdb/propuestas_schema.sql
ap="$(sqlite_ro "$DBP" "SELECT coalesce(aplicado_en,'') FROM arquetipos WHERE task_id=$(sql_str "$ID");")"
[[ -z "$ap" ]] || fail "La marca de $ID ya fue aplicada ($ap) — se congela"
sqlite_rw "$DBP" "INSERT INTO arquetipos (task_id, decision, decision_nota, decidida_en) VALUES ($(sql_str "$ID"), $(sql_str "$ARQ"), $( [[ -n "$NOTA" ]] && sql_str "$NOTA" || echo NULL ), datetime('now'))
  ON CONFLICT(task_id) DO UPDATE SET decision=excluded.decision, decision_nota=excluded.decision_nota, decidida_en=excluded.decidida_en;"
out="$(sqlite_ro "$DBP" -json "SELECT task_id, decision, decision_nota, decidida_en FROM arquetipos WHERE task_id=$(sql_str "$ID");")"
if [[ "$FORMAT" == json ]]; then jq -c '.[0] + {ok:true}' <<<"$out"; else jq -r '.[0]|"\(.task_id[0:8]) → \(.decision)"' <<<"$out"; fi

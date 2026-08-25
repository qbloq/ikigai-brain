#!/usr/bin/env bash
# [WRITE local] La decisión sobre UNA propuesta: entra (se creará en el
# cerebro), se_queda (no), ninguna (borra la decisión). Único write de la
# vista «Propuestas» de la UI de revisión (patrón cruce_mark.sh). Guardrail:
# una propuesta ya creada (creada_id) se congela.
#
# Usage: propuesta_mark.sh <n> --decision entra|se_queda|ninguna [--nota "…"] [--json]
#   --json  {ok, n, decision, decision_nota, decidida_en}
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"
N=""; DEC=""; NOTA=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --decision) DEC="$2"; shift 2 ;;
    --nota) NOTA="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    -*) echo "Argumento desconocido: $1" >&2; exit 2 ;;
    *) N="$1"; shift ;;
  esac
done
fail() { if [[ "$FORMAT" == json ]]; then jq -cn --arg e "$1" '{ok:false,error:$e}'; else echo "$1" >&2; fi; exit "${2:-1}"; }
[[ "$N" =~ ^[0-9]+$ ]] || fail "Falta <n> (propuestas.n)" 2
[[ "$DEC" =~ ^(entra|se_queda|ninguna)$ ]] || fail "--decision entra|se_queda|ninguna" 2
DBP="$(require_db propuestas_reuniones)"
row="$(sqlite_ro "$DBP" "SELECT coalesce(creada_id,'')||'|'||seccion FROM propuestas WHERE n=$N;")"
[[ -n "$row" ]] || fail "No existe la propuesta n=$N"
[[ "${row%%|*}" == "" ]] || fail "La propuesta n=$N ya fue creada en el cerebro (${row%%|*}) — se congela"
if [[ "$DEC" == ninguna ]]; then
  sqlite_rw "$DBP" "UPDATE propuestas SET decision=NULL, decision_nota=NULL, decidida_en=NULL WHERE n=$N;"
else
  sqlite_rw "$DBP" "UPDATE propuestas SET decision=$(sql_str "$DEC"), decision_nota=$( [[ -n "$NOTA" ]] && sql_str "$NOTA" || echo NULL ), decidida_en=datetime('now') WHERE n=$N;"
fi
out="$(sqlite_ro "$DBP" -json "SELECT n, decision, decision_nota, decidida_en FROM propuestas WHERE n=$N;")"
if [[ "$FORMAT" == json ]]; then jq -c '.[0] + {ok:true}' <<<"$out"; else jq -r '.[0]|"n=\(.n) decision=\(.decision//"—") nota=\(.decision_nota//"")"' <<<"$out"; fi

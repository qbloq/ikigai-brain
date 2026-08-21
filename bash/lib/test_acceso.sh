#!/usr/bin/env bash
# Test de bash/lib/acceso.sh — la cerca por rol, sin red ni base.
# Correr: bash bash/lib/test_acceso.sh   (sale 0 si todo pasa)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$HERE/acceso.sh"
fails=0; ERRF="$(mktemp)"; trap 'rm -f "$ERRF"' EXIT

# arma un repo de mentira con el helper en la misma posición relativa
# (bash/lib/) para que resuelva su raíz y lea tmp/copilot.json.
MAPA="$HERE/../../docs/roles/acceso.json"
mk() {  # mk <copilot.json-content | ""(sin archivo)> [sin-mapa]
  local d; d="$(mktemp -d)"
  mkdir -p "$d/bash/lib" "$d/docs/roles"; cp "$HELPER" "$d/bash/lib/acceso.sh" 2>/dev/null
  [[ "${2:-}" == "sin-mapa" ]] || cp "$MAPA" "$d/docs/roles/acceso.json"
  [[ -n "$1" ]] && printf '%s' "$1" >"$d/copilot.json"
  printf '%s' "$d"
}
run() {  # run <dir> <dominio> → echo exit code; stderr queda en $ERRF
  local d="$1" dom="$2"
  bash -c "source '$d/bash/lib/acceso.sh'; require_acceso '$dom'" 2>"$ERRF" >/dev/null
  echo $?
}
check() {  # check <nombre> <esperado> <obtenido> [<frag que stderr debe contener>]
  local ERR; ERR="$(cat "$ERRF")"
  if [[ "$2" == "$3" ]] && { [[ -z "${4:-}" ]] || grep -q -- "$4" <<<"$ERR"; }; then
    echo "ok   $1"
  else
    echo "FAIL $1: esperaba exit $2${4:+ + «$4»}, obtuve exit $3; stderr: $ERR"; fails=$((fails+1))
  fi
}

d="$(mk "")";                                        check "cerebro (sin copilot.json) → ghl"    0 "$(run "$d" ghl)"
d="$(mk "")";                                        check "cerebro → vturb"                     0 "$(run "$d" vturb)"
d="$(mk '{"employee":"lorenzo-cadavid","team_member_id":"x","role":"ejecutivo"}')"
                                                     check "ejecutivo → ghl"                     0 "$(run "$d" ghl)"
                                                     check "ejecutivo → vturb"                   0 "$(run "$d" vturb)"
                                                     check "ejecutivo → dominio futuro (*)"      0 "$(run "$d" futuro)"
d="$(mk '{"employee":"tony-vidal","team_member_id":"x","role":"editor"}')"
                                                     check "editor → ghl negado"                 3 "$(run "$d" ghl)"   "bash/crm/"
                                                     check "editor → vturb negado"               3 "$(run "$d" vturb)" "editor"
d="$(mk '{"employee":"luis-david","team_member_id":"x","role":"director-comercial"}')"
                                                     check "director-comercial → ghl negado"     3 "$(run "$d" ghl)"   "director-comercial"
d="$(mk '{"employee":"x","team_member_id":"x"}')";   check "copilot.json sin role → negado"      3 "$(run "$d" ghl)"   "identidad"
d="$(mk 'esto no es json')";                         check "copilot.json roto → negado"          3 "$(run "$d" ghl)"   "identidad"
d="$(mk '{"employee":"pablo-gaviria","team_member_id":"x","role":"technology"}')"
                                                     check "technology → ghl"                    0 "$(run "$d" ghl)"
                                                     check "technology → vturb"                  0 "$(run "$d" vturb)"
d="$(mk '{"employee":"x","team_member_id":"x","role":"ejecutivo"}' sin-mapa)"
                                                     check "mapa ausente + ejecutivo → negado"   3 "$(run "$d" ghl)"   "acceso.json"
d="$(mk "" sin-mapa)";                               check "mapa ausente + cerebro → pasa"       0 "$(run "$d" ghl)"
d="$(mk '{"employee":"x","team_member_id":"x","role":"ejecutivo"}')"
bash -c "source '$d/bash/lib/acceso.sh'" 2>"$ERRF"; check "source no ejecuta nada"           0 "$?"

echo; (( fails == 0 )) && echo "todo ok" || { echo "$fails fallos"; exit 1; }

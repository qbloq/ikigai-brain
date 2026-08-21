#!/usr/bin/env bash
# bash/lib/acceso.sh — quién puede usar los dominios con CREDENCIAL DE PROVEEDOR.
# Source desde el lib del dominio:  source "$(dirname "$0")/../../lib/acceso.sh"
#                                   require_acceso ghl
#
# LA DOCTRINA (spec docs/superpowers/specs/2026-08-20-control-de-acceso-fuentes-design.md)
# Algunos dominios de bash/ operan con tokens de proveedor leídos de la base
# (bash/ghl/ → project_crm_configs, bash/vturb/ → project_vturb_video_configs,
# en claro). El cerebro corre en una máquina que la org controla; los copilotos
# son forks destinados a 19 laptops, y una llave maestra regada no se audita ni
# se revoca por persona. Hasta 2026-08-20 la cerca era binaria («¿hay
# copilot.json? → no»), y trataba igual al CEO que al editor de video.
# Decisión de Santiago (2026-08-20): el acceso a fuentes lo define EL ROL,
# no el hecho de ser copiloto. `ejecutivo` accede a cualquier fuente del
# negocio, incluidas las de credencial de proveedor.
#
# Dos honestidades que este archivo carga:
#   1. Es un riel, no un muro: un fork con DATABASE_URL podría leer el token
#      con un SELECT. El helper mantiene honesto el camino honesto y evita que
#      nazca algo NUEVO que dependa de la llave en un fork. El muro real es
#      mover las credenciales detrás del backend (patrón bash/google/).
#   2. La máquina no es el criterio: se decide por copilot.json (rol), jamás
#      por dónde corre, para que no se olvide cerrar el día de la mudanza.
#
# Independiente de common.sh a propósito: tiene que poder responder en un fork
# sin .env ni Postgres. No toca red ni base: decide con el archivo local.
#
# EL MAPA — editarlo es decisión de gobernanza (registrarla en el spec).
# Es un `case` y no un arreglo asociativo a propósito: los copilotos macOS
# corren bash 3.2, que no tiene `declare -A` (ya mató a bash/publicar/ una vez).
# Lectura: `*` = todos los dominios con credencial; lista = solo esos
# (separados por espacio); vacío = rol ausente del mapa = negado.
acceso_perm_rol() {  # acceso_perm_rol <rol> → echoes the role's domains
  case "$1" in
    ejecutivo) echo '*' ;;                 # acceso total a fuentes del negocio
    # director-comercial) echo 'ghl' ;;    # candidato; NO decidido (2026-08-21) — lee el espejo bash/crm/
    *) echo '' ;;
  esac
}

ACCESO_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCESO_REPO_ROOT="$(cd "$ACCESO_LIB_DIR/../.." && pwd)"

# acceso_rol : echoes the role of this repo — "cerebro" when there is no
# copilot.json; the `role` value when there is one; "" when the file is
# unreadable or has no role (fail-closed upstream).
acceso_rol() {
  local f="$ACCESO_REPO_ROOT/copilot.json"
  [[ -f "$f" ]] || { echo cerebro; return 0; }
  python3 - "$f" 2>/dev/null <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    r = d.get("role") if isinstance(d, dict) else None
    print(r.strip() if isinstance(r, str) and r.strip() else "")
except Exception:
    print("")
PY
}

# acceso_alternativa <dominio> : a dónde ir cuando el dominio está negado.
acceso_alternativa() {
  case "$1" in
    ghl)   echo "bash/ghl/ lee tokens de project_crm_configs; el espejo del CRM es bash/crm/ (ingestado, sin credencial)." ;;
    vturb) echo "bash/vturb/ lee tokens de project_vturb_video_configs; el fallback vía proxy Mkt (apis/mkt/vturb-video.openapi.json) está pendiente." ;;
    *)     echo "el dominio '$1' opera con credencial de proveedor." ;;
  esac
}

# require_acceso <dominio> : returns 0 when this repo may use the domain;
# otherwise prints why and exits 3 (same code the old binary fence used).
require_acceso() {
  local dom="$1" rol perm d
  rol="$(acceso_rol)"
  [[ "$rol" == "cerebro" ]] && return 0
  if [[ -z "$rol" ]]; then
    echo "$dom: copilot.json sin identidad legible (falta \`role\` o no es JSON) — un fork sin identidad no hereda permisos." >&2
    echo "     (bash/lib/acceso.sh: el acceso a fuentes con credencial lo define el rol; arregla copilot.json o pide el alta de nuevo)" >&2
    exit 3
  fi
  perm="$(acceso_perm_rol "$rol")"
  if [[ "$perm" == "*" ]]; then return 0; fi
  for d in $perm; do [[ "$d" == "$dom" ]] && return 0; done
  echo "$dom: este dominio no está habilitado para el rol '$rol' — solo el cerebro y los roles del mapa en bash/lib/acceso.sh manejan credenciales de proveedor." >&2
  echo "     ($(acceso_alternativa "$dom"))" >&2
  exit 3
}

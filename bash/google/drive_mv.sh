#!/usr/bin/env bash
# drive_mv.sh <file id|url> --to <folder id|url|name> [--json]      [WRITE→Drive]
#
# Mover UN archivo o carpeta a otra carpeta del Drive de la org, con la
# identidad de la org (backend Meetico: PATCH /drive/files/{id} con parentId).
# Reemplaza TODOS los padres actuales por el destino (un ítem de Drive puede
# colgar de varias carpetas; acá se quiere uno). El id y la URL del archivo
# no cambian al moverlo, así que los enlaces de los contratos no se rompen.
# Si ya está en el destino, informa y no toca nada (`moved:false`).
#
# Nació el 2026-08-22 para ordenar «1. David Guerrero/Hermetico/» en una
# carpeta por tarea. La tercera escritura de bash/google/ (carpeta, Doc, mover).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/common.sh"
ref="" to=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --to) to="$2"; shift 2;;
    --json) FORMAT=json; shift;;
    -h|--help) sed -n '2,12p' "$0"; exit 0;;
    -*) echo "arg desconocido: $1" >&2; exit 2;;
    *) ref="$1"; shift;;
  esac
done
[[ -n "$ref" && -n "$to" ]] || { echo "uso: drive_mv.sh <file id|url> --to <folder id|url|name> [--json]" >&2; exit 2; }
fid="$(gid "$ref")"
pid="$(resolve_folder "$to")"
body="$(PID="$pid" python3 -c 'import json,os; print(json.dumps({"parentId":os.environ["PID"]}))')"
out="$(mapi PATCH "/drive/files/$fid" -H 'Content-Type: application/json' --data-binary "$body")"
if [[ "$FORMAT" == "json" ]]; then printf '%s\n' "$out" | python3 -m json.tool; exit 0; fi
OUT="$out" python3 - <<'PY'
import json, os
f = json.loads(os.environ["OUT"])
print(("movido" if f.get("moved") else "ya estaba ahí") + f": {f.get('name')}  ({f.get('id')}) → carpeta {', '.join(f.get('parents') or [])}")
PY

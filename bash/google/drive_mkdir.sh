#!/usr/bin/env bash
# drive_mkdir.sh <parent id|url|name> --name "Nombre" [--json]      [WRITE→Drive]
#
# Crear UNA carpeta dentro de otra, con la identidad Google de la org (vía el
# backend Meetico: POST /drive/folders). Idempotente por nombre: si ya existe
# una carpeta no-borrada con ese nombre en ese padre, la devuelve (`created:
# false`) en vez de duplicarla — Drive sí permite hermanas homónimas, y eso
# nunca es lo que se quiere acá.
#
# Nació el 2026-08-22 para la estructura «1. David Guerrero/Hermetico/<id8> ·
# <título>/» donde viven los Docs de los contratos de tarea. La segunda
# escritura real de bash/google/ (la primera: el refresco del índice).
#
#   <parent>   id, URL de Drive, o nombre de carpeta (se resuelve como en drive_ls.sh)
#   --name     nombre de la carpeta a crear
#   --json     el objeto del backend: {id,name,mimeType,parents,webViewLink,created}
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/common.sh"
parent="" name=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) name="$2"; shift 2;;
    --json) FORMAT=json; shift;;
    -h|--help) sed -n '2,16p' "$0"; exit 0;;
    -*) echo "arg desconocido: $1" >&2; exit 2;;
    *) parent="$1"; shift;;
  esac
done
[[ -n "$parent" && -n "$name" ]] || { echo "uso: drive_mkdir.sh <parent id|url|name> --name \"Nombre\" [--json]" >&2; exit 2; }
pid="$(resolve_folder "$parent")"
body="$(PID="$pid" NAME="$name" python3 -c 'import json,os; print(json.dumps({"parentId":os.environ["PID"],"name":os.environ["NAME"]},ensure_ascii=False))')"
out="$(mapi POST "/drive/folders" -H 'Content-Type: application/json' --data-binary "$body")"
if [[ "$FORMAT" == "json" ]]; then printf '%s\n' "$out" | python3 -m json.tool; exit 0; fi
OUT="$out" python3 - <<'PY'
import json, os
f = json.loads(os.environ["OUT"])
print(("creada" if f.get("created") else "ya existía") + f": {f.get('name')}  ({f.get('id')})")
print(f"  {f.get('webViewLink','')}")
PY

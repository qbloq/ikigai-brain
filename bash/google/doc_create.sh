#!/usr/bin/env bash
# doc_create.sh <parent id|url|name> --title "Título" (--from archivo.md | -)
#               [--html] [--share email[:reader|commenter|writer]]... [--notify]
#               [--dry-run] [--json]                               [WRITE→Drive]
#
# Crear UN Google Doc en una carpeta del Drive de la org a partir de un
# Markdown (o HTML con --html), con la identidad Google de la org — vía el
# backend Meetico (POST /drive/files, que importa el contenido como Doc
# nativo). Sirve para dejar en Drive los entregables que el Cerebro produce
# y que el equipo consume como Docs (requerimientos, reportes, planes).
#
# El Markdown se convierte a HTML acá (pandoc) antes de enviarlo: la
# importación HTML→Doc de Google conserva títulos, tablas, negritas, listas
# y enlaces; la de Markdown directo es más frágil. --html salta la conversión.
#
#   --share    da acceso al crear (rol default: reader). Varias veces. Sin
#              --notify, Google no manda correo.
#   --dry-run  muestra qué se enviaría (padre resuelto, título, tamaño) y sale.
#   --json     el objeto del backend: {id,name,mimeType,webViewLink,createdTime,shared[]}
#
# No sobreescribe ni actualiza: crear dos veces = dos Docs. Para re-publicar un
# reporte que cambia, el contrato pide PUT /drive/files/{id}/content (pendiente).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/common.sh"
parent="" title="" from="" html=0 notify=0 dry=0; shares=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --title) title="$2"; shift 2;;
    --from) from="$2"; shift 2;;
    --html) html=1; shift;;
    --share) shares+=("$2"); shift 2;;
    --notify) notify=1; shift;;
    --dry-run) dry=1; shift;;
    --json) FORMAT=json; shift;;
    -h|--help) sed -n '2,24p' "$0"; exit 0;;
    -) from="-"; shift;;
    -*) echo "arg desconocido: $1" >&2; exit 2;;
    *) parent="$1"; shift;;
  esac
done
[[ -n "$parent" && -n "$title" && -n "$from" ]] || { sed -n '2,4p' "$0" >&2; exit 2; }
if [[ "$from" == "-" ]]; then content="$(cat)"; else [[ -f "$from" ]] || { echo "no existe: $from" >&2; exit 1; }; content="$(cat "$from")"; fi
[[ -n "$content" ]] || { echo "contenido vacío" >&2; exit 1; }
if [[ "$html" == 0 ]]; then
  command -v pandoc >/dev/null || { echo "hace falta pandoc para convertir Markdown → HTML (o pasá --html)" >&2; exit 1; }
  content="$(printf '%s\n' "$content" | pandoc -f gfm -t html --wrap=none)"
fi
pid="$(resolve_folder "$parent")"
body="$(PID="$pid" TITLE="$title" CONTENT="$content" NOTIFY="$notify" SHARES="$(printf '%s\n' "${shares[@]:-}")" python3 - <<'PY'
import json, os
shares=[]
for s in os.environ["SHARES"].splitlines():
    s=s.strip()
    if not s: continue
    email, _, role = s.partition(":")
    shares.append({"emailAddress": email, "role": role or "reader", "notify": os.environ["NOTIFY"]=="1"})
o={"parentId":os.environ["PID"],"name":os.environ["TITLE"],"content":os.environ["CONTENT"],"contentMimeType":"text/html","convertTo":"google-doc"}
if shares: o["share"]=shares
print(json.dumps(o, ensure_ascii=False))
PY
)"
if [[ "$dry" == 1 ]]; then
  echo "(dry-run) padre=$pid título=\"$title\" html=${#content} bytes share=${shares[*]:-—}"; exit 0
fi
out="$(mapi POST "/drive/files" -H 'Content-Type: application/json' --data-binary "$body")"
if [[ "$FORMAT" == "json" ]]; then printf '%s\n' "$out" | python3 -m json.tool; exit 0; fi
OUT="$out" python3 - <<'PY'
import json, os
f = json.loads(os.environ["OUT"])
print(f"creado: {f.get('name')}  ({f.get('id')})")
print(f"  {f.get('webViewLink','')}")
for s in f.get("shared") or []:
    print(f"  compartido con {s.get('emailAddress')} ({s.get('role')}): {'ok' if s.get('ok') else s.get('error')}")
PY

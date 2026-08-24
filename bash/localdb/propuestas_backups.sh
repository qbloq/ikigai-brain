#!/usr/bin/env bash
# Los backups de propuestas de tareas (backups/meeting-tasks/) que la UI de
# revisión puede cargar: uno por reunión, con su gemelo JSON si existe y la
# marca `cargado` (ya tiene lote en la sqlite local `propuestas_reuniones`).
# READ-ONLY. Fuente viz `propuestas_backups`.
#
# Usage: propuestas_backups.sh [--desde YYYY-MM-DD] [--json]
#   --desde  fecha mínima de la REUNIÓN (default 2026-08-21). Un backup con
#            solo .md (sin gemelo) usa la fecha de modificación del archivo.
#   --json   [{meeting_id, meeting_corto, archivo, json, fecha, nombre, n_a,
#             n_b, cargado, cargado_en}]
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"

DESDE="2026-08-21"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --desde) DESDE="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
[[ "$DESDE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "--desde espera YYYY-MM-DD" >&2; exit 2; }

DIR="$REPO_ROOT/backups/meeting-tasks"
DBP="$(db_path propuestas_reuniones)"
lotes="[]"
[[ -f "$DBP" ]] && lotes="$(sqlite_ro "$DBP" -json "SELECT meeting_id, meeting_corto, cargado_en FROM lotes;" | { read -r -d '' x || true; printf '%s' "${x:-[]}"; })"

# Un objeto por .md; el gemelo .json aporta fecha/nombre/conteos; sin gemelo
# la fecha es la del archivo (mtime) y json=0.
items=""
for md in "$DIR"/*.md; do
  base="$(basename "$md" .md)"
  [[ "$base" =~ ^[0-9a-f]{8} ]] || continue          # los lotes históricos (2026-07-…) no son por reunión
  corto="${base:0:8}"
  js="$DIR/$base.json"
  if [[ -f "$js" ]]; then
    item="$(jq -c --arg archivo "$base.md" --arg corto "$corto" '{meeting_id:.meeting, meeting_corto:$corto, archivo:$archivo, json:1, fecha:.fecha, nombre:.nombre, n_a:([.propuestas[]|select(.seccion=="A")]|length), n_b:([.propuestas[]|select(.seccion=="B")]|length)}' "$js")"
  else
    fecha="$(date -r "$md" +%F)"
    item="$(jq -cn --arg archivo "$base.md" --arg corto "$corto" --arg fecha "$fecha" '{meeting_id:null, meeting_corto:$corto, archivo:$archivo, json:0, fecha:$fecha, nombre:null, n_a:0, n_b:0}')"
  fi
  items+="${items:+,}$item"
done
out="$(jq -c --arg desde "$DESDE" --argjson lotes "$lotes" '
  [ .[] | select(.fecha >= $desde)
        | . as $b | ($lotes | map(select(.meeting_corto == $b.meeting_corto)) | first) as $l
        | . + {cargado: (if $l then 1 else 0 end), cargado_en: ($l.cargado_en // null)} ]
  | sort_by(.fecha) | reverse' <<<"[$items]")"
if [[ "$FORMAT" == "json" ]]; then printf '%s\n' "$out"
else jq -r '["corto","fecha","json","cargado","A","B","nombre"], (.[]|[.meeting_corto,.fecha,.json,.cargado,.n_a,.n_b,(.nombre//"—")]) | @tsv' <<<"$out" | column -t -s $'\t'; fi

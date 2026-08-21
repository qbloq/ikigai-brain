#!/usr/bin/env bash
# videos.sh — the VTurb catalog of a project, from the source.
#
# Default: GET /players/list (every player under the project's token), with a
# `sel` column marking the ones curated into `project_vturb_video_selections`
# — the set analitica.sh reports on. --seleccionados lists only those, from
# OUR database (that's where the stored duration lives, the input the
# retention endpoint requires).
source "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Uso: videos.sh --project NOMBRE [--seleccionados] [--json]

Catálogo de players VTurb del proyecto (en vivo, desde el API):
  id · nombre · duración (s) · pitch_time · creado · sel (✓ = seleccionado)

--seleccionados  Solo las selecciones curadas del proyecto, leídas de la DB
                 (project_vturb_video_selections): video_id, título, duración,
                 fecha de selección.

Solo lee. El token sale de project_vturb_video_configs y nunca se imprime.
EOF
}

project=""; only_sel=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) project="$2"; shift 2 ;;
    --seleccionados) only_sel=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$project" ]] && { echo "vturb: falta --project (proyectos: $(vturb_projects | cut -f2 | paste -sd', '))" >&2; exit 2; }

IFS=$'\t' read -r pid pname < <(vturb_resolve_project "$project")
sels="$(vturb_selections "$pid")"

if (( only_sel )); then
  printf '%s' "$sels" | vturb_render 'video_id:video_id,titulo:titulo,duracion:duracion,seleccionado:seleccionado'
  exit 0
fi

vturb_load_creds "$pid"
out="$(vturb_api_get "/players/list")"

python3 -c '
import json, sys
d = json.loads(sys.argv[1])
rows = d if isinstance(d, list) else (d.get("players") or d.get("videos") or [])
selected = {s["video_id"] for s in json.loads(sys.argv[2])}
items = [{
    "id": v.get("id"),
    "nombre": v.get("name") or "(sin nombre)",
    "duracion": v.get("duration"),
    "pitch_time": v.get("pitch_time"),
    "creado": (v.get("created_at") or "")[:10],
    "sel": "✓" if v.get("id") in selected else "",
} for v in rows]
items.sort(key=lambda x: (x["sel"] != "✓", x["creado"]), reverse=False)
json.dump(items, sys.stdout, ensure_ascii=False)' "$out" "$sels" \
  | vturb_render 'id:id,nombre:nombre,duracion:duracion,pitch_time:pitch_time,creado:creado,sel:sel'

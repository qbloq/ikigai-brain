#!/usr/bin/env bash
# WRITE (pg): dar de alta una REUNIÓN DE EQUIPO en `meetings` a partir de su
# grabación en el Drive («Meet Recordings»). Existe porque las reuniones que
# graba Meet no entran solas al sistema: el ingestor de Marketico registra las
# que pasan por su calendario, y el resto (reuniones ad-hoc, agendadas desde
# una cuenta personal) quedan solo como mp4 en el Drive — sin acta, sin
# transcript, sin tareas derivables.
#
# Qué escribe (una txn): una fila en `meetings` con meeting_type='team',
# nombre = el del archivo del Drive (misma convención que las ingeridas),
# actual_end = createdTime del mp4 y actual_start = end − duración del video
# (la convención verificada en las filas que ya ingirió Marketico),
# drive_file_id = el mp4, description opcional. El transcript NO lo genera:
# eso es bash/calls/procesar_video.sh --tipo team (STT desde el video), y el
# acta es el skill transcript-to-report.
#
# Idempotente por drive_file_id: si ya hay una reunión con ese video, la
# devuelve y no crea otra.
#
# Uso: ingest_meeting.sh <drive-file-id|url> --project N [--space ID]
#                        [--name N] [--description T] [--status S]
#                        [--dry-run] [--json]
#   --project N      nombre (fragmento) del proyecto — obligatorio
#   --space ID       spaces.id; default: el space de la última reunión de
#                    equipo del mismo proyecto
#   --name N         default: el nombre del archivo en el Drive
#   --status S       default: completed (ya ocurrió: hay grabación)
#   --dry-run        todo el trabajo, pero la transacción hace ROLLBACK
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../lib/common.sh"          # psql_ro / psql_rw
source "$here/../google/lib/common.sh"   # mapi + gid (metadata del Drive)

FORMAT="${FORMAT:-table}"
ref="" project="" space="" name="" description="" status="completed" dry=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) project="$2"; shift 2 ;;
    --space) space="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --description) description="$2"; shift 2 ;;
    --status) status="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) ref="$1"; shift ;;
  esac
done
[[ -n "$ref" && -n "$project" ]] || { echo "Uso: ingest_meeting.sh <drive-file-id|url> --project N […]; ver -h" >&2; exit 2; }
file_id="$(gid "$ref")"

# ── proyecto (exactamente uno)
pesc="${project//\'/\'\'}"
prow="$(psql_ro -t -A -F'|' -c "SELECT id, name FROM projects WHERE name ILIKE '%${pesc}%'")"
[[ "$(grep -c . <<<"${prow:-}")" == 1 ]] || { echo "proyecto '$project': $(grep -c . <<<"${prow:-}") coincidencias (se necesita 1)" >&2; exit 1; }
IFS='|' read -r project_id project_name <<<"$prow"

# ── ya existe?
existing="$(psql_ro -t -A -c "SELECT id FROM meetings WHERE drive_file_id='${file_id//\'/\'\'}' LIMIT 1")"
if [[ -n "$existing" ]]; then
  echo "ya existe una reunión con ese video: $existing (nada que crear)" >&2
  [[ "$FORMAT" == json ]] && printf '{"meeting_id":"%s","created":false}\n' "$existing"
  exit 0
fi

# ── metadata del Drive: nombre, createdTime, duración
meta="$(mapi GET "/drive/files/$file_id")"
IFS=$'\t' read -r d_name d_created d_dur d_mime <<<"$(python3 -c '
import json,sys
d=json.load(sys.stdin)
if not d.get("id"): sys.stderr.write("drive: archivo no encontrado\n"); sys.exit(1)
dur=(d.get("videoMediaMetadata") or {}).get("durationMillis") or ""
print("\t".join([d.get("name",""), d.get("createdTime",""), str(dur), d.get("mimeType","")]))' <<<"$meta")"
[[ "$d_mime" == video/* ]] || { echo "el archivo no es un video ($d_mime); se ingiere desde la grabación mp4" >&2; exit 1; }
[[ -n "$d_created" ]] || { echo "el Drive no devolvió createdTime" >&2; exit 1; }
[[ -n "$name" ]] || name="$d_name"
if [[ -n "$d_dur" ]]; then
  end_sql="'${d_created}'::timestamptz"
  start_sql="${end_sql} - make_interval(secs => ${d_dur}/1000.0)"
else
  echo "⚠ el video no trae duración: actual_start = actual_end (corrígelo luego)" >&2
  end_sql="'${d_created}'::timestamptz"; start_sql="$end_sql"
fi

# ── space: el de la última reunión de equipo del proyecto
if [[ -z "$space" ]]; then
  space="$(psql_ro -t -A -c "SELECT space_id FROM meetings WHERE meeting_type='team' AND project_id='$project_id' AND space_id IS NOT NULL ORDER BY scheduled_start_time DESC NULLS LAST LIMIT 1")"
fi
space_sql="NULL"; [[ -n "$space" ]] && space_sql="'${space//\'/\'\'}'"
desc_sql="NULL"; [[ -n "$description" ]] && desc_sql="'${description//\'/\'\'}'"

echo "proyecto : $project_name ($project_id)" >&2
echo "video    : $file_id — $d_name ($(( ${d_dur:-0} / 60000 )) min)" >&2
echo "nombre   : $name" >&2

sql="$(cat <<SQL
BEGIN;
INSERT INTO meetings (space_id, project_id, name, description, scheduled_start_time, scheduled_end_time,
                      actual_start_time, actual_end_time, status, drive_file_id, meeting_type)
VALUES (${space_sql}, '${project_id}', '${name//\'/\'\'}', ${desc_sql},
        ${start_sql}, ${end_sql}, ${start_sql}, ${end_sql},
        '${status//\'/\'\'}', '${file_id//\'/\'\'}', 'team')
RETURNING id, name, status, actual_start_time, actual_end_time;
$( ((dry)) && echo ROLLBACK\; || echo COMMIT\; )
SQL
)"
out="$(psql_rw -t -A -F'|' -c "$sql")"
IFS='|' read -r mid _ <<<"$(grep -m1 '|' <<<"$out")"
echo "reunión  : $mid  actual $(cut -d'|' -f4,5 <<<"$(grep -m1 '|' <<<"$out")")$( ((dry)) && echo '  (dry-run, revertido)')" >&2

if [[ "$FORMAT" == json ]]; then
  python3 -c 'import json,sys; print(json.dumps({"meeting_id":sys.argv[1],"created":sys.argv[2]!="1","project":sys.argv[3],"file_id":sys.argv[4],"name":sys.argv[5]},ensure_ascii=False))' \
    "$mid" "$dry" "$project_name" "$file_id" "$name"
else
  echo "✓ $name → meetings $mid (team, $project_name)$( ((dry)) && echo ' — dry-run')"
fi

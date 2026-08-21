#!/usr/bin/env bash
# frame.sh — saca UN fotograma de un video en un instante dado, con ffmpeg.
#
# Local y sin dependencias del repo (ni .env ni Postgres): entra un archivo y
# un tiempo, sale una imagen. Seek preciso (decodifica desde el keyframe
# anterior y descarta hasta el instante pedido), así que el frame es el del
# tiempo exacto, no el keyframe más cercano.
#
# Uso: frame.sh <video> --at T [--out F] [--force] [--json]
#   --at T     instante: segundos (90, 12.5) o reloj (01:30, 00:01:30.250)
#   --out F    ruta de la imagen (default: <video sin extensión>-<T>.jpg);
#              la extensión decide el formato (.jpg / .png / .webp)
#   --force    sobreescribe el destino si ya existe
#   --json     {frame, at, width, height, bytes}
set -euo pipefail

FORMAT="${FORMAT:-table}"
video="" at="" out="" force=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --at) at="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --force) force=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) video="$1"; shift ;;
  esac
done
usage="Uso: frame.sh <video> --at T [--out F] [--force] [--json]"
[[ -n "$video" && -n "$at" ]] || { echo "$usage" >&2; exit 2; }
[[ -f "$video" ]] || { echo "No existe: $video" >&2; exit 1; }
[[ "$at" =~ ^([0-9]+:)?([0-9]+:)?[0-9]+(\.[0-9]+)?$ ]] || { echo "--at inválido: '$at' (segundos o HH:MM:SS[.ms])" >&2; exit 2; }
command -v ffmpeg >/dev/null || { echo "ffmpeg no está instalado" >&2; exit 1; }

# default: <video>-<T>.jpg, con el tiempo saneado para que sea nombre de archivo
[[ -n "$out" ]] || out="${video%.*}-$(tr ':' '-' <<<"$at" | tr '.' '_').jpg"
if [[ -e "$out" && $force -eq 0 ]]; then
  echo "El destino ya existe: $out (usa --force para sobreescribir)" >&2; exit 1
fi

# -ss antes de -i: seek por índice + decodificación desde el keyframe previo
# (preciso desde ffmpeg 2.1). -frames:v 1 = un solo fotograma. -q:v 2 = mejor
# calidad jpg (ignorado por png). -nostdin: sin él se come el stdin heredado
# de un loop `while read` (ya pasó en bash/audio).
ffmpeg -hide_banner -loglevel error -nostdin ${force:+-y} -ss "$at" -i "$video" \
  -frames:v 1 -q:v 2 -update 1 "$out"

# Pedir un instante más allá del final no es error para ffmpeg: simplemente
# no escribe nada. Aquí sí lo es.
if [[ ! -s "$out" ]]; then
  rm -f "$out"
  dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$video" 2>/dev/null | cut -d. -f1 || echo '?')"
  echo "No hay fotograma en $at (el video dura ${dur}s)" >&2; exit 1
fi

dims="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$out" 2>/dev/null || echo 'x')"
w="${dims%x*}" h="${dims#*x}"
bytes="$(stat -c%s "$out")"

if [[ "$FORMAT" == json ]]; then
  python3 -c 'import json,sys; print(json.dumps({"frame":sys.argv[1],"at":sys.argv[2],"width":int(sys.argv[3] or 0),"height":int(sys.argv[4] or 0),"bytes":int(sys.argv[5])}))' "$out" "$at" "${w:-0}" "${h:-0}" "$bytes"
else
  echo "frame: $out (${at}, ${w:-?}x${h:-?}, $((bytes/1024)) KB)"
fi

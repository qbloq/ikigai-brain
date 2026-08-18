#!/usr/bin/env bash
# extract_audio.sh — extrae la pista de audio de un video con ffmpeg, lista
# para STT: mono, 16 kHz, mp3 48 kbps (~21 MB por hora — lo que un upload a un
# API de transcripción agradece; la voz no pierde nada útil por debajo de eso).
#
# Local y sin dependencias del repo (ni .env ni Postgres): entra un archivo,
# sale un archivo. La composición con Drive y la DB vive en
# bash/calls/procesar_video.sh.
#
# Uso: extract_audio.sh <video> [--out F] [--force] [--json]
#   --out F    ruta del audio (default: <video sin extensión>.mp3)
#   --force    sobreescribe el destino si ya existe
#   --json     {audio, seconds, bytes}
set -euo pipefail

FORMAT="${FORMAT:-table}"
video="" out="" force=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    --force) force=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) video="$1"; shift ;;
  esac
done
[[ -n "$video" ]] || { echo "Uso: extract_audio.sh <video> [--out F] [--force] [--json]" >&2; exit 2; }
[[ -f "$video" ]] || { echo "No existe: $video" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg no está instalado" >&2; exit 1; }

[[ -n "$out" ]] || out="${video%.*}.mp3"
if [[ -e "$out" && $force -eq 0 ]]; then
  echo "El destino ya existe: $out (usa --force para sobreescribir)" >&2; exit 1
fi

# -nostdin: sin él ffmpeg lee del stdin heredado y se come lo que un loop
# `while read` tenga en cola (ya pasó: mutiló la lista de un lote)
ffmpeg -hide_banner -loglevel error -nostdin ${force:+-y} -i "$video" \
  -vn -ac 1 -ar 16000 -b:a 48k "$out"

secs="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out" 2>/dev/null | cut -d. -f1 || echo '')"
bytes="$(stat -c%s "$out")"

if [[ "$FORMAT" == json ]]; then
  python3 -c 'import json,sys; print(json.dumps({"audio":sys.argv[1],"seconds":int(sys.argv[2] or 0),"bytes":int(sys.argv[3])}))' "$out" "${secs:-0}" "$bytes"
else
  echo "audio: $out (${secs:-?}s, $((bytes/1024)) KB)"
fi

#!/usr/bin/env bash
# assemblyai.sh — Speech-to-Text de UN archivo de audio (o video) vía el API
# de AssemblyAI. Primera variante de bash/audio/stt/; cada motor STT es un
# script con el mismo contrato (entra audio, sale texto diarizado en stdout),
# para poder compararlos y cambiarlos sin tocar la composición.
#
# Salida: texto plano diarizado «Speaker A: …» por línea — el MISMO formato de
# meeting_transcripts.transcript, así el pipeline de reportes lo consume igual.
#
# Credencial: ASSEMBLYAI_API_KEY (en el .env del repo). Se pasa a curl por
# process substitution (-H @fd), nunca en argv. Costo: AssemblyAI cobra por
# minuto de audio — este script sube y transcribe UNA vez por corrida, sin
# reintentos silenciosos.
#
# Uso: assemblyai.sh <audio|video> [--lang es] [--no-speakers] [--out F]
#                    [--raw F] [--poll S] [--timeout S] [--json]
#   --lang         código de idioma (default es)
#   --no-speakers  sin diarización (texto corrido)
#   --out F        escribe el texto en F (además de stdout si no hay --json)
#   --raw F        guarda la respuesta completa del API (utterances, words…)
#   --poll/--timeout  segundos entre sondeos / máximo de espera (10 / 1800)
#   --json         {id, status, audio_seconds, chars, out}
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$here/../../.." && pwd)"

API="https://api.assemblyai.com/v2"
FORMAT="${FORMAT:-table}"
audio="" lang="es" speakers=true out="" raw="" poll=10 timeout=1800
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang) lang="$2"; shift 2 ;;
    --no-speakers) speakers=false; shift ;;
    --out) out="$2"; shift 2 ;;
    --raw) raw="$2"; shift 2 ;;
    --poll) poll="$2"; shift 2 ;;
    --timeout) timeout="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) audio="$1"; shift ;;
  esac
done
[[ -n "$audio" && -f "$audio" ]] || { echo "Uso: assemblyai.sh <audio> [--out F] …  (archivo no encontrado: '${audio:-}')" >&2; exit 2; }

# credencial: env primero; si no, directo del .env (sin cargar todo el entorno)
KEY="${ASSEMBLYAI_API_KEY:-}"
[[ -z "$KEY" && -f "$REPO_ROOT/.env" ]] && KEY="$(sed -n 's/^ASSEMBLYAI_API_KEY=//p' "$REPO_ROOT/.env" | tail -1)"
[[ -n "$KEY" ]] || { echo "ASSEMBLYAI_API_KEY vacío — ponla en el .env del repo" >&2; exit 1; }

aai() { # aai <method> <path> [curl-args...]
  curl -sS -X "$1" "$API$2" -H @<(printf 'authorization: %s\n' "$KEY") "${@:3}"
}

# 1. upload (el archivo, binario)
up="$(aai POST /upload --data-binary @"$audio")"
url="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("upload_url",""))' <<<"$up")"
[[ -n "$url" ]] || { echo "assemblyai upload falló: $(head -c 300 <<<"$up")" >&2; exit 1; }

# 2. crear el job
job="$(python3 -c 'import json,sys; print(json.dumps({"audio_url":sys.argv[1],"language_code":sys.argv[2],"speaker_labels":sys.argv[3]=="true","punctuate":True,"format_text":True}))' "$url" "$lang" "$speakers" \
  | aai POST /transcript -H 'content-type: application/json' -d @-)"
tid="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' <<<"$job")"
[[ -n "$tid" ]] || { echo "assemblyai job falló: $(head -c 300 <<<"$job")" >&2; exit 1; }
echo "assemblyai job $tid (lang=$lang, speakers=$speakers) — esperando…" >&2

# 3. sondear hasta completed/error
t0="$(date +%s)" resp="" status=""
while :; do
  resp="$(aai GET "/transcript/$tid")"
  status="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' <<<"$resp")"
  case "$status" in
    completed) break ;;
    error) echo "assemblyai error: $(python3 -c 'import json,sys; print(json.load(sys.stdin).get("error",""))' <<<"$resp")" >&2; exit 1 ;;
  esac
  (( $(date +%s) - t0 > timeout )) && { echo "assemblyai timeout tras ${timeout}s (job $tid sigue '$status')" >&2; exit 1; }
  sleep "$poll"
done

# la respuesta completa siempre pasa por archivo: puede pesar MBs (words[])
rawf="${raw:-$(mktemp)}"
printf '%s' "$resp" > "$rawf"

# 4. texto: utterances diarizadas si las hay, texto plano si no
txt="$(python3 - "$rawf" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
utts = r.get("utterances") or []
if utts:
    print("\n\n".join(f"Speaker {u['speaker']}: {u['text']}" for u in utts))
else:
    print(r.get("text") or "")
PY
)"
[[ -z "$raw" ]] && rm -f "$rawf"
[[ -n "$out" ]] && printf '%s\n' "$txt" > "$out"

if [[ "$FORMAT" == json ]]; then
  python3 -c 'import json,sys; print(json.dumps({"id":sys.argv[1],"status":"completed","audio_seconds":int(sys.argv[2] or 0),"chars":len(sys.argv[4]),"out":sys.argv[3] or None}))' \
    "$tid" "$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("audio_duration") or 0)' <<<"$resp")" "$out" "$txt"
else
  [[ -n "$out" ]] && echo "texto: $out ($(printf '%s' "$txt" | wc -c) chars)" >&2 || printf '%s\n' "$txt"
fi

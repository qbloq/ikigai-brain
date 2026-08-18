#!/usr/bin/env bash
# WRITE (pg): recuperar el transcript de una llamada desde su VIDEO en Drive —
# la composición completa para las llamadas cuya grabación existe pero cuyo
# transcript nunca se generó (la cola que muestra la vista `no_completadas`
# de la sqlite closer_calls):
#
#   1. descarga el video del Drive (backend mkt, /drive/files/{id}/download)
#   2. extrae el audio               (bash/audio/extract_audio.sh)
#   3. lo transcribe                 (bash/audio/stt/assemblyai.sh, es + speakers)
#   4. persiste en UNA transacción:  upsert de meeting_transcripts
#                                    + meetings.status = 'completed'
#   5. borra la descarga             (--keep la conserva para inspección)
#
# Guardas — las dos son la misma regla: no fabricar un ciclo cerrado falso.
#   · Si la llamada YA tiene transcript ≥ --min-chars se niega sin --force:
#     ese transcript es de la plataforma y pisarlo destruye evidencia.
#   · Si el STT devuelve < --min-chars NO persiste nada (ni el status):
#     un transcript basura con status 'completed' es exactamente el hueco
#     que estamos reparando, no hay que crearlo de nuevo.
#
# El costo real es el paso 3 (AssemblyAI cobra por minuto): el script
# transcribe UNA vez y solo toca la DB si el resultado es usable.
#
# Uso: procesar_video.sh <meeting-id|prefix> [--file-id ID] [--min-chars N]
#                        [--force] [--keep] [--dry-run] [--json]
#   --file-id ID   video concreto del Drive (default: meetings.drive_file_id,
#                  o el archivo más grande cruzado en la sqlite closer_calls)
#   --min-chars N  umbral de transcript usable (default 2000, el del pipeline)
#   --dry-run      todo el trabajo, pero la transacción hace ROLLBACK
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../lib/common.sh"          # psql_ro / psql_rw
source "$here/../google/lib/common.sh"   # MKT_BASE + MKT_BEARER (descarga)
source "$here/../lib/sqlite.sh"          # cruce local closer_calls (fallback)

FORMAT="${FORMAT:-table}"
ref="" file_id="" min_chars=2000 force=0 keep=0 dry=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file-id) file_id="$2"; shift 2 ;;
    --min-chars) min_chars="$2"; shift 2 ;;
    --force) force=1; shift ;;
    --keep) keep=1; shift ;;
    --dry-run) dry=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,31p' "$0"; exit 0 ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) ref="$1"; shift ;;
  esac
done
[[ -n "$ref" ]] || { echo "Uso: procesar_video.sh <meeting-id|prefix> [--file-id ID] …" >&2; exit 2; }

# ── resolver el meeting (prefijo de uuid; ambiguo = error)
row="$(psql_ro -t -A -F'|' -c "
SELECT m.id, m.name, m.status, coalesce(m.drive_file_id,''),
       coalesce(length(mt.transcript),0)
FROM meetings m LEFT JOIN meeting_transcripts mt ON mt.meeting_id=m.id
WHERE m.meeting_type='call' AND m.id::text LIKE '$(printf '%s' "$ref" | tr -cd 'a-f0-9-')%';")"
n="$(grep -c . <<<"${row:-}")" || true
[[ "$n" == 1 ]] || { echo "meeting '$ref': $n coincidencias (se necesita exactamente 1)" >&2; exit 1; }
IFS='|' read -r mid mname mstatus m_fid tr_chars <<<"$row"
echo "llamada: $mname [$mstatus] — transcript actual: $tr_chars chars" >&2

if (( tr_chars >= min_chars && force == 0 )); then
  echo "Ya tiene transcript usable ($tr_chars ≥ $min_chars) — esa llamada va por el pipeline normal (generar_pendientes.sh). --force para pisarlo." >&2
  exit 1
fi

# ── resolver el video: flag > meetings.drive_file_id > snapshot local (el más grande)
if [[ -z "$file_id" ]]; then
  file_id="$m_fid"
  if [[ -z "$file_id" ]]; then
    dbp="$(db_path closer_calls)"
    [[ -f "$dbp" ]] && file_id="$(sqlite_ro "$dbp" \
      "SELECT file_id FROM archivos WHERE meeting_id='$mid' ORDER BY size_bytes DESC LIMIT 1;")"
  fi
fi
[[ -n "$file_id" ]] || { echo "Sin video: ni meetings.drive_file_id ni cruce en closer_calls. Pásalo con --file-id." >&2; exit 1; }

wd="$(mktemp -d)"
cleanup() { (( keep )) && echo "descarga conservada en $wd" >&2 || rm -rf "$wd"; }
trap cleanup EXIT

# ── 1. descarga (binaria, mismo bearer que mapi)
echo "1/5 descargando $file_id …" >&2
code="$(curl -sSL "$MKT_BASE/drive/files/$file_id/download" \
  -H @<(printf 'Authorization: Bearer %s\n' "$MKT_BEARER") \
  -o "$wd/video.mp4" -w '%{http_code}')"
[[ "$code" == 2* ]] || { echo "descarga HTTP $code: $(head -c 300 "$wd/video.mp4")" >&2; exit 1; }
echo "   $(stat -c%s "$wd/video.mp4" | awk '{printf "%.1f MB", $1/1048576}')" >&2

# ── 2. audio
echo "2/5 extrayendo audio…" >&2
"$here/../audio/extract_audio.sh" "$wd/video.mp4" --out "$wd/audio.mp3" >&2

# ── 3. STT
echo "3/5 transcribiendo (AssemblyAI)…" >&2
"$here/../audio/stt/assemblyai.sh" "$wd/audio.mp3" --out "$wd/transcript.txt" --raw "$wd/stt-raw.json" >/dev/null
chars="$(wc -c < "$wd/transcript.txt")"
echo "   transcript: $chars chars" >&2

if (( chars < min_chars )); then
  keep=1  # conservar la evidencia para inspección
  echo "STT devolvió $chars chars (< $min_chars) — NO se persiste (llamada sin contenido real). Revisa $wd/transcript.txt" >&2
  exit 1
fi

# ── 4. persistir (una txn): transcript + status
echo "4/5 persistiendo en la DB…" >&2
python3 - "$mid" "$wd/transcript.txt" "$dry" > "$wd/persist.sql" <<'PY'
import sys
mid, path, dry = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
txt = open(path, encoding="utf-8").read().strip().replace("'", "''")
print("BEGIN;")
print(f"""INSERT INTO meeting_transcripts (meeting_id, transcript)
VALUES ('{mid}', '{txt}')
ON CONFLICT (meeting_id) DO UPDATE SET transcript=EXCLUDED.transcript, updated_at=now();""")
print(f"UPDATE meetings SET status='completed', updated_at=now() WHERE id='{mid}';")
print(f"SELECT status, length(mt.transcript) AS chars FROM meetings m JOIN meeting_transcripts mt ON mt.meeting_id=m.id WHERE m.id='{mid}';")
print("ROLLBACK;" if dry else "COMMIT;")
PY
psql_rw -f "$wd/persist.sql" >&2

# ── 5. limpiar
(( dry )) && echo "(dry-run: la transacción se revirtió)" >&2
echo "5/5 listo." >&2

if [[ "$FORMAT" == json ]]; then
  python3 -c 'import json,sys; print(json.dumps({"meeting_id":sys.argv[1],"name":sys.argv[2],"file_id":sys.argv[3],"chars":int(sys.argv[4]),"status_antes":sys.argv[5],"persistido":sys.argv[6]!="1"}))' \
    "$mid" "$mname" "$file_id" "$chars" "$mstatus" "$dry"
else
  echo "✓ $mname: transcript $chars chars, status $mstatus → completed$( ((dry)) && echo ' (dry-run, revertido)')"
fi

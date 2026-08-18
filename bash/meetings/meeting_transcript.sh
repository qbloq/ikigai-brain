#!/usr/bin/env bash
# Print the raw transcript text of a meeting.
#
# Usage:  meeting_transcript.sh <id|prefix>
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

idarg="${1:-}"
[[ -z "$idarg" || "$idarg" == "-h" || "$idarg" == "--help" ]] && { sed -n '2,5p' "$0"; exit 0; }
idarg="${idarg//\'/}"

mid="$(psql_ro -t -A -c "SELECT id FROM meetings WHERE id::text LIKE '${idarg}%' LIMIT 2;" | head -1)"
[[ -z "$mid" ]] && { echo "No meeting matches: $idarg" >&2; exit 1; }

txt="$(psql_ro -t -A -c "SELECT transcript FROM meeting_transcripts WHERE meeting_id='$mid' ORDER BY created_at LIMIT 1;")"
[[ -z "$txt" ]] && { echo "No transcript for: $idarg" >&2; exit 1; }

# 36% de los transcripts de llamada (84 de 235 con reporte) NO están guardados
# como texto sino como un Buffer de Node serializado a JSON:
#   {"type":"Buffer","data":[35,32,84,...]}
# Es un bug del lado que escribe, no del dato: decodificado sale el transcript
# íntegro (el más largo, 529k almacenados, son 141k de texto real — el inflado
# es de ~3.7x porque cada byte ocupa 3-4 caracteres de dígitos y coma).
# Se decodifica aquí, en la LECTURA, para que ningún consumidor tenga que saber
# de esto. Arreglarlo en la escritura sigue pendiente y es de otro repo.
if [[ "$txt" == '{"type":"Buffer"'* ]]; then
  printf '%s' "$txt" | python3 -c '
import json, sys
o = json.load(sys.stdin)
try:
    sys.stdout.write(bytes(o["data"]).decode("utf-8", errors="replace") + "\n")
    sys.stdout.flush()
except BrokenPipeError:   # el consumidor cerró (| head); no es un error
    sys.exit(0)
' 2>/dev/null
else
  printf '%s\n' "$txt"
fi

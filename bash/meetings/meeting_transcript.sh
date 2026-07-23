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
printf '%s\n' "$txt"

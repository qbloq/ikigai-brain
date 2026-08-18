#!/usr/bin/env bash
# Frescura del índice de Drive: cuántos items tiene, cuándo se sincronizó por
# última vez, y el estado de la corrida en curso (si la hay).
#
# Usage: drive_status.sh [--json]
#
# Solo GET (`/drive/index/status`). Es el gemelo de lectura de `drive_sync.sh`
# —que dispara— y existe separado a propósito: el visor necesita la frescura, y
# apuntarlo a drive_sync.sh sería colgar un botón de disparo de una fuente de
# lectura (el whitelist de flags del viz solo emite lo declarado, así que una
# llamada sin --status lanzaría un barrido).
#
# La frescura no es adorno: el índice es un caché que envejece, y sin un número
# al lado, una respuesta vieja se lee como una respuesta actual.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/common.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)    FORMAT=json; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1 (see -h)" >&2; exit 1 ;;
  esac
done

json="$(mapi GET "/drive/index/status")"

if [[ "$FORMAT" == "json" ]]; then printf '%s\n' "$json"; exit 0; fi

python3 - "$json" <<'PY'
import json, sys
s = json.loads(sys.argv[1])
synced = (s.get("synced_at") or "?")[:16].replace("T", " ")
age = s.get("age_hours")
print(f'índice   {s.get("items", "?")} items · sync {synced} (hace {age if age is not None else "?"}h)')
if age is not None and age > 48:
    print(f'⚠  {age}h sin refrescar — lo más nuevo del Drive NO está en el índice.')
    print('   refréscalo con: drive_sync.sh --wait')
if s.get("running"):
    print(f'corrida  EN CURSO desde {(s.get("run_started_at") or "")[:19].replace("T", " ")}')
elif s.get("last_error"):
    print(f'corrida  FALLÓ: {s["last_error"]}')
elif s.get("last_summary"):
    r = s["last_summary"]
    print(f'corrida  ok · {r.get("items")} items ({r.get("folders")} carpetas, '
          f'{r.get("files")} archivos) · {r.get("pruned", 0)} podados · '
          f'{round(r.get("durationMs", 0) / 1000)}s')
PY

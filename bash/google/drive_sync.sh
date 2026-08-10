#!/usr/bin/env bash
# Refrescar el índice de Drive del backend. **[WRITE]**
#
# Usage:
#   drive_sync.sh [--all-drives] [--trashed] [--wait] [--timeout N] [--status] [--json]
#
#   --all-drives  incluir Shared Drives (por defecto solo My Drive)
#   --trashed     incluir la papelera
#   --wait        esperar a que termine y reportar el resumen (default: no espera)
#   --timeout N   segundos máximos de espera con --wait (default 600)
#   --status      solo consultar el estado, sin disparar nada
#
# La ÚNICA excepción a la regla read-only de bash/google/: el resto de la capa
# solo hace GET. Esta escribe — dispara `indexDrive.js` en el backend, que hace
# upsert de todo el Drive en `drive_index` y **poda** lo que ya no existe.
#
# Existe porque hasta hoy refrescar el índice pedía entrar por SSH al servidor,
# así que nadie lo hacía: el 2026-08-04 llevaba desde el 27-jul sin correr y 8
# días de actividad real eran invisibles. Un caché viejo no contesta «no pasó
# nada», no contesta — y se lee igual.
#
# Un barrido tarda ~1 min sobre ~18k items. El backend responde 202 y sigue en
# background; con --wait este script hace polling de /drive/index/status.
# Una corrida ya en curso devuelve 409: nunca se lanzan dos barridos.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/common.sh"

all_drives=0 trashed=0 wait=0 timeout=600 only_status=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all-drives) all_drives=1; shift ;;
    --trashed)    trashed=1; shift ;;
    --wait)       wait=1; shift ;;
    --timeout)    timeout="$2"; shift 2 ;;
    --status)     only_status=1; shift ;;
    --json)       FORMAT=json; shift ;;
    -h|--help)    sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1 (see -h)" >&2; exit 1 ;;
  esac
done

# Render del estado. Con FORMAT=json escupe el objeto crudo del backend.
show_status() {
  local json="$1"
  if [[ "$FORMAT" == "json" ]]; then printf '%s\n' "$json"; return; fi
  python3 - "$json" <<'PY'
import json, sys
s = json.loads(sys.argv[1])
synced = (s.get("synced_at") or "?")[:16].replace("T", " ")
age = s.get("age_hours")
print(f'índice   {s.get("items", "?")} items · sync {synced} (hace {age if age is not None else "?"}h)')
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
}

if [[ "$only_status" == 1 ]]; then
  show_status "$(mapi GET "/drive/index/status")"
  exit 0
fi

# --- Disparar ---------------------------------------------------------------
# El 409 (ya hay una corrida) no es un fallo del que informar como error: es
# información. Se reporta y se sigue al polling si venía --wait.
q=""
[[ "$all_drives" == 1 ]] && q="${q}&allDrives=true"
[[ "$trashed" == 1 ]] && q="${q}&trashed=true"
q="${q#&}"

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
code="$(curl -sS -X POST "$MKT_BASE/drive/index${q:+?$q}" \
  -H "Authorization: Bearer ${MKT_BEARER}" -o "$tmp" -w '%{http_code}')"

case "$code" in
  202) echo "barrido lanzado ($(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["started_at"][:19].replace("T"," "))' "$tmp") UTC)" >&2 ;;
  409) echo "ya había un barrido en curso — no se lanzó otro" >&2 ;;
  404) echo "el backend aún no expone POST /drive/index (pendiente de desplegar)" >&2; exit 4 ;;
  *)   echo "mkt api HTTP $code:" >&2; head -c 300 "$tmp" >&2; echo >&2; exit 1 ;;
esac

if [[ "$wait" == 0 ]]; then
  echo "sigue con: $(basename "$0") --status" >&2
  exit 0
fi

# --- Esperar ----------------------------------------------------------------
deadline=$(( SECONDS + timeout ))
while :; do
  st="$(mapi GET "/drive/index/status")"
  running="$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["running"])' "$st")"
  [[ "$running" == "False" ]] && break
  if (( SECONDS > deadline )); then
    echo "⚠  timeout tras ${timeout}s — el barrido SIGUE corriendo en el backend." >&2
    echo "   consúltalo con: $(basename "$0") --status" >&2
    show_status "$st"
    exit 5
  fi
  sleep 5
done

show_status "$st"
python3 -c 'import json,sys;sys.exit(1 if json.loads(sys.argv[1]).get("last_error") else 0)' "$st"

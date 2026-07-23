#!/usr/bin/env bash
# auth_status.sh [--json]
#
# Read-only. Show how this workspace reaches the org's Drive: the mode
# (copiloto vía proxy · cerebro directo), the base, and a live probe against
# the mkt API. Las credenciales de Google viven en el backend — aquí no hay
# token de Google que inspeccionar.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/common.sh"

for a in "$@"; do
  case "$a" in
    --json) FORMAT=json;;
    -h|--help) sed -n '2,7p' "$0"; exit 0;;
    *) echo "unknown arg: $a" >&2; exit 1;;
  esac
done

# probe: stats del índice si está desplegado; si no, la raíz live
alcanza=false probe="" n=""
if out="$(mapi GET "/drive/index/stats" 2>/dev/null)"; then
  alcanza=true probe="index/stats"
  # stats = [{type, count, total_size}…] → total de archivos indexados
  n="$(printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(sum(t.get("count",0) for t in d) if isinstance(d, list) else d.get("total",""))' 2>/dev/null || true)"
elif out="$(mapi GET "/drive/contents" 2>/dev/null)"; then
  alcanza=true probe="contents (raíz live)"
  n="$(printf '%s' "$out" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || true)"
fi

if [[ "$FORMAT" == "json" ]]; then
  python3 - "$MKT_MODE" "$MKT_BASE" "$alcanza" "$probe" "$n" <<'PY'
import json, sys
mode, base, ok, probe, n = sys.argv[1:6]
print(json.dumps({
    "modo": mode, "base": base, "alcanza": ok == "true",
    "probe": probe or None, "items_visibles": int(n) if n.isdigit() else None,
}, indent=2, ensure_ascii=False))
PY
else
  echo "modo     $MKT_MODE $( [[ "$MKT_MODE" == proxy ]] && echo '(copiloto → forja-proxy → backend)' || echo '(cerebro → backend directo)')"
  echo "base     $MKT_BASE"
  if [[ "$alcanza" == true ]]; then
    echo "alcanza  sí — probe: $probe${n:+ ($n items)}"
  else
    echo "alcanza  NO — revisa credenciales (.env) o la salud del backend"
    exit 1
  fi
fi

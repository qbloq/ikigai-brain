#!/usr/bin/env bash
# [WRITE → Meta] Crea una plantilla en el WABA del Cerebro (690499003502578).
# Queda en revisión — no es usable hasta que Meta la marque APPROVED (las 4
# plantillas de closers llevan desde el 12-ago en PENDING, cuenta con días).
# No hay upsert: si el nombre ya existe Meta rechaza (borrar a mano en
# Business Manager para reintentar con el mismo nombre).
#
# Usage:
#   plantilla_crear.sh --nombre N --categoria UTILITY|MARKETING \
#     --cuerpo "texto con {{1}} {{2}}..." [--ejemplos "a|b"] [--lang es_CO] \
#     [--dry-run] [--json]
# Token: $WABA_TOKEN, .env, o el access_token del config zeroclaw (inline) —
# mismo mecanismo que bash/closers/enviar.sh. Necesita permiso
# whatsapp_business_management, no solo whatsapp_business_messaging.
set -euo pipefail
cd "$(dirname "$0")/../.."

WABA_ID="690499003502578"
NOMBRE=""; CATEGORIA=""; CUERPO=""; EJEMPLOS=""; LANG_T="es_CO"; DRY=0; FORMAT=text
while [[ $# -gt 0 ]]; do
  case "$1" in
    --nombre) NOMBRE="$2"; shift 2 ;;
    --categoria) CATEGORIA="$2"; shift 2 ;;
    --cuerpo) CUERPO="$2"; shift 2 ;;
    --ejemplos) EJEMPLOS="$2"; shift 2 ;;
    --lang) LANG_T="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$NOMBRE" && -n "$CATEGORIA" && -n "$CUERPO" ]] || { echo "Faltan --nombre/--categoria/--cuerpo" >&2; exit 2; }
[[ "$NOMBRE" =~ ^[a-z0-9_]+$ ]] || { echo "--nombre debe ser [a-z0-9_]" >&2; exit 2; }
[[ "$CATEGORIA" == "UTILITY" || "$CATEGORIA" == "MARKETING" ]] || { echo "--categoria debe ser UTILITY|MARKETING" >&2; exit 2; }

TOKEN="${WABA_TOKEN:-}"
if [[ -z "$TOKEN" && -f .env ]]; then
  TOKEN="$(grep -E '^WABA_TOKEN=' .env | head -1 | cut -d= -f2- || true)"
fi
if [[ -z "$TOKEN" ]]; then
  TOKEN="$(grep -E '^access_token = "' "$HOME/.zeroclaw/config.toml" 2>/dev/null | sed 's/access_token = "//; s/"$//' || true)"
  [[ "$TOKEN" == enc2:* ]] && TOKEN=""
fi
[[ -n "$TOKEN" ]] || { echo "Sin token WABA" >&2; exit 1; }

WABA_ID="$WABA_ID" TOKEN="$TOKEN" NOMBRE="$NOMBRE" CATEGORIA="$CATEGORIA" \
CUERPO="$CUERPO" EJEMPLOS="$EJEMPLOS" LANG_T="$LANG_T" DRY="$DRY" FORMAT="$FORMAT" python3 - <<'PY'
import json, os, sys, urllib.request

env = os.environ
ejemplos = [e for e in env["EJEMPLOS"].split("|") if e] if env["EJEMPLOS"] else []
componente = {"type": "BODY", "text": env["CUERPO"]}
if ejemplos:
    componente["example"] = {"body_text": [ejemplos]}

payload = {
    "name": env["NOMBRE"], "language": env["LANG_T"],
    "category": env["CATEGORIA"], "components": [componente],
}

if env["DRY"] == "1":
    if env["FORMAT"] == "json":
        print(json.dumps({"estado": "crearía", **payload}, ensure_ascii=False))
    else:
        print(f"crearía: {json.dumps(payload, ensure_ascii=False, indent=2)}")
    sys.exit(0)

req = urllib.request.Request(
    f"https://graph.facebook.com/v18.0/{env['WABA_ID']}/message_templates",
    data=json.dumps(payload).encode(),
    headers={"Authorization": f"Bearer {env['TOKEN']}", "Content-Type": "application/json"})
try:
    with urllib.request.urlopen(req, timeout=20) as r:
        resp = json.load(r)
except urllib.error.HTTPError as e:
    detalle = e.read().decode()[:500]
    if env["FORMAT"] == "json":
        print(json.dumps({"estado": "fallido", "error": detalle}, ensure_ascii=False))
    else:
        print(f"error: {detalle}", file=sys.stderr)
    sys.exit(1)

if env["FORMAT"] == "json":
    print(json.dumps({"estado": "creada", **resp}, ensure_ascii=False))
else:
    print(f"id={resp.get('id')} estado={resp.get('status')} categoria={resp.get('category')}")
PY

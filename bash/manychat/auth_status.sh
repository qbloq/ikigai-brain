#!/usr/bin/env bash
# auth_status.sh — qué tokens de ManyChat hay en .env y A QUÉ PÁGINA responde
# cada uno. Sonda read-only contra api.manychat.com (GET /fb/page/getInfo, la
# llamada autenticada más liviana): nombre, usuario, id, plan y zona horaria de
# la página detrás de cada token.
#
# Existe para responder «tengo dos tokens, ¿cuál es cuál?»: los tokens de
# ManyChat son POR PÁGINA, así que lo normal es que cada uno sea una cuenta
# distinta (p.ej. David Guerrero vs Andrea Torres), no una versión vieja del
# mismo. Patrón bash/vturb/: el token nunca se imprime ni viaja en argv (va a
# curl por stdin como header); aquí solo se ve un prefijo para reconocerlo.
#
# Uso: auth_status.sh [--json]
#   Lee TODAS las variables MANYCHAT_TOKEN* de .env (MANYCHAT_TOKEN_A,
#   MANYCHAT_TOKEN_DG, …); el nombre de la variable es la etiqueta. Sin ninguna,
#   sale 1 con la instrucción de dónde ponerlas.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

FORMAT="${FORMAT:-table}"
for a in "$@"; do
  case "$a" in
    --json) FORMAT=json ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $a" >&2; exit 2 ;;
  esac
done

MC_BASE="${MANYCHAT_BASE:-https://api.manychat.com}"
vars=(); while IFS= read -r l; do [[ -n "$l" ]] && vars+=("$l"); done < <(compgen -v | grep -E '^MANYCHAT_TOKEN' | sort)
if (( ${#vars[@]} == 0 )); then
  echo "Sin tokens: agrega MANYCHAT_TOKEN_A=… (y _B, …) a $REPO_ROOT/.env — nunca por chat ni argv." >&2
  exit 1
fi

rows="[]"
for v in "${vars[@]}"; do
  tok="${!v}"
  pref="${tok:0:6}…"
  resp="$(curl -sS --max-time 20 "$MC_BASE/fb/page/getInfo" \
    -H @<(printf 'Authorization: Bearer %s\n' "$tok") \
    -H 'Accept: application/json' -w '\n%{http_code}' 2>/dev/null || echo -e '\n000')"
  code="${resp##*$'\n'}"; body="${resp%$'\n'*}"
  rows="$(ROWS="$rows" V="$v" P="$pref" C="$code" B="$body" python3 - <<'PY'
import json, os
rows = json.loads(os.environ["ROWS"])
code = os.environ["C"]
try: b = json.loads(os.environ["B"] or "{}")
except Exception: b = {}
d = b.get("data") or {}
rows.append({
  "variable": os.environ["V"], "token": os.environ["P"], "http": code,
  "ok": code == "200" and b.get("status") == "success",
  "pagina": d.get("name"), "usuario": d.get("username"), "page_id": d.get("id"),
  "plan": ("pro" if d.get("is_pro") else ("free" if d else None)),
  "timezone": d.get("timezone"),
  "error": (None if code == "200" else (b.get("message") or b.get("details") or f"HTTP {code}")),
})
print(json.dumps(rows, ensure_ascii=False))
PY
)"
done

if [[ "$FORMAT" == json ]]; then echo "$rows"; exit 0; fi
echo "$rows" | python3 -c '
import json,sys
rows=json.load(sys.stdin)
cols=["variable","token","ok","pagina","usuario","page_id","plan","timezone","error"]
w={c:max(len(c),*(len(str(r.get(c) if r.get(c) is not None else "—")) for r in rows)) for c in cols}
print("  ".join(c.ljust(w[c]) for c in cols)); print("  ".join("-"*w[c] for c in cols))
for r in rows: print("  ".join(str(r.get(c) if r.get(c) is not None else "—").ljust(w[c]) for c in cols))
print(f"({len(rows)} tokens)")'

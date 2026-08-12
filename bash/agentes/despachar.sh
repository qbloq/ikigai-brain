#!/usr/bin/env bash
# [WRITE → WhatsApp] Ejecuta las filas APROBADAS de la cola de despacho:
# resuelve el destinatario en `directorio` (nombre → E.164) y envía el recado
# por WhatsApp Cloud API con la plantilla `recado_cerebro` (la vía legal para
# iniciar conversación fuera de la ventana de 24h). Registra wamid y estado.
#
# La ejecución corre DESDE LA CONVERSACIÓN con el cerebro (patrón
# merge_from_cruce.sh) — la Mesa solo aprueba.
#
# Token: $WABA_TOKEN, o WABA_TOKEN= en .env, o el access_token del config de
# zeroclaw (~/.zeroclaw/config.toml) mientras siga inline.
#
# Usage: despachar.sh [--n LISTA] [--plantilla NOMBRE] [--dry-run] [--json]
#   --n 3,5           solo esas filas (default: todas las aprobadas)
#   --plantilla NOM   plantilla Meta a usar (default recado_cerebro; la gemela
#                     MARKETING es recado_cerebro_mkt — usar la que esté APPROVED)
#   --dry-run         muestra qué enviaría, no envía ni escribe
set -euo pipefail
cd "$(dirname "$0")/../.."
source bash/lib/sqlite.sh

PNID="568780566329582"
PLANTILLA="recado_cerebro"; PLANTILLA_LANG="es_CO"
NLIST=""; DRY=0; FORMAT=text

while [[ $# -gt 0 ]]; do
  case "$1" in
    --n) NLIST="$2"; shift 2 ;;
    --plantilla) PLANTILLA="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ "$PLANTILLA" =~ ^[a-z0-9_]+$ ]] || { echo "--plantilla inválida" >&2; exit 2; }
[[ -z "$NLIST" || "$NLIST" =~ ^[0-9,]+$ ]] || { echo "--n debe ser lista numérica 3,5" >&2; exit 2; }

DB="$LOCALDB_DIR/mesa_despacho.db"
[[ -f "$DB" ]] || { echo "No existe $DB" >&2; exit 1; }

# ── token ──
TOKEN="${WABA_TOKEN:-}"
if [[ -z "$TOKEN" && -f .env ]]; then
  TOKEN="$(grep -E '^WABA_TOKEN=' .env | head -1 | cut -d= -f2- || true)"
fi
if [[ -z "$TOKEN" ]]; then
  TOKEN="$(grep -E '^access_token = "' "$HOME/.zeroclaw/config.toml" 2>/dev/null | sed 's/access_token = "//; s/"$//' || true)"
  [[ "$TOKEN" == enc2:* ]] && TOKEN=""
fi
[[ -n "$TOKEN" ]] || { echo "Sin token WABA: exporta WABA_TOKEN o agrégalo a .env" >&2; exit 1; }

WHERE="estado='aprobado'"
[[ -n "$NLIST" ]] && WHERE="$WHERE AND n IN ($NLIST)"

DB="$DB" TOKEN="$TOKEN" PNID="$PNID" PLANTILLA="$PLANTILLA" LANG_T="$PLANTILLA_LANG" \
WHERE="$WHERE" DRY="$DRY" FORMAT="$FORMAT" python3 - <<'PY'
import json, os, re, sqlite3, sys, urllib.request

db, token, pnid = os.environ["DB"], os.environ["TOKEN"], os.environ["PNID"]
plantilla, lang = os.environ["PLANTILLA"], os.environ["LANG_T"]
where, dry, fmt = os.environ["WHERE"], os.environ["DRY"] == "1", os.environ["FORMAT"]

con = sqlite3.connect(db)
con.row_factory = sqlite3.Row
filas = list(con.execute(f"SELECT * FROM despachos WHERE {where} ORDER BY n"))
directorio = {r["nombre"].lower(): r["numero"] for r in con.execute("SELECT nombre, numero FROM directorio")}

def resolver(para):
    # Gana la coincidencia MÁS LARGA («marisol ochoa» antes que «mari») para
    # que los alias cortos no capturen nombres completos por substring.
    p = para.lower()
    for nombre in sorted(directorio, key=len, reverse=True):
        if nombre in p:
            return nombre, directorio[nombre]
    return None, None

def limpiar(s):
    # Las variables de plantilla no aceptan saltos de línea ni 4+ espacios.
    return re.sub(r"\s+", " ", s or "").strip()

def enviar(numero, destinatario, de, que):
    payload = {
        "messaging_product": "whatsapp", "to": numero.lstrip("+"),
        "type": "template",
        "template": {"name": plantilla, "language": {"code": lang},
                     "components": [{"type": "body", "parameters": [
                         {"type": "text", "text": limpiar(destinatario)},
                         {"type": "text", "text": limpiar(de)},
                         {"type": "text", "text": limpiar(que)}]}]}}
    req = urllib.request.Request(
        f"https://graph.facebook.com/v18.0/{pnid}/messages",
        data=json.dumps(payload).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.load(r), None
    except urllib.error.HTTPError as e:
        return None, e.read().decode()[:400]
    except Exception as e:
        return None, str(e)

resultados = []
for f in filas:
    nombre, numero = resolver(f["para"])
    r = {"n": f["n"], "recado": f["recado_id"][:8], "para": f["para"], "numero": numero}
    if not numero:
        r["resultado"] = "sin_directorio"
        if not dry:
            con.execute("UPDATE despachos SET nota=coalesce(nota,'')||' | sin número en directorio' WHERE n=?", (f["n"],))
    elif dry:
        r["resultado"] = "enviaría"
    else:
        resp, err = enviar(numero, f["para"], f["de"], f["que"])
        if resp:
            wamid = (resp.get("messages") or [{}])[0].get("id", "")
            r["resultado"], r["wamid"] = "ejecutado", wamid
            con.execute("UPDATE despachos SET estado='ejecutado', ejecutado_at=datetime('now','localtime'), wamid=?, destino_numero=? WHERE n=?",
                        (wamid, numero, f["n"]))
        else:
            r["resultado"], r["error"] = "fallido", err
            con.execute("UPDATE despachos SET estado='fallido', nota=coalesce(nota,'')||' | error: '||? WHERE n=?",
                        (err[:200], f["n"]))
    resultados.append(r)
if not dry:
    con.commit()

if fmt == "json":
    print(json.dumps({"dry_run": dry, "despachos": resultados}, ensure_ascii=False))
else:
    if not resultados:
        print("Nada aprobado por despachar."); sys.exit(0)
    for r in resultados:
        extra = r.get("wamid") or r.get("error", "") or (r["numero"] or "—")
        print(f"n={r['n']} {r['recado']} → {r['para']}: {r['resultado']}  {extra[:80]}")
PY

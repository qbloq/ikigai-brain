#!/usr/bin/env bash
# [WRITE → WhatsApp] El enviador ÚNICO de los escenarios de closers: manda un
# mensaje de sesión (texto libre, requiere ventana de 24h abierta) o una
# plantilla Meta aprobada, y registra TODO en la sqlite local `closers_ops`
# (tabla envios) con clave de idempotencia (escenario, ref) — reintentar un
# escenario jamás duplica un mensaje.
#
# Si un mensaje de sesión rebota por ventana cerrada (error 131047) y se pasó
# --fallback-plantilla, reintenta automáticamente como plantilla con el mismo
# cuerpo colapsado a una línea (las variables de plantilla no aceptan saltos).
#
# Puente Cerebro→Iki: cada envío exitoso deja constancia en la memoria del
# Agente (bash/agentes/aviso_iki.sh — best-effort) para que Iki tenga el
# contexto cuando el destinatario responda por el mismo chat.
#
# Usage:
#   enviar.sh --para <+E164|nombre> --texto "..."            [opciones]
#   enviar.sh --para <+E164|nombre> --plantilla N --vars "a|b|c" [opciones]
# Opciones:
#   --escenario S --ref R   clave de idempotencia (default: manual / timestamp)
#   --closer NOMBRE         etiqueta para el log (default: el --para resuelto)
#   --lang CODE             idioma de la plantilla (default es_CO)
#   --fallback-plantilla N  plantilla si la sesión rebota (vars: nombre|cuerpo)
#   --dry-run               muestra qué enviaría, no envía ni escribe
#   --json
# Token: $WABA_TOKEN, .env, o el access_token del config zeroclaw (inline).
set -euo pipefail
cd "$(dirname "$0")/../.."
source bash/lib/sqlite.sh

PNID="568780566329582"
PARA=""; TEXTO=""; PLANTILLA=""; VARS=""; LANG_T="es_CO"
ESCENARIO="manual"; REF=""; CLOSER=""; FALLBACK=""; DRY=0; FORMAT=text
while [[ $# -gt 0 ]]; do
  case "$1" in
    --para) PARA="$2"; shift 2 ;;
    --texto) TEXTO="$2"; shift 2 ;;
    --plantilla) PLANTILLA="$2"; shift 2 ;;
    --vars) VARS="$2"; shift 2 ;;
    --lang) LANG_T="$2"; shift 2 ;;
    --escenario) ESCENARIO="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    --closer) CLOSER="$2"; shift 2 ;;
    --fallback-plantilla) FALLBACK="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$PARA" ]] || { echo "--para es obligatorio" >&2; exit 2; }
[[ -n "$TEXTO" || -n "$PLANTILLA" ]] || { echo "Falta --texto o --plantilla" >&2; exit 2; }
[[ -z "$PLANTILLA" || "$PLANTILLA" =~ ^[a-z0-9_]+$ ]] || { echo "--plantilla inválida" >&2; exit 2; }
[[ -z "$FALLBACK" || "$FALLBACK" =~ ^[a-z0-9_]+$ ]] || { echo "--fallback-plantilla inválida" >&2; exit 2; }
[[ -n "$REF" ]] || REF="$(date +%s)"

OPS_DB="$LOCALDB_DIR/closers_ops.db"
MESA_DB="$LOCALDB_DIR/mesa_despacho.db"

# ── token (mismo patrón que despachar.sh) ──
TOKEN="${WABA_TOKEN:-}"
if [[ -z "$TOKEN" && -f .env ]]; then
  TOKEN="$(grep -E '^WABA_TOKEN=' .env | head -1 | cut -d= -f2- || true)"
fi
if [[ -z "$TOKEN" ]]; then
  TOKEN="$(grep -E '^access_token = "' "$HOME/.zeroclaw/config.toml" 2>/dev/null | sed 's/access_token = "//; s/"$//' || true)"
  [[ "$TOKEN" == enc2:* ]] && TOKEN=""
fi
[[ -n "$TOKEN" ]] || { echo "Sin token WABA" >&2; exit 1; }

# ── esquema (idempotente) ──
sqlite3 "$OPS_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS envios(
  n INTEGER PRIMARY KEY AUTOINCREMENT,
  fecha TEXT NOT NULL,
  escenario TEXT NOT NULL,
  ref TEXT NOT NULL,
  closer TEXT, numero TEXT NOT NULL,
  tipo TEXT NOT NULL,
  plantilla TEXT, cuerpo TEXT,
  wamid TEXT, estado TEXT NOT NULL,
  error TEXT,
  creado_at TEXT DEFAULT (datetime('now','localtime')),
  UNIQUE(escenario, ref)
);
CREATE TABLE IF NOT EXISTS resultados(
  n INTEGER PRIMARY KEY AUTOINCREMENT,
  fecha TEXT, closer TEXT, lead TEXT, meeting_id TEXT,
  resultado TEXT, detalle TEXT, origen TEXT DEFAULT 'iki',
  registrado_api INTEGER DEFAULT 0,
  creado_at TEXT DEFAULT (datetime('now','localtime'))
);
SQL

OPS_DB="$OPS_DB" MESA_DB="$MESA_DB" TOKEN="$TOKEN" PNID="$PNID" \
PARA="$PARA" TEXTO="$TEXTO" PLANTILLA="$PLANTILLA" VARS="$VARS" LANG_T="$LANG_T" \
ESCENARIO="$ESCENARIO" REF="$REF" CLOSER="$CLOSER" FALLBACK="$FALLBACK" \
DRY="$DRY" FORMAT="$FORMAT" python3 - <<'PY'
import json, os, re, sqlite3, sys, urllib.request

env = os.environ
dry, fmt = env["DRY"] == "1", env["FORMAT"]
escenario, ref = env["ESCENARIO"], env["REF"]

def salir(obj):
    if fmt == "json": print(json.dumps(obj, ensure_ascii=False))
    else: print(" ".join(f"{k}={v}" for k, v in obj.items() if v))
    sys.exit(0 if obj.get("estado") in ("enviado", "omitido", "enviaría") else 1)

# ── resolver destinatario ──
para = env["PARA"].strip()
if para.startswith("+"):
    numero, nombre = para, env["CLOSER"] or para
else:
    con_m = sqlite3.connect(env["MESA_DB"])
    directorio = {r[0].lower(): r[1] for r in con_m.execute("SELECT nombre, numero FROM directorio")}
    con_m.close()
    p = para.lower()
    nombre, numero = None, None
    for cand in sorted(directorio, key=len, reverse=True):
        if cand in p or p in cand:
            nombre, numero = cand, directorio[cand]; break
    if not numero:
        salir({"estado": "fallido", "error": f"'{para}' no está en el directorio"})
    nombre = env["CLOSER"] or nombre

con = sqlite3.connect(env["OPS_DB"])
ya = con.execute("SELECT estado, wamid FROM envios WHERE escenario=? AND ref=? AND estado='enviado'",
                 (escenario, ref)).fetchone()
if ya:
    salir({"estado": "omitido", "motivo": "ya enviado", "wamid": ya[1] or ""})

def limpiar(s):
    return re.sub(r"\s+", " ", s or "").strip()

def post(payload):
    req = urllib.request.Request(
        f"https://graph.facebook.com/v18.0/{env['PNID']}/messages",
        data=json.dumps(payload).encode(),
        headers={"Authorization": f"Bearer {env['TOKEN']}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.load(r), None
    except urllib.error.HTTPError as e:
        return None, e.read().decode()[:500]
    except Exception as e:
        return None, str(e)

def payload_sesion(texto):
    return {"messaging_product": "whatsapp", "to": numero.lstrip("+"),
            "type": "text", "text": {"preview_url": True, "body": texto}}

def payload_plantilla(nombre_t, variables):
    return {"messaging_product": "whatsapp", "to": numero.lstrip("+"), "type": "template",
            "template": {"name": nombre_t, "language": {"code": env["LANG_T"]},
                         "components": [{"type": "body", "parameters": [
                             {"type": "text", "text": limpiar(v)} for v in variables]}]}}

texto, plantilla, vars_raw = env["TEXTO"], env["PLANTILLA"], env["VARS"]
if plantilla:
    tipo, cuerpo = "plantilla", vars_raw
    intento = payload_plantilla(plantilla, vars_raw.split("|") if vars_raw else [])
else:
    tipo, cuerpo = "sesion", texto
    intento = payload_sesion(texto)

if dry:
    salir({"estado": "enviaría", "numero": numero, "tipo": tipo,
           "cuerpo": (cuerpo or "")[:120]})

resp, err = post(intento)
usada = plantilla
# ventana cerrada → fallback a plantilla si la hay
if resp is None and env["FALLBACK"] and tipo == "sesion" and "131047" in (err or ""):
    usada = env["FALLBACK"]
    resp, err = post(payload_plantilla(usada, [nombre.split()[0].title(), limpiar(texto)]))
    tipo = "plantilla-fallback"

fecha = __import__("subprocess").run(
    ["date", "+%F"], capture_output=True, text=True, env={**os.environ, "TZ": "America/Bogota"}
).stdout.strip()

if resp:
    wamid = (resp.get("messages") or [{}])[0].get("id", "")
    con.execute("""INSERT INTO envios(fecha,escenario,ref,closer,numero,tipo,plantilla,cuerpo,wamid,estado)
                   VALUES(?,?,?,?,?,?,?,?,?,'enviado')
                   ON CONFLICT(escenario,ref) DO UPDATE SET
                     wamid=excluded.wamid, estado='enviado', tipo=excluded.tipo, error=NULL""",
                (fecha, escenario, ref, nombre, numero, tipo, usada, (cuerpo or "")[:1000], wamid))
    con.commit()
    # Puente Cerebro→Iki: dejar constancia del envío en la SESIÓN del
    # destinatario para que el Agente tenga el contexto de esta conversación.
    # Best-effort: el mensaje ya salió — un aviso fallido se pierde, no revierte.
    try:
        aviso = texto if texto else f"[plantilla {usada}] {vars_raw}"
        __import__("subprocess").run(
            ["bash/agentes/aviso_iki.sh", "--numero", numero, "--persona", nombre,
             "--texto", aviso, "--escenario", escenario,
             "--ref", re.sub(r"[^A-Za-z0-9_-]", "-", ref)],
            capture_output=True, timeout=15)
    except Exception:
        pass
    salir({"estado": "enviado", "numero": numero, "tipo": tipo, "wamid": wamid})
else:
    con.execute("""INSERT INTO envios(fecha,escenario,ref,closer,numero,tipo,plantilla,cuerpo,estado,error)
                   VALUES(?,?,?,?,?,?,?,?,'fallido',?)
                   ON CONFLICT(escenario,ref) DO UPDATE SET
                     estado='fallido', error=excluded.error""",
                (fecha, escenario, ref, nombre, numero, tipo, usada, (cuerpo or "")[:1000], (err or "")[:400]))
    con.commit()
    salir({"estado": "fallido", "numero": numero, "error": (err or "")[:200]})
PY

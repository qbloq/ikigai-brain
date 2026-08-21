#!/usr/bin/env bash
# [WRITE → memoria de Iki] El ÚNICO escritor de avisos del Cerebro en la
# memoria del Agente (~/.zeroclaw/data/memory/brain.db): inserta una fila
# `AVISO DEL CEREBRO: enviado a <persona> el <fecha> (<escenario>): "<texto>"`
# EN LA SESIÓN del destinatario (session_id = whatsapp_<numero> sanitizado,
# category=conversation) para que Iki tenga el contexto de los mensajes que el
# Cerebro origina por WABA (bash/closers/enviar.sh) y la conversación sea UNA.
#
# ⚠️ Excepción declarada al rail sqlite_rw/LOCALDB_DIR: brain.db es la DB viva
# del daemon zeroclaw (WAL — escritor externo concurrente OK), esquema de
# upstream. Por eso: un solo escritor (este script), guard de schema_version
# (falla ruidoso si upstream migró), y NUNCA session_id NULL ni category
# daily/core — una fila global se inyectaría en la sesión de cualquiera.
#
# Idempotente por (escenario, ref): la key `aviso_cerebro_<escenario>_<ref>`
# es UNIQUE por agente — reintentar jamás duplica el aviso.
#
# Usage:
#   aviso_iki.sh --numero +E164 --texto "..." [--persona NOMBRE]
#                [--escenario S] [--ref R] [--dry-run] [--json]
set -euo pipefail
cd "$(dirname "$0")/../.."

BRAIN_DB="${IKI_BRAIN_DB:-$HOME/.zeroclaw/data/memory/brain.db}"
SCHEMA_ESPERADO=1

NUMERO=""; TEXTO=""; PERSONA=""; ESCENARIO="manual"; REF=""; DRY=0; FORMAT=text
while [[ $# -gt 0 ]]; do
  case "$1" in
    --numero) NUMERO="$2"; shift 2 ;;
    --texto) TEXTO="$2"; shift 2 ;;
    --persona) PERSONA="$2"; shift 2 ;;
    --escenario) ESCENARIO="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ "$NUMERO" =~ ^\+[0-9]{8,15}$ ]] || { echo "--numero debe ser E.164 (+57...)" >&2; exit 2; }
[[ -n "$TEXTO" ]] || { echo "--texto es obligatorio" >&2; exit 2; }
[[ "$ESCENARIO" =~ ^[a-z0-9_-]+$ ]] || { echo "--escenario inválido (a-z0-9_-)" >&2; exit 2; }
[[ -n "$REF" ]] || REF="$(date +%s)"
[[ "$REF" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "--ref inválido (A-Za-z0-9_-)" >&2; exit 2; }
[[ -f "$BRAIN_DB" ]] || { echo "No existe $BRAIN_DB" >&2; exit 1; }

BRAIN_DB="$BRAIN_DB" SCHEMA_ESPERADO="$SCHEMA_ESPERADO" NUMERO="$NUMERO" \
TEXTO="$TEXTO" PERSONA="$PERSONA" ESCENARIO="$ESCENARIO" REF="$REF" \
DRY="$DRY" FORMAT="$FORMAT" python3 - <<'PY'
import json, os, sqlite3, sys, uuid
from datetime import datetime, timezone, timedelta

env = os.environ
dry, fmt = env["DRY"] == "1", env["FORMAT"]

def salir(obj, code=None):
    if fmt == "json": print(json.dumps(obj, ensure_ascii=False))
    else: print(" ".join(f"{k}={v}" for k, v in obj.items() if v))
    sys.exit(code if code is not None
             else 0 if obj.get("estado") in ("insertado", "omitido", "insertaría") else 1)

con = sqlite3.connect(env["BRAIN_DB"], timeout=10)
con.execute("PRAGMA busy_timeout=10000")

# ── guards: el esquema es de upstream — si migró, parar ruidoso ──
v = con.execute("SELECT version FROM schema_version WHERE component='memories'").fetchone()
if not v or v[0] != int(env["SCHEMA_ESPERADO"]):
    salir({"estado": "fallido",
           "error": f"schema_version memories={v[0] if v else '?'} ≠ {env['SCHEMA_ESPERADO']} "
                    "(upstream migró brain.db — revisar el INSERT antes de seguir)"})
ag = con.execute("SELECT id FROM agents WHERE alias='default'").fetchone()
if not ag:
    salir({"estado": "fallido", "error": "no hay agente 'default' en brain.db"})
agent_id = ag[0]

# ── la fila: session-bound SIEMPRE (la frontera anti-leak de la inyección) ──
def sanitize(s):  # réplica de sanitize_session_key (zeroclaw-api/session_keys.rs)
    return "".join(c if c.isalnum() or c in "_-" else "_" for c in s)

numero, persona = env["NUMERO"], env["PERSONA"] or env["NUMERO"]
session_id = sanitize(f"whatsapp_{numero}")
key = f"aviso_cerebro_{env['ESCENARIO']}_{env['REF']}"
bogota = timezone(timedelta(hours=-5))
ahora = datetime.now(bogota)
content = (f'AVISO DEL CEREBRO: enviado a {persona} el '
           f'{ahora.strftime("%Y-%m-%d %H:%M")} ({env["ESCENARIO"]}): "{env["TEXTO"]}"')

ya = con.execute("SELECT 1 FROM memories WHERE agent_id=? AND key=?", (agent_id, key)).fetchone()
if ya:
    salir({"estado": "omitido", "motivo": "ya existe", "key": key})
if dry:
    salir({"estado": "insertaría", "key": key, "session_id": session_id,
           "content": content[:160]})

con.execute("""INSERT INTO memories(id, key, content, category, created_at, updated_at,
                                    session_id, namespace, importance, agent_id, pinned)
               VALUES(?,?,?,'conversation',?,?,?,'default',0.5,?,0)""",
            (str(uuid.uuid4()), key, content, ahora.isoformat(), ahora.isoformat(),
             session_id, agent_id))
con.commit()
salir({"estado": "insertado", "key": key, "session_id": session_id})
PY

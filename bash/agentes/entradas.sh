#!/usr/bin/env bash
# Las entradas a Iki: mensajes recibidos por el agente (memoria
# category='conversation' — el autosave guarda el lado del usuario; las
# respuestas del agente no se persisten hoy). READ-ONLY sobre brain.db.
#
# Usage: entradas.sh [--limit N] [--json]
#   --limit N   máximo de entradas (default 100; 0 = sin tope)
#   --json      [{id,fecha,canal,remitente,texto}] — fuente viz `iki_entradas`.
set -euo pipefail

ZC_DIR="${ZEROCLAW_DIR:-$HOME/.zeroclaw}"
DB="$ZC_DIR/data/memory/brain.db"
FORMAT=text; LIMIT=100

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) LIMIT="$2"; shift 2 ;;
    --json)  FORMAT=json; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -f "$DB" ]] || { echo "No existe $DB" >&2; exit 1; }
[[ "$LIMIT" =~ ^[0-9]+$ ]] || { echo "--limit debe ser numérico" >&2; exit 2; }

DB="$DB" LIMIT="$LIMIT" FORMAT="$FORMAT" python3 - <<'PY'
import json, os, re, sqlite3, sys

db, limit, fmt = os.environ["DB"], int(os.environ["LIMIT"]), os.environ["FORMAT"]
con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
sql = ("SELECT id, key, content, substr(created_at,1,19) FROM memories "
       "WHERE category = 'conversation' ORDER BY created_at DESC")
if limit:
    sql += f" LIMIT {limit}"

def origen(key):
    # whatsapp_+573226531629_<uuid> → (whatsapp, +57322…); user_msg_<uuid> → (cli, —)
    m = re.match(r"^([a-z]+)_(\+\d+)_", key)
    if m:
        return m.group(1), m.group(2)
    if key.startswith("user_msg_"):
        return "cli", ""
    return key.split("_", 1)[0], ""

filas = []
for rid, key, content, fecha in con.execute(sql):
    canal, remitente = origen(key)
    filas.append({"id": rid, "fecha": fecha, "canal": canal,
                  "remitente": remitente, "texto": content})

if fmt == "json":
    print(json.dumps(filas, ensure_ascii=False))
else:
    if not filas:
        print("Sin entradas."); sys.exit(0)
    for f in filas:
        quien = f"{f['canal']}{' ' + f['remitente'] if f['remitente'] else ''}"
        print(f"── {f['fecha']} · {quien}")
        print(f"   {f['texto'][:200]}")
        print()
PY

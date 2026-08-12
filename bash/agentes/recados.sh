#!/usr/bin/env bash
# La cola de recados de Iki: memorias `RECADO:` del agente, con el formato
# canónico (DE/PARA/QUÉ/URGENCIA/CONTEXTO/PROPUESTA) parseado a columnas.
# READ-ONLY sobre la DB de memoria del daemon zeroclaw.
#
# Usage: recados.sh [--para FRAG] [--limit N] [--json]
#   --para FRAG  filtra por destinatario (fragmento, case-insensitive)
#   --limit N    máximo de recados (default 100; 0 = sin tope)
#   --json       [{id,fecha,sesion,de,para,que,urgencia,contexto,propuesta,texto}]
#                — lo que consume la fuente viz `iki_recados` (Mesa de Despacho).
set -euo pipefail

ZC_DIR="${ZEROCLAW_DIR:-$HOME/.zeroclaw}"
DB="$ZC_DIR/data/memory/brain.db"
FORMAT=text; PARA=""; LIMIT=100

while [[ $# -gt 0 ]]; do
  case "$1" in
    --para)  PARA="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --json)  FORMAT=json; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -f "$DB" ]] || { echo "No existe $DB" >&2; exit 1; }
[[ "$LIMIT" =~ ^[0-9]+$ ]] || { echo "--limit debe ser numérico" >&2; exit 2; }

DB="$DB" PARA="$PARA" LIMIT="$LIMIT" FORMAT="$FORMAT" python3 - <<'PY'
import json, os, re, sqlite3, sys

db, para, limit, fmt = os.environ["DB"], os.environ["PARA"], int(os.environ["LIMIT"]), os.environ["FORMAT"]
con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
sql = "SELECT id, content, substr(created_at,1,19), coalesce(session_id,'') FROM memories WHERE content LIKE 'RECADO%' ORDER BY created_at DESC"
if limit:
    sql += f" LIMIT {limit}"

CAMPOS = ["DE", "PARA", "QUÉ", "URGENCIA", "CONTEXTO", "PROPUESTA"]
def parse(texto):
    # Campos del formato canónico; QUE sin tilde se acepta por robustez.
    out = {c: "" for c in CAMPOS}
    actual = None
    for linea in texto.splitlines():
        m = re.match(r"^\s*(DE|PARA|QUÉ|QUE|URGENCIA|CONTEXTO|PROPUESTA)\s*:\s*(.*)$", linea)
        if m:
            actual = "QUÉ" if m.group(1) == "QUE" else m.group(1)
            out[actual] = m.group(2).strip()
        elif actual and linea.strip():
            out[actual] += " " + linea.strip()
    return out

filas = []
for rid, content, fecha, sesion in con.execute(sql):
    c = parse(content)
    if para and para.lower() not in c["PARA"].lower():
        continue
    filas.append({
        "id": rid, "fecha": fecha, "sesion": sesion,
        "de": c["DE"], "para": c["PARA"], "que": c["QUÉ"],
        "urgencia": c["URGENCIA"], "contexto": c["CONTEXTO"],
        "propuesta": c["PROPUESTA"], "texto": content,
    })

if fmt == "json":
    print(json.dumps(filas, ensure_ascii=False))
else:
    if not filas:
        print("Sin recados en la cola."); sys.exit(0)
    for f in filas:
        print(f"■ {f['fecha']}  {f['de']} → {f['para']}  [{f['urgencia']}]")
        print(f"  QUÉ: {f['que']}")
        if f["contexto"]: print(f"  CONTEXTO: {f['contexto']}")
        print(f"  PROPUESTA: {f['propuesta']}")
        print(f"  id: {f['id'][:8]}")
        print()
PY

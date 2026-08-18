#!/usr/bin/env bash
# [WRITE local] Cosecha los recados de Iki (memoria del daemon, read-only)
# hacia la cola de despacho del cerebro (sqlite local `mesa_despacho`).
#
# Reglas (patrón sync_tareas del cruce PM):
#   - Upsert por recado_id: los NUEVOS entran como 'pendiente'.
#   - Filas ya marcadas (estado != 'pendiente') se CONGELAN: documentan una
#     decisión tomada; jamás se reescriben.
#   - Nunca borra; nunca escribe en las DBs de zeroclaw.
#
# Usage: sync_despachos.sh [--dry-run] [--json]
set -euo pipefail
cd "$(dirname "$0")/../.."

DRY=0; FORMAT=text
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

RECADOS_JSON="$(bash/agentes/recados.sh --json --limit 0)"

RECADOS_JSON="$RECADOS_JSON" DRY="$DRY" FORMAT="$FORMAT" python3 - <<'PY'
import json, os, sqlite3, sys
from datetime import datetime

recados = json.loads(os.environ["RECADOS_JSON"])
dry, fmt = os.environ["DRY"] == "1", os.environ["FORMAT"]
db = os.path.join(os.environ.get("LOCALDB_DIR", "data/sqlite"), "mesa_despacho.db")
con = sqlite3.connect(db)

existentes = {r[0] for r in con.execute("SELECT recado_id FROM despachos")}
nuevos, congelados = [], 0
for r in recados:
    if r["id"] in existentes:
        congelados += 1
        continue
    nuevos.append(r)
    if not dry:
        con.execute(
            "INSERT INTO despachos (recado_id, fecha_recado, de, para, que, urgencia, contexto, propuesta, texto) "
            "VALUES (?,?,?,?,?,?,?,?,?)",
            (r["id"], r["fecha"], r["de"], r["para"], r["que"], r["urgencia"],
             r["contexto"], r["propuesta"], r["texto"]))
if not dry:
    con.commit()

res = {"nuevos": len(nuevos), "ya_registrados": congelados,
       "dry_run": dry, "ids_nuevos": [n["id"][:8] for n in nuevos]}
if fmt == "json":
    print(json.dumps(res, ensure_ascii=False))
else:
    accion = "entrarían" if dry else "entraron"
    print(f"{res['nuevos']} recado(s) {accion} a la cola; {congelados} ya registrados (congelados).")
    for n in nuevos:
        print(f"  + {n['id'][:8]}  {n['de']} → {n['para']}: {n['que'][:60]}")
PY

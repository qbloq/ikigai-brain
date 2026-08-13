#!/usr/bin/env bash
# [WRITE local] Refresca el `directorio` de la Mesa de Despacho (sqlite
# mesa_despacho) desde la DB: espejo derivado de users→persons.
#
# Regla de fuentes (decisión 2026-08-12): **users.phone_number manda**;
# team_members.whatsapp es fallback (cubre a quienes users no tiene número).
# Un número de users repetido entre personas DISTINTAS es dato sospechoso y
# cae al fallback (caso real: Daniel Cardona traía el número de Lucho).
# Normalización: solo dígitos (limpia unicode invisible), 10 dígitos que
# empiezan por 3 → +57, siempre E.164. La fila seed 'santiago' (Gaviria,
# Parallelo — no es team member) se preserva. El alias 'santi' se EXCLUYE
# adrede (ambiguo: Santiago Ruiz vs Santiago Gaviria → revisión humana).
#
# Usage: sync_directorio.sh [--dry-run] [--json]
set -euo pipefail
cd "$(dirname "$0")/../.."
source bash/lib/common.sh
source bash/lib/sqlite.sh

DRY=0; FORMAT=text
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

RAW="$(psql_ro -t -A -F'|' -c "
SELECT trim(coalesce(p.name,'')||' '||coalesce(p.lastname,'')),
       coalesce(tm.whatsapp,''), coalesce(u.phone_number,''),
       coalesce(tr.name,''), coalesce(t.name,'')
FROM team_members tm
LEFT JOIN users u ON u.id = tm.user_id
LEFT JOIN persons p ON p.person_id = u.person_id
LEFT JOIN team_roles tr ON tr.id = tm.role_id
LEFT JOIN teams t ON t.id = tm.team_id
WHERE tm.whatsapp IS NOT NULL OR u.phone_number IS NOT NULL")"

DB="$LOCALDB_DIR/mesa_despacho.db"
[[ -f "$DB" ]] || { echo "No existe $DB" >&2; exit 1; }

RAW="$RAW" DB="$DB" DRY="$DRY" FORMAT="$FORMAT" python3 - <<'PY'
import json, os, re, sqlite3
from collections import Counter

raw, db = os.environ["RAW"], os.environ["DB"]
dry, fmt = os.environ["DRY"] == "1", os.environ["FORMAT"]

def digits(s):
    return re.sub(r"\D", "", s)

def e164(d):
    if len(d) == 10 and d.startswith("3"):
        d = "57" + d
    return "+" + d

filas = []
for line in raw.strip().splitlines():
    nombre, tm_w, u_phone, rol, equipo = (line.split("|") + [""] * 5)[:5]
    filas.append((nombre.strip(), digits(tm_w), digits(u_phone), rol.strip(), equipo.strip()))

por_num = {}
for f in filas:
    if f[2]:
        por_num.setdefault(f[2], set()).add(f[0])
dup_users = {n for n, ps in por_num.items() if len(ps) > 1}

rows = {}
for nombre, tm_w, u_phone, rol, equipo in filas:
    if not nombre:
        continue
    if u_phone and u_phone not in dup_users:
        num, fuente = e164(u_phone), "users"
    elif tm_w:
        num, fuente = e164(tm_w), "tm.whatsapp (users vacío o duplicado)"
    else:
        continue
    rows[nombre.lower()] = (num, f"{rol} · {equipo} · fuente: {fuente}")

ALIAS = {
    "bala": "david castaño", "jota": "jhonatan rengifo", "jona": "jhonatan rengifo",
    "sophie": "sofia", "juanca": "juan camilo correa", "mari": "marisol ochoa",
    "pablo": "pablo gaviria", "toño": "tony vidal", "tony": "tony vidal",
    "loro": "lorenzo cadavid", "lorenzo": "lorenzo cadavid",
    "lucho": "luis david flórez", "marisol": "marisol ochoa",
    "andrés": "andrés alzate", "jhonatan": "jhonatan rengifo",
    "ayrton": "ayrton vega", "cristian": "cristian  buelvas",
}
for a, full in ALIAS.items():
    if full in rows:
        num, notas = rows[full]
        rows[a] = (num, f"alias de {full.replace('  ', ' ')} — {notas}")

con = sqlite3.connect(db)
previos = {r[0]: r[1] for r in con.execute("SELECT nombre, numero FROM directorio")}
cambios = [(n, previos.get(n), v[0]) for n, v in sorted(rows.items()) if previos.get(n) != v[0]]

if not dry:
    con.execute("BEGIN")
    con.execute("DELETE FROM directorio WHERE nombre != 'santiago'")
    con.executemany("INSERT OR REPLACE INTO directorio (nombre, numero, notas) VALUES (?,?,?)",
                    [(n, v[0], v[1]) for n, v in rows.items()])
    con.commit()

res = {"filas": len(rows) + 1, "cambios": [{"nombre": n, "antes": a, "ahora": d} for n, a, d in cambios],
       "sospechosos_users": sorted(dup_users), "dry_run": dry}
if fmt == "json":
    print(json.dumps(res, ensure_ascii=False))
else:
    verbo = "cambiarían" if dry else "cambiaron"
    print(f"{res['filas']} filas en directorio; {len(cambios)} {verbo}; números users sospechosos: {res['sospechosos_users'] or '—'}")
    for c in res["cambios"]:
        print(f"  {c['nombre']}: {c['antes'] or '(nuevo)'} → {c['ahora']}")
PY

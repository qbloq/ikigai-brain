#!/usr/bin/env bash
# sync_cerebro.sh — WRITE (local): refresca el lado CEREBRO del cruce desde
# Postgres. Es el espejo exacto de sync_tareas.sh, que hace lo mismo del lado PM.
#
# POR QUÉ EXISTE
# La tabla `cruce` no consulta en vivo: guarda COPIAS de los dos lados puestas
# lado a lado, porque PM vive en sqlite y el cerebro en Postgres y no hay JOIN
# posible entre ambos. A esas copias se les construyó refresco a UNA sola mitad.
# Resultado medido el 2026-08-20: de 205 filas con lado cerebro, 140 mentían
# (94 decían `pending` de tareas ya canceladas) — la UI ofrecía como candidatas
# vivas cosas que llevaban horas cerradas. Este script corre la mitad que falta.
#
# QUÉ ESCRIBE — y qué deliberadamente no
#   · `cerebro_tareas` : upsert por id (prefijo de 8, la forma que usa `cruce`).
#                        NUNCA BORRA. Una tarea que ya no está en Postgres se
#                        REPORTA, no se elimina: hay filas de `cruce` apuntándole.
#   · `cruce`          : las copias ce_titulo/ce_estado/ce_proyecto se refrescan
#                        SOLO en filas sin resolver (`resuelta=0`). Una fila
#                        resuelta documenta una decisión tomada sobre el
#                        contenido que muestra; refrescarla reescribe la historia.
#   · `cerebro_sync`   : una fila por corrida (se crea al primer uso) — el log de
#                        frescura que este lado no tenía.
#   · Postgres         : JAMÁS. Solo lee (psql_ro). Este script no decide nada
#                        sobre tareas: no cierra, no cancela, no crea.
#
# LO QUE NO HACE, Y HAY QUE SABERLO: no recalcula el cruce. Los veredictos, la
# confianza y los pares salieron de una pasada semántica hecha una vez; una tarea
# nacida después del snapshot no gana fila por correr esto — sale listada en
# «sin fila en el cruce» para que alguien la cruce.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/sqlite.sh"

DB=pm_platform

usage() {
  cat <<'EOF'
Uso: sync_cerebro.sh [--dry-run] [--no-cruce] [--json]

  --dry-run   lee y compara, no escribe nada (imprime el plan)
  --no-cruce  refresca `cerebro_tareas` pero no toca las copias ce_* de `cruce`
  --json      plan completo machine-readable

WRITE local: escribe en la sqlite pm_platform (cerebro_tareas, cruce, cerebro_sync).
Nunca borra filas y nunca escribe en Postgres.
EOF
}

DRY=0; DO_CRUCE=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)  DRY=1; shift ;;
    --no-cruce) DO_CRUCE=0; shift ;;
    --json)     FORMAT=json; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          echo "Argumento desconocido: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null || { echo "Falta python3" >&2; exit 3; }
p="$(require_db "$DB")"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# --- Fetch: el cerebro, en la forma que el cruce entiende ---------------------
# El id es el PREFIJO de 8 porque así lo guardan `cruce.ce_id` y `cerebro_tareas`.
# Un prefijo ambiguo (dos tareas, mismo prefijo) se excluye y se reporta: elegir
# una al azar metería el estado de otra tarea en la fila del cruce.
psql_ro -At -c "
WITH base AS (
  SELECT left(t.id::text,8) AS id, t.title AS titulo, t.status::text AS estado,
         t.priority::text AS prioridad,
         coalesce(to_char(t.due_date,'YYYY-MM-DD'),'') AS vence,
         coalesce($ASSIGNEES_SQL,'') AS asignados,
         coalesce(t.source_type::text,'') AS source_type,
         coalesce(pr.name,'') AS proyecto
  FROM tasks t LEFT JOIN projects pr ON pr.id = t.project_id
), dup AS (SELECT id FROM base GROUP BY id HAVING count(*) > 1)
SELECT coalesce(json_agg(row_to_json(b)),'[]')::text
FROM base b WHERE b.id NOT IN (SELECT id FROM dup)" > "$WORK/pg.json"

psql_ro -At -c "
SELECT coalesce(json_agg(x),'[]')::text FROM (
  SELECT left(t.id::text,8) AS id FROM tasks t
  GROUP BY 1 HAVING count(*) > 1) x" > "$WORK/dup.json"

PG_N="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$WORK/pg.json")"
# Cero tareas es Postgres caído o un search_path roto, no un cerebro vacío.
# Nunca dejar que eso maneje una escritura.
(( PG_N == 0 )) && { echo "postgres devolvió 0 tareas — no escribo nada (¿conexión o esquema?)" >&2; exit 1; }

# --- Estado local -------------------------------------------------------------
json_or_empty "$(sqlite_ro "$p" -json "SELECT * FROM cerebro_tareas")" >"$WORK/local.json"
json_or_empty "$(sqlite_ro "$p" -json \
  "SELECT n, ce_id, ce_titulo, ce_estado, ce_proyecto, resuelta, veredicto, accion FROM cruce")" >"$WORK/cruce.json"

# --- Diff → plan.json + sync.sql ---------------------------------------------
python3 - "$WORK/pg.json" "$WORK/local.json" "$WORK/cruce.json" "$WORK/dup.json" \
         "$WORK/plan.json" "$WORK/sync.sql" "$DO_CRUCE" <<'PY'
import json, sys, datetime

pg_f, local_f, cruce_f, dup_f, plan_f, sql_f, do_cruce = sys.argv[1:8]
do_cruce = do_cruce == "1"

COLS = ["id","titulo","estado","prioridad","vence","asignados","source_type","proyecto"]

pg    = json.load(open(pg_f))
local = {r["id"]: r for r in json.load(open(local_f))}
cruce = json.load(open(cruce_f))
dups  = [d["id"] if isinstance(d, dict) else d for d in json.load(open(dup_f))]

def norm(v):
    if v is None: return ""
    return str(v)

def lit(v):
    if v is None: return "NULL"
    if isinstance(v, (int, float)) and not isinstance(v, bool): return repr(v)
    return "'" + str(v).replace("'", "''") + "'"

nuevas, cambiadas, iguales = [], [], 0
for t in pg:
    old = local.get(t["id"])
    if old is None:
        nuevas.append({k: t.get(k) for k in ("id","titulo","estado","proyecto")})
        continue
    diff = {c: {"antes": norm(old.get(c)), "ahora": norm(t.get(c))}
            for c in COLS if norm(old.get(c)) != norm(t.get(c))}
    if diff: cambiadas.append({"id": t["id"], "titulo": t.get("titulo"), "campos": diff})
    else:    iguales += 1

pg_ids = {t["id"] for t in pg}
# No borrar: una fila del cruce puede estar apuntándole.
desaparecidas = [{"id": i, "titulo": r.get("titulo"), "estado": r.get("estado")}
                 for i, r in local.items() if i not in pg_ids]

# --- cruce: refrescar las copias ce_* de las filas SIN RESOLVER ---------------
pg_by_id = {t["id"]: t for t in pg}
cruce_upd, cruce_alertas, cruce_huerfanas = [], [], []
cruce_ce_ids = {c.get("ce_id") for c in cruce if c.get("ce_id")}
if do_cruce:
    for c in cruce:
        if str(c.get("resuelta") or 0) != "0": continue
        ce = c.get("ce_id")
        if not ce: continue
        t = pg_by_id.get(ce)
        if not t:
            cruce_huerfanas.append({"n": c["n"], "ce_id": ce, "titulo": c.get("ce_titulo"),
                                    "ambiguo": ce in dups})
            continue
        pares = [("ce_titulo","titulo"), ("ce_estado","estado"), ("ce_proyecto","proyecto")]
        diff = {cc: {"antes": norm(c.get(cc)), "ahora": norm(t.get(k))}
                for cc, k in pares if norm(c.get(cc)) != norm(t.get(k))}
        if not diff: continue
        cruce_upd.append({"n": c["n"], "campos": diff, "titulo": t.get("titulo")})
        # Un lado cerebro que se cerró invalida la acción propuesta: la fila ya
        # no pide importar ni completar nada.
        if "ce_estado" in diff and diff["ce_estado"]["ahora"] in ("completed","cancelled"):
            cruce_alertas.append({"n": c["n"], "titulo": t.get("titulo"),
                                  "antes": diff["ce_estado"]["antes"],
                                  "ahora": diff["ce_estado"]["ahora"],
                                  "accion": c.get("accion"), "veredicto": c.get("veredicto")})

# Tareas del cerebro que nacieron después de la pasada semántica: nadie las cruzó.
sin_par = [x for x in nuevas if x["id"] not in cruce_ce_ids]

ahora = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
plan = {"corrida_en": ahora, "pg_total": len(pg), "local_antes": len(local),
        "prefijos_ambiguos": dups,
        "nuevas": nuevas, "cambiadas": cambiadas, "iguales": iguales,
        "desaparecidas": desaparecidas, "cruce_actualizadas": cruce_upd,
        "cruce_alertas": cruce_alertas, "cruce_huerfanas": cruce_huerfanas,
        "nuevas_sin_par": sin_par}
json.dump(plan, open(plan_f, "w"), ensure_ascii=False, indent=2)

# --- SQL ----------------------------------------------------------------------
sql = ["CREATE TABLE IF NOT EXISTS cerebro_sync ("
       "id INTEGER PRIMARY KEY AUTOINCREMENT, corrida_en TEXT NOT NULL, pg_total INTEGER,"
       " nuevas INTEGER, cambiadas INTEGER, sin_cambio INTEGER, desaparecidas INTEGER,"
       " cruce_actualizadas INTEGER, detalle TEXT);"]
setcols = ", ".join("%s=excluded.%s" % (c, c) for c in COLS if c != "id")
tocadas = {x["id"] for x in nuevas} | {x["id"] for x in cambiadas}
for t in pg:
    if t["id"] not in tocadas: continue      # lo que no cambió no se reescribe
    vals = ", ".join(lit(t.get(c)) for c in COLS)
    sql.append("INSERT INTO cerebro_tareas (%s) VALUES (%s) ON CONFLICT(id) DO UPDATE SET %s;"
               % (", ".join(COLS), vals, setcols))
for u in cruce_upd:
    sets = ", ".join("%s=%s" % (c, lit(v["ahora"])) for c, v in u["campos"].items())
    sql.append("UPDATE cruce SET %s WHERE n=%d AND resuelta=0;" % (sets, int(u["n"])))
detalle = json.dumps({k: plan[k] for k in ("nuevas","cambiadas","desaparecidas",
                                           "cruce_actualizadas","cruce_alertas",
                                           "cruce_huerfanas")}, ensure_ascii=False)
sql.append("INSERT INTO cerebro_sync (corrida_en, pg_total, nuevas, cambiadas, sin_cambio,"
           " desaparecidas, cruce_actualizadas, detalle) VALUES (%s, %d, %d, %d, %d, %d, %d, %s);"
           % (lit(ahora), len(pg), len(nuevas), len(cambiadas), iguales,
              len(desaparecidas), len(cruce_upd), lit(detalle)))
open(sql_f, "w").write("\n".join(sql) + "\n")
PY

# --- Aplicar ------------------------------------------------------------------
APPLIED=0
if (( DRY == 0 )); then
  { echo "BEGIN;"; cat "$WORK/sync.sql"; echo "COMMIT;"; } | sqlite_rw "$p"
  APPLIED=1
fi

# --- Render -------------------------------------------------------------------
DESPUES="$(sqlite_ro "$p" "SELECT count(*) FROM cerebro_tareas")"
if [[ "$FORMAT" == "json" ]]; then
  python3 -c '
import json, sys
plan = json.load(open(sys.argv[1]))
plan["aplicado"] = sys.argv[2] == "1"
plan["despues"] = int(sys.argv[3])
json.dump(plan, sys.stdout, ensure_ascii=False, indent=2); print()
' "$WORK/plan.json" "$APPLIED" "$DESPUES"
  exit 0
fi

python3 -c '
import json, sys
plan = json.load(open(sys.argv[1]))
aplicado, despues = sys.argv[2] == "1", sys.argv[3]

def corto(s, n=58):
    s = (s or "").replace("\n", " ")
    return s if len(s) <= n else s[:n-1] + "…"

print("Sync Cerebro (Postgres) → sqlite pm_platform   (%s)" % plan["corrida_en"])
print("  Postgres: %d tareas   ·   espejo: %s antes → %s ahora"
      % (plan["pg_total"], plan["local_antes"], despues))
print("  nuevas %d · cambiadas %d · sin cambio %d · ya no en Postgres %d · cruce refrescado %d"
      % (len(plan["nuevas"]), len(plan["cambiadas"]), plan["iguales"],
         len(plan["desaparecidas"]), len(plan["cruce_actualizadas"])))
print("  %s" % ("APLICADO" if aplicado else "DRY-RUN — nada escrito"))

if plan["prefijos_ambiguos"]:
    print("\n⚠ Prefijos de 8 compartidos por más de una tarea (excluidos, NO se adivina):")
    for d in plan["prefijos_ambiguos"]: print("  %s" % d)
if plan["cruce_alertas"]:
    print("\n⚠ Filas sin resolver cuyo lado cerebro YA se cerró (su acción propuesta caducó):")
    for a in plan["cruce_alertas"]:
        print("  n=%-4s %-20s %s → %s   %s"
              % (a["n"], (a["accion"] or "—")[:20], a["antes"], a["ahora"], corto(a["titulo"], 40)))
if plan["cruce_huerfanas"]:
    print("\n⚠ Filas sin resolver cuyo ce_id ya no existe en Postgres:")
    for h in plan["cruce_huerfanas"]:
        print("  n=%-4s %s%s %s" % (h["n"], h["ce_id"],
              " (prefijo ambiguo)" if h["ambiguo"] else "", corto(h["titulo"], 40)))
if plan["desaparecidas"]:
    print("\nYa no están en Postgres (NO se borraron del espejo): %d" % len(plan["desaparecidas"]))
if plan["nuevas_sin_par"]:
    print("\nTareas del cerebro sin fila en el cruce (nadie las cruzó todavía): %d"
          % len(plan["nuevas_sin_par"]))
' "$WORK/plan.json" "$APPLIED" "$DESPUES"

exit 0

#!/usr/bin/env bash
# sync_tareas.sh — WRITE (local): refresh the `pm_platform` SQLite mirror from
# the PM platform's API (project360, Mari's).
#
# WHY THIS EXISTS
# The `cruce` UI reads two frozen snapshots, not live data: `tareas` (Mari's
# platform, pulled by hand on 2026-08-06) and `cerebro_tareas` (ours). A cross
# whose PM side is weeks old proposes actions on states that already changed —
# it says "completar en el cerebro" for something Mari reopened, or misses the
# task she closed yesterday. This script re-pulls the PM side.
#
# WHAT IT WRITES — and what it deliberately does not
#   · `tareas`  : upsert by id. NOTHING IS EVER DELETED. A task that vanished
#                 upstream is reported, not removed: `cruce` rows point at it,
#                 and the line here is "cruzar y ajustar, no borrar".
#   · `cruce`   : the pm_titulo/pm_estado/pm_asignado copies are re-synced ONLY
#                 for unresolved rows (`resuelta=0`). A resolved row records a
#                 decision taken over the content it shows — refreshing it would
#                 rewrite history.
#   · `pm_sync` : one row per run (created on first use) — the freshness log the
#                 mirror had no way to answer before.
#   · Postgres  : never. This layer only touches the local SQLite db; promoting
#                 anything to the brain is bash/tasks/merge_from_cruce.sh's job.
#
# CREDENTIALS: PM360_BASE + PM360_TOKEN from .env, handed to curl over stdin
# (--config -) so the token never reaches argv. Every API call is a GET.
set -euo pipefail
source "$(dirname "$0")/../lib/sqlite.sh"

DB=pm_platform
SNAP_DIR="$REPO_ROOT/data/pm-platform"

usage() {
  cat <<'EOF'
Uso: sync_tareas.sh [--dry-run] [--limit N] [--no-cruce] [--no-snapshot] [--json]

  --dry-run      trae y compara, no escribe nada (imprime el plan)
  --limit N      tope de tareas a traer (0 = todas, default)
  --no-cruce     no refresca las copias pm_* de la tabla `cruce`
  --no-snapshot  no guarda el JSON crudo en data/pm-platform/
  --json         plan completo machine-readable

WRITE local: escribe en la sqlite pm_platform (tareas, cruce, pm_sync).
Nunca borra filas y nunca toca Postgres.
EOF
}

DRY=0; LIMIT=0; DO_CRUCE=1; DO_SNAP=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)     DRY=1; shift ;;
    --limit)       LIMIT="${2:?}"; shift 2 ;;
    --no-cruce)    DO_CRUCE=0; shift ;;
    --no-snapshot) DO_SNAP=0; shift ;;
    --json)        FORMAT=json; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             echo "Argumento desconocido: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$LIMIT" =~ ^[0-9]+$ ]] || { echo "--limit debe ser un entero" >&2; exit 2; }

# --- Credentials -------------------------------------------------------------
# Independent of bash/lib/common.sh on purpose (same reason as sqlite.sh): the
# local layer must work with no Postgres client installed.
if [[ -z "${PM360_TOKEN:-}" && -f "$REPO_ROOT/.env" ]]; then
  set -a; source "$REPO_ROOT/.env"; set +a
fi
: "${PM360_BASE:?PM360_BASE no está en .env — es el API de la plataforma de Mari}"
: "${PM360_TOKEN:?PM360_TOKEN no está en .env}"
command -v curl >/dev/null || { echo "Falta curl" >&2; exit 3; }
command -v python3 >/dev/null || { echo "Falta python3" >&2; exit 3; }

p="$(require_db "$DB")"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# --- Fetch -------------------------------------------------------------------
# pm_api <path> : authenticated GET. Token via stdin, out of `ps`.
pm_api() {
  local path="$1" tmp code
  tmp="$WORK/resp.json"
  code="$(printf 'url = "%s"\nheader = "Authorization: Bearer %s"\nheader = "Accept: application/json"\n' \
        "$PM360_BASE$path" "$PM360_TOKEN" \
      | curl -sS -m 60 --config - -o "$tmp" -w '%{http_code}')" || return 1
  if [[ "$code" != 2* ]]; then
    echo "pm api HTTP $code — ${path%%\?*}" >&2
    head -c 300 "$tmp" >&2; echo >&2
    return 1
  fi
  cat "$tmp"
}

page=0; got=0; step=100
: >"$WORK/pages.jsonl"
while :; do
  (( LIMIT > 0 && LIMIT - got < step )) && step=$(( LIMIT - got ))
  out="$(pm_api "/tasks?limite=$step&offset=$got")" || exit 1
  read -r n more < <(printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if not d.get("success"): sys.exit("pm api: respuesta sin success=true")
data = d.get("data") or {}
print(len(data.get("tareas") or []), 1 if (data.get("paginacion") or {}).get("hay_mas") else 0)')
  printf '%s\n' "$out" >>"$WORK/pages.jsonl"
  got=$(( got + n )); page=$(( page + 1 ))
  (( n == 0 || more == 0 )) && break
  (( LIMIT > 0 && got >= LIMIT )) && break
  (( page > 200 )) && { echo "pm api: demasiadas páginas, corto por seguridad" >&2; break; }
done

python3 -c '
import json, sys
items, seen = [], set()
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    for t in (json.loads(line).get("data") or {}).get("tareas") or []:
        if t.get("id") in seen: continue
        seen.add(t["id"]); items.append(t)
json.dump(items, open(sys.argv[2], "w"), ensure_ascii=False)
' "$WORK/pages.jsonl" "$WORK/api.json"

API_N="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$WORK/api.json")"
# A zero fetch is an API problem, not an empty platform — never let it drive a write.
(( API_N == 0 )) && { echo "pm api: devolvió 0 tareas — no escribo nada (¿token o API caídos?)" >&2; exit 1; }

if (( DO_SNAP )) && (( DRY == 0 )); then
  mkdir -p "$SNAP_DIR"
  cp "$WORK/api.json" "$SNAP_DIR/tareas-$(date +%F).json"
fi

# --- Local state -------------------------------------------------------------
json_or_empty "$(sqlite_ro "$p" -json "SELECT * FROM tareas")" >"$WORK/local.json"
json_or_empty "$(sqlite_ro "$p" -json \
  "SELECT n, pm_id, pm_titulo, pm_estado, pm_asignado, resuelta, veredicto, accion FROM cruce")" >"$WORK/cruce.json"

# --- Diff → plan.json + sync.sql ---------------------------------------------
python3 - "$WORK/api.json" "$WORK/local.json" "$WORK/cruce.json" "$WORK/plan.json" "$WORK/sync.sql" "$DO_CRUCE" <<'PY'
import json, sys, datetime

api_f, local_f, cruce_f, plan_f, sql_f, do_cruce = sys.argv[1:7]
do_cruce = do_cruce == "1"

COLS = ["id","client_id","cliente","titulo","descripcion","estado","prioridad",
        "asignado_a","fecha_limite","completada_en","etiqueta","external_id",
        "origen","meeting_id","creada_en"]

api   = json.load(open(api_f))
local = {r["id"]: r for r in json.load(open(local_f))}
cruce = json.load(open(cruce_f))

extra = sorted({k for t in api for k in t} - set(COLS))
if extra:
    print("aviso: el API trae campos que el espejo no guarda: %s" % ", ".join(extra), file=sys.stderr)

def norm(v):
    if v is None: return None
    if isinstance(v, (dict, list)): return json.dumps(v, ensure_ascii=False)
    return str(v)

def lit(v):
    if v is None: return "NULL"
    if isinstance(v, bool): return "1" if v else "0"
    if isinstance(v, (int, float)): return repr(v)
    if isinstance(v, (dict, list)): v = json.dumps(v, ensure_ascii=False)
    return "'" + str(v).replace("'", "''") + "'"

nuevas, cambiadas, iguales = [], [], 0
for t in api:
    tid = t.get("id")
    if not tid: continue
    old = local.get(tid)
    if old is None:
        nuevas.append({"id": tid, "titulo": t.get("titulo"), "estado": t.get("estado"),
                       "asignado_a": t.get("asignado_a"), "creada_en": t.get("creada_en")})
        continue
    diff = {c: {"antes": norm(old.get(c)), "ahora": norm(t.get(c))}
            for c in COLS if norm(old.get(c)) != norm(t.get(c))}
    if diff:
        cambiadas.append({"id": tid, "titulo": t.get("titulo"), "campos": diff})
    else:
        iguales += 1

api_ids = {t["id"] for t in api if t.get("id")}
desaparecidas = [{"id": i, "titulo": r.get("titulo"), "estado": r.get("estado")}
                 for i, r in local.items() if i not in api_ids]

# --- cruce: refresh the denormalized PM copies of UNRESOLVED rows only --------
api_by_id = {t["id"]: t for t in api if t.get("id")}
cruce_upd, cruce_alertas = [], []
cruce_pm_ids = {c.get("pm_id") for c in cruce if c.get("pm_id")}
if do_cruce:
    for c in cruce:
        if str(c.get("resuelta") or 0) != "0": continue
        t = api_by_id.get(c.get("pm_id"))
        if not t: continue
        pares = [("pm_titulo", "titulo"), ("pm_estado", "estado"), ("pm_asignado", "asignado_a")]
        diff = {cc: {"antes": norm(c.get(cc)), "ahora": norm(t.get(cc_api))}
                for cc, cc_api in pares if norm(c.get(cc)) != norm(t.get(cc_api))}
        if not diff: continue
        cruce_upd.append({"n": c["n"], "campos": diff, "titulo": t.get("titulo")})
        if "pm_estado" in diff and diff["pm_estado"]["ahora"] == "completed":
            cruce_alertas.append({"n": c["n"], "titulo": t.get("titulo"),
                                  "antes": diff["pm_estado"]["antes"],
                                  "accion": c.get("accion"), "veredicto": c.get("veredicto")})

sin_par = [x for x in nuevas if x["id"] not in cruce_pm_ids]

ahora = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
plan = {"corrida_en": ahora, "api_total": len(api), "local_antes": len(local),
        "nuevas": nuevas, "cambiadas": cambiadas, "iguales": iguales,
        "desaparecidas": desaparecidas, "cruce_actualizadas": cruce_upd,
        "cruce_alertas": cruce_alertas, "nuevas_sin_par": sin_par}
json.dump(plan, open(plan_f, "w"), ensure_ascii=False, indent=2)

# --- SQL ---------------------------------------------------------------------
sql = ["CREATE TABLE IF NOT EXISTS pm_sync ("
       "id INTEGER PRIMARY KEY AUTOINCREMENT, corrida_en TEXT NOT NULL, api_total INTEGER,"
       " nuevas INTEGER, cambiadas INTEGER, sin_cambio INTEGER, desaparecidas INTEGER,"
       " cruce_actualizadas INTEGER, detalle TEXT);"]
setcols = ", ".join("%s=excluded.%s" % (c, c) for c in COLS if c != "id")
for t in api:
    if not t.get("id"): continue
    if not any(x["id"] == t["id"] for x in nuevas) and not any(x["id"] == t["id"] for x in cambiadas):
        continue                      # untouched rows are not rewritten
    vals = ", ".join(lit(t.get(c)) for c in COLS)
    sql.append("INSERT INTO tareas (%s) VALUES (%s) ON CONFLICT(id) DO UPDATE SET %s;"
               % (", ".join(COLS), vals, setcols))
for u in cruce_upd:
    sets = ", ".join("%s=%s" % (c, lit(v["ahora"])) for c, v in u["campos"].items())
    sql.append("UPDATE cruce SET %s WHERE n=%d AND resuelta=0;" % (sets, int(u["n"])))
detalle = json.dumps({k: plan[k] for k in ("nuevas", "cambiadas", "desaparecidas",
                                           "cruce_actualizadas", "cruce_alertas")},
                     ensure_ascii=False)
sql.append("INSERT INTO pm_sync (corrida_en, api_total, nuevas, cambiadas, sin_cambio,"
           " desaparecidas, cruce_actualizadas, detalle) VALUES (%s, %d, %d, %d, %d, %d, %d, %s);"
           % (lit(ahora), len(api), len(nuevas), len(cambiadas), iguales,
              len(desaparecidas), len(cruce_upd), lit(detalle)))
open(sql_f, "w").write("\n".join(sql) + "\n")
PY

# --- Apply -------------------------------------------------------------------
APPLIED=0
if (( DRY == 0 )); then
  { echo "BEGIN;"; cat "$WORK/sync.sql"; echo "COMMIT;"; } | sqlite_rw "$p"
  APPLIED=1
fi

# --- Render ------------------------------------------------------------------
if [[ "$FORMAT" == "json" ]]; then
  python3 -c '
import json, sys
plan = json.load(open(sys.argv[1]))
plan["aplicado"] = sys.argv[2] == "1"
plan["despues"] = int(sys.argv[3])
json.dump(plan, sys.stdout, ensure_ascii=False, indent=2); print()
' "$WORK/plan.json" "$APPLIED" "$(sqlite_ro "$p" "SELECT count(*) FROM tareas")"
  exit 0
fi

python3 -c '
import json, sys
plan = json.load(open(sys.argv[1]))
aplicado, despues = sys.argv[2] == "1", sys.argv[3]

def corto(s, n=58):
    s = (s or "").replace("\n", " ")
    return s if len(s) <= n else s[:n-1] + "…"

print("Sync PM → sqlite pm_platform   (%s)" % plan["corrida_en"])
print("  API: %d tareas   ·   espejo: %s antes → %s ahora"
      % (plan["api_total"], plan["local_antes"], despues))
print("  nuevas %d · cambiadas %d · sin cambio %d · desaparecidas del API %d · cruce refrescado %d"
      % (len(plan["nuevas"]), len(plan["cambiadas"]), plan["iguales"],
         len(plan["desaparecidas"]), len(plan["cruce_actualizadas"])))
print("  %s" % ("APLICADO" if aplicado else "DRY-RUN — nada escrito"))

if plan["nuevas"]:
    print("\nNuevas en la plataforma de Mari:")
    for t in plan["nuevas"]:
        print("  + [%-11s] %-10s %s" % (t["estado"], (t["asignado_a"] or "—")[:10], corto(t["titulo"])))
if plan["cambiadas"]:
    print("\nCambios en tareas que ya teníamos:")
    for t in plan["cambiadas"]:
        print("  ~ %s" % corto(t["titulo"]))
        for c, d in t["campos"].items():
            print("      %-14s %s\n      %-14s → %s" % (c, corto(d["antes"], 60), "", corto(d["ahora"], 60)))
if plan["desaparecidas"]:
    print("\nYa no vienen del API (NO se borraron del espejo):")
    for t in plan["desaparecidas"]:
        print("  ? [%-11s] %s" % (t["estado"], corto(t["titulo"])))
if plan["cruce_alertas"]:
    print("\n⚠ Filas del cruce sin resolver que Mari pasó a completed:")
    for a in plan["cruce_alertas"]:
        print("  n=%-4s %-12s %s" % (a["n"], a["accion"] or "—", corto(a["titulo"], 48)))
if plan["nuevas_sin_par"]:
    print("\nNuevas sin fila en el cruce (candidatas a cruzar): %d" % len(plan["nuevas_sin_par"]))
' "$WORK/plan.json" "$APPLIED" "$(sqlite_ro "$p" "SELECT count(*) FROM tareas")"

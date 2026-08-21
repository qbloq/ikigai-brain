#!/usr/bin/env bash
# cobertura.sh — READ-ONLY: el chequeo de cobertura PM↔cerebro, en un solo lugar.
#
# POR QUÉ EXISTE
# Este invariante se midió MAL tres veces el 2026-08-20, siempre por el mismo
# motivo: hay DOS vías de enlace entre una tarea de PM y una del cerebro
#   · por identidad : tasks.source_external_id = tareas.id
#   · por el cruce  : cruce.ce_id (prefijo de 8) ↔ cruce.pm_id
# y una consulta que solo mira una de las dos inventa huecos que no existen.
# Mientras el chequeo se rearmaba a mano cada vez, «estamos cuadrados» era una
# afirmación frágil. Aquí está escrito una vez, con las dos vías adentro.
#
# QUÉ REPORTA
#   [A] tareas ABIERTAS en PM sin ninguna tarea viva en el cerebro, clasificadas:
#         · hueco        — de verdad no está: hay que crearla
#         · decidida     — su fila del cruce ya está resuelta y dice qué se hizo
#                          (típicamente: duplicado del lado PM, subsumido a
#                          propósito). No es un hueco, es un enlace en prosa.
#         · muchos-a-uno — la tarea del cerebro que la cubre YA tiene otro
#                          source_external_id. Una columna no es una lista; esto
#                          no se arregla vinculando, pide tabla de enlaces.
#   [B] tareas ABIERTAS en el cerebro cuya gemela en PM está cerrada — por las
#       dos vías. Éstas sí son siempre acción: cerrarlas (complete_task.sh).
#   Frescura de los dos espejos, porque un invariante medido sobre un espejo
#   viejo es una opinión sobre el pasado.
#
# NO ESCRIBE NADA. psql_ro + sqlite_ro. Correr después de sync_tareas.sh y
# sync_cerebro.sh — LOS DOS: refrescar una sola mitad deja la comparación coja.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/sqlite.sh"

DB=pm_platform
MAX_HORAS="${MAX_HORAS:-24}"

usage() {
  cat <<'EOF'
Uso: cobertura.sh [--json] [--estricto] [--horas N]

  --json      un objeto machine-readable con las listas completas
  --estricto  sale 1 si hay HUECOS reales (para cron/routine). Los casos
              «decidida» y «muchos-a-uno» no cuentan como huecos.
  --horas N   umbral de frescura de los espejos en horas (default 24)

Read-only. Correr después de sync_tareas.sh Y sync_cerebro.sh.
EOF
}

ESTRICTO=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)     FORMAT=json; shift ;;
    --estricto) ESTRICTO=1; shift ;;
    --horas)    MAX_HORAS="${2:?}"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "Argumento desconocido: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null || { echo "Falta python3" >&2; exit 3; }
p="$(require_db "$DB")"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

psql_ro -At -c "
SELECT coalesce(json_agg(row_to_json(x)),'[]')::text FROM (
  SELECT left(t.id::text,8) AS id, t.status::text AS estado,
         coalesce(t.source_external_id,'') AS ext,
         coalesce(pr.name,'') AS proyecto, t.title AS titulo
  FROM tasks t LEFT JOIN projects pr ON pr.id = t.project_id) x" > "$WORK/ce.json"

json_or_empty "$(sqlite_ro "$p" -json "SELECT id, estado, titulo, coalesce(cliente,'') cliente FROM tareas")" >"$WORK/pm.json"
json_or_empty "$(sqlite_ro "$p" -json \
  "SELECT n, coalesce(pm_id,'') pm_id, coalesce(ce_id,'') ce_id, resuelta,
          coalesce(resolucion,'') resolucion, coalesce(accion,'') accion FROM cruce")" >"$WORK/cruce.json"
json_or_empty "$(sqlite_ro "$p" -json \
  "SELECT (SELECT max(corrida_en) FROM pm_sync) pm, (SELECT max(corrida_en) FROM cerebro_sync) cerebro")" >"$WORK/fresh.json"

python3 - "$WORK/ce.json" "$WORK/pm.json" "$WORK/cruce.json" "$WORK/fresh.json" \
         "$MAX_HORAS" "$FORMAT" "$ESTRICTO" <<'PY'
import json, sys, datetime

ce_f, pm_f, cruce_f, fresh_f, max_horas, fmt, estricto = sys.argv[1:8]
max_horas = float(max_horas); estricto = estricto == "1"

ce    = json.load(open(ce_f))
pm    = json.load(open(pm_f))
cruce = json.load(open(cruce_f))
fresh = (json.load(open(fresh_f)) or [{}])[0]

VIVO   = ("pending", "in_progress")
CERRADO= ("completed",)

# --- índices: las DOS vías de enlace ------------------------------------------
por_id  = {t["id"]: t for t in ce}                       # prefijo de 8 del cerebro
por_ext = {}                                             # id externo → tarea del cerebro
for t in ce:
    if t["ext"]: por_ext.setdefault(t["ext"][:8], []).append(t)
cruce_por_pm = {}
for c in cruce:
    if c["pm_id"]: cruce_por_pm.setdefault(c["pm_id"][:8], []).append(c)
cruce_por_ce = {}
for c in cruce:
    if c["ce_id"]: cruce_por_ce.setdefault(c["ce_id"][:8], []).append(c)
pm_por_id = {t["id"][:8]: t for t in pm}

def cubierta(pm8):
    """Devuelve (tarea_del_cerebro, via) si algo VIVO cubre esta tarea de PM."""
    for t in por_ext.get(pm8, []):
        if t["estado"] in VIVO: return t, "identidad"
    for c in cruce_por_pm.get(pm8, []):
        t = por_id.get(c["ce_id"][:8]) if c["ce_id"] else None
        if t and t["estado"] in VIVO: return t, "cruce"
    return None, None

# --- [A] PM abierta sin nada vivo acá -----------------------------------------
huecos, decididas, muchos = [], [], []
for t in pm:
    if t["estado"] not in VIVO: continue
    pm8 = t["id"][:8]
    cub, _ = cubierta(pm8)
    if cub: continue
    filas = cruce_por_pm.get(pm8, [])
    fila_res = next((c for c in filas if str(c["resuelta"]) == "1"), None)
    item = {"pm_id": pm8, "titulo": t["titulo"], "cliente": t["cliente"],
            "estado": t["estado"]}
    if fila_res:
        item["n"] = fila_res["n"]; item["resolucion"] = fila_res["resolucion"]
        decididas.append(item); continue
    # ¿la tarea del cerebro que la cubriría ya tiene OTRA identidad externa?
    destino = None
    for c in filas:
        cand = por_id.get(c["ce_id"][:8]) if c["ce_id"] else None
        if cand and cand["estado"] in VIVO and cand["ext"] and cand["ext"][:8] != pm8:
            destino = cand; break
    if destino:
        item["cerebro"] = destino["id"]; item["ocupada_por"] = destino["ext"][:8]
        muchos.append(item)
    else:
        huecos.append(item)

# --- [B] cerebro abierta con gemela PM cerrada --------------------------------
cerrar = []
for t in ce:
    if t["estado"] not in VIVO: continue
    gemelas = []
    if t["ext"]:
        g = pm_por_id.get(t["ext"][:8])
        if g: gemelas.append((g, "identidad"))
    for c in cruce_por_ce.get(t["id"], []):
        g = pm_por_id.get(c["pm_id"][:8]) if c["pm_id"] else None
        if g: gemelas.append((g, "cruce"))
    if not gemelas: continue
    # Si CUALQUIER gemela sigue abierta, la tarea debe seguir abierta.
    if any(g["estado"] in VIVO for g, _ in gemelas): continue
    if all(g["estado"] in CERRADO for g, _ in gemelas):
        g, via = gemelas[0]
        cerrar.append({"cerebro": t["id"], "pm_id": g["id"][:8], "via": via,
                       "titulo": t["titulo"], "proyecto": t["proyecto"]})

# --- frescura -----------------------------------------------------------------
def edad(ts):
    if not ts: return None
    try:
        d = datetime.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    except ValueError:
        return None
    return round((datetime.datetime.now(datetime.timezone.utc) - d).total_seconds() / 3600, 1)

fr = {"pm": {"corrida": fresh.get("pm"), "horas": edad(fresh.get("pm"))},
      "cerebro": {"corrida": fresh.get("cerebro"), "horas": edad(fresh.get("cerebro"))}}
avisos = [k for k, v in fr.items()
          if v["horas"] is None or v["horas"] > max_horas]

pm_abiertas = sum(1 for t in pm if t["estado"] in VIVO)
ce_abiertas = sum(1 for t in ce if t["estado"] in VIVO)

out = {"pm_abiertas": pm_abiertas, "cerebro_abiertas": ce_abiertas,
       "frescura": fr, "espejos_viejos": avisos,
       "huecos": huecos, "decididas": decididas, "muchos_a_uno": muchos,
       "cerrar_en_cerebro": cerrar}

if fmt == "json":
    json.dump(out, sys.stdout, ensure_ascii=False, indent=2); print()
else:
    def corto(s, n=52):
        s = (s or "").replace("\n", " ")
        return s if len(s) <= n else s[:n-1] + "…"
    print("Cobertura PM ↔ cerebro")
    for k in ("pm", "cerebro"):
        h = fr[k]["horas"]
        marca = "  ⚠ VIEJO" if (h is None or h > max_horas) else ""
        print("  espejo %-8s %s (%s h)%s" % (k, fr[k]["corrida"] or "nunca",
                                             "?" if h is None else h, marca))
    if avisos:
        print("  ⚠ corré sync_tareas.sh y sync_cerebro.sh — LOS DOS — antes de creerle a esto")
    print("  abiertas: PM %d · cerebro %d" % (pm_abiertas, ce_abiertas))

    print("\n[A] abiertas en PM sin nada vivo en el cerebro")
    print("  huecos reales        : %d" % len(huecos))
    for x in huecos:
        print("      %s [%s] %s" % (x["pm_id"], x["cliente"][:14], corto(x["titulo"])))
    print("  ya decididas         : %d   (enlace en prosa, no es hueco)" % len(decididas))
    for x in decididas:
        print("      %s n=%-4s %s" % (x["pm_id"], x["n"], corto(x["resolucion"], 46)))
    print("  muchos-a-uno         : %d   (pide tabla de enlaces, no vincular)" % len(muchos))
    for x in muchos:
        print("      %s → %s (ocupada por %s) %s"
              % (x["pm_id"], x["cerebro"], x["ocupada_por"], corto(x["titulo"], 30)))

    print("\n[B] abiertas en el cerebro con su gemela PM cerrada: %d" % len(cerrar))
    for x in cerrar:
        print("      %s ← %s [%s] %s" % (x["cerebro"], x["pm_id"], x["via"], corto(x["titulo"], 40)))
    if cerrar:
        print("  → cerrar con: bash/tasks/complete_task.sh <ids> --at <fecha de PM> --author cruce-pm")

if estricto and (huecos or cerrar):
    sys.exit(1)
PY

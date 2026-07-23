#!/usr/bin/env bash
# Health and findings of the ONTOLOGY itself — the metrics behind the viz
# "ontologia" dashboard.
#
# Reads the BUILT artifacts (docs/graph/graph.json + business.json), not the DB.
# That is deliberate: the ontology is not a view of the database, it is a curated
# artifact ABOUT it (verified implicit edges with their resolution rates, the
# rejected claims, the domain classification, the role aliases). Re-deriving it
# live would throw that curation away.
#
# The one thing it DOES ask the DB is drift: how many entities exist now versus
# how many the graph knows about — so "always up to date" cannot quietly become
# "silently stale". If the DB is unreachable, drift comes back null and
# everything else still works.
#
# Usage:  ontology_stats.sh [--json] [--no-db]
#   --json    One JSON object (what the viz consumes).
#   --no-db   Skip the drift check (pure file-based, no connection).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
GRAPHDIR="$REPO/docs/graph"

FORMAT="${FORMAT:-table}"
USE_DB=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)  FORMAT=json ;;
    --no-db) USE_DB=0 ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "ontology_stats.sh: unknown arg '$1'" >&2; exit 2 ;;
  esac
  shift
done

# --- drift: entities in the DB right now vs entities the graph models ---------
DB_ENTITIES=""
if [[ "$USE_DB" == "1" ]]; then
  # shellcheck disable=SC1091
  source "$REPO/bash/lib/common.sh" 2>/dev/null || true
  if declare -F psql_ro >/dev/null 2>&1; then
    DB_ENTITIES="$(psql_ro -t -A -c "
      SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='ikigaigm' AND c.relkind IN ('r','v','m','p');" 2>/dev/null || echo "")"
  fi
fi

GRAPHDIR="$GRAPHDIR" DB_ENTITIES="$DB_ENTITIES" FORMAT="$FORMAT" python3 <<'PY'
import json, os, sys, collections, datetime

D = os.environ["GRAPHDIR"]
FORMAT = os.environ["FORMAT"]
db_entities = os.environ.get("DB_ENTITIES", "").strip()
db_entities = int(db_entities) if db_entities.isdigit() else None

def load(name):
    p = os.path.join(D, name)
    with open(p) as f:
        return json.load(f), datetime.datetime.fromtimestamp(os.path.getmtime(p))

g,  g_at = load("graph.json")
b,  b_at = load("business.json")

def components(nodes, edges):
    """Connected components over the undirected projection. A knowledge graph
    that has fragmented into islands is a different (worse) thing than one
    dense graph, and the node/edge counts alone never show it."""
    adj = {n["id"]: set() for n in nodes}
    for e in edges:
        if e["source"] in adj and e["target"] in adj:
            adj[e["source"]].add(e["target"]); adj[e["target"]].add(e["source"])
    seen, comps = set(), []
    for nid in adj:
        if nid in seen: continue
        stack, size = [nid], 0
        seen.add(nid)
        while stack:
            cur = stack.pop(); size += 1
            for nb in adj[cur]:
                if nb not in seen: seen.add(nb); stack.append(nb)
        comps.append(size)
    return sorted(comps, reverse=True)

def pct(a, b): return round(100.0 * a / b, 1) if b else 0.0

# ---------------- data layer: knowledge-graph health -------------------------
gn, ge = g["nodes"], g["edges"]
N, E = len(gn), len(ge)
gcomp = components(gn, ge)
isolated = [n["id"] for n in gn if n["degree"] == 0]
implicit = [e for e in ge if e["kind"] == "implicit"]
res = [e["verified"]["pct"] for e in implicit if e.get("verified")]
fragile = sorted(
    ({"relacion": f'{e["source"]}.{e["src_col"]} → {e["target"]}',
      "pct": e["verified"]["pct"],
      "detalle": f'{e["verified"]["matched"]}/{e["verified"]["total"]}'}
     for e in implicit if e.get("verified") and e["verified"]["pct"] < 100),
    key=lambda x: x["pct"])
jsonb_total = sum(len(n.get("jsonb", [])) for n in gn)
jsonb_linked = len({e["source"] for e in implicit if "." in e["src_col"] or "{" in e["src_col"]})

dato = {
    "entidades": N, "relaciones": E,
    "fk": g["meta"]["n_fk"], "implicitas": g["meta"]["n_implicit"],
    "reglas": g["meta"]["n_rules"],
    "grado_medio": round(2.0 * E / N, 2) if N else 0,
    "densidad": round(2.0 * E / (N * (N - 1)), 4) if N > 1 else 0,
    "aisladas": len(isolated),
    "componentes": len(gcomp),
    "mayor_componente": gcomp[0] if gcomp else 0,
    "pct_en_mayor": pct(gcomp[0] if gcomp else 0, N),
    "pct_con_pk": pct(sum(1 for n in gn if n.get("pk")), N),
    "pct_con_reglas": pct(sum(1 for n in gn
                              if n.get("enums") or n.get("checks") or n.get("uniques")), N),
    "pct_conectadas": pct(N - len(isolated), N),
    "resolucion_media": round(sum(res) / len(res), 1) if res else None,
    "implicitas_al_100": sum(1 for p in res if p == 100),
    "jsonb_columnas": jsonb_total,
    "jsonb_con_relacion": jsonb_linked,
    "rechazadas": len(g["meta"].get("rejected", [])),
}

# ---------------- concept layer: what the ontology says about the org --------
bn, be = b["nodes"], b["edges"]
arqs = [n for n in bn if n["group"] == "archetype"]
usados = [a for a in arqs if a.get("tasks", 0) > 0]
tareas = sum(a.get("tasks", 0) for a in arqs)
top = sorted(arqs, key=lambda a: -a.get("tasks", 0))[:5]
ejec = [e for e in be if e["kind"] == "ejecuta"]
tareas_ejec = sum(e.get("tasks", 0) for e in ejec)
F = b["meta"]["findings"]
gaps = F["ejecucion_fuera_de_lo_declarado"]          # top-N, for display only
n_gaps = F.get("n_ejecucion_fuera_de_lo_declarado", len(gaps))   # the real total
tareas_fuera = F.get("tareas_fuera_de_lo_declarado", sum(x["tasks"] for x in gaps))
con_in  = {e["source"] for e in be if e["kind"] == "requiere"}
con_out = {e["source"] for e in be if e["kind"] == "produce"}
sops = [n for n in bn if n["group"] == "sop"]
sop_con_arq = {e["source"] for e in be if e["kind"] == "agrupa"}

negocio = {
    "conceptos": len(bn), "relaciones": len(be),
    "macro_procesos": sum(1 for n in bn if n["group"] == "macro"),
    "sops": len(sops),
    "sops_sin_arquetipos": sum(1 for s in sops if s["id"] not in sop_con_arq),
    "arquetipos": len(arqs),
    "arquetipos_usados": len(usados),
    "arquetipos_sin_usar": len(arqs) - len(usados),
    "pct_instanciado": pct(len(usados), len(arqs)),
    "tareas": tareas,
    "concentracion_top1": pct(top[0].get("tasks", 0), tareas) if top and tareas else 0,
    "concentracion_top5": pct(sum(a.get("tasks", 0) for a in top), tareas) if tareas else 0,
    "pct_con_insumos": pct(len(con_in), len(arqs)),
    "pct_con_entregables": pct(len(con_out), len(arqs)),
    "roles": sum(1 for n in bn if n["group"] == "role"),
    "clientes": sum(1 for n in bn if n["group"] == "project"),
    "tipos_entregable": sum(1 for n in bn if n["group"] == "io_type"),
    "pares_fuera_de_lo_declarado": n_gaps,
    "pct_tareas_fuera_de_lo_declarado": pct(tareas_fuera, tareas_ejec) if tareas_ejec else 0,
}

# value chain with its real load
by_macro = {}
sop_of = {n["id"]: n for n in bn if n["group"] == "sop"}
for a in arqs:
    s = sop_of.get(f'sop:{a.get("sop")}')
    if not s: continue
    m = s.get("macro")
    d = by_macro.setdefault(m, {"arquetipos": 0, "tareas": 0})
    d["arquetipos"] += 1; d["tareas"] += a.get("tasks", 0)
cadena = []
for n in sorted((n for n in bn if n["group"] == "macro"),
                key=lambda n: (n.get("chain_order") or 99)):
    d = by_macro.get(n["label"], {"arquetipos": 0, "tareas": 0})
    cadena.append({"macro": n["label"], "nombre": n["name"],
                   "orden": n.get("chain_order"), **d,
                   "pct_tareas": pct(d["tareas"], tareas)})

out = {
    "frescura": {
        "grafo_dato": g_at.isoformat(timespec="seconds"),
        "grafo_negocio": b_at.isoformat(timespec="seconds"),
        "dias_desde_build": round((datetime.datetime.now() - min(g_at, b_at)).total_seconds() / 86400, 1),
        "entidades_en_db": db_entities,
        "deriva_entidades": (db_entities - N) if db_entities is not None else None,
    },
    "dato": dato,
    "negocio": negocio,
    "hallazgos": {
        "hubs": [{"entidad": n["id"], "grado": n["degree"], "dominio": n["domain_label"]}
                 for n in sorted(gn, key=lambda n: -n["degree"])[:6]],
        "implicitas_fragiles": fragile,
        "top_arquetipos": [{"arquetipo": a["label"], "nombre": a["name"],
                            "tareas": a.get("tasks", 0),
                            "pct": pct(a.get("tasks", 0), tareas)} for a in top],
        "sin_instanciar": sorted(a["label"] for a in arqs if a.get("tasks", 0) == 0),
        "deriva_roles": [{"rol": x["role"], "arquetipo": x["archetype"], "tareas": x["tasks"],
                          "declarado": ", ".join(x["declared"])} for x in gaps[:8]],
        "cadena": cadena,
        "rechazadas": g["meta"].get("rejected", []),
    },
}

if FORMAT == "json":
    print(json.dumps(out, ensure_ascii=False))
    sys.exit(0)

# ---- human-readable ---------------------------------------------------------
def sec(t): print(f"\n\033[1m{t}\033[0m")
f = out["frescura"]
sec("FRESCURA")
print(f"  grafo dato    {f['grafo_dato']}")
print(f"  grafo negocio {f['grafo_negocio']}   ({f['dias_desde_build']} días)")
if f["deriva_entidades"] is None:
    print("  deriva        — (sin DB)")
else:
    d = f["deriva_entidades"]
    print(f"  deriva        {'AL DÍA' if d == 0 else f'{d:+d} entidades sin modelar'}"
          f"  (DB={f['entidades_en_db']}, grafo={dato['entidades']})")
sec("CAPA DE DATO")
for k in ("entidades","relaciones","fk","implicitas","reglas","grado_medio","densidad",
          "componentes","mayor_componente","aisladas","pct_con_pk","pct_con_reglas",
          "resolucion_media","jsonb_columnas","jsonb_con_relacion","rechazadas"):
    print(f"  {k:<22} {dato[k]}")
sec("CAPA DE NEGOCIO")
for k in ("conceptos","relaciones","macro_procesos","sops","sops_sin_arquetipos","arquetipos",
          "arquetipos_usados","arquetipos_sin_usar","pct_instanciado","tareas",
          "concentracion_top1","concentracion_top5","pct_con_insumos","pct_con_entregables",
          "pares_fuera_de_lo_declarado","pct_tareas_fuera_de_lo_declarado"):
    print(f"  {k:<32} {negocio[k]}")
sec("CADENA DE VALOR")
for c in cadena:
    print(f"  {str(c['orden'] or '-'):>2}. {c['macro']:<4} {c['nombre'][:34]:<34} "
          f"{c['arquetipos']:>3} arq  {c['tareas']:>4} tareas  {c['pct_tareas']:>5}%")
sec("EJECUCIÓN FUERA DE LO DECLARADO")
for x in out["hallazgos"]["deriva_roles"]:
    print(f"  {x['rol']:<18} {x['arquetipo']:<6} {x['tareas']:>3} tareas   declarado: {x['declarado'][:40]}")
sec("IMPLÍCITAS POR DEBAJO DEL 100%")
for x in fragile:
    print(f"  {x['pct']:>5}%  {x['detalle']:<12} {x['relacion']}")
print()
PY

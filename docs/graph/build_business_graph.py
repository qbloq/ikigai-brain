#!/usr/bin/env python3
"""Build the BUSINESS (conceptual) ontology of the organization.

This is the layer ABOVE the schema graph: not tables and FKs, but the concepts
the org actually runs on — the value chain, its macro-processes, the SOPs that
decompose them, the activity archetypes that group under each SOP, the typed
deliverables those archetypes declare, the roles that own them and the clients
they serve.

Two kinds of relation live here and they are deliberately kept apart:
  * DECLARED  — what the catalog says (a SOP is owned by these roles)
  * OBSERVED  — what the 329 real tasks say (this role actually executed it,
                this client actually consumed it)
Keeping both is the point: the gap between them is the finding.

Outputs: business.json (node-link) + business.ttl (RDF/Turtle)
Usage:   build_business_graph.py <business_dir_with_tsvs> <output_dir>
"""
import json, os, re, sys, unicodedata

IN  = sys.argv[1] if len(sys.argv) > 1 else "business"
OUT = sys.argv[2] if len(sys.argv) > 2 else "."

def read_tsv(name, width=None):
    rows = []
    with open(os.path.join(IN, name)) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line: continue
            parts = line.split("\t")
            if width: parts = (parts + [""] * width)[:width]
            rows.append(parts)
    return rows

# ---- concept classes (the meta-model) ---------------------------------------
CLASSES = {
    "macro":     "Macro-proceso",
    "sop":       "SOP",
    "archetype": "Arquetipo de actividad",
    "role":      "Rol",
    "project":   "Cliente / Proyecto",
    "io_type":   "Tipo de entregable",
}
# Which tables in the data layer realize each concept — the bridge down to the
# schema graph, so the two ontologies stay connected instead of parallel.
REALIZED_BY = {
    "macro":     ["macro_processes"],
    "sop":       ["sops"],
    "archetype": ["activity_archetypes", "archetype_inputs", "archetype_outputs",
                  "archetype_acceptance_criteria", "tasks"],
    "role":      ["team_roles", "team_members", "users", "persons"],
    "project":   ["projects"],
    "io_type":   ["io_types", "artifact_types", "task_inputs", "task_outputs"],
}

# ---- role identity ----------------------------------------------------------
# Role rows are duplicated per team, so role_id is NOT a role's identity — the
# name is. The catalog and the DB also disagree on two names; alias them and
# keep the disagreement recorded rather than silently normalising it away.
ALIASES = {"pm": "Project Manager"}
def rkey(name):
    s = unicodedata.normalize("NFKD", name.strip().lower())
    s = "".join(c for c in s if not unicodedata.combining(c))
    return ALIASES.get(s, s)

# ---- load -------------------------------------------------------------------
macros    = read_tsv("macros.tsv", 7)
sops      = read_tsv("sops.tsv", 5)
archs     = read_tsv("archetypes.tsv", 9)
arch_io   = read_tsv("arch_io.tsv", 4)
io_types  = read_tsv("io_types.tsv", 3)
roles     = read_tsv("roles.tsv", 2)
projects  = read_tsv("projects.tsv", 3)
proj_arch = read_tsv("project_archetype.tsv", 3)
role_arch = read_tsv("role_archetype.tsv", 3)
coverage  = {r[0]: int(r[1]) for r in read_tsv("coverage.tsv", 2)}

nodes, edges = [], []
def add(nid, cls, label, name, **kw):
    nodes.append({"id":nid,"group":cls,"group_label":CLASSES[cls],
                  "label":label,"name":name, **kw})
def link(s, t, kind, label, **kw):
    edges.append({"source":s,"target":t,"kind":kind,"label":label, **kw})

# roles: canonical registry, keyed by normalised name
role_people, role_display = {}, {}
for name, n in roles:
    k = rkey(name)
    role_people[k] = role_people.get(k, 0) + int(n or 0)
    # prefer the spelling that carries people; else first seen
    if k not in role_display or int(n or 0) > 0:
        role_display.setdefault(k, name)
        if int(n or 0) > 0: role_display[k] = ALIASES.get(k, name)
def role_node(k):
    return f"rol:{role_display.get(k, k)}"

# ---- concept instances ------------------------------------------------------
macro_order = {}
for code, name, order, cadence, owners, status, note in macros:
    o = int(order) if order.strip() else None
    macro_order[code] = o
    add(f"mp:{code}", "macro", code, name, chain_order=o, cadence=cadence,
        status=status, note=note,
        declared_owners=[r for r in owners.split("|") if r])

# the value chain itself: an ordered spine, drawn as a chain of edges
chain = sorted([c for c, o in macro_order.items() if o], key=lambda c: macro_order[c])
for a, b in zip(chain, chain[1:]):
    link(f"mp:{a}", f"mp:{b}", "precede", f"{a}→{b}",
         note="orden de la cadena de valor")

sop_macro = {}
for code, macro, name, owners, status in sops:
    sop_macro[code] = macro
    add(f"sop:{code}", "sop", code, name, macro=macro, status=status,
        declared_owners=[r for r in owners.split("|") if r])
    if macro:
        link(f"mp:{macro}", f"sop:{code}", "descompone", f"{macro} ▸ {code}")

arch_tasks = {}
for aid, sop, verb, name, drole, is_gate, cadence, status, ntasks in archs:
    n = int(ntasks or 0); arch_tasks[aid] = n
    add(f"arq:{aid}", "archetype", aid, name, verb=verb, sop=sop,
        default_role=drole, is_gate=(is_gate == "t"), cadence=cadence,
        status=status, tasks=n)
    if sop:
        link(f"sop:{sop}", f"arq:{aid}", "agrupa", f"{sop} ▸ {aid}")

for name, display, cat in io_types:
    add(f"io:{name}", "io_type", name, display or name, category=cat)

for k, disp in role_display.items():
    add(role_node(k), "role", disp, disp, people=role_people.get(k, 0))

for name, ntot, nopen in projects:
    add(f"proj:{name}", "project", name, name,
        tasks=int(ntot or 0), open_tasks=int(nopen or 0))

known = {n["id"] for n in nodes}

# ---- DECLARED ownership: catalog → roles ------------------------------------
unmatched_roles = set()
for n in list(nodes):
    if n["group"] not in ("macro", "sop"): continue
    for r in n.get("declared_owners", []):
        k = rkey(r)
        rid = role_node(k)
        if rid not in known:
            unmatched_roles.add(r); continue
        link(n["id"], rid, "dueño", f"{n['label']} → {r}", declared=True)

# ---- OBSERVED execution: real tasks -----------------------------------------
for rname, aid, cnt in role_arch:
    rid, aq = role_node(rkey(rname)), f"arq:{aid}"
    if rid in known and aq in known:
        link(rid, aq, "ejecuta", f"{rname} ▷ {aid}", tasks=int(cnt), observed=True)

for pname, aid, cnt in proj_arch:
    pid, aq = f"proj:{pname}", f"arq:{aid}"
    if pid in known and aq in known:
        link(pid, aq, "consume", f"{pname} ▷ {aid}", tasks=int(cnt), observed=True)

# ---- the work contract: archetype ⇄ typed deliverables ----------------------
agg = {}
for aid, direction, io, req in arch_io:
    key = (aid, direction, io)
    agg[key] = agg.get(key, {"n":0, "req":False})
    agg[key]["n"] += 1
    agg[key]["req"] |= (req == "t")
for (aid, direction, io), v in sorted(agg.items()):
    aq, ion = f"arq:{aid}", f"io:{io}"
    if aq in known and ion in known:
        kind = "requiere" if direction == "input" else "produce"
        link(aq, ion, kind, f"{aid} {'←' if direction=='input' else '→'} {io}",
             n=v["n"], required=v["req"])

# ---- degree + findings ------------------------------------------------------
deg = {n["id"]: 0 for n in nodes}
for e in edges:
    if e["source"] in deg: deg[e["source"]] += 1
    if e["target"] in deg: deg[e["target"]] += 1
for n in nodes: n["degree"] = deg[n["id"]]

# declared vs observed, per archetype's SOP owners: who was supposed to own it
# vs who actually did it. This is the whole reason both edge kinds exist.
declared_by_arch = {}
sop_owners = {n["label"]: {rkey(r) for r in n.get("declared_owners", [])}
              for n in nodes if n["group"] == "sop"}
for n in nodes:
    if n["group"] == "archetype":
        declared_by_arch[n["label"]] = sop_owners.get(n.get("sop"), set())
observed = {}
for rname, aid, cnt in role_arch:
    observed.setdefault(aid, {})[rkey(rname)] = int(cnt)

gaps = []
for aid, obs in observed.items():
    dec = declared_by_arch.get(aid, set())
    for rk, cnt in obs.items():
        if dec and rk not in dec:
            gaps.append({"archetype":aid, "role":role_display.get(rk, rk),
                         "tasks":cnt, "declared":sorted(role_display.get(d, d) for d in dec)})
gaps.sort(key=lambda g: -g["tasks"])

never = sorted(a for a, n in arch_tasks.items() if n == 0)

meta = {
    "layer": "negocio (conceptual)",
    "title": "Ikigai · ontología de la organización",
    "subtitle": "cadena de valor → macro-proceso → SOP → arquetipo → tarea",
    "generated_from": "catalog (macro_processes/sops/activity_archetypes + contratos de IO) "
                      "+ tareas reales para la capa observada",
    "classes": CLASSES,
    "realized_by": REALIZED_BY,
    "n_nodes": len(nodes), "n_edges": len(edges),
    "counts": {c: sum(1 for n in nodes if n["group"] == c) for c in CLASSES},
    "edge_kinds": {k: sum(1 for e in edges if e["kind"] == k)
                   for k in ["precede","descompone","agrupa","dueño","ejecuta","consume","requiere","produce"]},
    "coverage": coverage,
    "findings": {
        "arquetipos_sin_tareas": never,
        "roles_del_catalogo_sin_rol_en_db": sorted(unmatched_roles),
        # the list is truncated for display; the totals must NOT be re-derived
        # from it (counting the truncated list would under-report 103 as 20)
        "n_ejecucion_fuera_de_lo_declarado": len(gaps),
        "tareas_fuera_de_lo_declarado": sum(g["tasks"] for g in gaps),
        "tareas_observadas": sum(int(c) for _, _, c in role_arch),
        "ejecucion_fuera_de_lo_declarado": gaps[:20],
    },
}
graph = {"meta": meta, "nodes": nodes, "edges": edges}
os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT, "business.json"), "w") as f:
    json.dump(graph, f, ensure_ascii=False, indent=2)

# ---- RDF / Turtle -----------------------------------------------------------
def esc(s): return str(s).replace("\\", "\\\\").replace('"', "'").replace("\n", " ")
def uri(nid):
    pfx, _, rest = nid.partition(":")
    return f"{ {'mp':'mp','sop':'sop','arq':'arq','rol':'rol','proj':'proj','io':'io'}[pfx] }:" \
           + re.sub(r"[^A-Za-z0-9_.-]+", "_", rest)

PRED = {"precede":"biz:precedeA","descompone":"biz:seDescomponeEn","agrupa":"biz:agrupa",
        "dueño":"biz:tieneDueño","ejecuta":"biz:ejecuta","consume":"biz:consume",
        "requiere":"biz:requiere","produce":"biz:produce"}
CLSU = {"macro":"biz:MacroProceso","sop":"biz:SOP","archetype":"biz:ArquetipoDeActividad",
        "role":"biz:Rol","project":"biz:Cliente","io_type":"biz:TipoDeEntregable"}

ttl = [
    "@prefix rdf:  <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .",
    "@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .",
    "@prefix owl:  <http://www.w3.org/2002/07/owl#> .",
    "@prefix biz:  <https://ikigai.parallelo.ai/ontology/business#> .",
    "@prefix ent:  <https://ikigai.parallelo.ai/ontology/entity#> .",
    "@prefix mp:   <https://ikigai.parallelo.ai/business/macro#> .",
    "@prefix sop:  <https://ikigai.parallelo.ai/business/sop#> .",
    "@prefix arq:  <https://ikigai.parallelo.ai/business/arquetipo#> .",
    "@prefix rol:  <https://ikigai.parallelo.ai/business/rol#> .",
    "@prefix proj: <https://ikigai.parallelo.ai/business/cliente#> .",
    "@prefix io:   <https://ikigai.parallelo.ai/business/entregable#> .",
    "", "### Concept classes, each bridged to the tables that realize it",
]
for c, lbl in CLASSES.items():
    ttl.append(f'{CLSU[c]} a owl:Class ; rdfs:label "{lbl}"@es ;')
    ttl.append("    " + " ; ".join(f'biz:realizadoPor ent:{t}' for t in REALIZED_BY[c]) + " .")
ttl += ["", "### Relations"]
for k, p in PRED.items():
    ttl.append(f'{p} a owl:ObjectProperty ; rdfs:label "{k}"@es ; '
               f'biz:evidencia "{"observada" if k in ("ejecuta","consume") else "declarada"}" .')
ttl += ["", "### Instances"]
for n in nodes:
    ttl.append(f'{uri(n["id"])} a {CLSU[n["group"]]} ;')
    ttl.append(f'    rdfs:label "{esc(n["label"])}" ;')
    ttl.append(f'    biz:nombre "{esc(n["name"])}" ;')
    if n.get("tasks") is not None:  ttl.append(f'    biz:tareas {n["tasks"]} ;')
    if n.get("people") is not None: ttl.append(f'    biz:personas {n["people"]} ;')
    if n.get("chain_order"):        ttl.append(f'    biz:ordenCadena {n["chain_order"]} ;')
    if n.get("verb"):               ttl.append(f'    biz:verbo "{esc(n["verb"])}" ;')
    ttl.append(f'    rdfs:comment "{esc(n["group_label"])}"@es .')
ttl += ["", "### Statements"]
for e in edges:
    extra = ""
    if e.get("tasks"): extra = f' ; biz:tareas {e["tasks"]}'
    ttl.append(f'{uri(e["source"])} {PRED[e["kind"]]} {uri(e["target"])}{extra} .'
               if not extra else
               f'[] rdf:subject {uri(e["source"])} ; rdf:predicate {PRED[e["kind"]]} ; '
               f'rdf:object {uri(e["target"])} ; biz:tareas {e["tasks"]} .')
    if extra:  # keep the plain triple too, so simple queries still work
        ttl.append(f'{uri(e["source"])} {PRED[e["kind"]]} {uri(e["target"])} .')
ttl.append("")
with open(os.path.join(OUT, "business.ttl"), "w") as f:
    f.write("\n".join(ttl))

print(f"nodes={len(nodes)} edges={len(edges)}")
print("  clases:", ", ".join(f"{CLASSES[c]}={v}" for c, v in meta["counts"].items()))
print("  relaciones:", ", ".join(f"{k}={v}" for k, v in meta["edge_kinds"].items()))
print(f"  arquetipos nunca instanciados: {len(never)}/{len(arch_tasks)}")
print(f"  roles del catálogo sin rol en DB: {sorted(unmatched_roles) or '—'}")
print(f"  ejecución fuera de lo declarado: {len(gaps)} pares rol×arquetipo")
for g in gaps[:5]:
    print(f"    {g['role']:<18} {g['archetype']:<6} {g['tasks']:>3} tareas "
          f"(declarado: {', '.join(g['declared'])[:44]})")

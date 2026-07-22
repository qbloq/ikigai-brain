#!/usr/bin/env python3
"""Build the ikigaigm schema graph in faithful representations:
   - graph.json : neutral node-link (source of truth for viz + downstream)
   - schema.ttl : RDF/Turtle ontology (semantic layer)

Beyond entities+FKs this carries the parts of the ontology Postgres knows but a
plain FK dump throws away:
  * cardinality (1:1 vs N:1, from a single-column unique index on the FK column)
  * participation (mandatory vs optional, from NOT NULL)
  * referential action (ON DELETE)
  * rules: enums, CHECK constraints (incl. the check-as-enum idiom), UNIQUE
  * the relations that travel through jsonb / arrays, each one VERIFIED against
    live data and stamped with its resolution rate (see IMPLICIT below).

Usage: build_graph.py <catalog_dir_with_tsvs> <output_dir>
Inputs (produced by dump_catalog.sh): tables, fk_rich, pks, enums,
                                      typed_cols, constraints  (.tsv)
"""
import json, os, re, sys

IN  = sys.argv[1] if len(sys.argv) > 1 else "catalog"
OUT = sys.argv[2] if len(sys.argv) > 2 else "."

def read_tsv(name):
    rows = []
    with open(os.path.join(IN, name)) as f:
        for line in f:
            line = line.rstrip("\n")
            if line:
                rows.append(line.split("\t"))
    return rows

# ---- domain classification --------------------------------------------------
DOMAINS = {
    "tasks":"Tareas","meetings":"Reuniones","crm":"CRM / Ventas","ads":"Pauta (Meta)",
    "finance":"Finanzas","catalog":"Ontología de procesos","people":"Personas / Equipo",
    "projects":"Proyectos / Config","okr":"OKR / KPI","runtime":"Runtime agéntico / LLM",
    "content":"Contenido (Notion/Drive)","whatsapp":"WhatsApp","misc":"Otros",
}
EXPLICIT_DOMAIN = {
    "users":"people","persons":"people","team_members":"people","team_roles":"people",
    "teams":"people","team_member_roles":"people","identities":"people",
    "projects":"projects","spaces":"projects","project_teams":"projects",
    "project_ad_account_mappings":"projects","project_campaign_mappings":"projects",
    "project_crm_configs":"projects","project_google_configs":"projects",
    "project_meta_configs":"projects","project_notion_configs":"projects",
    "project_panda_video_configs":"projects","project_panda_video_selections":"projects",
    "project_vturb_video_configs":"projects","project_vturb_video_selections":"projects",
    "project_whatsapp_configs":"projects","settings":"projects",
    "tasks":"tasks","task_inputs":"tasks","task_outputs":"tasks","task_acceptance_criteria":"tasks",
    "task_attestations":"tasks","task_comments":"tasks","task_todos":"tasks","task_columns":"tasks",
    "artifact_binding_backup_inputs":"tasks","artifact_binding_backup_outputs":"tasks",
    "meetings":"meetings","meeting_reports":"meetings","meeting_transcripts":"meetings",
    "meeting_participants":"meetings","call_meeting_results":"meetings",
    "crm_contacts":"crm","crm_opportunities":"crm","crm_pipelines":"crm",
    "crm_calendars":"crm","crm_custom_fields":"crm","funnel_goals":"crm",
    "ad_accounts":"ads","ad_sets":"ads","ads":"ads","ad_insights_daily":"ads",
    "campaigns":"ads","campaign_insights_daily":"ads","meta_capi_events":"ads",
    "payment_plans":"finance","installments":"finance","commission_payouts":"finance",
    "commission_rules":"finance","expenses":"finance","expense_categories":"finance",
    "expense_templates":"finance","economics_ledger":"finance","products":"finance",
    "revenue_share_distributions":"finance","revenue_share_payouts":"finance",
    "revenue_share_rules":"finance","payroll_actuals":"finance","payroll_rules":"finance",
    "macro_processes":"catalog","sops":"catalog","activity_archetypes":"catalog",
    "archetype_inputs":"catalog","archetype_outputs":"catalog","archetype_acceptance_criteria":"catalog",
    "archetype_params":"catalog","io_types":"catalog","artifact_types":"catalog",
    "verification_templates":"catalog",
    "objectives":"okr","key_results":"okr","kpis":"okr","kpi_snapshots":"okr","okr_reviews":"okr",
    "llm_calls":"runtime","llmrouter_api_keys":"runtime","prompt_sections":"runtime",
    "prompt_budgets":"runtime","runners":"runtime","runner_runs":"runtime","workers":"runtime",
    "worker_runs":"runtime","skills":"runtime","output_channels":"runtime",
    "graph_conversations":"runtime","graph_messages":"runtime",
    "sql_conversations":"runtime","sql_messages":"runtime",
    "notion_content_index":"content","drive_index":"content","drive_index_type_stats":"content",
    "whatsapp_messages":"whatsapp","user_evolution_instances":"whatsapp",
}
def domain_of(t): return EXPLICIT_DOMAIN.get(t, "misc")

ONDELETE = {"a":"no action","r":"restrict","c":"cascade","n":"set null","d":"set default"}

# ---- rules: parse CHECK / UNIQUE definitions --------------------------------
def parse_check(defn):
    """Recognise the check-as-enum idiom (col = ANY (ARRAY['a','b',...])), which is
    how most of this schema declares allowed values; anything else stays raw."""
    m = re.search(r"\(*([a-z_][a-z0-9_]*)\)*(?:::text)?\s*=\s*ANY\s*\(+\s*ARRAY\[(.*?)\]",
                  defn, re.I | re.S)
    if m:
        vals = re.findall(r"'([^']*)'", m.group(2))
        if vals:
            return {"type":"allowed_values","col":m.group(1),"values":vals}
    body = defn[6:].strip() if defn.upper().startswith("CHECK ") else defn
    return {"type":"expr","expr":body.strip("() ")}

def parse_unique(defn):
    m = re.search(r"UNIQUE\s*\((.*?)\)", defn, re.I | re.S)
    return [c.strip() for c in m.group(1).split(",")] if m else []

# ---- load -------------------------------------------------------------------
tables      = read_tsv("tables.tsv")
fks         = read_tsv("fk_rich.tsv")
pks         = {r[0]: r[1] for r in read_tsv("pks.tsv")}
enum_types  = {r[0]: r[1].split("|") for r in read_tsv("enums.tsv")}
typed_cols  = read_tsv("typed_cols.tsv")
constraints = read_tsv("constraints.tsv")

# per-table rule/column indexes
enums_by_tbl, jsonb_by_tbl, arrays_by_tbl = {}, {}, {}
for relname, attname, typname, typtype, notnull in typed_cols:
    if typtype == "e":
        enums_by_tbl.setdefault(relname, []).append(
            {"col":attname,"type":typname,"values":enum_types.get(typname, [])})
    elif typname in ("jsonb","json"):
        jsonb_by_tbl.setdefault(relname, []).append(attname)
    elif typname.startswith("_"):
        arrays_by_tbl.setdefault(relname, []).append(
            {"col":attname,"of":typname.lstrip("_")})

checks_by_tbl, uniques_by_tbl = {}, {}
for relname, contype, conname, defn in constraints:
    if contype == "c":
        checks_by_tbl.setdefault(relname, []).append(dict(name=conname, **parse_check(defn)))
    else:
        checks = parse_unique(defn)
        if checks:
            uniques_by_tbl.setdefault(relname, []).append({"name":conname,"cols":checks})

nodes = []
for relname, kind, rows, ncols in tables:
    d = domain_of(relname)
    nodes.append({
        "id":relname,"kind":kind,"rows":int(rows),"cols":int(ncols),
        "domain":d,"domain_label":DOMAINS[d],
        "pk":pks.get(relname),
        "enums":enums_by_tbl.get(relname, []),
        "checks":checks_by_tbl.get(relname, []),
        "uniques":uniques_by_tbl.get(relname, []),
        "jsonb":jsonb_by_tbl.get(relname, []),
        "arrays":arrays_by_tbl.get(relname, []),
    })
node_ids = {n["id"] for n in nodes}

# ---- FK edges, with cardinality + participation + referential action --------
edges, seen = [], set()
for src, scol, snotnull, tgt, tcol, sunique, deltype, cname in fks:
    key = (src, scol, tgt, tcol)
    if key in seen: continue
    seen.add(key)
    edges.append({
        "source":src,"target":tgt,"src_col":scol,"tgt_col":tcol,
        "kind":"fk","self":src==tgt,"label":f"{scol}→{tcol}",
        "card":"1:1" if sunique=="t" else "N:1",
        "optional":snotnull!="t",
        "on_delete":ONDELETE.get(deltype, deltype),
        "constraint":cname,
    })

# ---- implicit relationships -------------------------------------------------
# Relations no FK enforces, that the domain uses daily. Every one below was
# VERIFIED against live data — `verified` is (matched, total) of distinct source
# values that resolve on the target. They are NOT assumptions.
#   src, tgt, via (source path), tgt_col, (matched,total), note
IMPLICIT = [
    ("tasks","team_members","assignee[]","id",(18,18),
     "assignee uuid[]: cada elemento resuelve a team_members.id (no hay FK sobre el array)"),
    ("meetings","crm_contacts","event.booking.contact_id","ghl_contact_id",(1267,1559),
     "traza del closer: el booking de GHL embebido en event apunta al contacto"),
    ("crm_opportunities","crm_pipelines","ghl_stage_id","stages[].id",(15,15),
     "la etapa del tablero vive DENTRO del jsonb stages del pipeline, no en una tabla"),
    ("crm_contacts","crm_custom_fields","custom_fields[].id","ghl_field_id",(73,94),
     "cada valor de campo personalizado referencia su definición por id de GHL"),
    ("project_ad_account_mappings","ad_accounts","ad_account_id","id",(8,8),
     "mapea cuenta publicitaria→proyecto por id externo de Meta"),
    ("project_campaign_mappings","campaigns","campaign_id","id",(23,23),
     "mapea campaña→proyecto por id externo de Meta"),
    ("users","project_crm_configs","integrations{location}","location_id",(2,4),
     "las LLAVES del jsonb integrations son location_id de GHL; el valor es el ghl_user"),
    ("output_channels","project_whatsapp_configs","config.whatsapp_config_id","id",(1,1),
     "el canal de salida de WhatsApp apunta a la config del proyecto desde su jsonb"),
    ("task_inputs","drive_index","artifact_reference.file_id","file_id",(1,1),
     "un input ligado a un archivo de Drive guarda el file_id en su binding jsonb"),
    ("macro_processes","team_roles","owner_roles[]","name",(13,14),
     "el dueño del macro-proceso se referencia por NOMBRE de rol, no por id"),
    ("sops","team_roles","owner_roles[]","name",(12,13),
     "el dueño del SOP se referencia por NOMBRE de rol, no por id"),
]
for src, tgt, scol, tcol, (matched, total), note in IMPLICIT:
    if src not in node_ids or tgt not in node_ids:
        print(f"  !! implicit skipped (entidad ausente): {src}→{tgt}", file=sys.stderr)
        continue
    edges.append({
        "source":src,"target":tgt,"src_col":scol,"tgt_col":tcol,
        "kind":"implicit","self":False,"label":f"{scol}→{tcol}",
        "card":"N:1","optional":True,"on_delete":"—","note":note,
        "verified":{"matched":matched,"total":total,
                    "pct":round(100.0*matched/total) if total else None},
    })

# Candidates tested against live data and REJECTED — kept so they are not
# re-added from folklore. (They were documented as real before this pass.)
REJECTED = [
    {"claim":"users.crm_id → crm_opportunities.user_id",
     "why":"crm_id guarda un id de usuario de GHL (texto, p.ej. '61qHdbyUdafDb9nDxit3'), "
           "no un uuid: 0/6 parecen uuid. El camino real ya es la FK "
           "crm_opportunities.user_id → users.id (10/10)."},
    {"claim":"meta_capi_events → crm_contacts.ghl_contact_id",
     "why":"payload->data solo trae user_data hasheado (PII para CAPI); no hay id de "
           "contacto. Sus relaciones reales ya son FK a installments y projects."},
]

deg = {n["id"]:0 for n in nodes}
for e in edges:
    if e["source"] in deg: deg[e["source"]] += 1
    if e["target"] in deg: deg[e["target"]] += 1
for n in nodes: n["degree"] = deg[n["id"]]

n_rules = sum(len(n["enums"]) + len(n["checks"]) + len(n["uniques"]) for n in nodes)
graph = {
    "meta":{
        "schema":"ikigaigm",
        "generated_from":"pg_catalog (entidades, FK+cardinalidad, PK, enums, checks, "
                         "únicos) + sondeo verificado de jsonb/arrays",
        "n_nodes":len(nodes),"n_edges":len(edges),
        "n_fk":sum(1 for e in edges if e["kind"]=="fk"),
        "n_implicit":sum(1 for e in edges if e["kind"]=="implicit"),
        "n_rules":n_rules,
        "n_enums":sum(len(n["enums"]) for n in nodes),
        "n_checks":sum(len(n["checks"]) for n in nodes),
        "n_uniques":sum(len(n["uniques"]) for n in nodes),
        "n_jsonb":sum(len(n["jsonb"]) for n in nodes),
        "domains":DOMAINS,
        "rejected":REJECTED,
    },
    "nodes":nodes,"edges":edges,
}
os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT,"graph.json"),"w") as f:
    json.dump(graph, f, ensure_ascii=False, indent=2)

# ---- RDF / Turtle ontology --------------------------------------------------
def esc(s): return str(s).replace("\\", "\\\\").replace('"', "'")
def cls(t): return f"ent:{t}"
def prop(src, scol, tgt):
    slug = re.sub(r"[^A-Za-z0-9]+", "_", scol).strip("_")
    return f"rel:{src}__{slug}__{tgt}"

ttl = [
    "@prefix rdf:  <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .",
    "@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .",
    "@prefix owl:  <http://www.w3.org/2002/07/owl#> .",
    "@prefix xsd:  <http://www.w3.org/2001/XMLSchema#> .",
    "@prefix ent:  <https://ikigai.parallelo.ai/ontology/entity#> .",
    "@prefix rel:  <https://ikigai.parallelo.ai/ontology/relation#> .",
    "@prefix dom:  <https://ikigai.parallelo.ai/ontology/domain#> .",
    "@prefix rule: <https://ikigai.parallelo.ai/ontology/rule#> .",
    "", "### Domains (grouping concepts)",
]
for k, v in DOMAINS.items():
    ttl.append(f'dom:{k} a owl:Class ; rdfs:label "{v}"@es .')

ttl += ["", "### Entities (tables/views as classes)"]
for n in nodes:
    ttl.append(f'{cls(n["id"])} a owl:Class ;')
    ttl.append(f'    rdfs:label "{n["id"]}" ;')
    ttl.append(f'    rdfs:subClassOf dom:{n["domain"]} ;')
    if n["pk"]:
        ttl.append(f'    rule:primaryKey "{esc(n["pk"])}" ;')
    for u in n["uniques"]:
        ttl.append(f'    rule:unique "{esc(",".join(u["cols"]))}" ;')
    ttl.append(f'    rdfs:comment "{n["kind"]}, ~{n["rows"]} filas, {n["cols"]} columnas"@es .')

ttl += ["", "### Rules: enumerated value sets (enum types and CHECK-as-enum)"]
for n in nodes:
    for en in n["enums"]:
        ttl.append(f'{cls(n["id"])} rule:enumerated [ rule:column "{esc(en["col"])}" ; '
                   f'rule:datatype "{esc(en["type"])}" ; '
                   f'rule:oneOf "{esc("|".join(en["values"]))}" ] .')
    for ck in n["checks"]:
        if ck["type"] == "allowed_values":
            ttl.append(f'{cls(n["id"])} rule:enumerated [ rule:column "{esc(ck["col"])}" ; '
                       f'rule:datatype "check" ; '
                       f'rule:oneOf "{esc("|".join(ck["values"]))}" ] .')
        else:
            ttl.append(f'{cls(n["id"])} rule:constraint "{esc(ck["expr"])}" .')

ttl += ["", "### Relations (FK = object properties; implicit ones carry evidence)"]
for e in edges:
    p = prop(e["source"], e["src_col"], e["target"])
    ttl.append(f'{p} a owl:ObjectProperty ;')
    ttl.append(f'    rdfs:domain {cls(e["source"])} ;')
    ttl.append(f'    rdfs:range  {cls(e["target"])} ;')
    ttl.append(f'    rdfs:label "{esc(e["label"])}" ;')
    ttl.append(f'    rule:cardinality "{e["card"]}" ;')
    ttl.append(f'    rule:participation "{"opcional" if e["optional"] else "obligatoria"}" ;')
    # a mandatory N:1 means every instance must have exactly one target
    if not e["optional"]:
        ttl.append(f'    rdfs:subPropertyOf owl:FunctionalProperty ;'
                   if e["card"] == "1:1" else '    rule:minCardinality "1" ;')
    if e["kind"] == "implicit":
        v = e["verified"]
        ttl.append(f'    rule:enforced "false" ;')
        ttl.append(f'    rule:resolution "{v["matched"]}/{v["total"]} ({v["pct"]}%)" ;')
        ttl.append(f'    rdfs:comment "IMPLÍCITA (no forzada por FK): {esc(e.get("note",""))}"@es .')
    else:
        ttl.append(f'    rule:enforced "true" ;')
        ttl.append(f'    rule:onDelete "{e["on_delete"]}" ;')
        ttl.append(f'    rdfs:comment "foreign key {esc(e.get("constraint",""))}"@es .')
ttl.append("")
with open(os.path.join(OUT,"schema.ttl"),"w") as f:
    f.write("\n".join(ttl))

m = graph["meta"]
print(f"nodes={m['n_nodes']} edges={m['n_edges']} (fk={m['n_fk']} implícitas={m['n_implicit']})")
print(f"reglas={m['n_rules']} (enums={m['n_enums']} checks={m['n_checks']} únicos={m['n_uniques']}) "
      f"· columnas jsonb={m['n_jsonb']} · rechazadas={len(REJECTED)}")
card = {}
for e in edges: card[(e["card"], "opcional" if e["optional"] else "obligatoria")] = \
    card.get((e["card"], "opcional" if e["optional"] else "obligatoria"), 0) + 1
for k, v in sorted(card.items()): print(f"  {k[0]:4} {k[1]:<12} {v}")
for n in sorted(nodes, key=lambda n:-n["degree"])[:8]:
    print(f"  hub {n['id']:<28} deg={n['degree']:<3} {n['domain']}")

#!/usr/bin/env python3
"""Build the ikigaigm schema graph in faithful representations:
   - graph.json : neutral node-link (source of truth for viz + downstream)
   - schema.ttl : RDF/Turtle ontology (semantic layer)
Usage: build_graph.py <input_dir_with_tsvs> <output_dir>
Inputs: tables.tsv (relname, kind, approx_rows, ncols)
        fks.tsv    (src_tbl, src_col, tgt_tbl, tgt_col, cname)
"""
import json, os, sys

IN  = sys.argv[1] if len(sys.argv) > 1 else "."
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

# ---- load -------------------------------------------------------------------
tables = read_tsv("tables.tsv")
fks = read_tsv("fks.tsv")

nodes = []
for relname, kind, rows, ncols in tables:
    d = domain_of(relname)
    nodes.append({"id":relname,"kind":kind,"rows":int(rows),"cols":int(ncols),
                  "domain":d,"domain_label":DOMAINS[d]})

edges, seen = [], set()
for src, scol, tgt, tcol, cname in fks:
    key = (src, scol, tgt, tcol)
    if key in seen: continue
    seen.add(key)
    edges.append({"source":src,"target":tgt,"src_col":scol,"tgt_col":tcol,
                  "kind":"fk","self":src==tgt,"label":f"{scol}→{tcol}"})

# ---- implicit relationships (documented in CLAUDE.md, not FK-enforced) -------
IMPLICIT = [
    ("tasks","team_members","assignee[]","id","assignee uuid[] resuelve a team_members (no hay FK sobre el array)"),
    ("meetings","crm_contacts","event.booking.contact_id","ghl_contact_id","traza del closer: booking.contact_id ≈ crm_contacts.ghl_contact_id"),
    ("project_ad_account_mappings","ad_accounts","account_id","(externo)","mapea cuenta publicitaria→proyecto por id externo de Meta"),
    ("project_campaign_mappings","campaigns","campaign_id","(externo)","mapea campaña→proyecto por id externo"),
    ("users","crm_opportunities","crm_id","user_id","crm_id (integrations jsonb) es lo que la resolución del closer lee"),
    ("meta_capi_events","crm_contacts","(evento)","ghl_contact_id","eventos CAPI ligados al contacto/lead"),
]
for src, tgt, scol, tcol, note in IMPLICIT:
    edges.append({"source":src,"target":tgt,"src_col":scol,"tgt_col":tcol,
                  "kind":"implicit","self":False,"label":f"{scol}→{tcol}","note":note})

deg = {n["id"]:0 for n in nodes}
for e in edges:
    if e["source"] in deg: deg[e["source"]] += 1
    if e["target"] in deg: deg[e["target"]] += 1
for n in nodes: n["degree"] = deg[n["id"]]

graph = {
    "meta":{"schema":"ikigaigm",
            "generated_from":"pg_catalog + information_schema (FK) + CLAUDE.md (implicit)",
            "n_nodes":len(nodes),"n_edges":len(edges),
            "n_fk":sum(1 for e in edges if e["kind"]=="fk"),
            "n_implicit":sum(1 for e in edges if e["kind"]=="implicit"),
            "domains":DOMAINS},
    "nodes":nodes,"edges":edges,
}
os.makedirs(OUT, exist_ok=True)
with open(os.path.join(OUT,"graph.json"),"w") as f:
    json.dump(graph, f, ensure_ascii=False, indent=2)

# ---- RDF / Turtle ontology --------------------------------------------------
def cls(t): return f"ent:{t}"
def prop(src, scol, tgt): return f"rel:{src}__{scol.replace('[]','_arr').replace('.','_')}__{tgt}"
ttl = [
    "@prefix rdf:  <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .",
    "@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .",
    "@prefix owl:  <http://www.w3.org/2002/07/owl#> .",
    "@prefix ent:  <https://ikigai.parallelo.ai/ontology/entity#> .",
    "@prefix rel:  <https://ikigai.parallelo.ai/ontology/relation#> .",
    "@prefix dom:  <https://ikigai.parallelo.ai/ontology/domain#> .",
    "", "### Domains (grouping concepts)",
]
for k, v in DOMAINS.items():
    ttl.append(f'dom:{k} a owl:Class ; rdfs:label "{v}"@es .')
ttl += ["", "### Entities (tables/views as classes)"]
for n in nodes:
    ttl.append(f'{cls(n["id"])} a owl:Class ;')
    ttl.append(f'    rdfs:label "{n["id"]}" ;')
    ttl.append(f'    rdfs:subClassOf dom:{n["domain"]} ;')
    ttl.append(f'    rdfs:comment "{n["kind"]}, ~{n["rows"]} filas, {n["cols"]} columnas"@es .')
ttl += ["", "### Relations (FK = object properties; implicit flagged)"]
for e in edges:
    p = prop(e["source"], e["src_col"], e["target"])
    ttl.append(f'{p} a owl:ObjectProperty ;')
    ttl.append(f'    rdfs:domain {cls(e["source"])} ;')
    ttl.append(f'    rdfs:range  {cls(e["target"])} ;')
    ttl.append(f'    rdfs:label "{e["label"].replace(chr(34), chr(39))}" ;')
    if e["kind"] == "implicit":
        ttl.append(f'    rdfs:comment "IMPLÍCITA (no forzada por FK): {e.get("note","").replace(chr(34),chr(39))}"@es .')
    else:
        ttl.append('    rdfs:comment "foreign key"@es .')
ttl.append("")
with open(os.path.join(OUT,"schema.ttl"),"w") as f:
    f.write("\n".join(ttl))

print(f"nodes={len(nodes)} edges={len(edges)} fk={graph['meta']['n_fk']} implicit={graph['meta']['n_implicit']}")
for n in sorted(nodes, key=lambda n:-n["degree"])[:12]:
    print(f"  hub {n['id']:<28} deg={n['degree']:<3} {n['domain']}")

# Grafo de entidades — esquema `ikigaigm`

Grafo inicial de todas las entidades de la DB (Supabase/Postgres) y sus
relaciones, levantado desde el **catálogo de Postgres** (fuente determinista)
+ las **relaciones implícitas** documentadas en `CLAUDE.md` (no forzadas por FK).

**98 entidades** (97 tablas + 1 vista) · **148 relaciones** (142 FK + 6 implícitas)
· **13 dominios**. Hubs: `projects` (grado 40 — la columna del org),
`users` (24), `tasks` (10), `meetings` (8).

## Artefactos

| Archivo | Qué es | Para qué |
|---------|--------|----------|
| `graph.json` | Node-link neutral (`{meta, nodes[], edges[]}`). Cada nodo lleva `domain`, `kind`, `rows`, `cols`, `degree`; cada edge `kind` (`fk`\|`implicit`), `src_col`/`tgt_col`. | Fuente de verdad. Alimenta el visor y cualquier consumidor downstream (D3, cytoscape, networkx, un import a GraphDB). |
| `schema.ttl` | Ontología **RDF/Turtle**: entidades → `owl:Class` (subclase de su dominio), FKs → `owl:ObjectProperty` con `rdfs:domain`/`rdfs:range`. Las implícitas quedan marcadas en `rdfs:comment`. | Semantic layer / triple-store (GraphDB, Fuseki, rdflib, Neo4j n10s). |
| `schema-graph.html` | Visor interactivo self-contained (force-directed, sin dependencias externas). Filtro por dominio, toggle FK/implícitas, click → panel de relaciones, búsqueda, zoom/pan. | Visualizar y navegar. Se publica como Artifact. |

## Regenerar (cuando cambie el esquema)

```bash
# 1) re-dumpear el catálogo (read-only) a TSV
source bash/lib/common.sh
psql_ro -t -A -F$'\t' -c "SELECT c.relname, CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view' WHEN 'm' THEN 'matview' WHEN 'p' THEN 'parted' ELSE c.relkind::text END, GREATEST(c.reltuples::bigint,0), (SELECT count(*) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='ikigaigm' AND c.relkind IN ('r','v','m','p') ORDER BY c.relname;" > tables.tsv
psql_ro -t -A -F$'\t' -c "SELECT kcu.table_name, kcu.column_name, ccu.table_name, ccu.column_name, tc.constraint_name FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage kcu ON tc.constraint_name=kcu.constraint_name AND tc.table_schema=kcu.table_schema JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name=tc.constraint_name AND ccu.table_schema=tc.table_schema WHERE tc.constraint_type='FOREIGN KEY' AND tc.table_schema='ikigaigm' ORDER BY kcu.table_name;" > fks.tsv

# 2) reconstruir graph.json + schema.ttl (leyendo los TSV del dir actual)
python3 docs/graph/build_graph.py . docs/graph

# 3) regenerar el visor con los datos embebidos
python3 docs/graph/build_viewer.py docs/graph
```

## Relaciones implícitas incluidas

No las fuerza ningún FK, pero el dominio las usa a diario (viven en `build_graph.py` → `IMPLICIT`):

- `tasks.assignee[]` → `team_members.id` (uuid array, sin FK)
- `meetings.event.booking.contact_id` ≈ `crm_contacts.ghl_contact_id` (traza del closer)
- `project_ad_account_mappings.account_id` → `ad_accounts` (id externo de Meta)
- `project_campaign_mappings.campaign_id` → `campaigns` (id externo)
- `users.crm_id` → `crm_opportunities.user_id` (resolución del closer)
- `meta_capi_events` → `crm_contacts.ghl_contact_id` (evento CAPI ↔ lead)

## Notas

- `rows` es la estimación de `pg_class.reltuples` (aprox, no `count(*)`).
- Falta por modelar: relaciones que viajan por columnas jsonb (p.ej. `users.integrations`,
  `meetings.event`) más allá de las 6 implícitas anotadas. Se agregan a `IMPLICIT` cuando se necesiten.

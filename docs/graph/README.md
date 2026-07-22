# Grafo de Ikigai — dos capas de ontología

La ontología vive en **dos capas**, cada una con su grafo, su Turtle y su visor.
Un solo motor las dibuja (`build_viewer.py --profile schema|business`).

| Capa | Qué modela | Artefactos |
|---|---|---|
| **Dato** (abajo) | las 98 entidades de la DB, sus relaciones y reglas | `graph.json` · `schema.ttl` · `schema-graph.html` |
| **Negocio** (arriba) | los conceptos de la organización: cadena de valor → macro-proceso → SOP → arquetipo → tarea, con roles, clientes y entregables | `business.json` · `business.ttl` · `business-graph.html` |

Las capas están **puenteadas**: cada clase conceptual declara en `meta.realized_by`
qué tablas de la capa de dato la realizan (p. ej. `Rol` ← `team_roles`,
`team_members`, `users`, `persons`), así las dos ontologías no crecen en paralelo.

---

# Capa de dato — esquema `ikigaigm`

Ontología del **dato**: todas las entidades de la DB (Supabase/Postgres), sus
relaciones y las **reglas** que las gobiernan, levantadas desde el **catálogo de
Postgres** (fuente determinista) + un **sondeo verificado** de las columnas
`jsonb`/array que cargan relaciones que ningún FK obliga.

**98 entidades** (97 tablas + 1 vista) · **154 relaciones** (143 FK + 11
implícitas verificadas) · **85 reglas** (20 enums + 22 checks + 43 únicos) ·
**13 dominios**. Hubs: `projects` (grado 40 — la columna del org),
`users` (25), `tasks` (10), `meetings` (8), `team_roles` (8).

## Qué carga el modelo (más allá de "tabla → tabla")

| Dimensión | De dónde sale | Para qué sirve |
|---|---|---|
| **Cardinalidad** (`1:1` / `N:1`) | índice único de una sola columna sobre la columna FK | distinguir un perfil (1:1) de una colección (N:1) |
| **Participación** (obligatoria / opcional) | `NOT NULL` en la columna FK | saber si la relación puede faltar |
| **Acción referencial** (`ON DELETE`) | `pg_constraint.confdeltype` | qué se lleva por delante un borrado |
| **Reglas de valor** | enums + `CHECK` (incl. el idiom *check-as-enum*) | los estados legales de cada entidad |
| **Identidad y unicidad** | PK + constraints `UNIQUE` | qué hace única a una fila |
| **Relaciones implícitas** | sondeo de `jsonb`/arrays **verificado contra datos vivos** | el 7% del grafo que no está en los FK |

Reparto de cardinalidad: **9** relaciones `1:1` obligatorias, **1** `1:1`
opcional, **64** `N:1` obligatorias, **80** `N:1` opcionales.

## Artefactos

| Archivo | Qué es | Para qué |
|---------|--------|----------|
| `dump_catalog.sh` | Vuelca el catálogo a 6 TSV (`catalog/`). **Read-only**. | Hacer reproducible la extracción. |
| `graph.json` | Node-link neutral (`{meta, nodes[], edges[]}`). Cada nodo lleva `domain`, `kind`, `rows`, `cols`, `degree`, `pk`, `enums`, `checks`, `uniques`, `jsonb`, `arrays`; cada edge `kind`, `card`, `optional`, `on_delete` y, si es implícita, `verified`. | Fuente de verdad. Alimenta el visor y cualquier consumidor (D3, cytoscape, networkx, import a GraphDB). |
| `schema.ttl` | Ontología **RDF/Turtle**: entidades → `owl:Class`, relaciones → `owl:ObjectProperty` con `rdfs:domain`/`rdfs:range`, más el vocabulario `rule:` (`cardinality`, `participation`, `onDelete`, `enumerated`, `primaryKey`, `unique`, `enforced`, `resolution`). **2.177 triples**, validado con rdflib. | Semantic layer / triple-store (GraphDB, Fuseki, rdflib, Neo4j n10s) y consultas SPARQL. |
| `schema-graph.html` | Visor interactivo self-contained (force-directed, sin dependencias externas). Filtro y aislamiento por dominio, toggle FK/implícitas, click → panel con relaciones (cardinalidad + participación + evidencia), reglas y columnas semiestructuradas. | Visualizar y navegar. Se publica como Artifact. |

## Regenerar (cuando cambie el esquema)

```bash
docs/graph/dump_catalog.sh                              # 1) catálogo → docs/graph/catalog/*.tsv
python3 docs/graph/build_graph.py docs/graph/catalog docs/graph   # 2) graph.json + schema.ttl
python3 docs/graph/build_viewer.py docs/graph           # 3) visor con los datos embebidos
```

## Relaciones implícitas (verificadas, no supuestas)

No las fuerza ningún FK, pero el dominio las usa a diario. Cada una se comprobó
con un join real contra datos vivos; `resuelve` es la fracción de valores
distintos de origen que encuentran destino. Viven en `build_graph.py` → `IMPLICIT`.

| Origen | Camino | Destino | Resuelve |
|---|---|---|---|
| `tasks` | `assignee[]` | `team_members.id` | 18/18 (100%) |
| `crm_opportunities` | `ghl_stage_id` | `crm_pipelines.stages[].id` | 15/15 (100%) |
| `project_campaign_mappings` | `campaign_id` | `campaigns.id` | 23/23 (100%) |
| `project_ad_account_mappings` | `ad_account_id` | `ad_accounts.id` | 8/8 (100%) |
| `output_channels` | `config.whatsapp_config_id` | `project_whatsapp_configs.id` | 1/1 (100%) |
| `task_inputs` | `artifact_reference.file_id` | `drive_index.file_id` | 1/1 (100%) |
| `macro_processes` | `owner_roles[]` | `team_roles.name` | 13/14 (93%) |
| `sops` | `owner_roles[]` | `team_roles.name` | 12/13 (92%) |
| `meetings` | `event.booking.contact_id` | `crm_contacts.ghl_contact_id` | 1267/1559 (81%) |
| `crm_contacts` | `custom_fields[].id` | `crm_custom_fields.ghl_field_id` | 73/94 (78%) |
| `users` | `integrations{location}` | `project_crm_configs.location_id` | 2/4 (50%) |

Las tres últimas no llegan al 100% y eso **es el dato**: marcan la cola de higiene
(el 19% de reuniones sin contacto resuelto es la misma cola S8.2 que documenta
`CLAUDE.md` para el closer).

### Correcciones de esta pasada

Al verificar se cayeron dos relaciones que estaban documentadas como reales, y
una tercera apuntaba a una columna inexistente. Quedan registradas en
`graph.json` → `meta.rejected` para que no vuelvan por folclore:

- ❌ `users.crm_id → crm_opportunities.user_id` — `crm_id` guarda un **id de
  usuario de GHL** (texto, p.ej. `61qHdbyUdafDb9nDxit3`): 0 de 6 valores parecen
  uuid. El camino real ya era la **FK** `crm_opportunities.user_id → users.id` (10/10).
- ❌ `meta_capi_events → crm_contacts.ghl_contact_id` — `payload->data` solo trae
  `user_data` hasheado (PII para CAPI); no hay id de contacto. Sus relaciones
  reales ya son FK a `installments` y `projects`.
- ⚠️ `project_ad_account_mappings.account_id` no existe: la columna es
  **`ad_account_id`** (corregida; resuelve 8/8).

## Notas

- `rows` es la estimación de `pg_class.reltuples` (aprox, no `count(*)`).
- Los enums se anclan por **OID del tipo**, no por nombre: esta DB aloja un
  segundo proyecto no relacionado y hay nombres de enum repetidos entre esquemas
  (filtrar por `typname` fusionaba los labels de ambos).
- Quedan **50 columnas jsonb** en el esquema; solo las que probaron cargar una
  relación están como aristas. El resto es configuración, payloads o esquemas
  (`skills.input_schema`, `settings.config`, `llm_calls.*`), no relaciones.
- `llm_calls.prompt_sections`, `okr_reviews.key_result_snapshots` y
  `task_attestations.responsible_contact` están **vacías** (0 filas no nulas):
  no hay nada que extraer todavía.

---

# Capa de negocio — la ontología de la organización

Los conceptos sobre los que la empresa opera, no las tablas donde se guardan.
**167 conceptos** · **644 relaciones** · 6 clases. Se levanta del catálogo de
procesos (`macro_processes`/`sops`/`activity_archetypes` + sus contratos de IO)
y de las **329 tareas reales**.

```
cadena de valor → macro-proceso (S1…S12) → SOP (Sx.y) → arquetipo (A_.__) → tarea
```

| Clase | N | Realizada por (capa de dato) |
|---|---|---|
| Macro-proceso | 12 | `macro_processes` |
| SOP | 36 | `sops` |
| Arquetipo de actividad | 76 | `activity_archetypes`, `archetype_*`, `tasks` |
| Rol | 21 | `team_roles`, `team_members`, `users`, `persons` |
| Cliente / Proyecto | 4 | `projects` |
| Tipo de entregable | 18 | `io_types`, `artifact_types`, `task_inputs/outputs` |

## Declarado vs. observado — la razón de ser de esta capa

Las relaciones se guardan en dos sabores y **no se mezclan**:

- **Declaradas** por el catálogo: `descompone`, `agrupa`, `dueño`, `requiere`,
  `produce`, `precede` (línea sólida).
- **Observadas** en las tareas reales: `ejecuta` (rol→arquetipo),
  `consume` (cliente→arquetipo), con el número de tareas (línea punteada).

El hueco entre ambas es el hallazgo, no un error de datos:

- **103 pares rol×arquetipo se ejecutan fuera de lo declarado.** El caso mayor:
  A2.5 *«Editar audio/video de anuncios»* declara dueño **Editor**, pero lo
  ejecuta el **Project Manager** en 48 tareas (el Editor, 32).
- **A2.5 concentra 84 de 329 tareas** (26%): la organización es, en volumen, una
  máquina de editar creativos.
- **17 de 76 arquetipos nunca se instanciaron**: catálogo declarado que la
  operación todavía no usa.

## Regenerar

```bash
docs/graph/dump_business.sh                                        # capa de negocio → business/*.tsv
python3 docs/graph/build_business_graph.py docs/graph/business docs/graph
python3 docs/graph/build_viewer.py docs/graph --profile business
```

## Notas

- Los roles se identifican **por nombre**, no por `role_id`: las filas de
  `team_roles` están duplicadas por equipo. El catálogo y la DB discrepan en dos
  nombres (`PM`/`Project Manager`, `Líder de Servicio`/`Líder de servicio`);
  se alían explícitamente en `ALIASES`/`rkey()` en vez de normalizar en silencio.
- El visor de negocio abre con las clases **Rol**, **Cliente** y **Tipo de
  entregable** plegadas: 644 aristas de golpe son una madeja. Encender una clase
  trae sus relaciones con ella.

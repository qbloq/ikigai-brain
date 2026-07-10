- The DB connection string is DATABASE_URL in .env
- We only use the ´ikigaigm´ schema

# Data access via bash/ scripts

Prefer these scripts over writing ad-hoc SQL for common reads. They are
**read-only** (connection forced to `default_transaction_read_only=on`), scoped
to the `ikigaigm` schema, and evaluate dates in `America/Bogota`. Every script
accepts `--json` for machine-readable output and `-h` for usage.

Shared helpers live in [bash/lib/common.sh](bash/lib/common.sh) (loads `.env`,
`psql_ro`, the `emit` renderer, and the assignee-name resolution used everywhere).

**Write operations** opt into `psql_rw` (a writable connection) and live alongside
the read scripts but are clearly marked WRITE. They run in a transaction, print
before/after, and support `--dry-run` (rolls back). `resolve_member <id-prefix|name>`
turns a member reference into a `team_members.id`, erroring on ambiguous names.

## Tasks domain ([bash/tasks/](bash/tasks/))

| Script | Use it to… |
|--------|-----------|
| `tasks.sh [--status S] [--priority P] [--project NAME] [--assignee NAME] [--due W] [--open] [--limit N]` | List/filter tasks. `--due W` = due window (today/tomorrow/yesterday/this-week/next-week/overdue). `--limit 0` = no cap. |
| `tasks_by_role.sh [--role NAME] [...same filters as tasks.sh]` | Filter tasks by assignee **role** (resolves assignee→team_members→team_roles). Adds a `roles` column. Omit `--role` to list all with roles shown. |
| `tasks_due.sh --today\|--tomorrow\|--yesterday\|--this-week\|--next-week\|--overdue` | Tasks by due date. Also `--from YYYY-MM-DD --to YYYY-MM-DD`. Defaults to open tasks; `--all` includes done. |
| `task_show.sh <id\|prefix>` | Full detail of one task: header + inputs + outputs + acceptance criteria + todos + comments. Id may be the UUID prefix (e.g. `a9644868`). |
| `task_detail.sh <id\|prefix>` | One task as a single JSON object (resolved project/assignees + io_types), tailored for the viz detail panel. Always JSON. |
| `task_stats.sh [--by status\|priority\|project\|assignee] [--open]` | Aggregate counts. |
| `projects.sh` | List projects (clients) with open/total task counts. |
| `team.sh [--team NAME]` | List team members (the universe of assignees) with name, role, team, contact. |
| `reassign.sh <id> --from M --to M` / `--add M` / `--remove M` / `--set M,M` **[WRITE]** | Change a task's assignees. M = id-prefix or name fragment. `--dry-run` to preview. |
| `add_comment.sh <id> --text "…" [--author NAME] [--dry-run] [--json]` **[WRITE]** | Append one comment to a task's comment trail (nothing deleted/overwritten). One txn, before/after, `--json` emits `{task_id,comment_id,…}`. `--author` defaults to `note`. Use to record a cross-reference/decision on an existing task (e.g. a dedup/merge candidate found via the meeting pipeline) instead of creating a duplicate task. |
| `io_types.sh` | List the semantic IO types (with default artifact type) usable in task contracts. |
| `io_catalog.sh` | One JSON object `{io_types[], artifact_types[]}` (with ids) — reference data for the viz IO editor's dropdowns. Read-only. |
| `update_task_io.sh --io <id> [--title T] [--io-type NAME] [--artifact NAME] [--required true\|false]` / `--add input\|output --task <id>` / `--delete --io <id> [--cascade]` **[WRITE]** | Edit one IO row of a task: retype its `io_type`/`artifact_type` (accepts id, name, or display_name), rename, toggle required, or add/remove rows. One op per call, one transaction, before/after, `--dry-run`, `--json` (emits `task_id` for re-render). Deleting an output with acceptance criteria is blocked unless `--cascade`. Powers the viz IO editor. Also `--ref-merge '<json>'` / `--ref-clear`: shallow-merge into / wipe the row's binding jsonb (`artifact_reference`/`deliverable_reference`) — how a **SQL Results** artifact stores its `{query, params}` and how bind caches `_resolved`. |
| `run_io_query.sh <io_id\|prefix> [--limit N] [--json]` | Execute the SQL persisted in one IO row's binding (`reference.query`) and print the result — the concrete data of a `sql_query` artifact (its sql resolver). Read-only + `statement_timeout=10s` + row cap (default 500). Only runs SQL with provenance (already persisted in the DB row); accepts nothing inline. Feeds the viz `io_query` source. |
| `create_task.sh <contract.json\|-> [--dry-run]` **[WRITE]** | Insert a full task "work contract" (task + inputs + outputs + acceptance criteria) from JSON. Pre-validates project/assignees/io_types; one transaction. Tags `archetype` (→SOP). **Template instantiation:** pass `archetype`+`slots` with no inputs/outputs to pull the archetype's template contract and substitute `{slots}`. **Provenance:** `source_meeting` (id/prefix→FK), `source_url`/`source_external_id` (Notion), `source_type` (auto-inferred) populate the tasks provenance columns. See `-h`. |
| `set_archetype.sh <id> <archetype-id> [--method m] [--confidence X]` / `<id> --clear` **[WRITE]** | (Re)tag a task's activity archetype (the human/correction path; `create_task.sh` tags at birth). Validates the archetype; SOP/macro follow via the join. `--dry-run` to preview. |
| `ingest_notion.sh <classified.json> [--project N] [--limit N] [--only-open] [--yes]` **[WRITE]** | Bulk-ingest Notion tasks (from an ontology-pilot `classified.json`) into `tasks` in ONE txn: born with provenance (`source_type='notion'`, `source_url`, `source_external_id`) + archetype tag (`method='llm'`). v1 = **tag+provenance only** (no IO instantiation, no assignees). Dedups by `source_external_id` (idempotent). Safe by default: previews + ROLLBACK unless `--yes`. |
| `materialize_io.sh [--source notion] [--label NAME] [--yes]` **[WRITE]** | Backfill the IO work-contract (task_inputs/outputs/acceptance_criteria) onto EXISTING tasks by instantiating their archetype's template (set-based, one txn). Substitutes `{proyecto}`→label; **neutralizes other unfilled `{slots}`→«pendiente»** (templates keep their slots — the dimensional socket — untouched). Idempotent (skips tasks that already have IO); scoped by `--source`. Safe by default: ROLLBACK unless `--yes`. Only tasks whose archetype has a template get IO. |
| `cancel_task.sh <id> [--into <id>] [--reason "…"]` **[WRITE]** | Cancel a task (`status='cancelled'`), optionally recording a merge into another (`--into`) with an auditable comment trail on both. Nothing is deleted. `--dry-run` to preview. Use for dedup/merges (e.g. cross-project duplicates the per-project dedup misses). |
| `wipe_tasks.sh [--yes]` **[WRITE, IRREVERSIBLE]** | Delete the ENTIRE task domain (tasks + inputs + outputs + criteria + attestations + todos + comments) in one FK-safe transaction. Preserves `task_columns` and all FK parents. Safe by default: previews + rolls back unless `--yes`. Back up first (CSV snapshots in `backups/tasks-backup-<date>/`, restore via its `restore.sql`). |

**Skill — IO review session:**
- `revisar-tarea-io` ([.claude/skills/revisar-tarea-io/](.claude/skills/revisar-tarea-io/SKILL.md)):
  `/revisar-tarea-io <task-id>` — interactive review/edit of ONE task's IO
  contract with the user: renders `task_detail.sh` + `io_catalog.sh`, then maps
  each request to a single `update_task_io.sh` call (the CLI twin of the viz
  "Editor de IO"). Criteria editing is out of scope (no write script yet).

## Meetings domain ([bash/meetings/](bash/meetings/))

Scoped to **team meetings** (`meetings.meeting_type='team'`) — the coordination
meetings across projects. Each usually has a `meeting_transcripts` row (raw text)
and a `meeting_reports` row (structured jsonb, in Spanish).

| Script | Use it to… |
|--------|-----------|
| `meetings.sh [--status S] [--project NAME] [--from D] [--to D] [--has-report] [--has-transcript] [--limit N]` | List team meetings. Columns include `rep`/`tr` flags. Default 30; `--limit 0` = no cap. |
| `meeting_show.sh <id\|prefix>` | Full detail: header + participants + report (summary, objectives, decisions, action items, blockers, next steps). `--json` dumps the raw report jsonb. |
| `meeting_transcript.sh <id\|prefix>` | Print the raw transcript text. |
| `meeting_action_items.sh [--since D] [--priority P] [--assignee NAME] [--limit N]` | Flatten action items across team-meeting reports (coordination view). |
| `upsert_report.sh <id\|prefix> <report.json\|-> [--dry-run]` **[WRITE]** | Insert or REPLACE a team meeting's structured report (jsonb). Upserts on UNIQUE `meeting_id` (overwrites without looking back); validates the meeting + all 14 canonical keys; leaves `report_es` untouched. |

**Skills — the meeting pipeline:**
- `transcript-to-report` ([.claude/skills/transcript-to-report/](.claude/skills/transcript-to-report/SKILL.md)):
  **Stage 1** — regenerates the canonical report jsonb from the transcript with an
  evidence-grounded, SOP-mapped task-discovery pass, then upserts it via
  `upsert_report.sh` (replace without looking back). Emits a discovery **sidecar**
  to `backups/meeting-reports/<id>.discovery.md` (resolved owners + ISO dates +
  SOP refs + evidence) that feeds Stage 2–3.
- `meeting-to-tasks` ([.claude/skills/meeting-to-tasks/](.claude/skills/meeting-to-tasks/SKILL.md)):
  **Stages 2–3** — turns the action items (preferring the sidecar) into proposed
  task work contracts (via `create_task.sh`) for review + insertion.

### Meetings data model
- **meetings** — `meeting_type` is `team` (166) or `call` (1731); `status`: scheduled/completed/ended/cancelled/processing/… `scheduled_start_time`/`actual_start_time`, `project_id`→projects, `space_id`→spaces. `meeting_type` matters: `team` = coordination, `call` = sales calls.
- **meeting_reports.report** (jsonb, ES) keys: `reportTitle`, `reportSubtitle`, `executiveSummary` (string), `meetingObjectives`/`meetingContext`/`nextStepsAndFollowUp` (objects), `actionItems` (array of `{task,dueDate,priority,assignedTo[],dependencies}`), `discussionPointsAndDecisions` (array of `{topic,summary,decision,rationale}`), `criticalIssuesAndBlockers` (array of `{issue,status,nextSteps}`), plus `risksAndConcerns`/`keySubjectAreas`/`resourceRequirements`/`futureConsiderations`/`additionalNotes`. `report_es` is unused (always null).
- **meeting_transcripts.transcript** — plain text (Speaker A/B/… diarized). **meeting_participants** is sparse (only ~9 team meetings populated; names often blank). Note: action-item `assignedTo` uses free-text nicknames, not team_member ids.

## Calls domain — sales calls ([bash/calls/](bash/calls/))

Scoped to **sales calls** (`meetings.meeting_type='call'`, ~1.8k) — the
closers' work product, which never enters the task system. ~200 have an
analysis report (jsonb, its own 6-section canon: `generalInformation` with
lead/program/**callStatus**/paymentDate · `generalMetrics` ·
`performanceInsights` with the 5-phase call structure + **finalCloserEvaluation**
(overallScore 0-10, strengths, coaching) + marketingInsights ·
`objectionsAndInsights` (objections with status/closerResponse/aiSuggestion) ·
`leadProfile` (BANT, archetype, closing probability + strategy) ·
`aiAgentConclusion`). Built for the **Director Comercial** role (S12).

**Closer resolution** (no closer column exists — it's a CRM trace, baked into
every script): `meetings.event->booking->>contact_id` =
`crm_contacts.ghl_contact_id` → `crm_opportunities.contact_id` (tiebreak: same
`project_id`, then latest `created_date`) → `.user_id` → `users` → `persons`.
Resolves ~83% of reported calls; the rest is the S8.2 data-hygiene queue.

| Script | Use it to… |
|--------|-----------|
| `calls.sh [--status S] [--result R] [--project N] [--program P] [--closer N] [--from D] [--to D] [--reported] [--sin-closer] [--limit N]` | List calls with lead, program, project, **resolved closer**, resultado, prob, score. `--sin-closer` = reported calls whose closer didn't resolve (S8.2 queue). |
| `call_show.sh <id\|prefix>` | Full detail of one call: header + all 6 report sections rendered (métricas, estructura por fases, evaluación del closer + coaching, objeciones con respuestas, momentos críticos, perfil del lead, marketing insights, conclusión). `--json` = one object incl. raw report. |
| `call_stats.sh [--by closer\|result\|program\|project\|week] [--project N] [--from D] [--to D]` | Effectiveness aggregates over analyzed calls: calls, won, win %, avg closing probability, avg closer score. Default `--by closer` — the Director Comercial's KPI. |
| `call_objections.sh [--project N] [--closer N] [--status S] [--from D] [--to D] [--limit N]` | One row per objection across reports (status, objection, closer response, AI suggestion) — the feedback loop into narrative/copy (S1) and the objection protocol (S12.2). |

Viz sources: `calls`, `call_detail` (object), `call_stats`, `call_objections`.

## Catalog domain — process ontology ([catalog/](catalog/), [bash/catalog/](bash/catalog/))

The org's process ontology, mapped from the start so every task is born tagged.
**Three process tiers** (per [docs/role-sops-discovery.md](docs/role-sops-discovery.md)):

```
value chain → macro_process (S1…S12) → sop (Sx.y) → activity archetype (A_.__) → task
```
S1–S10 are **macro-processes** (§1 spine); each is broken into canonical **SOPs**
(deduped from §2 per-role candidates); each SOP groups **archetypes** (activities);
a task instantiates an archetype. A task rolls up archetype → sop → macro.

- **[catalog/sop-archetypes.json](catalog/sop-archetypes.json)** — canonical source
  of truth: 12 macro-processes (S1–S10 + gaps S11 Producto / S12 Cierre-Retención),
  33 SOPs, 65 archetypes `{id, sop, verb, name, slots[]}`. Every SOP has ≥1 archetype.
- **DB tables** (`ikigaigm`, seeded from the JSON): `macro_processes`, `sops`
  (→macro_processes), `activity_archetypes` (→sops, +`embedding extensions.vector(1536)`
  for the future matcher), `archetype_params`, and the template-contract tables
  `archetype_inputs`/`archetype_outputs`/`archetype_acceptance_criteria` (an
  archetype = a task template with declared I/O+criteria; **S5 Testimonios is the
  first SOP authored**, the rest are pending). Template contracts are declared in
  the catalog JSON per archetype and seeded by `sync_catalog.sh`.
- **`tasks.archetype_id`** (FK→activity_archetypes) + `archetype_confidence` +
  `archetype_match_method` (`rule|embedding|llm|human`): instance → template link.
  The SOP/macro are reached by joining through `activity_archetypes`→`sops`.
- `bash/catalog/sync_catalog.sh [--dry-run]` **[WRITE]** — rebuilds the catalog
  tables from the JSON (task archetype_id values preserved). Re-run after editing it.
- `bash/catalog/sops.sh [--macro CODE] [--json]` — **read-only** listing of the
  ontology: one row per archetype (SOP + macro-process + task count). Feeds the
  viz `sop-tree` UI for navigating SOPs with their activities.
- **Schema of record:** [catalog/migrations/001_process_ontology.sql](catalog/migrations/001_process_ontology.sql)
  — the documented, idempotent DDL for all tables/columns added (the 7 tables above
  + the 3 `tasks.archetype_*` columns). DDL only; seeding is `sync_catalog.sh`'s job.

**Where it plugs in:** `transcript-to-report` classifies each action item (sop +
archetype) in the discovery sidecar; `meeting-to-tasks`/`create_task.sh` persist
the tag. Matching is manual now; the path to automatic is rule → pgvector
embedding → LLM judge (thresholds: ≥0.85 auto · 0.6–0.85 confirm · <0.6 new
candidate), growing the catalog from the tail. Rollup example:
`SELECT mp.code, count(*) FROM tasks t JOIN activity_archetypes a ON a.id=t.archetype_id JOIN sops s ON s.code=a.sop_code JOIN macro_processes mp ON mp.code=s.macro_process_code GROUP BY mp.code`.

## Localdb domain — local SQLite databases ([bash/localdb/](bash/localdb/))

The user's OWN local databases — the **personal data layer** of
[docs/deltas-architecture.md](docs/deltas-architecture.md): prototype schemas
and datasets here without touching the shared Postgres; a proven local schema
(`db_schema.sh`) is the *candidate* for a real migration. All dbs live in
`data/sqlite/` (git-ignored; `LOCALDB_DIR` overrides). Helpers in
[bash/lib/sqlite.sh](bash/lib/sqlite.sh) — deliberately independent of
`common.sh` (works with no `.env`/Postgres); policy mirror of the Postgres
layer: `sqlite_ro` (read-only + safe mode) by default, `sqlite_rw` opt-in for
WRITE scripts, one whitelisted dir, scripts take db *names*, never paths.

| Script | Use it to… |
|--------|-----------|
| `dbs.sh [--json]` | Inventory in one call: each db with size, modified and tables + row counts (feeds the viz `localdbs` source). |
| `db_schema.sh <db> [--table T]` | Schema of one db: columns (name/type/pk/notnull) + row counts. |
| `db_table.sh <db> <table> [--limit N]` | Rows of one table/view; the name is validated against `sqlite_master` and identifier-quoted (viz `localdb_table` source). |
| `db_query.sh <db> [SQL\|-] [--limit N]` | Read-only SQL (the connection is `-readonly -safe`, so the engine rejects writes/dot-commands). Inline SQL is fine locally; via the viz (`localdb_query`) the query comes from the saved UI spec, never the browser. |
| `db_exec.sh <db> [SQL\|-] [--create] [--dry-run]` **[WRITE]** | DDL/DML in ONE transaction — how a local db is created, filled and evolved, and the hook for external syncs (pipe INSERTs in). Local only; cannot touch Postgres. |
| `db_import.sh <db> <file.csv> [--table T] [--replace] [--create] [--dry-run]` **[WRITE]** | CSV → table: new table from the header row, append to an existing one, `--replace` drops it first. One txn. |

The viz `localdb` page (seeded as «Bases locales») is the explorer: left,
every db with its tables + counts; right, a ≤200-row preview. The selection
travels as `?db=&table=`, so any view is URL-addressable (`/u/<id>?db=…`).

## Deltas domain — copilot pipeline ([bash/deltas/](bash/deltas/))

The Fase-1 MVP of [docs/deltas-architecture.md](docs/deltas-architecture.md).
Each employee's copilot is a git FORK of this repo (configured with
`pull.rebase=true`, so its deltas always sit on top of the genome) whose
identity is a `copilot.json` at the root (`{employee, team_member_id, role}`):
the viz store then loads ONLY that role's spec layer and stamps `owner`/`role`
on everything created. The brain (no copilot.json) sees org + all roles.
Everything a copilot writes lands in `viz/specs/local/` and auto-commits —
git IS the telemetry; structure is observed, content never.

| Script | Use it to… |
|--------|-----------|
| `scan.sh <fork-path> [--base origin/main] [--json]` | **Read-only** digest of one fork's deltas: `git diff origin/main...HEAD` classified by path (`viz/specs`→ui-spec · `catalog`→ontología · `*/migrations`→esquema · `copilot.json`→identidad · else→código), with slug/name/lineage for ui-specs. Feeds the Gobernanza session. |
| `elevate_ui.sh <fork-path> <slug> [--to org\|roles/<rol>] [--dry-run] [--json]` **[WRITE to the central tree]** | The spec-pure lane: a fork's `viz/specs/local/<slug>.json` → central `org/` or `roles/<rol>/` (default: the fork's role), validated against the central genome (`validateSpec`), stamped `promoted_from: <employee>/local/<slug>@<fork-sha>` and committed with `Delta-Type`/`Delta-Scope`/`Promoted-From` trailers. Slug collision aborts. |

Pilot fork lives under `data/forks/` (git-ignored). Loop demonstrated
end-to-end (2026-07-08): capture in the fork (auto-commit) → scan digest →
elevate (commit f8b2843) → pull → shadow → unfork. New-fork setup must wipe
the inherited `viz/specs/local/` (open decision: whether the central should
commit its own local layer at all).

## Fleet domain — gobernanza de la torre ([bash/fleet/](bash/fleet/))

La Revisión de deltas de [docs/torre-de-control.md](docs/torre-de-control.md)
(T2): **cola = derivado − decidido**. Lo pendiente se deriva en vivo (scan
sobre `data/forks/`); las decisiones son eventos append-only en
[plataforma/gobernanza/decisiones.jsonl](plataforma/gobernanza/README.md), commiteados
por `review.sh`. Una decisión oculta un delta solo si es más nueva que el
último commit que tocó ese path — si el copiloto re-edita, el delta
reaparece solo. No toca Postgres (todo es git + archivos).

| Script | Use it to… |
|--------|-----------|
| `queue.sh [--all] [--clase C] [--json]` | La cola pendiente (una fila por delta, clave `org/empleado/(capa/slug\|path)`). `--all` incluye lo ya decidido. Fuente viz `fleet_queue`. |
| `review.sh <key\|slug> --dismiss\|--changes\|--elevate [--to DEST] --reason "…" [--by N] [--dry-run] [--json]` **[WRITE al repo]** | Registra UNA decisión (append + commit). `--elevate` (solo ui-spec) delega en `bash/deltas/elevate_ui.sh` y registra el commit resultante. |
| `delta_show.sh <key\|slug>` | Digest de UN delta como objeto JSON: fila + `spec` cruda (ui-spec, para el render en sombra) o `diff` (resto) + `history` de decisiones. Fuente viz `fleet_delta`. Siempre JSON. |
| `orgs.sh [--pull] [--json]` | La Flota (T4): una fila por org del registro `plataforma/clientes/*.json`, cruzada con telemetría (head, pulso, pushes 7d, espejo OK/FALLÓ), forks (copilotos) y cola (Δpend). `--pull` refresca la telemetría antes (offline-first por defecto). Fuente viz `fleet_orgs`. |
| `org_show.sh <org>` | Ficha de UNA org (objeto JSON): identidad + espejo + copilotos (con deltas en cola y última actividad) + últimos 10 pushes + últimas 5 decisiones. Fuente viz `fleet_org_detail`. Siempre JSON. |
| `stats.sh [--by semana\|clase\|accion] [--json]` | Salud/adopción (T5): pulso semanal (pushes + archivos-delta), volumen por clase, decisiones por acción. La fuente que acumula datos para la métrica norte de «cliente sano». Fuente viz `fleet_stats`. |

La telemetría del servidor git es un repo (`telemetria.git`, T1): clon local
en `data/telemetria/` (git-ignored) — `git -C data/telemetria pull` la
actualiza. Alimentará `fleet_stats` (T5).

**Viz (T3–T5):** cuatro UIs sembradas en org — «Revisión de deltas»,
«Flota» (master `orgs-table` + detail `org-detail`, view-only), «Pulso de
deltas (semanal)» (chart line sobre `fleet_stats by=semana`, `y=archivos`) y
«Decisiones de gobernanza» (donut `by=accion`). La Cola (seed org, patrón `master-detail`:
master `queue-table` sobre `fleet_queue`; detail `delta-detail` sobre
`fleet_delta`). Un delta ui-spec se aprueba VIENDO su **render en sombra**
(`GET /shadow/:key` — el gemelo de `/u/:id` para specs de fork, iframe
aislado, jamás instalada); código/esquema muestran diffstat y solo admiten
descartar/pedir cambios. Los tres botones son el primer write-path de la
torre: `@post /c/delta-detail/act/review` → `review.sh` (declarado en
`manifest.writes`).

## Snapshot exports ([scripts/](scripts/))

Regenerate the `backups/` snapshots from the live DB (read-only, open tasks).
`npm run export` runs all three; or `export:json` / `export:by-role` /
`export:by-due-date` individually. See [scripts/README.md](scripts/README.md).

## On-demand UIs — viz server ([viz/](viz/))

When the user asks to **"crear una UI"** (a table/dashboard/visualization), this
is the system to use — **do not** hand-write a one-off HTML file. A "UI" is a
persisted *spec* (`{id, name, component, source, params}`), not frozen markup, so
it always re-renders from live data. Node stdlib, **zero npm deps**;
TailwindCSS (Play CDN) + **Datastar 1.0** over **SSE**. See [viz/README.md](viz/README.md).
Datastar is **vendored** at `viz/public/datastar.js` and served at `/datastar.js`
(not the CDN — avoids CDN/CORS); `viz/public/` is the static-asset dir (also
`chart.umd.js` — Chart.js v4 — and `charts-init.js`, whitelisted in
`PUBLIC_FILES` in server.js).

```bash
npm run viz                 # http://localhost:4317   (PORT=… overrides)
```

- **Data only flows through `bash/ --json`** — same read-only policy as everything
  else. The whitelist of allowed sources + their CLI flags lives in
  [viz/lib/datasources.js](viz/lib/datasources.js) (`SOURCES`): `tasks`, `tasks_due`,
  `projects`, `team`, `task_stats`, `meetings` (now also `from`/`to`/`has-report`),
  `meeting_detail` (one report OBJECT, from `meeting_show.sh --json`), `dashboard`,
  `sops`, `task_detail` (one task OBJECT), `io_catalog` (`{io_types[],
  artifact_types[]}` for the IO editor), `io_query` (the rows of one IO's
  persisted SQL binding, via `run_io_query.sh` — never SQL from the client; the
  query's provenance is the DB row) and the local-SQLite trio
  `localdbs`/`localdb_table`/`localdb_query` (inventory / one table / a
  spec-persisted query over `data/sqlite/` — see the Localdb domain).
  **Never** add SQL here. The one write
  path (the IO editor) likewise shells out to a bash script, never inline SQL.
- **Caching — the DB connection (~0.8s/query, remote) dominates render time.** A
  source opts into a short in-memory TTL cache with `cache: <ms>` in its `SOURCES`
  entry. Use it ONLY for reference/static data (`sops`, `projects`, `team` — 60s);
  **never** for live operational views (`tasks`, `tasks_due`, `dashboard`), whose
  value is freshness. The cache is per-process — `npm run viz:restart` clears it.
  Components that filter in the browser (e.g. a dropdown) should fetch the data
  **once unfiltered** and slice in JS, so every filter change is a cache hit, not a
  re-query (see `sop-tree`).
- **Restart after editing `viz/`** — Node caches required modules, so changes
  (new source, component, cache TTL) need `npm run viz:restart` (or `viz:stop`).
- **The spec store is LAYERED** ([viz/lib/store.js](viz/lib/store.js), deltas
  paso 5): `viz/specs/org/` (the shared genome, in git — seeds live HERE, no
  runtime seeding) → `viz/specs/roles/<rol>/` → `viz/specs/local/` (the
  personal layer, the ONLY writable one). `list()` merges with shadowing by
  stable slug id (local > role > org; the left panel marks a shadowing fork
  with ⑂). Every write goes to `local/`: creating stamps `scope: personal` and
  a slug id; archiving/editing an org/role spec FORKS it into local with
  `derived_from: "<layer>/<slug>@<git-sha>"`. Each local write **auto-commits**
  (`viz(ui): <verb> <slug>` + `Delta-Type: ui-spec` / `Delta-Scope: personal`
  trailers) — git is the delta event log; `VIZ_AUTOCOMMIT=0` disables it.
  Programmatically: `store.create({name, component, source, params})`. Legacy
  `viz/store/` (git-ignored) is migrated once by
  `viz/scripts/migrate-store-to-specs.js` (old ids preserved → `/u/<id>` URLs
  keep working).
- **Layout** is master-detail: left `#ui-list` (saved UIs + form), right `#pane`
  (selected UI). Datastar swaps fragments via SSE — no full reloads.
- **Routes**: `GET /` (shell, `?ui=<id>` opens one) · `GET /u/:id` (standalone page)
  · `GET /ui/:id` (SSE patch `#pane`) · `GET /c/:component/frag/:name` &
  `POST /c/:component/act/:name` (**generic component dispatch** — the
  component's `frags`/`acts` maps own the handlers; handlers never touch
  req/res: they get `ctx = {params, body, run, refreshUiList}` and return HTML
  patches, the server wraps the SSE; server.js never grows a route per
  component) · frozen legacy aliases onto that dispatch: `GET /task/:id` &
  `GET /meeting/:id` (SSE detail panels), `GET /task/:id/edit` +
  `POST /task/:tid/io/...` (the IO editor — see below) · `GET /datastar.js`
  (vendored bundle) · `POST /ui` (gated by `validateSpec`: component/source
  exist, `consumes` matches the source's `emits`, params whitelisted — also
  swept over saved specs at boot (logs) and enforced at render, where an
  unknown component degrades to a "requiere actualizar el núcleo" card) ·
  `POST /ui/:id/archive|unarchive` (soft-hide/restore a UI in the left panel's
  collapsible «Archivadas» section — stamps `archived_at` on the spec, never
  deletes the file) · `GET /shadow/:key` (render en sombra: la spec de un
  delta de fork — vía `fleet_delta` — renderizada full-page sin instalarla;
  la iframea el panel de la Revisión de deltas) · `GET /health`.
- **Datastar 1.0 — colon syntax** (NOT v0.x dashes): `data-on:click`,
  `data-on:submit__prevent`, `data-bind="signal"`, `@get`/`@post`. SSE event is
  `datastar-patch-elements` (see [viz/lib/sse.js](viz/lib/sse.js)). **Validate
  Datastar syntax against Context7** before changing attributes.

**Extending:** new data source → add an entry to `SOURCES` (script + allowed flags),
it shows up in the form's `<select>` automatically. The render code is layered as
the **composition tower** (see [docs/deltas-architecture.md](docs/deltas-architecture.md)):
kernel [viz/lib/kit.js](viz/lib/kit.js) (stable primitives — growing it is a
governance decision) → blocks [viz/blocks/](viz/blocks/) (fragments shared by 2+
pages or SSE-addressable: tasks-table, meetings-table, task-detail,
task-edit-form, meeting-detail, charts)
→ patterns [viz/patterns/](viz/patterns/) (`master-detail`, generalized to
slots: master = `{block, source, params?}` filled by a master-contract block
[signals/regetQS/controls/prepare?/table/counter — its filters are FIXED per
block], detail = `{block, frag?}` filled by a routed panel block whose
manifest declares `{slot:'detail', frag, width, selSignal}`; the pattern owns
all wiring — row-click → `/c/<detail>/frag/<frag>`, overlays, signals) → pages
[viz/pages/](viz/pages/). A saved spec can also be **v2 — pattern-addressed**:
`{spec_version: 2, pattern: "master-detail", master: {...}, detail: {...}}`
with blocks resolved by id from the registry; `validateSpec` checks the
pattern's slot contract (block exists, fills the right slot, consumes≅emits,
frag exists) and a v2 spec renders byte-identical to its page-instance twin. New component = one `viz/pages/<name>.js` exporting
`{id, render(ui), manifest}` — the manifest is the page's machine-checkable
contract: `{consumes: 'rows'|'object'` (must match the source's `emits` in
`SOURCES`), `overridable: [...]}` (exactly the query params the browser may
override — per-page, replacing any global whitelist). A block that owns SSE
fragments or write actions also registers: it exports `{id, frags, acts,
manifest: {writes: [scripts]}}` and is routed automatically under `/c/:id/...`;
`ctx.run()` throws on any script not declared in `writes` (the governance
rail — what gets approved when a component is elevated). The registry in
[viz/lib/components.js](viz/lib/components.js)
scans both dirs at startup (restart to pick it up) into one flat namespace
(collision = boot error); there is no central switch to edit. Current pages, keyed by `ui.component` (`table` with inferred columns, `dashboard` KPI cards,
`sop-tree` — a collapsible macro→SOP→archetype tree over the `sops` source,
`chart` — see below,
`localdb` — the local-SQLite explorer (see the Localdb domain),
`notion-tasks` — a read-only filterable table of one Notion project's BD
Avances tasks (fetched once — the source is cached — filtered in the browser), and
`tasks` — one task list with a filter bar (status/priority/project/assignee/due
window/open) that re-fetches via `@get` with query params; replaces the old
separate "abiertas"/"vencidas" UIs, since vencidas = `due=overdue` + `open`).
The `chart` component renders any tabular source as an interactive **bar/donut**
chart (line reserved for future time series): server block
[viz/blocks/charts.js](viz/blocks/charts.js) shapes rows into a compact spec
(picks columns, sorts by value, folds the donut tail into «Otros» at 6 segments)
and emits `<div data-chart='{spec}'><canvas></div>`; client glue
[viz/public/charts-init.js](viz/public/charts-init.js) instantiates the vendored
Chart.js over those placeholders on load AND after every SSE patch (a
MutationObserver survives idiomorph morphs) — the glue owns the house style
(validated CVD-safe categorical palette in slot order, single-series bars in ONE
color, thin marks, hairline grid). Every chart card ships a «ver tabla» toggle
(the accessible twin — required, not optional) and the standard loading overlay.
`kind`/`by` are overridable query params (whitelisted in `withParamOverrides`),
so the selectors re-fetch like every other filter bar. Seeded UIs: «Tareas por
estado» (donut) and «Tareas por proyecto» (bars), both over `task_stats`.
The Título/Vence column headers sort the list (click toggles asc/desc); `sort`/`dir`
are presentation-only params — applied in JS over the fetched rows, never passed
to the shell (`buildArgs` ignores non-whitelisted params).
The `tasks` pane is master-detail: clicking a row hits `GET /task/:id`, which
SSE-patches a `#task-detail` side panel (header + **Origen** provenance chip +
IO + acceptance criteria, view-only) from the `task_detail` source; `GET /task/`
(empty id) closes it. The `task_detail` object carries a `source` field
(`{type,url,external_id,meeting_id,meeting_name}`) → the chip links to Notion (↗)
or names the meeting.
The `meetings` component is a master-detail instance over team meetings
(master block `meetings-table`: filter bar project/status/solo-con-reporte;
detail block `meeting-detail`: report summary/objectives/decisions/blockers,
view-only, from the `meeting_detail` source).
The `task-editor` component is the **editable** twin of `tasks` (seeded as the
"Editor de IO" UI): same master list, but clicking a row hits `GET /task/:id/edit`,
which SSE-patches `#task-detail` with an editable IO-contract form (rename, retype
`io_type`/`artifact_type`, toggle required, add/remove inputs/outputs) built from
`task_detail` + `io_catalog`. Both `tasks` and `task-editor` are thin
instances of [viz/patterns/master-detail.js](viz/patterns/master-detail.js)
(same `tasks-table` master; different detail block); the read-only
`renderTaskDetail` is unchanged. **This is the viz's only write path:**
each control persists immediately via one `@post` (`POST /task/:tid/io/add` ·
`.../io/:ioId/field/:field?value=` · `.../io/:ioId/delete`) → `update_task_io.sh`
(one txn) → SSE re-render of the form. No SQL in the viz — writes go through the
whitelisted bash script, same policy as reads. Bound controls (`data-bind`) must
seed their signals via `data-signals` (current values) or Datastar blanks them.
**SQL Results bindings:** an IO row whose artifact is `sql_query` swaps the
generic "pegar enlace" input for a collapsible monospace textarea (the artifact's
instance IS a query, stored in the row's binding jsonb as `{query, params}`; the
chip titles itself from the query's first `--` comment line — see
[viz/lib/artifacts.js](viz/lib/artifacts.js)). Its signal is **local**
(`_`-prefixed → excluded by Datastar's default `filterSignals`) so large SQL
never rides along on other requests; "Guardar SQL" ships it explicitly as the
`@post` `payload` (→ `POST .../io/:ioId/sql` → `--ref-merge`). Two result
surfaces share the `io_query` source: **Probar** (`GET .../io/:ioId/sqlrun`)
patches a compact preview (first 20 rows + truncation hint) into the row, and
**Abrir como UI** (`POST .../io/:ioId/sqlui`) materializes the binding as a
saved generic-`table` UI (idempotent per IO row) — any SQL artifact is a latent
UI. Both only ever execute the **persisted** query, never textarea content.

**Loaders:** master-detail components (`tasks`, `meetings`) show *transparent
overlays* (`bg-white/50` + a spinner, with a `.2s` opacity transition) while data
loads — one over the table, driven by `data-indicator:<signal>` on the filter
controls (the `@get` re-fetch), and one over the `#detail-wrap` panel, driven by
`data-indicator:loading` on the row click (the `GET /<thing>/:id` SSE patch).
`selectCtl(...)` takes an `indicator` arg (default `loadingtasks`) for the table
signal. Any new UI with a re-fetch or an SSE detail panel must include both.

## Tasks data model (schema `ikigaigm`)

- **tasks** — core. `status` enum (`pending`,`in_progress`,`completed`,`blocked`,`cancelled`), `priority` enum (`Low`,`Medium`,`High`), `due_date`, `assignee` is `uuid[]`, `project_id`, `column_id`, `is_completed`.
- **task provenance** (migration 002): `source_type` (`meeting`|`notion`|`manual`|`other`), `source_meeting_id` (FK→meetings), `source_url` (external URL, e.g. Notion page — preferred), `source_external_id` (external stable id, e.g. Notion page id — for dedup/sync). Populated by `create_task.sh` (structured twin of the human provenance comment). Schema: [catalog/migrations/002_task_provenance.sql](catalog/migrations/002_task_provenance.sql).
- **assignee resolution**: `tasks.assignee[]` → `team_members.id` → `users.user_id` → `persons` (name); role via `team_roles`, team via `teams`. (Note: assignee UUIDs are team_members.id, **not** users.id.)
- **task_inputs** / **task_outputs** — requirements and deliverables; typed by `io_types` / `artifact_types`.
- **task_acceptance_criteria** — verification criteria per *output* (`verification_method`: `manual`/`attested`/auto). Linked by `output_id` → `task_outputs.id`.
- **task_attestations** — human (WhatsApp) confirmation of a criterion.
- **task_todos** / **task_comments** — checklist and comments per task.
- **task_columns** — kanban columns.
- **projects**: Andrea Torres, David Guerrero, Floppy, Ikigai.

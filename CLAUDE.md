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
| `io_types.sh` | List the semantic IO types (with default artifact type) usable in task contracts. |
| `io_catalog.sh` | One JSON object `{io_types[], artifact_types[]}` (with ids) — reference data for the viz IO editor's dropdowns. Read-only. |
| `update_task_io.sh --io <id> [--title T] [--io-type NAME] [--artifact NAME] [--required true\|false]` / `--add input\|output --task <id>` / `--delete --io <id> [--cascade]` **[WRITE]** | Edit one IO row of a task: retype its `io_type`/`artifact_type` (accepts id, name, or display_name), rename, toggle required, or add/remove rows. One op per call, one transaction, before/after, `--dry-run`, `--json` (emits `task_id` for re-render). Deleting an output with acceptance criteria is blocked unless `--cascade`. Powers the viz IO editor. |
| `create_task.sh <contract.json\|-> [--dry-run]` **[WRITE]** | Insert a full task "work contract" (task + inputs + outputs + acceptance criteria) from JSON. Pre-validates project/assignees/io_types; one transaction. Tags `archetype` (→SOP). **Template instantiation:** pass `archetype`+`slots` with no inputs/outputs to pull the archetype's template contract and substitute `{slots}`. See `-h`. |
| `set_archetype.sh <id> <archetype-id> [--method m] [--confidence X]` / `<id> --clear` **[WRITE]** | (Re)tag a task's activity archetype (the human/correction path; `create_task.sh` tags at birth). Validates the archetype; SOP/macro follow via the join. `--dry-run` to preview. |
| `cancel_task.sh <id> [--into <id>] [--reason "…"]` **[WRITE]** | Cancel a task (`status='cancelled'`), optionally recording a merge into another (`--into`) with an auditable comment trail on both. Nothing is deleted. `--dry-run` to preview. Use for dedup/merges (e.g. cross-project duplicates the per-project dedup misses). |
| `wipe_tasks.sh [--yes]` **[WRITE, IRREVERSIBLE]** | Delete the ENTIRE task domain (tasks + inputs + outputs + criteria + attestations + todos + comments) in one FK-safe transaction. Preserves `task_columns` and all FK parents. Safe by default: previews + rolls back unless `--yes`. Back up first (CSV snapshots in `backups/tasks-backup-<date>/`, restore via its `restore.sql`). |

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
(not the CDN — avoids CDN/CORS); `viz/public/` is the static-asset dir.

```bash
npm run viz                 # http://localhost:4317   (PORT=… overrides)
```

- **Data only flows through `bash/ --json`** — same read-only policy as everything
  else. The whitelist of allowed sources + their CLI flags lives in
  [viz/lib/datasources.js](viz/lib/datasources.js) (`SOURCES`): `tasks`, `tasks_due`,
  `projects`, `team`, `task_stats`, `meetings` (now also `from`/`to`/`has-report`),
  `meeting_detail` (one report OBJECT, from `meeting_show.sh --json`), `dashboard`,
  `sops`, `task_detail` (one task OBJECT) and `io_catalog` (`{io_types[],
  artifact_types[]}` for the IO editor). **Never** add SQL here. The one write
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
- **Creating a UI** = appending a record (a JSON file in `viz/store/`, git-ignored,
  re-seeded on first run). The user can also create one from the left-panel "Nueva
  UI" form. Programmatically: `store.create({name, component, source, params})` in
  [viz/lib/store.js](viz/lib/store.js).
- **Layout** is master-detail: left `#ui-list` (saved UIs + form), right `#pane`
  (selected UI). Datastar swaps fragments via SSE — no full reloads.
- **Routes**: `GET /` (shell, `?ui=<id>` opens one) · `GET /u/:id` (standalone page)
  · `GET /ui/:id` (SSE patch `#pane`) · `GET /task/:id` & `GET /meeting/:id` (SSE
  detail panels) · `GET /task/:id/edit` + `POST /task/:tid/io/...` (the IO editor —
  see below) · `GET /datastar.js` (vendored bundle) · `POST /ui` · `GET /health`.
- **Datastar 1.0 — colon syntax** (NOT v0.x dashes): `data-on:click`,
  `data-on:submit__prevent`, `data-bind="signal"`, `@get`/`@post`. SSE event is
  `datastar-patch-elements` (see [viz/lib/sse.js](viz/lib/sse.js)). **Validate
  Datastar syntax against Context7** before changing attributes.

**Extending:** new data source → add an entry to `SOURCES` (script + allowed flags),
it shows up in the form's `<select>` automatically. New component (form, cards,
stats-bar…) → another case in `renderPane()` in [viz/lib/components.js](viz/lib/components.js),
keyed by `ui.component` (`table` with inferred columns, `dashboard` KPI cards,
`sop-tree` — a collapsible macro→SOP→archetype tree over the `sops` source, and
`tasks` — one task list with a filter bar (status/priority/project/assignee/due
window/open) that re-fetches via `@get` with query params; replaces the old
separate "abiertas"/"vencidas" UIs, since vencidas = `due=overdue` + `open`).
The `tasks` pane is master-detail: clicking a row hits `GET /task/:id`, which
SSE-patches a `#task-detail` side panel (header + IO + acceptance criteria,
view-only) from the `task_detail` source; `GET /task/` (empty id) closes it.
The `meetings` component is the same master-detail shape over team meetings:
filter bar (project/status/solo-con-reporte) over the `meetings` source; clicking
a row hits `GET /meeting/:id`, which SSE-patches a `#meeting-detail` panel (report
summary/objectives/decisions/blockers, view-only) from the `meeting_detail` source.
The `task-editor` component is the **editable** twin of `tasks` (seeded as the
"Editor de IO" UI): same master list, but clicking a row hits `GET /task/:id/edit`,
which SSE-patches `#task-detail` with an editable IO-contract form (rename, retype
`io_type`/`artifact_type`, toggle required, add/remove inputs/outputs) built from
`task_detail` + `io_catalog`. Both share `tasksMasterDetail(ui, edit)`; the
read-only `renderTaskDetail` is unchanged. **This is the viz's only write path:**
each control persists immediately via one `@post` (`POST /task/:tid/io/add` ·
`.../io/:ioId/field/:field?value=` · `.../io/:ioId/delete`) → `update_task_io.sh`
(one txn) → SSE re-render of the form. No SQL in the viz — writes go through the
whitelisted bash script, same policy as reads. Bound controls (`data-bind`) must
seed their signals via `data-signals` (current values) or Datastar blanks them.

**Loaders:** master-detail components (`tasks`, `meetings`) show *transparent
overlays* (`bg-white/50` + a spinner, with a `.2s` opacity transition) while data
loads — one over the table, driven by `data-indicator:<signal>` on the filter
controls (the `@get` re-fetch), and one over the `#detail-wrap` panel, driven by
`data-indicator:loading` on the row click (the `GET /<thing>/:id` SSE patch).
`selectCtl(...)` takes an `indicator` arg (default `loadingtasks`) for the table
signal. Any new UI with a re-fetch or an SSE detail panel must include both.

## Tasks data model (schema `ikigaigm`)

- **tasks** — core. `status` enum (`pending`,`in_progress`,`completed`,`blocked`,`cancelled`), `priority` enum (`Low`,`Medium`,`High`), `due_date`, `assignee` is `uuid[]`, `project_id`, `column_id`, `is_completed`.
- **assignee resolution**: `tasks.assignee[]` → `team_members.id` → `users.user_id` → `persons` (name); role via `team_roles`, team via `teams`. (Note: assignee UUIDs are team_members.id, **not** users.id.)
- **task_inputs** / **task_outputs** — requirements and deliverables; typed by `io_types` / `artifact_types`.
- **task_acceptance_criteria** — verification criteria per *output* (`verification_method`: `manual`/`attested`/auto). Linked by `output_id` → `task_outputs.id`.
- **task_attestations** — human (WhatsApp) confirmation of a criterion.
- **task_todos** / **task_comments** — checklist and comments per task.
- **task_columns** — kanban columns.
- **projects**: Andrea Torres, David Guerrero, Floppy, Ikigai.

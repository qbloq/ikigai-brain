<!-- CLAUDE.md del CEREBRO DE IKIGAI — org ikigai, vertical agencia
     (cerebro.json). Byte-idéntico en todos los forks: la identidad se
     compone vía @identidad.md, jamás editando este archivo. -->

@identidad.md

- The DB connection string is DATABASE_URL in .env
- We only use the ´ikigaigm´ schema
- Git lineage: `upstream` = el repo del que este nació — sus updates se integran con **merge** en el cerebro (los forks, en cambio, rebasean sus deltas encima); `origin` = el remoto de trabajo propio. Los remotos concretos: `git remote -v`.

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
| `cancel_task.sh <id> [--into <id>] [--reason "…"]` **[WRITE]** | Cancel a task (`status='cancelled'`), optionally recording a merge into another (`--into`) with an auditable comment trail on both. Nothing is deleted. `--dry-run` to preview. Use for dedup/merges (e.g. cross-project duplicates the per-project dedup misses). |
| `complete_task.sh <id> [<id>…] [--at YYYY-MM-DD] [--note "…"] [--author N]` **[WRITE]** | Mark tasks DONE (`status='completed'` + `is_completed`), with a comment trail. The twin of `cancel_task.sh` — **do not confuse them**: `completed` = the work happened, `cancelled` = it never will; mixing them corrupts every compliance metric. **`--at` is what makes it honest**: without it the migration-003 trigger seals `completed_at` with `now()`, which lies for anything executed weeks ago (an explicit value survives the trigger). Already-completed tasks are skipped, not rewritten — re-running never moves a date or duplicates a comment. `--dry-run` to preview. |

**Skill — IO review session:**
- `revisar-tarea-io` ([.claude/skills/revisar-tarea-io/](.claude/skills/revisar-tarea-io/SKILL.md)):
  `/revisar-tarea-io <task-id>` — interactive review/edit of ONE task's IO
  contract with the user: renders `task_detail.sh` + `io_catalog.sh`, then maps
  each request to a single `update_task_io.sh` call (the CLI twin of the viz
  "Editor de IO"). Criteria editing is out of scope (no write script yet).

### Tasks data model (schema `ikigaigm`)

- **tasks** — core. `status` enum (`pending`,`in_progress`,`completed`,`blocked`,`cancelled`), `priority` enum (`Low`,`Medium`,`High`), `due_date`, `assignee` is `uuid[]`, `project_id`, `column_id`, `is_completed`.
- **completion instant** (migration 003): `tasks.completed_at`, sealed by trigger
  on the *transition* into completed and cleared if the task is reopened; an
  explicitly supplied value is never overwritten. It exists because neither
  `created_at` (294 tasks share the Notion-import date) nor `updated_at` (two
  bulk-sync stamps) can measure rhythm. **Deliberately not backfilled** — every
  rhythm metric is defined over `completed_at IS NOT NULL` only, so the series
  starts 2026-07-27 instead of inventing a past. Written by `complete_task.sh`.
  Schema: `catalog/migrations/003_task_completed_at.sql`.
- **task provenance** (migration 002): `source_type` (`meeting`|`notion`|`manual`|`other`), `source_meeting_id` (FK→meetings), `source_url` (external URL, e.g. Notion page — preferred), `source_external_id` (external stable id, e.g. Notion page id — for dedup/sync). Populated by `create_task.sh` (structured twin of the human provenance comment). Schema: `catalog/migrations/002_task_provenance.sql`.
- **assignee resolution**: `tasks.assignee[]` → `team_members.id` → `users.user_id` → `persons` (name); role via `team_roles`, team via `teams`. (Note: assignee UUIDs are team_members.id, **not** users.id.)
- **task_inputs** / **task_outputs** — requirements and deliverables; typed by `io_types` / `artifact_types`.
- **task_acceptance_criteria** — verification criteria per *output* (`verification_method`: `manual`/`attested`/auto). Linked by `output_id` → `task_outputs.id`.
- **task_attestations** — human (WhatsApp) confirmation of a criterion.
- **task_todos** / **task_comments** — checklist and comments per task.
- **task_columns** — kanban columns.
- **projects**: Andrea Torres, David Guerrero, Floppy, Ikigai.

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
| `lead_profile.sh [--by base\|arquetipo\|tramo\|prioridad\|closer\|resultado] [--project N] [--closer N] [--arquetipo F] [--from D] [--to D] [--incluir-sin-analizar] [--limit N]` | The **lead profile** already inside each report (`leadProfile.bantAnalysis` + `intelligentSegmentation`), extracted and normalized. Without `--by`: one row per call with BANT in 0-100 **and** in the 1-5 scale per item. Carries three declared normalizations, all of which change the numbers — see below. |

⚠️ **Three normalizations that `lead_profile.sh` declares and the rest of the
calls domain does not** — they are not cosmetic, each moves the numbers:

1. **Sin analizar ≠ mal calificado.** 66 of 230 reports carry all four BANT
   scores at literal zero — calls with no usable transcript, not bad leads.
   Excluded by default (`--incluir-sin-analizar` brings them back). Any average
   that includes them understates everything.
2. **Archetype is free text**: 43 canonical labels for what are really **four
   traits** (Novato · Emocional · Inexperto · Experimentado) plus qualifiers.
   `--by base` collapses to the traits and their combinations; `--by arquetipo`
   keeps the qualifier.
3. **`callStatus` is free text too**: 131 distinct values for 230 calls.
   `call_stats.sh` counts wins with `ILIKE 'closed won%'` and therefore **misses**
   `Closed/Won`, `Closed - Payment Initiated`, `Cerrado Pendiente Pago` — its win
   rate is undercounted. `lead_profile.sh` classifies into 7 buckets, strongest
   signal first, and counts `ganada`+`compromiso` as conversion (the real close
   is sealed by the first installment, days after the call). Still a heuristic:
   **the truth about money lives in `installments`**, not in `callStatus`.

Result of all three: BANT **does** discriminate — the 81-100 band converts
**38.9%** against **3.2%** for 61-80.

Viz sources: `calls`, `call_detail` (object), `call_stats`, `call_objections`.

## Ads domain — Meta pauta ([bash/ads/](bash/ads/))

The paid-media view (S3 — the Media Buyer gap the Ejecutivo role absorbs).
Source tables: `campaigns`/`ad_sets`/`ads` (structure), `ad_insights_daily`
(daily performance, ad granularity — campaign totals reconcile with
`campaign_insights_daily`, so it's the single source used). Project is resolved
via `project_ad_account_mappings` (account→project). **Currencies coexist**
(Andrea/Floppy = COP, David Guerrero = USD): every row carries `cur` and
groupings split per currency — never sum across. Ratios (CTR/CPC/CPM/ROAS/CPA)
are recomputed from summed columns, never averaged from daily ratios. Budgets
are already in currency units (not cents). Default window: current month
(Bogota). Insights sync can lag a few days — `last_data` shows freshness.

| Script | Use it to… |
|--------|-----------|
| `campaigns.sh [--status S] [--active] [--project N] [--account ID] [--from D] [--to D] [--with-spend] [--limit N]` | List campaigns with project, currency, status, daily budget, window spend/purchases/ROAS and `last_data`. Ordered by spend. |
| `ad_stats.sh [--by campaign\|adset\|ad\|day\|week\|project\|account] [--project N] [--account ID] [--campaign TOK] [--from D] [--to D] [--limit N]` | Aggregate performance: spend, impressions, clicks, CTR, CPC, CPM, LPV, purchases, purchase value, ROAS, CPA. `--campaign` (id prefix or name fragment) pairs with `--by adset`/`--by ad`. |
| `ad_detail.sh <campaign-id\|prefix\|name> [--from D] [--to D] [--days N]` | One campaign end-to-end: header (account/project/budget), window totals, per-adset breakdown, top-15 ads by spend, daily series (last N days with data, default 14). `--json` = one object `{campaign, totals, adsets[], ads[], daily[]}` (window default: whole life). |

Known data caveat: Meta-reported `purchase_value` on the Andrea (COP) account
has junk magnitudes (~663M COP for 4 purchases in June) — treat COP ROAS as
unreliable until the pixel currency is fixed; cash truth lives in
`installments`/`economics_ledger`.

Viz sources: `ad_campaigns`, `ad_stats`, `ad_detail` (object).

## CRM domain — GHL pipeline ([bash/crm/](bash/crm/))

Opportunities/pipelines synced from GHL: `crm_opportunities` (~2.1k) against
`crm_pipelines` (stage names + board order live in the `stages` jsonb, keyed by
`ghl_stage_id`). Two active pipelines: NEW CRM TEST (David Guerrero) and
ALQUIMIA CRM (Andrea Torres). **Caveat:** open opportunities carry
`monetary_value` ≈ 0 — counts are meaningful, forecast value is not; `won`
value IS real. Closer resolves via `o.user_id`→users→persons.

⚠️ **The mirror is SCOPED, and it drifts.** Verified against the source on
2026-08-04 (`bash/ghl/gap.sh`, `bash/ghl/opportunities.sh`):

- **Scope is one pipeline per project** — the rows in `crm_pipelines`. GHL holds
  12 pipelines for David Guerrero and 5 for Andrea; only NEW CRM TEST and
  ALQUIMIA CRM are ingested. That is mostly *correct*: of the other pipelines
  only **LOW TICKET** (David) still receives opportunities, and it went quiet in
  July. The rest are historical. Whole-CRM totals therefore overstate the gap —
  always compare within the mirrored pipeline.
- **It drifts because the ingestor pages at 100 per run and is fired by hand.**
  `crm_contacts.created_at` shows runs of exactly 100 (04-ago, 23-jul, 14-jul,
  29-jun, 29-may); when more than ~10 days pass, the excess is dropped silently.
  July 2026 (the heaviest month) lost 202 of 552 opportunities that way. Repair
  the gap backwards with `node scripts/backfill-ghl.js` **[WRITE]**; the ingestor
  itself is not fixed by it.
- **`crm_contacts` is a by-product of opportunity ingestion**, not a contact
  mirror: contacts and opportunities sit ~1:1 in the DB, ~1.6:1 in GHL. A call
  whose booking points at a contact with no opportunity cannot resolve its
  closer — that is the residual ~14% (`bash/calls/`). Of the calls that still
  fail, most reference contacts that no longer exist in GHL at all.
- **`crm_contacts.created_at` is the INGESTION timestamp** (no GHL creation date
  is stored), so contact cohorts measure our ingestion, not the business.
  `crm_opportunities.created_date` IS the real one.

State after the 2026-08-04 backfill: the mirrored pipeline is complete for
May–August (1086/1086 for David), closer resolution is 86% (195/226 analyzed
calls), and ~237 opportunities/contacts were recovered. Opportunities with no
`user_id` (237 in July alone) are a real ownership gap in GHL, not an ingestion
artifact.

| Script | Use it to… |
|--------|-----------|
| `pipeline.sh [--by stage\|status\|month\|closer] [--list] [--project N] [--status S] [--stage FRAG] [--from D] [--to D] [--limit N]` | Default `--by stage`: the pipeline board in order with open/won/lost/abandoned counts + won value per stage. `--by month` = cohorts (created, won, win %, won value). `--by closer` = per-closer effectiveness by opp (complements `call_stats.sh`, which is per-call). `--list` = raw opportunity rows (lead, stage, status, value, assigned). |
| `leads.sh [--dueno LISTA] [--sin-dueno] [--project N] [--stage FRAG] [--from D] [--to D] [--dias-min N] [--pagado\|--organico] [--limit N]` | The leads as ROWS, with owner **and attribution**: resolves `utm_source`/`utm_campaign` from the contact's `custom_fields` against `crm_custom_fields`, so each row says whether the lead came from paid media (and which campaign) or an organic form. `--dueno` takes a comma list of name fragments plus the token `sin-dueno` for the orphans. Supersedes `pipeline.sh --list`. |
| `opp_detail.sh <id\|prefix>` | One opportunity + its contact as a single JSON object, with the GHL custom fields resolved to their question — the qualification survey the lead answered plus the `utm_*`. Feeds the viz detail panel. |
| `facets.sh [--project N] [--from D]` | The universe of owners and stages with counts (`{tipo,valor,n}`) — reference data that populates the leads filters. Kept separate on purpose: derived from already-filtered rows, a filter's options would close in on themselves. |

## GHL domain — el CRM en la fuente ([bash/ghl/](bash/ghl/))

**Read-only** access to the GoHighLevel API v2, direct. Exists to **measure the
mirror against the source** — it is a probe, not a second ingestion path
(nothing here writes, to GHL or to the DB). Credentials are the org's GHL
Private Integration Tokens, which live in `project_crm_configs` **in
plaintext** (despite the column name `api_key_encrypted`), so the layer is
fenced: it **refuses to run inside a copilot fork**, only GETs, and hands the
token to curl over stdin so it never reaches `argv`. Moving the credentials
behind the backend (the `bash/google/` pattern) is the right end state.

| Script | Use it to… |
|--------|-----------|
| `auth_status.sh` | Which projects have an integration and whether it answers — live probe with GHL's own contact/opportunity totals. |
| `gap.sh [--project N] [--ids]` | **The coverage report**: GHL vs the DB per project. `--ids` walks the full pagination and counts the opportunities actually missing. |
| `contacts.sh --project N [--limit N] [--id ID] [--missing]` | Contacts from the source. `--id` answers "does this contact exist upstream?" when a call won't resolve its closer; `--missing` lists what the mirror lacks. |
| `opportunities.sh --project N [--limit N] [--status S] [--missing]` | Opportunities from the source, same flags. |

`--limit 0` pages to the end (via `meta.startAfterId`). The API paginates fine
— 495/495 for Andrea — so the **100-record cap is the ingestor's**, not GHL's:
`crm_contacts.created_at` shows runs of exactly 100 (04-ago, 23-jul, 14-jul,
29-jun, 29-may). Findings and the credentials policy: [bash/ghl/README.md](bash/ghl/README.md).

Viz sources: `crm_pipeline`, `crm_leads`, `crm_opp_detail` (object), `crm_facets`
(cached 60s). The **Leads** UI (Director Comercial layer) is master-detail over
them, and is built on a UX rule worth keeping: *a table with filters can express
any query, and precisely for that reason it proposes nothing* — so it opens with
**named views** («Sin dueño», «Pagados sin dueño», «Sin dueño y fríos»,
«Estancados en NUEVO LEAD», «Todos»), and the filters stay for what those don't
anticipate. The **Ejecutivo role layer**
([viz/specs/roles/ejecutivo/](viz/specs/roles/ejecutivo/), 9 UIs) covers all
three domains: portafolio, pauta (campañas + line chart de gasto diario),
cobranza (vencidas + aging), comisiones (cola de aprobación), cashflow y
pipeline CRM (tablero + donut por estado).

## Notion domain — read-only extraction ([bash/notion/](bash/notion/))

Pull Notion content to local via the HTTP API (curl/python3 stdlib, no npm deps;
token `NOTION=ntn_…` in `.env`, integration "Parallelo 2"). **Read-only** — never
creates/edits in Notion. Prefer these scripts over Notion MCP; distill results to `docs/`.
`fetch_page.sh <id|url> [--out F] [--blocks|--raw|--db|--search]` distills a page
to Markdown (`--search` lists everything shared with the bot);
`project_tasks.sh <project-page-id|url>` extracts all **BD Avances** tasks whose
`Proyectos brief` relation points to that project. Gotchas (data-source model,
linked views that report `data_sources: []`) in [bash/notion/README.md](bash/notion/README.md).

## Google domain — Drive vía el API mkt ([bash/google/](bash/google/))

**Read-only** access to the org's Drive through the **Meetico backend**
(contract: `apis/mkt/drive.openapi.json`) — the
backend owns the Google identity (token, refresh, index); these scripts never
see Google credentials and never touch the DB. Mode picked from `.env`:
**copiloto** (`CEREBRO_API`+`CEREBRO_TOKEN` → forja-proxy `/v1/mkt/…`, audited
per employee) or **cerebro** (`MEETICO_BASE`+`MEETICO_JWT_TOKEN`, direct — the
same pair the viz uses for IO binding). All scripts take raw ids or docs/drive
URLs and accept `--json`. Endpoints not yet deployed by the backend fail with
a clear «el backend aún no expone …» message. See [bash/google/README.md](bash/google/README.md).

| Script | Use it to… |
|--------|-----------|
| `auth_status.sh` | Mode, base and a live probe against the backend. |
| `drive_ls.sh [--folder ID\|url\|name] [--q FRAG] [--type doc\|sheet\|slide\|folder\|pdf] [--limit N]` | List a folder live (`/drive/contents`) or search the whole drive (index). |
| `drive_recent.sh [--days N] [--from D] [--to D] [--modified] [--docs] [--type T] [--folder FRAG] [--owner FRAG] [--exclude FRAG] [--with-folders] [--by day\|type\|owner\|folder] [--limit N]` | What **entered or changed** lately, newest first — the index has no other way to be asked "what's new". Always prints the index's freshness to stderr and shouts past 48h, because the index is a hand-refreshed cache and a stale one answers "what came in this week?" with silence. Needs the 2026-08-04 backend change (date filters + `sort` + `/drive/index/status`); refuses to run without it. |
| `drive_file.sh <id\|url>` | Metadata of one file. |
| `doc_read.sh <id\|url> [--out F] [--txt]` | A Google Doc as **Markdown** (`?format=markdown`). `--out` writes a file. |
| `sheet_show.sh <id\|url>` | Sheet metadata (tabs not exposed by the backend yet). |
| `sheet_read.sh <id\|url> [--limit N] [--raw]` | First tab's values as an aligned table (CSV; row 1 = header); `--json` = array of objects. |

## Metrics domain ([bash/metrics/](bash/metrics/))

`dashboard.sh [--project NAME] [--from D] [--to D] [--json]` — financial KPI set
for one project/period (cash-collected model: ingresos brutos, venta programas,
pauta, costos, reparto). Read-only; feeds the viz `dashboard` source (emits one object).

## Finance domain — owner's view ([bash/finance/](bash/finance/))

The CEO/COO money layer over `payment_plans`/`installments` (cash),
`commission_payouts`, `expenses` and `economics_ledger`. **Everything is USD**
(plans, payouts, ledger) — only ad spend mixes currencies, so `portfolio.sh`
splits `pauta_usd`/`pauta_cop` and subtracts only USD from profit. Formulas
mirror `bash/metrics/dashboard.sh` (the verified cash-collected KPI model).

| Script | Use it to… |
|--------|-----------|
| `portfolio.sh [--from D] [--to D]` | The dashboard KPIs for ALL projects side by side + TOTAL row: nuevas/cuotas, ingresos, venta programas, comisiones, gastos, ingreso neto, pauta (USD/COP apart), profit, margen %, ROAS real (cash/pauta), leads, CPL. Default: current month. |
| `cobranza.sh [--overdue] [--upcoming N] [--project N] [--customer FRAG] [--summary] [--all] [--limit N]` | Uncollected installments (Scheduled/Partial/Overdue) with days overdue + aging bucket, computed from `due_date` (the `Overdue` status flag is NOT maintained). `--summary` = aging buckets per project (counts + amounts). |
| `comisiones.sh [--status S] [--person FRAG] [--project N] [--from D] [--to D] [--by status\|person\|project\|month] [--limit N]` | Commission payouts with person resolved (user→persons, contractor fallback) and review state — the approval queue (pending→approved→paid). Row list puts pending first; `--by` aggregates with pending counts/amounts. |
| `cashflow.sh [--by month\|type\|month-type] [--project N] [--from D] [--to D]` | Economics ledger: entradas (revenue) vs opex/comisiones/reparto and neto, by month (default), type, or month×type. |

Data caveats: ~46 unpaid installments hang off plans with NULL `project_id`
(show as project `—` — hygiene queue); ledger history starts 2026-03.

Viz sources: `portfolio`, `cobranza`, `comisiones`, `cashflow`.

## Catalog domain — process ontology (`catalog/`, [bash/catalog/](bash/catalog/))

The org's process ontology, mapped from the start so every task is born tagged.
**Three process tiers** (per `docs/role-sops-discovery.md`):

```
value chain → macro_process (S1…S12) → sop (Sx.y) → activity archetype (A_.__) → task
```
S1–S10 are **macro-processes** (§1 spine); each is broken into canonical **SOPs**
(deduped from §2 per-role candidates); each SOP groups **archetypes** (activities);
a task instantiates an archetype. A task rolls up archetype → sop → macro.

- **`catalog/sop-archetypes.json`** — canonical source
  of truth: 12 macro-processes (S1–S10 + S11 Producto / S12 Cierre-Retención, born
  as gaps and filled by the Mastermind pilot), 36 SOPs, 77 archetypes
  `{id, sop, verb, name, slots[]}`. Every SOP has ≥1 archetype.
- **DB tables** (`ikigaigm`, seeded from the JSON): `macro_processes`, `sops`
  (→macro_processes), `activity_archetypes` (→sops, +`embedding extensions.vector(1536)`
  for the future matcher), `archetype_params`, and the template-contract tables
  `archetype_inputs`/`archetype_outputs`/`archetype_acceptance_criteria` (an
  archetype = a task template with declared I/O+criteria; **59 of the 77 archetypes
  already carry one** — S5 Testimonios was the first authored, the Mastermind pilot
  wrote the rest; the 18 without a template are listed in the meeting-to-tasks
  skill). Template contracts are declared in the catalog JSON per archetype and
  seeded by `sync_catalog.sh`. ⚠️ `create_task.sh` leaves **unfilled `{slots}`
  literal** (unlike `materialize_io.sh`, which neutralizes them) — always pass
  `slots`, including `proyecto`.
- **`tasks.archetype_id`** (FK→activity_archetypes) + `archetype_confidence` +
  `archetype_match_method` (`rule|embedding|llm|human`): instance → template link.
  The SOP/macro are reached by joining through `activity_archetypes`→`sops`.
- `bash/catalog/sops.sh [--macro CODE] [--json]` — **read-only** listing of the
  ontology: one row per archetype (SOP + macro-process + task count). Feeds the
  viz `sop-tree` UI for navigating SOPs with their activities.
- `bash/graph/ontology_stats.sh [--json] [--no-db]` — health + findings of the
  **ontology itself**, over the built graph artifacts in `docs/graph/`
  (not the DB: the graph is a *curated* artifact about it). Feeds the viz
  `ontologia` source / `ontology` dashboard. Rebuilding the graph refreshes it;
  the freshness bar reports build dates + drift vs the live DB. The graph has two
  layers — **dato** (98 entidades, FKs+reglas) and **negocio** (cadena de valor →
  macro → SOP → arquetipo), each with `graph.json`/`business.json`, a validated
  `.ttl` and a self-contained viewer built by `build_viewer.py --profile`.
- **Schema of record:** `catalog/migrations/001_process_ontology.sql`
  — the documented, idempotent DDL for all tables/columns added (the 7 tables above
  + the 3 `tasks.archetype_*` columns). DDL only; seeding is `sync_catalog.sh`'s job.

**Where it plugs in:** `create_task.sh` persists the tag at birth. Matching is manual now; the path to automatic is rule → pgvector
embedding → LLM judge (thresholds: ≥0.85 auto · 0.6–0.85 confirm · <0.6 new
candidate), growing the catalog from the tail. Rollup example:
`SELECT mp.code, count(*) FROM tasks t JOIN activity_archetypes a ON a.id=t.archetype_id JOIN sops s ON s.code=a.sop_code JOIN macro_processes mp ON mp.code=s.macro_process_code GROUP BY mp.code`.

## Localdb domain — local SQLite databases ([bash/localdb/](bash/localdb/))

The user's OWN local databases — the **personal data layer** of
`docs/deltas-architecture.md`: prototype schemas
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

## Forks — copilotos

Each employee's copilot is a git FORK of this repo (configured with
`pull.rebase=true`, so its deltas always sit on top of the brain) whose
identity is a `copilot.json` at the root (`{employee, team_member_id, role}`)
plus its agent-readable twin `identidad.md` (written at birth from
`plantillas/identidad-copiloto/`; it imports `docs/roles/<rol>.md`). The
CLAUDE.md stays byte-identical across brain and forks — it composes identity
via `@identidad.md`, never by assembling a per-fork copy. The viz store loads
ONLY that role's spec layer and stamps `owner`/`role` on everything created.
The brain (no copilot.json) sees org + all roles.
Everything a copilot writes lands in `viz/specs/local/` and auto-commits —
git IS the telemetry; structure is observed, content never. Structural
changes propose themselves by push; governance reviews and, when approved,
promotes a spec into `org/` or `roles/<rol>/` with `promoted_from` lineage.
Each fork's own CLAUDE.md/copilot.json belongs to that copilot — never edit
them from the brain.

## On-demand UIs — viz server ([viz/](viz/))

When the user asks to **"crear una UI"** (a table/dashboard/visualization), this
is the system to use — **do not** hand-write a one-off HTML file. A "UI" is a
persisted *spec* (`{id, name, component, source, params}`), not frozen markup,
so it always re-renders from live data. Node stdlib, **zero npm deps**;
TailwindCSS (Play CDN) + **Datastar 1.0** (vendored) over **SSE**.

```bash
npm run viz                 # http://localhost:4317   (PORT=… overrides)
npm run viz:restart         # REQUIRED after editing viz/ (Node caches modules)
```

- **Tema — la identidad visual de la org**
  (`docs/ui-theming/README.md`; la fuente de diseño es
  `docs/ui-theming/ikigai-design-system.html`,
  se lee en el navegador). Un tema son **10 hex + tipografía** en `tema.json` a
  la raíz del repo; de ahí [viz/lib/theme.js](viz/lib/theme.js) emite
  `:root{--pal-*}` y [viz/public/tokens.css](viz/public/tokens.css) deriva con
  `color-mix()` los ~90 semánticos, el tema oscuro, las rampas y ~130 clases de
  componente (`.btn`, `.card`, `.kpi`, `.tbl`, `.badge`, `.check`…). **Regla de
  oro: los componentes jamás consumen `--pal-*`, solo los semánticos.** Editar
  `tema.json` no pide reinicio (se lee por request). Claro/oscuro es preferencia
  del usuario (`localStorage` `viz-modo`, botón «◐»), no del tema.
  [viz/public/tw-bridge.js](viz/public/tw-bridge.js) es el puente: el viz usaba
  sus ~700 clases de color Tailwind semánticamente (slate=neutral,
  indigo/blue/sky/violet=marca, red=negativo, emerald=positivo, amber=precaución,
  pink=acento), así que redefine esas familias sobre las rampas de tokens.css —
  todo lo no portado se tematiza igual, y gana modo oscuro porque las rampas
  invierten sus polos bajo `[data-theme="dark"]`. Sora + JetBrains Mono van
  **vendorizadas** en `viz/public/fonts/` (variables, ~104 KB).

- **Data only flows through `bash/ --json`** — same read-only policy as
  everything else. The whitelist of sources + their CLI flags is `SOURCES` in
  [viz/lib/datasources.js](viz/lib/datasources.js); each domain section above
  names its viz sources. **Never** add SQL to the viz — the one write path (the
  IO editor) also shells out to a whitelisted bash script.
- **The spec store is LAYERED** ([viz/lib/store.js](viz/lib/store.js)):
  `viz/specs/org/` (shared genome, in git — seeds live here) →
  `roles/<rol>/` → `local/` (the ONLY writable layer). Editing/archiving an
  org/role spec forks it into local with `derived_from` lineage; every local
  write auto-commits (`Delta-Type`/`Delta-Scope` trailers) — git is the delta
  event log. Programmatically: `store.create({name, component, source, params})`.
- Render code is layered as the **composition tower**
  (`docs/deltas-architecture.md`): kernel
  [viz/lib/kit.js](viz/lib/kit.js) → blocks → patterns (`master-detail`) →
  pages (one per `ui.component`); a saved spec can also be v2 pattern-addressed.
  Components: `table`, `dashboard`, `chart` (bar/donut), `sop-tree`, `localdb`,
  `notion-tasks`, `tasks`, `meetings`, `task-editor` (the IO editor — the viz's
  only write path).

**Operating rules** (Datastar colon syntax, caching policy, manifest contracts,
required loaders, store details) live in [viz/CLAUDE.md](viz/CLAUDE.md) —
auto-loaded when working under `viz/`. Architecture narrative + component
catalog: [viz/README.md](viz/README.md).


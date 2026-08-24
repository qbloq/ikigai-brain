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
| `update_task_criteria.sh --crit <id\|prefix> [--text T] [--method llm\|manual\|automated\|test\|attested] [--required true\|false] [--category C]` / `--add --output <id> --text T` / `--delete --crit <id> [--cascade]` **[WRITE]** | Edit the acceptance criteria of an output — the other half of the work contract. Twin of `update_task_io.sh`: one op per call, one txn, before/after, `--dry-run`, `--json` (emits `task_id`). Ids resolve by **prefix** (ambiguous = error) because this one is driven from the conversation, not the viz. A criterion hangs off an **output** (`output_id`), never off the task. Deleting one that already has attestations is blocked without `--cascade` — cascading erases the human's evidence. ⚠️ `is_met`/`verified_*` are **not** editable here: verification state is earned by attestation, never typed. |
| `run_io_query.sh <io_id\|prefix> [--limit N] [--json]` | Execute the SQL persisted in one IO row's binding (`reference.query`) and print the result — the concrete data of a `sql_query` artifact (its sql resolver). Read-only + `statement_timeout=10s` + row cap (default 500). Only runs SQL with provenance (already persisted in the DB row); accepts nothing inline. Feeds the viz `io_query` source. |
| `create_task.sh <contract.json\|-> [--dry-run]` **[WRITE]** | Insert a full task "work contract" (task + inputs + outputs + acceptance criteria) from JSON. Pre-validates project/assignees/io_types; one transaction. Tags `archetype` (→SOP). **Template instantiation:** pass `archetype`+`slots` with no inputs/outputs to pull the archetype's template contract and substitute `{slots}`. **Provenance:** `source_meeting` (id/prefix→FK), `source_url`/`source_external_id` (Notion), `source_type` (auto-inferred) populate the tasks provenance columns. See `-h`. |
| `apply_contract.sh <id\|prefix> <contract.json\|-> [--dry-run] [--json]` **[WRITE]** | Aplicar un contrato IO (inputs + outputs + criterios + tag de arquetipo) a una tarea que **ya existe y no tiene ninguno** — el gemelo de `create_task.sh` para las tareas nacidas sin contrato (hoy: las 53 que entraron desde la plataforma PM, `source_type='other'` + `source_external_id`). Misma forma de contrato que `create_task.sh` sin la cabecera; `archetype`+`slots` sin inputs/outputs instancia la plantilla del arquetipo, y un `{slot}` sin valor queda **literal** (nombra lo que falta; el «pendiente» de `materialize_io.sh` lo pierde — brief de slots §6.2). `{proyecto}` se llena solo con el proyecto de la tarea. Se niega si la tarea ya tiene IO (rellena el hueco, nunca reescribe: eso es `materialize_io.sh --replace`). Una txn, before/after, deja comentario de rastro. Nació 2026-08-21 para el backfill de las tareas PM (`docs/io-backfill-pm-2026-08-21.md`). |
| `set_archetype.sh <id> <archetype-id> [--method m] [--confidence X]` / `<id> --clear` **[WRITE]** | (Re)tag a task's activity archetype (the human/correction path; `create_task.sh` tags at birth). Validates the archetype; SOP/macro follow via the join. `--dry-run` to preview. ⚠️ **Re-tagging moves the pointer, it does NOT rewrite the task's IO contract** — the inputs/outputs/criteria stay exactly as the OLD template left them, so a re-tagged task keeps criteria describing a different activity until its contract is re-instantiated. |
| `link_external.sh <id> --external <id-ext> [--url URL] [--sistema N] [--nota "…"] [--dry-run] [--json]` **[WRITE]** | **Vincular sin fusionar** — el tercer desenlace que le faltaba al cruce. Escribe `source_external_id` (+`source_url`) sobre una tarea que YA existe: dos tareas que describen el mismo trabajo, cada una nacida en su sistema, donde no hay nada que fusionar porque la del cerebro ya está completa. Hasta 2026-08-20 eso solo cabía en prosa (`cruce.resolucion` o un comentario), y la prosa no la lee ningún chequeo: **13 tareas abiertas en PM figuraban como «sin representación»** estando todas cubiertas. ⚠️ **No toca `source_type`**: eso dice dónde NACIÓ la tarea, no con qué sistema sincroniza — una nacida de un acta y emparejada con PM sigue siendo `meeting`. Se niega si la tarea ya tiene otro id externo (una columna no es una lista: el caso muchos-a-uno pide tabla de enlaces) o si el id ya está en otra tarea **viva** (una cancelada lo conserva como procedencia y no bloquea). Re-vincular al mismo valor es idempotente. |
| `cancel_task.sh <id> [--into <id>] [--reason "…"]` **[WRITE]** | Cancel a task (`status='cancelled'`), optionally recording a merge into another (`--into`) with an auditable comment trail on both. Nothing is deleted. `--dry-run` to preview. Use for dedup/merges (e.g. cross-project duplicates the per-project dedup misses). |
| `complete_task.sh <id> [<id>…] [--at YYYY-MM-DD \| --sin-fecha] [--note "…"] [--author N]` **[WRITE]** | Mark tasks DONE (`status='completed'` + `is_completed`), with a comment trail. The twin of `cancel_task.sh` — **do not confuse them**: `completed` = the work happened, `cancelled` = it never will; mixing them corrupts every compliance metric. **`--at` is what makes it honest**: without it the migration-003 trigger seals `completed_at` with `now()`, which lies for anything executed weeks ago (an explicit value survives the trigger). **`--sin-fecha`** is the third case — *it happened, we don't know when*: it undoes the trigger's seal leaving `completed_at` NULL, so the task counts as done and stays out of the tempo series (rhythm metrics are defined over `completed_at IS NOT NULL`). Not a corner case — the PM platform leaves 41 of its 116 closures with no `completada_en`; same criterion `merge_from_cruce.sh` already applied. Mutually exclusive with `--at`. Already-completed tasks are skipped, not rewritten — re-running never moves a date or duplicates a comment. `--dry-run` to preview. |
| `start_task.sh <id> [<id>…] [--note "…"] [--author N] [--reabrir]` **[WRITE]** | Put tasks IN PROGRESS (`status='in_progress'`), with a comment trail. The third state, the one that was missing: `complete`/`cancel` are terminal, this one says *being worked on* — without it a task under active work and one parked for three months both read `pending`, and a queue can't be read. Tasks already in progress are skipped, not rewritten. **Closed tasks are refused unless `--reabrir`**: leaving `completed` makes the migration-003 trigger *erase* `completed_at`, and the date does not come back. `--dry-run` to preview. |
| `merge_from_cruce.sh [--n LIST] [--contrato plantilla\|copia] [--dry-run]` **[WRITE]** | Execute the curated merges of the PM↔cerebro cruce (rows with `merge=1` in the local sqlite `pm_platform.cruce`, marked from the viz `cruce` UI). Per pair, ONE txn: duplicate the cerebro task with the **PM platform's title** (contract re-instantiated from the archetype template with `{proyecto}` filled + slots neutralized, or `--contrato copia` cloning the live contract with verification state reset), copy comments/todos (timestamps kept) + provenance comments, resolve status (completed if either side is; `completed_at` = Mari's date or **NULL, never an invented now()** — the script un-does the 003 trigger's seal), record PM identity (`source_external_id` = PM uuid), cancel the original into the duplicate, stamp the sqlite row `resuelta`. |

**Skill — contract review session:**
- `revisar-tarea-io` ([.claude/skills/revisar-tarea-io/](.claude/skills/revisar-tarea-io/SKILL.md)):
  `/revisar-tarea-io <task-id>` — interactive review/edit of ONE task's work
  contract with the user: renders `task_detail.sh` + `io_catalog.sh`, then maps
  each request to a single `update_task_io.sh` (IO rows) or
  `update_task_criteria.sh` (acceptance criteria) call. **This is where the
  contract gets edited**: the viz "Editor de IO" is the viewer of the same
  contract and shows criteria read-only, printing each criterion's short id
  precisely so the user can dictate it here.

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
- **task_acceptance_criteria** — verification criteria per *output*, linked by `output_id` → `task_outputs.id` (never to the task directly). `verification_method` is a closed set: `llm`, `manual`, `automated`, `test`, `attested` (there is no `auto`). `is_met`/`verified_*` are state earned by attestation, not contract. Edited with `update_task_criteria.sh`.
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
| `ingest_meeting.sh <drive-file-id\|url> --project N [--space ID] [--name N] [--description T] [--status S] [--dry-run] [--json]` **[WRITE pg]** | **Dar de alta una reunión de equipo desde su grabación en el Drive** («Meet Recordings»). Existe porque las reuniones que no pasan por el calendario de Marketico (ad-hoc, agendadas desde una cuenta personal) quedan solo como mp4: sin fila, sin transcript, sin acta, sin tareas. Crea la fila `meetings` (`team`, nombre = el del archivo, `actual_end` = createdTime del mp4 y `actual_start` = end − duración — la convención verificada en las filas que ingiere Marketico —, `drive_file_id`). Idempotente por `drive_file_id`. **No genera el transcript**: eso es `bash/calls/procesar_video.sh <id> --tipo team` (STT desde el video; el «plain» que Meet deja al lado del mp4 es el CHAT, no el transcript), y después el ciclo normal: skill `transcript-to-report` → `meeting-to-tasks`. Nació 2026-08-23 con la reunión de servicio del 20-ago (`2ea7176d`). |

### Meetings data model
- **meetings** — `meeting_type` is `team` (166) or `call` (1731); `status`: scheduled/completed/ended/cancelled/processing/… `scheduled_start_time`/`actual_start_time`, `project_id`→projects, `space_id`→spaces. `meeting_type` matters: `team` = coordination, `call` = sales calls.
- ⚠️ **`scheduled_start_time` guarda hora BOGOTÁ etiquetada como UTC** (verificado 2026-08-13: histograma del reloj crudo = jornada 07-20 + calendario real). Leer el reloj LITERAL (`AT TIME ZONE 'UTC'`); convertir a America/Bogota corre todo −5h. Patrón correcto en `bash/closers/agenda.sh`.
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
| `reporte_guardar.sh --meeting <uuid> --modelo M [--variante mejorado2] --tirada f.json ×N [--umbral 10] [--destino ambos\|pg\|local] [--sin-escaparate] [--dry-run] [--json]` **[WRITE pg + local]** | Aggregate N tiradas into THE report of a call and persist it (one txn): mediana por ítem, mayoría de arquetipo, narrativa de la tirada más cercana a las medianas, rango>umbral → `baja_confianza`. The deterministic half of the `generar-reporte-llamada` skill (which spawns the N clean-context agents). Regenerating never overwrites (`generacion+1`). **Desde 2026-08-13 escribe en Postgres**: `call_reports` + `call_report_tiradas` y upsert del agregado en `meeting_reports` (el escaparate de la plataforma) — ver «PRODUCCIÓN» abajo. |
| `reportes_pendientes.sh [--desde N] [--min-chars N] [--con-closer] [--limit N]` | **La cola del pipeline**: llamadas con transcript usable (≥2000 chars) y sin reporte del Cerebro, con closer resuelto. Read-only. |
| `generar_pendientes.sh [--limit N] [--desde N] [--model M] [--timeout S] [--dry-run]` **[WRITE pg + local]** | **El runner**: por cada llamada de la cola corre el skill `generar-reporte-llamada` en una sesión headless (`claude -p`) — la generación son N subagentes, no un script. Cuenta intentos en `closers_ops.reportes_intentos` y para a los 2 fallos (sin eso, un transcript roto se reintenta para siempre). La verdad de si funcionó no es el exit code: es si quedó la fila en `call_reports`. |
| `reportes_a_pg.sh [--variante V] [--sin-escaparate] [--dry-run]` **[WRITE pg]** | Promueve a Postgres los reportes que el pipeline ya tenía en la sqlite local (los 63 de la etapa prototipo). Idempotente por meeting: lo ya promovido se salta. |
| `drive_snapshot.sh [--folder N] [--db N] [--dry-run] [--json]` **[WRITE local]** | Snapshot de la carpeta «Closer Calls» del Drive (vía el ÍNDICE de bash/google/, no el listado live que topa en 100 y sin fechas) cruzada contra los call meetings → sqlite `closer_calls.archivos` (tamaño, creado, meeting+status, contacto CRM, resultado, callStatus del reporte vigente) + log `corridas`. Cascada de match declarada por fila (`drive_file_id`→`meet_code`→nombre→prefijo+fecha). Recalcular = volver a correr; reconstruye la tabla entera (las vistas `no_completadas` —ciclo abierto, sin vacías <10 MB— y `confirmadas` se derivan solas). Si el índice está viejo, antes `drive_sync.sh --wait`. |
| `procesar_video.sh <meeting-id> [--file-id ID] [--tipo call\|team] [--min-chars N] [--force] [--keep] [--dry-run]` **[WRITE pg]** | Recuperar el transcript de una llamada desde su VIDEO en Drive (la cola de `no_completadas`): descarga (backend mkt) → audio (`bash/audio/`) → STT (AssemblyAI) → upsert `meeting_transcripts` + `meetings.status='completed'` en una txn → borra la descarga. Dos guardas simétricas: no pisa un transcript ya usable (≥2000 chars) sin `--force`, y no persiste NADA (ni el status) si el STT devuelve <2000 — un transcript basura con status completed es justo el hueco que repara. Tras esto, la llamada cae sola en la cola del pipeline de reportes. `--tipo team` (2026-08-23) hace lo mismo para una reunión de equipo dada de alta con `bash/meetings/ingest_meeting.sh`. |

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

**Experimento de prompt (en curso).** El 60% de los puntajes BANT no nulos cae
en 90-100 y el arquetipo se fragmentó en 47 etiquetas para lo que son cuatro
rasgos. Para separar «es del prompt» de «es del modelo» hay un cuadro de dos
ejes en la db local sqlite `reportes_llamada`: el skill
`replicar-reporte-llamada` regenera el reporte de UNA llamada
(`prompt-produccion.md`, `prompt-mejorado.md` —rúbrica de anclaje + lista
cerrada de arquetipos— o `prompt-mejorado-2.md`),
`bash/calls/importar_produccion.sh` trae el reporte real de gemini como celda de
control, `bash/calls/bant_diff.sh` lo contrasta y
`bash/calls/comparativo_bant.sh` emite la matriz completa (una fila por llamada
× cuatro celdas, las que faltan con `existe:0` + su handle).

**Lo medido hasta hoy** (cohorte ciega de 15 + 3 piloto; pareado mismo-modelo
n=3, que es poco): la rúbrica baja la media 11.7 puntos y casi duplica la
dispersión (sd 8.7→15.9) — *separa*, no comprime. Pero por ítem baja budget
−16.7, timeline −15.0, authority −13.3 y **`need` solo −1.7**: las anclas
genéricas piden que el lead «lo haya dicho explícitamente» y agendar la llamada
ya lo dice, así que ese ítem no tiene modo de fallo (gemini le pone ≥90 a 17 de
18 leads). `prompt-mejorado-2.md` corrige justo eso dándole a `need` un eje
propio —costo de la inacción— y no toca nada más. El confound del modelo va en
contra del hallazgo (claude+producción puntúa +5.1 sobre gemini, n=6), así que
las caídas medidas son un piso. Lo que sí está cerrado: el arquetipo se rompe en
los **dos** modelos (`Emotional Trader / Novice Trader`, `Inexperienced Person
(Emotionally Blocked by Past Losses)` salieron de corridas a ciegas con el
prompt de producción) — eso es del prompt, no del modelo.

**Cohorte 2 — v1 vs v2, un subagente por reporte** (tabla `muestra2`, 8 llamadas
nuevas × 2 variantes, corridas `*-agente`). El diseño cambió y por eso el
resultado vale más: **cada reporte se generó en un contexto independiente**, así
que las dos variantes de una misma llamada no se conocen. Eso elimina el
anclaje intra-sesión —el Δ deja de ser «un piso» y pasa a ser una medida— y
además es *más fiel a producción*, que puntúa cada llamada sin memoria de las
anteriores. Resultado: `need` **81.4 → 60.0**, baja en 7/8 y no sube en ninguna
(prueba de signos **p=0.016**), ≥90 pasa de 3/8 a **0/8**. Los otros tres ítems
—anclas byte-idénticas entre v1 y v2— son el **grupo de control** y se comportan
como ruido: |Δ| 4.0-6.6 sin dirección (p 0.38 / 1.00 / 0.45). El eje nuevo se
mueve **4.2× el ruido**. La llamada que v1 ya había puntuado bajo (45) salió 45
también en v2: corrige lo inflado, no descuenta todo. Arquetipos: **7/8
idénticos** entre contextos que no se conocen, cero etiquetas fuera de la lista.
⚠️ Lo que esto NO prueba: que el puntaje v2 **prediga mejor**. Eso se valida
contra plata (`installments`), no contra otro prompt. Y la sd de `need` casi no
cambió (14.4→13.7): el eje quita el techo, no demuestra dar más granularidad.
Hallazgo lateral que hay que respetar de aquí en adelante: **el ruido de corrida
a corrida con prompt idéntico es de ±4-7 puntos**, así que toda comparación
futura necesita grupo de control.

**Cohorte 3 — test-retest de `mejorado2`** (tabla `muestra3`, 6 llamadas
aleatorias jamás usadas, semilla `20260809`, × 5 tiradas cada una en contextos
limpios; corridas `*-mejorado2-t*`). Mide LA pregunta de fondo: el reporte lo
produce un LLM, ¿cuánto del puntaje es el lead y cuánto es el dado? Resultado:
**ICC 0.88-0.95 en los cuatro ítems** (sd_intra 2.2-4.5 contra sd_inter
8.2-17.4) — la varianza es del lead, el proceso es un instrumento y no una
ruleta. La cifra OPERATIVA es la **diferencia mínima detectable** (2.77·sd_intra):
budget ±12.4 · need ±10.0 · authority ±8.5 · timeline ±6.0 — dos leads que
difieren menos que eso en UNA corrida son indistinguibles del azar, y eso aplica
también a los reportes de producción, que son una tirada única. Arquetipo:
unánime 5/5 en 3 de 6 llamadas; donde difiere, difiere en el rasgo *secundario*
(el primario coincidió en 30/30 tiradas) — el punto flaco es la regla de cuándo
componer con `+`, no el vocabulario. Análisis servido por
`bash/calls/variabilidad_bant.sh` (fuente viz `bant_variabilidad`, UI
`bant-variabilidad`: KPIs de ICC + tiras de puntos por tirada). ⚠️ n=6 llamadas;
y el ICC alto NO valida el contenido del puntaje — consistencia no es verdad;
la verdad se mide contra `installments`.
⚠️ Todo esto vive bajo una regla de contaminación: **no se miran los puntajes de
una llamada antes de generar los propios** — ni el JSON, ni la db local, ni la
UI. Ver el skill. **El informe que junta las tres cohortes y justifica el cambio
en producción: `docs/bant-prompt-informe.md` (operador).**

**Generación de reportes desde el cerebro (pipeline, no experimento).** Decisión
2026-08-09: los reportes de llamada se generan AQUÍ de ahora en adelante; la
generación por gemini en el API se depreca eventualmente. El skill
`generar-reporte-llamada` lanza **N subagentes de contexto limpio** (default 3)
con el prompt canónico vigente (`prompt-mejorado-2.md`), y
`bash/calls/reporte_guardar.sh` **[WRITE local]** agrega y persiste en la db
local `generador_reportes` en una txn: **mediana por ítem** (el ruido real es
«pelotón + tirada suelta», y la mediana-de-3 baja el mínimo distinguible de
±11/±9 a ±4.5/±3.2), **voto de mayoría** para el arquetipo, narrativa de la
tirada más cercana a las medianas, y **rango>10 → ítem en `baja_confianza`**
(umbral calibrado con ruido de claude; recalibrar si cambia el modelo). Tablas:
`reportes` (agregado: medianas/rangos/votos en columnas + JSON canon con bloque
`_generacion`) y `tiradas` (los N crudos, siempre). Regenerar = `generacion+1`,
nunca sobreescribe. La motivación con números: el primer cruce
contra plata (14 llamadas v2, 5 con primera cuota pagada 0-3 días post-llamada)
dio AUC 0.93 para v2 contra 0.59 de producción — n chico, pero la dirección
justificó el pipeline.

**PRODUCCIÓN (2026-08-13) — el reporte del Cerebro reemplaza al de gemini.**
Decisión de Santiago: las operaciones de la plataforma se van portando al
Cerebro y el reporte de llamada es la primera. Migración
`catalog/migrations/005_call_reports.sql` (operador):

- **`call_reports`** (+ `call_report_tiradas`) — la fuente de verdad: una fila
  por meeting × generación, con la procedencia EN COLUMNAS (variante, modelo,
  N, medianas, **rangos**, `baja_confianza`, votos de arquetipo, tirada
  narrativa). Un puntaje sin su rango no dice si es señal o ruido.
- **`meeting_reports`** pasa a ser el **escaparate**: lo que la plataforma
  muestra. `reporte_guardar.sh` lo upsertea con el agregado — reemplazando al
  de gemini. (Tiene UNIQUE por meeting: no caben los dos.)
- **`call_reports_gemini`** — los 240 reportes de gemini **congelados antes del
  primer reemplazo**. Es la celda de CONTROL de las cohortes 1-5; sin ella el
  experimento que justificó el cambio deja de ser reproducible. No se toca.
- **`call_report_vigente`** (vista) — cuál manda por llamada: cerebro (última
  generación) si existe, si no lo que haya en `meeting_reports`. Cada fila
  declara su `fuente`.

⚠️ **Regla de consumo que hay que sostener.** Los scripts **operativos**
(`calls.sh`, `call_show.sh`, `call_stats.sh`, `call_objections.sh`,
`lead_profile.sh`, `closer_dashboard.sh`) leen **la vista**. Los del
**experimento** (`bant_diff`, `comparativo_bant`, `importar_produccion`,
`validacion_plata`, `rasgo_plata`, `conversion_real`, `lead_score_model`) leen
**`call_reports_gemini`**, nunca `meeting_reports`: desde hoy esa tabla trae
reportes nuestros, así que seguir leyéndola como «producción» convierte el
control en el tratamiento y pudre todos los AUC en silencio. Verificado tras el
corte: la cohorte 4 sigue dando 0.850 vs 0.620.

**El pipeline automático** (transcript → reporte → coaching al closer):
`reportes_pendientes.sh` (cola) → `generar_pendientes.sh` (corre el skill
headless) → `bash/closers/escenario_reporte.sh` (el mensaje de vuelta). El
disparador es la **aparición del transcript**, no `meetings.status` (que es
inservible: hay llamadas con transcript en `completed`, `ended` y una en
`in_progress` al día siguiente). Dos hechos medidos que el diseño respeta:
la fila de transcript aparece **+4 a +90 min** del inicio, pero **la mitad son
basura de ~210-220 chars** (las de verdad pesan 23k-70k) y **solo 25-40% de las
llamadas que ocurren dejan transcript** — así que esta cola no es el universo
del día y el mensaje post-llamada a ciegas sigue haciendo falta.

**Cohorte 4 — VALIDACIÓN CONTRA PLATA** (tabla `muestra_validacion` en
`generador_reportes`, semilla `validacion-plata-20260809`). La pregunta que las
cohortes 1-3 no podían responder: consistencia no es verdad. Diseño
**caso-control ciego**: 20 llamadas estratificadas 10 que pagaron / 10 que no
(de 131 candidatas frescas con transcript y reporte de producción), puntuadas
por el pipeline de 3 tiradas en contextos limpios — los agentes solo vieron el
transcript, y el desenlace es posterior a la llamada, así que no puede
filtrarse. Criterio externo: `bash/calls/conversion_real.sh` (llamada→contacto→
`payment_plans`→cuota pagada, con **ventana temporal** de 30 días y
**atribución única** al llamado más cercano que precede al plan). Métrica: AUC
con **p por permutación exacta** sobre las C(20,10)=184.756 asignaciones
(`bash/calls/validacion_plata.sh`).

Resultado: **v2-mediana AUC 0.850 (p=0.0068) contra producción 0.620
(p=0.38)**. Por ítem, v2 authority 0.82 · need 0.81 · timeline 0.835 ·
budget 0.64; producción no pasa de 0.625 en ninguno. **El eje de `need` quedó
validado contra dinero**: producción da 95.0 a los que pagaron y 94.0 a los que
no (3 valores distintos en 20 llamadas — el techo diagnosticado en la cohorte
1), v2 da 74.3 vs 57.2. Granularidad: v2 usa 11-13 valores distintos por ítem
contra 3-8 de producción, y **cero empates** en el promedio contra 5 de
producción — un puntaje que empata no ordena. ⚠️ **Qué es «la plata»**:
`pagado` = total cobrado hasta hoy (suma de cuotas `Paid`) — ni el primer pago
ni el precio del producto, y **confundido con el tiempo** (una llamada vieja
acumuló más cuotas), así que sirve para el binario pero NO como magnitud; la
variable limpia de tiempo es `payment_plans.original_amount` (valor del
contrato). Los dos «convertidos» que v2 manda al fondo pagaron \$25 y \$50 pero
**firmaron planes de \$450 y \$1.000**: son ventas incumplidas, no pagos
simbólicos. Contra desenlaces más exigentes el AUC **sube**: firmó plan
≥\$1.000 → **0.893**; pagó ≥50% del plan → **0.945 (p=0.0005)**. Entre los que
compraron, el puntaje ordena también el tamaño de la venta (Spearman ρ=+0.58,
n=10). ⚠️ Muestra caso-control: el AUC es válido (no depende de prevalencia)
pero **las tasas de conversión por banda NO** — eso pide muestra aleatoria
aparte. n=20; el orden de magnitud es sólido, el tercer decimal no.

**Cohorte 5 — LA RÉPLICA** (misma tabla, `cohorte=5`, semilla
`replicacion-plata-20260809-c5`): 20 llamadas nuevas, mismo diseño 10/10, mismo
pipeline, cero solapamiento. Se reporta sola ANTES que combinada — juntar 40
filas escondería si la réplica falló. **v2: 0.850 (c4) → 0.760 (c5) → 0.804
(las 40, p=0.0007)**; producción: 0.620 → 0.700 → 0.655 (p=0.09). El hallazgo
**se sostiene y se encoge**: el primer número fue el más alto de dos muestras,
la lectura honesta es la combinada, y v2 le saca ~15 puntos de AUC a producción
en ambas. Lo que NO se replicó: `need` cayó a 0.605 en la c5 (era 0.810) — el
eje suma en el combinado (0.719) pero **no es el motor estable** que sugería la
c4; `timeline` (0.791) y `authority` (0.774) sí. Lo que SÍ se replicó exacto:
el `need` de producción es plano en las dos (95.0/94.0 · 95.5/94.0). Con n=40
el p ya no se enumera (C(40,20)≈1.4e11) → Monte Carlo 200k con semilla fija; el
script declara el método por fila. `validacion_plata.sh [--cohorte 4|5|todas]`.

Viz sources: `calls`, `call_detail` (object), `call_stats`, `call_objections`,
`bant_comparativo` (la matriz del experimento; UI `bant-comparativo`).

## Audio domain — video→texto ([bash/audio/](bash/audio/))

Piezas locales y sin estado para convertir grabaciones en texto; la composición
con Drive y la DB vive en `bash/calls/procesar_video.sh`. `extract_audio.sh
<video> [--out F]` extrae la pista con ffmpeg (mono 16 kHz mp3 48 kbps, ~21
MB/hora). En [bash/audio/stt/](bash/audio/stt/) vive un script por motor STT,
todos con el mismo contrato (entra audio, sale texto diarizado `Speaker A: …`
— el formato de `meeting_transcripts`): hoy solo `assemblyai.sh <audio>
[--lang es] [--out F] [--raw F]` (credencial `ASSEMBLYAI_API_KEY` en `.env`,
pasada por fd, nunca argv; cobra por minuto de audio — transcribe UNA vez, sin
reintentos).

## Video domain — cosas con ffmpeg ([bash/video/](bash/video/))

Piezas locales y sin estado (ni `.env` ni Postgres): entra un archivo, sale un
archivo; la composición con Drive/DB vive en los dominios que las usan. Hoy:
`frame.sh <video> --at T [--out F] [--force] [--json]` — UN fotograma en un
instante (`T` = segundos o `HH:MM:SS[.ms]`), seek preciso (no el keyframe más
cercano), la extensión de `--out` decide jpg/png/webp, y pedir más allá del
final es error (ffmpeg calla, el script no). Reglas compartidas con
`bash/audio/`: `-nostdin` siempre, nunca pisa sin `--force`. Detalle en
[bash/video/README.md](bash/video/README.md).

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
| `anuncios.sh --project N [--from D] [--to D] [--tipo adquisicion\|marca\|todos] [--campaign TOK] [--min-spend X] [--limit N]` | **Una fila por ANUNCIO** (el creativo como unidad — lo que el equipo mira en la «plataforma de Bala»): campaña/adset/objetivo, `tipo`, estado, spend, impr, clics al link, CTR/CPC/CPM, LPV + tasa, plays y cuartiles, **hook = vistas 25%/plays · hold = 75%/25% · fin = 100%/plays** (⚠️ `video_views` de Meta aquí es autoplay ≈ impresiones, no 3 s: por eso el hook va por cuartil), **compras/valor/ROAS del PIXEL** y, al lado, **la caja REAL por anuncio**: leads (oportunidades del CRM de la ventana atribuidas por `crm_contacts.attr_ad_id` — la atribución nativa de GHL que Marketico persiste desde 2026-08-21 a pedido nuestro, `docs/marketico-pedido-atribucion-ghl.md`; último toque, `url.ad_id` antes que `utmTerm`), won, planes ≤60 d del lead, contrato, cash, **ROAS real** (solo USD), CPL real, CAC, y tres columnas de cobertura repetidas por fila (`cob_leads_total/con_ad/ad_en_ventana`: ~70% de los leads del mes traen ad; el resto es orgánico/directo y no se reparte). CPA, y la **miniatura** desde la caché local. `tipo` = marca si el objetivo de campaña es de awareness/engagement/likes/video **o** si LPV ≤ 2% de los clics (≥50): «no llevan tráfico a la landing» medido, no por nombre — así las campañas de seguidores con objetivo TRAFFIC caen en marca. Read-only. Fuente viz `ad_anuncios` → page `anuncios` (UI ejecutivo `anuncios`: tarjetas con creativo + tabla gemela, selector tipo/orden; KPI «Leads atribuidos N/M» declara la cobertura para que el ROAS real no se lea como exhaustivo). |
| `angulos.sh --project N [--from D] [--to D] [--min-spend X] [--sin-web]` | **Ángulos ganadores → titulares**, un objeto: `campanas` (ranking por CAJA con la **atribución de GHL** — `crm_contacts.attr_campaign_id`, último toque — y fallback al `utm_campaign` del form, mismas CTEs de `embudo.sh`: leads, won, planes ≤60 d, contrato, cash, CPL/CAC/ROAS real, más `leads_ghl`/`leads_solo_form`; la fila «sin atribución» es orgánico/referral/directo y **no se reparte**; `{{campaign.name}}` literal se marca como UTM roto), `angulos` (familias de **copy** del anuncio agrupadas por texto — el ángulo con que se compró el clic — con spend/LPV/hook/hold/compras pixel y **leads/planes/contrato/cash REALES = suma de los de sus anuncios** vía `anuncios.sh` (`attr_ad_id`); hasta el 2026-08-21 era `cash_estimado` proporcional al gasto y se declaraba), y `landings` (a dónde manda la pauta, con el **H1 leído en vivo** — curl, tolerante: si falla viene `null` + error). Nació del meeting `b3f06835` («testear titulares del VSL»): pone juntos el ángulo que compra el clic y el titular que lo recibe, para que el quiebre de message-match se vea. Read-only. Fuente viz `ad_angulos` → page `angulos` (UI ejecutivo `angulos-titulares`, cuyos **titulares propuestos viven en `params.titulares` del spec** — copy curado, se cambia re-publicando; el testeo se abre con `testeo_abrir.sh --step titular`, nunca desde la página). |
| `creativos_sync.sh --project N [--from D] [--to D] [--min-spend X] [--dry-run] [--json]` **[WRITE local]** | Llena/refresca la caché de miniaturas `data/sqlite/ads_creativos.db` desde el **Graph API** (`/?ids=…&fields=creative{thumbnail_url,image_url}`, lotes de 50) con el user token de `identities` (provider `facebook*`, el vigente de vencimiento más lejano; por header, jamás argv ni impreso). Existe porque `ads.ad_creative_id` está vacío en toda la tabla. Cerca por rol (`bash/lib/acceso.sh`, dominio `meta`). Las URLs de Meta expiran → cada corrida refresca todos los anuncios de la ventana (110 ads = 3 GETs). **Desde 2026-08-21 trae también el COPY del creativo** (`titulo`/`cuerpo`, de `title`/`body` u `object_story_spec`) **y el `enlace`** (la landing del anuncio) — `anuncios.sh --json` los emite y `angulos.sh` los agrupa; cachés viejas migran solas (ALTER). Solo GET a Meta; la única escritura es la sqlite local. **En el publicador corre solo**: pm2 `creativos-cron` (diario 10:30 UTC = 05:30 Bogotá, `--project "David Guerrero"`; la caché es local a cada máquina). |
| `followme.sh --project N [--from D] [--to D]` | **Los follow-me ads (la pauta de marca) medidos en lo que Meta sí reporta por anuncio**: por campaña y por día, visitas al perfil de IG (`link_click` con destino `INSTAGRAM_PROFILE`/meta `PROFILE_VISIT`), conversaciones DM iniciadas, likes, guardados, video views, con costo unitario — y la serie de **seguidores** construida con las fotos de `seguidores_snapshot.sh`. Las campañas «marca» son las de `anuncios.sh --tipo marca` (una sola regla). Graph API nivel campaña×día con el token de identities (cerca por rol `meta`); errores por cuenta declarados en `meta.errores_meta` (la cuenta `DavidGuerrero_93` responde 403 al token; las de marca viven en «CONTINGENCIA»). ⚠️ Meta no reporta follows por anuncio e IG Insights (`follower_count`) está cerrado por scopes — pedido `docs/marketico-pedido-instagram-insights.md`. Read-only. Lo consume `bash/metrics/organico.sh` (`followme`). |
| `seguidores_snapshot.sh [--project N] [--dry-run] [--json]` **[WRITE local]** | **La foto diaria del total de seguidores** de cada cuenta IG business del token (`me/accounts{instagram_business_account{followers_count}}` — eso sí responde con `pages_show_list`) → sqlite `data/sqlite/ig_seguidores.db` (`fotos` PK fecha+ig_id, upsert; `corridas`). Restadas entre sí son la serie de seguidores nuevos que IG no nos deja pedir hacia atrás: **el histórico empieza el día de la primera foto** (2026-08-21). Caché local por máquina; en el publicador corre el pm2 `seguidores-cron` (04:55 UTC = 23:55 Bogotá). Cerca por rol `meta`; solo GET a Meta. |

Known data caveat: Meta-reported `purchase_value` on the Andrea (COP) account
has junk magnitudes (~663M COP for 4 purchases in June) — treat COP ROAS as
unreliable until the pixel currency is fixed; cash truth lives in
`installments`/`economics_ledger`.

Viz sources: `ad_campaigns`, `ad_stats`, `ad_detail` (object), `ad_anuncios`, `ad_angulos` (object).

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
| `leads.sh [--dueno LISTA] [--sin-dueno] [--project N] [--stage FRAG] [--from D] [--to D] [--dias-min N] [--pagado\|--organico] [--limit N]` | The leads as ROWS, with owner **and attribution from two sources** (desde 2026-08-21): la **nativa de GHL** que Marketico persiste en `crm_contacts` (`attr_campaign_id`/`attr_ad_id`, último toque — campaña y **anuncio** de Meta resueltos contra `campaigns`/`ads`) con fallback al `utm_source`/`utm_campaign` del formulario (`custom_fields` contra `crm_custom_fields`). Cada fila trae `origen` (utm_source si hay; si no `fb` para pauta sin form, o la **sesión** que registró GHL — Social media / Referral / Direct traffic — para lo no pagado: el orgánico deja de ser un balde ciego), `campana`, `anuncio`, `formulario` (`ghl_source`). `--pagado`/`--organico` = con/sin campaña por cualquiera de las dos fuentes. `--dueno` takes a comma list of name fragments plus the token `sin-dueno` for the orphans. Supersedes `pipeline.sh --list`. |
| `opp_detail.sh <id\|prefix>` | One opportunity + its contact as a single JSON object, with the GHL custom fields resolved to their question — the qualification survey the lead answered plus the `utm_*` — **and the `atribucion` block** (desde 2026-08-21): la atribución nativa de GHL del contacto con sesión, campaña y anuncio de Meta resueltos, `utm_content`, `placement`, referrer, formulario de entrada, fecha real de alta en GHL y el primer toque si difiere del último. Feeds the viz detail panel (bloque «Por dónde entró (GHL)»). |
| `facets.sh [--project N] [--from D]` | The universe of owners and stages with counts (`{tipo,valor,n}`) — reference data that populates the leads filters. Kept separate on purpose: derived from already-filtered rows, a filter's options would close in on themselves. |

## GHL domain — el CRM en la fuente ([bash/ghl/](bash/ghl/))

**Read-only** access to the GoHighLevel API v2, direct. Exists to **measure the
mirror against the source** — it is a probe, not a second ingestion path
(nothing here writes, to GHL or to the DB). Credentials are the org's GHL
Private Integration Tokens, which live in `project_crm_configs` **in
plaintext** (despite the column name `api_key_encrypted`), so the layer is
fenced **por rol** (`bash/lib/acceso.sh` — cerebro y `ejecutivo` acceden; el
resto se niega, exit 3), only GETs, and hands the
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

## VTurb domain — el video en la fuente ([bash/vturb/](bash/vturb/))

Sonda **read-only** contra el VTurb Analytics API (`analytics.vturb.net`) — el
proveedor de video de las VSLs. Patrón `bash/ghl/` completo: tokens en la DB en
claro (`project_vturb_video_configs.api_key_encrypted`), **cerca por rol**
(`bash/lib/acceso.sh`: cerebro y `ejecutivo`; el resto exit 3), token por stdin jamás en argv, y «solo consultas» (el API usa
POST para leer stats; no expone mutaciones). Contrato de la superficie proxy de
Marketico: `apis/mkt/vturb-video.openapi.json`.

| Script | Use it to… |
|--------|-----------|
| `auth_status.sh` | Qué proyectos tienen VTurb y si el token responde (sonda live + conteo de players). |
| `videos.sh --project N [--seleccionados]` | Catálogo de players en vivo (con `pitch_time` y columna `sel`); `--seleccionados` = los curados en `project_vturb_video_selections`, desde la DB (ahí vive la duración, insumo de retención). |
| `analitica.sh --project N [--video ID [--duracion S]] [--from D] [--to D]` | El funnel de video por seleccionado: impresiones → plays (tasa de play) → retención 25/50/75% → % pitch → % terminó → CTA. Default mes actual (Bogotá). `--json` trae histograma completo + `average_watched_time`/`engagement_rate`. |

⚠️ **Semántica verificada 2026-08-20** (detalle en [bash/vturb/README.md](bash/vturb/README.md)):
`grouped_timed` es **histograma de abandono** (dónde paró cada espectador; el
bucket duración+1 = los que terminaron), NO curva de supervivencia — la
retención se calcula como cola acumulada. El normalizador de Marketico
(`vturbVideoProvider.normalizeRetention`) lo lee como supervivencia: **bug vivo
en su funnel, reportable**. `total_viewed_*` = impresiones del player (≥ plays =
`total_started_*`). La ventana de fechas SÍ aplica también al engagement. Los 2
proyectos configurados comparten una sola cuenta VTurb (mismo catálogo).

## PM domain — la plataforma de Mari ([bash/pm/](bash/pm/))

El API de project360 (`PM360_BASE`+`PM360_TOKEN` en `.env`, Bearer; superficie:
`GET /tasks?limite=&offset=` y `GET /tasks/{id}`) es la fuente del **lado PM del
cruce**. El cruce PM↔cerebro se lee sobre *snapshots* en la sqlite local
`pm_platform`, no sobre datos vivos: sin refresco, propone acciones sobre
estados que ya cambiaron.

| Script | Use it to… |
|--------|-----------|
| `cobertura.sh [--json] [--estricto] [--horas N]` | **El chequeo del invariante PM↔cerebro**, escrito una vez. Read-only; se corre DESPUÉS de los dos sync (avisa si algún espejo pasa de `--horas`, default 24). Existe porque este invariante se midió mal tres veces el 2026-08-20 por el mismo motivo: hay **dos vías de enlace** —`tasks.source_external_id` y `cruce.ce_id`— y mirar solo una inventa huecos. Reporta **[A]** abiertas en PM sin nada vivo acá, **clasificadas**: `hueco` (hay que crearla) · `decidida` (su fila del cruce ya está resuelta — enlace en prosa, no hueco) · `muchos-a-uno` (la tarea que la cubre ya tiene otro `source_external_id`: pide tabla de enlaces, no `link_external.sh`). Y **[B]** abiertas acá con su gemela PM cerrada → `complete_task.sh`. ⚠️ Una tarea con **varias** gemelas en PM sigue abierta si **alguna** sigue abierta. `--estricto` sale 1 solo con huecos reales (para cron). |
| `sync_cerebro.sh [--dry-run] [--no-cruce] [--json]` **[WRITE local]** | El **espejo** del anterior, para el otro lado: refresca `cerebro_tareas` desde Postgres (upsert por prefijo de 8) y con él las copias `ce_titulo`/`ce_estado`/`ce_proyecto` de las filas **no resueltas** de `cruce`. Existe porque al cruce se le había construido refresco a UNA sola mitad: medido el 2026-08-20, **140 de 205 filas mentían** sobre el lado cerebro (94 decían `pending` de tareas ya canceladas), así que la UI ofrecía como candidatas vivas cosas cerradas hacía horas. Solo LEE Postgres (`psql_ro`) — no cierra, no cancela, no crea. Registra la corrida en `cerebro_sync`. ⚠️ **No recalcula el cruce**: veredictos y pares salieron de una pasada semántica hecha una vez; lo nacido después del snapshot sale listado como «sin fila en el cruce», no gana fila solo. Un prefijo de 8 compartido por dos tareas se excluye y se reporta antes que adivinar. |
| `sync_tareas.sh [--dry-run] [--limit N] [--no-cruce] [--no-snapshot] [--json]` **[WRITE local]** | Refrescar el espejo `tareas` desde el API (upsert por id, una txn) y, con él, las copias denormalizadas `pm_titulo`/`pm_estado`/`pm_asignado` de las filas **no resueltas** de `cruce`. Guarda el JSON crudo en `data/pm-platform/tareas-<fecha>.json` y registra la corrida en `pm_sync`. |

Tres reglas que el script sostiene y conviene no romper:

- **Nunca borra.** Una tarea que desaparece del API se *reporta* (`desaparecidas`),
  no se elimina: hay filas de `cruce` apuntándole, y la línea es «cruzar y
  ajustar, no borrar». Tampoco escribe jamás en Postgres — promover al cerebro
  es trabajo de `bash/tasks/merge_from_cruce.sh`.
- **Las filas `resuelta=1` del cruce se congelan.** Una fila resuelta documenta
  una decisión tomada sobre el contenido que muestra; refrescarla reescribe la
  historia. Solo se re-sincronizan las abiertas.
- **Un fetch de 0 tareas aborta sin escribir** — eso es el API caído, no una
  plataforma vacía.

**El cruce es multi-proyecto desde 2026-08-10.** Nació mirando solo las 402
tareas de David Guerrero, y por eso todo lo que Mari archivó bajo DG sin serlo
cayó en `otro_proyecto`. Al entrar las 24 de Ikigai (`cerebro_tareas.proyecto`,
`cruce.ce_proyecto` — antes el proyecto era implícito), ese balde se desplomó de
**23 a 3** (solo Andrea, aún fuera de alcance) y aparecieron 19 pares que el
alcance DG no podía ver. La regla que lo hace posible: **la plataforma PM archiva
todo bajo DG, así que el único lado que sabe de qué proyecto es un par es el
cerebro** — de ahí que el filtro de la UI lea `ce_proyecto` y que las filas «solo
PM» no pertenezcan a ningún proyecto. Meter Andrea es la misma operación.

Lo que hay que mirar en la salida: `cruce_alertas` (filas sin resolver que Mari
pasó a `completed` — cambian la acción propuesta, típicamente a
`completar_en_cerebro`) y `nuevas_sin_par` (tareas nuevas sin fila de cruce; el
cruce semántico se hace aparte, el script no lo inventa). El **lado cerebro**
(`cerebro_tareas`) lo refresca su gemelo `sync_cerebro.sh` — este script no lo
toca, y hasta el 2026-08-20 nadie lo hacía: fue un snapshot congelado del
2026-08-06 durante dos semanas. **Los dos hay que correrlos**; refrescar una
sola mitad deja la comparación coja, que es exactamente el estado del que salió
el gemelo.

## Closers domain — acompañamiento WhatsApp ([bash/closers/](bash/closers/))

Los 5 escenarios diarios de los closers por WhatsApp (saludo 07:00 con agenda
· recordatorio 45 min con link de Meet · resultado post-llamada · confirmación
de plan de pagos · cierre 20:00 con cuotas de mañana), mitad cron/scripts y
mitad Iki (protocolo post-llamada de su AGENTS.md). `agenda.sh` (read-only,
llamadas del día resueltas por closer con la traza CRM de bash/calls/),
`enviar.sh` **[WRITE→WhatsApp]** (enviador único: sesión o plantilla Meta,
idempotente por `(escenario,ref)` en la sqlite `closers_ops`), y los tres
`escenario_*.sh` **[WRITE→WhatsApp]** que el cron dispara. Doc completo, con
plantillas Meta y pendientes: `docs/closers-whatsapp.md` (operador).
⚠️ **El canal como problema de negocio** —capacidad, bloqueos, el pivote a
WhatsApp como entrada del embudo y los cambios de Meta de octubre— está
rastreado desde las actas en `docs/whatsapp-canal-brief.md`. Leerlo ANTES
de tocar rotación de números, verificación paga o coexistencia: el equipo
viene resolviendo la capacidad multiplicando números, que es justo lo que
causó los 3 bloqueos de agosto.

## Onboarding domain — primer contacto por WhatsApp ([bash/onboarding/](bash/onboarding/))

El opt-in inicial del equipo al Cerebro por WhatsApp (mismo WABA que
`bash/closers/`, 690499003502578) — **nunca broadcast**: un destinatario por
corrida, a quién y cuándo lo decide el humano. `enviar_onboarding.sh --para
<nombre> [--gancho "…"] [--grupo equipo|closer] [--dry-run] [--json]`
**[WRITE→WhatsApp]** agrupa por rol (team_members/team_roles): **closer** ya
tiene ventana abierta con Iki a diario → texto de sesión +
`--fallback-plantilla bienvenida_iki_closer`; **equipo** (primer contacto real,
nunca les llegó nada de este número) → siempre plantilla `bienvenida_iki_equipo`
(un texto de sesión aquí lo acepta Meta y falla después por webhook, no al
instante — ver `docs/closers-whatsapp.md`). Ambas plantillas se presentan como
**Iki, la asistente IA de Ikigai** (no "el Cerebro" — ese es el nombre interno
del sistema, cara al equipo es Iki). El gancho (`{{2}}`) es genérico
por defecto, `--gancho` lo personaliza (p.ej. Juan Camilo: sus dos assets ya
vivos, dashboard del embudo + testeos VSL/pauta). Idempotente vía
`bash/closers/enviar.sh` (`escenario=onboarding-cerebro`, `ref=<nombre>`).
`plantilla_crear.sh --nombre N --categoria UTILITY|MARKETING --cuerpo "…{{1}}…"
[--ejemplos "a|b"] [--dry-run] [--json]` **[WRITE→Meta]** crea una plantilla
nueva en el WABA (sin upsert; queda PENDING hasta que Meta la revise, cuenta
con días).

## ManyChat domain — Instagram DMs en la fuente ([bash/manychat/](bash/manychat/))

Sonda **read-only** contra `api.manychat.com` (patrón `bash/vturb/`: token por
header, jamás argv ni impreso). Es la entrada del **embudo orgánico** (setters →
leads orgánicos → cierres), que `embudo.sh` hoy no ve más allá de `crm.organicos`.
Tokens en `.env` como `MANYCHAT_TOKEN*`; hay **dos cuentas de Instagram**
distintas a nombre de David Guerrero, las dos activas — la **operación**
(setters, audios de calificación/agenda, comentarios en reels, y donde aparecen
los leads ganados del CRM) es la `3175…`; la `5001…` es la secundaria de
contenido/YouTube. Evidencia y cómo se distinguieron: [bash/manychat/README.md](bash/manychat/README.md).
`auth_status.sh [--json]` dice a qué página responde cada token.

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

Access to the org's Drive through the **Meetico backend** (read-only salvo las tres escrituras declaradas: carpeta, Doc y mover)
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
| `drive_mkdir.sh <parent id\|url\|name> --name N [--json]` **[WRITE→Drive]** | Crear una carpeta en el Drive de la org con la identidad de la org (`POST /drive/folders`, desde 2026-08-22). **Idempotente por nombre** dentro del padre: la que ya existe se devuelve (`created:false`), nunca se duplica. Convención para los Docs de contratos de tarea: `1. David Guerrero/Hermetico/<id8> · <título corto>/` — una carpeta por tarea, el id corto en el nombre es el enlace de vuelta al contrato. |
| `doc_create.sh <parent> --title T --from f.md\|- [--html] [--share email[:reader\|commenter\|writer]]… [--notify] [--dry-run] [--json]` **[WRITE→Drive]** | Crear un **Google Doc** desde un Markdown (pandoc → HTML → importación nativa de Google; conserva títulos, tablas, listas) u HTML (`--html`), en una carpeta, opcionalmente compartido al crear (`POST /drive/files`). No sobreescribe: crear dos veces = dos Docs (re-publicar contenido pide `PUT /drive/files/{id}/content`, pendiente). Primer uso: los «Requerimientos del reporte» de 332c414a. |
| `drive_mv.sh <file id\|url> --to <folder id\|url\|name> [--json]` **[WRITE→Drive]** | Mover un archivo o carpeta a otra carpeta del Drive de la org (`PATCH /drive/files/{id}` con `parentId`, desde 2026-08-22). Reemplaza **todos** los padres por el destino; el id y la URL no cambian, así que los enlaces de los contratos sobreviven al orden. Si ya está ahí, no toca nada. Con `drive_mkdir.sh` y `doc_create.sh` cierra el trío carpeta · Doc · mover; lo único que falta es reemplazar contenido. |
| `drive_sync.sh [--all-drives] [--trashed] [--wait] [--timeout N] [--status]` **[WRITE]** | Refresh the index (`POST /drive/index` → 202, poll `/drive/index/status`; 409 if one is already running). The **only** write in `bash/google/` — and it rewrites our index, not the Drive. Since 2026-08-09 a PM2 `drive-index` job also runs it daily at 10:00 UTC (05:00 Bogotá), so this is for "I need it fresh *now*". |
| `drive_file.sh <id\|url>` | Metadata of one file. |
| `doc_read.sh <id\|url> [--out F] [--txt]` | A Google Doc as **Markdown** (`?format=markdown`). `--out` writes a file. |
| `sheet_show.sh <id\|url>` | Sheet metadata (tabs not exposed by the backend yet). |
| `sheet_read.sh <id\|url> [--limit N] [--raw]` | First tab's values as an aligned table (CSV; row 1 = header); `--json` = array of objects. |

## Metrics domain ([bash/metrics/](bash/metrics/))

`dashboard.sh [--project NAME] [--from D] [--to D] [--json]` — financial KPI set
for one project/period (cash-collected model: ingresos brutos, venta programas,
pauta, costos, reparto). Read-only; feeds the viz `dashboard` source (emits one object).

`embudo.sh --project NAME [--from D] [--to D] [--meses N]` — **EL CRUCE** del
embudo completo en un objeto: pauta (Meta) → VSL (VTurb **en vivo**, agregado +
por video) → leads/etapas con atribución por **dos fuentes** (la nativa de GHL en
`crm_contacts.attr_*` con fallback al UTM del form; `crm.atribucion_fuentes`
las concilia y `crm.sin_atribucion_por_sesion` desglosa lo no pagado) →
llamadas (meetings, reloj literal) → ventas/cash (payment_plans/installments) → serie mensual de cuotas
(cobrado/día total y solo n≥2, % de planes pagando, empiezan/dejan) →
`atribucion` por campaña (spend×leads×cash, guardia temporal +60d) →
`conciliacion` (handoffs entre fuentes con delta) → `series` mensuales
(CAC/ROAS real) → `frescura` (lags + alertas, p.ej. ingestor CRM quieto) →
`sin_instrumentar` (huecos declarados). Reglas: leads del CRM y no de Excel;
la verdad del dinero es la caja (pixel viaja como `*_pixel`); ratios solo
contra pauta USD. Nació del meeting `b3f06835` (2026-08-19). Read-only; feeds
la fuente viz `embudo` (cache 60s por etiqueta con el API externo) y la UI de
rol ejecutivo `embudo-cruce` (page `embudo`; las **metas** — p.ej. ROAS ≥3.5 —
van en `params.metas` del spec, no en código). Desde 2026-08-21 el spec lleva
también **`metas.salud`**: la lista de benchmarks por tasa de paso (`{metrica,
ruta, bueno, excelente, dir, unidad, escala}`) que la página pinta como bloque
«Salud del embudo vs benchmarks» (excelente · bueno · mejorable). La `ruta` es
punteada con la **misma semántica que `testeo_abrir.sh --metrica`**
(`pauta.0.ctr`, `vsl.total.tasa_play`) y admite un cociente `a / b` con
`escala` para tasas que el script no emite calculadas. Son referencias (hoy:
high-ticket infoproductos, alineación DG 2026-08-20), no metas de la org —
calibrar con la serie propia re-publicando el spec.

`etapas_semana.sh --project NAME [--desde D] [--hasta D] [--incluir-pauta]` — **el
reporte semanal por etapa del embudo orgánico** (entregable de 3f8f9914): una
fila por semana de entrada con los leads orgánicos, cuántos traen usuario de
Instagram, la **cobertura** de calificación y los conteos por etapa (calificado
· no calificado · agendó · no conectó · venta) leídos de los tags del contacto
en GHL — misma definición de orgánico y de etapa que `organico.sh`. Se mide en
el CRM y no en ManyChat porque su API no cuenta por etiqueta; la regla es que la
etiqueta se pone en ManyChat **con el mismo nombre** que en el CRM, viaja al
contacto y aquí se cuenta (`docs/etapas-etiquetas-embudo-organico.md`, el Doc
del input). Línea base jul–ago 2026: cobertura 15–35 %, IG 0–13 %. Fuente viz
`etapas_semana` → UI publicada `etapas-semana-dg` (tabla).

`organico.sh --project NAME [--from D] [--to D] [--meses N]` — **EL EMBUDO
ORGÁNICO** en un objeto (hueco #3 del contraste Kaizen 2026-08-20): los leads
del CRM **sin pauta** (sin campaña ni en la atribución de GHL ni en el utm del
form) por **canal de entrada** — regex sobre `ghl_source` primero (el form que
creó el lead) y los tags después: serie de YouTube (+ `serie_youtube` por
módulo), lead magnets, survey orgánico, VSL sin pauta, masterclass, low
ticket, aplicación premium, referido Bala, sin formulario — con sesión de GHL
(Social media · Referral · Direct), won/planes ≤60 d/contrato/cash, **el tramo
intermedio** (`con_etapa`/`cobertura_etapa`/`calificados`/`no_calificados`/
`agendo`/`no_conecto`, leídos de los tags del contacto en GHL: `calificado cc` ·
`no calificado`+`descalificado cc` · `agenda*`+`llamada agendada pm` ·
`no se conectó`+`no contesta`), `series`
mensual orgánico vs pauta, y la **pauta de marca** del mes al lado (misma regla
`tipo=marca` de `anuncios.sh`) con `roas_vs_marca` **declarado heurístico**.
`followme` = `bash/ads/followme.sh` (visitas al perfil, DMs, likes por dólar
de los follow-me ads + seguidores por foto diaria; `disponible=false` con
motivo si el rol no puede usar `meta`). `manychat.mapa` = solo los tags del
flujo de IG (el API no lista suscriptores ni da conteos; por nombre matchea
14/79 — ver `bash/manychat/README.md`), así que NO cuenta DMs ni setters y lo
dice en `sin_instrumentar`. Agosto DG: 79
orgánicos (32 %) con tasa a plan 11,4 % contra 7,1 % de los pagados.
⚠️ **`cobertura_etapa` manda sobre los conteos de etapa de su fila** y por eso
viaja al lado: poca cobertura significa dos cosas opuestas —no lo trabajaron, o
lo trabajaron sin etiquetar— y sin declararla una falla de proceso se lee como
conclusión sobre el canal. Medido jul+ago: la serie de YouTube trae 143 leads
con **7 % de cobertura** y 3 ganadas, mientras «sin formulario» (el DM puro, el
que no deja llave) trae 33 con **97 %** y 7 ganadas — el canal de más volumen es
el que nadie califica. La cobertura del 97 % puede ser artefacto (si el
confirmador crea el contacto ya etiquetado), y la página lo dice. Read-only
(+ un GET a ManyChat si hay `MANYCHAT_TOKEN_DG`/`_B`). Fuente viz
`embudo_organico` → page `organico` (UI ejecutivo `embudo-organico`).

## Testeos domain — el histórico de testeos del embudo ([bash/testeos/](bash/testeos/))

El registro que la alineación DG 2026-08-19 dejó como acuerdo: cada testeo del
embudo con sus **métricas iniciales y finales congeladas** (snapshots de
`bash/metrics/embudo.sh` con procedencia — no se digitan) y su desenlace.
Vive en **Postgres** (`ikigaigm.testeos`, migración
`catalog/migrations/006_testeos.sql`; nació sqlite y se graduó el mismo día)
porque **los testeos los crean y monitorean los copilotos del rol Ejecutivo**
(Juan Camilo y Lorenzo) y un histórico compartido no puede vivir en la sqlite
de una máquina. `abierto_por`/`cerrado_por` salen del `copilot.json` del fork
(`cerebro` si no hay). ⚠️ **En un fork de rol distinto de `ejecutivo` el
bloque VSL del snapshot viene con error declarado** (`bash/vturb` se niega por
rol, `bash/lib/acceso.sh`): los testeos con métrica `vsl.*` se abren desde el
cerebro o desde un copiloto ejecutivo hasta que el fallback vía el proxy Mkt
exista (`apis/mkt/vturb-video.openapi.json` ya expone analytics; ojo al
bug de retención del normalizador de Marketico, ver `bash/vturb/README.md`).
Las dos disciplinas de la reunión van en el diseño:
**un solo cambio por testeo** (`--variable` es singular y obligatoria) y
**un testeo por step** (`testeo_abrir.sh` se niega si ya hay uno `en_curso`
en ese step+proyecto; `--forzar` para la excepción consciente).

| Script | Use it to… |
|--------|-----------|
| `testeos.sh [--estado E] [--step S] [--project N] [--limit N]` | El histórico como filas (id corto, variable, métrica, inicial→final, Δ, resultado). Read-only; alimenta la fuente viz `testeos` (UI ejecutivo `testeos-embudo`, componente `table`). |
| `testeo_abrir.sh --project N --step S --variable "…" [--hipotesis] [--metrica RUTA] [--nota] [--forzar] [--dry-run]` **[WRITE local]** | Abrir un testeo congelando el embudo AHORA como línea base. `--metrica` es ruta punteada dentro del snapshot (`kpis.roas_real`, `vsl.total.tasa_play`, `pauta.0.ctr`); si el embudo no responde, NO se abre. Steps: titular·hook_vsl·survey·pagina·pauta·remarketing·otro. |
| `testeo_cerrar.sh <id\|prefijo> --resultado gano\|perdio\|inconcluso [--decision] [--abortar] [--dry-run]` **[WRITE local]** | Cerrar con snapshot final y Δ de la métrica. El resultado lo declara el humano (el Δ informa, no decide). `--abortar` = testeo contaminado, sin snapshot final. Un cierre no se reescribe. Id por prefijo (se dicta en conversación). |

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
| `cohorte_mora.sh --project N [--desde D] [--hasta D] [--contexto]` | **La cohorte en mora, por estudiante**: planes iniciados en la ventana (cohorte = `start_date`, default feb–mar 2026) con al menos una cuota vencida sin pagar — pendiente, cobrado, en qué cuota se frenó, días de mora **desde `due_date`** (el status jamás escribe Overdue), contacto del CRM (correo/teléfono: tener fila no es tener canal), closer, y el **segmento de reactivación por reglas declaradas** (S1 ≤30 d · S2 ≤90 d · S3 pagó ≥50 % · S4 el resto — verificadas contra el plan de 9f249dbe: 2/7/12/14). `--contexto` = una fila por cohorte mensual (alumnos, en mora, %) para leer la cohorte en su contexto: toda cohorte madura vive en 43–62 % de impago. Entregable de la tarea 9f249dbe. Fuente viz `cohorte_mora` → page `plan-reactivacion` (UI publicada `plan-reactivacion-feb-mar`). |
| `ventas_diarias.sh --project N [--from D] [--to D]` | **La serie diaria**: una fila por día (termina HOY, no inventa días) con caja (nuevas = cuota 1 / cuotas n≥2, por `payment_date` día Bogotá), pauta **solo USD** del día, `roas_dia` = cash/pauta del MISMO día (ritmo, no atribución), leads y ganadas CRM, planes iniciados + contrato. Default mes en curso. Nació del hueco #1 del contraste con el dashboard comercial (2026-08-21): el Cerebro solo tenía series mensuales. Feeds la fuente viz `ventas_diarias` → page `ventas-diarias` (UI ejecutivo `ventas-diarias`: KPIs mejor día / promedio / por día de la semana + cash vs pauta diario). |

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
  as gaps and filled by the Mastermind pilot), 36 SOPs, 78 archetypes
  `{id, sop, verb, name, slots[]}`. Every SOP has ≥1 archetype.
- **DB tables** (`ikigaigm`, seeded from the JSON): `macro_processes`, `sops`
  (→macro_processes), `activity_archetypes` (→sops, +`embedding extensions.vector(1536)`
  for the future matcher), `archetype_params`, and the template-contract tables
  `archetype_inputs`/`archetype_outputs`/`archetype_acceptance_criteria` (an
  archetype = a task template with declared I/O+criteria; **60 of the 78 archetypes
  already carry one** — S5 Testimonios was the first authored, the Mastermind pilot
  wrote the rest; the 18 without a template are listed in the meeting-to-tasks
  skill). Template contracts are declared in the catalog JSON per archetype and
  seeded by `sync_catalog.sh`. ⚠️ `create_task.sh` leaves **unfilled `{slots}`
  literal** (unlike `materialize_io.sh`, which neutralizes them) — always pass
  `slots`, including `proyecto`.
- ⚠️ **Los slots son un hueco de diseño abierto, no un detalle de formato.**
  Hay **tres** sustituidores con dos comportamientos incompatibles, y los
  **valores de los slots no se persisten en ninguna parte** — se hornean en el
  texto al instanciar, así que toda re-instanciación (merge, re-tag, corrección
  de plantilla) los pierde. Ya costó: el merge PM↔cerebro degradó 16 contratos
  que estaban llenos, y el daño se concentra en los **criterios de aceptación**
  (un criterio con `«pendiente»` es inverificable, no solo feo). El socket
  (`archetype_params` con `type`/`enum_options`) existe y está **vacío: 120
  params, todos `text`**. Antes de tocar plantillas, instanciación o
  `set_archetype.sh`, leer
  `docs/plantillas-slots-brief.md` (operador) — evidencia,
  mecanismo y las preguntas de diseño abiertas.
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
| `cruce_mark.sh <n> [--merge 0\|1] [--resuelta 0\|1] [--resolucion T]` **[WRITE]** | Curation marks on ONE row of `pm_platform.cruce` (the PM↔cerebro reconciliation). The only write behind the viz `cruce` UI's Merge button; guardrail: merge only on `igual`+`alta` unresolved rows. The marked set is what `bash/tasks/merge_from_cruce.sh` executes. |

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
that role's spec layer — or every role's, when `docs/roles/acceso.json` says
`uis:"*"` for it (today: `technology`), or exactly the layers it lists (today:
`ejecutivo` = `["ejecutivo","director-comercial"]`, so the CEO/COO see the
sales team's UIs; the map is read at viz start → `viz:restart` after pull) —
and stamps `owner`/`role` on everything created. The brain (no copilot.json) sees org + all roles. That
same file's `dominios` key is what `bash/lib/acceso.sh` reads, and its
`tablas` key is what forja's `crear_alta.sh` turns into Postgres tiers
(`"*"` → `ikigai_tier_total`, every table read-only — today ejecutivo and
technology, migration `007_tier_total.sql`): **one map, three consumers**
(`docs/roles/README.md`).
Everything a copilot writes lands in `viz/specs/local/` and auto-commits —
git IS the telemetry; structure is observed, content never. Structural
changes propose themselves by push; governance reviews and, when approved,
promotes a spec into `org/` or `roles/<rol>/` with `promoted_from` lineage.
Each fork's own CLAUDE.md/copilot.json belongs to that copilot — never edit
them from the brain.
**Voz del copiloto** (plantilla `identidad-copiloto/` de la forja, desde
2026-08-21): al humano se le habla en el idioma de su trabajo — **nunca se le
muestran rutas, scripts, comandos, flags ni tablas**; se nombra el QUÉ («el
embudo del mes, de la pauta a la caja»), jamás el CÓMO (`embudo.sh --project …`).
Este CLAUDE.md es el manual del motor, no el guion de la conversación. La
regla vive en `identidad.md` y `actualizar_flota.sh` la re-sincroniza en los
forks vivos cuando la plantilla cambia.

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
- **viz is the VIEWER; the editor is the conversation with the brain.** The IO
  editor's write path predates that rule and stays, but nothing new gets one:
  when a view needs to become editable, the write goes into a `bash/` script and
  a skill, and the panel's job is to render the state **plus the row's short id**
  — the handle the user dictates. Acceptance criteria were the first thing built
  this way (read-only under their output in the panel, edited via
  `update_task_criteria.sh` / `revisar-tarea-io`).

**Operating rules** (Datastar colon syntax, caching policy, manifest contracts,
required loaders, store details) live in [viz/CLAUDE.md](viz/CLAUDE.md) —
auto-loaded when working under `viz/`. Architecture narrative + component
catalog: [viz/README.md](viz/README.md).

## Intercepciones domain — procesos de Marketico observados ([bash/intercepciones/](bash/intercepciones/))

La **segunda operación de Marketico interceptada** (la primera fue el reporte
de llamada): el webhook de agendamiento GHL→`/webhooks/crm`. Dos piezas
complementarias, ambas vivas desde 2026-08-17: **auto-reporte** — Marketico
(`src/services/cerebroReporter.js` en su repo) POSTea el desenlace de cada
`processBooking` a `viz/hooks.js` (pm2 `viz-hooks`, puerto 4319 loopback,
nginx `app.ikigaigm.parallelo.ai/hooks/crm-resultado`, Bearer `HOOKS_TOKEN`);
y **verificación independiente** — pm2 cron `intercepciones-cron` (minuto 17
de cada hora) corre `reconciliar_agenda.sh`: meetings de la DB vs Appointments
vivos de GHL por cada `crm_calendars` activo, misma ventana en ambos lados,
todos los status. Todo escribe en la sqlite `intercepciones.db` del servidor
api (estado propio del interceptor, patrón `publicaciones.db`); los scripts de
consulta son **local-first + ssh** (la db local si existe, si no `root@api`).
Spec: `docs/superpowers/specs/2026-08-16-intercepcion-webhook-crm-design.md` (operador).

| Script | Use it to… |
|--------|-----------|
| `log.sh [--desde D] [--solo-errores] [--limit N]` | El log del webhook: qué reportó Marketico de cada `/crm` (ok/error, paso, duración). |
| `drift.sh [--historia]` | Drift de agenda **vigente** (última corrida ok por calendario); `--historia` lista corridas. |
| `resumen.sh` | Un objeto: KPIs 24h/7d del webhook + últimas corridas + drift — la fuente de la UI. |
| `reconciliar_agenda.sh [--desde N] [--hasta N] [--dry-run] [--json]` **[WRITE sqlite]** | La reconciliación a mano (el cron la corre sola cada hora). |
| `bash/ghl/appointments.sh (--project F\|--project-id U) [--calendar ID] [--desde N] [--hasta N]` | La sonda GHL de calendario (Version 2021-04-15, epoch millis) que alimenta la reconciliación. |

Reglas que sostener: **GHL caído ≠ agenda vacía** (corrida `estado='error'`,
jamás drift inventado); `scheduled_start_time` se compara por **reloj literal**
(el quirk Bogotá-como-UTC); solo meetings `scheduled` pueden dar `sobra_en_db`
/ `horas_difieren` — un status vivo con par en GHL cuenta como `coinciden`.
Viz: fuentes `intercepciones_resumen`/`_log`/`_drift`, UI org `intercepciones`.
Fase actual: **observar** — ni alerta ni repara (eso se gana con datos).

## Publicar domain — UIs publicadas ([bash/publicar/](bash/publicar/))

El **publicador** es `viz/publish.js` corriendo en el servidor `api` desde
`/apps/hermetico` (pm2 `viz-publish`, puerto 4318 solo en loopback, nginx+TLS
en **https://app.ikigaigm.parallelo.ai**). Es un entrypoint aparte del viz, con
superficie mínima por construcción: sirve **solo** las UIs registradas, con
datos vivos, login contra Marketico (JWT verificado localmente con el mismo
`JWT_SECRET`) — no existen el shell, la creación/edición de UIs ni los `acts`.
Rutas: `GET /<slug>` · `/s/<codigo>` (alias corto) · `/ui/<slug>` (SSE) ·
`/u/<slug>` · `/login` · `/logout` · `/health`.

| Script | Use it to… |
|--------|-----------|
| `publicar_ui.sh <spec-id> --slug S [--identidad k=v]… [--fijar k=v]… [--archivar] [--dry-run] [--json]` **[WRITE remoto]** | Publicar (o re-publicar) un spec del viz como despliegue. `--identidad` declara la plantilla; `--fijar` clava params; `--archivar` despublica. |
| `permiso_ui.sh <slug> --rol R \| --user EMAIL [--identidad k=v]… \| --sin-identidad [--revocar] [--listar] [--visitas]` **[WRITE remoto]** | Dar/quitar acceso y ver quién entró. `--listar`/`--visitas` siempre emiten JSON. |
| `desplegar.sh [--dry-run]` **[WRITE remoto]** | Llevar el CÓDIGO al publicador: push a `origin`, `git pull --ff-only` en `/apps/hermetico` y `pm2 restart viz-publish`. No toca el registro. |

**Permisos — tres estados de `params_identidad`**, y entre varios roles gana el
**menos restrictivo** (un permiso por `--user` siempre gana sobre los de rol):
`NULL` = *hereda* la plantilla de identidad del despliegue (el closer se ve solo
a sí mismo) · `'{}'` = *anula* la plantilla, ve todo (el Director Comercial) ·
json explícito = fuerza esos valores (la excepción). Sin permiso que matchee,
la respuesta es el **mismo 404** que un slug inexistente — no se filtra qué
existe.

**Plantilla de identidad**: `--identidad 'closer=$name'` guarda la plantilla, no
el valor; en cada visita `$name`/`$email`/`$user_id` se resuelven contra el JWT
del visitante y los params resueltos se aplican **al final** (spec → fijos →
overrides del navegador → forzados), así que la query string no los puede pisar
y el control del param sale bloqueado en la UI.

**El spec viaja CONGELADO**: publicar guarda un snapshot del spec, y re-publicar
inserta `generación+1` — nunca sobreescribe ni borra (archivar sella). Editar la
UI en el viz **no** cambia lo publicado hasta que se vuelva a publicar.

**v1 = solo UIs autosuficientes**: `/c/` (frags/acts de los bloques) no se monta,
así que un componente que dependa de fragmentos enrutados no se publica todavía.
Ver `docs/viz-publish-fragmentos.md` (operador).

⚠️ **Excepción declarada al rail de «nada de SQL fuera de `bash/`»**: el registro
del publicador (`data/sqlite/publicaciones.db` — despliegues, permisos, visitas)
es **estado propio del publicador**, no dato de la org, y por eso estos scripts
sí llevan SQL (sqlite, por ssh y por stdin, nunca en el argv del remoto). Los
datos de la org siguen entrando únicamente por `bash/ --json`.


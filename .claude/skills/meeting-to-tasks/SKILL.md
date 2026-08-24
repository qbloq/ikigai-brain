---
name: meeting-to-tasks
description: Turn a team meeting's report action items into full task "work contracts" (task + inputs + outputs + acceptance criteria) for review and insertion. Use when the user wants to derive tasks from a meeting, convert action items into tasks, or "process"/"ingest" a team meeting into the task system.
---

# Meeting → Task Contracts

Convert the **action items** of a team meeting's report into proposed task
**work contracts**, let the user review them, then insert the approved ones.

This skill covers **Stages 2–3** of the pipeline: the report (Stage 1) is assumed
to already exist in `meeting_reports`. It does **not** generate the report.

Background model (read if unsure): [tasks-system.md](../../../docs/tasks-system.md),
[task-io-validation.md](../../../docs/task-io-validation.md) (the I/O + artifact
model; its companion [task-io-validation-impl-status.md](../../../docs/task-io-validation-impl-status.md)
says what is actually built), [task-criteria-review.md](../../../docs/task-criteria-review.md).

## Input
A meeting id or prefix (e.g. `32a519c9`). If the user names a meeting loosely,
find it with `bash/meetings/meetings.sh --has-report`.

## Workflow

### 1. Fetch the meeting + report
```
bash/meetings/meeting_show.sh <id>          # header: project, scheduled date, status
bash/meetings/meeting_show.sh <id> --json   # raw report jsonb (actionItems live here)
```
Note the **project** and the **meeting date** — both are needed below.

> **Prefer the discovery sidecar.** If
> `backups/meeting-reports/<meeting-id>.discovery.md` exists (produced by the
> [transcript-to-report](../transcript-to-report/SKILL.md) skill), use it as the
> source of action items: it already carries resolved canonical owners, an
> estimated `dueDateISO`, the SOP/archetype mapping, and a transcript evidence
> anchor per item — so you don't re-guess owners/dates. Fall back to the raw
> report `actionItems` only when no sidecar is present.

### 2. Build one contract per action item
Each `actionItems[]` entry becomes a task contract. Map fields:

- **title** ← the action item `task` text (clean it up; imperative, concrete).
- **project** ← the **per-task project from the sidecar** (`project` column), NOT
  the meeting's project. Team meetings (mostly tagged Ikigai = the agency) span
  clients: route each task to David Guerrero / Andrea Torres / Floppy by content,
  keep only genuinely internal work under Ikigai, and ask on `⚠️ undecided`.
- **priority** ← the item `priority` (`High`/`Medium`/`Low`).
- **assignee** ← resolve the free-text `assignedTo[]` nicknames to **canonical
  team-member names** using the nickname map below. Pass canonical names (e.g.
  `"David Castaño"`), not nicknames. Drop generic mentions ("Equipo de Ventas", "N/A").
  For the three **ambiguous roster names** (Mateo Restrepo · Luis David Flórez ·
  David Guerrero — see the map) pass the **id prefix** instead of the name, or
  `create_task.sh` aborts on the ambiguity.
- **external collaborators** (people not in the Ikigai roster — e.g. Alex, Sara)
  are **never assignees**. Instead, add a `comments[]` entry naming the external
  and the **specific input expected from them**, and make sure **one of the task's
  team-member assignees coordinates** with them (say who in the comment). The task
  stays owned by a team member who chases the external. Example:
  `{"text":"Coordinar con Alex (externo, dueño de la herramienta de métricas): se espera una página/módulo para el orgánico que integre las conversaciones. Coordina: Luis David Flórez."}`
- **due_date** ← **REQUIRED, never null.** Always produce a `YYYY-MM-DD`. The
  agentic system uses this date to follow up on the deliverable and chase the
  responsible person, so a task without a date is invisible to it. See the
  estimation policy below.
- **source_meeting** ← the meeting id (for provenance).
- **archetype** ← carry the archetype id from the discovery sidecar (e.g. `A2.4`)
  into the contract so the task is born tagged to its SOP. Validate it exists in
  `catalog/sop-archetypes.json` (12 macros S1–S12 · 36 SOPs · 77 archetypes; S11
  Producto and S12 Cierre/Retención are no longer gaps — the Mastermind pilot
  filled them). If the sidecar marked the item a `gap` (no archetype), leave
  `archetype` out and add a `comments[]` note proposing the new archetype for the
  catalog tail. `create_task.sh` persists it to `tasks.archetype_id` and rejects
  an unknown id.
- **inputs / outputs** ← **template instantiation is the default path now.** 59 of
  the 77 archetypes carry a template contract (only `A1.4 A3.5 A4.3 A4.5 A4.6 A6.2
  A6.6 A7.2 A7.5 A8.6 A9.3 A10.1 A10.3 A10.4 A11.4 A12.1 A12.3 A12.4` don't —
  verify with the catalog JSON). When the matched archetype has one, **omit
  `inputs`/`outputs`** and pass `archetype` + `slots`; `create_task.sh` pulls
  `archetype_inputs/outputs/acceptance_criteria` and substitutes the `{slots}`.
  - ⚠️ **Unfilled slots stay literal.** `create_task.sh` leaves an unmatched
    `{placeholder}` verbatim in the title/description (unlike `materialize_io.sh`,
    which neutralizes them to «pendiente»). Read the archetype's `slots[]` in
    `catalog/sop-archetypes.json` and fill **all** of them — **always including
    `proyecto`**, which nearly every template description interpolates.
  - Only when the archetype has no template (or the fit is poor) infer I/O by
    hand: pick the semantic **io_type** that fits (see catalog below; confirm with
    `bash/tasks/io_types.sh`). Most tasks have 1 main output; add inputs only when
    the work genuinely needs a prerequisite artifact. Keep references unbound —
    binding an output to a concrete Drive/SQL artifact happens later (the viz IO
    editor, `update_task_io.sh --ref-merge`, `bind_io_notion.sh`).
- **acceptance criteria** (per output) ← 2–4 concrete, verifiable statements.
  Choose `verification_method` with the rules below and a `criterion_category`
  of `completeness` | `quality` | `format` | `accuracy`.

### 3. De-duplicate against existing tasks
Before proposing, check the open tasks of **every project the batch touches** —
not just the meeting's — because per-task routing regularly lands two meetings'
items on the same work in different projects (memory `cross-project-dedup-gap`):
```
bash/tasks/tasks.sh --project "<project>" --open --limit 0     # once per routed project
bash/tasks/tasks.sh --open --limit 0                            # cross-project sweep
```
Also dedup **by archetype**, not just by title: two differently-worded items
tagged the same `A_.__` for the same project+owner are usually the same work.
The DB now carries provenance (`source_type`/`source_meeting_id`/`source_url`),
so a Notion-ingested twin of a meeting commitment is a real possibility — check
before creating.

Three outcomes, none of them silent:
- **new** → propose the contract.
- **already exists** → skip it, and record the cross-reference on the existing
  task: `bash/tasks/add_comment.sh <id> --text "…" ` (mentioning this meeting).
- **duplicate found among existing tasks** → propose a merge:
  `bash/tasks/cancel_task.sh <dup-id> --into <keep-id> --reason "…"` (nothing is
  deleted; both ends get an auditable comment). Never merge without asking.

### 4. Propose for review
Write a proposal the user can edit and save it to
`backups/meeting-tasks/<meeting-id>.md`. Use the two-section shape the corpus
settled on:
- **§A — proposed contracts**: one block per task — title, project, priority, due
  (flag `(est.)`), assignee, archetype (+ slots, or a note when the fit is
  imperfect), inputs/outputs/criteria with their `verification_method`, and the
  evidence anchor.
- **§B — held for your call**: items that are too logistical to be tasks, likely
  duplicates/merges, or `⚠️ undecided` project routing — each stated as a concrete
  question. Close with a **Notes carried from Stage 1** block (owner-resolution
  caveats, archetype gaps worth adding to the catalog tail).

**And its structured twin.** Alongside the `.md`, write
`backups/meeting-tasks/<meeting-id8>.json` — the same proposal as data, which
is what the viz «Revisión de propuestas» UI loads (`propuesta_cargar.sh`):
`{meeting, meeting_corto, fecha, nombre, md, propuestas[]}` where each §A entry
is `{ref, seccion:"A", contrato:{…exact create_task.sh shape…}, vence_estimada,
evidencia, comentario, relacionadas:[id8…], depende_de:[ref…]}` and each §B
entry is `{ref, seccion:"B", contrato:null, titulo, pregunta, accion_sugerida,
relacionadas, depende_de}`. The `.md` is for the human; the `.json` is the
contract — validate every §A `contrato` with `create_task.sh - --dry-run`
before saving. The two files must agree (same refs, same count).

Wait for approval; apply edits.

### 5. Write the approved contracts
For each approved contract, write the JSON and **dry-run first**, then commit:
```
bash/tasks/create_task.sh <contract.json> --dry-run   # verify counts
bash/tasks/create_task.sh <contract.json>             # writes in a transaction
```
`create_task.sh` pre-validates project/assignees/io_types and inserts task +
inputs + outputs + criteria (+ a provenance comment) atomically. `source_meeting`
also sets the structured provenance (`source_type='meeting'` + the
`source_meeting_id` FK), which is what makes this batch auditable later. See its
`-h` for the exact contract shape.

### 6. Verify and repair (after writing)
```
bash/tasks/task_show.sh <id>            # header + I/O + criteria + comments as written
```
Fix in place rather than re-creating — the repair tools are one-op, transactional
and `--dry-run`-able:
- wrong/missing archetype → `bash/tasks/set_archetype.sh <id> <A_.__> --method human`
- wrong I/O row (type, title, required, add/delete) → `bash/tasks/update_task_io.sh`,
  or run the interactive `/revisar-tarea-io <task-id>` skill with the user.
- something to record without changing structure → `bash/tasks/add_comment.sh`.

Finally, report the batch: N created (with ids), N skipped as duplicates, N held
in §B awaiting the user's call.

## Reference

### io_types (semantic types — use these names)
`bash/tasks/io_types.sh` is authoritative (18 types today). Common picks:
- **document**: `content_draft` (copy/scripts), `strategy_document`, `video_asset`,
  `audio_asset`, `ad_creative`, `image_asset`, `documentation`, `meeting_report`,
  `transcript`, `message_or_communication`.
- **data**: `analytics_report` (dashboards/metrics), `system_configuration`
  (build/config work — deliverable is "the system now does X"), `schedule_event`.
- **resource**: `credentials_access` (access grants — never store secrets),
  `team_member`, `contact_info`.
- **decision**: `decision`. **approval**: `task_approval`.

### due_date estimation (mandatory — never leave null)
Anchor on the **meeting date** and resolve the report's `dueDate` text:

| `dueDate` says | Resolve to |
|---|---|
| "Hoy" / "Inmediato" / "Ya" | meeting date |
| "Mañana" | meeting date + 1 |
| "Esta semana" | the Friday of the meeting's week |
| "Próxima semana" | the Monday of next week |
| "Fin de mes" | last day of the meeting's month |
| "Siguiente mes" / "Próximo mes" | last day of next month |
| a concrete date | that date |
| **vague** ("Lo antes posible", "En curso", "Continuo", "No especificado", "Pronto", missing) | **meeting date + priority offset** |

**Priority offset** (for vague/ongoing items): `High` → +3 days · `Medium` → +7 days · `Low` → +14 days.

Always sanity-check: the estimate must be **on or after the meeting date**. When
you estimate (vs. parse an explicit date), say so in the proposal so the user can
correct it.

### verification_method — how to pick (from task-criteria-review.md)
- **attested** — opaque human/3rd-party action the system can't inspect: a
  message/audio was *sent*, access was *granted*, an opaque tool (Meta Ads, VTurb,
  Biturbo, WhatsApp communities) was *configured*. Default for "sent/shared/activated".
- **llm** — semantic compliance of an inspectable artifact: "the doc covers X",
  "the copy follows the approved narrative".
- **automated** / **test** — deterministic checks: file present, valid format,
  a status flag flipped.
- **manual** — a human must eyeball it but it isn't an external attestation.

When in doubt between llm and attested: if the artifact's *content* isn't stored
in our system (it lives in someone's inbox / an opaque tool), use **attested**.

### Nickname → canonical team member  (see memory `nickname-to-team-member-map`)
Bala→David Castaño · Jota/Jona→Jhonatan Rengifo · Sophie→Sofia ·
Santi→Santiago Ruiz · Juanca→Juan Camilo Correa · Mari→Marisol Ochoa ·
Andrés→Andrés Alzate · Mateo→Mateo Restrepo · Pablo→Pablo Gaviria ·
Toño/Tony→Tony Vidal · Lucho→Luis David Flórez · Loro/Lorenzo→Lorenzo Cadavid
(Ejecutivo, escribe VSLs) · Robert/Roberto→Roberto Maestre (Operaciones).

⚠️ **Franco ≠ Francisco** (user-verified 2026-07-02): **Franco** is an
underperforming *closer* (not in the roster — never an assignee), **Francisco /
Cisco** is **Francisco Otalvaro**, *Líder de servicio* (cuotas/retención).

⚠️ **Paralelo** work (the app/dashboard vendor; "Santiago Gaviria" is theirs)
routes to **Pablo Gaviria** (Technology), their contact at Ikigai. Not Santi.

⚠️ **Ambiguous — pass the id prefix, not the name** (`resolve_member` aborts):
**Mateo Restrepo** `637277b5` / `dd4621c1` (both Setter/Ikigai — ask which) ·
**Luis David Flórez** `ece00919` (Director Comercial — the usual one) vs
`81d4bc8e` (Closer/Closers) · **David Guerrero** `89ce896e` (Closer/Ikigai) vs
`a193bc8b` (**Cliente** — the "David" who records content, and the id to use for
talent tasks).

If a nickname is unknown, ask — don't guess.

## Principles
- **Propose, then write.** Never insert without review. Always `--dry-run` first.
- **Ground every type** in `io_types`; don't invent io_type names.
- **One transaction per task** via `create_task.sh` — partial writes can't happen.
- **Conservative inputs.** Only add an input if the task truly can't start without it.

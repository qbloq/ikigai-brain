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
[task-io-discovery.md](../../../docs/task-io-discovery.md),
[task-criteria-review.md](../../../docs/task-criteria-review.md).

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
  `catalog/sop-archetypes.json`. If the sidecar marked the item a `gap` (no
  archetype), leave `archetype` out and add a `comments[]` note flagging it as a
  candidate for a new archetype (S11/S12). `create_task.sh` persists it to
  `tasks.archetype_id` and rejects an unknown id.
- **inputs / outputs** ← **if the matched archetype has a template contract**
  (e.g. S5 Testimonios), prefer **instantiating** it: omit `inputs`/`outputs` and
  pass `archetype` + `slots` (e.g. `{"cantidad":"14","talento":"David"}`);
  `create_task.sh` pulls the template and substitutes the `{slots}`. Otherwise
  infer them: use the semantic **io_type** that best fits (see catalog below;
  confirm with `bash/tasks/io_types.sh`). Most tasks have 1 main output; add inputs
  only when the work genuinely needs a prerequisite artifact. Keep references unbound.
- **acceptance criteria** (per output) ← 2–4 concrete, verifiable statements.
  Choose `verification_method` with the rules below and a `criterion_category`
  of `completeness` | `quality` | `format` | `accuracy`.

### 3. De-duplicate against existing tasks
Before proposing, check the project's open tasks so you don't recreate one:
```
bash/tasks/tasks.sh --project "<project>" --open --limit 0
```
Skip (or flag) action items that clearly already exist as a task. Note skips
explicitly — never silently drop.

### 4. Propose for review
Write a proposal the user can edit, one section per contract: title, assignee,
priority, due, and the inferred inputs/outputs/criteria with their methods. Save
to `backups/meeting-tasks/<meeting-id>.md`. Wait for approval; apply edits.

### 5. Write the approved contracts
For each approved contract, write the JSON and **dry-run first**, then commit:
```
bash/tasks/create_task.sh <contract.json> --dry-run   # verify counts
bash/tasks/create_task.sh <contract.json>             # writes in a transaction
```
`create_task.sh` pre-validates project/assignees/io_types and inserts task +
inputs + outputs + criteria (+ a provenance comment) atomically. See its `-h`
for the exact contract shape.

## Reference

### io_types (semantic types — use these names)
`bash/tasks/io_types.sh` is authoritative. Common picks:
- **document**: `content_draft` (copy/scripts), `strategy_document`, `video_asset`,
  `audio_asset`, `ad_creative`, `image_asset`, `documentation`, `meeting_report`,
  `message_or_communication`.
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
Bala→David Castaño · Jota/Jona→Jhonatan Rengifo · Franco→Francisco Otalvaro ·
Sophie→Sofia · Santi→Santiago Ruiz · Juanca→Juan Camilo Correa · Mari→Marisol
Ochoa · Andrés→Andrés Alzate · Mateo→Mateo Restrepo · Pablo→Pablo Gaviria ·
Toño/Tony→Tony Vidal · Lucho→Luis David Flórez · Loro/Lorenzo→Lorenzo Cadavid
(Ejecutivo, escribe VSLs) · Cisco→Francisco Otalvaro · Robert/Roberto→Roberto
Maestre (Operaciones). The client "David" who records
content = David Guerrero (Cliente). If a nickname is unknown, ask — don't guess.

## Principles
- **Propose, then write.** Never insert without review. Always `--dry-run` first.
- **Ground every type** in `io_types`; don't invent io_type names.
- **One transaction per task** via `create_task.sh` — partial writes can't happen.
- **Conservative inputs.** Only add an input if the task truly can't start without it.

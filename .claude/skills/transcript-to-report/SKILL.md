---
name: transcript-to-report
description: Regenerate a team meeting's structured report (the canonical Spanish jsonb) from its raw transcript, with a powerful evidence-grounded task-discovery pass, then REPLACE it in the DB. Use when the user wants to (re)generate a meeting report, rebuild a report from the transcript, or refresh/overwrite a meeting's report.
---

# Transcript → Report (Stage 1)

Turn a team meeting's **raw transcript** into the **canonical structured report**
(jsonb, Spanish) and **upsert it into the DB, replacing any existing report
without looking back**.

This is **Stage 1** of the pipeline. It is the upstream sibling of
[meeting-to-tasks](../meeting-to-tasks/SKILL.md) (Stages 2–3): the quality of the
`actionItems` produced here is the seam that feeds task creation, so discovery is
done with care (see §3).

Background (read if unsure): [tasks-system.md](../../../docs/tasks-system.md),
[role-sops-discovery.md](../../../docs/role-sops-discovery.md) (the S1–S10
macro-process spine), [activity-archetypes.md](../../../docs/activity-archetypes.md)
(the A_.__ atomic activities).

## Input
A meeting id or prefix (e.g. `32a519c9`). Find it loosely with
`bash/meetings/meetings.sh --has-transcript`. The meeting MUST be a **team**
meeting with a transcript.

## Workflow

### 1. Fetch transcript + context
```
bash/meetings/meeting_show.sh <id>          # project, scheduled date, status, participants
bash/meetings/meeting_transcript.sh <id>    # the raw diarized text (Speaker A/B/…)
```
Note the **project** and the **meeting date** — both anchor the report
(`meetingContext.date`) and the due-date estimation downstream.

> **Per-task project routing (important).** The meeting's `project` is NOT the
> project of every task. Most team meetings are tagged **Ikigai** — the agency —
> and coordinate work across clients. Treat `Ikigai` as the **internal/agency
> bucket only** (Paralelo/S11, team & role ops, Ikigai's own-brand marketing).
> Route each task to its **real project inferred from content** — David Guerrero /
> Andrea Torres / Floppy when a client/brand/offer is named; **Ikigai** only when
> the work is genuinely internal; **flag** when undecidable (never assume). A
> single meeting can yield tasks for several projects. This lives as a `project`
> column per item in the sidecar (§4).

If there is no transcript, stop and tell the user — there is nothing to generate from.

### 2. Generate the report — canonical schema (be faithful)
Produce ONE jsonb object in Spanish with **exactly these 14 keys** (the whole
corpus uses this shape; `upsert_report.sh` rejects a report missing any of them):

| key | shape |
|---|---|
| `reportTitle` | string |
| `reportSubtitle` | string |
| `executiveSummary` | string |
| `meetingContext` | `{date, duration, meetingType, participants[]}` |
| `meetingObjectives` | `{stated, achieved, unresolved}` |
| `keySubjectAreas` | `[{topic, description}]` |
| `discussionPointsAndDecisions` | `[{topic, summary, decision, rationale}]` |
| `actionItems` | `[{task, dueDate, priority, assignedTo[], dependencies}]` |
| `criticalIssuesAndBlockers` | `[{issue, status, nextSteps}]` |
| `risksAndConcerns` | `[{risk, mitigation}]` |
| `resourceRequirements` | `{budget, personnel, toolsAndEquipment}` |
| `nextStepsAndFollowUp` | `{nextMeeting, reviewPoints, keyMilestones[]}` |
| `futureConsiderations` | `[string]` (or a string — match what the content needs) |
| `additionalNotes` | `[string]` |

Rules:
- **Spanish**, business-analyst register, same voice as the existing corpus.
- Ground everything in the transcript — never invent decisions, numbers, or names.
- `meetingContext.date` = the meeting date (YYYY-MM-DD). List participants as
  spoken (`"Mari (Speaker A)"`, `"Cristian (mencionado)"`).
- `actionItems[].assignedTo` stays as the **names/nicknames spoken in the room**
  (fidelity to the corpus — do NOT canonicalize here; resolution lives in §3).
- `actionItems[].dueDate` / `dependencies` stay as free-text (as discussed).
- Leave `report_es` alone — the script never touches it (corpus keeps it null).

### 3. Powerful task discovery (two passes, evidence-grounded)
The default LLM summary under-discovers: it merges compound commitments, drops
ones only said in passing, and loses owners. Do better:

1. **Narrative pass** → the 12 descriptive keys above.
2. **Commitment-mining pass over the RAW transcript** → scan the whole text for
   every commitment, not just what made the summary: phrases like *"yo hago / me
   encargo / quedamos en / hay que / toca / para el (fecha) / antes de…"*, plus
   implicit owners. Each becomes a **candidate action item**, **atomic** (one
   deliverable each — split compound ones; e.g. "subir presupuesto" and "llegar a
   la meta $2,000" are two items).
3. **Reconcile** the two passes: union, de-duplicate, drop pure restatements.
   Each surviving item must have a transcript **evidence anchor** (a short
   verbatim quote). If you can't anchor it, it isn't an action item.

The reconciled set is what goes into `actionItems` (canonical free-text form) AND
into the sidecar (resolved form, §4).

### 4. Write the discovery sidecar (the seam to Stage 2–3)
Keep the DB report canonical/clean; emit the resolution metadata to a sidecar at
`backups/meeting-reports/<meeting-id>.discovery.md`. Open it with a **header**
(meeting + date + project + the resolved due-date anchors) and a **speaker map**
(`A = Juanca → Juan Camilo Correa`, plus who was only *mentioned* and is therefore
never an owner) — diarization is the main source of owner errors, so resolve it
once, up front. Then one row per action item (aligned by index to `actionItems`):

| # | task | **project** | assignedTo (spoken) | **owner (canonical)** | **dueDateISO** | priority | **SOP/archetype** | **evidence** |

- **project** ← the real project inferred from the task content (David Guerrero /
  Andrea Torres / Floppy / Ikigai-internal), NOT inherited from the meeting. Flag
  `⚠️ undecided` when the client can't be determined. See the routing rule in §1.

- **owner (canonical)** ← resolve each `assignedTo` against the live roster
  (`bash/tasks/team.sh`) + the nickname map below. Mark unknowns as
  `⚠️ UNRESOLVED` — **never silently drop**.
- **dueDateISO** ← apply the due-date estimation policy below (always a date).
- **SOP/archetype** ← classify the item against the canonical catalog
  `catalog/sop-archetypes.json` (the source of truth — 12 macro-processes S1–S12,
  36 SOPs, 77 `A_.__` archetypes; browse it with `bash/catalog/sops.sh`). Put the
  **archetype id** (e.g. `A2.4`) and its SOP. If nothing fits, mark it
  `gap → nuevo archetype candidato` naming the closest one (never force a bad
  match — the tail grows the catalog). This gives Stage 2–3 a strong prior and is
  persisted on the task (`tasks.archetype_id`).
  > **The mapping now decides the task's I/O.** 59 of the 77 archetypes carry a
  > **template contract** (`archetype_inputs`/`outputs`/`acceptance_criteria`), and
  > Stage 2 instantiates it verbatim via `create_task.sh --archetype + slots`. A
  > sloppy archetype id no longer just mislabels the task — it gives it the wrong
  > deliverables. When a template exists, also note in the sidecar which **slots**
  > it declares (the `slots[]` of the archetype) so Stage 2 can fill them.
- **evidence** ← the verbatim quote anchoring the item.

`meeting-to-tasks` consumes this sidecar (preferring it over the raw report
actionItems) so it never has to re-guess owners or dates.

### 5. Upsert into the DB (replace without looking back)
Always **dry-run first**, then commit:
```
bash/ops/upsert_report.sh <id> <report.json> --dry-run   # shows BEFORE/AFTER, rolls back
bash/ops/upsert_report.sh <id> <report.json>             # INSERT … ON CONFLICT(meeting_id) DO UPDATE
```
The script pre-validates the meeting (exactly one team meeting) and that all 14
canonical keys are present, then upserts in one transaction. An existing report
is overwritten; `updated_at` is refreshed.

## Reference

### due_date estimation (for the sidecar dueDateISO — never null)
Anchor on the **meeting date**, resolve the `dueDate` text:

| `dueDate` says | Resolve to |
|---|---|
| "Hoy" / "Inmediato" / "Ya" | meeting date |
| "Mañana" | meeting date + 1 |
| "Esta semana" | Friday of the meeting's week |
| "Próxima semana" | Monday of next week |
| "Fin de mes" | last day of the meeting's month |
| "Siguiente mes" / "Próximo mes" | last day of next month |
| a concrete date | that date |
| **vague** ("Lo antes posible", "En curso", "Continuo", missing) | **meeting date + priority offset**: High +3 · Medium +7 · Low +14 |

Estimate must be **on or after** the meeting date. Flag estimates as `(est.)`.

### SOP / archetype ontology (for mapping)
**Authoritative catalog: `catalog/sop-archetypes.json`** (also live in the DB:
`ikigaigm.sops` + `ikigaigm.activity_archetypes`; browse with
`bash/catalog/sops.sh [--macro Sx]`). Use its exact codes/ids — do not re-derive
from prose, and do not trust the counts quoted in prose docs: read the JSON.
The spine: **S1** Narrativa & Oferta · **S2** Creativos · **S3** Pauta · **S4**
Orgánico · **S5** Testimonios · **S6** Leads/Setter · **S7** Funnel · **S8**
Métricas · **S9** Lanzamiento · **S10** Gobernanza · **S11** Producto · **S12**
Cierre/Retención. S11 and S12 were originally gaps; the Mastermind ontology pilot
**filled them** (A11.1–A11.4, A12.1–A12.7), so they are ordinary macros now —
map to them normally. Background prose: role-sops-discovery.md,
activity-archetypes.md (older than the JSON — the JSON wins).

### Nickname → canonical team member  (memory `nickname-to-team-member-map`)
Bala→David Castaño · Jota/Jona→Jhonatan Rengifo · Sophie→Sofia ·
Santi→Santiago Ruiz · Juanca→Juan Camilo Correa · Mari→Marisol Ochoa ·
Andrés→Andrés Alzate · Mateo→Mateo Restrepo · Pablo→Pablo Gaviria ·
Toño/Tony→Tony Vidal · Lucho→Luis David Flórez · Loro/Lorenzo→Lorenzo Cadavid
(Ejecutivo, escribe VSLs) · Robert/Roberto→Roberto Maestre (Operaciones).

⚠️ **Franco ≠ Francisco** (user-verified 2026-07-02). In the David Guerrero
meetings **Franco** is an underperforming *closer* (his own person, not in the
roster), while **Francisco / Cisco** is **Francisco Otalvaro**, *Líder de
servicio* (cuotas/retención). Never resolve closer-review items to Francisco
Otalvaro, nor service-delivery/cuotas items to the closer Franco.

⚠️ **Paralelo** (the app/dashboard vendor) — "Santiago Gaviria" is Paralelo, not
Ikigai; its point of contact for Ikigai is **Pablo Gaviria** (Technology), so
"equipo de Paralelo" work routes to Pablo. Note this is *not* Santi (→ Santiago
Ruiz, Contenido).

⚠️ **Ambiguous roster names — pin the id.** Three names resolve to two
`team_members` rows each, and `resolve_member` errors out on them: **Mateo
Restrepo** (`637277b5` / `dd4621c1`, both Setter/Ikigai), **Luis David Flórez**
(`ece00919` Director Comercial/Ikigai vs `81d4bc8e` Closer/Closers) and **David
Guerrero** (`89ce896e` Closer/Ikigai vs `a193bc8b` Cliente/Externos). Write the
id prefix next to the name in the sidecar so Stage 2 doesn't have to re-decide.
The client "David" who records content = David Guerrero **Cliente** (`a193bc8b`).

If a nickname is unknown, mark it `⚠️ UNRESOLVED` and ask the user — don't guess.

## Principles
- **Faithful schema.** Exactly the 14 canonical keys; Spanish; corpus voice.
  `upsert_report.sh` enforces presence.
- **Replace without looking back**, but **dry-run first** every time.
- **Evidence or it isn't an action item.** Every action item is anchored to a
  transcript quote.
- **Resolve in the sidecar, not the DB report.** The DB report stays canonical
  (spoken names); the sidecar carries the resolved owners / ISO dates / SOP refs.
- **Never silently drop** an owner or a commitment — flag unknowns.

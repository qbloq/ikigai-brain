---
name: revisar-tarea-io
description: Interactively review and edit one task's work contract — inputs, outputs, types, required flags AND the acceptance criteria of each output — together with the user, applying each change through bash/tasks/update_task_io.sh and bash/tasks/update_task_criteria.sh. Use whenever the user types /revisar-tarea-io <task-id>, or asks to review/fix/edit a task's IO, inputs, outputs, contract, io_type, artifact_type, criterios de aceptación/validación or how an output gets verified — e.g. "revisemos el IO de la tarea X", "ese output debería ser video_asset", "agrégale un input a la tarea", "ese criterio debería validarse por attested", "agrega un criterio a S1", even without naming the skill.
---

# Revisar / editar el IO de una tarea

A collaborative review session over ONE task's work contract — both halves:
the IO rows (what goes in, what comes out) and the **acceptance criteria** that
say when an output is actually done. Show the current state, then translate the
user's requests into `update_task_io.sh` / `update_task_criteria.sh` calls —
one operation per call, one transaction each — re-rendering after every change.

The viz "Editor de IO" is the **viewer** of this same contract (same read
source), and it renders each output's criteria read-only: **editing them
happens here, in the conversation.** That is why the panel prints each
criterion's short id — it is the handle the user will dictate to you.
Never inline SQL; every write goes through a whitelisted script.

**Interact in Spanish** (the user's language). Script names, io_type names and
JSON stay verbatim.

## Input

A task id or UUID prefix (e.g. `916e19aa`). If the user gave none or a loose
title, find it first:

```
bash/tasks/tasks.sh --open --limit 0            # filter by --project/--assignee as hinted
```

Ambiguous match → show the candidates and ask; don't guess.

## 1. Fetch and render the contract

```
bash/tasks/task_detail.sh <id>                  # ONE JSON object; always JSON
bash/tasks/io_catalog.sh                        # valid io_types + artifact_types
```

`task_detail.sh` is the right read — unlike `task_show.sh` it carries the **row
`id` of every input, output AND criterion** (what `--io` / `--crit` need), plus
each criterion's `output_id`, the archetype and provenance. Keep all those ids
in your context; never show full UUIDs to the user (the 8-char prefix is enough
for the scripts, which resolve prefixes and refuse ambiguous ones).

Render a compact review, numbering rows `E1..` (entradas) and `S1..` (salidas).
Header = title line, then `proyecto · status · priority · vence <due>`, then an
`Asignados:` line (the project is NOT the assignee — don't conflate them), then
the archetype line if present:

```
## 916e19aa — DG-Enviar propuesta para el sistema de testimonios
David Guerrero · in_progress · Medium · vence 2026-05-06
Asignados: Luis David Flórez, Lorenzo Cadavid, Jhonatan Rengifo, Francisco Otalvaro
Arquetipo A5.5 «Estructurar registro de casos de éxito (con trazabilidad financiera)» (S5.3 / S5 Testimonios)

### Entradas
| # | Título | io_type | artefacto | ¿req? | ¿ok? |
|---|--------|---------|-----------|-------|------|
| E1 | Datos de resultados de clientes | Analytics Report | Web URL | sí | ✗ |

### Salidas (con sus criterios)
| # | Título | io_type | artefacto | ¿req? | ¿ok? |
|---|--------|---------|-----------|-------|------|
| S1 | Registro de casos de éxito | System Configuration | Computed Check | sí | ✗ |
  - S1.1 ✗ El registro captura cada caso… (llm)
  - S1.2 ✗ El sistema está operativo y actualizable. (attested)
```

`¿ok?` renders `is_satisfied` (inputs) / `is_delivered` (outputs) as ✓/✗, and
each criterion's ✓/✗ is its `is_met`. Criteria arrive as a flat array carrying
`output_id` — **group by that, never by the `output` title** (two outputs can
share a title). Number them `S<n>.<m>` so the user can point at one without an
id, and keep the mapping `S1.1 → criterion id` in your context.

Close the render with your own read: does the contract make sense for this task
and its archetype? Point out anything off (an output typed `documentation` that
is clearly a video, a task with no output, an input that isn't a real
prerequisite) as **suggestions** — the user decides. If the archetype has a
template contract (see `catalog/sop-archetypes.json`), a divergence from it is
worth mentioning, not auto-fixing.

## 2. Edit loop

For each change the user asks for, run exactly **one** script call, then confirm
from its before/after output. Map natural language → mode:

**IO rows** (`update_task_io.sh`):

| User says | Call |
|---|---|
| renombrar E1 / cambiar el título | `update_task_io.sh --io <id> --title "…"` |
| "eso es un video", cambiar tipo | `update_task_io.sh --io <id> --io-type video_asset` |
| cambiar el artefacto | `update_task_io.sh --io <id> --artifact storage_file` |
| hacerlo opcional / requerido | `update_task_io.sh --io <id> --required false` |
| agregar un input/output | `update_task_io.sh --add input\|output --task <task-id> --title "…"` then usually a second call to type it |
| quitar / borrar una fila | `update_task_io.sh --delete --io <id>` |

**Criterios de validación** (`update_task_criteria.sh` — always `--crit` for an
existing one, `--add --output` for a new one):

| User says | Call |
|---|---|
| reescribir S1.2 | `update_task_criteria.sh --crit <id> --text "…"` |
| "eso lo confirma una persona" / cambiar cómo se verifica | `update_task_criteria.sh --crit <id> --method attested` |
| volverlo opcional | `update_task_criteria.sh --crit <id> --required false` |
| agregar un criterio a S1 | `update_task_criteria.sh --add --output <output-id> --text "…" [--method M]` |
| quitar un criterio | `update_task_criteria.sh --delete --crit <id>` |

Rules of the road:

- **Types must exist.** `--io-type` / `--artifact` accept `name` or
  `display_name` from `io_catalog.sh` — offer the closest valid options instead
  of inventing one. Retyping the io_type does NOT auto-update the artifact;
  if the pairing stops making sense, propose the artifact change too.
- **`--method` is a closed set**: `llm`, `manual`, `automated`, `test`,
  `attested`. There is no `auto`. Pick from what the user *means*: a human
  confirming over WhatsApp is `attested`; "que lo revise el sistema" is `llm` or
  `automated` depending on whether judgement is involved.
- **A criterion belongs to an output, not to the task.** "Agregá un criterio"
  with more than one salida is ambiguous — ask which one, don't pick.
- **Criteria describe the contract, not its state.** `is_met` is earned by
  attestation and no flag here writes it; if the user says "ese ya se cumplió",
  say that this is the attestation path, not a contract edit.
- **Deleting an output that has criteria** is blocked without `--cascade`, and
  cascade deletes the criteria with it. Say exactly which criteria will die and
  get an explicit sí before running `--delete --io <id> --cascade`. Same shape
  one level down: deleting a **criterion that already has attestations** is
  blocked without `--cascade`, because cascading erases the evidence a human
  gave — never pass it without spelling that out first.
- **Binding a Doc/archivo desde la conversación** (`--ref-merge`): incluí
  siempre `title` (el nombre humano) además de `url`/`file_id`. El visor muestra
  `_resolved.title` → `title` → id crudo; el viz solo cachea `_resolved` cuando
  se vincula desde su botón, así que un binding sin `title` sale como un id de
  Drive (pasó con 386e9036, 2026-08-24).
- **`--dry-run` when unsure.** Deletes and anything the user phrased tentatively
  ("¿y si…?") get a dry-run first; plain field edits can go direct — the script
  prints before/after and nothing else is touched.
- **Batch requests** ("E1 a video_asset y bórrame S2") still run as sequential
  single-op calls; report each result.
- After a change (or a small batch), **re-fetch `task_detail.sh` and re-render**
  the affected section so the user always sees the persisted state, not your
  memory of it.

## 3. Out of scope — redirect, don't improvise

These two scripts edit the work contract and nothing else. When the user asks
for something else, say so and route it:

- **Marcar un criterio como cumplido** (`is_met`, `verified_*`) → attestation
  path, not this skill. No script writes it by hand.
- **Assignees** → `bash/tasks/reassign.sh`. **Task title/due/status** → no
  script; flag it. **Merge/duplicate** → `bash/tasks/cancel_task.sh --into`.
  **Completar la tarea** → `bash/tasks/complete_task.sh` (con `--at` si pasó
  hace días).
- Something with no script at all: offer to record the intent as a comment
  (`bash/tasks/add_comment.sh <id> --text "…"`) so it isn't lost.
- Edits to a **different task** mid-session: fine — fetch it and continue there.

## 4. Close the session

When the user is done, re-render the full contract once more and summarize the
changes applied (field → old → new). If nothing was changed, say so. Mention
that the viz "Editor de IO" UI (`npm run viz`) shows the same contract live —
including the criteria you just edited, which it renders read-only under their
output.

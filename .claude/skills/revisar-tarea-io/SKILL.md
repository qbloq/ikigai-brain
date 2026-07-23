---
name: revisar-tarea-io
description: Interactively review and edit one task's IO contract (inputs, outputs, types, required flags) together with the user, applying each change through bash/tasks/update_task_io.sh. Use whenever the user types /revisar-tarea-io <task-id>, or asks to review/fix/edit a task's IO, inputs, outputs, contract, io_type or artifact_type — e.g. "revisemos el IO de la tarea X", "ese output debería ser video_asset", "agrégale un input a la tarea", "quita ese input", even without naming the skill.
---

# Revisar / editar el IO de una tarea

A collaborative review session over ONE task's IO work contract: show the
current inputs/outputs/criteria, then translate the user's requests into
`update_task_io.sh` calls — one operation per call, one transaction each —
re-rendering after every change. This is the CLI twin of the viz "Editor de IO"
UI: same read source, same single write path, never inline SQL.

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
`id` of every input/output** (what `--io` needs), plus the archetype and
provenance. Keep those input/output row ids in your context (criteria carry no
id — consistent with them being read-only here); never show full UUIDs to the
user.

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
  - ✗ El registro captura cada caso… (llm)
  - ✗ El sistema está operativo y actualizable. (attested)
```

`¿ok?` renders `is_satisfied` (inputs) / `is_delivered` (outputs) as ✓/✗, and
each criterion's ✓/✗ is its `is_met`. Criteria arrive as a flat array linked to
their output only by **title** (`"output": "<output title>"` — no output_id in
the JSON); nest them under the matching salida, and if two outputs share a
title, say so instead of guessing the grouping.

Close the render with your own read: does the contract make sense for this task
and its archetype? Point out anything off (an output typed `documentation` that
is clearly a video, a task with no output, an input that isn't a real
prerequisite) as **suggestions** — the user decides. If the archetype has a
template contract (see `catalog/sop-archetypes.json`), a divergence from it is
worth mentioning, not auto-fixing.

## 2. Edit loop

For each change the user asks for, run exactly **one** `update_task_io.sh`
call, then confirm from its before/after output. Map natural language → mode:

| User says | Call |
|---|---|
| renombrar E1 / cambiar el título | `update_task_io.sh --io <id> --title "…"` |
| "eso es un video", cambiar tipo | `update_task_io.sh --io <id> --io-type video_asset` |
| cambiar el artefacto | `update_task_io.sh --io <id> --artifact storage_file` |
| hacerlo opcional / requerido | `update_task_io.sh --io <id> --required false` |
| agregar un input/output | `update_task_io.sh --add input\|output --task <task-id> --title "…"` then usually a second call to type it |
| quitar / borrar una fila | `update_task_io.sh --delete --io <id>` |

Rules of the road:

- **Types must exist.** `--io-type` / `--artifact` accept `name` or
  `display_name` from `io_catalog.sh` — offer the closest valid options instead
  of inventing one. Retyping the io_type does NOT auto-update the artifact;
  if the pairing stops making sense, propose the artifact change too.
- **Deleting an output that has criteria** is blocked without `--cascade`, and
  cascade deletes the criteria with it. Say exactly which criteria will die and
  get an explicit sí before running `--delete --io <id> --cascade`.
- **`--dry-run` when unsure.** Deletes and anything the user phrased tentatively
  ("¿y si…?") get a dry-run first; plain field edits can go direct — the script
  prints before/after and nothing else is touched.
- **Batch requests** ("E1 a video_asset y bórrame S2") still run as sequential
  single-op calls; report each result.
- After a change (or a small batch), **re-fetch `task_detail.sh` and re-render**
  the affected section so the user always sees the persisted state, not your
  memory of it.

## 3. Out of scope — redirect, don't improvise

`update_task_io.sh` only edits IO rows. When the user asks for something else,
say so and route it:

- **Acceptance criteria** (text/method/add/remove): no write script exists yet.
  Offer to record the desired change as a comment
  (`bash/tasks/add_comment.sh <id> --text "…"`) so it isn't lost.
- **Assignees** → `bash/tasks/reassign.sh`. **Task title/due/status** → no
  script; flag it. **Merge/duplicate** → `bash/tasks/cancel_task.sh --into`.
- Edits to a **different task** mid-session: fine — fetch it and continue there.

## 4. Close the session

When the user is done, re-render the full contract once more and summarize the
changes applied (field → old → new). If nothing was changed, say so. Mention
that the viz "Editor de IO" UI (`npm run viz`) shows the same contract live.

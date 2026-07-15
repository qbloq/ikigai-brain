# Export scripts

## elevate_núcleo.sh — el carril manual org→núcleo

`elevate_núcleo.sh <path>... [-m "título"] [--commit SHA] [--scope S] [--yes]`
**[WRITE al producto]** — eleva el delta de este cerebro sobre unos paths a
`núcleo.git` (nivel 0→1), mientras la plataforma no tenga la herramienta definitiva.
Codifica la liturgia demostrada en núcleo `5948844`: exige paths committeados
(el `Promoted-From` debe ser verdad), guarda de **des-clientización** (grep de
nombres del cliente en las líneas añadidas; `--force-names` lo salta,
`$CLIENT_PATTERNS` lo ajusta), ensaya el apply real en un worktree temporal
sobre la punta del núcleo (3-way; conflicto = aborta; no-op = "ya elevado") y
commitea con trailers `Delta-Type` (clasificado por path) / `Delta-Scope` /
`Promoted-From: cerebros/<org>@<sha>`. **Seguro por defecto:** siempre muestra
diffstat + mensaje y solo `--yes` pushea. `--commit SHA` eleva un commit
puntual; sin él, todo el delta del cerebro en esos paths.

## Snapshot exports

Regenerate the snapshots under [`backups/`](../backups/) from the live database.
Each script reads `DATABASE_URL` from `.env` and queries the `ikigaigm` schema
**read-only**, in `America/Bogota` time — the same connection policy as the
`bash/` toolkit. The universe is every *open* task (not completed/cancelled).

| Command | Output | What it is |
| --- | --- | --- |
| `npm run export` | everything below | runs all three |
| `npm run export:json` | `backups/tasks.json` | structural dump: each task with its outputs and acceptance criteria |
| `npm run export:by-role` | `backups/tasks-by-role/` | one markdown file per role (from each assignee's team role) + index |
| `npm run export:by-due-date` | `backups/tasks-by-due-date/` | tasks bucketed by due date (overdue / today / this week / next week) + a folder per exact date |

Each script takes an optional output-path argument, e.g.
`node scripts/export-tasks-json.js /tmp/tasks.json`.

`export-by-role.js` also accepts `--project NAME` (name fragment) to export a
single project. Output goes to a per-project subdir
`backups/tasks-by-role/<project-slug>/`, leaving the global export untouched:

```
node scripts/export-by-role.js --project "David Guerrero"
# → backups/tasks-by-role/david-guerrero/
```

`backups/` is git-ignored — these are regenerable snapshots, not source.

## Layout

- `lib/db.js` — loads `.env`, runs read-only `psql`, and `fetchTasks()` returns
  the full open-task universe (roles, todos, outputs/criteria) in one query that
  powers all three exports.
- `lib/render.js` — shared markdown helpers (slugs, relative date labels, task
  blocks, document assembly).
- `export-*.js` — one script per artifact; `export-all.js` runs them in order.

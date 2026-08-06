<!-- bash/ops/CLAUDE.md — reglas del dominio de OPERADOR. Este directorio NO
     viaja al copiloto (excluido en derivar_canal.sh), y por eso su manual vive
     aquí y no en el CLAUDE.md raíz, que es byte-idéntico en todos los forks. -->

# bash/ops — escrituras de operador

Las escrituras que **no** son del empleado: cargas masivas, backfills, el
pipeline de ingesta de Notion y la demolición del dominio de tareas. Se corren
desde el cerebro, por un humano que sabe lo que está haciendo, con la credencial
de operador.

## Por qué existe este directorio

El copiloto de un empleado es un fork del cerebro, y hasta hace poco estas seis
operaciones viajaban con él: veinte máquinas fuera de nuestro control con un
`wipe_tasks.sh` documentado en el manual que el agente lee primero. El rol
Postgres scopeado del copiloto casi con seguridad las rechaza —la credencial es
el límite real, no el archivo— pero **una herramienta que un agente puede leer
es una herramienta que un agente puede intentar**, y el error de permiso llega
después del intento, no antes.

Separarlas en un dominio propio (en vez de excluir archivo por archivo dentro de
`bash/tasks/`) mantiene el filtro y la narrativa a la misma granularidad: el
directorio se va del canal y su manual se va con él. Toda escritura de operador
futura nace aquí, sin que nadie tenga que acordarse de agregarla a una lista de
exclusión.

## Reglas

- **Nada de aquí se referencia desde el `CLAUDE.md` raíz** ni desde ningún
  archivo que viaje al copiloto. Si lo haces, el copiloto lee una promesa que su
  árbol no cumple. El chequeo de `derivar_canal.sh` lo caza.
- Todas abren con `psql_rw` y corren en UNA transacción, con `--dry-run` o
  ROLLBACK por defecto. Ninguna escribe sin que se lo pidan dos veces.
- `wipe_tasks.sh` es **irreversible**: respalda antes (los CSV de
  `backups/tasks-backup-<fecha>/` con su `restore.sql`).

## Scripts

| Script | Use it to… |
|--------|-----------|
| `ingest_notion.sh <classified.json> [--project N] [--limit N] [--only-open] [--yes]` **[WRITE]** | Bulk-ingest Notion tasks (from an ontology-pilot `classified.json`) into `tasks` in ONE txn: born with provenance (`source_type='notion'`, `source_url`, `source_external_id`) + archetype tag (`method='llm'`). v1 = **tag+provenance only** (no IO instantiation, no assignees). Dedups by `source_external_id` (idempotent). Safe by default: previews + ROLLBACK unless `--yes`. |
| `bind_io_notion.sh <notion-rows.json> [--dry-run] [--yes]` **[WRITE]** | Enganchar las carpetas de Drive que trae una tarea de Notion (`❌Drive Crudo`/`✅Drive Editado`) a su contrato IO: crudo→input, editado→output. **Tercer paso** del pipeline, DESPUÉS de que existan las filas IO (`ingest_notion.sh` → `materialize_io.sh` → `bind_io_notion.sh`). Regla de matching por `io_type` (`video_asset`/`ad_creative`) que **falla ruidoso**: si matchea 0 o >1 filas, salta y reporta. Retipa el artefacto a `drive_file` y cachea `_resolved:{title,url}` vía `bash/google/`. Idempotente. Diseño: [docs/io-bindings-drive.md](docs/io-bindings-drive.md). ⚠️ Re-materializar el IO **borra los bindings** — hay que re-correrlo. |
| `materialize_io.sh [--source notion] [--task ID,ID] [--replace] [--label NAME] [--yes]` **[WRITE]** | Backfill the IO work-contract (task_inputs/outputs/acceptance_criteria) onto EXISTING tasks by instantiating their archetype's template (set-based, one txn). Substitutes `{proyecto}`→label; **neutralizes other unfilled `{slots}`→«pendiente»** (templates keep their slots — the dimensional socket — untouched). Idempotent (skips tasks that already have IO); scoped by `--source` (bulk) or `--task` (surgical). `{proyecto}` resolves to **each task's own project** — `--label` overrides it for the whole batch (a single global label writes one project's contract onto another's). `--replace` (requires `--task`) DELETES the current IO first: the **re-materialization path**, needed because `set_archetype.sh` moves the archetype pointer but does **not** rewrite the contract — without it a re-tagged task keeps criteria describing a different activity. Destructive, not idempotent, kills Drive bindings. Safe by default: ROLLBACK unless `--yes`. Only tasks whose archetype has a template get IO. |
| `sync_catalog.sh [--dry-run]` **[WRITE]** | Rebuild the catalog tables from [catalog/sop-archetypes.json](../../catalog/sop-archetypes.json) (task `archetype_id` values preserved). Re-run after editing it. |
| `upsert_report.sh <id\|prefix> <report.json\|-> [--dry-run]` **[WRITE]** | Insert or REPLACE a team meeting's structured report (jsonb). Upserts on UNIQUE `meeting_id` (overwrites without looking back); validates the meeting + all 14 canonical keys; leaves `report_es` untouched. |
| `wipe_tasks.sh [--yes]` **[WRITE, IRREVERSIBLE]** | Delete the ENTIRE task domain (tasks + inputs + outputs + criteria + attestations + todos + comments) in one FK-safe transaction. Preserves `task_columns` and all FK parents. Safe by default: previews + rolls back unless `--yes`. Back up first (CSV snapshots in `backups/tasks-backup-<date>/`, restore via its `restore.sql`). |

## El pipeline de Notion

El orden importa y cada paso asume el anterior:

```
ingest_notion.sh   →   materialize_io.sh   →   bind_io_notion.sh
   tareas con           el contrato IO          las carpetas de
   procedencia          instanciado             Drive enganchadas
```

Diseño y decisiones: [docs/io-bindings-drive.md](../../docs/io-bindings-drive.md).
⚠️ Re-materializar el IO **borra los bindings** — hay que re-correr el tercer paso.

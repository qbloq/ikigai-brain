#!/usr/bin/env bash
# materialize_io.sh [--source notion] [--task ID,ID] [--replace] [--label NAME] [--yes]  **[WRITE]**
#
# Backfill the IO "work contract" (task_inputs / task_outputs / task_acceptance_criteria)
# onto EXISTING tasks by instantiating their archetype's template contract. Set-based,
# one transaction. For each task whose archetype has a template AND that has no IO yet:
#   - copy archetype_inputs/outputs/acceptance_criteria → task_*.
#   - substitute {proyecto}; NEUTRALIZE other unfilled {slots} → «pendiente».
#     Templates keep their slots (the dimensional socket) untouched — see
#     memory slots-as-org-dimensions; only THIS instantiation blanks unknowns.
#
# SCOPE — one of two ways:
#   --source S    all tasks of that provenance (default: notion). The bulk mode.
#   --task ID,ID  specific tasks by id prefix. Ignores --source.
#
# --replace  (requires --task) DELETES the task's current IO before instantiating.
#   This is the RE-materialization path, and it exists because re-tagging a task's
#   archetype does NOT rewrite its contract: `set_archetype.sh` moves the pointer,
#   the IO rows stay as the old template left them. Without this the task keeps
#   criteria that describe a different activity, and no work can satisfy it.
#   ⚠️ Destructive and NOT idempotent: acceptance criteria cascade with their
#   output, and any Drive binding on those rows dies too (re-run bind_io_notion.sh).
#
# {proyecto} resolves to the task's OWN project name. --label overrides it for
#   every task in scope — needed only when the tasks have no project, or when the
#   contract should read some other label (the historical Notion backfill used
#   "Premium Mastermind"). A task with neither resolves to «el proyecto».
#
# Idempotent WITHOUT --replace: skips tasks that already have inputs/outputs.
# SAFE BY DEFAULT: previews + ROLLBACK unless --yes.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

SRC="notion"; LABEL=""; COMMIT=""; TASKS=""; REPLACE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)  SRC="$2"; shift 2;;
    --task)    TASKS="${TASKS:+$TASKS,}$2"; shift 2;;
    --replace) REPLACE=1; shift;;
    --label)   LABEL="$2"; shift 2;;
    --yes)     COMMIT=1; shift;;
    -h|--help) sed -n '2,31p' "$0"; exit 0;;
    *) echo "arg desconocido: $1" >&2; exit 2;;
  esac
done

# --replace sin --task borraría el contrato de un dominio entero de un tirón.
[[ -n "$REPLACE" && -z "$TASKS" ]] && {
  echo "--replace exige --task: reinstanciar a ciegas borraría el contrato de todas las tareas de --source." >&2
  exit 2
}

# Alcance: por tarea (explícito) o por procedencia (masivo).
if [[ -n "$TASKS" ]]; then
  scope=""
  IFS=',' read -ra refs <<< "$TASKS"
  for raw in "${refs[@]}"; do
    tok="$(printf '%s' "$raw" | tr -d "[:space:]'")"
    [[ -z "$tok" ]] && continue
    scope="${scope:+$scope OR }t.id::text LIKE '${tok}%'"
  done
  [[ -z "$scope" ]] && { echo "--task quedó vacío tras limpiar." >&2; exit 2; }
  SCOPE_SQL="($scope)"
else
  SCOPE_SQL="t.source_type = '${SRC//\'/}'"
fi

# Sin --replace se salta lo que ya tiene contrato; con --replace se reemplaza.
if [[ -n "$REPLACE" ]]; then
  FRESH_SQL="true"
else
  FRESH_SQL="NOT EXISTS (SELECT 1 FROM task_inputs  x WHERE x.task_id = t.id)
         AND NOT EXISTS (SELECT 1 FROM task_outputs x WHERE x.task_id = t.id)"
fi

end="COMMIT"; [[ -z "$COMMIT" ]] && end="ROLLBACK"
psql_rw -v ON_ERROR_STOP=1 -v label="$LABEL" -v end="$end" <<SQL
BEGIN;
-- slot substitution: {proyecto}->label, other unfilled {slots}->«pendiente»
-- (dimensional param not captured for this task — honest, greppable,
-- grammatically safe), then collapse doubled spaces.
CREATE OR REPLACE FUNCTION pg_temp.slotclean(x text, label text) RETURNS text AS \$f\$
  SELECT btrim(regexp_replace(
           regexp_replace(
             regexp_replace(coalesce(x,''), '\{proyecto\}', label, 'g'),
             '\{[a-z_0-9]+\}', '«pendiente»', 'g'),
           '\s{2,}', ' ', 'g'));
\$f\$ LANGUAGE sql IMMUTABLE;

-- Tareas en alcance. El label viaja POR TAREA: dos tareas del mismo lote
-- pueden ser de proyectos distintos, y un solo --label global les escribiría
-- a ambas el contrato de una.
CREATE TEMP TABLE _targets ON COMMIT DROP AS
SELECT t.id, t.archetype_id,
       coalesce(nullif(:'label',''), pr.name, 'el proyecto') AS label
FROM tasks t
LEFT JOIN projects pr ON pr.id = t.project_id
WHERE $SCOPE_SQL
  AND t.archetype_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM archetype_outputs ao WHERE ao.archetype_id = t.archetype_id)
  AND ($FRESH_SQL);

\echo '==== ANTES ===='
SELECT left(g.id::text,8) AS tarea, g.archetype_id, g.label,
       (SELECT count(*) FROM task_inputs  x WHERE x.task_id=g.id) AS inputs,
       (SELECT count(*) FROM task_outputs x WHERE x.task_id=g.id) AS outputs
FROM _targets g ORDER BY 1;

-- Reemplazo: los criterios caen por CASCADE con su output. Sin --replace esto
-- es un no-op por construcción — _targets solo trae tareas sin IO.
DELETE FROM task_outputs o USING _targets g WHERE o.task_id = g.id;
DELETE FROM task_inputs  i USING _targets g WHERE i.task_id = g.id;

-- inputs
INSERT INTO task_inputs (task_id, title, description, io_type_id, artifact_type_id, is_required, position)
SELECT g.id, pg_temp.slotclean(ai.title, g.label), pg_temp.slotclean(ai.description, g.label),
       ai.io_type_id, it.default_artifact_type_id, ai.is_required, ai.position
FROM _targets g
JOIN archetype_inputs ai ON ai.archetype_id = g.archetype_id
LEFT JOIN io_types it ON it.id = ai.io_type_id;

-- outputs (capture new ids ↔ task+position for the criteria step)
CREATE TEMP TABLE _newout ON COMMIT DROP AS
WITH ins AS (
  INSERT INTO task_outputs (task_id, title, description, io_type_id, artifact_type_id, is_required, position)
  SELECT g.id, pg_temp.slotclean(ao.title, g.label), pg_temp.slotclean(ao.description, g.label),
         ao.io_type_id, it.default_artifact_type_id, ao.is_required, ao.position
  FROM _targets g
  JOIN archetype_outputs ao ON ao.archetype_id = g.archetype_id
  LEFT JOIN io_types it ON it.id = ao.io_type_id
  RETURNING id, task_id, position
)
SELECT * FROM ins;

-- acceptance criteria: link new outputs → archetype criteria via (archetype, position)
INSERT INTO task_acceptance_criteria (output_id, criterion, criterion_category, verification_method, is_required, position)
SELECT n.id, pg_temp.slotclean(cr.criterion, g.label),
       cr.criterion_category, cr.verification_method, cr.is_required, cr.position
FROM _newout n
JOIN _targets g ON g.id = n.task_id
JOIN archetype_outputs ao ON ao.archetype_id = g.archetype_id AND ao.position = n.position
JOIN archetype_acceptance_criteria cr ON cr.output_id = ao.id;

\echo '==== DESPUES ===='
SELECT (SELECT count(*) FROM _targets)                            AS tareas_materializadas,
       (SELECT count(*) FROM task_inputs  i JOIN _targets g ON g.id=i.task_id)   AS inputs_creados,
       (SELECT count(*) FROM _newout)                             AS outputs_creados,
       (SELECT count(*) FROM task_acceptance_criteria c JOIN _newout n ON n.id=c.output_id) AS criterios_creados;
:end;
SQL

[[ -z "$COMMIT" ]] && echo "(dry-run: ROLLBACK — nada escrito. Añade --yes para confirmar.)" >&2
exit 0

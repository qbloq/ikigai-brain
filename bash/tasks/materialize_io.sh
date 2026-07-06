#!/usr/bin/env bash
# materialize_io.sh [--source notion] [--label "Premium Mastermind"] [--yes]  **[WRITE]**
#
# Backfill the IO "work contract" (task_inputs / task_outputs / task_acceptance_criteria)
# onto EXISTING tasks by instantiating their archetype's template contract. Set-based,
# one transaction. For each task whose archetype has a template AND that has no IO yet:
#   - copy archetype_inputs/outputs/acceptance_criteria → task_*.
#   - substitute {proyecto} → --label; NEUTRALIZE other unfilled {slots} (drop them).
#     Templates keep their slots (the dimensional socket) untouched — see
#     memory slots-as-org-dimensions; only THIS instantiation blanks unknowns.
#
# Idempotent: skips tasks that already have inputs/outputs. Scoped by --source
# (default notion). SAFE BY DEFAULT: previews + ROLLBACK unless --yes.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

SRC="notion"; LABEL="Premium Mastermind"; COMMIT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SRC="$2"; shift 2;;
    --label) LABEL="$2"; shift 2;;
    --yes) COMMIT=1; shift;;
    -h|--help) sed -n '2,18p' "$0"; exit 0;;
    *) echo "arg desconocido: $1" >&2; exit 2;;
  esac
done

end="COMMIT"; [[ -z "$COMMIT" ]] && end="ROLLBACK"
psql_rw -v ON_ERROR_STOP=1 -v src="$SRC" -v label="$LABEL" -v end="$end" <<'SQL'
BEGIN;
-- slot substitution: {proyecto}->label, strip other {slots}, collapse spaces.
-- {proyecto}->label; other unfilled {slots}->«pendiente» (dimensional param not
-- captured for this historical task — honest, greppable, grammatically safe).
CREATE OR REPLACE FUNCTION pg_temp.slotclean(x text, label text) RETURNS text AS $f$
  SELECT btrim(regexp_replace(
           regexp_replace(
             regexp_replace(coalesce(x,''), '\{proyecto\}', label, 'g'),
             '\{[a-z_0-9]+\}', '«pendiente»', 'g'),
           '\s{2,}', ' ', 'g'));
$f$ LANGUAGE sql IMMUTABLE;

-- tasks in scope: given source, archetype has a template, and no IO yet.
CREATE TEMP TABLE _targets ON COMMIT DROP AS
SELECT t.id, t.archetype_id
FROM ikigaigm.tasks t
WHERE t.source_type = :'src'
  AND t.archetype_id IS NOT NULL
  AND EXISTS (SELECT 1 FROM ikigaigm.archetype_outputs ao WHERE ao.archetype_id = t.archetype_id)
  AND NOT EXISTS (SELECT 1 FROM ikigaigm.task_inputs  x WHERE x.task_id = t.id)
  AND NOT EXISTS (SELECT 1 FROM ikigaigm.task_outputs x WHERE x.task_id = t.id);

-- inputs
INSERT INTO ikigaigm.task_inputs (task_id, title, description, io_type_id, artifact_type_id, is_required, position)
SELECT g.id, ai.title, pg_temp.slotclean(ai.description, :'label'),
       ai.io_type_id, it.default_artifact_type_id, ai.is_required, ai.position
FROM _targets g
JOIN ikigaigm.archetype_inputs ai ON ai.archetype_id = g.archetype_id
LEFT JOIN ikigaigm.io_types it ON it.id = ai.io_type_id;

-- outputs (capture new ids ↔ task+position for the criteria step)
CREATE TEMP TABLE _newout ON COMMIT DROP AS
WITH ins AS (
  INSERT INTO ikigaigm.task_outputs (task_id, title, description, io_type_id, artifact_type_id, is_required, position)
  SELECT g.id, ao.title, pg_temp.slotclean(ao.description, :'label'),
         ao.io_type_id, it.default_artifact_type_id, ao.is_required, ao.position
  FROM _targets g
  JOIN ikigaigm.archetype_outputs ao ON ao.archetype_id = g.archetype_id
  LEFT JOIN ikigaigm.io_types it ON it.id = ao.io_type_id
  RETURNING id, task_id, position
)
SELECT * FROM ins;

-- acceptance criteria: link new outputs → archetype criteria via (archetype, position)
INSERT INTO ikigaigm.task_acceptance_criteria (output_id, criterion, criterion_category, verification_method, is_required, position)
SELECT n.id, pg_temp.slotclean(cr.criterion, :'label'),
       cr.criterion_category, cr.verification_method, cr.is_required, cr.position
FROM _newout n
JOIN _targets g ON g.id = n.task_id
JOIN ikigaigm.archetype_outputs ao ON ao.archetype_id = g.archetype_id AND ao.position = n.position
JOIN ikigaigm.archetype_acceptance_criteria cr ON cr.output_id = ao.id;

-- report
SELECT (SELECT count(*) FROM _targets)                            AS tareas_materializadas,
       (SELECT count(*) FROM ikigaigm.task_inputs  i JOIN _targets g ON g.id=i.task_id)   AS inputs_creados,
       (SELECT count(*) FROM _newout)                             AS outputs_creados,
       (SELECT count(*) FROM ikigaigm.task_acceptance_criteria c JOIN _newout n ON n.id=c.output_id) AS criterios_creados;
:end;
SQL

[[ -z "$COMMIT" ]] && echo "(dry-run: ROLLBACK — nada escrito. Añade --yes para confirmar.)" >&2
exit 0

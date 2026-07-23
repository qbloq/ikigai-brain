#!/usr/bin/env bash
# Delete the ENTIRE task domain: every row of tasks + inputs + outputs +
# acceptance criteria + attestations + todos + comments. WRITE, IRREVERSIBLE.
# Preserves task_columns (kanban structure) and all FK parents (projects, users,
# team_members, io_types, artifact_types, verification_templates).
#
# Runs in ONE transaction, deleting children before parents (FK-safe). Prints
# before/after counts. SAFE BY DEFAULT: without --yes it only previews (rolls
# back). You must pass --yes to actually commit.
#
# Usage:
#   wipe_tasks.sh             # dry-run: show counts, roll back, write nothing
#   wipe_tasks.sh --dry-run   # same as above (explicit)
#   wipe_tasks.sh --yes       # ACTUALLY delete everything (commits)
#
# Make a backup first (see backups/tasks-backup-YYYY-MM-DD/).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

commit=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) commit=1; shift ;;
    --dry-run) commit=""; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Child→parent delete order (FK-safe).
end="ROLLBACK"; [[ -n "$commit" ]] && end="COMMIT"
if [[ -n "$commit" ]]; then
  echo ">>> --yes given: this WILL permanently delete the task domain." >&2
else
  echo ">>> dry-run (no --yes): previewing counts, nothing will be written." >&2
fi

psql_rw <<SQL
\echo '==== BEFORE ===='
SELECT 'tasks' t, count(*) n FROM tasks
UNION ALL SELECT 'task_inputs', count(*) FROM task_inputs
UNION ALL SELECT 'task_outputs', count(*) FROM task_outputs
UNION ALL SELECT 'task_acceptance_criteria', count(*) FROM task_acceptance_criteria
UNION ALL SELECT 'task_attestations', count(*) FROM task_attestations
UNION ALL SELECT 'task_todos', count(*) FROM task_todos
UNION ALL SELECT 'task_comments', count(*) FROM task_comments
ORDER BY 1;

BEGIN;
DELETE FROM task_attestations;
DELETE FROM task_acceptance_criteria;
DELETE FROM task_inputs;
DELETE FROM task_outputs;
DELETE FROM task_todos;
DELETE FROM task_comments;
DELETE FROM tasks;

\echo '==== AFTER (within tx) ===='
SELECT 'tasks' t, count(*) n FROM tasks
UNION ALL SELECT 'task_inputs', count(*) FROM task_inputs
UNION ALL SELECT 'task_outputs', count(*) FROM task_outputs
UNION ALL SELECT 'task_acceptance_criteria', count(*) FROM task_acceptance_criteria
UNION ALL SELECT 'task_attestations', count(*) FROM task_attestations
UNION ALL SELECT 'task_todos', count(*) FROM task_todos
UNION ALL SELECT 'task_comments', count(*) FROM task_comments
ORDER BY 1;
$end;
\echo '==== task_columns (preserved) ===='
SELECT count(*) AS task_columns_kept FROM task_columns;
SQL

if [[ -z "$commit" ]]; then
  echo "(dry-run: rolled back, nothing written — pass --yes to commit)"
else
  echo "(committed: task domain wiped — restore from backups/ if needed)"
fi

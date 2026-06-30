#!/usr/bin/env bash
# Show the full detail of a single task: header, inputs, outputs,
# acceptance criteria, todos and comments.
#
# Usage:  task_show.sh <task_id|id_prefix>   [--json]
# The id may be the full UUID or just its first characters (e.g. b09f8132).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

idarg="" ; while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) idarg="$1"; shift ;;
  esac
done
[[ -z "$idarg" ]] && { echo "Usage: task_show.sh <task_id|prefix>" >&2; exit 2; }
idarg="${idarg//\'/}"

tid="$(psql_ro -t -A -c "SELECT id FROM ikigaigm.tasks WHERE id::text LIKE '${idarg}%' LIMIT 2;" | head -1)"
[[ -z "$tid" ]] && { echo "No task matches: $idarg" >&2; exit 1; }

if [[ "$FORMAT" == "json" ]]; then
  psql_ro -t -A -c "
  SELECT row_to_json(x) FROM (
    SELECT t.*,
      (SELECT json_agg(i) FROM ikigaigm.task_inputs  i WHERE i.task_id=t.id) AS inputs,
      (SELECT json_agg(o) FROM ikigaigm.task_outputs o WHERE o.task_id=t.id) AS outputs,
      (SELECT json_agg(c) FROM ikigaigm.task_acceptance_criteria c
         WHERE c.output_id IN (SELECT id FROM ikigaigm.task_outputs WHERE task_id=t.id)) AS criteria,
      (SELECT json_agg(d) FROM ikigaigm.task_todos d WHERE d.task_id=t.id) AS todos,
      (SELECT json_agg(m) FROM ikigaigm.task_comments m WHERE m.task_id=t.id) AS comments
    FROM ikigaigm.tasks t WHERE t.id='$tid'
  ) x;"
  exit 0
fi

echo "== TASK =="
psql_ro -x -c "
SELECT left(t.id::text,8) AS id, t.title, t.status, t.priority,
       to_char(t.due_date,'YYYY-MM-DD HH24:MI') AS due,
       pr.name AS project, $ASSIGNEES_SQL AS assignees,
       t.is_completed, to_char(t.created_at,'YYYY-MM-DD') AS created
FROM ikigaigm.tasks t LEFT JOIN ikigaigm.projects pr ON pr.id=t.project_id
WHERE t.id='$tid';"

echo "== INPUTS =="
psql_ro -c "SELECT title, is_required, is_satisfied, it.display_name AS io_type
  FROM ikigaigm.task_inputs i LEFT JOIN ikigaigm.io_types it ON it.id=i.io_type_id
  WHERE i.task_id='$tid' ORDER BY i.position;"

echo "== OUTPUTS =="
psql_ro -c "SELECT title, is_required, is_delivered, it.display_name AS io_type
  FROM ikigaigm.task_outputs o LEFT JOIN ikigaigm.io_types it ON it.id=o.io_type_id
  WHERE o.task_id='$tid' ORDER BY o.position;"

echo "== ACCEPTANCE CRITERIA =="
psql_ro -c "SELECT c.criterion, c.verification_method AS method, c.is_required, c.is_met
  FROM ikigaigm.task_acceptance_criteria c
  WHERE c.output_id IN (SELECT id FROM ikigaigm.task_outputs WHERE task_id='$tid')
  ORDER BY c.position;"

echo "== TODOS =="
psql_ro -c "SELECT completed, text FROM ikigaigm.task_todos WHERE task_id='$tid' ORDER BY position;"

echo "== COMMENTS =="
psql_ro -c "SELECT to_char(created_at,'YYYY-MM-DD') AS date, author_name, text
  FROM ikigaigm.task_comments WHERE task_id='$tid' ORDER BY created_at;"

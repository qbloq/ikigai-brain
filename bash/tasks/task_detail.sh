#!/usr/bin/env bash
# Full detail of ONE task as a single JSON object, tailored for the viz detail
# panel: header (resolved project + assignees) plus inputs, outputs and
# acceptance criteria, with io_types resolved to display names.
#
# Usage:  task_detail.sh <task_id|prefix> [--json]
# Always emits JSON (single object); --json is accepted for consistency.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

idarg=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) idarg="$1"; shift ;;
  esac
done
[[ -z "$idarg" ]] && { echo "Usage: task_detail.sh <task_id|prefix>" >&2; exit 2; }
idarg="${idarg//\'/}"
tid="$(psql_ro -t -A -c "SELECT id FROM ikigaigm.tasks WHERE id::text LIKE '${idarg}%' LIMIT 1;")"
[[ -z "$tid" ]] && { echo "No task matches: $idarg" >&2; exit 1; }

psql_ro -t -A -c "
SELECT json_build_object(
  'id',        left(t.id::text,8),
  'title',     t.title,
  'status',    t.status::text,
  'priority',  t.priority::text,
  'due',       to_char(t.due_date,'YYYY-MM-DD'),
  'project',   pr.name,
  'assignees', $ASSIGNEES_SQL,
  'created',   to_char(t.created_at,'YYYY-MM-DD'),
  'archetype', CASE WHEN a.id IS NULL THEN NULL ELSE json_build_object(
     'id', a.id, 'verb', a.verb, 'name', a.name,
     'sop', s.code, 'sop_name', s.name,
     'macro', mp.code, 'macro_name', mp.name) END,
  'inputs', coalesce((SELECT json_agg(json_build_object(
       'title', i.title, 'io_type', it.display_name,
       'is_required', i.is_required, 'is_satisfied', i.is_satisfied) ORDER BY i.position)
     FROM ikigaigm.task_inputs i LEFT JOIN ikigaigm.io_types it ON it.id=i.io_type_id
     WHERE i.task_id=t.id), '[]'::json),
  'outputs', coalesce((SELECT json_agg(json_build_object(
       'title', o.title, 'io_type', it.display_name,
       'is_required', o.is_required, 'is_delivered', o.is_delivered) ORDER BY o.position)
     FROM ikigaigm.task_outputs o LEFT JOIN ikigaigm.io_types it ON it.id=o.io_type_id
     WHERE o.task_id=t.id), '[]'::json),
  'criteria', coalesce((SELECT json_agg(json_build_object(
       'criterion', c.criterion, 'method', c.verification_method,
       'is_required', c.is_required, 'is_met', c.is_met,
       'output', o.title) ORDER BY c.position)
     FROM ikigaigm.task_acceptance_criteria c
     JOIN ikigaigm.task_outputs o ON o.id=c.output_id
     WHERE o.task_id=t.id), '[]'::json),
  'comments', coalesce((SELECT json_agg(json_build_object(
       'date', to_char(m.created_at,'YYYY-MM-DD'),
       'author', m.author_name, 'text', m.text) ORDER BY m.created_at)
     FROM ikigaigm.task_comments m WHERE m.task_id=t.id), '[]'::json)
) FROM ikigaigm.tasks t
  LEFT JOIN ikigaigm.projects pr ON pr.id=t.project_id
  LEFT JOIN ikigaigm.activity_archetypes a ON a.id=t.archetype_id
  LEFT JOIN ikigaigm.sops s ON s.code=a.sop_code
  LEFT JOIN ikigaigm.macro_processes mp ON mp.code=s.macro_process_code
WHERE t.id='$tid';"

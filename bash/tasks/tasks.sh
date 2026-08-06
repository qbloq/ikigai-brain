#!/usr/bin/env bash
# List tasks with optional filters.
#
# Usage:
#   tasks.sh [--status S] [--priority P] [--project NAME] [--assignee NAME]
#            [--due W] [--open] [--stale N] [--no-due] [--macro CODE]
#            [--sin-arquetipo] [--sin-outputs] [--closed N] [--limit N] [--json]
#
#   --status S      pending | in_progress | completed | blocked | cancelled
#   --priority P    Low | Medium | High
#   --project NAME  project name fragment
#   --assignee NAME person name fragment (e.g. David)
#   --due W         due window: today|tomorrow|yesterday|this-week|next-week|overdue
#   --open          only tasks not completed/cancelled
#   --stale N       untouched for >= N days (updated_at) — the chase queue; pair with --open
#   --no-due        no due date at all (date-hygiene queue)
#   --macro CODE    macro-process of the task's archetype: code (S4) or name fragment
#   --sin-arquetipo not tagged with an activity archetype (ontology-hygiene queue)
#   --sin-outputs   no declared deliverable (contract-hygiene queue)
#   --closed N      completed within the last N days (completed_at, migration 003)
#   --limit N       cap rows (default 50; use 0 for no limit)
#   --json          JSON array output
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

status="" priority="" project="" assignee="" due="" open="" limit="50"
stale="" nodue="" macro="" no_arch="" no_outputs="" closed=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --status)   status="$2"; shift 2 ;;
    --priority) priority="$2"; shift 2 ;;
    --project)  project="$2"; shift 2 ;;
    --assignee) assignee="$2"; shift 2 ;;
    --due)      due="$2"; shift 2 ;;
    --open)     open=1; shift ;;
    --stale)    stale="$2"; shift 2 ;;
    --no-due)   nodue=1; shift ;;
    --macro)    macro="$2"; shift 2 ;;
    --sin-arquetipo) no_arch=1; shift ;;
    --sin-outputs)   no_outputs=1; shift ;;
    --closed)   closed="$2"; shift 2 ;;
    --limit)    limit="$2"; shift 2 ;;
    --json)     FORMAT=json; shift ;;
    -h|--help)  sed -n '2,21p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

esc() { printf '%s' "${1//\'/\'\'}"; }
where="true"
[[ -n "$status" ]]   && where="$where AND t.status = '$(esc "$status")'"
[[ -n "$priority" ]] && where="$where AND t.priority = '$(esc "$priority")'"
[[ -n "$open" ]]     && where="$where AND $OPEN_PRED"
if [[ -n "$due" ]]; then
  case "$due" in
    today)     due_pred="t.due_date::date = current_date" ;;
    tomorrow)  due_pred="t.due_date::date = current_date + 1" ;;
    yesterday) due_pred="t.due_date::date = current_date - 1" ;;
    this-week) due_pred="t.due_date::date BETWEEN date_trunc('week',current_date)::date AND (date_trunc('week',current_date)+interval '6 days')::date" ;;
    next-week) due_pred="t.due_date::date BETWEEN (date_trunc('week',current_date)+interval '7 days')::date AND (date_trunc('week',current_date)+interval '13 days')::date" ;;
    overdue)   due_pred="t.due_date::date < current_date" ;;
    *) echo "Unknown --due window: $due" >&2; exit 2 ;;
  esac
  where="$where AND t.due_date IS NOT NULL AND ($due_pred)"
fi
if [[ -n "$project" ]]; then
  pid="$(resolve_project "$project")"
  [[ -z "$pid" ]] && { echo "No project matches: $project" >&2; exit 1; }
  where="$where AND t.project_id = '$pid'"
fi
if [[ -n "$assignee" ]]; then
  where="$where AND EXISTS (SELECT 1 FROM unnest(t.assignee) aid
    JOIN team_members tm ON tm.id=aid
    LEFT JOIN users u ON u.id=tm.user_id
    LEFT JOIN persons p ON p.person_id=u.person_id
    WHERE (coalesce(p.name,'')||' '||coalesce(p.lastname,'')) ILIKE '%$(esc "$assignee")%')"
fi

num() { [[ "$1" =~ ^[0-9]+$ ]] || { echo "$2 espera un número entero de días, no '$1'" >&2; exit 2; }; }
if [[ -n "$stale" ]]; then
  num "$stale" "--stale"
  where="$where AND t.updated_at < now() - interval '$stale days'"
fi
[[ -n "$nodue" ]]      && where="$where AND t.due_date IS NULL"
[[ -n "$no_arch" ]]    && where="$where AND t.archetype_id IS NULL"
[[ -n "$no_outputs" ]] && where="$where AND NOT EXISTS (SELECT 1 FROM task_outputs o WHERE o.task_id = t.id)"
if [[ -n "$closed" ]]; then
  num "$closed" "--closed"
  where="$where AND t.completed_at >= now() - interval '$closed days'"
fi
if [[ -n "$macro" ]]; then
  # El macro-proceso no vive en la tarea: se alcanza por arquetipo→SOP→macro.
  where="$where AND EXISTS (SELECT 1 FROM activity_archetypes a
    JOIN sops s ON s.code = a.sop_code
    JOIN macro_processes mp ON mp.code = s.macro_process_code
    WHERE a.id = t.archetype_id
      AND (upper(mp.code) = upper('$(esc "$macro")') OR mp.name ILIKE '%$(esc "$macro")%'))"
fi

# El orden sigue al filtro dominante: la cola de chase se lee por lo más
# abandonado arriba, la de cierres por lo más reciente. Si no hay ninguno de
# los dos, manda el vencimiento (el orden histórico de este script).
order="t.due_date NULLS LAST, t.priority DESC"
[[ -n "$stale" ]]  && order="t.updated_at ASC"
[[ -n "$closed" ]] && order="t.completed_at DESC"

[[ "$limit" == "0" ]] && limit=""
emit "$(tasks_select "$where" "$order" "$limit")"

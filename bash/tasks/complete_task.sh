#!/usr/bin/env bash
# Mark one or more tasks as DONE (status='completed' + is_completed=true).
# WRITE, transactional, --dry-run rolls back. Leaves a comment trail.
#
# Usage:
#   complete_task.sh <id|prefix> [<id|prefix>...] [--at YYYY-MM-DD]
#                    [--note "text"] [--author NAME] [--dry-run]
#
#   --at FECHA    cuándo se completó DE VERDAD. Sin esto, el trigger sella
#                 completed_at con now(), que para una tarea ejecutada hace
#                 semanas es mentira. Migración 003 respeta un valor explícito.
#   --note TEXTO  evidencia del cierre (p.ej. la reunión donde consta)
#   --author NOM  autor del comentario (default: complete_task)
#
# Es el gemelo de cancel_task.sh y NO lo reemplaza: 'completed' significa que el
# trabajo se hizo; 'cancelled' que ya no se hará. Confundirlos corrompe toda
# medición de cumplimiento.
#
# Nada se borra. Reabrir una tarea (volverla a pending) limpia completed_at por
# trigger, así que el cierre nunca queda sostenido a medias.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

[[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { sed -n '2,20p' "$0"; exit 0; }

refs=() at="" note="" author="complete_task" dry=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --at) at="$2"; shift 2 ;;
    --note) note="$2"; shift 2 ;;
    --author) author="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    --json) FORMAT=json; shift ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) refs+=("$1"); shift ;;
  esac
done
[[ ${#refs[@]} -eq 0 ]] && { echo "Falta al menos un id de tarea." >&2; exit 2; }

if [[ -n "$at" && ! "$at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "--at espera YYYY-MM-DD (recibí '$at')." >&2; exit 2
fi

resolve_task() { # echoes the single full id for a prefix, errors otherwise
  local ref="$1" ids n
  ids="$(psql_ro -t -A -c "SELECT id FROM tasks WHERE id::text LIKE '${ref//\'/\'\'}%'")"
  n="$(printf '%s\n' "$ids" | grep -c . || true)"
  [[ "$n" -eq 1 ]] || { echo "Task ref '$ref' resolved to $n tasks (need 1)." >&2; return 1; }
  printf '%s' "$ids"
}

ids=()
for r in "${refs[@]}"; do ids+=("$(resolve_task "$r")") || exit 1; done

# Ya cerradas: se avisan y se excluyen — reescribirlas movería su completed_at.
list="$(printf "'%s'," "${ids[@]}")"; list="${list%,}"
done_already="$(psql_ro -t -A -c "
  SELECT string_agg(left(id::text,8), ', ')
  FROM tasks WHERE id IN ($list) AND (status='completed' OR coalesce(is_completed,false));")"
[[ -n "$done_already" ]] && echo "Ya estaban completadas (se omiten): $done_already" >&2

end="COMMIT"; [[ -n "$dry" ]] && end="ROLLBACK"
psql_rw -v list="$list" -v at="$at" -v note="$note" -v author="$author" <<SQL
BEGIN;
\echo '==== ANTES ===='
SELECT left(id::text,8) AS id, status, to_char(due_date,'YYYY-MM-DD') AS vence,
       to_char(completed_at,'YYYY-MM-DD') AS completada, left(title,52) AS title
FROM tasks WHERE id IN ($list) ORDER BY due_date;

-- El UPDATE excluye las ya cerradas: el trigger de la migración 003 sólo sella
-- la TRANSICIÓN, y un completed_at explícito sobrevive (no se sobreescribe).
-- El comentario cuelga del RETURNING, no de un SELECT posterior: así sólo se
-- comenta lo que esta corrida cerró de verdad, y nunca lo que ya estaba cerrado.
WITH upd AS (
  UPDATE tasks
     SET status = 'completed'::task_status,
         is_completed = true,
         completed_at = CASE WHEN nullif(:'at','') IS NOT NULL
                             THEN (:'at')::timestamptz ELSE completed_at END
   WHERE id IN ($list)
     AND status <> 'completed' AND coalesce(is_completed,false) = false
  RETURNING id
)
INSERT INTO task_comments (task_id, author_name, text)
SELECT id, :'author',
       'Completada'
       || CASE WHEN nullif(:'at','')   IS NOT NULL THEN ' el '||:'at' ELSE '' END
       || CASE WHEN nullif(:'note','') IS NOT NULL THEN '. '||:'note' ELSE '' END
FROM upd;

\echo '==== DESPUÉS ===='
SELECT left(id::text,8) AS id, status, to_char(due_date,'YYYY-MM-DD') AS vence,
       to_char(completed_at,'YYYY-MM-DD') AS completada, left(title,52) AS title
FROM tasks WHERE id IN ($list) ORDER BY due_date;
$end;
SQL

[[ -n "$dry" ]] && echo "(dry-run: rolled back, nothing written)"
exit 0

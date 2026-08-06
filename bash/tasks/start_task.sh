#!/usr/bin/env bash
# Poner una o más tareas EN CURSO (status='in_progress'). WRITE, transaccional,
# --dry-run hace rollback. Deja rastro en comentarios.
#
# Uso:
#   start_task.sh <id|prefijo> [<id|prefijo>...]
#                 [--note "texto"] [--author NOMBRE] [--reabrir] [--dry-run]
#
#   --note TEXTO  qué se empezó / con qué evidencia (queda en el trail)
#   --author NOM  autor del comentario (default: start_task)
#   --reabrir     permite mover una tarea YA COMPLETADA de vuelta a in_progress.
#                 Sin esta bandera se rechaza, porque el trigger de la migración
#                 003 BORRA completed_at al salir de 'completed': reabrir por
#                 descuido no cambia un estado, destruye la única medición de
#                 ritmo que tenemos y no hay cómo recuperar la fecha.
#
# Es el tercer estado, el que faltaba. complete_task.sh y cancel_task.sh son
# terminales ('se hizo' / 'no se hará'); esto declara 'se está haciendo', que es
# lo que distingue una tarea trabajándose de una que lleva tres meses quieta.
# Ambas se ven 'pending' y esa ambigüedad es justamente lo que impide leer una
# cola.
#
# Las que ya están in_progress se omiten, no se reescriben: volver a correrlo
# nunca duplica comentarios.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

[[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { sed -n '2,25p' "$0"; exit 0; }

refs=() note="" author="start_task" dry="" reopen=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --note) note="$2"; shift 2 ;;
    --author) author="$2"; shift 2 ;;
    --reabrir|--reopen) reopen=1; shift ;;
    --dry-run) dry=1; shift ;;
    --json) FORMAT=json; shift ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) refs+=("$1"); shift ;;
  esac
done
[[ ${#refs[@]} -eq 0 ]] && { echo "Falta al menos un id de tarea." >&2; exit 2; }

resolve_task() { # imprime el id completo de un prefijo, o falla
  local ref="$1" ids n
  ids="$(psql_ro -t -A -c "SELECT id FROM tasks WHERE id::text LIKE '${ref//\'/\'\'}%'")"
  n="$(printf '%s\n' "$ids" | grep -c . || true)"
  [[ "$n" -eq 1 ]] || { echo "Task ref '$ref' resolved to $n tasks (need 1)." >&2; return 1; }
  printf '%s' "$ids"
}

ids=()
for r in "${refs[@]}"; do ids+=("$(resolve_task "$r")") || exit 1; done
list="$(printf "'%s'," "${ids[@]}")"; list="${list%,}"

# Cerradas: sin --reabrir esto se detiene ANTES de escribir nada. El costo de
# equivocarse es asimétrico (completed_at no se recupera), así que se rechaza
# la corrida entera en vez de omitir la fila y seguir.
closed="$(psql_ro -t -A -c "
  SELECT string_agg(left(id::text,8)||' ('||status||')', ', ')
  FROM tasks WHERE id IN ($list)
    AND (status IN ('completed','cancelled') OR coalesce(is_completed,false));")"
if [[ -n "$closed" && -z "$reopen" ]]; then
  echo "Estas ya están cerradas: $closed" >&2
  echo "Reabrirlas borra su completed_at (trigger migración 003). Si es a propósito, pasa --reabrir." >&2
  exit 3
fi

# Ya en curso: se avisan y se excluyen del UPDATE.
already="$(psql_ro -t -A -c "
  SELECT string_agg(left(id::text,8), ', ')
  FROM tasks WHERE id IN ($list) AND status = 'in_progress';")"
[[ -n "$already" ]] && echo "Ya estaban en curso (se omiten): $already" >&2

end="COMMIT"; [[ -n "$dry" ]] && end="ROLLBACK"
psql_rw -v note="$note" -v author="$author" <<SQL
BEGIN;
\echo '==== ANTES ===='
SELECT left(id::text,8) AS id, status, to_char(due_date,'YYYY-MM-DD') AS vence,
       to_char(completed_at,'YYYY-MM-DD') AS completada, left(title,52) AS title
FROM tasks WHERE id IN ($list) ORDER BY due_date;

-- is_completed=false va explícito: en una reapertura el status por sí solo no
-- alcanza (la bandera quedaría en true y la tarea seguiría contando como hecha
-- en todo lo que lee is_completed en vez de status). El trigger 003 limpia
-- completed_at al ver la salida de 'completed'.
WITH upd AS (
  UPDATE tasks
     SET status = 'in_progress'::task_status,
         is_completed = false
   WHERE id IN ($list)
     AND status <> 'in_progress'
  RETURNING id, status
)
INSERT INTO task_comments (task_id, author_name, text)
SELECT id, :'author',
       'En curso'
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

#!/usr/bin/env bash
# WRITE: execute the curated merges of the PM↔cerebro cruce — the script you
# run AFTER finishing the Merge curation in the viz `cruce` UI.
#
# For every row of the local SQLite `pm_platform.cruce` with merge=1 AND
# resuelta=0, in ONE Postgres transaction per pair:
#   1. duplicates the cerebro task: the duplicate takes the TITLE from the PM
#      platform, inherits project/assignees/priority/column/archetype and the
#      original's provenance (source_type, source_meeting_id), and records the
#      PM identity (source_external_id = PM task uuid, source_url = its API
#      URL) — the dedup hook for the future cerebro→PM sync;
#   2. gives it a contract: --contrato plantilla (default) re-instantiates the
#      archetype's template contract with {proyecto} substituted and unfilled
#      {slots} neutralized to «pendiente» (same rule as materialize_io.sh),
#      falling back to `copia` when the task has no archetype template;
#      --contrato copia clones the original's live inputs/outputs/criteria
#      (bindings included, verification state RESET — is_met is earned by
#      attestation, never copied);
#   3. copies the trail: every comment and todo of the original (timestamps
#      preserved) plus one merge-provenance comment on each side;
#   4. resolves the status: completed if EITHER side completed (completed_at
#      from the PM's completada_en when it's the PM side — an explicit value
#      survives the migration-003 trigger), else in_progress if either side
#      is, else pending;
#   5. cancels the original INTO the duplicate (status='cancelled' + trail,
#      mirror of cancel_task.sh --into; nothing deleted);
#   6. stamps the SQLite row: resuelta=1, resolucion='merge → <new_id>'.
#
# Usage: merge_from_cruce.sh [--n LIST] [--contrato plantilla|copia] [--dry-run] [--json]
#   --n LIST     only these cruce.n rows (comma list), still requiring merge=1
#   --contrato   contract source for the duplicate (default: plantilla)
#   --dry-run    run each pair's transaction and ROLLBACK; SQLite untouched
#   --json       one JSON line per pair + final {ok, merged, dry_run}
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

SQLITE_DB="${LOCALDB_DIR:-$REPO_ROOT/data/sqlite}/pm_platform.db"
PM_API_BASE="https://project360-pearl.vercel.app/api/v1/tasks"

nlist="" contrato="plantilla" dry=0 json=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --n)        nlist="$2"; shift 2 ;;
    --contrato) contrato="$2"; shift 2 ;;
    --dry-run)  dry=1; shift ;;
    --json)     json=1; shift ;;
    -h|--help)  sed -n '2,36p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
[[ "$contrato" =~ ^(plantilla|copia)$ ]] || { echo "--contrato debe ser plantilla|copia" >&2; exit 2; }
[[ -z "$nlist" || "$nlist" =~ ^[0-9]+(,[0-9]+)*$ ]] || { echo "--n debe ser una lista de enteros separados por coma" >&2; exit 2; }
[[ -f "$SQLITE_DB" ]] || { echo "No existe $SQLITE_DB (¿corriste el cruce?)" >&2; exit 1; }
command -v sqlite3 >/dev/null || { echo "sqlite3 no está instalado" >&2; exit 1; }

filter=""
[[ -n "$nlist" ]] && filter="AND c.n IN ($nlist)"

# The work list: curated rows joined to the PM snapshot (the local mirror of
# Mari's API — titles/estados/fechas come from THERE, not from Postgres).
worklist="$(sqlite3 -readonly -separator $'\t' "$SQLITE_DB" "
  SELECT c.n, c.ce_id, c.pm_id, t.titulo, t.estado,
         coalesce(t.fecha_limite,''), coalesce(t.completada_en,'')
  FROM cruce c JOIN tareas t ON t.id = c.pm_id
  WHERE c.merge=1 AND c.resuelta=0 $filter
  ORDER BY c.n")"

if [[ -z "$worklist" ]]; then
  [[ "$json" == 1 ]] && echo '{"ok":true,"merged":0,"dry_run":'"$dry"',"note":"no hay filas con merge=1 pendientes"}' \
                     || echo "Nada que mezclar: no hay filas con merge=1 y resuelta=0."
  exit 0
fi

# --- SQL blocks (quoted heredocs: literal $f$ and quotes; data via psql -v) --
read -r -d '' SQL_HEAD <<'EOF' || true
BEGIN;
CREATE OR REPLACE FUNCTION pg_temp.slotclean(x text, label text) RETURNS text AS $f$
  SELECT btrim(regexp_replace(
           regexp_replace(
             regexp_replace(coalesce(x,''), '\{proyecto\}', label, 'g'),
             '\{[a-z_0-9]+\}', '«pendiente»', 'g'),
           '\s{2,}', ' ', 'g'));
$f$ LANGUAGE sql;

\echo '==== ANTES ===='
SELECT left(id::text,8) AS id, status, left(title,60) AS title FROM tasks WHERE id = :'old_id'::uuid;

INSERT INTO tasks (id, user_id, title, project_id, priority, due_date,
                   status, is_completed, completed_at, column_id, position, assignee,
                   archetype_id, archetype_confidence, archetype_match_method,
                   source_type, source_meeting_id, source_url, source_external_id)
SELECT :'new_id'::uuid, t.user_id, :'pm_titulo', t.project_id, t.priority,
       coalesce(nullif(:'pm_fecha','')::timestamptz, t.due_date),
       :'new_status'::task_status,
       (:'new_status' = 'completed'),
       CASE WHEN :'new_status' = 'completed'
            THEN coalesce(nullif(:'pm_completada','')::timestamptz, t.completed_at) END,
       t.column_id, t.position, t.assignee,
       t.archetype_id, t.archetype_confidence, t.archetype_match_method,
       t.source_type, t.source_meeting_id,
       coalesce(t.source_url, :'pm_url'), :'pm_id'
FROM tasks t WHERE t.id = :'old_id'::uuid;

-- Sin fecha real de cierre (ni en PM ni en la original), completed_at debe
-- quedar NULL — filosofía de la migración 003: una métrica equivocada es peor
-- que una ausente. El trigger sella now() en el INSERT; esto lo deshace.
UPDATE tasks SET completed_at = NULL
WHERE id = :'new_id'::uuid AND :'new_status' = 'completed'
  AND nullif(:'pm_completada','') IS NULL
  AND NOT EXISTS (SELECT 1 FROM tasks o WHERE o.id = :'old_id'::uuid AND o.completed_at IS NOT NULL);
EOF

read -r -d '' SQL_PLANTILLA <<'EOF' || true
-- contract from the archetype template, {proyecto} filled, other slots neutralized
INSERT INTO task_inputs (task_id, title, description, io_type_id, artifact_type_id, is_required, position)
SELECT :'new_id'::uuid, pg_temp.slotclean(ai.title, :'projname'), pg_temp.slotclean(ai.description, :'projname'),
       ai.io_type_id, ai.artifact_type_id, ai.is_required, ai.position
FROM archetype_inputs ai JOIN tasks t ON t.id = :'old_id'::uuid AND ai.archetype_id = t.archetype_id;

WITH no AS (
  INSERT INTO task_outputs (task_id, title, description, io_type_id, artifact_type_id, is_required, position)
  SELECT :'new_id'::uuid, pg_temp.slotclean(ao.title, :'projname'), pg_temp.slotclean(ao.description, :'projname'),
         ao.io_type_id, ao.artifact_type_id, ao.is_required, ao.position
  FROM archetype_outputs ao JOIN tasks t ON t.id = :'old_id'::uuid AND ao.archetype_id = t.archetype_id
  RETURNING id, position
)
INSERT INTO task_acceptance_criteria (output_id, criterion, criterion_category, verification_method, is_required, position)
SELECT no.id, pg_temp.slotclean(ac.criterion, :'projname'), ac.criterion_category,
       ac.verification_method, ac.is_required, ac.position
FROM archetype_acceptance_criteria ac
JOIN archetype_outputs ao ON ao.id = ac.output_id
JOIN tasks t ON t.id = :'old_id'::uuid AND ao.archetype_id = t.archetype_id
JOIN no ON no.position = ao.position;
EOF

read -r -d '' SQL_COPIA <<'EOF' || true
-- contract cloned from the original's live rows (bindings kept, state reset)
INSERT INTO task_inputs (task_id, title, description, io_type_id, artifact_type_id,
                         artifact_reference, is_required, position, metadata)
SELECT :'new_id'::uuid, title, description, io_type_id, artifact_type_id,
       artifact_reference, is_required, position, metadata
FROM task_inputs WHERE task_id = :'old_id'::uuid;

WITH old_o AS (SELECT * FROM task_outputs WHERE task_id = :'old_id'::uuid),
no AS (
  INSERT INTO task_outputs (task_id, title, description, io_type_id, artifact_type_id,
                            deliverable_reference, content_resolver, is_required, position, metadata)
  SELECT :'new_id'::uuid, title, description, io_type_id, artifact_type_id,
         deliverable_reference, content_resolver, is_required, position, metadata
  FROM old_o
  RETURNING id, position
)
INSERT INTO task_acceptance_criteria (output_id, criterion, criterion_category, verification_method, is_required, position)
SELECT no.id, c.criterion, c.criterion_category, c.verification_method, c.is_required, c.position
FROM task_acceptance_criteria c
JOIN old_o oo ON oo.id = c.output_id
JOIN no ON no.position = oo.position;
EOF

read -r -d '' SQL_TAIL <<'EOF' || true
-- the trail travels with the work: comments and todos, timestamps preserved
INSERT INTO task_comments (task_id, user_id, author_name, author_avatar, text, created_at)
SELECT :'new_id'::uuid, user_id, author_name, author_avatar, text, created_at
FROM task_comments WHERE task_id = :'old_id'::uuid ORDER BY created_at;

INSERT INTO task_todos (task_id, text, completed, position, created_at)
SELECT :'new_id'::uuid, text, completed, position, created_at
FROM task_todos WHERE task_id = :'old_id'::uuid;

-- merge provenance, on both sides
INSERT INTO task_comments (task_id, author_name, text)
SELECT :'new_id'::uuid, 'merge-cruce',
       'Creada por merge del cruce PM↔cerebro (fila n='||:'n'||'): reemplaza '||left(:'old_id',8)
       ||' («'||coalesce((SELECT title FROM tasks WHERE id=:'old_id'::uuid),'?')
       ||'»). Título de la plataforma PM ('||left(:'pm_id',8)||'); contrato: '||:'contrato'||'.';

UPDATE tasks SET status='cancelled'::task_status WHERE id = :'old_id'::uuid;

INSERT INTO task_comments (task_id, author_name, text)
SELECT :'old_id'::uuid, 'merge-cruce',
       'Cancelada por merge del cruce PM↔cerebro → fusionada en '||left(:'new_id',8)
       ||' («'||:'pm_titulo'||'», fila n='||:'n'||').';

\echo '==== DESPUÉS ===='
SELECT left(id::text,8) AS id, status, left(title,60) AS title,
       to_char(completed_at,'YYYY-MM-DD') AS completada,
       (SELECT count(*) FROM task_outputs o WHERE o.task_id=tasks.id) AS outs,
       (SELECT count(*) FROM task_comments c WHERE c.task_id=tasks.id) AS comments
FROM tasks WHERE id IN (:'old_id'::uuid, :'new_id'::uuid) ORDER BY status;
EOF

merged=0 failed=0
while IFS=$'\t' read -r n ce_id pm_id pm_titulo pm_estado pm_fecha pm_completada; do
  [[ -n "$n" ]] || continue

  # Pre-check the original: resolve the id (cruce stores the 8-char prefix),
  # require exactly one match, and refuse an already-cancelled task.
  old="$(psql_ro -Atc "SELECT t.id::text||'|'||t.status||'|'||coalesce((SELECT name FROM projects p WHERE p.id=t.project_id),'')
                       FROM tasks t WHERE t.id::text LIKE '${ce_id//\'/}%'")" || old=""
  if [[ -z "$old" || "$(wc -l <<<"$old")" -ne 1 ]]; then
    echo "n=$n: la tarea original '$ce_id' no resuelve a exactamente una tarea — omitida." >&2
    failed=$((failed+1)); continue
  fi
  IFS='|' read -r ce_id old_status projname <<<"$old"
  if [[ "$old_status" == "cancelled" ]]; then
    echo "n=$n: la original ${ce_id:0:8} ya está cancelada — omitida." >&2
    failed=$((failed+1)); continue
  fi

  # Resolved status: completed if either side completed, else in_progress if
  # either side is, else pending. (PM dates win when the PM side completed.)
  new_status="pending"
  [[ "$pm_estado" == "in_progress" || "$old_status" == "in_progress" ]] && new_status="in_progress"
  [[ "$pm_estado" == "completed"   || "$old_status" == "completed"   ]] && new_status="completed"
  [[ "$pm_estado" == "completed" ]] || pm_completada=""

  # Contract mode for THIS pair: plantilla needs an archetype with a template.
  mode="$contrato"
  if [[ "$mode" == "plantilla" ]]; then
    hastpl="$(psql_ro -Atc "SELECT EXISTS(
      SELECT 1 FROM tasks t WHERE t.id='$ce_id' AND t.archetype_id IS NOT NULL
        AND (EXISTS(SELECT 1 FROM archetype_inputs  ai WHERE ai.archetype_id=t.archetype_id)
          OR EXISTS(SELECT 1 FROM archetype_outputs ao WHERE ao.archetype_id=t.archetype_id)))")"
    [[ "$hastpl" == "t" ]] || mode="copia"
  fi
  branch="$SQL_COPIA"; [[ "$mode" == "plantilla" ]] && branch="$SQL_PLANTILLA"

  new_id="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  endcmd="COMMIT;"; [[ "$dry" == 1 ]] && endcmd="ROLLBACK;"

  echo "── n=$n · ${ce_id:0:8} → $([[ $dry == 1 ]] && echo '(dry-run) ')${new_id:0:8} · contrato=$mode · estado=$new_status"
  if printf '%s\n%s\n%s\n%s\n' "$SQL_HEAD" "$branch" "$SQL_TAIL" "$endcmd" | psql_rw \
      -v n="$n" -v old_id="$ce_id" -v new_id="$new_id" -v pm_id="$pm_id" \
      -v pm_titulo="$pm_titulo" -v pm_fecha="$pm_fecha" -v pm_completada="$pm_completada" \
      -v pm_url="$PM_API_BASE/$pm_id" -v new_status="$new_status" \
      -v projname="$projname" -v contrato="$mode" -f -; then
    if [[ "$dry" == 0 ]]; then
      sqlite3 "$SQLITE_DB" "UPDATE cruce SET resuelta=1,
        resolucion='merge → $new_id',
        resuelta_en=strftime('%Y-%m-%dT%H:%M:%SZ','now') WHERE n=$n;"
    fi
    merged=$((merged+1))
    [[ "$json" == 1 ]] && printf '{"n":%s,"old_id":"%s","new_id":"%s","status":"%s","contrato":"%s"}\n' \
      "$n" "$ce_id" "$new_id" "$new_status" "$mode"
  else
    echo "n=$n: la transacción falló — la fila queda sin resolver." >&2
    failed=$((failed+1))
  fi
done <<<"$worklist"

if [[ "$json" == 1 ]]; then
  printf '{"ok":%s,"merged":%d,"failed":%d,"dry_run":%s}\n' \
    "$([[ $failed == 0 ]] && echo true || echo false)" "$merged" "$failed" "$([[ $dry == 1 ]] && echo true || echo false)"
else
  echo "════ $merged mezcla(s)$([[ $dry == 1 ]] && echo ' (dry-run, todo revertido)'), $failed fallida(s)/omitida(s)."
fi
[[ "$failed" == 0 ]]

#!/usr/bin/env bash
# link_external.sh — WRITE: vincular una tarea EXISTENTE del cerebro con su
# gemela en un sistema externo (hoy: la plataforma PM). Escribe
# source_external_id (+ source_url) sobre una fila que ya existe.
#
# POR QUÉ EXISTE
# El cruce PM↔cerebro sabe expresar dos desenlaces —«fusionada» y «resuelta»—
# pero le faltaba el tercero, que es el más común: **vinculada sin mezclar**.
# Son las dos tareas que describen el mismo trabajo, cada una nacida en su
# sistema, donde no hay nada que fusionar porque la del cerebro ya está
# completa: solo falta decir que son la misma. Hasta hoy eso solo se podía
# dejar escrito en prosa (en `cruce.resolucion` o en un comentario), y la prosa
# no la lee ningún chequeo: 13 tareas abiertas en PM figuraban como «sin
# representación en el cerebro» el 2026-08-20 cuando todas estaban cubiertas.
# El propio cruce ya proponía `accion='vincular'` en 17 filas y no había con qué.
#
# QUÉ NO TOCA — y por qué importa
#   · `source_type` : describe DÓNDE NACIÓ la tarea, no con qué sistema está
#                     sincronizada. Una tarea nacida de un acta que hoy está
#                     emparejada con PM sigue siendo `meeting`. Pisarlo borraría
#                     su procedencia real.
#   · `status`, fechas, contrato, asignados : nada. Esto solo declara identidad.
#
# GUARDAS
#   · Si la tarea ya tiene un source_external_id DISTINTO, se niega. Una columna
#     no es una lista: cuando varias tareas del sistema externo apuntan a UNA del
#     cerebro (duplicados del lado externo), esto no alcanza y hace falta una
#     tabla de enlaces. Negarse es más honesto que pisar el enlace anterior.
#   · Si el id externo ya está en OTRA tarea, se niega: dos tareas del cerebro
#     reclamando la misma gemela hace ambiguo cualquier chequeo de cobertura.
#   · Re-vincular al MISMO valor es idempotente: informa y sale 0, sin comentar
#     de nuevo.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

usage() { sed -n '2,40p' "$0"; cat <<'EOF'

Uso:
  link_external.sh <id|prefijo> --external <id-externo> [--url URL]
                   [--sistema NOMBRE] [--nota "…"] [--author N] [--dry-run] [--json]

  --external  el id estable en el sistema externo (p.ej. el uuid de la tarea en PM)
  --url       URL del recurso externo (se escribe en source_url si está vacío)
  --sistema   nombre legible para el comentario (default: "la plataforma PM")
  --nota      contexto adicional para el comentario
EOF
}

tref="${1:-}"
[[ -z "$tref" || "$tref" == "-h" || "$tref" == "--help" ]] && { usage; exit 0; }
shift
ext="" url="" sistema="la plataforma PM" nota="" author="link_external" dry=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --external) ext="${2:?}"; shift 2 ;;
    --url)      url="${2:?}"; shift 2 ;;
    --sistema)  sistema="${2:?}"; shift 2 ;;
    --nota)     nota="${2:?}"; shift 2 ;;
    --author)   author="${2:?}"; shift 2 ;;
    --dry-run)  dry=1; shift ;;
    --json)     FORMAT=json; shift ;;
    *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$ext" ]] || { echo "Falta --external <id-externo>." >&2; exit 2; }

resolve_task() {
  local ref="$1" ids n
  ids="$(psql_ro -t -A -c "SELECT id FROM tasks WHERE id::text LIKE '${ref//\'/\'\'}%'")"
  n="$(printf '%s\n' "$ids" | grep -c . || true)"
  [[ "$n" -eq 1 ]] || { echo "El id '$ref' resuelve a $n tareas (hace falta 1)." >&2; return 1; }
  printf '%s' "$ids"
}
tid="$(resolve_task "$tref")" || exit 1

# --- Guardas (antes de abrir transacción: son de negocio, no de concurrencia) --
actual="$(psql_ro -t -A -c "SELECT coalesce(source_external_id,'') FROM tasks WHERE id='$tid'")"
if [[ -n "$actual" && "$actual" != "$ext" ]]; then
  cat >&2 <<EOF
La tarea ${tid:0:8} YA está vinculada a '$actual', distinto de '$ext'.

No lo piso: source_external_id es UNA columna, no una lista. Si varias tareas
del sistema externo describen esta misma, el modelo que hace falta es una tabla
de enlaces (task_id, sistema, id_externo), no sobreescribir el que ya está.
Mientras tanto, dejá constancia con: bash/tasks/add_comment.sh ${tid:0:8} --text "…"
EOF
  exit 4
fi
# Solo compiten las tareas VIVAS. Una cancelada conserva su id externo como
# procedencia (es justo el rastro de «esta copia se fusionó en aquélla»), y
# bloquear por ella impediría que la superviviente reclame la identidad.
otra="$(psql_ro -t -A -c "SELECT left(id::text,8) FROM tasks WHERE source_external_id='${ext//\'/\'\'}' AND id<>'$tid' AND status <> 'cancelled'")"
if [[ -n "$otra" ]]; then
  echo "El id externo '$ext' ya está en la tarea viva $otra — dos tareas no pueden reclamar la misma gemela." >&2
  exit 4
fi
muerta="$(psql_ro -t -A -c "SELECT left(id::text,8) FROM tasks WHERE source_external_id='${ext//\'/\'\'}' AND id<>'$tid' AND status = 'cancelled'")"
[[ -n "$muerta" ]] && echo "nota: la tarea cancelada $muerta también lleva ese id externo (conserva su procedencia)." >&2
if [[ "$actual" == "$ext" ]]; then
  echo "${tid:0:8} ya estaba vinculada a '$ext' — nada que hacer."
  exit 0
fi

end="COMMIT"; [[ -n "$dry" ]] && end="ROLLBACK"
psql_rw -v tid="$tid" -v ext="$ext" -v url="$url" -v sistema="$sistema" \
        -v nota="$nota" -v author="$author" <<SQL
BEGIN;
\echo '==== ANTES ===='
SELECT left(id::text,8) AS id, status, coalesce(source_type::text,'—') AS tipo,
       coalesce(left(source_external_id,8),'(sin vínculo)') AS externo, left(title,48) AS title
FROM tasks WHERE id = :'tid'::uuid;

-- source_type NO se toca: dice dónde nació la tarea, no con quién sincroniza.
UPDATE tasks
   SET source_external_id = :'ext',
       source_url = coalesce(source_url, nullif(:'url',''))
 WHERE id = :'tid'::uuid;

INSERT INTO task_comments (task_id, author_name, text)
SELECT :'tid'::uuid, :'author',
       'Vinculada con '||:'sistema'||': id externo '||:'ext'||'. '
       || 'Misma obra, dos sistemas — no se fusionó nada, solo se declara la identidad.'
       || CASE WHEN nullif(:'nota','') IS NOT NULL THEN ' '||:'nota' ELSE '' END;

\echo '==== DESPUÉS ===='
SELECT left(id::text,8) AS id, status, coalesce(source_type::text,'—') AS tipo,
       coalesce(left(source_external_id,8),'(sin vínculo)') AS externo, left(title,48) AS title
FROM tasks WHERE id = :'tid'::uuid;
$end;
SQL

[[ -n "$dry" ]] && echo "(dry-run: revertido, nada escrito)"

exit 0

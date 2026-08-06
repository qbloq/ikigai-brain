#!/usr/bin/env bash
# Registrar la VERIFICACIÓN de uno o más criterios de aceptación: marcarlos
# cumplidos (is_met) dejando quién verificó, cuándo y con qué evidencia.
# WRITE, transaccional, --dry-run hace rollback.
#
# Uso:
#   verify_criteria.sh --crit <id|prefijo> [--crit <id|prefijo>…]
#                      --by NOMBRE --notes "evidencia"
#                      [--confidence high|medium|low] [--at YYYY-MM-DD]
#                      [--unmet] [--dry-run] [--json]
#
#   --by NOMBRE      quién verifica. Va a verified_by; sin firma no hay
#                    verificación, hay un checkbox.
#   --notes TEXTO    la evidencia CONCRETA (ruta del entregable, cifra, corrida
#                    que lo prueba). Obligatorio, y esa es la idea: un criterio
#                    marcado sin decir contra qué se comprobó no se distingue de
#                    uno marcado por pereza, y el contrato deja de significar.
#   --at FECHA       cuándo se verificó de verdad (default: ahora).
#   --unmet          revierte: is_met=false y limpia verified_*/notes/confidence.
#                    Para cuando la evidencia se cae o el entregable cambia.
#
# Es el complemento de update_task_criteria.sh, que edita el CONTRATO (texto,
# método, required) y a propósito no toca el estado. Esto toca el ESTADO y a
# propósito no toca el contrato: mover el criterio y declararlo cumplido en la
# misma corrida es cómo un contrato se reescribe para que dé cumplido.
#
# ⚠️ Los criterios con verification_method='attested' se RECHAZAN. Ese método
# significa que un humano lo confirma por WhatsApp y queda en task_attestations;
# teclearlo aquí falsifica la confirmación de una persona. Si el criterio no
# necesita atestación, cámbiale el método con update_task_criteria.sh — y que
# ese cambio quede como el acto explícito que es.
#
# Los ya verificados se omiten, no se reescriben: correrlo dos veces no mueve
# una fecha ni pisa una firma.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

[[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { sed -n '2,35p' "$0"; exit 0; }

crits=() by="" notes="" conf="" at="" unmet="" dry=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --crit)       crits+=("${2//\'/}"); shift 2 ;;
    --by)         by="$2"; shift 2 ;;
    --notes)      notes="$2"; shift 2 ;;
    --confidence) conf="$2"; shift 2 ;;
    --at)         at="$2"; shift 2 ;;
    --unmet)      unmet=1; shift ;;
    --dry-run)    dry=1; shift ;;
    --json)       FORMAT=json; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ ${#crits[@]} -eq 0 ]] && { echo "Falta al menos un --crit." >&2; exit 2; }
if [[ -z "$unmet" ]]; then
  [[ -n "$by" ]]    || { echo "Falta --by: una verificación sin firma no es una verificación." >&2; exit 2; }
  [[ -n "$notes" ]] || { echo "Falta --notes: hay que decir contra qué evidencia se comprobó." >&2; exit 2; }
fi
if [[ -n "$conf" && ! "$conf" =~ ^(high|medium|low)$ ]]; then
  echo "--confidence acepta high|medium|low (recibí '$conf')." >&2; exit 2
fi
if [[ -n "$at" && ! "$at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "--at espera YYYY-MM-DD (recibí '$at')." >&2; exit 2
fi

resolve_crit() { # prefijo → id completo; ambiguo o inexistente = error
  local ref="$1" ids n
  ids="$(psql_ro -t -A -c "SELECT id FROM task_acceptance_criteria WHERE id::text LIKE '${ref//\'/\'\'}%'")"
  n="$(printf '%s\n' "$ids" | grep -c . || true)"
  [[ "$n" -eq 1 ]] || { echo "Criterio '$ref' resolvió a $n filas (necesito 1)." >&2; return 1; }
  printf '%s' "$ids"
}

ids=()
for c in "${crits[@]}"; do ids+=("$(resolve_crit "$c")") || exit 1; done
list="$(printf "'%s'," "${ids[@]}")"; list="${list%,}"

# Atestados: se rechaza la corrida ENTERA antes de escribir. Marcar uno solo por
# error deja en la base una confirmación humana que ningún humano dio.
if [[ -z "$unmet" ]]; then
  att="$(psql_ro -t -A -c "
    SELECT string_agg(left(id::text,8), ', ')
    FROM task_acceptance_criteria WHERE id IN ($list) AND verification_method = 'attested';")"
  if [[ -n "$att" ]]; then
    echo "Estos criterios son 'attested': $att" >&2
    echo "Se confirman por WhatsApp (task_attestations); teclearlos aquí falsifica la firma de una persona." >&2
    exit 3
  fi
fi

# Ya verificados: se avisan y se excluyen del UPDATE.
if [[ -z "$unmet" ]]; then
  done_already="$(psql_ro -t -A -c "
    SELECT string_agg(left(id::text,8), ', ')
    FROM task_acceptance_criteria WHERE id IN ($list) AND coalesce(is_met,false);")"
  [[ -n "$done_already" ]] && echo "Ya estaban verificados (se omiten): $done_already" >&2
fi

end="COMMIT"; [[ -n "$dry" ]] && end="ROLLBACK"

if [[ -n "$unmet" ]]; then
  SET_SQL="SET is_met = false, verified_at = NULL, verified_by = NULL,
               verification_notes = NULL, confidence = NULL,
               requires_reverification = false"
  WHERE_SQL="coalesce(is_met,false) = true"
  ACTION="revertidos"
else
  # coalesce y no CASE: Postgres pliega el literal ''::timestamptz al analizar,
  # así que un CASE revienta cuando --at viene vacío aunque esa rama no corra.
  SET_SQL="SET is_met = true,
               verified_at = coalesce(nullif(:'at','')::timestamptz, now()),
               verified_by = :'by',
               verification_notes = :'notes',
               confidence = nullif(:'conf',''),
               requires_reverification = false"
  WHERE_SQL="coalesce(is_met,false) = false"
  ACTION="verificados"
fi

psql_rw -v by="$by" -v notes="$notes" -v conf="$conf" -v at="$at" <<SQL
BEGIN;
\echo '==== ANTES ===='
SELECT left(c.id::text,8) AS crit, c.verification_method AS metodo, c.is_met,
       c.verified_by, to_char(c.verified_at,'YYYY-MM-DD') AS verificado,
       left(c.criterion,58) AS criterio
FROM task_acceptance_criteria c WHERE c.id IN ($list) ORDER BY c.position;

UPDATE task_acceptance_criteria
   $SET_SQL
 WHERE id IN ($list) AND $WHERE_SQL;

\echo '==== DESPUÉS ===='
SELECT left(c.id::text,8) AS crit, c.is_met, c.verified_by,
       to_char(c.verified_at,'YYYY-MM-DD') AS verificado, c.confidence AS conf,
       left(coalesce(c.verification_notes,''),58) AS evidencia
FROM task_acceptance_criteria c WHERE c.id IN ($list) ORDER BY c.position;

-- El estado del OUTPUT queda a la vista: cuántos criterios requeridos faltan.
-- No se toca is_delivered — que los criterios se cumplan y que el entregable
-- esté entregado son dos hechos distintos, y colapsarlos aquí sería inventar.
\echo '==== OUTPUT ===='
SELECT left(o.id::text,8) AS output, o.is_delivered AS entregado,
       count(*) FILTER (WHERE c.is_required) AS req,
       count(*) FILTER (WHERE c.is_required AND c.is_met) AS req_ok,
       left(o.title,44) AS titulo
FROM task_outputs o JOIN task_acceptance_criteria c ON c.output_id = o.id
WHERE o.id IN (SELECT output_id FROM task_acceptance_criteria WHERE id IN ($list))
GROUP BY o.id, o.is_delivered, o.title;
$end;
SQL

[[ -n "$dry" ]] && echo "(dry-run: rolled back, nothing written)"
echo "($ACTION)"
exit 0

#!/usr/bin/env bash
# Reasignar la CARTERA (payment_plans.user_id) de un dueño a otro. WRITE
# (psql_rw). Una transacción, before/after, --dry-run para previsualizar.
#
# El dueño de un plan es users.id (→persons), NO team_members.id — por eso
# este script trae su propio resolvedor y no usa resolve_member. La cartera
# es el conjunto de planes del dueño con cuotas pendientes
# (Scheduled/Partial/Overdue); los planes ya saldados no se tocan salvo
# --incluir-saldados. Nada se borra: cambia el dueño y updated_at, y las
# comisiones ya generadas (commission_payouts) conservan su user_id propio.
#
# Usage:
#   reasignar_planes.sh --de <user> --a <user> [--planes 1,2,3] [--dry-run]
#     --de / --a   fragmento de nombre o prefijo de users.id (único, o error)
#     --planes     lista de plan_id; default: toda la cartera pendiente de --de
#     --incluir-saldados   con default (sin --planes): también planes sin deuda
#     --dry-run    preview: misma txn, ROLLBACK al final
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

de="" a="" planes="" dry="" saldados=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --de)     de="$2"; shift 2 ;;
    --a)      a="$2"; shift 2 ;;
    --planes) planes="$2"; shift 2 ;;
    --incluir-saldados) saldados=1; shift ;;
    --dry-run) dry=1; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$de" || -z "$a" ]] && { echo "--de y --a son obligatorios" >&2; exit 2; }

# resolve_user <token> : users.id por prefijo de id o fragmento de nombre.
resolve_user() {
  local tok="$1" esc rows n
  esc="${tok//\'/\'\'}"
  rows="$(psql_ro -t -A -F'|' -c "
    SELECT u.id, trim(coalesce(p.name,'')||' '||coalesce(p.lastname,''))
    FROM users u JOIN persons p ON p.person_id = u.person_id
    WHERE u.id::text LIKE '${esc}%'
       OR trim(coalesce(p.name,'')||' '||coalesce(p.lastname,'')) ILIKE '%${esc}%'
    ORDER BY 2;")"
  if [[ -z "$rows" ]]; then echo "resolve_user: sin match para '$tok'" >&2; return 1; fi
  n="$(printf '%s\n' "$rows" | grep -c .)"
  if [[ "$n" -gt 1 ]]; then
    { echo "resolve_user: '$tok' es ambiguo ($n matches):"
      printf '%s\n' "$rows" | sed 's/^/  /'; } >&2
    return 1
  fi
  printf '%s' "${rows%%|*}"
}

uid_de="$(resolve_user "$de")" || exit 1
uid_a="$(resolve_user "$a")"   || exit 1
[[ "$uid_de" == "$uid_a" ]] && { echo "--de y --a resuelven al mismo user" >&2; exit 2; }

# Qué planes se mueven
if [[ -n "$planes" ]]; then
  [[ "$planes" =~ ^[0-9]+(,[0-9]+)*$ ]] || { echo "--planes debe ser lista de ids numéricos" >&2; exit 2; }
  where="pp.plan_id IN ($planes) AND pp.user_id = '$uid_de'"
else
  where="pp.user_id = '$uid_de'"
  [[ -z "$saldados" ]] && where+=" AND EXISTS (SELECT 1 FROM installments i
      WHERE i.plan_id = pp.plan_id AND i.status IN ('Scheduled','Partial','Overdue'))"
fi

show_sql="SELECT pp.plan_id, pp.customer_name,
       trim(coalesce(p.name,'')||' '||coalesce(p.lastname,'')) AS dueno,
       (SELECT coalesce(sum(i.scheduled_amount - coalesce(i.paid_amount,0)),0)
        FROM installments i WHERE i.plan_id = pp.plan_id
          AND i.status IN ('Scheduled','Partial','Overdue')) AS monto_pend
FROM payment_plans pp
JOIN users u ON u.id = pp.user_id
JOIN persons p ON p.person_id = u.person_id
WHERE pp.plan_id IN (SELECT plan_id FROM _mover)
ORDER BY monto_pend DESC"

end="COMMIT"; [[ -n "$dry" ]] && end="ROLLBACK"

psql_rw <<SQL
BEGIN;
CREATE TEMP TABLE _mover ON COMMIT DROP AS
  SELECT pp.plan_id FROM payment_plans pp WHERE $where;
\echo '--- ANTES ---'
$show_sql;
UPDATE payment_plans pp SET user_id = '$uid_a', updated_at = now()
WHERE pp.plan_id IN (SELECT plan_id FROM _mover);
\echo '--- DESPUÉS ---'
$show_sql;
$end;
SQL

[[ -n "$dry" ]] && echo "(dry-run: rollback, sin cambios)"

exit 0

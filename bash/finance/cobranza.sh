#!/usr/bin/env bash
# Collections view over payment-plan installments (all USD). Default: every
# UNCOLLECTED installment (Scheduled/Partial/Overdue) with days overdue and
# aging bucket, ordered by due date. `Overdue` is computed from due_date —
# the status column is not reliably maintained.
#
# Usage:
#   cobranza.sh [--overdue] [--upcoming N] [--project NAME] [--customer FRAG]
#               [--all] [--summary] [--limit N] [--json]
#
#   --overdue      only installments past due (due_date < today, unpaid)
#   --upcoming N   only installments due in the next N days (unpaid)
#   --project      restrict to one project (client)
#   --customer     filter by customer name fragment
#   --all          include Paid/Cancelled too (full history)
#   --summary      aging buckets per project (counts + amounts) instead of rows
#   --limit N      default 100; 0 = no cap
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

overdue=0 upcoming="" project="" customer="" all=0 summary=0 limit=100
while [[ $# -gt 0 ]]; do
  case "$1" in
    --overdue)  overdue=1; shift ;;
    --upcoming) upcoming="$2"; shift 2 ;;
    --project)  project="$2"; shift 2 ;;
    --customer) customer="$2"; shift 2 ;;
    --all)      all=1; shift ;;
    --summary)  summary=1; shift ;;
    --limit)    limit="$2"; shift 2 ;;
    --json)     FORMAT=json; shift ;;
    -h|--help)  sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

where="true"
[[ "$all" == 0 ]] && where="$where AND i.status IN ('Scheduled','Partial','Overdue')"
[[ "$overdue" == 1 ]] && where="$where AND i.due_date < current_date"
[[ -n "$upcoming" ]] && where="$where AND i.due_date BETWEEN current_date AND current_date + ${upcoming//\'/}::int"
[[ -n "$customer" ]] && where="$where AND pp.customer_name ILIKE '%${customer//\'/\'\'}%'"
if [[ -n "$project" ]]; then
  pid="$(resolve_project "$project")"
  [[ -z "$pid" ]] && { echo "No project matches: $project" >&2; exit 1; }
  where="$where AND pp.project_id = '$pid'"
fi

# Aging bucket: negative days = not yet due, positive = overdue.
BUCKET="CASE
  WHEN i.due_date >= current_date + 31 THEN 'por vencer >30d'
  WHEN i.due_date >= current_date + 8  THEN 'por vencer 8-30d'
  WHEN i.due_date >= current_date      THEN 'por vencer 0-7d'
  WHEN i.due_date >= current_date - 7  THEN 'vencida 1-7d'
  WHEN i.due_date >= current_date - 30 THEN 'vencida 8-30d'
  ELSE 'vencida >30d' END"

if [[ "$summary" == 1 ]]; then
  emit "SELECT coalesce(pr.name,'—') AS project,
         $BUCKET AS bucket,
         count(*) AS cuotas,
         round(sum(i.scheduled_amount - coalesce(i.paid_amount,0)), 2) AS por_cobrar
  FROM ikigaigm.installments i
  JOIN ikigaigm.payment_plans pp ON pp.plan_id = i.plan_id
  LEFT JOIN ikigaigm.projects pr ON pr.id = pp.project_id
  WHERE $where
  GROUP BY 1, 2
  ORDER BY 1, min(i.due_date)"
else
  lim=""; [[ "$limit" != 0 ]] && lim="LIMIT $limit"
  emit "SELECT i.installment_id AS id,
         coalesce(pr.name,'—')                       AS project,
         left(coalesce(pp.customer_name,'—'), 32)    AS customer,
         i.installment_number || '/' || pp.number_of_installments AS cuota,
         to_char(i.due_date,'YYYY-MM-DD')            AS due,
         (current_date - i.due_date)                 AS days_over,
         $BUCKET                                     AS bucket,
         i.scheduled_amount                          AS scheduled,
         coalesce(i.paid_amount,0)                   AS paid,
         round(i.scheduled_amount - coalesce(i.paid_amount,0), 2) AS pendiente,
         i.status::text                              AS status,
         i.collection_attempts                       AS attempts
  FROM ikigaigm.installments i
  JOIN ikigaigm.payment_plans pp ON pp.plan_id = i.plan_id
  LEFT JOIN ikigaigm.projects pr ON pr.id = pp.project_id
  WHERE $where
  ORDER BY i.due_date, pr.name
  $lim"
fi

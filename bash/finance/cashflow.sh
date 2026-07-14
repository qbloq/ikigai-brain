#!/usr/bin/env bash
# Cash flow over the economics ledger (all USD): money in vs money out, net,
# by month (default), by entry type, or the month×type matrix. Entry types:
# revenue (+), expense_opex / expense_commission / distribution (−).
#
# Usage:
#   cashflow.sh [--by month|type|month-type] [--project NAME]
#               [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--json]
#
#   --by DIM       default: month
#   --project      restrict to one project (client)
#   --from / --to  entry-date window (default: all history)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

by="month" project="" from="" to=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --by)      by="$2"; shift 2 ;;
    --project) project="$2"; shift 2 ;;
    --from)    from="$2"; shift 2 ;;
    --to)      to="$2"; shift 2 ;;
    --json)    FORMAT=json; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

where="true"
[[ -n "$from" ]] && where="$where AND l.entry_date >= '${from//\'/}'"
[[ -n "$to" ]]   && where="$where AND l.entry_date <= '${to//\'/}'"
if [[ -n "$project" ]]; then
  pid="$(resolve_project "$project")"
  [[ -z "$pid" ]] && { echo "No project matches: $project" >&2; exit 1; }
  where="$where AND l.project_id = '$pid'"
fi

case "$by" in
  month)
    emit "SELECT to_char(date_trunc('month', l.entry_date),'YYYY-MM') AS month,
           count(*) AS entries,
           round(coalesce(sum(l.amount_base) FILTER (WHERE l.entry_type='revenue'),0), 2)              AS entradas,
           round(coalesce(sum(l.amount_base) FILTER (WHERE l.entry_type='expense_opex'),0), 2)         AS opex,
           round(coalesce(sum(l.amount_base) FILTER (WHERE l.entry_type='expense_commission'),0), 2)   AS comisiones,
           round(coalesce(sum(l.amount_base) FILTER (WHERE l.entry_type='distribution'),0), 2)         AS reparto,
           round(sum(l.amount_base), 2) AS neto
    FROM ikigaigm.economics_ledger l
    WHERE $where
    GROUP BY 1 ORDER BY 1" ;;
  type)
    emit "SELECT l.entry_type,
           count(*) AS entries,
           round(sum(l.amount_base), 2) AS total,
           to_char(min(l.entry_date),'YYYY-MM-DD') AS first,
           to_char(max(l.entry_date),'YYYY-MM-DD') AS last
    FROM ikigaigm.economics_ledger l
    WHERE $where
    GROUP BY 1 ORDER BY total DESC" ;;
  month-type)
    emit "SELECT to_char(date_trunc('month', l.entry_date),'YYYY-MM') AS month,
           l.entry_type,
           count(*) AS entries,
           round(sum(l.amount_base), 2) AS total
    FROM ikigaigm.economics_ledger l
    WHERE $where
    GROUP BY 1, 2 ORDER BY 1, 2" ;;
  *) echo "--by inválido: '$by' (month|type|month-type)" >&2; exit 2 ;;
esac

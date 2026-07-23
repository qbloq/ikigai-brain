#!/usr/bin/env bash
# Commission payouts (closers & contractors) with the person resolved and the
# review state — the COO's approval queue (status: pending → approved → paid;
# also rejected/cancelled). Amounts in base currency (USD).
#
# Usage:
#   comisiones.sh [--status S] [--person FRAG] [--project NAME]
#                 [--from YYYY-MM-DD] [--to YYYY-MM-DD]
#                 [--by status|person|project|month] [--limit N] [--json]
#
#   --status S     pending | approved | paid | rejected | cancelled
#   --person FRAG  person name / contractor fragment
#   --from / --to  filter by creation date (default: all history)
#   --by DIM       aggregate view instead of the row list
#   --limit N      default 100; 0 = no cap
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

status="" person="" project="" from="" to="" by="" limit=100
while [[ $# -gt 0 ]]; do
  case "$1" in
    --status)  status="$2"; shift 2 ;;
    --person)  person="$2"; shift 2 ;;
    --project) project="$2"; shift 2 ;;
    --from)    from="$2"; shift 2 ;;
    --to)      to="$2"; shift 2 ;;
    --by)      by="$2"; shift 2 ;;
    --limit)   limit="$2"; shift 2 ;;
    --json)    FORMAT=json; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

PERSON_SQL="coalesce(
  nullif(trim(coalesce(p.name,'')||' '||coalesce(p.lastname,'')), ''),
  cp.contractor_name, '(sin persona)')"

where="true"
[[ -n "$status" ]] && where="$where AND cp.status = '${status//\'/\'\'}'"
[[ -n "$person" ]] && where="$where AND $PERSON_SQL ILIKE '%${person//\'/\'\'}%'"
[[ -n "$from" ]]   && where="$where AND cp.created_at::date >= '${from//\'/}'"
[[ -n "$to" ]]     && where="$where AND cp.created_at::date <= '${to//\'/}'"
if [[ -n "$project" ]]; then
  pid="$(resolve_project "$project")"
  [[ -z "$pid" ]] && { echo "No project matches: $project" >&2; exit 1; }
  where="$where AND cp.project_id = '$pid'"
fi

FROMJOIN="FROM ikigaigm.commission_payouts cp
LEFT JOIN ikigaigm.projects pr ON pr.id = cp.project_id
LEFT JOIN ikigaigm.users u ON u.id = cp.user_id
LEFT JOIN ikigaigm.persons p ON p.person_id = u.person_id"

if [[ -n "$by" ]]; then
  case "$by" in
    status)  dim="cp.status::text" ;;
    person)  dim="$PERSON_SQL" ;;
    project) dim="coalesce(pr.name,'—')" ;;
    month)   dim="to_char(cp.created_at,'YYYY-MM')" ;;
    *) echo "--by inválido: '$by' (status|person|project|month)" >&2; exit 2 ;;
  esac
  emit "SELECT $dim AS $by,
         count(*) AS payouts,
         round(sum(cp.payout_amount_base), 2) AS total,
         count(*) FILTER (WHERE cp.status='pending')  AS pending,
         round(coalesce(sum(cp.payout_amount_base) FILTER (WHERE cp.status='pending'),0), 2) AS pending_amt,
         count(*) FILTER (WHERE cp.status='approved') AS approved,
         count(*) FILTER (WHERE cp.status='paid')     AS paid
  $FROMJOIN
  WHERE $where
  GROUP BY 1
  ORDER BY total DESC"
else
  lim=""; [[ "$limit" != 0 ]] && lim="LIMIT $limit"
  emit "SELECT left(cp.id::text, 8)                    AS id,
         $PERSON_SQL                                   AS person,
         cp.commission_type::text                      AS type,
         coalesce(pr.name,'—')                         AS project,
         round(cp.installment_paid_amount, 2)          AS base_amt,
         round(cp.payout_amount_base, 2)               AS payout,
         cp.status::text                               AS status,
         to_char(cp.created_at,'YYYY-MM-DD')           AS created,
         to_char(cp.paid_at,'YYYY-MM-DD')              AS paid_on
  $FROMJOIN
  WHERE $where
  ORDER BY cp.status = 'pending' DESC, cp.created_at DESC
  $lim"
fi

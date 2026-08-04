#!/usr/bin/env bash
# Insert or REPLACE the structured report (jsonb) for a team meeting. WRITE,
# single transaction, --dry-run rolls back. Upserts on the UNIQUE meeting_id:
# if a report exists it is overwritten "without looking back"; otherwise created.
#
# Usage:
#   upsert_report.sh <meeting-id|prefix> <report.json | -> [--dry-run]
#
# Pre-flight (read-only) checks: the meeting resolves to exactly one TEAM
# meeting, the JSON parses, and all 14 canonical report keys are present.
# Leaves report_es untouched (the whole corpus keeps it null).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

mref="${1:-}" src="${2:-}" dry=""
[[ -z "$mref" || "$mref" == "-h" || "$mref" == "--help" ]] && { sed -n '2,11p' "$0"; exit 0; }
[[ -z "$src" ]] && { echo "Missing <report.json|->; see -h" >&2; exit 2; }
shift 2 || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

tmp="$(mktemp "${TMPDIR:-/tmp}/report.XXXXXX.json")"
trap 'rm -f "$tmp"' EXIT
if [[ "$src" == "-" ]]; then cat > "$tmp"; else cp "$src" "$tmp"; fi
json="$(cat "$tmp")"

# JSON must parse (let psql be the judge via a cast in validation below), and
# resolve the meeting id up front.
mid="$(psql_ro -t -A -c "
  SELECT m.id FROM meetings m
  WHERE m.meeting_type='team' AND m.id::text LIKE '${mref//\'/\'\'}%'")"
n_mid="$(printf '%s\n' "$mid" | grep -c . || true)"
if [[ "$n_mid" -ne 1 ]]; then
  echo "Meeting ref '$mref' resolved to $n_mid team meetings (need exactly 1)." >&2
  [[ -n "$mid" ]] && printf '  %s\n' $mid >&2
  exit 1
fi

# --- Pre-flight validation (read-only): missing canonical keys => abort ------
problems="$(psql_ro -v report="$json" -t -A -F'|' <<'SQL'
WITH r AS (SELECT :'report'::jsonb AS j),
keys AS (
  SELECT unnest(ARRAY[
    'reportTitle','reportSubtitle','executiveSummary','meetingContext',
    'meetingObjectives','keySubjectAreas','discussionPointsAndDecisions',
    'actionItems','criticalIssuesAndBlockers','risksAndConcerns',
    'resourceRequirements','nextStepsAndFollowUp','futureConsiderations',
    'additionalNotes']) AS k
)
SELECT 'missing-key', k FROM keys, r WHERE NOT (r.j ? k)
UNION ALL SELECT 'actionItems-not-array', 'actionItems'
  FROM r WHERE jsonb_typeof((SELECT j FROM r)->'actionItems') <> 'array'
SQL
)"
if [[ -n "$problems" ]]; then
  echo "Validation failed (kind|key):" >&2
  printf '%s\n' "$problems" | sed 's/^/  /' >&2
  exit 1
fi

# --- Upsert (writable, transactional) --------------------------------------
end="COMMIT"; [[ -n "$dry" ]] && end="ROLLBACK"
psql_rw -v report="$json" -v mid="$mid" <<SQL
BEGIN;
\echo '==== BEFORE ===='
SELECT meeting_id,
       (report->>'reportTitle') AS title,
       jsonb_array_length(report->'actionItems') AS action_items,
       updated_at
FROM meeting_reports WHERE meeting_id = :'mid'::uuid;

INSERT INTO meeting_reports (meeting_id, report)
VALUES (:'mid'::uuid, :'report'::jsonb)
ON CONFLICT (meeting_id) DO UPDATE
  SET report = EXCLUDED.report, updated_at = now();

\echo '==== AFTER ===='
SELECT meeting_id,
       (report->>'reportTitle') AS title,
       jsonb_array_length(report->'actionItems') AS action_items,
       updated_at
FROM meeting_reports WHERE meeting_id = :'mid'::uuid;
$end;
SQL

[[ -n "$dry" ]] && echo "(dry-run: rolled back, nothing written)"
exit 0

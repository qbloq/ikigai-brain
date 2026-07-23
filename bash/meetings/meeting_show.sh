#!/usr/bin/env bash
# Full detail of one meeting: header, participants, and the structured report
# (executive summary, objectives, decisions, action items, blockers, next steps).
#
# Usage:  meeting_show.sh <id|prefix> [--json]
# --json prints the raw report jsonb. Id may be the UUID prefix (e.g. 1a2b3c4d).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

idarg="" ; while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) idarg="$1"; shift ;;
  esac
done
[[ -z "$idarg" ]] && { echo "Usage: meeting_show.sh <id|prefix>" >&2; exit 2; }
idarg="${idarg//\'/}"

mid="$(psql_ro -t -A -c "SELECT id FROM meetings WHERE id::text LIKE '${idarg}%' LIMIT 2;" | head -1)"
[[ -z "$mid" ]] && { echo "No meeting matches: $idarg" >&2; exit 1; }

if [[ "$FORMAT" == "json" ]]; then
  psql_ro -t -A -c "SELECT coalesce(report::text,'null') FROM meeting_reports WHERE meeting_id='$mid' LIMIT 1;"
  exit 0
fi

echo "== MEETING =="
psql_ro -x -c "
SELECT left(m.id::text,8) AS id, m.name, m.meeting_type AS type, m.status,
  to_char(m.scheduled_start_time,'YYYY-MM-DD HH24:MI') AS scheduled,
  to_char(m.actual_start_time,'YYYY-MM-DD HH24:MI') AS started,
  coalesce(pr.name,'—') AS project,
  EXISTS (SELECT 1 FROM meeting_transcripts x WHERE x.meeting_id=m.id) AS has_transcript,
  (SELECT count(*) FROM meeting_participants p WHERE p.meeting_id=m.id) AS participants,
  m.meet_url, m.recording_url
FROM meetings m LEFT JOIN projects pr ON pr.id=m.project_id
WHERE m.id='$mid';"

parts="$(psql_ro -t -A -c "SELECT count(*) FROM meeting_participants WHERE meeting_id='$mid';")"
if [[ "$parts" != "0" ]]; then
  echo "== PARTICIPANTS =="
  psql_ro -c "SELECT name, email, participant_role AS role, duration_minutes AS mins
    FROM meeting_participants WHERE meeting_id='$mid' ORDER BY duration_minutes DESC NULLS LAST;"
fi

has_report="$(psql_ro -t -A -c "SELECT 1 FROM meeting_reports WHERE meeting_id='$mid' LIMIT 1;")"
[[ -z "$has_report" ]] && { echo; echo "(no report for this meeting)"; exit 0; }

R="(SELECT report FROM meeting_reports WHERE meeting_id='$mid' LIMIT 1)"

echo "== REPORT =="
psql_ro -x -c "SELECT r.report->>'reportTitle' AS title,
  r.report->>'reportSubtitle' AS subtitle,
  r.report->>'executiveSummary' AS executive_summary
FROM meeting_reports r WHERE r.meeting_id='$mid';"

echo "-- Objectives --"
psql_ro -x -c "SELECT $R->'meetingObjectives'->>'stated' AS stated,
  $R->'meetingObjectives'->>'achieved' AS achieved,
  $R->'meetingObjectives'->>'unresolved' AS unresolved;"

echo "-- Decisions --"
psql_ro -c "SELECT d->>'topic' AS topic, d->>'decision' AS decision
  FROM jsonb_array_elements($R->'discussionPointsAndDecisions') d;"

echo "-- Action items --"
psql_ro -c "SELECT ai->>'priority' AS priority,
  (SELECT string_agg(x,', ') FROM jsonb_array_elements_text(ai->'assignedTo') x) AS assigned_to,
  ai->>'dueDate' AS due, ai->>'task' AS task
  FROM jsonb_array_elements($R->'actionItems') ai;"

echo "-- Blockers / critical issues --"
psql_ro -c "SELECT b->>'issue' AS issue, b->>'status' AS status FROM jsonb_array_elements($R->'criticalIssuesAndBlockers') b;"

echo "-- Next steps --"
psql_ro -x -c "SELECT $R->'nextStepsAndFollowUp'->>'nextMeeting' AS next_meeting,
  $R->'nextStepsAndFollowUp'->>'reviewPoints' AS review_points;"

#!/usr/bin/env bash
# Create a full task "work contract" (task + inputs + outputs + acceptance
# criteria) from a JSON spec. WRITE operation (psql_rw), single transaction,
# --dry-run rolls back. Pre-flight validates project/assignees/io_types first.
#
# Usage:  create_task.sh <contract.json | -> [--dry-run]
#
# Contract shape (see also the meeting-to-tasks skill):
# {
#   "title": "string",                         (required)
#   "project": "David Guerrero",               (required; name fragment or id prefix)
#   "priority": "High|Medium|Low",             (default Medium)
#   "due_date": "2026-06-30",                   (REQUIRED; always estimate, never null)
#   "status": "pending",                        (default pending)
#   "assignee": ["David Castaño", "a193bc8b"],  (optional; names resolve within the
#                                                Ikigai team, id-prefixes in ANY team
#                                                — use an id for externals/other teams,
#                                                e.g. David Guerrero "Cliente")
#   "source_meeting": "32a519c9",               (optional; adds a provenance comment)
#   "archetype": "A3.2",                         (optional; FK to activity_archetypes;
#                                                 tags the task to its SOP via the catalog)
#   "archetype_match_method": "human",           (optional; rule|embedding|llm|human, default human)
#   "archetype_confidence": "0.9",               (optional)
#   "slots": {"cantidad":"14","talento":"David"},(optional; fills {placeholders} when
#                                                 instantiating the archetype template)
#
# TEMPLATE INSTANTIATION: if "archetype" is set and BOTH "inputs" and "outputs"
# are omitted, the archetype's template contract (archetype_inputs/outputs/
# acceptance_criteria) is pulled and used, with {slot} placeholders substituted
# from "slots". Provide inputs/outputs explicitly to override the template.
#   "comments": [ {"text","author_name"} ],      (optional; e.g. coordination notes
#                                                 for external collaborators — what
#                                                 input is expected from whom)
#   "inputs":  [ {"title","description","io_type","is_required"} ],
#   "outputs": [ {"title","description","io_type","is_required",
#                 "criteria":[ {"criterion","criterion_category",
#                               "verification_method","is_required"} ]} ]
# }
# io_type must be a name from io_types (see io_types.sh). The output's default
# artifact_type is applied automatically; references are left unbound.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

src="${1:-}" dry=""
[[ -z "$src" || "$src" == "-h" || "$src" == "--help" ]] && { sed -n '2,30p' "$0"; exit 0; }
shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

tmp="$(mktemp "${TMPDIR:-/tmp}/contract.XXXXXX.json")"
trap 'rm -f "$tmp"' EXIT
if [[ "$src" == "-" ]]; then cat > "$tmp"; else cp "$src" "$tmp"; fi
json="$(cat "$tmp")"

# --- Template instantiation: archetype set + no explicit inputs/outputs -----
arch="$(node -e 'const j=require(process.argv[1]); process.stdout.write(j.archetype||"")' "$tmp" 2>/dev/null || true)"
needtpl="$(node -e 'const j=require(process.argv[1]); const noIn=!Array.isArray(j.inputs)||!j.inputs.length; const noOut=!Array.isArray(j.outputs)||!j.outputs.length; process.stdout.write((j.archetype&&noIn&&noOut)?"1":"")' "$tmp" 2>/dev/null || true)"
if [[ -n "$needtpl" ]]; then
  tpl="$(psql_ro -t -A -v arch="$arch" <<'SQL'
SELECT jsonb_build_object(
  'inputs', coalesce((SELECT jsonb_agg(jsonb_build_object(
              'title',i.title,'description',i.description,'io_type',it.name,'is_required',i.is_required) ORDER BY i.position)
            FROM ikigaigm.archetype_inputs i LEFT JOIN ikigaigm.io_types it ON it.id=i.io_type_id
            WHERE i.archetype_id = :'arch'), '[]'::jsonb),
  'outputs', coalesce((SELECT jsonb_agg(ob ORDER BY pos) FROM (
              SELECT o.position AS pos, jsonb_build_object(
                'title',o.title,'description',o.description,'io_type',oit.name,'is_required',o.is_required,
                'criteria', coalesce((SELECT jsonb_agg(jsonb_build_object(
                      'criterion',cr.criterion,'criterion_category',cr.criterion_category,
                      'verification_method',cr.verification_method,'is_required',cr.is_required) ORDER BY cr.position)
                    FROM ikigaigm.archetype_acceptance_criteria cr WHERE cr.output_id=o.id),'[]'::jsonb)
              ) AS ob
              FROM ikigaigm.archetype_outputs o LEFT JOIN ikigaigm.io_types oit ON oit.id=o.io_type_id
              WHERE o.archetype_id = :'arch') s), '[]'::jsonb)
)::text
SQL
)"
  TPL="$tpl" node -e '
    const fs=require("fs"); const tmp=process.argv[1];
    const c=JSON.parse(fs.readFileSync(tmp,"utf8"));
    const tpl=JSON.parse(process.env.TPL||"{}"); const slots=c.slots||{};
    const sub=s=> typeof s==="string" ? s.replace(/\{(\w+)\}/g,(m,k)=> (k in slots)?String(slots[k]):m) : s;
    const walk=o=> Array.isArray(o)?o.map(walk):(o&&typeof o==="object"?Object.fromEntries(Object.entries(o).map(([k,v])=>[k,walk(v)])):sub(o));
    c.inputs=walk(tpl.inputs||[]); c.outputs=walk(tpl.outputs||[]);
    fs.writeFileSync(tmp,JSON.stringify(c,null,2));
  ' "$tmp"
  json="$(cat "$tmp")"
  ins=$(node -e 'const j=require(process.argv[1]);console.log((j.inputs||[]).length+"/"+(j.outputs||[]).length)' "$tmp")
  echo "(instantiated archetype $arch template → inputs/outputs: $ins)" >&2
  [[ "$ins" == "0/0" ]] && echo "  warning: archetype $arch has no template contract; task will have no I/O." >&2
fi

# --- Pre-flight validation (read-only): unresolved refs => abort ------------
problems="$(psql_ro -v contract="$json" -t -A -F'|' <<'SQL'
WITH c AS (SELECT :'contract'::jsonb AS j),
proj AS (
  SELECT j->>'project' AS ref,
         (SELECT count(*) FROM ikigaigm.projects p
           WHERE p.name ILIKE '%'||(j->>'project')||'%' OR p.id::text LIKE (j->>'project')||'%') AS n
  FROM c
),
asg AS (
  SELECT a.name AS ref,
    (SELECT count(*) FROM ikigaigm.team_members tm
       LEFT JOIN ikigaigm.users u ON u.id=tm.user_id
       LEFT JOIN ikigaigm.persons p ON p.person_id=u.person_id
       LEFT JOIN ikigaigm.teams te ON te.id=tm.team_id
      WHERE (te.name='Ikigai' AND regexp_replace(trim(coalesce(p.name,'')||' '||coalesce(p.lastname,'')),'\s+',' ','g')=a.name)
         OR tm.id::text LIKE a.name||'%') AS n
  FROM c, jsonb_array_elements_text(coalesce((SELECT j FROM c)->'assignee','[]'::jsonb)) a(name)
),
iot AS (
  SELECT x.io AS ref, (SELECT count(*) FROM ikigaigm.io_types it WHERE it.name=x.io) AS n
  FROM (
    SELECT (e->>'io_type') AS io FROM c, jsonb_array_elements(coalesce((SELECT j FROM c)->'inputs','[]'::jsonb)) e
    UNION ALL
    SELECT (e->>'io_type')      FROM c, jsonb_array_elements(coalesce((SELECT j FROM c)->'outputs','[]'::jsonb)) e
  ) x
)
SELECT 'title'    , coalesce((SELECT j->>'title' FROM c),'(missing)'), 0 WHERE (SELECT j->>'title' FROM c) IS NULL
UNION ALL SELECT 'due_date', '(missing — estimate one)', 0 WHERE nullif((SELECT j->>'due_date' FROM c),'') IS NULL
UNION ALL SELECT 'project' , ref, n FROM proj WHERE n <> 1
UNION ALL SELECT 'assignee', ref, n FROM asg  WHERE n <> 1
UNION ALL SELECT 'io_type' , coalesce(ref,'(null)'), n FROM iot WHERE n <> 1
UNION ALL SELECT 'archetype', a.ref, a.n FROM (
  SELECT (SELECT j->>'archetype' FROM c) AS ref,
         (SELECT count(*) FROM ikigaigm.activity_archetypes aa
           WHERE aa.id = (SELECT j->>'archetype' FROM c)) AS n
) a WHERE nullif(a.ref,'') IS NOT NULL AND a.n <> 1
SQL
)"
if [[ -n "$problems" ]]; then
  echo "Validation failed — unresolved references (kind|ref|matches):" >&2
  printf '%s\n' "$problems" | sed 's/^/  /' >&2
  exit 1
fi

# --- Insert (writable, transactional) --------------------------------------
end="COMMIT"; [[ -n "$dry" ]] && end="ROLLBACK"
psql_rw -v contract="$json" <<SQL
BEGIN;
WITH c AS (SELECT :'contract'::jsonb AS j),
new_task AS (
  INSERT INTO ikigaigm.tasks (title, project_id, priority, due_date, status,
                              archetype_id, archetype_confidence, archetype_match_method, assignee)
  SELECT j->>'title',
         (SELECT id FROM ikigaigm.projects p
            WHERE p.name ILIKE '%'||(j->>'project')||'%' OR p.id::text LIKE (j->>'project')||'%' LIMIT 1),
         coalesce(nullif(j->>'priority',''),'Medium')::ikigaigm.task_priority,
         nullif(j->>'due_date','')::timestamptz,
         coalesce(nullif(j->>'status',''),'pending')::ikigaigm.task_status,
         nullif(j->>'archetype',''),
         nullif(j->>'archetype_confidence',''),
         CASE WHEN nullif(j->>'archetype','') IS NOT NULL
              THEN coalesce(nullif(j->>'archetype_match_method',''),'human') END,
         (SELECT array_agg(mid) FROM (
            SELECT (SELECT tm.id FROM ikigaigm.team_members tm
                      LEFT JOIN ikigaigm.users u ON u.id=tm.user_id
                      LEFT JOIN ikigaigm.persons p ON p.person_id=u.person_id
                      LEFT JOIN ikigaigm.teams te ON te.id=tm.team_id
                     WHERE (te.name='Ikigai' AND regexp_replace(trim(coalesce(p.name,'')||' '||coalesce(p.lastname,'')),'\s+',' ','g')=a.name)
                        OR tm.id::text LIKE a.name||'%'
                     LIMIT 1) AS mid
            FROM jsonb_array_elements_text(coalesce(j->'assignee','[]'::jsonb)) a(name)
         ) s WHERE s.mid IS NOT NULL)
  FROM c
  RETURNING id
),
ins_inputs AS (
  INSERT INTO ikigaigm.task_inputs (task_id, title, description, io_type_id, artifact_type_id, is_required, position)
  SELECT t.id, e.i->>'title', e.i->>'description', it.id, it.default_artifact_type_id,
         coalesce((e.i->>'is_required')::bool, true), e.ord-1
  FROM new_task t, c, jsonb_array_elements(coalesce(c.j->'inputs','[]'::jsonb)) WITH ORDINALITY e(i,ord)
  LEFT JOIN ikigaigm.io_types it ON it.name = e.i->>'io_type'
  RETURNING id
),
ins_outputs AS (
  INSERT INTO ikigaigm.task_outputs (task_id, title, description, io_type_id, artifact_type_id, is_required, position)
  SELECT t.id, e.o->>'title', e.o->>'description', it.id, it.default_artifact_type_id,
         coalesce((e.o->>'is_required')::bool, true), e.ord-1
  FROM new_task t, c, jsonb_array_elements(coalesce(c.j->'outputs','[]'::jsonb)) WITH ORDINALITY e(o,ord)
  LEFT JOIN ikigaigm.io_types it ON it.name = e.o->>'io_type'
  RETURNING id, position
),
ins_criteria AS (
  INSERT INTO ikigaigm.task_acceptance_criteria
    (output_id, criterion, criterion_category, verification_method, is_required, position)
  SELECT oi.id, cc.cr->>'criterion', cc.cr->>'criterion_category',
         coalesce(nullif(cc.cr->>'verification_method',''),'manual'),
         coalesce((cc.cr->>'is_required')::bool, true), cc.crord-1
  FROM c, jsonb_array_elements(coalesce(c.j->'outputs','[]'::jsonb)) WITH ORDINALITY e(o,ord)
  JOIN ins_outputs oi ON oi.position = e.ord-1
  CROSS JOIN LATERAL jsonb_array_elements(coalesce(e.o->'criteria','[]'::jsonb)) WITH ORDINALITY cc(cr,crord)
  RETURNING id
),
ins_comment AS (
  INSERT INTO ikigaigm.task_comments (task_id, author_name, text)
  SELECT t.id, 'meeting-to-tasks',
         'Created from meeting '||(c.j->>'source_meeting')||' by the meeting-to-tasks skill.'
  FROM new_task t, c
  WHERE nullif(c.j->>'source_meeting','') IS NOT NULL
  RETURNING id
),
ins_user_comments AS (
  INSERT INTO ikigaigm.task_comments (task_id, author_name, text)
  SELECT t.id,
         coalesce(nullif(e->>'author_name',''),'meeting-to-tasks'),
         e->>'text'
  FROM new_task t, c, jsonb_array_elements(coalesce(c.j->'comments','[]'::jsonb)) e
  WHERE nullif(e->>'text','') IS NOT NULL
  RETURNING id
)
SELECT (SELECT id FROM new_task)                 AS task_id,
       (SELECT count(*) FROM ins_inputs)         AS inputs,
       (SELECT count(*) FROM ins_outputs)        AS outputs,
       (SELECT count(*) FROM ins_criteria)       AS criteria,
       (SELECT count(*) FROM ins_comment)
        + (SELECT count(*) FROM ins_user_comments) AS comments;
$end;
SQL

[[ -n "$dry" ]] && echo "(dry-run: rolled back, nothing written)"

#!/usr/bin/env bash
# apply_contract.sh <task-id|prefix> <contract.json|-> [--dry-run] [--json]   **[WRITE]**
#
# Apply an IO "work contract" (inputs + outputs + acceptance criteria, and the
# archetype tag) onto an EXISTING task that has none. The twin of create_task.sh
# for tasks born without a contract — today: the ones that came in from the PM
# platform (source_type='other' + source_external_id), which create_task.sh never
# saw. One transaction, before/after, --dry-run rolls back.
#
# Contract shape — the SAME as create_task.sh minus the task header:
# {
#   "archetype": "A7.6",                       (optional; tags tasks.archetype_id; must exist)
#   "archetype_confidence": "0.8",             (optional; default 0.8 when archetype given)
#   "archetype_match_method": "human",         (optional; rule|embedding|llm|human, default human)
#   "slots": {"pagina":"survey","proyecto":"David Guerrero"},   (optional; fills {slot}s)
#   "inputs":  [ {"title","description","io_type","is_required"} ],
#   "outputs": [ {"title","description","io_type","is_required",
#                 "criteria":[ {"criterion","criterion_category","verification_method","is_required"} ]} ],
#   "comments": [ {"text","author_name"} ]     (optional; e.g. why this archetype / what's uncertain)
# }
#
# TEMPLATE INSTANTIATION (same rule as create_task.sh): if "archetype" is set and
# BOTH inputs and outputs are omitted, the archetype's template contract is pulled
# and its {slots} substituted from "slots". An unfilled {slot} stays LITERAL on
# purpose — it names what is missing (see docs/plantillas-slots-brief.md §6.2);
# «pendiente» (materialize_io.sh) loses that. {proyecto} defaults to the task's
# own project name when not passed.
#
# Guards:
#   - the task must resolve to exactly ONE row (prefix ok);
#   - the task must have NO inputs and NO outputs yet — this script only fills the
#     hole, it never rewrites; re-materialization stays with
#     bash/ops/materialize_io.sh --task X --replace (destructive, by design);
#   - every io_type name must exist; an archetype, if given, must be in the catalog.
# If the task already carries a DIFFERENT archetype, it is overwritten and the
# change is shown in before/after (the contract being applied is the authority).
#
# Output: before/after blocks; --json emits {task_id, archetype, inputs, outputs,
# criteria, comments, dry_run}.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

tref="${1:-}" src="${2:-}"
[[ -z "$tref" || "$tref" == "-h" || "$tref" == "--help" ]] && { sed -n '2,40p' "$0"; exit 0; }
[[ -z "$src" ]] && { echo "Missing <contract.json|->; see -h" >&2; exit 2; }
shift 2 || true
dry="" asjson=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry=1; shift ;;
    --json)    asjson=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

tmp="$(mktemp "${TMPDIR:-/tmp}/contract.XXXXXX.json")"
trap 'rm -f "$tmp"' EXIT
if [[ "$src" == "-" ]]; then cat > "$tmp"; else cp "$src" "$tmp"; fi
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$tmp" 2>/dev/null \
  || { echo "Contract is not valid JSON: $src" >&2; exit 2; }

# --- Resolve the task (exactly one) and read its state ----------------------
row="$(psql_ro -t -A -F $'\x1f' -v ref="$tref" <<'SQL'
SELECT t.id, coalesce(p.name,''), coalesce(t.archetype_id,''),
       (SELECT count(*) FROM task_inputs  i WHERE i.task_id=t.id),
       (SELECT count(*) FROM task_outputs o WHERE o.task_id=t.id),
       left(t.title,70)
FROM tasks t LEFT JOIN projects p ON p.id=t.project_id
WHERE t.id::text LIKE :'ref'||'%';
SQL
)"
n="$(printf '%s\n' "$row" | grep -c . || true)"
[[ "$n" -eq 1 ]] || { echo "Task ref '$tref' resolved to $n tasks (need 1)." >&2; exit 1; }
IFS=$'\x1f' read -r tid tproject tarch n_in n_out ttitle <<< "$row"
if [[ "$n_in" != "0" || "$n_out" != "0" ]]; then
  echo "Task ${tid:0:8} already has IO (inputs=$n_in outputs=$n_out). This script only fills an empty contract;" >&2
  echo "use bash/ops/materialize_io.sh --task ${tid:0:8} --replace to re-instantiate (destructive)." >&2
  exit 1
fi

# --- Template instantiation: archetype set + no explicit inputs/outputs -----
arch="$(node -e 'const j=require(process.argv[1]); process.stdout.write(j.archetype||"")' "$tmp")"
needtpl="$(node -e 'const j=require(process.argv[1]); const noIn=!Array.isArray(j.inputs)||!j.inputs.length; const noOut=!Array.isArray(j.outputs)||!j.outputs.length; process.stdout.write((j.archetype&&noIn&&noOut)?"1":"")' "$tmp")"
if [[ -n "$needtpl" ]]; then
  tpl="$(psql_ro -t -A -v arch="$arch" <<'SQL'
SELECT jsonb_build_object(
  'inputs', coalesce((SELECT jsonb_agg(jsonb_build_object(
              'title',i.title,'description',i.description,'io_type',it.name,'is_required',i.is_required) ORDER BY i.position)
            FROM archetype_inputs i LEFT JOIN io_types it ON it.id=i.io_type_id
            WHERE i.archetype_id = :'arch'), '[]'::jsonb),
  'outputs', coalesce((SELECT jsonb_agg(ob ORDER BY pos) FROM (
              SELECT o.position AS pos, jsonb_build_object(
                'title',o.title,'description',o.description,'io_type',oit.name,'is_required',o.is_required,
                'criteria', coalesce((SELECT jsonb_agg(jsonb_build_object(
                      'criterion',cr.criterion,'criterion_category',cr.criterion_category,
                      'verification_method',cr.verification_method,'is_required',cr.is_required) ORDER BY cr.position)
                    FROM archetype_acceptance_criteria cr WHERE cr.output_id=o.id),'[]'::jsonb)
              ) AS ob
              FROM archetype_outputs o LEFT JOIN io_types oit ON oit.id=o.io_type_id
              WHERE o.archetype_id = :'arch') s), '[]'::jsonb)
)::text
SQL
)"
  TPL="$tpl" TPROJECT="$tproject" node -e '
    const fs=require("fs"); const tmp=process.argv[1];
    const c=JSON.parse(fs.readFileSync(tmp,"utf8"));
    const tpl=JSON.parse(process.env.TPL||"{}"); const slots=Object.assign({}, c.slots||{});
    if(!("proyecto" in slots) && process.env.TPROJECT) slots.proyecto=process.env.TPROJECT;
    const sub=s=> typeof s==="string" ? s.replace(/\{(\w+)\}/g,(m,k)=> (k in slots)?String(slots[k]):m) : s;
    const walk=o=> Array.isArray(o)?o.map(walk):(o&&typeof o==="object"?Object.fromEntries(Object.entries(o).map(([k,v])=>[k,walk(v)])):sub(o));
    c.inputs=walk(tpl.inputs||[]); c.outputs=walk(tpl.outputs||[]); c.slots=slots;
    fs.writeFileSync(tmp,JSON.stringify(c,null,2));
  ' "$tmp"
  ins=$(node -e 'const j=require(process.argv[1]);console.log((j.inputs||[]).length+"/"+(j.outputs||[]).length)' "$tmp")
  echo "(instantiated archetype $arch template → inputs/outputs: $ins)" >&2
  if [[ "$ins" == "0/0" ]]; then
    echo "archetype $arch has no template contract — pass explicit inputs/outputs." >&2; exit 1
  fi
  left="$(node -e 'const j=require(process.argv[1]);const s=new Set();const w=o=>{if(Array.isArray(o))o.forEach(w);else if(o&&typeof o==="object")Object.values(o).forEach(w);else if(typeof o==="string")(o.match(/\{\w+\}/g)||[]).forEach(m=>s.add(m));};w(j.inputs);w(j.outputs);process.stdout.write([...s].join(" "))' "$tmp")"
  [[ -n "$left" ]] && echo "  warning: unfilled slots left literal: $left" >&2
fi
json="$(cat "$tmp")"

# --- Pre-flight validation (read-only) --------------------------------------
problems="$(psql_ro -v contract="$json" -t -A -F'|' <<'SQL'
WITH c AS (SELECT :'contract'::jsonb AS j),
iot AS (
  SELECT x.io AS ref, (SELECT count(*) FROM io_types it WHERE it.name=x.io) AS n
  FROM (
    SELECT (e->>'io_type') AS io FROM c, jsonb_array_elements(coalesce((SELECT j FROM c)->'inputs','[]'::jsonb)) e
    UNION ALL
    SELECT (e->>'io_type')      FROM c, jsonb_array_elements(coalesce((SELECT j FROM c)->'outputs','[]'::jsonb)) e
  ) x
),
vm AS (
  SELECT cr->>'verification_method' AS ref FROM c,
       jsonb_array_elements(coalesce((SELECT j FROM c)->'outputs','[]'::jsonb)) o,
       jsonb_array_elements(coalesce(o->'criteria','[]'::jsonb)) cr
  WHERE nullif(cr->>'verification_method','') IS NOT NULL
    AND cr->>'verification_method' NOT IN ('llm','manual','automated','test','attested')
)
SELECT 'io_type', coalesce(ref,'(null)'), n FROM iot WHERE n <> 1
UNION ALL SELECT 'verification_method', ref, 0 FROM vm
UNION ALL SELECT 'archetype', a.ref, a.n FROM (
  SELECT (SELECT j->>'archetype' FROM c) AS ref,
         (SELECT count(*) FROM activity_archetypes aa WHERE aa.id = (SELECT j->>'archetype' FROM c)) AS n
) a WHERE nullif(a.ref,'') IS NOT NULL AND a.n <> 1
UNION ALL SELECT 'outputs', '(contract has no outputs — a work contract needs at least one deliverable)', 0
  WHERE jsonb_array_length(coalesce((SELECT j FROM c)->'outputs','[]'::jsonb)) = 0
SQL
)"
if [[ -n "$problems" ]]; then
  echo "Validation failed — unresolved references (kind|ref|matches):" >&2
  printf '%s\n' "$problems" | sed 's/^/  /' >&2
  exit 1
fi

# --- Apply (writable, transactional) ----------------------------------------
end="COMMIT"; [[ -n "$dry" ]] && end="ROLLBACK"
out="$(psql_rw -t -A -F'|' -v contract="$json" -v tid="$tid" <<SQL
BEGIN;
WITH c AS (SELECT :'contract'::jsonb AS j),
upd AS (
  UPDATE tasks t SET
    archetype_id = coalesce(nullif(c.j->>'archetype',''), t.archetype_id),
    archetype_match_method = CASE WHEN nullif(c.j->>'archetype','') IS NOT NULL
                                  THEN coalesce(nullif(c.j->>'archetype_match_method',''),'human')
                                  ELSE t.archetype_match_method END,
    archetype_confidence = CASE WHEN nullif(c.j->>'archetype','') IS NOT NULL
                                THEN coalesce(nullif(c.j->>'archetype_confidence',''),'0.8')
                                ELSE t.archetype_confidence END
  FROM c WHERE t.id = :'tid'::uuid
  RETURNING t.id
),
ins_inputs AS (
  INSERT INTO task_inputs (task_id, title, description, io_type_id, artifact_type_id, is_required, position)
  SELECT :'tid'::uuid, e.i->>'title', e.i->>'description', it.id, it.default_artifact_type_id,
         coalesce((e.i->>'is_required')::bool, true), e.ord-1
  FROM c, jsonb_array_elements(coalesce(c.j->'inputs','[]'::jsonb)) WITH ORDINALITY e(i,ord)
  LEFT JOIN io_types it ON it.name = e.i->>'io_type'
  RETURNING id
),
ins_outputs AS (
  INSERT INTO task_outputs (task_id, title, description, io_type_id, artifact_type_id, is_required, position)
  SELECT :'tid'::uuid, e.o->>'title', e.o->>'description', it.id, it.default_artifact_type_id,
         coalesce((e.o->>'is_required')::bool, true), e.ord-1
  FROM c, jsonb_array_elements(coalesce(c.j->'outputs','[]'::jsonb)) WITH ORDINALITY e(o,ord)
  LEFT JOIN io_types it ON it.name = e.o->>'io_type'
  RETURNING id, position
),
ins_criteria AS (
  INSERT INTO task_acceptance_criteria
    (output_id, criterion, criterion_category, verification_method, is_required, position)
  SELECT oi.id, cc.cr->>'criterion', cc.cr->>'criterion_category',
         coalesce(nullif(cc.cr->>'verification_method',''),'manual'),
         coalesce((cc.cr->>'is_required')::bool, true), cc.crord-1
  FROM c, jsonb_array_elements(coalesce(c.j->'outputs','[]'::jsonb)) WITH ORDINALITY e(o,ord)
  JOIN ins_outputs oi ON oi.position = e.ord-1
  CROSS JOIN LATERAL jsonb_array_elements(coalesce(e.o->'criteria','[]'::jsonb)) WITH ORDINALITY cc(cr,crord)
  RETURNING id
),
ins_trail AS (
  INSERT INTO task_comments (task_id, author_name, text)
  SELECT :'tid'::uuid, 'apply_contract',
         'Contrato IO aplicado por apply_contract.sh'
         || CASE WHEN nullif(c.j->>'archetype','') IS NOT NULL THEN ' — arquetipo '||(c.j->>'archetype') ELSE '' END
         || CASE WHEN c.j ? 'slots' AND c.j->'slots' <> '{}'::jsonb
                 THEN ' · slots: '||(SELECT string_agg(k||'='||v, ', ') FROM jsonb_each_text(c.j->'slots') s(k,v)) ELSE '' END
         || '.'
  FROM c
  RETURNING id
),
ins_user_comments AS (
  INSERT INTO task_comments (task_id, author_name, text)
  SELECT :'tid'::uuid, coalesce(nullif(e->>'author_name',''),'apply_contract'), e->>'text'
  FROM c, jsonb_array_elements(coalesce(c.j->'comments','[]'::jsonb)) e
  WHERE nullif(e->>'text','') IS NOT NULL
  RETURNING id
)
SELECT (SELECT count(*) FROM ins_inputs), (SELECT count(*) FROM ins_outputs),
       (SELECT count(*) FROM ins_criteria),
       (SELECT count(*) FROM ins_trail) + (SELECT count(*) FROM ins_user_comments),
       -- a data-modifying CTE is not visible to the outer SELECT: derive the after-state
       (SELECT coalesce(nullif(c.j->>'archetype',''), (SELECT archetype_id FROM tasks WHERE id = :'tid'::uuid)) FROM c);
$end;
SQL
)"
res="$(printf '%s\n' "$out" | grep -E '^[0-9]+\|[0-9]+\|[0-9]+\|[0-9]+\|' | tail -1)"
IFS='|' read -r c_in c_out c_cr c_cm arch_after <<< "$res"

if [[ -n "$asjson" ]]; then
  printf '{"task_id":"%s","title":"%s","archetype_before":"%s","archetype":"%s","inputs":%s,"outputs":%s,"criteria":%s,"comments":%s,"dry_run":%s}\n' \
    "$tid" "${ttitle//\"/\\\"}" "$tarch" "$arch_after" "$c_in" "$c_out" "$c_cr" "$c_cm" "$([[ -n "$dry" ]] && echo true || echo false)"
else
  echo "==== ${tid:0:8} · $ttitle"
  echo "  before: inputs=0 outputs=0 archetype=${tarch:-—}"
  echo "  after : inputs=$c_in outputs=$c_out criteria=$c_cr comments=$c_cm archetype=${arch_after:-—}"
  [[ -n "$dry" ]] && echo "  (dry-run: rolled back, nothing written)"
fi
exit 0

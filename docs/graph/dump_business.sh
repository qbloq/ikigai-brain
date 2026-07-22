#!/usr/bin/env bash
# Dump the BUSINESS (conceptual) layer to TSV for build_business_graph.py — READ-ONLY.
# This is the org's own ontology, not the database's: the value chain and its
# macro-processes, the SOPs that decompose them, the activity archetypes that
# group under each SOP, the typed deliverables they declare, the roles that own
# them — and, crucially, the OBSERVED reality (which project consumes which
# process, which role actually executes it) so declared ownership can be
# contrasted with what the tasks really say.
#
# Usage: docs/graph/dump_business.sh [outdir]     (default: docs/graph/business)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../bash/lib/common.sh"
OUT="${1:-$HERE/business}"
mkdir -p "$OUT"
q() { psql_ro -t -A -F$'\t' -c "$1"; }

# 1) macro-processes = the value chain spine
q "SELECT code, name, coalesce(value_chain_order::text,''), coalesce(cadence,''),
     coalesce(array_to_string(owner_roles,'|'),''), coalesce(status,''), coalesce(note,'')
   FROM ikigaigm.macro_processes ORDER BY value_chain_order NULLS LAST, code;" > "$OUT/macros.tsv"

# 2) SOPs decompose a macro-process
q "SELECT code, macro_process_code, name,
     coalesce(array_to_string(owner_roles,'|'),''), coalesce(status,'')
   FROM ikigaigm.sops ORDER BY code;" > "$OUT/sops.tsv"

# 3) activity archetypes group under a SOP; task_count = real instantiation
q "SELECT a.id, a.sop_code, coalesce(a.verb,''), a.name, coalesce(a.default_role,''),
     a.is_gate, coalesce(a.cadence,''), coalesce(a.status,''),
     (SELECT count(*) FROM ikigaigm.tasks t WHERE t.archetype_id=a.id)
   FROM ikigaigm.activity_archetypes a ORDER BY a.id;" > "$OUT/archetypes.tsv"

# 4) the work contract each archetype declares, typed by io_type
q "SELECT i.archetype_id, 'input', it.name, i.is_required
   FROM ikigaigm.archetype_inputs i JOIN ikigaigm.io_types it ON it.id=i.io_type_id
   UNION ALL
   SELECT o.archetype_id, 'output', it.name, o.is_required
   FROM ikigaigm.archetype_outputs o JOIN ikigaigm.io_types it ON it.id=o.io_type_id
   ORDER BY 1,2,3;" > "$OUT/arch_io.tsv"

# 5) the semantic types of deliverables
q "SELECT name, coalesce(display_name,name), coalesce(category,'') FROM ikigaigm.io_types ORDER BY name;" > "$OUT/io_types.tsv"

# 6) roles, deduped BY NAME (role rows are duplicated per team, so role_id is
#    not the identity of a role — the name is)
q "SELECT tr.name, count(DISTINCT tm.id)
   FROM ikigaigm.team_roles tr LEFT JOIN ikigaigm.team_members tm ON tm.role_id=tr.id
   GROUP BY tr.name ORDER BY tr.name;" > "$OUT/roles.tsv"

# 7) clients/projects with their task load
q "SELECT p.name,
     (SELECT count(*) FROM ikigaigm.tasks t WHERE t.project_id=p.id),
     (SELECT count(*) FROM ikigaigm.tasks t WHERE t.project_id=p.id AND t.status NOT IN ('completed','cancelled'))
   FROM ikigaigm.projects p ORDER BY p.name;" > "$OUT/projects.tsv"

# 8) OBSERVED: which project actually consumes which archetype
q "SELECT p.name, t.archetype_id, count(*)
   FROM ikigaigm.tasks t JOIN ikigaigm.projects p ON p.id=t.project_id
   WHERE t.archetype_id IS NOT NULL
   GROUP BY 1,2 ORDER BY 1,2;" > "$OUT/project_archetype.tsv"

# 9) OBSERVED: which role actually executes which archetype (assignee[] → member → role)
q "SELECT tr.name, t.archetype_id, count(*)
   FROM ikigaigm.tasks t
   CROSS JOIN LATERAL unnest(t.assignee) AS aid
   JOIN ikigaigm.team_members tm ON tm.id=aid
   JOIN ikigaigm.team_roles  tr ON tr.id=tm.role_id
   WHERE t.archetype_id IS NOT NULL
   GROUP BY 1,2 ORDER BY 1,2;" > "$OUT/role_archetype.tsv"

# 10) coverage counters used to keep the graph honest about what is real
q "SELECT 'tasks_total', count(*) FROM ikigaigm.tasks
   UNION ALL SELECT 'tasks_con_archetype', count(*) FROM ikigaigm.tasks WHERE archetype_id IS NOT NULL
   UNION ALL SELECT 'tasks_con_proyecto', count(*) FROM ikigaigm.tasks WHERE project_id IS NOT NULL
   UNION ALL SELECT 'tasks_con_asignado', count(*) FROM ikigaigm.tasks WHERE assignee IS NOT NULL AND cardinality(assignee)>0
   UNION ALL SELECT 'tasks_de_reunion', count(*) FROM ikigaigm.tasks WHERE source_meeting_id IS NOT NULL
   UNION ALL SELECT 'team_members', count(*) FROM ikigaigm.team_members;" > "$OUT/coverage.tsv"

for f in macros sops archetypes arch_io io_types roles projects project_archetype role_archetype coverage; do
  printf '%-18s %4s filas\n' "$f" "$(wc -l < "$OUT/$f.tsv")"
done
echo "→ $OUT"

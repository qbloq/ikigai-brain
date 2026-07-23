#!/usr/bin/env bash
# List the process ontology: SOPs with their activity archetypes (one row per
# archetype), rolled up to the macro-process, plus how many tasks instantiate
# each archetype. Read-only; feeds the viz "sop-tree" UI.
#
# Usage:  sops.sh [--macro CODE] [--json]
#   --macro CODE   Only SOPs under this macro-process (e.g. S5).
#   --json         Machine-readable array (one object per archetype).
#
# Grain: one row per archetype. SOPs with no archetypes still appear (the
# archetype columns come back null) so the ontology is shown in full.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

MACRO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)  FORMAT=json ;;
    --macro) MACRO="${2:-}"; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "sops.sh: unknown arg '$1'" >&2; exit 2 ;;
  esac
  shift
done

where="true"
if [[ -n "$MACRO" ]]; then
  esc="${MACRO//\'/\'\'}"
  where="mp.code = '${esc}'"
fi

emit "
SELECT mp.code                                  AS macro,
       mp.name                                  AS macro_name,
       s.code                                   AS sop,
       s.name                                   AS sop_name,
       array_to_string(s.owner_roles, ', ')     AS roles,
       a.id                                     AS archetype,
       a.verb                                   AS verb,
       a.name                                   AS activity,
       coalesce(a.is_gate, false)               AS gate,
       count(t.id)                              AS tasks
FROM sops s
JOIN macro_processes mp ON mp.code = s.macro_process_code
LEFT JOIN activity_archetypes a ON a.sop_code = s.code
LEFT JOIN tasks t ON t.archetype_id = a.id
WHERE $where
GROUP BY mp.code, mp.name, mp.value_chain_order, s.code, s.name, s.owner_roles,
         a.id, a.verb, a.name, a.is_gate
ORDER BY mp.value_chain_order NULLS LAST, mp.code, s.code, a.id NULLS FIRST"

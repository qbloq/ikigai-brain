#!/usr/bin/env bash
# Reference catalog for the IO editor: every semantic io_type and every concrete
# artifact_type, with ids, so a UI can offer them as dropdown options and persist
# the chosen ids. Read-only. Emits ONE JSON object:
#   { "io_types":      [ {id, name, display_name, category, default_artifact_type_id} ],
#     "artifact_types":[ {id, name, display_name, category} ] }
#
# Usage:  io_catalog.sh [--json]   (always JSON; --json accepted for consistency)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
[[ "${1:-}" == "--json" ]] && shift || true

psql_ro -t -A -c "
SELECT json_build_object(
  'io_types', coalesce((SELECT json_agg(json_build_object(
       'id', it.id, 'name', it.name, 'display_name', it.display_name,
       'category', it.category, 'default_artifact_type_id', it.default_artifact_type_id)
       ORDER BY it.category, it.display_name)
     FROM io_types it), '[]'::json),
  'artifact_types', coalesce((SELECT json_agg(json_build_object(
       'id', at.id, 'name', at.name, 'display_name', at.display_name,
       'category', at.category)
       ORDER BY at.category, at.display_name)
     FROM artifact_types at), '[]'::json)
);"

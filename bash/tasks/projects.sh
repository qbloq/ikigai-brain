#!/usr/bin/env bash
# List projects (clients) with their open/total task counts.
#
# Usage:  projects.sh [--json]
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

[[ "${1:-}" == "--json" ]] && FORMAT=json

emit "SELECT left(pr.id::text,8) AS id, pr.name,
       count(t.id) AS total_tasks,
       count(t.id) FILTER (WHERE t.status NOT IN ('completed','cancelled')
                             AND coalesce(t.is_completed,false)=false) AS open_tasks
FROM ikigaigm.projects pr
LEFT JOIN ikigaigm.tasks t ON t.project_id=pr.id
GROUP BY pr.id, pr.name
ORDER BY pr.name"

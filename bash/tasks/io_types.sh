#!/usr/bin/env bash
# List the IO types (semantic types) available for task inputs/outputs, with
# their default artifact type and resolver. Use these names in task contracts.
#
# Usage:  io_types.sh [--json]
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
[[ "${1:-}" == "--json" ]] && FORMAT=json

emit "SELECT it.name, it.category, at.name AS default_artifact, at.resolver_type AS resolver
FROM ikigaigm.io_types it
LEFT JOIN ikigaigm.artifact_types at ON at.id = it.default_artifact_type_id
ORDER BY it.category, it.name"

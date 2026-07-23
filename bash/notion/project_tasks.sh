#!/usr/bin/env bash
# project_tasks.sh <project-page-id|url> [--format json|csv|md] [--out FILE]
# project_tasks.sh --all              [--format json|csv|md] [--out FILE]
#
# Read-only. Extract BD Avances tasks. With a project page, only rows whose
# "Proyectos brief" relation points to it (e.g. DG- Premium Mastermind). With
# --all, the ENTIRE data source (org-wide, all clients); each row carries
# `proyecto_ids` (the project page id(s)) so you can slice by client. Default JSON.
#
# Token: NOTION=ntn_... in .env (see lib/common.sh).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/common.sh"

fmt="json"; out=""; id=""; all=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --format) fmt="$2"; shift 2;;
    --json) fmt="json"; shift;;
    --all) all="1"; shift;;
    --out) out="$2"; shift 2;;
    -h|--help) sed -n '2,12p' "$0"; exit 0;;
    *) id="$1"; shift;;
  esac
done
[[ -z "$id" && -z "$all" ]] && { echo "usage: project_tasks.sh <page-id|url>|--all [--format json|csv|md] [--out FILE]" >&2; exit 1; }

export NOTION_TOKEN
[[ -n "$all" ]] && sel="--all" || sel="$id"
if [[ -n "$out" ]]; then
  python3 "$HERE/lib/project_tasks.py" $sel --format "$fmt" > "$out"
  echo "wrote $out ($(wc -l < "$out") lines)" >&2
else
  python3 "$HERE/lib/project_tasks.py" $sel --format "$fmt"
fi

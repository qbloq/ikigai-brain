#!/usr/bin/env bash
# sheet_show.sh <id|url> [--json]
#
# Metadata of one Google Sheet (title + tabs). El backend mkt aún no expone
# pestañas — este script muestra la metadata del archivo y lo dice claro.
# Use sheet_read.sh to pull the first tab's values (CSV).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/lib/common.sh"

ref=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) FORMAT=json; shift;;
    -h|--help) sed -n '2,6p' "$0"; exit 0;;
    *) ref="$1"; shift;;
  esac
done
[[ -z "$ref" ]] && { echo "usage: sheet_show.sh <id|url> [--json]" >&2; exit 1; }

"$HERE/drive_file.sh" "$ref" $([[ "$FORMAT" == json ]] && echo --json)
echo "sheet_show: el backend no expone las pestañas del Sheet (pídele a Meetico un" >&2
echo "/drive/sheets/:id/tabs si lo necesitas); sheet_read.sh trae la primera como CSV." >&2

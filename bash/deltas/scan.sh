#!/usr/bin/env bash
# Delta scanner (Fase 1 — docs/deltas-architecture.md): read one copilot FORK
# and produce the digest of candidate deltas for Gobernanza. Git IS the
# telemetry: the fork's total delta is `git diff upstream/main...HEAD`, and
# classification is PATH-BASED — structure is observed, conversational content
# never is.
#
#   viz/specs/**        → ui-spec     (the cheap, spec-pure lane)
#   catalog/**          → ontologia
#   **/migrations/**    → esquema     (the heavy lane — never applied from a fork)
#   copilot.json        → identidad
#   anything else       → codigo      (engineering-review lane)
#
# Usage: scan.sh <fork-path> [--base origin/main] [--json]
#   <fork-path>  path to the copilot's clone (its `origin` = the central repo)
#   --base REF   upstream ref to diff against (default origin/main)
#   --json       [{type,status,path,slug,name,layer,derived_from}] + summary
#
# Read-only: fetches the fork's origin and reads files; never writes anywhere.
set -euo pipefail

FORK="" BASE="origin/main" FORMAT=table
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) FORK="$1"; shift ;;
  esac
done
[[ -n "$FORK" && -d "$FORK/.git" ]] || { echo "Usage: scan.sh <fork-path> [--base REF] [--json] (fork inválido: '$FORK')" >&2; exit 2; }

git -C "$FORK" fetch -q origin 2>/dev/null || true

employee="$(python3 -c "import json;print(json.load(open('$FORK/copilot.json')).get('employee',''))" 2>/dev/null || true)"
role="$(python3 -c "import json;print(json.load(open('$FORK/copilot.json')).get('role',''))" 2>/dev/null || true)"
head_sha="$(git -C "$FORK" rev-parse --short HEAD)"
base_sha="$(git -C "$FORK" rev-parse --short "$BASE")"
ahead="$(git -C "$FORK" rev-list --count "$BASE..HEAD")"

classify() {
  case "$1" in
    viz/specs/*) echo ui-spec ;;
    catalog/*) echo ontologia ;;
    */migrations/*|migrations/*) echo esquema ;;
    copilot.json) echo identidad ;;
    *) echo codigo ;;
  esac
}

# --name-status over the merge-base (the fork's total delta vs upstream)
rows=()
while IFS=$'\t' read -r status p rest; do
  [[ -n "$p" ]] || continue
  [[ "$status" == R* && -n "${rest:-}" ]] && p="$rest" # renames: use the new path
  type="$(classify "$p")"
  slug="" name="" layer="" derived=""
  if [[ "$type" == "ui-spec" ]]; then
    slug="$(basename "$p" .json)"
    layer="$(dirname "${p#viz/specs/}")"
    if [[ -f "$FORK/$p" ]]; then
      name="$(python3 -c "import json;print(json.load(open('$FORK/$p')).get('name',''))" 2>/dev/null || true)"
      derived="$(python3 -c "import json;print(json.load(open('$FORK/$p')).get('derived_from') or '')" 2>/dev/null || true)"
    fi
  fi
  rows+=("$type|$status|$p|$slug|$name|$layer|$derived")
done < <(git -C "$FORK" diff --name-status "$BASE...HEAD")

if [[ "$FORMAT" == "json" ]]; then
  {
    echo "{\"fork\":\"$FORK\",\"employee\":\"$employee\",\"role\":\"$role\",\"base\":\"$base_sha\",\"head\":\"$head_sha\",\"commits_ahead\":$ahead,\"deltas\":["
    first=1
    for r in "${rows[@]:-}"; do
      [[ -n "$r" ]] || continue
      IFS='|' read -r t s p sl n l d <<<"$r"
      [[ $first -eq 1 ]] || printf ','
      first=0
      python3 -c "import json,sys;print(json.dumps({'type':'$t','status':'$s','path':'$p','slug':'$sl' or None,'name':'''$n''' or None,'layer':'$l' or None,'derived_from':'$d' or None}))"
    done
    echo "]}"
  } | python3 -c "import json,sys;print(json.dumps(json.loads(sys.stdin.read()),ensure_ascii=False,indent=2))"
else
  echo "Digest de deltas — fork: $FORK"
  echo "copiloto: ${employee:-?} (rol: ${role:-?}) · $ahead commit(s) sobre $BASE ($base_sha → $head_sha)"
  echo
  if [[ ${#rows[@]} -eq 0 ]]; then
    echo "Sin deltas: el fork está al día con $BASE."
  else
    {
      echo "TIPO|ST|PATH|SLUG|NOMBRE|LINAJE"
      for r in "${rows[@]}"; do
        IFS='|' read -r t s p sl n l d <<<"$r"
        echo "$t|$s|$p|${sl:--}|${n:--}|${d:--}"
      done
    } | column -t -s'|'
  fi
fi

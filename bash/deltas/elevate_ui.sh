#!/usr/bin/env bash
# WRITE (al árbol central, no a la DB): elevate one UI spec from a copilot
# fork's personal layer into the central genome (Fase 1 —
# docs/deltas-architecture.md): viz/specs/local/<slug>.json (fork) →
# viz/specs/org/ or viz/specs/roles/<rol>/ (central), stamped with
# promoted_from — the inverse provenance of derived_from: nothing is born OR
# elevated without origin. Validates the spec against the CENTRAL genome
# (validateSpec) before writing; commits with the structured delta message.
#
# Usage: elevate_ui.sh <fork-path> <slug> [--to org|roles/<rol>] [--dry-run] [--json]
#   <fork-path>   the copilot's clone (reads its viz/specs/local/<slug>.json)
#   <slug>        the spec's id in the fork's local layer
#   --to DEST     destination layer (default: roles/<rol del copilot.json>,
#                 or org if the fork has no copilot.json/role)
#   --dry-run     print the elevated spec and destination, write nothing
#   --json        {ok, slug, dest, promoted_from, commit}
#
# Spec-pura = revisión ligera: this script IS that lane. Código/esquema never
# pass through here — those go through the full engineering process.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FORK="" SLUG="" DEST="" DRY=0 FORMAT=table
while [[ $# -gt 0 ]]; do
  case "$1" in
    --to) DEST="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) if [[ -z "$FORK" ]]; then FORK="$1"; else SLUG="$1"; fi; shift ;;
  esac
done
[[ -n "$FORK" && -n "$SLUG" ]] || { echo "Usage: elevate_ui.sh <fork-path> <slug> [--to org|roles/<rol>] [--dry-run]" >&2; exit 2; }

SRC="$FORK/viz/specs/local/$SLUG.json"
[[ -f "$SRC" ]] || { echo "No existe $SRC — ¿el slug está en la capa local del fork?" >&2; exit 1; }

employee="$(python3 -c "import json;print(json.load(open('$FORK/copilot.json')).get('employee','desconocido'))" 2>/dev/null || echo desconocido)"
role="$(python3 -c "import json;print(json.load(open('$FORK/copilot.json')).get('role',''))" 2>/dev/null || true)"
[[ -n "$DEST" ]] || { [[ -n "$role" ]] && DEST="roles/$role" || DEST="org"; }
case "$DEST" in org|roles/*) ;; *) echo "--to inválido: '$DEST' (org | roles/<rol>)" >&2; exit 2 ;; esac

fork_sha="$(git -C "$FORK" rev-parse --short HEAD 2>/dev/null || echo '?')"
OUT="$ROOT/viz/specs/$DEST/$SLUG.json"
[[ -e "$OUT" ]] && { echo "Colisión: ya existe $OUT en el central — resolver a mano (¿merge o rename?)." >&2; exit 1; }

# Validate against the CENTRAL genome (the elevated spec must render here) and
# stamp provenance. scope follows the destination layer.
SPEC="$(node -e "
const spec = JSON.parse(require('fs').readFileSync('$SRC', 'utf8'));
const { validateSpec } = require('$ROOT/viz/lib/components');
const v = validateSpec(spec);
if (!v.ok) { console.error('validateSpec: ' + v.errors.join(' · ')); process.exit(1); }
for (const w of v.warnings) console.error('aviso: ' + w);
delete spec.archived_at;
spec.scope = '$DEST' === 'org' ? 'org' : 'role';
spec.promoted_from = '$employee/local/$SLUG@$fork_sha';
spec.updated_at = new Date().toISOString();
console.log(JSON.stringify(spec, null, 2));
")" || { echo "La spec no valida contra el genoma central — no se eleva." >&2; exit 1; }

if [[ "$DRY" -eq 1 ]]; then
  echo "[dry-run] elevaría $employee/local/$SLUG@$fork_sha → viz/specs/$DEST/$SLUG.json:"
  echo "$SPEC"
  exit 0
fi

mkdir -p "$(dirname "$OUT")"
printf '%s\n' "$SPEC" > "$OUT"
REL="viz/specs/$DEST/$SLUG.json"
git -C "$ROOT" add -- "$REL"
git -C "$ROOT" commit -q \
  -m "viz(ui): elevate $SLUG → $DEST (de $employee)" \
  -m "Delta-Type: ui-spec
Delta-Scope: ${DEST/roles\//role:}
Promoted-From: $employee/local/$SLUG@$fork_sha" \
  -- "$REL"
commit="$(git -C "$ROOT" rev-parse --short HEAD)"

if [[ "$FORMAT" == "json" ]]; then
  printf '{"ok":true,"slug":"%s","dest":"%s","promoted_from":"%s/local/%s@%s","commit":"%s"}\n' \
    "$SLUG" "$DEST" "$employee" "$SLUG" "$fork_sha" "$commit"
else
  echo "Elevada: $SLUG → viz/specs/$DEST/ (commit $commit)"
  echo "promoted_from: $employee/local/$SLUG@$fork_sha"
  echo "Distribución: los copilotos la reciben con git pull upstream."
fi

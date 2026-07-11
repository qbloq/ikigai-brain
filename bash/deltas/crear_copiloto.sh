#!/usr/bin/env bash
# WRITE (crea un repo fork + commitea decisiones en la forja): crear_copiloto.sh
# — el paso mecánico (Fase B) del skill crear-copiloto: da de alta el fork de
# UN copiloto de rol a partir del cerebro central (Fase 1 de
# docs/deltas-architecture.md, destilado del piloto Director Comercial).
#
# Qué hace, en un solo commit del fork:
#   1. git clone del cerebro → <forks-dir>/<empleado>  (origin = el central)
#   2. git config pull.rebase true            (los deltas siempre encima del genoma)
#   3. wipe de viz/specs/local/ heredada      (la capa personal es del repo, no
#      del linaje — decisión 5 de deltas-architecture)
#   4. copilot.json {employee, team_member_id, role}   (identidad sin auth)
#
# Y en el central: registra las decisiones de NACIMIENTO en
# forja/gobernanza/decisiones.jsonl (dismiss de identidad + wipe, razón
# "esperada por construcción" — el precedente del piloto), para que un alta
# no inunde la Cola de Gobernanza. `--no-decisions` lo omite.
#
# NO toca al piloto (data/forks/piloto) ni a ningún fork existente: el
# destino debe no existir. La capa de rol (viz/specs/roles/<rol>/) puede no
# existir aún — el copiloto nace con capa de rol vacía y esta crece por
# gobernanza (Fase A del skill).
#
# Usage: crear_copiloto.sh <employee-slug> --member <id-prefix|nombre> --role <rol-slug>
#                          [--forks-dir DIR] [--no-decisions] [--dry-run] [--json]
#   <employee-slug>  kebab-case ascii (p.ej. luis-david) → data/forks/<slug>
#   --member M       resuelto vía resolve_member (id-prefix si el nombre es ambiguo)
#   --role R         slug kebab-case del rol; debe coincidir con viz/specs/roles/<R>/
#   --dry-run        muestra el plan sin clonar ni escribir nada
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

EMP="" MEMBER="" ROLE="" FORKS_DIR="$REPO_ROOT/data/forks" DECIDE=1 DRY=0 FORMAT=table
while [[ $# -gt 0 ]]; do
  case "$1" in
    --member) MEMBER="$2"; shift 2 ;;
    --role) ROLE="$2"; shift 2 ;;
    --forks-dir) FORKS_DIR="$2"; shift 2 ;;
    --no-decisions) DECIDE=0; shift ;;
    --dry-run) DRY=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,31p' "$0"; exit 0 ;;
    -*) echo "Unknown arg: $1" >&2; exit 2 ;;
    *) EMP="$1"; shift ;;
  esac
done
[[ -n "$EMP" && -n "$MEMBER" && -n "$ROLE" ]] || {
  echo "Usage: crear_copiloto.sh <employee-slug> --member M --role R [--forks-dir DIR] [--no-decisions] [--dry-run] [--json]" >&2
  exit 2
}
[[ "$EMP" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo "employee-slug inválido: '$EMP' (kebab-case ascii)" >&2; exit 2; }
[[ "$ROLE" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo "rol inválido: '$ROLE' (kebab-case ascii)" >&2; exit 2; }

TARGET="$FORKS_DIR/$EMP"
[[ -e "$TARGET" ]] && { echo "El destino ya existe: $TARGET (los forks existentes no se tocan)" >&2; exit 1; }

member_id="$(resolve_member "$MEMBER")"
member_prefix="${member_id:0:8}"

# specs locales heredadas que el alta limpia (para el plan y las decisiones)
mapfile -t inherited < <(cd "$REPO_ROOT" && git ls-files 'viz/specs/local/*.json' | xargs -rn1 basename | sed 's/\.json$//')

if [[ $DRY -eq 1 ]]; then
  echo "── DRY-RUN: alta de copiloto ─────────────────────────────"
  echo "  empleado : $EMP"
  echo "  miembro  : $member_prefix ($MEMBER)"
  echo "  rol      : $ROLE $( [[ -d "$REPO_ROOT/viz/specs/roles/$ROLE" ]] && echo '(capa de rol existe)' || echo '(sin capa de rol aún — nace vacía)')"
  echo "  fork     : $TARGET  (clone de $REPO_ROOT, pull.rebase=true)"
  echo "  wipe     : ${#inherited[@]} spec(s) local heredada(s): ${inherited[*]:-—}"
  echo "  decisión : $( [[ $DECIDE -eq 1 ]] && echo "$((${#inherited[@]} + 1)) dismiss de nacimiento en decisiones.jsonl" || echo 'ninguna (--no-decisions)')"
  echo "Nada escrito (dry-run)."
  exit 0
fi

git clone -q "$REPO_ROOT" "$TARGET"
git -C "$TARGET" config pull.rebase true

# wipe de la capa personal heredada — se entrega vacía (el store recrea el
# directorio al primer write; no hace falta .gitkeep)
if [[ ${#inherited[@]} -gt 0 ]]; then
  git -C "$TARGET" rm -q 'viz/specs/local/*.json'
fi

python3 - "$TARGET/copilot.json" "$EMP" "$member_prefix" "$ROLE" <<'PY'
import json, sys
path, emp, member, role = sys.argv[1:5]
with open(path, "w") as f:
    json.dump({"employee": emp, "team_member_id": member, "role": role}, f, indent=2)
    f.write("\n")
PY

git -C "$TARGET" add copilot.json
git -C "$TARGET" commit -q -m "copilot: identidad de $EMP ($ROLE)

Alta por crear_copiloto.sh: copilot.json + capa local heredada limpia.

Delta-Type: identidad
Delta-Scope: personal"
head_sha="$(git -C "$TARGET" rev-parse --short HEAD)"

# ── decisiones de nacimiento (el precedente del piloto: identidad y wipe son
#    "esperadas por construcción" — no son deltas a gobernar) ────────────────
n_dec=0
if [[ $DECIDE -eq 1 ]]; then
  DECISIONS="$REPO_ROOT/forja/gobernanza/decisiones.jsonl"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  by="${FLEET_REVIEWER:-santiago}"
  {
    printf '{"ts": "%s", "delta": "ikigai/%s/copilot.json", "sha": "%s", "action": "dismissed", "to": null, "by": "%s", "reason": "alta de copiloto — identidad esperada por construcción (crear_copiloto.sh)", "commit": null}\n' "$ts" "$EMP" "$head_sha" "$by"
    for slug in "${inherited[@]}"; do
      printf '{"ts": "%s", "delta": "ikigai/%s/local/%s", "sha": "%s", "action": "dismissed", "to": null, "by": "%s", "reason": "alta de copiloto — limpieza de la capa local heredada (crear_copiloto.sh)", "commit": null}\n' "$ts" "$EMP" "$slug" "$head_sha" "$by"
    done
  } >> "$DECISIONS"
  n_dec=$((${#inherited[@]} + 1))
  git -C "$REPO_ROOT" add "$DECISIONS"
  git -C "$REPO_ROOT" commit -q -m "gobernanza: alta de copiloto $EMP ($ROLE) — $n_dec dismiss de nacimiento" -- "$DECISIONS"
fi

if [[ "$FORMAT" == "json" ]]; then
  python3 -c "import json;print(json.dumps({'employee':'$EMP','team_member_id':'$member_prefix','role':'$ROLE','fork':'${TARGET#$REPO_ROOT/}','head':'$head_sha','wiped':${#inherited[@]},'decisions':$n_dec}))"
else
  echo "Copiloto creado: $EMP ($ROLE) → ${TARGET#$REPO_ROOT/} @ $head_sha (${#inherited[@]} spec(s) heredadas limpiadas, $n_dec decisión(es) de nacimiento)"
fi

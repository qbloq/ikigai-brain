#!/usr/bin/env bash
# Tareas del cerebro relacionadas con UNA propuesta (o con cualquier título):
# cada fila trae `score` (señales SUMADAS: puede pasar de 100) y `motivo`
# declarado. Señales, sumadas:
#   citada (id en --ids)                      100
#   mismo arquetipo + mismo proyecto           40
#   mismo dueño (algún asignado coincide)      20
#   palabras del título (Jaccard, tokens ≥4 letras sin stopwords) ×40
# Abiertas antes que cerradas a igual score. READ-ONLY. Fuente viz
# `tareas_relacionadas` (el bloque «Relacionadas» del panel de la UI).
# Sin `--project` ni `--ids` el universo son las tareas ABIERTAS de todos los
# proyectos (con `--project` es todas las del proyecto, abiertas y cerradas).
#
# Usage: relacionadas.sh --titulo T [--project P] [--archetype A] [--assignee "N, M"] [--ids a,b] [--limit N] [--json]
#   --ids     prefijos (8) citados en la propuesta: entran con score 100 aunque sean de otro proyecto
#   --limit   default 12 (0 = todas con score > 0)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
TITULO=""; PROJECT=""; ARQ=""; ASSIGNEE=""; IDS=""; LIMIT=12
while [[ $# -gt 0 ]]; do
  case "$1" in
    --titulo) TITULO="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --archetype) ARQ="$2"; shift 2 ;;
    --assignee) ASSIGNEE="$2"; shift 2 ;;
    --ids) IDS="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$TITULO" ]] || { echo "Falta --titulo" >&2; exit 2; }
[[ "$LIMIT" =~ ^[0-9]+$ ]] || { echo "--limit numérico" >&2; exit 2; }
[[ -z "$IDS" || "$IDS" =~ ^[0-9a-f]{8}(,[0-9a-f]{8})*$ ]] || { echo "--ids: prefijos de 8 separados por coma" >&2; exit 2; }
esc() { printf '%s' "$1" | sed "s/'/''/g"; }
# Candidatas: todas las del proyecto (abiertas y cerradas) + las citadas.
# Sin --project ni --ids el universo son las tareas ABIERTAS de todos los proyectos.
w="$OPEN_PRED"
[[ -n "$PROJECT" ]] && w="pr.name ILIKE '%$(esc "$PROJECT")%'"
[[ -n "$IDS" ]] && w="$w OR t.id::text ~ '^($(echo "$IDS" | sed 's/,/|/g'))'"
candfile="$(mktemp)"
trap 'rm -f "$candfile"' EXIT
psql_ro -t -A -c "SELECT coalesce(json_agg(row_to_json(q)),'[]') FROM (
  SELECT t.id::text AS id_full, t.title, t.status::text AS status, t.priority::text AS priority,
         to_char(t.due_date,'YYYY-MM-DD') AS due, pr.name AS project, $ASSIGNEES_SQL AS assignees,
         t.archetype_id AS archetype
  FROM tasks t LEFT JOIN projects pr ON pr.id=t.project_id WHERE $w) q;" > "$candfile"
python3 - "$TITULO" "$ARQ" "$ASSIGNEE" "$IDS" "$LIMIT" "$FORMAT" "$candfile" <<'PY'
import sys, json, re, unicodedata
titulo, arq, assignee, ids, limit, fmt, candfile = sys.argv[1:8]
with open(candfile, encoding="utf-8") as f:
    cand = json.load(f)
STOP = set("para con como esta este esto ese esa del los las una unos unas por que del sobre desde hasta entre hacer tarea tareas nueva nuevo".split())
def norm(s):
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode().lower()
    return {w[:5] for w in re.findall(r"[a-z0-9]+", s) if len(w) >= 4 and w not in STOP}
def jacc(a, b): return len(a & b) / len(a | b) if a and b else 0.0
T = norm(titulo); cited = set(ids.split(",")) if ids else set()
owners = {o.strip().lower() for o in assignee.split(",") if o.strip()}
out = []
for c in cand:
    score, motivo = 0.0, []
    if c["id_full"][:8] in cited: score += 100; motivo.append("citada")
    if arq and c.get("archetype") == arq: score += 40; motivo.append(f"mismo arquetipo {arq} + proyecto")
    cown = {o.strip().lower() for o in (c.get("assignees") or "").split(",") if o.strip()}
    if owners and cown & owners: score += 20; motivo.append("mismo dueño")
    j = jacc(T, norm(c["title"]))
    if j >= 0.15: score += 40 * j; motivo.append(f"título {j:.2f}")
    if score > 0:
        out.append({**c, "id": c["id_full"][:8], "score": round(score), "motivo": " · ".join(motivo),
                    "_open": c["status"] not in ("completed", "cancelled")})
out.sort(key=lambda r: (-r["score"], not r["_open"], r["title"]))
for r in out: r.pop("_open")
if int(limit): out = out[: int(limit)]
if fmt == "json": print(json.dumps(out, ensure_ascii=False))
else:
    for r in out: print(f'{r["id"]}  {r["score"]:>3}  {r["status"]:<12} {r["title"][:60]:<60}  {r["motivo"]}')
PY

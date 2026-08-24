#!/usr/bin/env bash
# Tareas sin arquetipo (tasks.archetype_id IS NULL) con el ARQUETIPO PROPUESTO
# y sus alternativas — el primer peldaño del matcher del catálogo (rule →
# embedding → LLM). Dos señales sumadas y declaradas en `motivo`:
#   léxica   tokens del título (prefijo 5, sin stopwords) contra verbo (×2),
#            nombre del arquetipo y nombre de su SOP, del catálogo JSON
#   vecinos  las tareas YA etiquetadas cuyo título se parece (Jaccard ≥ 0.2):
#            su arquetipo vota, ponderado por la similitud
# score 0-100; bajo 25 no se propone nada (sugerido=null) antes que inventar.
# READ-ONLY. Fuente viz `tareas_sin_arquetipo`.
#
# `--id <prefijo8>` acota la salida a UNA tarea SIN tocar el voto de los
# vecinos: el universo de tareas ya etiquetadas sigue siendo el completo, así
# que el score de esa tarea sale idéntico al de la corrida sin filtro. Existe
# porque el panel de la UI de revisión re-corría el matcher sobre TODAS las
# tareas sin arquetipo en cada clic de fila (3.6 s medidos).
#
# Usage: sin_arquetipo.sh [--project P] [--open] [--id <prefijo8>] [--json]
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
PROJECT=""; OPEN=0; ID8=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --open) OPEN=1; shift ;;
    --id) ID8="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
esc() { printf '%s' "$1" | sed "s/'/''/g"; }
w="t.archetype_id IS NULL"
[[ -n "$PROJECT" ]] && w="$w AND pr.name ILIKE '%$(esc "$PROJECT")%'"
[[ "$OPEN" == 1 ]] && w="$w AND $OPEN_PRED"
# El prefijo se valida con forma estricta (8 hex) antes de tocar el SQL: es lo
# único de esta consulta que llega desde el navegador.
if [[ -n "$ID8" ]]; then
  [[ "$ID8" =~ ^[0-9a-f]{8}$ ]] || { echo "--id debe ser un prefijo de 8 hex: $ID8" >&2; exit 2; }
  w="$w AND t.id::text LIKE '$ID8%'"
fi
sinfile="$(mktemp)"; confile="$(mktemp)"
trap 'rm -f "$sinfile" "$confile"' EXIT
psql_ro -t -A -c "SELECT coalesce(json_agg(row_to_json(q)),'[]') FROM (
  SELECT t.id::text AS id_full, t.title, t.status::text AS status, t.priority::text AS priority,
         to_char(t.due_date,'YYYY-MM-DD') AS due, pr.name AS project, $ASSIGNEES_SQL AS assignees
  FROM tasks t LEFT JOIN projects pr ON pr.id=t.project_id WHERE $w
  ORDER BY t.due_date NULLS LAST) q;" > "$sinfile"
psql_ro -t -A -c "SELECT coalesce(json_agg(row_to_json(q)),'[]') FROM (
  SELECT t.title, t.archetype_id AS archetype FROM tasks t WHERE t.archetype_id IS NOT NULL) q;" > "$confile"
python3 - "$REPO_ROOT/catalog/sop-archetypes.json" "$FORMAT" "$sinfile" "$confile" <<'PY'
import sys, json, re, unicodedata
from collections import defaultdict
cat = json.load(open(sys.argv[1])); fmt = sys.argv[2]
with open(sys.argv[3], encoding="utf-8") as f: sin = json.load(f)
with open(sys.argv[4], encoding="utf-8") as f: con = json.load(f)
sops = {s["code"]: s["name"] for s in cat["sops"]}
STOP = set("para con como esta este esto ese esa del los las una unos unas por que sobre desde hasta entre hacer crear tarea tareas".split())
def norm(s):
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode().lower()
    return {w[:5] for w in re.findall(r"[a-z0-9]+", s) if len(w) >= 4 and w not in STOP}
def jacc(a, b): return len(a & b) / len(a | b) if a and b else 0.0
arcs = [{"id": a["id"], "nombre": a["name"], "sop": a["sop"], "sop_nombre": sops.get(a["sop"], ""),
         "verb": norm(a.get("verb", "")), "name": norm(a["name"]), "sopn": norm(sops.get(a["sop"], ""))} for a in cat["archetypes"]]
tagged = [(norm(c["title"]), c["archetype"]) for c in con]
out = []
for t in sin:
    T = norm(t["title"]); scores = defaultdict(float); why = defaultdict(list)
    for a in arcs:
        lex = 2 * len(T & a["verb"]) + len(T & a["name"]) + 0.5 * len(T & a["sopn"])
        if lex: scores[a["id"]] += min(60, lex * 15); why[a["id"]].append(f"léxica {lex:g}")
    votes = defaultdict(float)
    for nt, arc in tagged:
        j = jacc(T, nt)
        if j >= 0.2: votes[arc] += j
    for arc, v in votes.items():
        scores[arc] += min(60, v * 60); why[arc].append(f"vecinos {v:.2f}")
    alts = sorted(scores.items(), key=lambda kv: -kv[1])[:3]
    byid = {a["id"]: a for a in arcs}
    alts = [{"id": k, "nombre": byid[k]["nombre"], "sop": byid[k]["sop"], "score": round(min(100, v)), "motivo": " · ".join(why[k])} for k, v in alts if k in byid]
    top = alts[0] if alts and alts[0]["score"] >= 25 else None
    out.append({**t, "id": t["id_full"][:8], "sugerido": top and top["id"], "sugerido_nombre": top and top["nombre"],
                "sugerido_sop": top and top["sop"], "score": top["score"] if top else 0,
                "motivo": top["motivo"] if top else "sin propuesta (score < 25)", "alternativas": json.dumps(alts, ensure_ascii=False)})
if fmt == "json": print(json.dumps(out, ensure_ascii=False))
else:
    for r in out: print(f'{r["id"]}  {r["status"]:<11} {(r["sugerido"] or "—"):<6} {r["score"]:>3}  {r["title"][:58]:<58}  {r["motivo"]}')
PY

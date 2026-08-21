#!/usr/bin/env bash
# testeo_abrir.sh — WRITE (local): abrir UN testeo del embudo con sus métricas
# iniciales CONGELADAS. El registro que la alineación DG 2026-08-19 dejó como
# acuerdo: «registrar el evento de cada testeo con las métricas iniciales y
# actualizarlo con las finales, para tener el histórico».
#
# Las dos disciplinas de la reunión van en el diseño, no en la memoria:
#   - UN SOLO CAMBIO POR TESTEO: `--variable` es un campo singular obligatorio
#     («qué se cambió»). Si hacen falta dos frases, son dos testeos.
#   - UN TESTEO POR STEP: si ya hay uno en_curso para el mismo step+proyecto,
#     este script SE NIEGA (--forzar para la excepción consciente — p.ej. dos
#     videos distintos del mismo step con atribución separada).
#
# El snapshot inicial no se digita: se corre bash/metrics/embudo.sh en el
# momento de abrir y se congela (kpis + pauta + vsl + crm + ventas, con su
# procedencia). Si el embudo no responde, NO se abre el testeo — un testeo sin
# línea base es exactamente lo que la reunión vino a matar.
#
# Uso: testeo_abrir.sh --project N --step S --variable "…"
#        [--hipotesis "…"] [--metrica RUTA] [--nota "…"] [--forzar]
#        [--dry-run] [--json]
#   --step     titular | hook_vsl | survey | pagina | pauta | remarketing | otro
#   --metrica  ruta punteada dentro del snapshot cuyo delta se calculará al
#              cerrar: p.ej. kpis.roas_real · vsl.total.tasa_play · pauta.0.ctr
#              (si no resuelve, se guarda igual y el delta queda null)
#   --dry-run  muestra lo que se insertaría (con snapshot real) y no escribe
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 1
source bash/lib/sqlite.sh

DB=testeos
project="" step="" variable="" hipotesis="" metrica="" nota="" forzar=0 dry=0 json=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)   project="$2"; shift 2 ;;
    --step)      step="$2"; shift 2 ;;
    --variable)  variable="$2"; shift 2 ;;
    --hipotesis) hipotesis="$2"; shift 2 ;;
    --metrica)   metrica="$2"; shift 2 ;;
    --nota)      nota="$2"; shift 2 ;;
    --forzar)    forzar=1; shift ;;
    --dry-run)   dry=1; shift ;;
    --json)      json=1; shift ;;
    -h|--help)   sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$project" ]]  || { echo "Falta --project" >&2; exit 2; }
[[ -n "$variable" ]] || { echo "Falta --variable — QUÉ se cambia, en singular (la regla de un cambio por testeo)" >&2; exit 2; }
case "$step" in
  titular|hook_vsl|survey|pagina|pauta|remarketing|otro) ;;
  *) echo "--step debe ser: titular|hook_vsl|survey|pagina|pauta|remarketing|otro" >&2; exit 2 ;;
esac

p="$(db_path "$DB")"
mkdir -p "$(dirname "$p")"
esc() { printf '%s' "$1" | sed "s/'/''/g"; }

sqlite_rw "$p" "CREATE TABLE IF NOT EXISTS testeos (
  id TEXT PRIMARY KEY,
  proyecto TEXT NOT NULL,
  step TEXT NOT NULL CHECK (step IN ('titular','hook_vsl','survey','pagina','pauta','remarketing','otro')),
  variable TEXT NOT NULL,
  hipotesis TEXT,
  metrica TEXT,
  estado TEXT NOT NULL DEFAULT 'en_curso' CHECK (estado IN ('en_curso','cerrado','abortado')),
  abierto_en TEXT NOT NULL,
  cerrado_en TEXT,
  snapshot_inicial TEXT,
  snapshot_final TEXT,
  valor_inicial REAL,
  valor_final REAL,
  delta REAL,
  resultado TEXT CHECK (resultado IN ('gano','perdio','inconcluso')),
  decision TEXT,
  nota TEXT
);"

# --- guardarraíl: un testeo por step (por proyecto) ---
abierto="$(sqlite_ro "$p" "SELECT id||' · '||variable FROM testeos
  WHERE estado='en_curso' AND step='$(esc "$step")' AND proyecto='$(esc "$project")' LIMIT 1")"
if [[ -n "$abierto" && "$forzar" == 0 ]]; then
  { echo "Ya hay un testeo en curso en el step '$step' de $project: $abierto"
    echo "Un testeo por step (regla de la reunión del 19-ago): cerralo primero"
    echo "con testeo_cerrar.sh, o pasá --forzar si es una excepción consciente."; } >&2
  exit 1
fi

# --- snapshot inicial: el embudo AHORA, congelado con procedencia ---
if ! EMB="$(bash/metrics/embudo.sh --project "$project" 2>/dev/null)"; then
  echo "bash/metrics/embudo.sh falló para '$project' — sin línea base no se abre el testeo." >&2
  exit 1
fi

ROW="$(EMB="$EMB" METRICA="$metrica" python3 - <<'PY'
import json, os, secrets, sys
emb = json.loads(os.environ["EMB"])
snap = {k: emb.get(k) for k in ("meta", "kpis", "pauta", "vsl", "crm", "ventas")}
snap["_procedencia"] = "bash/metrics/embudo.sh al abrir el testeo"

def resolve(path, obj):
    if not path: return None
    cur = obj
    for part in path.split("."):
        if isinstance(cur, list):
            try: cur = cur[int(part)]
            except (ValueError, IndexError): return None
        elif isinstance(cur, dict):
            cur = cur.get(part)
        else: return None
    return cur if isinstance(cur, (int, float)) else None

metrica = os.environ["METRICA"]
val = resolve(metrica, snap)
if metrica and val is None:
    print(f"aviso: la métrica '{metrica}' no resuelve a un número en el snapshot — se guarda igual, delta quedará null", file=sys.stderr)
print(json.dumps({"id": secrets.token_hex(4), "snapshot": snap, "valor": val}, ensure_ascii=False))
PY
)"
ID="$(printf '%s' "$ROW" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")"
SNAP="$(printf '%s' "$ROW" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['snapshot'],ensure_ascii=False))")"
VAL="$(printf '%s' "$ROW" | python3 -c "import json,sys; v=json.load(sys.stdin)['valor']; print('NULL' if v is None else v)")"
AHORA="$(TZ=America/Bogota date '+%Y-%m-%d %H:%M')"

resumen() {
  echo "== TESTEO A ABRIR =="
  echo "  id:        $ID"
  echo "  proyecto:  $project"
  echo "  step:      $step"
  echo "  variable:  $variable"
  [[ -n "$hipotesis" ]] && echo "  hipótesis: $hipotesis"
  [[ -n "$metrica"   ]] && echo "  métrica:   $metrica = ${VAL/NULL/—}"
  echo "  abierto:   $AHORA (America/Bogota)"
  echo "  snapshot:  $(printf '%s' "$SNAP" | wc -c) bytes congelados del embudo"
}

if [[ "$dry" == 1 ]]; then
  resumen; echo "(dry-run: no se escribió nada)"; exit 0
fi

sqlite_rw "$p" "BEGIN;
INSERT INTO testeos (id, proyecto, step, variable, hipotesis, metrica, estado,
                     abierto_en, snapshot_inicial, valor_inicial, nota)
VALUES ('$ID', '$(esc "$project")', '$(esc "$step")', '$(esc "$variable")',
        $( [[ -n "$hipotesis" ]] && printf "'%s'" "$(esc "$hipotesis")" || echo NULL ),
        $( [[ -n "$metrica"   ]] && printf "'%s'" "$(esc "$metrica")"   || echo NULL ),
        'en_curso', '$AHORA', '$(esc "$SNAP")', $VAL,
        $( [[ -n "$nota" ]] && printf "'%s'" "$(esc "$nota")" || echo NULL ));
COMMIT;"

if [[ "$json" == 1 || "$FORMAT" == json ]]; then
  sqlite_ro "$p" -json "SELECT id, proyecto, step, variable, metrica, estado, abierto_en, valor_inicial FROM testeos WHERE id='$ID'" | sed 's/^\[//;s/\]$//'
  echo
else
  resumen
  echo "Abierto. Cerralo con: bash/testeos/testeo_cerrar.sh $ID --resultado gano|perdio|inconcluso"
fi

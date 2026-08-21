#!/usr/bin/env bash
# testeo_abrir.sh — WRITE: abrir UN testeo del embudo con sus métricas
# iniciales CONGELADAS, en Postgres (ikigaigm.testeos, migración 006). El
# acuerdo de la alineación DG 2026-08-19: «registrar el evento de cada testeo
# con las métricas iniciales y actualizarlo con las finales».
#
# Las dos disciplinas de la reunión van en el diseño, no en la memoria:
#   - UN SOLO CAMBIO POR TESTEO: `--variable` es singular y obligatoria.
#     Si hacen falta dos frases, son dos testeos.
#   - UN TESTEO POR STEP: si ya hay uno en_curso para el mismo step+proyecto,
#     este script SE NIEGA (--forzar para la excepción consciente).
#
# El snapshot inicial no se digita: se corre bash/metrics/embudo.sh al abrir y
# se congela (kpis + pauta + vsl + crm + ventas, con procedencia). Si el
# embudo no responde, NO se abre — un testeo sin línea base es lo que la
# reunión vino a matar. ⚠️ En un FORK de rol sin acceso a bash/vturb (la cerca
# por rol de bash/lib/acceso.sh; hoy solo cerebro y `ejecutivo` pasan) el bloque
# VSL viene con error declarado: una métrica vsl.* abriría con línea base nula,
# y el script lo avisa.
#
# `abierto_por` sale del copilot.json del fork ('cerebro' si no hay).
#
# Uso: testeo_abrir.sh --project N --step S --variable "…"
#        [--hipotesis "…"] [--metrica RUTA] [--nota "…"] [--forzar]
#        [--dry-run] [--json]
#   --step     titular | hook_vsl | survey | pagina | pauta | remarketing | otro
#   --metrica  ruta punteada dentro del snapshot: kpis.roas_real ·
#              vsl.total.tasa_play · pauta.0.ctr … (si no resuelve, se guarda
#              igual y el delta quedará null)
#   --dry-run  todo el flujo (snapshot real incluido) en una txn que se revierte
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 1
source bash/lib/common.sh

project="" step="" variable="" hipotesis="" metrica="" nota="" forzar=0 dry="" json=""
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
    -h|--help)   sed -n '2,31p' "$0"; exit 0 ;;
    *) echo "Argumento desconocido: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$project" ]]  || { echo "Falta --project" >&2; exit 2; }
[[ -n "$variable" ]] || { echo "Falta --variable — QUÉ se cambia, en singular (la regla de un cambio por testeo)" >&2; exit 2; }
case "$step" in
  titular|hook_vsl|survey|pagina|pauta|remarketing|otro) ;;
  *) echo "--step debe ser: titular|hook_vsl|survey|pagina|pauta|remarketing|otro" >&2; exit 2 ;;
esac

pid="$(resolve_project "$project")"
[[ -n "$pid" ]] || { echo "No project matched: $project" >&2; exit 1; }

quien="cerebro"
if [[ -f copilot.json ]]; then
  quien="$(python3 -c "import json; print(json.load(open('copilot.json')).get('employee','copiloto'))" 2>/dev/null || echo copiloto)"
fi

# --- guardarraíl: un testeo por step (por proyecto) ---
abierto="$(psql_ro -t -A -v pid="$pid" -v step="$step" <<'SQL'
SELECT left(id::text,8)||' · '||variable FROM testeos
WHERE estado='en_curso' AND project_id=:'pid'::uuid AND step=:'step' LIMIT 1;
SQL
)"
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

ROW="$(EMB="$EMB" METRICA="$metrica" QUIEN="$quien" python3 - <<'PY'
import json, os, sys
emb = json.loads(os.environ["EMB"])
snap = {k: emb.get(k) for k in ("meta", "kpis", "pauta", "vsl", "crm", "ventas")}
snap["_procedencia"] = f"bash/metrics/embudo.sh al abrir el testeo (desde: {os.environ['QUIEN']})"

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
    aviso = f"aviso: la métrica '{metrica}' no resuelve a un número en el snapshot — se abre igual, delta quedará null"
    if metrica.startswith("vsl.") and isinstance(snap.get("vsl"), dict) and snap["vsl"].get("error"):
        aviso += " (VSL vino con error: en un fork bash/vturb no corre — los testeos vsl.* se abren desde el cerebro)"
    print(aviso, file=sys.stderr)
print(json.dumps({"snapshot": snap, "valor": "" if val is None else val}, ensure_ascii=False))
PY
)"
SNAP="$(printf '%s' "$ROW" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['snapshot'],ensure_ascii=False))")"
VAL="$(printf '%s' "$ROW" | python3 -c "import json,sys; print(json.load(sys.stdin)['valor'])")"

end="COMMIT"; [[ -n "$dry" ]] && end="ROLLBACK"
SEL="SELECT left(id::text,8) AS id, :'projname' AS proyecto, step, variable,
       coalesce(metrica,'—') AS metrica, estado,
       to_char(abierto_en AT TIME ZONE 'America/Bogota','YYYY-MM-DD HH24:MI') AS abierto,
       valor_inicial, abierto_por"

if [[ -n "$json" ]]; then
  psql_rw -t -A -v pid="$pid" -v projname="$project" -v step="$step" -v variable="$variable" \
    -v hipotesis="$hipotesis" -v metrica="$metrica" -v nota="$nota" \
    -v snap="$SNAP" -v val="$VAL" -v quien="$quien" <<SQL
BEGIN;
WITH ins AS (
  INSERT INTO testeos (project_id, step, variable, hipotesis, metrica,
                       abierto_por, snapshot_inicial, valor_inicial, nota)
  VALUES (:'pid'::uuid, :'step', :'variable', NULLIF(:'hipotesis',''), NULLIF(:'metrica',''),
          :'quien', :'snap'::jsonb, NULLIF(:'val','')::numeric, NULLIF(:'nota',''))
  RETURNING *)
SELECT row_to_json(x) FROM (
  SELECT left(id::text,8) AS id, step, variable, metrica, estado, valor_inicial, abierto_por
  FROM ins) x;
$end;
SQL
  [[ -n "$dry" ]] && echo "(dry-run: rolled back, nothing written)" >&2
  exit 0
fi

psql_rw -v pid="$pid" -v projname="$project" -v step="$step" -v variable="$variable" \
  -v hipotesis="$hipotesis" -v metrica="$metrica" -v nota="$nota" \
  -v snap="$SNAP" -v val="$VAL" -v quien="$quien" <<SQL
BEGIN;
\echo '==== TESTEO A ABRIR ===='
WITH ins AS (
  INSERT INTO testeos (project_id, step, variable, hipotesis, metrica,
                       abierto_por, snapshot_inicial, valor_inicial, nota)
  VALUES (:'pid'::uuid, :'step', :'variable', NULLIF(:'hipotesis',''), NULLIF(:'metrica',''),
          :'quien', :'snap'::jsonb, NULLIF(:'val','')::numeric, NULLIF(:'nota',''))
  RETURNING *)
$SEL, pg_column_size(snapshot_inicial) AS snapshot_bytes FROM ins;
$end;
SQL

if [[ -n "$dry" ]]; then
  echo "(dry-run: rolled back, nothing written)"
else
  echo "Abierto. Cerralo con: bash/testeos/testeo_cerrar.sh <id> --resultado gano|perdio|inconcluso"
fi

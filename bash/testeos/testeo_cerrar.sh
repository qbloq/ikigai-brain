#!/usr/bin/env bash
# testeo_cerrar.sh — WRITE: cerrar UN testeo con sus métricas finales
# CONGELADAS y su desenlace, en Postgres (ikigaigm.testeos). La otra mitad del
# acuerdo del 19-ago: el testeo se actualiza con las finales y queda el
# histórico.
#
# Al cerrar se corre bash/metrics/embudo.sh otra vez, se congela el snapshot
# final y se calcula el delta de la métrica objetivo (si la hay). El resultado
# lo declara el humano (--resultado): el delta informa, no decide — una
# métrica puede moverse por razones ajenas al cambio, y esa lectura es de
# quien corrió el testeo. Un cierre no se reescribe.
#
# Uso: testeo_cerrar.sh <id|prefijo> --resultado gano|perdio|inconcluso
#        [--decision "…"] [--nota "…"] [--abortar] [--dry-run] [--json]
#   --abortar  cierra como 'abortado' (testeo contaminado o cancelado); no
#              pide --resultado y NO toma snapshot final — un snapshot de un
#              testeo abortado compararía peras con nada.
#   --dry-run  todo el flujo (snapshot real incluido) en una txn que se revierte
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 1
source bash/lib/common.sh

id="" resultado="" decision="" nota="" abortar=0 dry="" json=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --resultado) resultado="$2"; shift 2 ;;
    --decision)  decision="$2"; shift 2 ;;
    --nota)      nota="$2"; shift 2 ;;
    --abortar)   abortar=1; shift ;;
    --dry-run)   dry=1; shift ;;
    --json)      json=1; shift ;;
    -h|--help)   sed -n '2,19p' "$0"; exit 0 ;;
    -*) echo "Argumento desconocido: $1" >&2; exit 2 ;;
    *)  id="$1"; shift ;;
  esac
done

[[ -n "$id" ]] || { echo "Falta <id|prefijo> del testeo" >&2; exit 2; }
if [[ "$abortar" == 0 ]]; then
  case "$resultado" in
    gano|perdio|inconcluso) ;;
    *) echo "Falta --resultado gano|perdio|inconcluso (o --abortar)" >&2; exit 2 ;;
  esac
else
  resultado=""
fi

quien="cerebro"
if [[ -f copilot.json ]]; then
  quien="$(python3 -c "import json; print(json.load(open('copilot.json')).get('employee','copiloto'))" 2>/dev/null || echo copiloto)"
fi

# id por PREFIJO (ambiguo = error): este script se dicta desde la conversación.
esc() { printf '%s' "$1" | sed "s/'/''/g"; }
matches="$(psql_ro -t -A -c "SELECT id FROM testeos WHERE id::text LIKE '$(esc "$id")%'")"
n_matches="$(printf '%s' "$matches" | grep -c . || true)"
[[ "$n_matches" == 1 ]] || {
  if [[ "$n_matches" == 0 ]]; then echo "Ningún testeo con id '$id'" >&2
  else echo "Prefijo ambiguo '$id' ($n_matches testeos)" >&2; fi
  exit 1; }
ID="$matches"

row="$(psql_ro -t -A -v tid="$ID" <<'SQL'
SELECT estado||'|'||pr.name||'|'||coalesce(metrica,'')||'|'||coalesce(valor_inicial::text,'')
FROM testeos t JOIN projects pr ON pr.id=t.project_id WHERE t.id=:'tid'::uuid;
SQL
)"
IFS='|' read -r estado proyecto metrica val_ini <<<"$row"
[[ "$estado" == "en_curso" ]] || { echo "El testeo $(echo "$ID" | cut -c1-8) no está en curso (estado: $estado) — un cierre no se reescribe" >&2; exit 1; }

SNAP="" VAL="" DELTA="" estado_final="abortado"
if [[ "$abortar" == 0 ]]; then
  estado_final="cerrado"
  if ! EMB="$(bash/metrics/embudo.sh --project "$proyecto" 2>/dev/null)"; then
    echo "bash/metrics/embudo.sh falló para '$proyecto' — sin métricas finales no se cierra; reintentá, o --abortar si el testeo se perdió." >&2
    exit 1
  fi
  ROW="$(EMB="$EMB" METRICA="$metrica" VAL_INI="$val_ini" QUIEN="$quien" python3 - <<'PY'
import json, os
emb = json.loads(os.environ["EMB"])
snap = {k: emb.get(k) for k in ("meta", "kpis", "pauta", "vsl", "crm", "ventas")}
snap["_procedencia"] = f"bash/metrics/embudo.sh al cerrar el testeo (desde: {os.environ['QUIEN']})"

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

val = resolve(os.environ["METRICA"], snap)
ini = os.environ["VAL_INI"]
delta = round(val - float(ini), 4) if (val is not None and ini != "") else None
print(json.dumps({"snapshot": snap,
                  "valor": "" if val is None else val,
                  "delta": "" if delta is None else delta}, ensure_ascii=False))
PY
)"
  SNAP="$(printf '%s' "$ROW" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['snapshot'],ensure_ascii=False))")"
  VAL="$(printf '%s' "$ROW" | python3 -c "import json,sys; print(json.load(sys.stdin)['valor'])")"
  DELTA="$(printf '%s' "$ROW" | python3 -c "import json,sys; print(json.load(sys.stdin)['delta'])")"
fi

end="COMMIT"; [[ -n "$dry" ]] && end="ROLLBACK"
BODY="UPDATE testeos SET
  estado = :'efinal',
  cerrado_en = now(),
  cerrado_por = :'quien',
  snapshot_final = NULLIF(:'snap','')::jsonb,
  valor_final = NULLIF(:'val','')::numeric,
  delta = NULLIF(:'delta','')::numeric,
  resultado = NULLIF(:'resultado',''),
  decision = coalesce(NULLIF(:'decision',''), decision),
  nota = coalesce(NULLIF(:'nota',''), nota)
WHERE id = :'tid'::uuid
RETURNING *"

if [[ -n "$json" ]]; then
  psql_rw -t -A -v tid="$ID" -v efinal="$estado_final" -v quien="$quien" -v snap="$SNAP" \
    -v val="$VAL" -v delta="$DELTA" -v resultado="$resultado" -v decision="$decision" -v nota="$nota" <<SQL
BEGIN;
WITH upd AS ($BODY)
SELECT row_to_json(x) FROM (
  SELECT left(id::text,8) AS id, step, variable, metrica, estado,
         valor_inicial, valor_final, delta, resultado, decision, cerrado_por
  FROM upd) x;
$end;
SQL
  [[ -n "$dry" ]] && echo "(dry-run: rolled back, nothing written)" >&2
  exit 0
fi

psql_rw -v tid="$ID" -v efinal="$estado_final" -v quien="$quien" -v snap="$SNAP" \
  -v val="$VAL" -v delta="$DELTA" -v resultado="$resultado" -v decision="$decision" -v nota="$nota" <<SQL
BEGIN;
\echo '==== ANTES ===='
SELECT left(id::text,8) AS id, step, variable, estado, valor_inicial FROM testeos WHERE id = :'tid'::uuid;
\echo '==== CIERRE ===='
WITH upd AS ($BODY)
SELECT left(id::text,8) AS id, estado, coalesce(resultado,'—') AS resultado,
       valor_inicial, valor_final, delta,
       to_char(cerrado_en AT TIME ZONE 'America/Bogota','YYYY-MM-DD HH24:MI') AS cerrado,
       cerrado_por
FROM upd;
$end;
SQL
[[ -n "$dry" ]] && echo "(dry-run: rolled back, nothing written)"
exit 0

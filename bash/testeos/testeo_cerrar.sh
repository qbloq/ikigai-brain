#!/usr/bin/env bash
# testeo_cerrar.sh — WRITE (local): cerrar UN testeo con sus métricas finales
# CONGELADAS y su desenlace. La otra mitad del acuerdo del 19-ago: el testeo
# se actualiza con las métricas finales y queda el histórico.
#
# Al cerrar se corre bash/metrics/embudo.sh otra vez, se congela el snapshot
# final y se calcula el delta de la métrica objetivo (si la hay). El resultado
# lo declara el humano (--resultado): el delta informa, no decide — una
# métrica puede subir por razones ajenas al cambio, y esa lectura es de quien
# corrió el testeo.
#
# Uso: testeo_cerrar.sh <id|prefijo> --resultado gano|perdio|inconcluso
#        [--decision "…"] [--nota "…"] [--abortar] [--dry-run] [--json]
#   --abortar  cierra como 'abortado' (el testeo se contaminó o se canceló);
#              no pide --resultado y NO toma snapshot final — un snapshot de
#              un testeo abortado compararía peras con nada.
#   --dry-run  muestra el cierre (con snapshot real) y no escribe
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 1
source bash/lib/sqlite.sh

DB=testeos
id="" resultado="" decision="" nota="" abortar=0 dry=0 json=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --resultado) resultado="$2"; shift 2 ;;
    --decision)  decision="$2"; shift 2 ;;
    --nota)      nota="$2"; shift 2 ;;
    --abortar)   abortar=1; shift ;;
    --dry-run)   dry=1; shift ;;
    --json)      json=1; shift ;;
    -h|--help)   sed -n '2,18p' "$0"; exit 0 ;;
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
fi

p="$(require_db "$DB")"
esc() { printf '%s' "$1" | sed "s/'/''/g"; }

# id por PREFIJO (ambiguo = error), como update_task_criteria.sh: este script
# se dicta desde la conversación.
matches="$(sqlite_ro "$p" "SELECT id FROM testeos WHERE id LIKE '$(esc "$id")%'")"
n_matches="$(printf '%s' "$matches" | grep -c . || true)"
[[ "$n_matches" == 1 ]] || {
  if [[ "$n_matches" == 0 ]]; then echo "Ningún testeo con id '$id'" >&2
  else echo "Prefijo ambiguo '$id': $(printf '%s' "$matches" | paste -sd' ' -)" >&2; fi
  exit 1; }
ID="$matches"

row="$(sqlite_ro "$p" "SELECT estado||'|'||proyecto||'|'||coalesce(metrica,'')||'|'||coalesce(valor_inicial,'')||'|'||step||'|'||variable FROM testeos WHERE id='$ID'")"
IFS='|' read -r estado proyecto metrica val_ini step variable <<<"$row"
[[ "$estado" == "en_curso" ]] || { echo "El testeo $ID no está en curso (estado: $estado) — un cierre no se reescribe" >&2; exit 1; }

AHORA="$(TZ=America/Bogota date '+%Y-%m-%d %H:%M')"
SNAP="NULL_SQL" VAL="NULL" DELTA="NULL"

if [[ "$abortar" == 0 ]]; then
  if ! EMB="$(bash/metrics/embudo.sh --project "$proyecto" 2>/dev/null)"; then
    echo "bash/metrics/embudo.sh falló para '$proyecto' — sin métricas finales no se cierra; reintentá, o --abortar si el testeo se perdió." >&2
    exit 1
  fi
  ROW="$(EMB="$EMB" METRICA="$metrica" VAL_INI="$val_ini" python3 - <<'PY'
import json, os
emb = json.loads(os.environ["EMB"])
snap = {k: emb.get(k) for k in ("meta", "kpis", "pauta", "vsl", "crm", "ventas")}
snap["_procedencia"] = "bash/metrics/embudo.sh al cerrar el testeo"

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
delta = round(val - float(ini), 4) if (val is not None and ini not in ("", "NULL")) else None
print(json.dumps({"snapshot": snap, "valor": val, "delta": delta}, ensure_ascii=False))
PY
)"
  SNAP="'$(esc "$(printf '%s' "$ROW" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['snapshot'],ensure_ascii=False))")")'"
  VAL="$(printf '%s' "$ROW" | python3 -c "import json,sys; v=json.load(sys.stdin)['valor']; print('NULL' if v is None else v)")"
  DELTA="$(printf '%s' "$ROW" | python3 -c "import json,sys; v=json.load(sys.stdin)['delta']; print('NULL' if v is None else v)")"
  estado_final="cerrado"
else
  SNAP="NULL"
  estado_final="abortado"
  resultado=""
fi
[[ "$SNAP" == "NULL_SQL" ]] && SNAP="NULL"

resumen() {
  echo "== CIERRE DE TESTEO =="
  echo "  id:        $ID ($step · $proyecto)"
  echo "  variable:  $variable"
  echo "  estado:    en_curso → $estado_final"
  [[ -n "$resultado" ]] && echo "  resultado: $resultado"
  [[ -n "$metrica"   ]] && echo "  métrica:   $metrica: ${val_ini:-—} → ${VAL/NULL/—} (Δ ${DELTA/NULL/—})"
  [[ -n "$decision"  ]] && echo "  decisión:  $decision"
  echo "  cerrado:   $AHORA (America/Bogota)"
}

if [[ "$dry" == 1 ]]; then
  resumen; echo "(dry-run: no se escribió nada)"; exit 0
fi

sqlite_rw "$p" "BEGIN;
UPDATE testeos SET
  estado='$estado_final',
  cerrado_en='$AHORA',
  snapshot_final=$SNAP,
  valor_final=$VAL,
  delta=$DELTA,
  resultado=$( [[ -n "$resultado" ]] && printf "'%s'" "$resultado" || echo NULL ),
  decision=$( [[ -n "$decision" ]] && printf "'%s'" "$(esc "$decision")" || echo "decision" ),
  nota=$( [[ -n "$nota" ]] && printf "'%s'" "$(esc "$nota")" || echo "nota" )
WHERE id='$ID';
COMMIT;"

if [[ "$json" == 1 || "$FORMAT" == json ]]; then
  sqlite_ro "$p" -json "SELECT id, proyecto, step, variable, metrica, estado, abierto_en, cerrado_en, valor_inicial, valor_final, delta, resultado, decision FROM testeos WHERE id='$ID'" | sed 's/^\[//;s/\]$//'
  echo
else
  resumen
fi

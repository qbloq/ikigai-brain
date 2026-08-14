#!/usr/bin/env bash
# [WRITE pg + local] El RUNNER del pipeline de reportes: toma la cola de
# `reportes_pendientes.sh` y, por cada llamada, corre el skill
# `generar-reporte-llamada` en una sesión headless de Claude Code.
#
# POR QUÉ UN RUNNER Y NO UN CRON DIRECTO: el paso de generación no es SQL ni
# curl — son N subagentes de contexto limpio puntuando el transcript por
# separado (el diseño que la cohorte 3 justificó: la mediana de 3 baja el mínimo
# distinguible de ±11 a ±4.5). Eso lo produce una Claude, no un script. El cron
# dispara ESTE script; este script invoca `claude -p` una vez por llamada; el
# skill hace el resto y persiste con `reporte_guardar.sh` (call_reports +
# meeting_reports). El script no genera ni un puntaje: solo agenda y audita.
#
# IDEMPOTENCIA EN DOS CAPAS:
#   1. La cola ya excluye lo que tiene reporte en `call_reports`.
#   2. `reportes_intentos` (sqlite closers_ops) cuenta intentos por llamada:
#      una llamada que falla dos veces se para y queda visible como `fallido` —
#      sin esto, un transcript roto se reintenta para siempre en cada tick.
#
# COSTO: ~3 subagentes por llamada. Corre con la suscripción del Cerebro (uso
# interno), no con API key de cliente. --limit es el tope por corrida y existe
# para eso: una primera pasada histórica son 115 llamadas.
#
# Usage: generar_pendientes.sh [--limit N] [--desde N] [--min-chars N]
#                              [--model M] [--timeout S] [--dry-run] [--json]
#   --limit N     llamadas por corrida (default 3)
#   --desde N     ventana del detector en días (default 7; 0 = toda la historia)
#   --model M     modelo de las tiradas (default claude-fable-5, el de los 63
#                 reportes ya en producción — mantener el modelo estable importa:
#                 el umbral de baja confianza está calibrado con su ruido)
#   --timeout S   tope por llamada (default 900s)
set -euo pipefail
cd "$(dirname "$0")/../.."
REPO="$PWD"
source bash/lib/common.sh
source bash/lib/sqlite.sh

LIMIT=3; DESDE=7; MIN=2000; MODEL="claude-fable-5"; TIMEOUT=900; DRY=0; FORMAT=text
MAX_INTENTOS=2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) LIMIT="$2"; shift 2 ;;
    --desde) DESDE="$2"; shift 2 ;;
    --min-chars) MIN="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

DB="$(require_db closers_ops)"
sqlite_rw "$DB" "CREATE TABLE IF NOT EXISTS reportes_intentos (
  meeting_id TEXT PRIMARY KEY, lead TEXT, closer TEXT,
  intentos INTEGER NOT NULL DEFAULT 0, estado TEXT NOT NULL DEFAULT 'pendiente',
  error TEXT, ultimo_at TEXT);" >/dev/null

COLA="$(bash bash/calls/reportes_pendientes.sh --desde "$DESDE" --min-chars "$MIN" \
        --con-closer --limit 0 --json)"

SEL="$(COLA="$COLA" LIMIT="$LIMIT" MAXI="$MAX_INTENTOS" DB="$DB" python3 - <<'PY'
import json, os, sqlite3
cola = json.loads(os.environ["COLA"] or "[]")
con = sqlite3.connect(os.environ["DB"])
gastadas = {r[0] for r in con.execute(
    "SELECT meeting_id FROM reportes_intentos WHERE intentos >= ?",
    (int(os.environ["MAXI"]),))}
sel = [c for c in cola if c["uuid"] not in gastadas][: int(os.environ["LIMIT"])]
print(json.dumps({"total": len(cola), "gastadas": len(gastadas), "sel": sel}, ensure_ascii=False))
PY
)"
TOTAL="$(python3 -c "import json,sys;print(json.loads(sys.argv[1])['total'])" "$SEL")"
GASTADAS="$(python3 -c "import json,sys;print(json.loads(sys.argv[1])['gastadas'])" "$SEL")"
N="$(python3 -c "import json,sys;print(len(json.loads(sys.argv[1])['sel']))" "$SEL")"

echo "cola: $TOTAL pendientes · $GASTADAS agotadas (>=$MAX_INTENTOS intentos) · esta corrida: $N" >&2
[[ "$N" == "0" ]] && { [[ "$FORMAT" == json ]] && echo "[]"; exit 0; }

RES="[]"
for i in $(seq 0 $((N - 1))); do
  fila="$(python3 -c "import json,sys;print(json.dumps(json.loads(sys.argv[1])['sel'][int(sys.argv[2])],ensure_ascii=False))" "$SEL" "$i")"
  uuid="$(python3 -c "import json,sys;print(json.loads(sys.argv[1])['uuid'])" "$fila")"
  lead="$(python3 -c "import json,sys;print(json.loads(sys.argv[1])['lead'])" "$fila")"
  closer="$(python3 -c "import json,sys;print(json.loads(sys.argv[1])['closer'] or '')" "$fila")"

  if [[ "$DRY" == "1" ]]; then
    echo "DRY-RUN: /generar-reporte-llamada ${uuid:0:8}  ($lead · $closer)" >&2
    continue
  fi

  sqlite_rw "$DB" "INSERT INTO reportes_intentos (meeting_id, lead, closer, intentos, estado, ultimo_at)
    VALUES ($(sql_str "$uuid"), $(sql_str "$lead"), $(sql_str "$closer"), 1, 'corriendo', datetime('now'))
    ON CONFLICT(meeting_id) DO UPDATE SET intentos=intentos+1, estado='corriendo',
      lead=excluded.lead, closer=excluded.closer, ultimo_at=datetime('now');" >/dev/null

  echo "→ ${uuid:0:8} $lead ($closer)" >&2
  salida="$(mktemp)"
  set +e
  timeout "$TIMEOUT" claude -p "/generar-reporte-llamada $uuid" \
    --model "$MODEL" \
    --permission-mode acceptEdits \
    --allowedTools Bash Read Write Task Glob Grep \
    > "$salida" 2>&1
  rc=$?
  set -e

  # La verdad no es el exit code del CLI: es si la fila quedó en Postgres.
  quedo="$(psql_ro -t -A -c "SELECT count(*) FROM ikigaigm.call_reports WHERE meeting_id='$uuid'")"
  if [[ "$quedo" -gt 0 ]]; then
    estado=ok; err=""
  else
    estado=fallido
    err="rc=$rc · $(tail -c 400 "$salida" | tr '\n' ' ' | tr -d "'")"
  fi
  sqlite_rw "$DB" "UPDATE reportes_intentos SET estado=$(sql_str "$estado"),
    error=$(sql_str "$err"), ultimo_at=datetime('now') WHERE meeting_id=$(sql_str "$uuid");" >/dev/null
  echo "   $estado" >&2
  rm -f "$salida"

  RES="$(python3 -c "
import json,sys
r=json.loads(sys.argv[1]); r.append({'meeting_id':sys.argv[2],'lead':sys.argv[3],'closer':sys.argv[4],'estado':sys.argv[5]})
print(json.dumps(r,ensure_ascii=False))" "$RES" "$uuid" "$lead" "$closer" "$estado")"
done

if [[ "$FORMAT" == json ]]; then printf '%s\n' "$RES"; fi

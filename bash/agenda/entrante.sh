#!/usr/bin/env bash
# entrante.sh — [WRITE local + →Marketico + pg] procesa UN agendamiento de GHL
# (el payload crudo del workflow, por stdin) según el ROL de su calendario:
#
#   venta      → POST /crm/process-booking de Marketico (Meet + evento +
#                fila meetings, el processBooking de siempre a demanda) y
#                sella meetings.ghl_calendar_id con el calendario de origen.
#   entrada    → solo se registra (confirmación de 20 min: SIN Meet — ese era
#                exactamente el bug que motivó el modo ack del webhook).
#   sin rol    → 'desconocido': NO se procesa (un calendario no oficial no
#                genera Meet; ya ni siquiera entra — supera la política del
#                caso Alexander 2026-08-17).
#   sin appointment_id → 'ignorada' (payloads de workflow que no son booking).
#
# TODO desenlace queda en la sqlite intercepciones.db tabla `entrantes` —
# también los errores: este script sale 0 si logró registrar; el exit ≠ 0 es
# solo para "ni registrar pude". Idempotencia: la da processBooking (verifica
# la cita existente y actualiza en vez de duplicar); reintento aquí = 2 para
# el POST a Marketico.
#
# uso: entrante.sh [--dry-run] [--json] < payload.json
#   --json: aceptado por homogeneidad con el resto de bash/ — la salida es
#           siempre una línea JSON, con o sin la flag.
# Spec: docs/superpowers/specs/2026-08-26-marketico-port-ux-llamadas-design.md
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck disable=SC1091
source bash/lib/common.sh   # .env (DATABASE_URL, MEETICO_*), psql_ro/psql_rw

DRY=0; JSON=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --json) JSON=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -20; exit 0 ;;
    *) echo "flag desconocido: $1" >&2; exit 2 ;;
  esac
done

T0=$(date +%s%3N)
RAW="$(cat)"
[[ -z "$RAW" ]] && { echo "sin payload en stdin" >&2; exit 2; }

# Extraer los campos (typo appoinmentStatus: es del API de GHL, se respeta).
eval "$(printf '%s' "$RAW" | python3 -c '
import json, sys, shlex
try: b = json.load(sys.stdin)
except Exception: print("PARSE_OK=0"); raise SystemExit
c = b.get("calendar") or {}
print("PARSE_OK=1")
for k, v in [("APPT", c.get("appointmentId")), ("CAL", c.get("id")),
             ("ESTADO", c.get("appoinmentStatus")), ("NOMBRE", b.get("full_name")),
             ("EMAIL", b.get("email")), ("INICIO", c.get("startTime"))]:
    print(f"{k}={shlex.quote(str(v) if v is not None else chr(0x2205))}")')"
SIN="∅"

registrar() { # accion resultado error
  local dur=$(( $(date +%s%3N) - T0 ))
  local db="${INTERCEPCIONES_DB:-data/sqlite/intercepciones.db}"
  mkdir -p "$(dirname "$db")"
  # Apply el DDL idempotente. Redirigido a /dev/null a propósito: `PRAGMA
  # journal_mode=WAL;` en schema.sql IMPRIME "wal" a stdout, que rompería el
  # contrato de una sola línea JSON de salida.
  sqlite3 "$db" < bash/intercepciones/schema.sql >/dev/null

  # RAW (el payload completo) y resultado (puede ser la respuesta cruda de
  # Marketico) NUNCA van por variable de entorno ni argv: un payload grande
  # (~1 MB+) revienta exec() con E2BIG y la fila no se llega a escribir.
  # Van por archivo temporal, leídos desde python; se borran al terminar.
  local raw_f res_f
  raw_f="$(mktemp)"; res_f="$(mktemp)"
  printf '%s' "$RAW" > "$raw_f"
  printf '%s' "${2:-}" > "$res_f"

  ACCION="$1" ERR="${3:-}" DUR="$dur" DB="$db" \
  APPT="${APPT:-}" CAL="${CAL:-}" ROL="${ROL:-}" ESTADO="${ESTADO:-}" NOMBRE="${NOMBRE:-}" \
  EMAIL="${EMAIL:-}" INICIO="${INICIO:-}" SIN="$SIN" RAW_F="$raw_f" RES_F="$res_f" python3 - <<'PYEOF'
import os, sqlite3
e = os.environ; n = lambda k: (None if e.get(k, "") in ("", e["SIN"]) else e[k])
with open(e["RAW_F"], "r", encoding="utf-8") as f:
    raw = f.read()
with open(e["RES_F"], "r", encoding="utf-8") as f:
    res = f.read()
con = sqlite3.connect(e["DB"], timeout=5)
con.execute("INSERT INTO entrantes (appointment_id, calendar_id, rol, estado_cita, contacto, email, start_time, accion, resultado, error, duracion_ms, payload) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
  (n("APPT"), n("CAL"), n("ROL"), n("ESTADO"), n("NOMBRE"), n("EMAIL"), n("INICIO"),
   e["ACCION"], (res or None), n("ERR"), int(e["DUR"]), raw))
con.commit()
PYEOF
  rm -f "$raw_f" "$res_f"
}

salida() { # accion detalle
  local accion="$1" detalle="${2:-}"
  # APPT/ROL pasados explícitos por entorno (no basta con que existan como
  # variables de shell: python3 -, al ser un proceso nuevo, solo hereda lo
  # exportado).
  APPT="${APPT:-}" ROL="${ROL:-}" SIN="$SIN" python3 - "$accion" "$detalle" <<'PYEOF'
import json, sys, os
e = os.environ
appt = e.get("APPT") or ""
rol = e.get("ROL") or ""
print(json.dumps({"accion": sys.argv[1],
  "appointment_id": (appt if appt and appt != e.get("SIN") else None),
  "rol": (rol or None), "detalle": sys.argv[2] or None}, ensure_ascii=False))
PYEOF
}

[[ "$PARSE_OK" == "0" ]] && { registrar error "" "payload no es JSON"; salida error "payload no es JSON"; exit 0; }

if [[ "$APPT" == "$SIN" ]]; then
  (( DRY )) && { salida ignorada "dry-run"; exit 0; }
  registrar ignorada "" ""; salida ignorada "sin appointment_id"; exit 0
fi

# El rol del calendario (migración 008). Sin Postgres no hay decisión → error.
ROL="$(psql_ro -t -A -c "SELECT coalesce(rol,'') FROM crm_calendars WHERE ghl_calendar_id='${CAL//\'/\'\'}'" 2>/dev/null || echo '__pgdown__')"
if [[ "$ROL" == "__pgdown__" ]]; then
  (( DRY )) && { salida error "postgres no responde (dry-run)"; exit 0; }
  # exit 0: el encabezado manda — "sale 0 si logró registrar", y la fila
  # accion='error' SÍ se logró escribir en sqlite. exit ≠ 0 queda reservado
  # para "ni registrar pude" (sqlite inaccesible, stdin vacío).
  registrar error "" "postgres no responde — no se pudo resolver el rol"; salida error "postgres no responde"; exit 0
fi

case "$ROL" in
  venta)
    if (( DRY )); then salida meet_solicitado "dry-run: POST $MEETICO_BASE/crm/process-booking"; exit 0; fi
    RESP=""; CODE=""
    for intento in 1 2; do
      # Token por header vía config en stdin — jamás en argv.
      OUTF="$(mktemp)"
      CODE="$(printf 'url = "%s"\nheader = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\n' \
          "$MEETICO_BASE/crm/process-booking" "$MEETICO_JWT_TOKEN" \
        | curl -sS --config - -X POST --data-binary "$RAW" -o "$OUTF" -w '%{http_code}' --max-time 120)" || CODE="000"
      RESP="$(cat "$OUTF")"; rm -f "$OUTF"
      [[ "$CODE" == 2* ]] && break
    done
    if [[ "$CODE" == 2* ]]; then
      registrar meet_solicitado "$RESP" ""
      # Sellar el calendario de origen en la reunión creada (spec §1.1).
      MID="$(printf '%s' "$RESP" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("meeting_id") or "")
except Exception: print("")')"
      if [[ -n "$MID" ]]; then
        psql_rw -c "UPDATE meetings SET ghl_calendar_id='${CAL//\'/\'\'}' WHERE id='${MID//\'/\'\'}' AND ghl_calendar_id IS NULL" >/dev/null 2>&1 || true
      else
        # No es un error del camino (la fila accion=meet_solicitado ya quedó
        # con el body completo en `resultado`) pero sí una constancia que el
        # log de pm2 debe mostrar: sin meeting_id no hay a qué sellarle el
        # calendario de origen.
        echo "2xx sin meeting_id — sin sellar" >&2
      fi
      salida meet_solicitado ""
    else
      registrar error "$RESP" "Marketico HTTP $CODE"
      salida error "Marketico HTTP $CODE"
    fi ;;
  entrada)
    (( DRY )) && { salida registrada "dry-run"; exit 0; }
    registrar registrada "" ""; salida registrada "confirmación — sin Meet" ;;
  *)
    (( DRY )) && { salida desconocido "dry-run"; exit 0; }
    registrar desconocido "" ""; salida desconocido "calendario sin rol: $CAL" ;;
esac

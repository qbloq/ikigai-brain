#!/usr/bin/env bash
# reparar_hueco_ack.sh — [WRITE→Marketico via entrante.sh] reparación puntual
# del hueco del modo ack (26-ago→01-sep-2026): mientras `/webhooks/crm` solo
# confirmaba recepción (Task 4/2026-08-26-flujo-agendamiento), las citas del
# calendario de VENTA («Aplicación a Premium Mastermind»,
# rmiAFkJKOZ2QZ1yEr8dn) no generaron Meet ni fila `meetings` — el bug exacto
# que el flujo nuevo corrige hacia adelante. Este script CIERRA el hueco hacia
# atrás: por cada appointment-id de GHL pasado por argv, reconstruye el
# payload de booking con la MISMA forma que GHL manda al webhook (verificado
# contra el `booking.sample.json` real de Marketico y el uso de campos en
# `crmService.js::processBooking`) y lo pasa por stdin a
# `bash/agenda/entrante.sh` — el mismo camino que un booking en vivo.
#
# ⚠️ Crear el Meet manda una invitación de Calendar a un lead real (y a
# `booking.user`, el closer asignado). Por eso el default es SIEMPRE
# --dry-run: solo muestra qué payload mandaría, con el email visible, y NO
# toca Marketico. Se necesita --ejecutar explícito para llamar de verdad, y
# aun con --ejecutar se procesa una cita a la vez (nunca en batch silencioso),
# mostrando el resultado de cada llamada antes de seguir con la siguiente.
#
# Los datos del payload se leen EN VIVO de GHL (no de un snapshot): por cada
# appointment-id se sondea /calendars/events/appointments/{id} (la cita),
# /contacts/{contactId} (el lead) y, si hay closer asignado,
# /users/{assignedUserId} (para booking.user — el invitado al Calendar). Una
# cita ya no 'confirmed' en GHL (cancelada, reagendada, etc.) se OMITE
# siempre — no hay reparación que valga para una cita que el lead ya canceló.
#
# uso: reparar_hueco_ack.sh [--project FRAG] [--ejecutar] [--json] <appointment-id>...
#   --project FRAG   fragmento del nombre del proyecto GHL (default: "David Guerrero")
#   --ejecutar       llama de verdad a entrante.sh, una cita a la vez (si se omite: dry-run)
#   --json           salida = array JSON (uno por cita) en vez de texto
#
# Spec: docs/superpowers/plans/2026-08-26-flujo-agendamiento.md (Task 8a,
# hallazgo operativo de la Task 7: 21 citas de venta sin meeting a la fecha
# de este script — 2026-09-01).
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SELF_DIR/../.."
# shellcheck disable=SC1091
source bash/lib/common.sh
# shellcheck disable=SC1091
source bash/ghl/lib/common.sh

PROJECT="David Guerrero"; EJECUTAR=0; JSON=0
usage() { sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --ejecutar) EJECUTAR=1; shift ;;
    --json) JSON=1; shift ;;
    -h|--help) usage ;;
    -*) echo "flag desconocido: $1" >&2; usage 1 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
[[ ${#ARGS[@]} -eq 0 ]] && { echo "falta al menos un appointment-id" >&2; usage 1; }

read -r PID PNAME < <(ghl_resolve_project "$PROJECT")
ghl_load_creds "$PID"
export GHL_LOCATION GHL_TOKEN

# GHL responde 401 "Command timed out" de forma intermitente y transitoria
# (no es el token — plan 2026-08-26-flujo-agendamiento.md §convenciones).
# Reintenta 3 veces antes de darse por vencido.
ghl_api_retry() {
  local path="$1" tries=0 out err
  err="$(mktemp)"
  while (( tries < 3 )); do
    if out="$(ghl_api "$path" 2>"$err")"; then
      rm -f "$err"; printf '%s' "$out"; return 0
    fi
    tries=$(( tries + 1 ))
    grep -q "Command timed out" "$err" || break
  done
  cat "$err" >&2; rm -f "$err"; return 1
}

# El comparador/constructor: recibe appointment + contact + user (o vacío) por
# archivos temporales (nunca argv — pueden traer texto libre del lead) y
# arma en un solo objeto {ok, motivo, futura, estado, closer_email, closer_nombre,
# lead_nombre, lead_email, payload} — payload con la MISMA forma que
# booking.sample.json de Marketico.
PY_ARMAR='
import json, sys
from datetime import datetime, timezone, timedelta

appt_f, contact_f, user_f, appt_id = sys.argv[1:5]

with open(appt_f) as f:
    ad = json.load(f)
a = ad.get("appointment") or {}
if not a.get("id"):
    print(json.dumps({"ok": False, "appointment_id": appt_id,
                       "motivo": "GHL no devolvió la cita (id inexistente o token sin acceso)"}))
    raise SystemExit

with open(contact_f) as f:
    cd = json.load(f)
c = cd.get("contact") or {}

user = {}
try:
    with open(user_f) as f:
        ud = json.load(f)
    if ud.get("id"):
        user = {"firstName": ud.get("firstName") or "", "lastName": ud.get("lastName") or "",
                "email": ud.get("email") or ""}
except Exception:
    pass

estado = a.get("appointmentStatus") or a.get("appoinmentStatus") or ""
fd = (a.get("appointmentMeta") or {}).get("defaultFormDetails") or {}
first = c.get("firstName") or fd.get("firstName") or ""
last = c.get("lastName") or fd.get("lastName") or ""
full = (first + " " + last).strip() or a.get("title") or ""
email = c.get("email") or fd.get("email") or ""
phone = c.get("phone") or fd.get("phone") or ""

start = a.get("startTime")
BOG = timezone(timedelta(hours=-5))
futura = None
if start:
    try:
        futura = datetime.fromisoformat(start.replace("Z", "+00:00")) > datetime.now(timezone.utc)
    except Exception:
        futura = None

payload = {
    "contact_id": a.get("contactId"),
    "first_name": first, "last_name": last, "full_name": full,
    "email": email, "phone": phone,
    "timezone": c.get("timezone") or "America/Bogota",
    "location": {"id": a.get("locationId")},
    "user": user,
    "calendar": {
        "title": a.get("title"),
        "appointmentId": a.get("id"),
        "startTime": a.get("startTime"),
        "endTime": a.get("endTime"),
        "appoinmentStatus": estado,
        "address": a.get("address") or "",
        "id": a.get("calendarId"),
    },
}

ok = estado == "confirmed"
motivo = None if ok else f"estado GHL actual = {estado!r} (no es confirmed) — se omite, no se repara"
print(json.dumps({
    "ok": ok, "appointment_id": a.get("id"), "motivo": motivo,
    "futura": futura, "estado": estado,
    "closer_nombre": (user.get("firstName", "") + " " + user.get("lastName", "")).strip() or None,
    "closer_email": user.get("email") or None,
    "lead_nombre": full or None, "lead_email": email or None,
    "payload": payload,
}, ensure_ascii=False))
'

RESULTS_F="$(mktemp)"; trap 'rm -f "$RESULTS_F"' EXIT
: >"$RESULTS_F"

for APPT_ID in "${ARGS[@]}"; do
  APPT_F="$(mktemp)"; CONTACT_F="$(mktemp)"; USER_F="$(mktemp)"

  if ! ghl_api_retry "/calendars/events/appointments/$APPT_ID" >"$APPT_F" 2>/tmp/reparar_hueco_ack.err; then
    ERR="$(head -c 300 /tmp/reparar_hueco_ack.err)"
    ROW="$(python3 -c 'import json,sys; print(json.dumps({"ok": False, "appointment_id": sys.argv[1], "motivo": "sonda GHL (appointment) falló: " + sys.argv[2]}, ensure_ascii=False))' "$APPT_ID" "$ERR")"
    echo "$ROW" >>"$RESULTS_F"
    echo "✗ $APPT_ID — sonda GHL (appointment) falló: $ERR" >&2
    rm -f "$APPT_F" "$CONTACT_F" "$USER_F"
    continue
  fi

  CONTACT_ID="$(python3 -c 'import json; d=json.load(open("'"$APPT_F"'")); print((d.get("appointment") or {}).get("contactId") or "")')"
  if [[ -n "$CONTACT_ID" ]]; then
    ghl_api_retry "/contacts/$CONTACT_ID" >"$CONTACT_F" 2>/dev/null || echo '{}' >"$CONTACT_F"
  else
    echo '{}' >"$CONTACT_F"
  fi

  ASSIGNED="$(python3 -c 'import json; d=json.load(open("'"$APPT_F"'")); print((d.get("appointment") or {}).get("assignedUserId") or "")')"
  if [[ -n "$ASSIGNED" ]]; then
    ghl_api_retry "/users/$ASSIGNED" >"$USER_F" 2>/dev/null || echo '{}' >"$USER_F"
  else
    echo '{}' >"$USER_F"
  fi

  ROW="$(python3 -c "$PY_ARMAR" "$APPT_F" "$CONTACT_F" "$USER_F" "$APPT_ID")"
  rm -f "$APPT_F" "$CONTACT_F" "$USER_F"

  OK="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("ok"))' <<<"$ROW")"

  if [[ "$OK" != "True" ]]; then
    MOTIVO="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("motivo") or "")' <<<"$ROW")"
    echo "$ROW" >>"$RESULTS_F"
    echo "✗ $APPT_ID — omitida: $MOTIVO" >&2
    continue
  fi

  if (( ! EJECUTAR )); then
    # dry-run: mostrar el payload completo (email visible) y NO tocar entrante.sh.
    echo "$ROW" >>"$RESULTS_F"
    if (( ! JSON )); then
      FUTURA="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print("futura" if d["futura"] else ("pasada" if d["futura"] is not None else "?"))' <<<"$ROW")"
      LEAD="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("lead_nombre") or "?")' <<<"$ROW")"
      CLOSER="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("closer_nombre") or "sin asignar")' <<<"$ROW")"
      echo "--- $APPT_ID ($FUTURA) — $LEAD — closer: $CLOSER [DRY-RUN, no se llamó a entrante.sh] ---"
      python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["payload"], indent=2, ensure_ascii=False))' <<<"$ROW"
    fi
    continue
  fi

  # --ejecutar: UNA cita a la vez, mostrando el resultado antes de seguir.
  PAYLOAD="$(python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["payload"], ensure_ascii=False))' <<<"$ROW")"
  RESP="$(printf '%s' "$PAYLOAD" | bash/agenda/entrante.sh)"
  MERGED="$(python3 -c '
import json, sys
row = json.loads(sys.argv[1]); resp = json.loads(sys.argv[2])
row["resultado_entrante"] = resp
print(json.dumps(row, ensure_ascii=False))' "$ROW" "$RESP")"
  echo "$MERGED" >>"$RESULTS_F"
  if (( ! JSON )); then
    echo "=== $APPT_ID → $RESP"
  fi
done

if (( JSON )); then
  python3 -c '
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
print(json.dumps(rows, ensure_ascii=False))
' "$RESULTS_F"
fi

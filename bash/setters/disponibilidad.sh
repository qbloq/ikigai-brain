#!/usr/bin/env bash
# disponibilidad.sh — LA MATRIZ SEMANAL DE DISPONIBILIDAD DE CLOSERS como un
# solo objeto JSON: closers × días (lunes–domingo) sobre el calendario de
# VENTA («Aplicación a Premium Mastermind»), para que el setter vea de un
# vistazo dónde hay campo antes de cuadrar una cita.
#
#   LA VERDAD ES GHL. Los huecos libres son los que calcula su endpoint
#   free-slots por closer (la configuración de disponibilidad de cada uno
#   menos sus citas) — aquí no se inventa horario laboral. Un closer con 0
#   libres y 0 citas en un día futuro sale `sin_horario` (no configuró su
#   disponibilidad en GHL); con citas y 0 libres sale `lleno`.
#
#   Días pasados: GHL no da huecos hacia atrás — la celda sale `pasado` con
#   las citas que hubo y libres vacío (declarado, no inventado).
#
#   Los closers son los MIEMBROS del calendario de venta, leídos en vivo
#   (GET /calendars/{id}); una cita del calendario asignada a alguien que no
#   es miembro (un setter, o nadie resoluble) va a `sin_closer`, nunca se bota.
#
# ⚠️ Solo GET a GHL y psql_ro. Cerca por rol vía bash/ghl/lib (dominio ghl).
# ⚠️ Sin Postgres no hay matriz: las credenciales de GHL viven en la base.
# ⚠️ GHL caído ≠ matriz vacía: fuente.ghl='error' y closers=[].
#
# Uso: disponibilidad.sh [--project N] [--fecha YYYY-MM-DD] [--calendar ID] [--json]
#   --project   fragmento del nombre (default: David Guerrero)
#   --fecha     un día cualquiera de la semana a mirar, Bogotá (default hoy)
#   --calendar  fija el calendario de venta (default: rol 'venta' en crm_calendars)
# Siempre emite JSON (un objeto). Read-only. Alimenta la fuente viz `disponibilidad_closers`.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../ghl/lib/common.sh"
export GHL_API_VERSION=2021-04-15   # calendars/* viven en esta versión

PROJECT="David Guerrero"; FECHA=""; CAL=""
usage() { sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)  PROJECT="${2:?}"; shift 2 ;;
    --fecha)    FECHA="${2:?}"; shift 2 ;;
    --calendar) CAL="${2:?}"; shift 2 ;;
    --json)     shift ;;
    -h|--help)  usage ;;
    *) echo "flag desconocido: $1" >&2; usage 1 ;;
  esac
done
[[ -z "$FECHA" ]] && FECHA="$(TZ=America/Bogota date +%F)"
[[ "$FECHA" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "--fecha debe ser YYYY-MM-DD" >&2; exit 2; }
AHORA="$(TZ=America/Bogota date +%FT%H:%M)"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
GHL_ESTADO=ok; GHL_DETALLE=""; DB_ESTADO=ok

# --- proyecto + credenciales --------------------------------------------------
IFS=$'\t' read -r PID PNAME < <(ghl_resolve_project "$PROJECT")
ghl_load_creds "$PID"
PID_ESC="${PID//\'/\'\'}"

# --- ventana: la semana entera en millis; free-slots solo desde AHORA ---------
read -r LUNES DOMINGO DESDE_MS HASTA_MS SLOTS_DESDE_MS < <(python3 - "$FECHA" "$HERE/lib" <<'PY'
import sys, time
from datetime import date, datetime, timedelta, timezone
sys.path.insert(0, sys.argv[2])
import disponibilidad_lib as D
dias = D.dias_semana(date.fromisoformat(sys.argv[1]))
tz = timezone(timedelta(hours=-5))
ms = lambda s: int(datetime.fromisoformat(s).replace(tzinfo=tz).timestamp() * 1000)
ahora_ms = int(time.time() * 1000)
ini, fin = ms(dias[0] + "T00:00"), ms(dias[-1] + "T00:00") + 86400000
print(dias[0], dias[-1], ini, fin, max(ini, ahora_ms))
PY
)

# --- el calendario de venta (espejo manda; --calendar sobreescribe) -----------
if [[ -z "$CAL" ]]; then
  LINEA="$(psql_ro -t -A -F$'\t' -c "SELECT ghl_calendar_id, coalesce(nullif(custom_name,''), ghl_calendar_name, '')
    FROM crm_calendars WHERE project_id='$PID_ESC' AND is_active AND rol = 'venta' ORDER BY created_at LIMIT 1;")" || LINEA=""
  CAL="${LINEA%%$'\t'*}"; CAL_NOMBRE="${LINEA#*$'\t'}"
else
  CAL_NOMBRE=""
fi
[[ -z "$CAL" ]] && { echo "el proyecto no tiene calendario de venta activo en crm_calendars (y no vino --calendar)" >&2; exit 2; }

# --- miembros del calendario, en vivo -----------------------------------------
MIEMBROS="[]"
if out="$(ghl_api "/calendars/$CAL" 2>"$TMP/err")"; then
  MIEMBROS="$(python3 -c 'import json,sys; d=json.load(sys.stdin); c=d.get("calendar") or d
print(json.dumps([m.get("userId") for m in (c.get("teamMembers") or []) if m.get("userId")]))' <<<"$out")"
  [[ -z "$CAL_NOMBRE" ]] && CAL_NOMBRE="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("calendar") or d).get("name") or "")' <<<"$out")"
else
  GHL_ESTADO=error; GHL_DETALLE="$(head -c 300 "$TMP/err" | tr '\n' ' ')"
fi
python3 -c 'import json,sys; json.dump({"id": sys.argv[1], "nombre": sys.argv[2] or None}, open(sys.argv[3],"w"), ensure_ascii=False)' \
  "$CAL" "$CAL_NOMBRE" "$TMP/calendario.json"

# --- nombres desde Postgres (una consulta) ------------------------------------
LOC_ESC="${GHL_LOCATION//\'/\'\'}"
USUARIOS="$(psql_ro -t -A -c "SELECT coalesce(json_agg(json_build_object(
    'ghl_user_id', u.integrations->>'$LOC_ESC', 'user_id', u.id,
    'nombre', trim(regexp_replace(coalesce(p.name,'')||' '||coalesce(p.lastname,''),'\s+',' ','g')))),'[]')
  FROM users u LEFT JOIN persons p ON p.person_id=u.person_id WHERE u.integrations ? '$LOC_ESC';" 2>"$TMP/dberr")" \
  || { DB_ESTADO=error; USUARIOS="[]"; echo "disponibilidad: la resolución de nombres falló: $(head -c 300 "$TMP/dberr")" >&2; }
python3 - "$TMP/closers.json" "$MIEMBROS" "$USUARIOS" <<'PY'
import json, sys
miembros, usuarios = json.loads(sys.argv[2]), {u["ghl_user_id"]: u for u in json.loads(sys.argv[3]) if u.get("ghl_user_id")}
out = [{"ghl_user_id": m, "user_id": (usuarios.get(m) or {}).get("user_id"),
        "nombre": (usuarios.get(m) or {}).get("nombre") or m} for m in miembros]
json.dump(out, open(sys.argv[1], "w"), ensure_ascii=False)
PY

# --- free-slots por closer (la semana en UNA llamada; tandas de 4) ------------
# Solo si queda semana por delante: GHL no calcula huecos hacia atrás.
mkdir -p "$TMP/slots"
if [[ "$GHL_ESTADO" == ok && "$SLOTS_DESDE_MS" -lt "$HASTA_MS" ]]; then
  n=0
  for uid in $(python3 -c 'import json,sys; print("\n".join(json.loads(sys.argv[1])))' "$MIEMBROS"); do
    ( ghl_api "/calendars/$CAL/free-slots?startDate=$SLOTS_DESDE_MS&endDate=$HASTA_MS&timezone=America/Bogota&userId=$uid" \
        >"$TMP/slots/$uid.json" 2>/dev/null || rm -f "$TMP/slots/$uid.json" ) &
    n=$((n+1)); (( n % 4 == 0 )) && wait
  done
  wait
fi
python3 - "$TMP" <<'PY'
import json, os, sys
tmp = sys.argv[1]; out = {}
sdir = os.path.join(tmp, "slots")
for fn in os.listdir(sdir) if os.path.isdir(sdir) else []:
    if not fn.endswith(".json"):
        continue
    try:
        d = json.load(open(os.path.join(sdir, fn)))
    except ValueError:
        continue
    d.pop("traceId", None)
    out[fn[:-5]] = {k: v.get("slots") or [] for k, v in d.items() if isinstance(v, dict)}
json.dump(out, open(os.path.join(tmp, "slots.json"), "w"))
PY

# --- las citas de la semana (un fetch) ----------------------------------------
echo '[]' >"$TMP/eventos.json"
if [[ "$GHL_ESTADO" == ok ]]; then
  if out="$(ghl_api "/calendars/events$(ghl_qs locationId "$GHL_LOCATION" calendarId "$CAL" startTime "$DESDE_MS" endTime "$HASTA_MS")" 2>"$TMP/err")"; then
    python3 -c 'import json,sys; json.dump(json.load(sys.stdin).get("events") or [], open(sys.argv[1],"w"), ensure_ascii=False)' \
      "$TMP/eventos.json" <<<"$out"
  else
    GHL_ESTADO=error; GHL_DETALLE="$(head -c 300 "$TMP/err" | tr '\n' ' ')"
  fi
fi

python3 -c 'import json,sys; json.dump({"ghl": sys.argv[1], "detalle": sys.argv[2] or None, "db": sys.argv[3]}, open(sys.argv[4],"w"))' \
  "$GHL_ESTADO" "$GHL_DETALLE" "$DB_ESTADO" "$TMP/fuente.json"

python3 "$HERE/lib/disponibilidad_lib.py" --dir "$TMP" --proyecto "$PNAME" --fecha "$FECHA" --ahora "$AHORA"

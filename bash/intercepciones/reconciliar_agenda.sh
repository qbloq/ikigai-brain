#!/usr/bin/env bash
# [WRITE sqlite intercepciones] Reconciliación de agenda — la verificación
# INDEPENDIENTE del interceptor: ¿los meetings 'scheduled' de la DB son
# exactamente los Appointments vivos del calendario GHL del proyecto?
# Por cada crm_calendars activo: GHL (via bash/ghl/appointments.sh) vs
# meetings (psql_ro), se cruzan por meetings.event_id = appointment.id, y se
# escriben corridas + drift en la sqlite del interceptor (UNA txn por corrida).
#
# ⚠️ Horas: meetings.scheduled_start_time guarda el reloj BOGOTÁ etiquetado
# como UTC, así que se lee LITERAL (AT TIME ZONE 'UTC' extrae el naive tal
# cual) y NO se convierte — convertir corre todo 5 horas. El startTime de GHL
# sí es ISO real (trae offset, p.ej. -05:00) → se pasa a reloj de pared Bogotá
# (UTC−5). Recién ahí los dos lados hablan el mismo idioma y se comparan al
# minuto. Verificado 2026-08-16 contra bash/closers/agenda.sh.
# ⚠️ GHL caído ≠ agenda vacía: si la sonda falla, la corrida queda con
# estado='error' y el detalle del stderr, SIN filas de drift, y se sigue con
# el siguiente calendario. Un 0 inventado borraría la agenda entera del día.
#
# ⚠️ LA VENTANA ES UNA SOLA, y se aplica a los DOS lados con las mismas fechas
# Bogotá (VENT_DESDE..VENT_HASTA, día completo). GHL filtra por su cuenta con
# epoch-millis y devuelve citas FUERA de lo pedido (filtro grueso del server),
# y el SQL usaba `now()-1d` — dos ventanas distintas fabrican drift espurio en
# los bordes: una cita de hoy-1 a las 09:00 entraba por GHL y no por la DB.
# Ahora el python descarta los eventos cuyo minuto Bogotá cae fuera, y el SQL
# usa esas mismas fechas sobre el reloj literal.
# ⚠️ El lado DB trae TODOS los status (no solo scheduled/cancelled): una
# llamada que ya ocurrió está 'ended'/'completed' y NO es un faltante. Solo
# 'cancelled' cuenta como «no agendada»; cualquier otro status pareado con una
# cita viva es `coinciden`. Y solo las 'scheduled' entran al compare de minuto
# (`horas_difieren`) y pueden salir como `sobra_en_db`: una reunión que ya pasó
# no se puede «reagendar sin avisar».
# ⚠️ SEGUNDA consulta por event_id (sin ventana): si una cita se reagendó, la
# hora VIEJA de la DB puede caer fuera de la ventana y el par se clasificaría
# `falta_en_db` con meeting_id null — quien lo repare a ciegas crearía un
# duplicado en vez de mover la fila. Trayendo el meeting por id, ese caso sale
# `horas_difieren` con su meeting_id real.
#
# uso: reconciliar_agenda.sh [--desde N] [--hasta N] [--dry-run] [--json]
#   --desde/--hasta  días relativos a hoy (default: -1 y 30)
#   --dry-run        imprime resumen + drift por stderr y NO escribe nada
#   --json           stdout = array JSON con el resumen por calendario
set -euo pipefail
INT_DIR_SELF="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$INT_DIR_SELF/lib.sh"
# shellcheck disable=SC1091
source "$INT_DIR_SELF/../lib/common.sh"

DESDE=-1; HASTA=30; DRY=0; FORMAT=table
usage() { sed -n '2,41p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --desde) DESDE="$2"; shift 2 ;;
    --hasta) HASTA="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) usage ;;
    *) echo "flag desconocido: $1" >&2; usage 1 ;;
  esac
done
# La ventana ya no entra al SQL (ahora van las fechas Bogotá entrecomilladas),
# pero sí a `date -d` y a la sonda GHL — se valida que sea un entero igual.
[[ "$DESDE" =~ ^-?[0-9]+$ && "$HASTA" =~ ^-?[0-9]+$ ]] || {
  echo "--desde/--hasta deben ser enteros (días relativos a hoy)" >&2; exit 1; }

# ---------------------------------------------------------------------------
# El comparador: recibe los dos lados por ENTORNO (jamás interpolados en el
# fuente python — un título con comillas rompería el script, o algo peor) y
# emite {corrida, drift[], resumen} en una línea JSON.
# ---------------------------------------------------------------------------
PY_COMPARA='
import json, os, sys
from datetime import datetime, timezone, timedelta

pid, pnombre, cal, vent_desde, vent_hasta = sys.argv[1:6]
ghl = json.loads(os.environ["GHL_JSON"])
db = json.loads(os.environ["DB_JSON"])
db_extra = json.loads(os.environ.get("DB_EXTRA_JSON") or "[]")

BOG = timezone(timedelta(hours=-5))
CANCELADOS = {"cancelled", "invalid", "noshow", "no-show"}

def bog_minuto(iso):
    # startTime de GHL: ISO real con offset -> reloj de pared Bogota, al minuto.
    if not iso:
        return None
    return datetime.fromisoformat(iso.replace("Z", "+00:00")).astimezone(BOG).strftime("%Y-%m-%dT%H:%M")

def cancelado(e):
    return (e.get("appointmentStatus") or "").lower() in CANCELADOS

def en_ventana(minuto):
    # La MISMA ventana que el SQL: fechas Bogota, dia completo en los dos bordes.
    return minuto is not None and vent_desde <= minuto[:10] <= vent_hasta

# GHL filtra grueso: devuelve eventos fuera de la ventana pedida. Se descartan
# aca para que los dos lados comparen el mismo conjunto de dias.
ghl_por_id = {}
fuera = 0
for e in ghl:
    if not e.get("id"):
        continue
    if not en_ventana(bog_minuto(e.get("startTime"))):
        fuera += 1
        continue
    ghl_por_id[e["id"]] = e
if fuera:
    sys.stderr.write("aviso: {} eventos GHL fuera de la ventana {}..{} descartados en {}\n".format(
        fuera, vent_desde, vent_hasta, pnombre))
# Las citas VIVAS se calculan aca, ANTES del merge de la consulta por id: son
# la puerta de ese merge (ver abajo).
vivos = {i: e for i, e in ghl_por_id.items() if not cancelado(e)}

con_appt = [m for m in db if m.get("event_id")]
db_por_appt = {m["event_id"]: m for m in con_appt}
# Dos meetings con el mismo event_id se colapsan en el dict y el segundo gana
# en silencio. No hay tipo de drift para eso (el CHECK es cerrado), asi que
# por ahora se OBSERVA: se avisa por stderr con los ids afectados.
if len(con_appt) != len(db_por_appt):
    vistos, dupes = set(), []
    for m in con_appt:
        if m["event_id"] in vistos:
            dupes.append(m["event_id"])
        vistos.add(m["event_id"])
    sys.stderr.write("aviso: {} meetings con event_id duplicado en {} -> {}\n".format(
        len(con_appt) - len(db_por_appt), pnombre, ", ".join(sorted(set(dupes)))))
# Los meetings traidos por event_id SIN filtro de ventana (segunda consulta):
# rellenan los pares cuya hora vieja quedo afuera. La fila de ventana gana.
# ⚠️ SOLO para citas VIVAS y dentro de la ventana: la consulta por id se arma
# con el payload crudo de GHL, asi que puede traer el meeting de un evento que
# `en_ventana` (o `cancelado`) acaba de descartar. Metido al dict, ese meeting
# no tendria par en ghl_por_id y el lado DB lo pintaria `sobra_en_db` con
# estado_ghl "ausente" — un drift inventado por el propio remedio.
for m in db_extra:
    if m.get("event_id") in vivos and m["event_id"] not in db_por_appt:
        db_por_appt[m["event_id"]] = m

drift = []
coinciden = 0

# Lado GHL: la cita existe y no esta cancelada -> tiene que estar agendada aca.
for i in sorted(vivos):
    e = vivos[i]
    m = db_por_appt.get(i)
    ghl_min = bog_minuto(e.get("startTime"))
    det = {"titulo": e.get("title"), "ghl_inicio_bogota": ghl_min,
           "estado_ghl": e.get("appointmentStatus"), "contact_id": e.get("contactId")}
    # Solo 'cancelled' (o la ausencia) es un faltante. Una llamada que ya
    # ocurrio ('ended'/'completed'/...) esta agendada, no falta.
    if m is None or m["status"] == "cancelled":
        det["estado_db"] = m["status"] if m else "ausente"
        drift.append({"tipo": "falta_en_db", "appointment_id": i,
                      "meeting_id": m["id"] if m else None, "detalle": det})
    # Solo las 'scheduled' pueden estar «reagendadas sin avisar»: en una que ya
    # paso, las horas de GHL pueden diferir legitimamente y no es drift.
    elif m["status"] == "scheduled" and m["inicio_bogota"] != ghl_min:
        det["db_inicio_bogota"] = m["inicio_bogota"]
        drift.append({"tipo": "horas_difieren", "appointment_id": i,
                      "meeting_id": m["id"], "detalle": det})
    else:
        coinciden += 1

# Lado DB: agendada aca pero en GHL no esta, o esta cancelada -> sobra.
for appt in sorted(db_por_appt):
    m = db_por_appt[appt]
    if m["status"] != "scheduled":
        continue
    e = ghl_por_id.get(appt)
    if e is not None and not cancelado(e):
        continue
    det = {"titulo": m.get("name"), "db_inicio_bogota": m["inicio_bogota"],
           "estado_ghl": e.get("appointmentStatus") if e else "ausente"}
    drift.append({"tipo": "sobra_en_db", "appointment_id": appt,
                  "meeting_id": m["id"], "detalle": det})

db_total = sum(1 for m in db if m["status"] == "scheduled")
resumen = {"proyecto": pnombre, "ghl": len(vivos), "db": db_total,
           "coinciden": coinciden, "discrepancias": len(drift)}
print(json.dumps({
    "corrida": {"project_id": pid, "proyecto": pnombre, "ghl_calendar_id": cal,
                "ventana_desde": vent_desde, "ventana_hasta": vent_hasta,
                "ghl_total": len(vivos), "db_total": db_total,
                "coinciden": coinciden, "discrepancias": len(drift)},
    "drift": drift, "resumen": resumen}, ensure_ascii=False))
'

# ---------------------------------------------------------------------------
# El persistidor: lee ese JSON por stdin y emite la transacción entera.
# La corrida y sus drift van juntos o no van: los drift cuelgan de la corrida
# por FK (int_sql antepone PRAGMA foreign_keys=ON), y su corrida_id se toma
# con (SELECT max(id) FROM corridas) — estable dentro de la txn, a diferencia
# de last_insert_rowid(), que cada INSERT de drift movería.
# ---------------------------------------------------------------------------
PY_PERSISTIR='
import json, sys

def lit(v):
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return str(int(v))
    if isinstance(v, int):
        return str(v)
    return "\x27" + str(v).replace("\x27", "\x27\x27") + "\x27"

d = json.load(sys.stdin)
c = d["corrida"]
cols = ["project_id", "proyecto", "ghl_calendar_id", "ventana_desde", "ventana_hasta",
        "ghl_total", "db_total", "coinciden", "discrepancias"]
print("BEGIN;")
print("INSERT INTO corridas (" + ", ".join(cols) + ") VALUES ("
      + ", ".join(lit(c[k]) for k in cols) + ");")
for x in d["drift"]:
    print("INSERT INTO drift (corrida_id, tipo, appointment_id, meeting_id, detalle) VALUES ("
          "(SELECT max(id) FROM corridas), "
          + lit(x["tipo"]) + ", " + lit(x["appointment_id"]) + ", "
          + lit(x["meeting_id"]) + ", "
          + lit(json.dumps(x["detalle"], ensure_ascii=False)) + ");")
print("COMMIT;")
'

PY_MOSTRAR='
import json, sys
d = json.load(sys.stdin)
print("[dry-run] " + json.dumps(d["resumen"], ensure_ascii=False))
for x in d["drift"]:
    print("  drift: " + json.dumps(x, ensure_ascii=False))
'

(( DRY )) || ensure_schema

# Los calendarios integrados activos: el universo de la reconciliación.
CALS="$(psql_ro -t -A -F$'\t' -c "
  SELECT cc.ghl_calendar_id, cc.project_id, p.name
  FROM crm_calendars cc JOIN projects p ON p.id = cc.project_id
  WHERE cc.is_active ORDER BY p.name;")"
[[ -z "$CALS" ]] && { echo "sin calendarios activos en crm_calendars" >&2; exit 0; }

TRABAJO="$(mktemp -d)"
trap 'rm -rf "$TRABAJO"' EXIT
RESUMENES="$TRABAJO/resumenes.jsonl"; : >"$RESUMENES"

# La etiqueta de la ventana se calcula en hora BOGOTÁ, no en la del host: el
# servidor api corre en UTC y entre las 19:00 y la medianoche de Bogotá
# `date` ya está en el día siguiente — corridas.ventana_* mentiría a diario.
VENT_DESDE="$(TZ=America/Bogota date -d "$DESDE days" +%F)"
VENT_HASTA="$(TZ=America/Bogota date -d "$HASTA days" +%F)"

# fd 3: el bucle llama scripts que también leen stdin — la lista no se les cede.
while IFS=$'\t' read -r CAL PID PNOMBRE <&3; do
  [[ -z "$CAL" ]] && continue

  # --- lado GHL (la fuente) --------------------------------------------------
  GHL_ERR=""
  if GHL_JSON="$("$INT_DIR_SELF/../ghl/appointments.sh" --project-id "$PID" \
        --calendar "$CAL" --desde "$DESDE" --hasta "$HASTA" --json 2>"$TRABAJO/ghl.err")"; then
    GHL_OK=1
  else
    GHL_OK=0; GHL_ERR="$(head -c 300 "$TRABAJO/ghl.err")"
  fi

  if (( ! GHL_OK )); then
    # GHL caído ≠ agenda vacía: se deja constancia y NO se compara nada.
    echo "corrida ERROR $PNOMBRE ($CAL): ${GHL_ERR:-la sonda GHL falló sin stderr}" >&2
    if (( ! DRY )); then
      printf '%s\n' "INSERT INTO corridas
        (project_id, proyecto, ghl_calendar_id, ventana_desde, ventana_hasta, estado, detalle)
        VALUES ($(sql_lit "$PID"), $(sql_lit "$PNOMBRE"), $(sql_lit "$CAL"),
                $(sql_lit "$VENT_DESDE"), $(sql_lit "$VENT_HASTA"), 'error', $(sql_lit "$GHL_ERR"));" \
        | int_sql
    fi
    continue
  fi

  # --- lado DB (reloj literal = Bogotá; ver el ⚠️ de la cabecera) ------------
  # Mismas fechas que el filtro del python sobre GHL, día completo en los dos
  # bordes, y TODOS los status (el python decide qué significa cada uno).
  DB_JSON="$(psql_ro -t -A -c "
    SELECT coalesce(json_agg(row_to_json(q)), '[]'::json) FROM (
      SELECT m.id, m.event_id, m.status, m.name,
        to_char(m.scheduled_start_time AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI') AS inicio_bogota
      FROM meetings m
      WHERE m.meeting_type = 'call' AND m.project_id = '${PID//\'/\'\'}'
        AND m.scheduled_start_time AT TIME ZONE 'UTC' >= $(sql_lit "$VENT_DESDE")::timestamp
        AND m.scheduled_start_time AT TIME ZONE 'UTC' <  ($(sql_lit "$VENT_HASTA")::timestamp + interval '1 day')
    ) q;")"

  # --- lado DB, segunda pasada: los meetings de ESAS citas, sin ventana ------
  # Los ids de GHL son opacos; se validan contra ^[A-Za-z0-9_-]+$ en python y
  # otra vez en bash antes de tocar el SQL (y aun así van entrecomillados).
  IDS_SQL="$(GHL_JSON="$GHL_JSON" python3 -c '
import json, os, re, sys
ok = re.compile(r"^[A-Za-z0-9_-]+$")
ids = sorted({e["id"] for e in json.loads(os.environ["GHL_JSON"])
              if e.get("id") and ok.match(str(e["id"]))})
sys.stdout.write(", ".join("\x27" + i.replace("\x27", "\x27\x27") + "\x27" for i in ids))')"
  DB_EXTRA_JSON='[]'
  if [[ -n "$IDS_SQL" ]]; then
    if [[ "$IDS_SQL" =~ ^\'[A-Za-z0-9_-]+\'(,\ \'[A-Za-z0-9_-]+\')*$ ]]; then
      DB_EXTRA_JSON="$(psql_ro -t -A -c "
        SELECT coalesce(json_agg(row_to_json(q)), '[]'::json) FROM (
          SELECT m.id, m.event_id, m.status, m.name,
            to_char(m.scheduled_start_time AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI') AS inicio_bogota
          FROM meetings m
          WHERE m.meeting_type = 'call' AND m.project_id = '${PID//\'/\'\'}'
            AND m.event_id IN ($IDS_SQL)
        ) q;")"
    else
      echo "aviso: lista de appointment_id no válida, se omite la consulta por id ($PNOMBRE)" >&2
    fi
  fi

  # --- comparación -----------------------------------------------------------
  OUT="$(GHL_JSON="$GHL_JSON" DB_JSON="$DB_JSON" DB_EXTRA_JSON="$DB_EXTRA_JSON" \
    python3 -c "$PY_COMPARA" "$PID" "$PNOMBRE" "$CAL" "$VENT_DESDE" "$VENT_HASTA")"

  # --- persistencia: corrida + drift en UNA transacción ----------------------
  if (( DRY )); then
    printf '%s' "$OUT" | python3 -c "$PY_MOSTRAR" >&2
  else
    printf '%s' "$OUT" | python3 -c "$PY_PERSISTIR" | int_sql
  fi

  printf '%s' "$OUT" \
    | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["resumen"], ensure_ascii=False))' \
    >>"$RESUMENES"
done 3<<<"$CALS"

python3 -c '
import json, sys
rs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
if sys.argv[2] == "json":
    print(json.dumps(rs, ensure_ascii=False))
else:
    for r in rs:
        print("{}: ghl={} db={} coinciden={} drift={}".format(
            r["proyecto"], r["ghl"], r["db"], r["coinciden"], r["discrepancias"]))
' "$RESUMENES" "$FORMAT"

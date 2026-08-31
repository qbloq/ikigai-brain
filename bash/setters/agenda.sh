#!/usr/bin/env bash
# agenda.sh — LA AGENDA DEL SETTER como un solo objeto JSON: las citas de los
# DOS calendarios oficiales de GHL (día o semana) enriquecidas con lo que el
# Cerebro sabe de cada lead. Spec: docs/superpowers/specs/2026-08-26-agenda-setter-design.md
# (+ ajuste dos calendarios, decisión de Santiago 2026-08-26).
#
#   DOS CALENDARIOS: el del FUNNEL (crm_calendars activo; el widget agenda ahí
#   y la llamada la toma un SETTER — round-robin entre ellos) y el de CLOSERS
#   («Aplicación…», donde el setter cuadra la agenda de los closers). Cada cita
#   sale con `calendario: funnel|closers`; `sin_closer` solo aplica en closers.
#   El de closers se fija con --calendar-closers o se descubre en vivo (activo,
#   nombre «aplicación…», no personal). Para el cruce funnel→«ya agendó con
#   closer» se traen además las citas de closers de los 7 días siguientes.
#
#   GHL MANDA. La lista de citas es la de GHL; Postgres solo enriquece (Meet,
#   transcript/grabación, reporte BANT, plan de pago, etapa del tablero,
#   historial). Si GHL falla, fuente.ghl='error' y citas=[] — jamás se rellena
#   la agenda desde la base.
#
#   Por cita: contacto EN VIVO (GET /contacts/{id}) — el lead recién agendado
#   existe en GHL antes que en el espejo; si el GET falla, cae al espejo y la
#   fila lo declara (lead.fuente). Banda pre-llamada A/B/C (lead-score.md §5)
#   solo para las que vienen; estado por capas para las que pasaron.
#   `anunciada` (lo que el closer dijo en ONLY CLOSERS) es null en v1.
#
# ⚠️ Horas: startTime de GHL trae offset → pared Bogotá (UTC−5);
#    meetings.scheduled_start_time se lee LITERAL (quirk Bogotá-como-UTC).
# ⚠️ Solo GET a GHL y psql_ro. Cerca por rol vía bash/ghl/lib (dominio ghl).
# ⚠️ Sin Postgres no hay agenda: las credenciales de GHL viven en la base.
# ⚠️ bash 3.2: las lecturas de contacto van en tandas de 4 subshells + wait.
#
# Uso: agenda.sh [--project N] [--fecha YYYY-MM-DD] [--vista dia|semana]
#                [--calendar-closers ID] [--json]
#   --project  fragmento del nombre (default: David Guerrero)
#   --fecha    día de referencia, Bogotá (default hoy)
#   --vista    dia (default) · semana = lunes–domingo que contiene --fecha
# Siempre emite JSON (un objeto). Read-only. Alimenta la fuente viz `agenda_setter`.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../ghl/lib/common.sh"
export GHL_API_VERSION=2021-04-15   # calendars/* viven en esta versión

PROJECT="David Guerrero"; FECHA=""; VISTA="dia"; CAL_CLOSERS=""
usage() { sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:?}"; shift 2 ;;
    --fecha)   FECHA="${2:?}"; shift 2 ;;
    --vista)   VISTA="${2:?}"; shift 2 ;;
    --calendar-closers) CAL_CLOSERS="${2:?}"; shift 2 ;;
    --json)    shift ;;
    -h|--help) usage ;;
    *) echo "flag desconocido: $1" >&2; usage 1 ;;
  esac
done
[[ -z "$FECHA" ]] && FECHA="$(TZ=America/Bogota date +%F)"
[[ "$FECHA" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "--fecha debe ser YYYY-MM-DD" >&2; exit 2; }
[[ "$VISTA" == "dia" || "$VISTA" == "semana" ]] || { echo "--vista debe ser dia|semana" >&2; exit 2; }
AHORA="$(TZ=America/Bogota date +%FT%H:%M)"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/contactos"
GHL_ESTADO=ok; GHL_DETALLE=""; DB_ESTADO=ok

# --- proyecto + credenciales (una vez) --------------------------------------
IFS=$'\t' read -r PID PNAME < <(ghl_resolve_project "$PROJECT")
ghl_load_creds "$PID"
PID_ESC="${PID//\'/\'\'}"

# --- ventana Bogotá → epoch millis (GHL filtra grueso; el python re-filtra) --
read -r DESDE HASTA DESDE_MS HASTA_MS HASTA_CRUCE_MS < <(python3 - "$FECHA" "$VISTA" "$HERE/lib" <<'PY'
import sys
from datetime import date, datetime, timedelta, timezone
sys.path.insert(0, sys.argv[3])
import agenda_lib as L
f = date.fromisoformat(sys.argv[1]); d, h = L.ventana(f, sys.argv[2])
tz = timezone(timedelta(hours=-5))
ms = lambda x: int(datetime(x.year, x.month, x.day, tzinfo=tz).timestamp() * 1000)
print(d.isoformat(), h.isoformat(), ms(d), ms(h + timedelta(days=1)), ms(h + timedelta(days=8)))
PY
)

# --- los dos calendarios ------------------------------------------------------
# funnel: los activos del espejo crm_calendars (el oficial del widget).
CALS="$(psql_ro -t -A -F$'\t' -c "SELECT ghl_calendar_id, coalesce(nullif(custom_name,''), ghl_calendar_name, '')
  FROM crm_calendars WHERE project_id='$PID_ESC' AND is_active ORDER BY created_at;")" || { DB_ESTADO=error; CALS=""; }
[[ -z "$CALS" ]] && { GHL_ESTADO=error; GHL_DETALLE="el proyecto no tiene calendario activo en crm_calendars"; }
FUNNEL_IDS="$(cut -f1 <<<"$CALS" | paste -sd, -)"

# closers: --calendar-closers manda; si no, descubrimiento en vivo (activo,
# nombre «aplicación…», no personal, distinto del funnel).
CLOSERS_LINEA=""
ALLCALS="$(ghl_api "/calendars/?locationId=$GHL_LOCATION" 2>"$TMP/err" || true)"
[[ -z "$ALLCALS" ]] && ALLCALS='{}'
printf '%s' "$ALLCALS" >"$TMP/allcals.json"
CLOSERS_LINEA="$(python3 - "$TMP/allcals.json" "$CAL_CLOSERS" "$FUNNEL_IDS" <<'PY'
import json, sys, unicodedata
cals = (json.load(open(sys.argv[1])) or {}).get("calendars") or []
quiere, funnel = sys.argv[2], set(filter(None, sys.argv[3].split(",")))
def plano(s):
    return unicodedata.normalize("NFD", s or "").encode("ascii", "ignore").decode().lower()
elegido = None
for c in cals:
    if quiere and c.get("id") == quiere:
        elegido = c; break
    if not quiere and c.get("isActive") and c.get("id") not in funnel \
       and "aplicacion" in plano(c.get("name")) and "personal" not in plano(c.get("name")):
        elegido = elegido or c
if elegido:
    print("%s\t%s" % (elegido["id"], elegido.get("name") or ""))
PY
)"

{ while IFS=$'\t' read -r cid cnom; do [[ -n "$cid" ]] && printf '%s\t%s\t%s\n' "$cid" "$cnom" funnel; done <<<"$CALS"
  [[ -n "$CLOSERS_LINEA" ]] && printf '%s\t%s\n' "$CLOSERS_LINEA" closers; } >"$TMP/cals.tsv"

echo '[]' >"$TMP/calendarios.json"; echo '[]' >"$TMP/eventos.json"; echo '[]' >"$TMP/eventos_cruce.json"
while IFS=$'\t' read -r cal_id cal_nombre cal_tipo; do
  [[ -z "$cal_id" ]] && continue
  miembros="[]"
  if out="$(ghl_api "/calendars/$cal_id" 2>"$TMP/err")"; then
    miembros="$(python3 -c 'import json,sys; d=json.load(sys.stdin); c=d.get("calendar") or d
print(json.dumps([m.get("userId") for m in (c.get("teamMembers") or []) if m.get("userId")]))' <<<"$out")"
  fi
  python3 - "$TMP/calendarios.json" "$cal_id" "$cal_nombre" "$cal_tipo" "$miembros" <<'PY'
import json, sys
p, cid, nom, tipo, mem = sys.argv[1:6]
arr = json.load(open(p)); arr.append({"id": cid, "nombre": nom, "tipo": tipo, "miembros": json.loads(mem)})
json.dump(arr, open(p, "w"), ensure_ascii=False)
PY
  fin_ms="$HASTA_MS"; [[ "$cal_tipo" == "closers" ]] && fin_ms="$HASTA_CRUCE_MS"
  if out="$(ghl_api "/calendars/events$(ghl_qs locationId "$GHL_LOCATION" calendarId "$cal_id" startTime "$DESDE_MS" endTime "$fin_ms")" 2>"$TMP/err")"; then
    printf '%s' "$out" >"$TMP/ev_raw.json"
    python3 - "$TMP" "$cal_id" "$HASTA" <<'PY'
import json, sys, os
tmp, cal_id, hasta = sys.argv[1:4]
nuevo = json.load(open(os.path.join(tmp, "ev_raw.json"))).get("events") or []
for destino, pred in (("eventos.json", lambda e: e.get("startTime", "")[:10] <= hasta),
                      ("eventos_cruce.json", lambda e: e.get("startTime", "")[:10] > hasta)):
    p = os.path.join(tmp, destino)
    arr = json.load(open(p)); vistos = {e.get("id") for e in arr}
    arr += [e for e in nuevo if e.get("calendarId") == cal_id and e.get("id") not in vistos and pred(e)]
    json.dump(arr, open(p, "w"), ensure_ascii=False)
PY
  else
    GHL_ESTADO=error; GHL_DETALLE="$(head -c 300 "$TMP/err" | tr '\n' ' ')"
  fi
done <"$TMP/cals.tsv"

# --- contactos en vivo (solo los de la ventana), en tandas de 4 ---------------
IDS="$(python3 -c '
import json, sys
print("\n".join(sorted({e.get("contactId") for e in json.load(open(sys.argv[1])) if e.get("contactId")})))' "$TMP/eventos.json")"
n=0
for cid in $IDS; do
  ( ghl_api "/contacts/$cid" >"$TMP/contactos/$cid.json" 2>/dev/null || rm -f "$TMP/contactos/$cid.json" ) &
  n=$((n+1)); (( n % 4 == 0 )) && wait
done
wait

# --- Postgres: UNA consulta con todos los ids -----------------------------------
AP_SQL="$(python3 -c '
import json, sys
ids = [e["id"] for e in json.load(open(sys.argv[1])) if e.get("id")]
print(",".join("\x27%s\x27" % i.replace("\x27","\x27\x27") for i in ids) or "\x27__ninguna__\x27")' "$TMP/eventos.json")"
CT_SQL="$(printf '%s\n' $IDS | sed "s/'/''/g; s/.*/'&'/" | paste -sd, -)"; [[ -z "$CT_SQL" || "$CT_SQL" == "''" ]] && CT_SQL="'__ninguno__'"
LOC_ESC="${GHL_LOCATION//\'/\'\'}"

DB_JSON="$(psql_ro -t -A -c "
WITH ap AS (SELECT unnest(ARRAY[$AP_SQL]) AS id),
     ct AS (SELECT unnest(ARRAY[$CT_SQL]) AS id),
     closer_de AS (
       SELECT c.ghl_contact_id,
              trim(regexp_replace(coalesce(p.name,'')||' '||coalesce(p.lastname,''),'\s+',' ','g')) AS dueno,
              (SELECT st->>'name' FROM jsonb_array_elements(pl.stages::jsonb) st WHERE st->>'id' = o.ghl_stage_id) AS etapa,
              row_number() OVER (PARTITION BY c.ghl_contact_id ORDER BY (o.project_id='$PID_ESC') DESC NULLS LAST, o.created_date DESC) AS rn
       FROM crm_contacts c JOIN crm_opportunities o ON o.contact_id=c.id
       LEFT JOIN crm_pipelines pl ON pl.id=o.pipeline_id
       LEFT JOIN users u ON u.id=o.user_id LEFT JOIN persons p ON p.person_id=u.person_id
       WHERE c.ghl_contact_id IN (SELECT id FROM ct))
SELECT json_build_object(
 'catalogo', (SELECT coalesce(json_agg(json_build_object('ghl_field_id',ghl_field_id,'name',name,'position',position) ORDER BY position NULLS LAST),'[]')
              FROM crm_custom_fields WHERE project_id='$PID_ESC'),
 'usuarios', (SELECT coalesce(json_agg(json_build_object('ghl_user_id', u.integrations->>'$LOC_ESC', 'user_id', u.id,
                 'nombre', trim(regexp_replace(coalesce(p.name,'')||' '||coalesce(p.lastname,''),'\s+',' ','g')))),'[]')
              FROM users u LEFT JOIN persons p ON p.person_id=u.person_id WHERE u.integrations ? '$LOC_ESC'),
 'meetings', (SELECT coalesce(json_agg(row_to_json(x)),'[]') FROM (
    SELECT coalesce(m.event_id, m.event->'booking'->>'appointment_id') AS appointment_id,
           left(m.id::text,8) AS id8, m.meet_url, m.status,
           (m.recording_url IS NOT NULL OR m.drive_file_id IS NOT NULL) AS grabacion,
           (coalesce(length(t.transcript),0) >= 2000) AS transcript,
           v.fuente AS reporte_fuente, to_json(v.baja_confianza) AS baja_confianza,
           v.report->'leadProfile'->'bantAnalysis' AS bant,
           v.report->'leadProfile'->'intelligentSegmentation'->'archetype'->>'name' AS arquetipo
    FROM meetings m
    LEFT JOIN meeting_transcripts t ON t.meeting_id=m.id
    LEFT JOIN call_report_vigente v ON v.meeting_id=m.id
    WHERE m.meeting_type='call'
      AND (m.event_id IN (SELECT id FROM ap) OR m.event->'booking'->>'appointment_id' IN (SELECT id FROM ap))) x),
 'planes', (SELECT coalesce(json_agg(row_to_json(x)),'[]') FROM (
    SELECT pp.customer_id, left(pp.plan_id::text,8) AS plan_id8, pp.original_amount AS monto,
           pp.number_of_installments AS cuotas, to_char(pp.created_at AT TIME ZONE 'America/Bogota','YYYY-MM-DD') AS creado
    FROM payment_plans pp WHERE pp.customer_id IN (SELECT id FROM ct) AND pp.plan_status='Active'
    ORDER BY pp.created_at DESC) x),
 'opps', (SELECT coalesce(json_agg(json_build_object('ghl_contact_id',ghl_contact_id,'etapa',etapa,'dueno',dueno)),'[]') FROM closer_de WHERE rn=1),
 'historial', (SELECT coalesce(json_agg(row_to_json(x)),'[]') FROM (
    SELECT g.ghl_contact_id, g.llamadas_previas, g.ultima,
           (SELECT round(avg(nullif(regexp_replace(coalesce(v2.report->'leadProfile'->'bantAnalysis'->k->>'score',''),'[^0-9]','','g'),'')::numeric))
              FROM meetings m2 JOIN call_report_vigente v2 ON v2.meeting_id=m2.id,
                   unnest(ARRAY['budget','authority','need','timeline']) k
             WHERE m2.event->'booking'->>'contact_id' = g.ghl_contact_id
               AND (m2.scheduled_start_time AT TIME ZONE 'UTC')::date < '$DESDE'
             GROUP BY m2.id, m2.scheduled_start_time ORDER BY m2.scheduled_start_time DESC LIMIT 1) AS bant_previo
    FROM (SELECT m.event->'booking'->>'contact_id' AS ghl_contact_id, count(*) AS llamadas_previas,
                 to_char(max(m.scheduled_start_time AT TIME ZONE 'UTC'),'YYYY-MM-DD') AS ultima
          FROM meetings m
          WHERE m.meeting_type='call' AND m.event->'booking'->>'contact_id' IN (SELECT id FROM ct)
            AND (m.scheduled_start_time AT TIME ZONE 'UTC')::date < '$DESDE' AND m.status <> 'cancelled'
          GROUP BY 1) g) x),
 'espejo', (SELECT coalesce(json_agg(row_to_json(x)),'[]') FROM (
    SELECT ghl_contact_id, first_name, last_name, email, phone, custom_fields, tags
    FROM crm_contacts WHERE ghl_contact_id IN (SELECT id FROM ct)) x),
 'solo_en_sistema', (SELECT coalesce(json_agg(row_to_json(x) ORDER BY x.fecha, x.hora),'[]') FROM (
    SELECT left(m.id::text,8) AS id8,
           to_char(m.scheduled_start_time AT TIME ZONE 'UTC','YYYY-MM-DD') AS fecha,
           to_char(m.scheduled_start_time AT TIME ZONE 'UTC','HH24:MI') AS hora,
           regexp_replace(m.name, ' *[-|–] *.*$', '') AS lead,
           (SELECT trim(regexp_replace(coalesce(p.name,'')||' '||coalesce(p.lastname,''),'\s+',' ','g'))
              FROM crm_contacts c JOIN crm_opportunities o ON o.contact_id=c.id
              LEFT JOIN users u ON u.id=o.user_id LEFT JOIN persons p ON p.person_id=u.person_id
             WHERE c.ghl_contact_id = m.event->'booking'->>'contact_id'
             ORDER BY (o.project_id=m.project_id) DESC NULLS LAST, o.created_date DESC LIMIT 1) AS closer
    FROM meetings m
    WHERE m.meeting_type='call' AND m.project_id='$PID_ESC' AND m.status <> 'cancelled'
      AND (m.scheduled_start_time AT TIME ZONE 'UTC')::date BETWEEN '$DESDE' AND '$HASTA'
      AND coalesce(m.event_id, m.event->'booking'->>'appointment_id') NOT IN (SELECT id FROM ap)) x)
);" 2>"$TMP/dberr")" || { DB_ESTADO=error; DB_JSON="{}"; echo "agenda: la consulta de enriquecimiento falló: $(head -c 300 "$TMP/dberr")" >&2; }
printf '%s' "$DB_JSON" >"$TMP/db.json"

python3 -c 'import json,sys; json.dump({"ghl": sys.argv[1], "detalle": sys.argv[2] or None, "db": sys.argv[3]}, open(sys.argv[4],"w"))' \
  "$GHL_ESTADO" "$GHL_DETALLE" "$DB_ESTADO" "$TMP/fuente.json"

python3 "$HERE/lib/agenda_lib.py" --dir "$TMP" --proyecto "$PNAME" --fecha "$FECHA" --vista "$VISTA" --ahora "$AHORA"

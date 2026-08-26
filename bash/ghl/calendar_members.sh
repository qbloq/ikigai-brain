#!/usr/bin/env bash
# calendar_members.sh — [WRITE→GHL] los miembros (team members) de UN calendario
# de GHL: listar, agregar o quitar un usuario. La PRIMERA escritura del Cerebro
# en GHL (2026-08-26, spec docs/superpowers/specs/2026-08-26-marketico-port-ux-llamadas-design.md §4.1).
#
# POR QUÉ ES DELICADO: GHL no tiene "agregar miembro" — `PUT /calendars/{id}`
# REEMPLAZA la lista completa de teamMembers. Por eso este script siempre lee
# la lista actual, la modifica en memoria y manda la lista entera; y por eso
# imprime ANTES/DESPUÉS y exige --dry-run para ver el payload sin aplicar.
#
# Uso:
#   calendar_members.sh --project N --calendar ID                 # listar
#   calendar_members.sh --project N --calendar ID --add USER [--priority P] [--dry-run] [--json]
#   calendar_members.sh --project N --calendar ID --remove USER [--dry-run] [--json]
#   --priority  0.25 | 0.5 | 0.75 | 1 (default 1; el peso del round-robin de GHL —
#               irrelevante cuando el Cerebro asigna con assignedUserId explícito)
#
# Cerca: dominio `ghl` (lectura) hoy; cuando exista la llave `escrituras` en
# docs/roles/acceso.json, este script pasa a require_escritura ghl-agenda.
# Token por stdin (curl --config -), jamás en argv. Estado, no borrado: quitar
# un miembro no borra sus citas.
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "$0")/lib/common.sh"

PROJECT=""; CAL=""; ADD=""; REMOVE=""; PRIO="1"; DRY=0; JSON=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)  PROJECT="$2"; shift 2 ;;
    --calendar) CAL="$2"; shift 2 ;;
    --add)      ADD="$2"; shift 2 ;;
    --remove)   REMOVE="$2"; shift 2 ;;
    --priority) PRIO="$2"; shift 2 ;;
    --dry-run)  DRY=1; shift ;;
    --json)     JSON=1; shift ;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -22; exit 0 ;;
    *) echo "flag desconocido: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$PROJECT" || -z "$CAL" ]] && { echo "faltan --project y --calendar" >&2; exit 2; }
[[ -n "$ADD" && -n "$REMOVE" ]] && { echo "--add y --remove son excluyentes" >&2; exit 2; }

read -r PID _ < <(ghl_resolve_project "$PROJECT")
ghl_load_creds "$PID"

# ghl_put <path> <json>  — PUT con el token por stdin, como ghl_api.
ghl_put() {
  local path="$1" body="$2" tmp code
  tmp="$(mktemp)"
  code="$(printf 'url = "%s"\nrequest = "PUT"\nheader = "Authorization: Bearer %s"\nheader = "Version: %s"\nheader = "Accept: application/json"\nheader = "Content-Type: application/json"\ndata = %s\n' \
      "$GHL_BASE$path" "$GHL_TOKEN" "$GHL_API_VERSION" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$body")" \
    | curl -sS --config - -o "$tmp" -w '%{http_code}')" || { rm -f "$tmp"; return 1; }
  if [[ "$code" != 2* ]]; then
    echo "ghl api HTTP $code — PUT ${path}" >&2; head -c 400 "$tmp" >&2; echo >&2
    [[ "$code" == "401" || "$code" == "403" ]] && echo "(el token no tiene permiso de escritura de calendarios — pedir scope calendars.write)" >&2
    rm -f "$tmp"; return 1
  fi
  cat "$tmp"; rm -f "$tmp"
}

ACTUAL="$(ghl_api "/calendars/$CAL")"
USERS="$(ghl_api "/users/$(ghl_qs locationId "$GHL_LOCATION")")"

python3 - "$ACTUAL" "$USERS" "$ADD" "$REMOVE" "$PRIO" "$DRY" "$JSON" <<'PY' > "${TMPDIR:-/tmp}/cal_members_$$.json"
import json, sys
cal = json.loads(sys.argv[1])["calendar"]; users = {u["id"]: u.get("name") for u in json.loads(sys.argv[2]).get("users", [])}
add, remove, prio, dry, js = sys.argv[3], sys.argv[4], float(sys.argv[5]), sys.argv[6] == "1", sys.argv[7] == "1"
antes = cal.get("teamMembers") or []
def fila(m): return {"userId": m["userId"], "nombre": users.get(m["userId"], "?"), "priority": m.get("priority"), "isPrimary": m.get("isPrimary")}
despues = [dict(m) for m in antes]
if add:
    if add not in users: sys.exit(f"usuario {add} no existe en el location")
    if any(m["userId"] == add for m in despues): sys.exit(f"{users[add]} ya es miembro — nada que hacer")
    despues.append({"userId": add, "priority": prio})
if remove:
    if not any(m["userId"] == remove for m in despues): sys.exit(f"{remove} no es miembro — nada que hacer")
    despues = [m for m in despues if m["userId"] != remove]
out = {"calendario": cal.get("name"), "id": cal.get("id"), "antes": [fila(m) for m in antes], "despues": [fila(m) for m in despues],
       "payload": {"teamMembers": [{k: v for k, v in m.items() if k in ("userId", "priority", "isPrimary", "meetingLocationType", "meetingLocations")} for m in despues]},
       "cambio": bool(add or remove), "dry_run": dry}
json.dump(out, sys.stdout)
PY
PLAN="$(cat "${TMPDIR:-/tmp}/cal_members_$$.json")"; rm -f "${TMPDIR:-/tmp}/cal_members_$$.json"

render() { python3 -c "
import json,sys; d=json.load(sys.stdin)
print('calendario: %s (%s)' % (d['calendario'], d['id']))
for k in ('antes','despues'):
    print('  ' + k + ':')
    for m in d[k]:
        print('    %-32s prio=%s%s' % (m['nombre'], m['priority'], '  (primary)' if m.get('isPrimary') else ''))
"; }

if [[ "$(printf '%s' "$PLAN" | python3 -c 'import json,sys; print(int(json.load(sys.stdin)["cambio"]))')" == "0" ]]; then
  [[ $JSON -eq 1 ]] && printf '%s\n' "$PLAN" || printf '%s' "$PLAN" | render; exit 0
fi
if [[ $DRY -eq 1 ]]; then
  [[ $JSON -eq 1 ]] && printf '%s\n' "$PLAN" || { echo "[dry-run] no se aplica nada"; printf '%s' "$PLAN" | render; }; exit 0
fi

BODY="$(printf '%s' "$PLAN" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["payload"]))')"
ghl_put "/calendars/$CAL" "$BODY" >/dev/null
VERIF="$(ghl_api "/calendars/$CAL")"
RESULT="$(python3 - "$PLAN" "$VERIF" <<'PY'
import json,sys; plan=json.loads(sys.argv[1]); cal=json.loads(sys.argv[2])["calendar"]
ids_ok = sorted(m["userId"] for m in (cal.get("teamMembers") or [])) == sorted(m["userId"] for m in plan["despues"])
plan["aplicado"]=True; plan["verificado"]=ids_ok; plan["dry_run"]=False
json.dump(plan, sys.stdout)
PY
)"
[[ $JSON -eq 1 ]] && printf '%s\n' "$RESULT" || { printf '%s' "$RESULT" | render; echo "aplicado: sí · verificado contra GHL: $(printf '%s' "$RESULT" | python3 -c 'import json,sys; print("sí" if json.load(sys.stdin)["verificado"] else "NO — revisar")')"; }

# Flujo de agendamiento GHL → Cerebro → Meet a demanda — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que cada agendamiento de GHL llegue al Cerebro, y solo las citas del
calendario de VENTA generen Meet + reunión (pidiéndoselos a Marketico a
demanda); las de confirmación se registran sin Meet. Hoy el webhook de
Marketico está en modo `ack` (commit `6cf8bad` de google-meet-express) y
**ninguna cita recibe Meet** — este plan repara eso.

**Architecture:** GHL → webhook `/webhooks/crm` de Marketico (modo `forward`:
ACK 200 + reenvío del payload al Cerebro) → `viz/hooks.js POST /hooks/crm`
(Bearer) → `bash/agenda/entrante.sh` decide por el rol del calendario
(`crm_calendars.rol`, migración 008): venta → `POST /crm/process-booking` de
Marketico (el `processBooking` de siempre, expuesto con auth) → Meet +
`meetings`; entrada → solo registro local. Todo queda en la sqlite
`intercepciones.db` (tabla nueva `entrantes`).

**Tech Stack:** bash + psql + sqlite3 + curl (casa), Node http sin deps
(`viz/hooks.js`), Express ESM (Marketico, repo `/projects/google-meet-express`,
deploy pm2 `meetico` en `/apps/meetico`).

**Spec:** `docs/superpowers/specs/2026-08-26-marketico-port-ux-llamadas-design.md`
(§0 forma A→este puente, §1.1, §1.2, §5). Reordenado por decisión de Santiago:
este flujo va PRIMERO; la asignación y la UX son planes aparte.

## Global Constraints

- Convenciones bash de la casa: scripts read-only salvo los marcados **[WRITE…]**; `--json` y `-h` en todo; `--dry-run` en los WRITE; tokens por stdin (`curl --config -`), jamás en argv ni impresos; comentarios en español contando el porqué.
- Nada se borra: cancelar es estado, no DELETE.
- ⚠️ `meetings.scheduled_start_time` guarda reloj BOGOTÁ etiquetado UTC — leerlo LITERAL (`AT TIME ZONE 'UTC'`). Los `startTime` de GHL traen offset `-05:00`.
- ⚠️ GHL responde 401 `{"message":"Command timed out"}` de forma intermitente — es transitorio, se reintenta; no es el token.
- Ids de calendario: entrada = `bFFbTpMillO1n35FuDmv` («Calendario Premium Mastermind»), venta = `rmiAFkJKOZ2QZ1yEr8dn` («Aplicación a Premium Mastermind»). Proyecto David Guerrero = `9077f0f0-603e-4af5-8033-444778267d9e`.
- El typo de GHL es real y se respeta al leer: `booking.calendar.appoinmentStatus` (sin la segunda «t»).
- Envs ya existentes que se reutilizan: en `/apps/meetico/.env` → `CEREBRO_HOOK_URL` (= `https://app.ikigaigm.parallelo.ai/hooks/crm-resultado`) y `CEREBRO_HOOK_TOKEN`; en el `.env` de hermetico → `HOOKS_TOKEN` (mismo valor que `CEREBRO_HOOK_TOKEN`), `MEETICO_BASE`, `MEETICO_JWT_TOKEN`, `DATABASE_URL`.
- nginx ya enruta `location /hooks/ → 127.0.0.1:4319` (viz-hooks), así que `/hooks/crm` no necesita cambio de nginx.
- Commits: hermetico y google-meet-express son repos separados — commit en cada uno, mensajes en español, trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- No hay framework de tests en estos dominios: cada tarea verifica con corridas reales (dry-run, payloads sintéticos, sqlite) y muestra la salida esperada.

---

### Task 1: Migración 008 — rol de calendario y calendario de la reunión

**Files:**
- Create: `catalog/migrations/008_calendarios_rol.sql`
- Modify: ninguno
- Test: psql (selects de verificación)

**Interfaces:**
- Produces: `crm_calendars.rol` (`'entrada'|'venta'|NULL`) y `meetings.ghl_calendar_id text` — los leen las Tasks 3, 6 y 7.

- [ ] **Step 1: Escribir la migración**

```sql
-- 008_calendarios_rol.sql — dos calendarios oficiales con rol + el calendario
-- de origen de cada reunión.
--
-- Contexto (spec 2026-08-26-marketico-port-ux-llamadas-design.md §1.1): desde
-- el 22-24 ago el calendario oficial de GHL es el de CONFIRMACIÓN (20 min,
-- call confirmers) y la llamada de venta (60 min) vive en «Aplicación a
-- Premium Mastermind». El sistema asumía UN calendario; `rol` declara cuál es
-- cuál y `meetings.ghl_calendar_id` permite tipar cada reunión
-- (confirmación/venta) sin adivinar. Idempotente.

BEGIN;

ALTER TABLE ikigaigm.crm_calendars
  ADD COLUMN IF NOT EXISTS rol text
  CHECK (rol IN ('entrada','venta'));

COMMENT ON COLUMN ikigaigm.crm_calendars.rol IS
  'entrada = confirmación (call confirmers, 20 min) · venta = llamada de venta con closer (60 min) · NULL = histórico/sin clasificar';

-- El oficial histórico pasa a ser el de entrada.
UPDATE ikigaigm.crm_calendars
SET rol = 'entrada'
WHERE ghl_calendar_id = 'bFFbTpMillO1n35FuDmv' AND rol IS DISTINCT FROM 'entrada';

-- «Aplicación a Premium Mastermind» entra como calendario de venta.
INSERT INTO ikigaigm.crm_calendars (project_id, ghl_calendar_id, ghl_calendar_name, is_active, rol)
SELECT '9077f0f0-603e-4af5-8033-444778267d9e', 'rmiAFkJKOZ2QZ1yEr8dn', 'Aplicación a Premium Mastermind', true, 'venta'
WHERE NOT EXISTS (
  SELECT 1 FROM ikigaigm.crm_calendars WHERE ghl_calendar_id = 'rmiAFkJKOZ2QZ1yEr8dn'
);
UPDATE ikigaigm.crm_calendars
SET rol = 'venta', is_active = true
WHERE ghl_calendar_id = 'rmiAFkJKOZ2QZ1yEr8dn' AND (rol IS DISTINCT FROM 'venta' OR NOT is_active);

ALTER TABLE ikigaigm.meetings
  ADD COLUMN IF NOT EXISTS ghl_calendar_id text;

COMMENT ON COLUMN ikigaigm.meetings.ghl_calendar_id IS
  'Calendario GHL del appointment que originó la reunión (migración 008). Lo escribe el Cerebro (bash/agenda/entrante.sh al crear; bash/agenda/tipar_meetings.sh backfill). El rol se deriva por join a crm_calendars.';

COMMIT;
```

- [ ] **Step 2: Aplicar**

Run (desde la raíz de hermetico):
```bash
source bash/lib/common.sh && psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f catalog/migrations/008_calendarios_rol.sql
```
Expected: `BEGIN … COMMIT` sin errores.

- [ ] **Step 3: Verificar**

```bash
source bash/lib/common.sh && psql_ro -c "SELECT ghl_calendar_id, ghl_calendar_name, is_active, rol FROM ikigaigm.crm_calendars ORDER BY rol" \
  && psql_ro -c "SELECT count(*) FROM information_schema.columns WHERE table_schema='ikigaigm' AND table_name='meetings' AND column_name='ghl_calendar_id'"
```
Expected: fila `bFFb… | entrada` y `rmiA… | venta | t`; count = 1. (La fila de Andrea `9AHYELerN2hwQZN22CI2` queda con rol NULL — correcto.)

- [ ] **Step 4: Re-aplicar para probar idempotencia**

Run: el mismo psql del Step 2. Expected: sin errores, mismos datos.

- [ ] **Step 5: Commit**

```bash
git add catalog/migrations/008_calendarios_rol.sql
git commit -m "migración 008: dos calendarios oficiales con rol (entrada/venta) + meetings.ghl_calendar_id

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Tabla `entrantes` + lector `bash/agenda/entrantes.sh`

**Files:**
- Modify: `bash/intercepciones/schema.sql` (agregar tabla al final)
- Create: `bash/agenda/entrantes.sh`
- Test: sqlite local con fila sembrada

**Interfaces:**
- Produces: tabla `entrantes` en `intercepciones.db` — la escribe la Task 3 y el receptor de la Task 5; columnas exactas abajo. `entrantes.sh [--desde D] [--solo-errores] [--limit N] [--json]` — lector local-first + ssh (patrón `bash/intercepciones/log.sh`).

- [ ] **Step 1: Agregar la tabla al schema (idempotente, al final de `bash/intercepciones/schema.sql`)**

```sql
-- Los agendamientos ENTRANTES de GHL una vez el webhook de Marketico quedó en
-- modo forward (2026-08-26): el Cerebro es quien decide qué se hace con cada
-- uno. accion: registrada (entrada/confirmación, sin Meet) · meet_solicitado
-- (venta → POST /crm/process-booking de Marketico) · ignorada (sin
-- appointment_id) · desconocido (calendario sin rol — NO se procesa) · error.
CREATE TABLE IF NOT EXISTS entrantes (
  id INTEGER PRIMARY KEY,
  recibido_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  appointment_id TEXT, calendar_id TEXT, rol TEXT, estado_cita TEXT,
  contacto TEXT, email TEXT, start_time TEXT,
  accion TEXT NOT NULL CHECK (accion IN ('registrada','meet_solicitado','ignorada','desconocido','error')),
  resultado TEXT, error TEXT, duracion_ms INTEGER,
  payload TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_entrantes_recibido ON entrantes(recibido_at);
CREATE INDEX IF NOT EXISTS idx_entrantes_appt ON entrantes(appointment_id);
```

- [ ] **Step 2: Crear el lector `bash/agenda/entrantes.sh`**

Copiar el patrón local-first + ssh de `bash/intercepciones/log.sh` (mismo
remoto `root@api:/apps/hermetico`, misma resolución de db). Contenido:

```bash
#!/usr/bin/env bash
# entrantes.sh — los agendamientos de GHL que recibió el Cerebro (tabla
# `entrantes` de intercepciones.db) una vez Marketico pasó a modo forward.
# Read-only, local-first: usa la sqlite local si existe; si no, la del
# servidor api por ssh. Dominio nuevo bash/agenda/ (flujo de agendamiento,
# spec 2026-08-26-marketico-port-ux-llamadas-design.md).
#
# uso: entrantes.sh [--desde YYYY-MM-DD] [--solo-errores] [--limit N] [--json]
set -euo pipefail
cd "$(dirname "$0")/../.."

DESDE=""; SOLO_ERR=0; LIMIT=30; JSON=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --desde) DESDE="$2"; shift 2 ;;
    --solo-errores) SOLO_ERR=1; shift ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -8; exit 0 ;;
    *) echo "flag desconocido: $1" >&2; exit 2 ;;
  esac
done

DB="${INTERCEPCIONES_DB:-data/sqlite/intercepciones.db}"
W="1=1"
[[ -n "$DESDE" ]] && W="$W AND recibido_at >= '$DESDE'"
[[ $SOLO_ERR -eq 1 ]] && W="$W AND accion='error'"
SQL="SELECT id, recibido_at, appointment_id, calendar_id, rol, estado_cita,
  contacto, start_time, accion, resultado, error, duracion_ms
FROM entrantes WHERE $W ORDER BY id DESC LIMIT $LIMIT;"

correr() { sqlite3 -json -readonly "$1" "$SQL" 2>/dev/null || echo "[]"; }
if [[ -f "$DB" ]]; then OUT="$(correr "$DB")"; else
  OUT="$(printf '%s' "$SQL" | ssh root@api "sqlite3 -json -readonly /apps/hermetico/$DB '.timeout 3000' 2>/dev/null || true" 2>/dev/null)"
  [[ -z "$OUT" ]] && OUT="$(ssh root@api "sqlite3 -json -readonly /apps/hermetico/$DB \"$(printf '%s' "$SQL" | tr '\n' ' ')\"" 2>/dev/null || echo '[]')"
fi
[[ -z "$OUT" ]] && OUT="[]"
if [[ $JSON -eq 1 ]]; then printf '%s\n' "$OUT"; else
  printf '%s' "$OUT" | python3 -c '
import json,sys
rows=json.load(sys.stdin)
if not rows: print("sin entrantes"); raise SystemExit
for r in rows:
    print(f"{r[\"id\"]:>4} {r[\"recibido_at\"][:19]} {r[\"accion\"]:<15} {r.get(\"rol\") or \"-\":<8} {r.get(\"contacto\") or \"\"} {(r.get(\"error\") or r.get(\"resultado\") or \"\")[:60]}")'
fi
```

⚠️ Nota al implementar: en `log.sh` ya está resuelto cómo pasar el SQL al
sqlite remoto por ssh **por stdin, nunca en el argv remoto** — copiar ESA
mecánica exacta de `log.sh` en vez del doble intento de arriba si difiere.

- [ ] **Step 3: Probar con fila sembrada local**

```bash
chmod +x bash/agenda/entrantes.sh
sqlite3 data/sqlite/intercepciones.db < bash/intercepciones/schema.sql
sqlite3 data/sqlite/intercepciones.db "INSERT INTO entrantes (appointment_id, calendar_id, rol, estado_cita, contacto, accion, payload) VALUES ('TEST-1','bFFbTpMillO1n35FuDmv','entrada','confirmed','Prueba Semilla','registrada','{}');"
bash/agenda/entrantes.sh && bash/agenda/entrantes.sh --json | python3 -m json.tool >/dev/null && echo JSON_OK
sqlite3 data/sqlite/intercepciones.db "DELETE FROM entrantes WHERE appointment_id='TEST-1';"
```
Expected: la fila TEST-1 renderizada, luego `JSON_OK`. (La sqlite local es una
copia de juguete — la de verdad vive en el servidor; el DELETE limpia solo la
semilla local.)

- [ ] **Step 4: Commit**

```bash
git add bash/intercepciones/schema.sql bash/agenda/entrantes.sh
git commit -m "agenda: tabla entrantes (agendamientos GHL recibidos por el Cerebro) + lector entrantes.sh

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: `bash/agenda/entrante.sh` — el procesador de UN agendamiento

**Files:**
- Create: `bash/agenda/entrante.sh`
- Test: payloads sintéticos con `--dry-run` y sin él (rol entrada)

**Interfaces:**
- Consumes: `crm_calendars.rol` (Task 1), tabla `entrantes` (Task 2), envs `DATABASE_URL`, `MEETICO_BASE`, `MEETICO_JWT_TOKEN`, `INTERCEPCIONES_DB`.
- Produces: `entrante.sh [--dry-run] [--json] < payload.json` — exit 0 siempre que logre registrar (el error queda como fila `accion='error'`); lo invoca el receptor de la Task 5. Emite una línea JSON `{accion, appointment_id, rol, resultado|error}`.

- [ ] **Step 1: Escribir el script**

```bash
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
  local accion="$1" resultado="${2:-}" err="${3:-}" dur=$(( $(date +%s%3N) - T0 ))
  local db="${INTERCEPCIONES_DB:-data/sqlite/intercepciones.db}"
  mkdir -p "$(dirname "$db")"
  sqlite3 "$db" < bash/intercepciones/schema.sql
  python3 - "$db" <<PYEOF
import sqlite3, sys, json
con = sqlite3.connect(sys.argv[1], timeout=5)
def n(v): return None if v in ("", "$SIN") else v
con.execute("INSERT INTO entrantes (appointment_id, calendar_id, rol, estado_cita, contacto, email, start_time, accion, resultado, error, duracion_ms, payload) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
  (n("""$APPT"""), n("""$CAL"""), n("""${ROL:-}"""), n("""$ESTADO"""), n("""$NOMBRE"""), n("""$EMAIL"""), n("""$INICIO"""),
   """$accion""", n('''$resultado'''), n('''$err'''), $dur, ${RAW@Q}.encode().decode() if False else None))
con.commit()
PYEOF
}
```

⚠️ **Al implementar, NO usar el heredoc-con-interpolación de arriba tal cual**
(payloads con comillas lo rompen): pasar TODOS los valores por variables de
entorno al python (`APPT="$APPT" RAW="$RAW" … python3 - <<'PYEOF'` y dentro
`os.environ`) — cero interpolación de shell dentro del python. El esqueleto
correcto:

```bash
registrar() { # accion resultado error
  local dur=$(( $(date +%s%3N) - T0 ))
  local db="${INTERCEPCIONES_DB:-data/sqlite/intercepciones.db}"
  mkdir -p "$(dirname "$db")"; sqlite3 "$db" < bash/intercepciones/schema.sql
  ACCION="$1" RES="${2:-}" ERR="${3:-}" DUR="$dur" DB="$db" \
  APPT="$APPT" CAL="$CAL" ROL="${ROL:-}" ESTADO="$ESTADO" NOMBRE="$NOMBRE" \
  EMAIL="$EMAIL" INICIO="$INICIO" RAW="$RAW" SIN="$SIN" python3 - <<'PYEOF'
import os, sqlite3
e = os.environ; n = lambda k: (None if e.get(k, "") in ("", e["SIN"]) else e[k])
con = sqlite3.connect(e["DB"], timeout=5)
con.execute("INSERT INTO entrantes (appointment_id, calendar_id, rol, estado_cita, contacto, email, start_time, accion, resultado, error, duracion_ms, payload) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
  (n("APPT"), n("CAL"), n("ROL"), n("ESTADO"), n("NOMBRE"), n("EMAIL"), n("INICIO"),
   e["ACCION"], n("RES"), n("ERR"), int(e["DUR"]), e["RAW"]))
con.commit()
PYEOF
}

salida() { # accion detalle
  local accion="$1" detalle="${2:-}"
  python3 - "$accion" "$detalle" <<'PYEOF'
import json, sys, os
print(json.dumps({"accion": sys.argv[1], "appointment_id": os.environ.get("APPT"),
  "rol": os.environ.get("ROL") or None, "detalle": sys.argv[2] or None}, ensure_ascii=False))
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
  registrar error "" "postgres no responde — no se pudo resolver el rol"; salida error "postgres no responde"; exit 1
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
      [[ -n "$MID" ]] && psql_rw -c "UPDATE meetings SET ghl_calendar_id='${CAL//\'/\'\'}' WHERE id='${MID//\'/\'\'}' AND ghl_calendar_id IS NULL" >/dev/null 2>&1 || true
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
```

Notas de implementación obligatorias: (a) `psql_rw` — verificar en
`bash/lib/common.sh` el nombre exacto del helper de escritura; si no existe
uno, usar `psql "$DATABASE_URL" -v ON_ERROR_STOP=1` directo para el UPDATE,
comentando por qué; (b) el `eval` del parseo usa `shlex.quote` — mantenerlo;
(c) `date +%s%3N` para milisegundos.

- [ ] **Step 2: Probar los cuatro caminos sin tocar Marketico**

```bash
chmod +x bash/agenda/entrante.sh
# 1. entrada (real, escribe sqlite local):
echo '{"calendar":{"appointmentId":"TEST-e1","id":"bFFbTpMillO1n35FuDmv","appoinmentStatus":"confirmed","startTime":"2026-08-27T10:00:00-05:00"},"full_name":"Prueba Entrada","email":"t@t.co"}' | bash/agenda/entrante.sh
# 2. venta (dry-run — NO postea):
echo '{"calendar":{"appointmentId":"TEST-v1","id":"rmiAFkJKOZ2QZ1yEr8dn","appoinmentStatus":"confirmed"},"full_name":"Prueba Venta"}' | bash/agenda/entrante.sh --dry-run
# 3. sin appointment:
echo '{"full_name":"Sin Cita"}' | bash/agenda/entrante.sh
# 4. calendario desconocido:
echo '{"calendar":{"appointmentId":"TEST-d1","id":"SvQrgCt08ZqAmImfTWyb","appoinmentStatus":"confirmed"},"full_name":"Prueba Personal"}' | bash/agenda/entrante.sh
bash/agenda/entrantes.sh --limit 5
```
Expected: JSON de salida `registrada` / `meet_solicitado (dry-run)` /
`ignorada` / `desconocido`; el lector muestra las filas TEST-e1 (registrada),
sin-cita (ignorada) y TEST-d1 (desconocido). Limpiar:
`sqlite3 data/sqlite/intercepciones.db "DELETE FROM entrantes WHERE appointment_id LIKE 'TEST-%' OR contacto='Sin Cita';"`

- [ ] **Step 3: Commit**

```bash
git add bash/agenda/entrante.sh
git commit -m "agenda: entrante.sh — el Cerebro decide cada agendamiento de GHL por rol de calendario (venta→Meet a demanda, entrada→registro sin Meet)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Marketico — `POST /crm/process-booking` + modo `forward` del webhook

**Files (repo `/projects/google-meet-express`):**
- Create: `src/routes/crm.js`
- Modify: `src/server.js` (montar router), `src/routes/webhooks.js` (modo forward)
- Test: `node --check` + deploy en Task 6

**Interfaces:**
- Consumes: `processBooking(booking, { tokens })` de `src/services/crmService.js`; `getSettings`, `getIdentityByEmail` de `src/services/agenticoService.js`; `requireAuth` de `src/middleware/auth.js`; envs `CEREBRO_HOOK_URL`/`CEREBRO_HOOK_TOKEN` (ya en `/apps/meetico/.env`).
- Produces: `POST /crm/process-booking` (Bearer JWT) → `{procesado, meeting_id, event_id, space, cancelado}` o `{procesado, detalle}` — lo consume `entrante.sh` (Task 3). Webhook `/webhooks/crm` en modo `forward` (default): ACK 200 + reenvío del payload crudo a `/hooks/crm` del Cerebro.

- [ ] **Step 1: Crear `src/routes/crm.js`**

```javascript
import express from 'express';
import { requireAuth } from '../middleware/auth.js';
import { processBooking } from '../services/crmService.js';
import { getSettings, getIdentityByEmail } from '../services/agenticoService.js';

const router = express.Router();

// POST /crm/process-booking — el processBooking de siempre, A DEMANDA del
// Cerebro (loop «Marketico Port», 2026-08-26): desde que el webhook /crm dejó
// de procesar, es el Cerebro quien decide qué agendamientos generan Meet
// (solo el calendario de venta) y lo pide aquí con el payload crudo de GHL.
// Auth: el mismo requireAuth (JWT) que /drive — el Cerebro llama con
// MEETICO_JWT_TOKEN. Síncrono a propósito: el Cerebro necesita el meeting_id
// para sellar el calendario de origen.
router.post('/process-booking', requireAuth, async (req, res) => {
  try {
    const booking = req.body;
    const { google_main_identity } = getSettings();
    const tokens = await getIdentityByEmail(google_main_identity);
    if (!tokens) {
      return res.status(500).json({ error: 'Could not find Google service account credentials.' });
    }
    const r = await processBooking(booking, { tokens });
    if (r && typeof r === 'object') {
      return res.json({
        procesado: true,
        meeting_id: r.meeting?.id ?? null,
        event_id: r.event?.id ?? null,
        space: r.space?.google_space_id ?? null,
        cancelado: r.cancelled === true,
      });
    }
    // true = ya existía y se verificó/actualizó; undefined = sin appointmentId.
    return res.json({ procesado: r === true, detalle: r === true ? 'actualizado_o_vigente' : 'sin_appointment_id' });
  } catch (err) {
    console.error('process-booking error:', err.message);
    return res.status(500).json({ error: err.message });
  }
});

export default router;
```

- [ ] **Step 2: Montarlo en `src/server.js`**

Junto a los imports de rutas (línea ~18): `import crmRouter from './routes/crm.js';`
Junto a los `app.use` de rutas (después de `app.use('/drive', driveRouter);`):
`app.use('/crm', crmRouter);`

- [ ] **Step 3: Modo `forward` en `src/routes/webhooks.js`**

Reemplazar el bloque de modo ack (creado en `6cf8bad`) para que el default sea
reenviar. Cambiar:

```javascript
const CRM_WEBHOOK_MODE = (process.env.CRM_WEBHOOK_MODE || 'ack').toLowerCase();
```
por:
```javascript
// 'forward' (default desde 2026-08-26): ACK 200 + reenvío del payload crudo al
// Cerebro, que decide (venta → vuelve por POST /crm/process-booking; entrada →
// solo registro). 'ack' = acusar sin reenviar. 'process' = comportamiento
// anterior (procesar aquí). El destino se deriva de CEREBRO_HOOK_URL (el del
// auto-reporte) cambiando el path a /hooks/crm; CEREBRO_CRM_URL lo pisa.
const CRM_WEBHOOK_MODE = (process.env.CRM_WEBHOOK_MODE || 'forward').toLowerCase();
const CEREBRO_CRM_URL = process.env.CEREBRO_CRM_URL
  || (process.env.CEREBRO_HOOK_URL ? new URL('/hooks/crm', process.env.CEREBRO_HOOK_URL).href : null);
```

Y dentro del branch `if (CRM_WEBHOOK_MODE !== 'process')`, después del
`console.log` y antes del `reportarBooking`, agregar:

```javascript
    if (CRM_WEBHOOK_MODE === 'forward' && CEREBRO_CRM_URL && process.env.CEREBRO_HOOK_TOKEN) {
      axios.post(CEREBRO_CRM_URL, booking, {
        headers: { Authorization: `Bearer ${process.env.CEREBRO_HOOK_TOKEN}` },
        timeout: 5000,
      }).catch(err => console.warn('[cerebro] reenvío /hooks/crm falló (se sigue):', err.message));
    }
```

(`axios` ya es dependencia — importarlo arriba: `import axios from 'axios';`.)
Cambiar también el `detalle` del reporte en ese branch de `'inhabilitado'` a
`CRM_WEBHOOK_MODE === 'forward' ? 'reenviado' : 'inhabilitado'`.

- [ ] **Step 4: Verificar sintaxis y commitear**

```bash
cd /projects/google-meet-express
node --check src/routes/crm.js && node --check src/routes/webhooks.js && node --check src/server.js
git add src/routes/crm.js src/routes/webhooks.js src/server.js
git commit -m "crm: POST /crm/process-booking (processBooking a demanda del Cerebro) + webhook /crm en modo forward

El Cerebro decide qué agendamientos generan Meet (solo calendario de venta);
el webhook acusa 200 y reenvía el payload crudo a /hooks/crm con el token del
auto-reporte. CRM_WEBHOOK_MODE=process restaura el comportamiento viejo.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push origin main
```
Expected: 3 × ok de node --check; push acepta (el remoto redirige a qbloq/meetico — normal).

---

### Task 5: Receptor `POST /hooks/crm` en `viz/hooks.js`

**Files:**
- Modify: `viz/hooks.js` (nueva ruta después del bloque `/hooks/crm-resultado`, líneas ~91-106; agregar `spawn` al require de `child_process` en línea ~16)
- Test: instancia local en puerto alterno + curl

**Interfaces:**
- Consumes: `bash/agenda/entrante.sh` (Task 3), `HOOKS_TOKEN` (mismo Bearer que crm-resultado), `tokenValido()`/`readBody()` ya existentes.
- Produces: `POST /hooks/crm` → 202 y procesa async — lo llama el forward de Marketico (Task 4). nginx ya enruta `/hooks/` completo al puerto 4319.

- [ ] **Step 1: Agregar la ruta**

En el require de línea 16 sumar `spawn`:
`const { execFileSync, spawn } = require("node:child_process");`

Después del bloque de `/hooks/crm-resultado` (tras su `return fin(204);}`):

```javascript
    // El agendamiento ENTRANTE de GHL (reenviado por Marketico en modo
    // forward, o directo cuando el workflow apunte acá). Validar y delegar:
    // la decisión vive en bash/agenda/entrante.sh, que registra TODO en la
    // tabla `entrantes` — incluido su propio error. 202 al instante: el que
    // reenvía no debe esperar a Marketico.
    if (url.pathname === "/hooks/crm" && req.method === "POST") {
      if (!tokenValido(req.headers.authorization)) return fin(401);
      const raw = await readBody(req);
      if (raw == null) return fin(400, "cuerpo demasiado grande");
      try { JSON.parse(raw); } catch { return fin(400, "JSON inválido"); }
      try {
        const p = spawn("bash", [path.join(REPO_ROOT, "bash", "agenda", "entrante.sh")],
          { cwd: REPO_ROOT, detached: true, stdio: ["pipe", "ignore", "ignore"] });
        p.on("error", (e) => console.error(`[hooks] entrante.sh no arrancó: ${e.message}; payload: ${raw.slice(0, 2000)}`));
        p.stdin.write(raw); p.stdin.end(); p.unref();
      } catch (e) {
        console.error(`[hooks] entrante spawn falló (${e.message}); payload: ${raw.slice(0, 2000)}`);
        return fin(500);
      }
      return fin(202, "aceptado");
    }
```

- [ ] **Step 2: Probar local**

```bash
cd /projects/hermetico
node --check viz/hooks.js
HOOKS_TOKEN=probelocal PORT=4399 node viz/hooks.js & HPID=$!
until curl -sf http://127.0.0.1:4399/health >/dev/null; do :; done
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:4399/hooks/crm -H 'Authorization: Bearer probelocal' -H 'Content-Type: application/json' -d '{"calendar":{"appointmentId":"TEST-h1","id":"bFFbTpMillO1n35FuDmv","appoinmentStatus":"confirmed"},"full_name":"Prueba Hook"}'
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:4399/hooks/crm -d '{}'   # sin Bearer
kill $HPID
bash/agenda/entrantes.sh --limit 3
sqlite3 data/sqlite/intercepciones.db "DELETE FROM entrantes WHERE appointment_id='TEST-h1';"
```
Expected: `202`, luego `401`; el lector muestra TEST-h1 `registrada` (rol
entrada). 

- [ ] **Step 3: Commit**

```bash
git add viz/hooks.js
git commit -m "hooks: POST /hooks/crm — el agendamiento entrante de GHL entra al Cerebro y lo decide bash/agenda/entrante.sh

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Deploy de ambos lados + e2e sintético

**Files:** ninguno nuevo (deploy)

**Interfaces:**
- Consumes: `bash/publicar/desplegar.sh` (hermetico → servidor api, reinicia viz-publish y viz-hooks); deploy de meetico = `ssh root@api "cd /apps/meetico && git pull --ff-only && pm2 restart meetico --update-env"`.

- [ ] **Step 1: Desplegar hermetico** — `bash/publicar/desplegar.sh`. Expected: sha remoto = local, «viz-publish vivo».

- [ ] **Step 2: Desplegar meetico** — el ssh de arriba; verificar `git rev-parse --short HEAD` remoto = el commit de la Task 4 y `pm2 jlist` con meetico `online`.

- [ ] **Step 3: E2E sintético por el camino completo** (webhook de Marketico → forward → hooks → entrante.sh):

```bash
ssh root@api "curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:5000/webhooks/crm -H 'Content-Type: application/json' -d '{\"calendar\":{\"appointmentId\":\"TEST-e2e-entrada\",\"id\":\"bFFbTpMillO1n35FuDmv\",\"appoinmentStatus\":\"confirmed\"},\"full_name\":\"prueba e2e entrada\"}'"
sleep 0; bash/agenda/entrantes.sh --limit 3   # lector local-first: sin db local lee la del servidor
bash/intercepciones/log.sh --desde "$(date +%F)" --json | python3 -c "import json,sys; [print(r['id'], (r.get('resultado') or '')[:80]) for r in json.load(sys.stdin)[:2]]"
```
Expected: 200 del webhook; en `entrantes` (del SERVIDOR) la fila
`TEST-e2e-entrada` con `accion=registrada`, `rol=entrada`; en el log del
interceptor el auto-reporte con `detalle:'reenviado'`.

- [ ] **Step 4: Probar la autenticación del endpoint a demanda**

```bash
ssh root@api "curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:5000/crm/process-booking -H 'Content-Type: application/json' -d '{}'"
```
Expected: `401` (sin Bearer). Con Bearer se prueba en la Task 8 con cita real
— un booking sintético de venta haría que Marketico busque el appointment en
GHL y falle sucio; no vale la pena.

- [ ] **Step 5: Limpiar las filas TEST del servidor**

```bash
ssh root@api "sqlite3 /apps/hermetico/data/sqlite/intercepciones.db \"DELETE FROM entrantes WHERE appointment_id LIKE 'TEST-%'\""
```

---

### Task 7: La reconciliación y las agendas respetan el rol

**Files:**
- Modify: `bash/intercepciones/reconciliar_agenda.sh:232-236` (filtro de calendarios)
- Modify: `bash/closers/agenda.sh` (excluir confirmaciones)
- Create: `bash/agenda/tipar_meetings.sh` (backfill de `ghl_calendar_id`)
- Test: corrida manual de cada uno

**Interfaces:**
- Consumes: migración 008 (Task 1); `bash/ghl/lib/common.sh` (`ghl_api`).
- Produces: reconciliación solo sobre calendarios `rol='venta'` o `NULL`; agenda de closers sin confirmaciones; meetings recientes con `ghl_calendar_id` sellado.

- [ ] **Step 1: Reconciliación — el universo excluye `entrada`**

En `reconciliar_agenda.sh` (query `CALS`, línea ~232) cambiar el WHERE:

```sql
  WHERE cc.is_active AND (cc.rol IS NULL OR cc.rol = 'venta') ORDER BY p.name;
```
más un comentario encima: `-- Los calendarios de rol 'entrada' (confirmación) se excluyen: sus citas por diseño NO tienen fila en meetings, y compararlas gritaría falta_en_db eterno (migración 008).`

- [ ] **Step 2: Backfill `bash/agenda/tipar_meetings.sh`**

```bash
#!/usr/bin/env bash
# tipar_meetings.sh — [WRITE pg] sella meetings.ghl_calendar_id leyendo de GHL
# el calendario de cada appointment (GET /calendars/events/appointments/{id}).
# Backfill de la migración 008 para reuniones ya existentes; hacia adelante lo
# sella bash/agenda/entrante.sh al crear. Solo toca filas con la columna NULL
# y appointment conocido; por defecto las de los últimos 14 días + futuras.
# uso: tipar_meetings.sh [--desde YYYY-MM-DD] [--dry-run] [--json]
set -euo pipefail
cd "$(dirname "$0")/../.."
# shellcheck disable=SC1091
source bash/ghl/lib/common.sh   # trae también common.sh (psql)

DESDE="$(date -d '14 days ago' +%F 2>/dev/null || date -v-14d +%F)"; DRY=0; JSON=0
while [[ $# -gt 0 ]]; do case "$1" in
  --desde) DESDE="$2"; shift 2 ;; --dry-run) DRY=1; shift ;; --json) JSON=1; shift ;;
  -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -8; exit 0 ;;
  *) echo "flag desconocido: $1" >&2; exit 2 ;; esac; done

read -r PID _ < <(ghl_resolve_project "David Guerrero"); ghl_load_creds "$PID"

FILAS="$(psql_ro -t -A -F$'\t' -c "
  SELECT left(id::text,36), event->'booking'->>'appointment_id'
  FROM meetings
  WHERE meeting_type='call' AND ghl_calendar_id IS NULL
    AND event->'booking'->>'appointment_id' IS NOT NULL
    AND scheduled_start_time >= '$DESDE'::timestamptz")"
N=0; OK=0; SINCAL=0
while IFS=$'\t' read -r MID APPT; do
  [[ -z "$MID" ]] && continue; N=$((N+1))
  CAL=""
  for intento in 1 2 3; do
    CAL="$(ghl_api "/calendars/events/appointments/$APPT" 2>/dev/null \
      | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["appointment"].get("calendarId") or "")
except Exception: print("")')" && [[ -n "$CAL" ]] && break
  done
  if [[ -z "$CAL" ]]; then SINCAL=$((SINCAL+1)); echo "  $MID $APPT: sin calendario en GHL (borrado o error)" >&2; continue; fi
  if (( DRY )); then echo "  [dry-run] $MID ← $CAL"; else
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -c "UPDATE ikigaigm.meetings SET ghl_calendar_id='$CAL' WHERE id='$MID' AND ghl_calendar_id IS NULL"
  fi; OK=$((OK+1))
done <<< "$FILAS"
echo "{\"revisadas\": $N, \"selladas\": $OK, \"sin_calendario\": $SINCAL, \"dry_run\": $DRY}"
```

- [ ] **Step 3: Correr el backfill** — `bash/agenda/tipar_meetings.sh --dry-run`
(revisar la lista) y luego sin `--dry-run`. Verificar:

```bash
source bash/lib/common.sh && psql_ro -c "SELECT cc.rol, count(*) FROM ikigaigm.meetings m LEFT JOIN ikigaigm.crm_calendars cc ON cc.ghl_calendar_id=m.ghl_calendar_id WHERE m.scheduled_start_time >= now()::date - 14 AND m.meeting_type='call' GROUP BY 1"
```
Expected: filas con rol `entrada` (las confirmaciones del 24-26 ago), `venta`
(las de «Aplicación») y NULL (viejas o sin appointment).

- [ ] **Step 4: Agenda de closers sin confirmaciones**

En `bash/closers/agenda.sh` (query principal, línea ~62 `FROM meetings m`),
agregar al `WHERE $WHERE`:

```sql
AND NOT EXISTS (SELECT 1 FROM crm_calendars cc
                WHERE cc.ghl_calendar_id = m.ghl_calendar_id AND cc.rol = 'entrada')
```
con comentario: `-- las confirmaciones (rol entrada, migración 008) no son llamadas del closer`.
Revisar con `grep -ln "FROM meetings" bash/closers/*.sh bash/calls/*.sh` si
algún otro script de agenda u operación **futura** (no los históricos de
análisis) lista llamadas del día — aplicar el mismo `NOT EXISTS` solo donde la
salida alimente agendas/escenarios de closers (hoy: `agenda.sh`; los
escenarios la reutilizan).

- [ ] **Step 5: Verificar y commitear**

```bash
bash/closers/agenda.sh --json | python3 -m json.tool >/dev/null && echo AGENDA_OK
bash/intercepciones/reconciliar_agenda.sh --dry-run --json
git add bash/intercepciones/reconciliar_agenda.sh bash/closers/agenda.sh bash/agenda/tipar_meetings.sh
git commit -m "agenda: reconciliación y agenda de closers respetan el rol de calendario (entrada/venta) + backfill tipar_meetings.sh

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
bash/publicar/desplegar.sh
```
Expected: AGENDA_OK; el dry-run de reconciliación lista SOLO venta (+NULL de
otros proyectos); deploy ok (el cron del servidor usa el código nuevo).

---

### Task 8: Verificación con cita real + cierre

**Files:**
- Modify: `CLAUDE.md` de hermetico (sección nueva del dominio agenda — ver Step 4)

- [ ] **Step 1: Cita real de prueba en «Aplicación».** Crearla en GHL (Santiago
o un setter desde la UI de GHL: contacto de prueba interno, SIN email de lead
real para no notificar a nadie, mañana a una hora libre de Lucho). Al crearla,
el workflow de GHL dispara → Marketico reenvía → verificar la cadena:

```bash
bash/agenda/entrantes.sh --limit 3
# esperar la fila accion=meet_solicitado, luego:
source bash/lib/common.sh && psql_ro -c "SELECT left(id::text,8), name, meet_url IS NOT NULL AS con_meet, ghl_calendar_id FROM ikigaigm.meetings ORDER BY created_at DESC LIMIT 2"
```
Expected: `meet_solicitado` con `meeting_id` en resultado; la reunión nueva con
`con_meet = t` y `ghl_calendar_id = rmiAFkJKOZ2QZ1yEr8dn`.
⚠️ Si el workflow de GHL **no** dispara para «Aplicación» (nunca lo hemos visto
disparar por una cita creada a mano ahí — las de Cristian del 24-25 sí
llegaron), diagnosticar en el log de intercepciones (`detalle:'reenviado'`
presente = llegó a Marketico) antes de tocar nada.

- [ ] **Step 2: Cancelar la cita de prueba** desde GHL. Verificar que el
cancel viaja: fila nueva en `entrantes` (estado `cancelled`,
`meet_solicitado`) y la reunión queda `cancelled` en la DB (lo hace
processBooking).

- [ ] **Step 3: Reconciliación de la hora siguiente en cero.**
`bash/intercepciones/drift.sh --json` tras el próximo minuto 17. Expected: sin
drift nuevo (la cita test cancelada no cuenta; las confirmaciones ya no se
comparan).

- [ ] **Step 4: Documentar el dominio.** En el CLAUDE.md de hermetico, sección
nueva «Agenda domain — flujo de agendamiento ([bash/agenda/](bash/agenda/))»
después del dominio Setters: qué es (GHL → hooks → entrante.sh → Marketico a
demanda), la tabla de los 3 scripts (`entrante.sh` [WRITE], `entrantes.sh`,
`tipar_meetings.sh` [WRITE pg]), la semántica de `accion`, y la regla «solo el
calendario de rol venta genera Meet». Nota en la sección Intercepciones: el
webhook de Marketico quedó en modo `forward` (2026-08-26) y `detalle:
'reenviado'` es lo normal. ⚠️ El CLAUDE.md tiene ediciones sin commitear de
Santiago — editar el archivo está bien, pero **no** hacer `git add CLAUDE.md`;
avisarle para que lo commitee con su flujo.

- [ ] **Step 5: Commit final de docs** (solo lo nuestro) y actualizar la
memoria `marketico-port.md` (el flujo quedó vivo; el webhook en `forward`).

---

## Self-review (hecho al escribir)

- **Cobertura del spec:** §1.1 → Tasks 1 y 7; §1.2 → Tasks 4-6 (el filtro del
  workflow de GHL ya no se necesita: filtra el Cerebro); §5.1 (Marketico no
  crea Meet → «sin Meet aún») queda observable en `entrantes` accion=error —
  la señal en la página del closer es del Plan 3; §5.2 puntos 1 y 5 → Task 8.
  La base `asignacion`, la cerca `escrituras`, los comandos y las páginas son
  Planes 2 y 3 — fuera de este alcance a propósito.
- **Placeholders:** los dos bloques marcados «al implementar» en Task 3
  declaran exactamente qué sustituir y con qué mecánica — son advertencias de
  implementación con el esqueleto correcto al lado, no huecos.
- **Consistencia de tipos:** `entrante.sh` emite/espera `meeting_id` — igual
  que la respuesta de `crm.js` (Task 4). `accion` usa el mismo CHECK en schema
  (Task 2) y en el case (Task 3). `rol` usa `entrada|venta` en 008, CALS y
  NOT EXISTS.

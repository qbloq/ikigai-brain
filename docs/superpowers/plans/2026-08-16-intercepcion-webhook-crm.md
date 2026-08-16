# Intercepción del webhook de agendamiento — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** El Cerebro observa el proceso de agendamiento GHL→Marketico: Marketico auto-reporta el desenlace de cada `processBooking` a un hook del Cerebro, un cron horario reconcilia la agenda DB↔GHL, y una UI del viz muestra todo.

**Architecture:** Tres planos: (1) emisor en Marketico (`cerebroReporter.js` + wiring en `webhooks.js`, fire-and-forget), (2) receptor `viz/hooks.js` + sqlite `intercepciones.db` en el servidor api + cron `reconciliar_agenda.sh`, (3) consulta local-first/ssh en `bash/intercepciones/` que alimenta la página viz `intercepciones`.

**Tech Stack:** Node stdlib (cero deps npm en el viz), sqlite3 CLI, bash + psql_ro + python3, GHL API v2, Datastar 1.0.

**Spec:** `docs/superpowers/specs/2026-08-16-intercepcion-webhook-crm-design.md`

## Global Constraints

- **Cero npm deps en el viz** — `viz/hooks.js` usa solo `node:*` (patrón `publish.js`). En Marketico sí se usa `axios` (ya es dep, `^1.12.2`).
- **sqlite siempre vía CLI `sqlite3`**, SQL por stdin o `execFileSync` args — jamás en el argv de un comando remoto (patrón `pubstore.js` / `bash/publicar/lib.sh`).
- **Local-first + ssh**: los scripts de `bash/intercepciones/` usan la db local si existe (`data/sqlite/intercepciones.db`), si no `ssh root@api` contra `/apps/hermetico/data/sqlite/intercepciones.db`. Overrides por env: `INTERCEPCIONES_DB`, `INTERCEPCIONES_SSH`, `INTERCEPCIONES_DIR`.
- **Tokens jamás en argv**: GHL token a curl vía `--config -` por stdin (helper existente `ghl_api`).
- ⚠️ **Quirk horario**: `meetings.scheduled_start_time` guarda hora **Bogotá etiquetada como UTC** — leer el reloj literal (`AT TIME ZONE 'UTC'`); los Appointments GHL traen ISO real con offset → convertir a reloj Bogotá antes de comparar.
- **GHL caído ≠ 0 appointments**: una corrida que no pudo leer GHL se registra `estado='error'` y NO genera drift.
- **bash**: `set -euo pipefail`, `--json`, `-h` usage, nombres en español (convención del repo).
- **viz**: Datastar 1.0 sintaxis de dos puntos (`data-on:click`, `@get`), tokens semánticos (`var(--text-1)`), jamás hex ni `--pal-*`, `npm run viz:restart` tras editar.
- **Puertos**: hooks 4319 loopback; publish 4318; viz local 4317.

## Estructura de archivos

| Archivo | Responsabilidad |
|---|---|
| `bash/intercepciones/schema.sql` | DDL idempotente de las 3 tablas |
| `bash/intercepciones/lib.sh` | helpers local-first/ssh (`int_sql`, `sql_lit`, `ensure_schema`) |
| `viz/hooks.js` | receptor HTTP: `POST /hooks/crm-resultado`, `GET /health` |
| `bash/ghl/appointments.sh` | sonda GHL: appointments de un calendario en ventana |
| `bash/intercepciones/reconciliar_agenda.sh` | cron: compara DB↔GHL, escribe corridas+drift |
| `bash/intercepciones/log.sh` `drift.sh` `resumen.sh` | consulta read-only (`--json`) |
| `viz/lib/datasources.js` | +3 entradas SOURCES |
| `viz/pages/intercepciones.js` | página de la UI |
| `viz/specs/org/intercepciones.json` | seed del spec |
| `bash/publicar/desplegar.sh` | +restart de `viz-hooks` |
| Marketico: `src/services/cerebroReporter.js` | el emisor (fire-and-forget) |
| Marketico: `src/routes/webhooks.js:546-570` | wiring del reporte en `/crm` |

---

### Task 1: Schema + lib del dominio intercepciones

**Files:**
- Create: `bash/intercepciones/schema.sql`
- Create: `bash/intercepciones/lib.sh`

**Interfaces:**
- Produces: `int_sql [-json]` (SQL por stdin → db local o remota), `sql_lit <v>`, `ensure_schema`, vars `INT_DB_LOCAL`/`INT_SSH`/`INT_DIR`. Tablas `crm_webhook`, `corridas`, `drift`.

- [ ] **Step 1: Escribir `bash/intercepciones/schema.sql`**

```sql
-- Estado propio del interceptor de procesos Marketico — jamás datos de la org.
-- Idempotente: se aplica en cada arranque del receptor y en cada escritura bash.
PRAGMA journal_mode=WAL;

CREATE TABLE IF NOT EXISTS crm_webhook (
  id INTEGER PRIMARY KEY,
  recibido_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  appointment_id TEXT, location_id TEXT, estado_cita TEXT,
  contacto TEXT, email TEXT, telefono TEXT,
  start_time TEXT, end_time TEXT,
  ok INTEGER NOT NULL,
  resultado TEXT,
  error TEXT,
  duracion_ms INTEGER,
  payload TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_crm_webhook_recibido ON crm_webhook(recibido_at);
CREATE INDEX IF NOT EXISTS idx_crm_webhook_appt ON crm_webhook(appointment_id);

CREATE TABLE IF NOT EXISTS corridas (
  id INTEGER PRIMARY KEY,
  corrida_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  project_id TEXT, proyecto TEXT, ghl_calendar_id TEXT,
  ventana_desde TEXT, ventana_hasta TEXT,
  ghl_total INTEGER, db_total INTEGER,
  coinciden INTEGER, discrepancias INTEGER,
  estado TEXT NOT NULL DEFAULT 'ok',
  detalle TEXT
);
CREATE INDEX IF NOT EXISTS idx_corridas_at ON corridas(corrida_at);

CREATE TABLE IF NOT EXISTS drift (
  id INTEGER PRIMARY KEY,
  corrida_id INTEGER NOT NULL REFERENCES corridas(id),
  tipo TEXT NOT NULL CHECK (tipo IN ('falta_en_db','sobra_en_db','horas_difieren')),
  appointment_id TEXT, meeting_id TEXT,
  detalle TEXT
);
CREATE INDEX IF NOT EXISTS idx_drift_corrida ON drift(corrida_id);
```

- [ ] **Step 2: Escribir `bash/intercepciones/lib.sh`**

```bash
#!/usr/bin/env bash
# Helpers del dominio intercepciones — la sqlite del interceptor
# (data/sqlite/intercepciones.db). LOCAL-FIRST: si la db existe en este
# checkout (caso servidor api, donde escriben el hook y el cron) se usa
# sqlite3 directo; si no, por ssh al servidor (caso cerebro). El SQL viaja
# SIEMPRE por stdin — jamás en el argv del remoto. Patrón: bash/publicar/lib.sh.
set -euo pipefail
INT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$INT_LIB_DIR/../.." && pwd)"

INT_SSH="${INTERCEPCIONES_SSH:-root@api}"
INT_DIR="${INTERCEPCIONES_DIR:-/apps/hermetico}"
INT_DB_LOCAL="${INTERCEPCIONES_DB:-$REPO_ROOT/data/sqlite/intercepciones.db}"
INT_DB_REMOTA="$INT_DIR/data/sqlite/intercepciones.db"

# sql_lit <v> : literal SQL con comillas escapadas.
sql_lit() { printf "'%s'" "${1//\'/\'\'}"; }

# int_es_local : ¿la db vive en este checkout? (el override INTERCEPCIONES_DB
# también cuenta como local — así los tests apuntan a un archivo temporal).
int_es_local() { [[ -n "${INTERCEPCIONES_DB:-}" || -f "$INT_DB_LOCAL" ]]; }

# int_sql [-json] : ejecuta el SQL de stdin en la db del interceptor.
int_sql() {
  local flags=(); [[ "${1:-}" == "-json" ]] && flags=(-json)
  if int_es_local; then
    mkdir -p "$(dirname "$INT_DB_LOCAL")"
    sqlite3 "${flags[@]}" "$INT_DB_LOCAL"
  else
    ssh "$INT_SSH" "mkdir -p '$INT_DIR/data/sqlite' && sqlite3 ${flags[*]:-} '$INT_DB_REMOTA'"
  fi
}

# ensure_schema : aplica el DDL idempotente (silencioso: WAL responde «wal»).
ensure_schema() { int_sql < "$INT_LIB_DIR/schema.sql" >/dev/null; }
```

- [ ] **Step 3: Probar el schema en una db temporal**

Run:
```bash
cd /projects/hermetico && chmod +x bash/intercepciones/lib.sh
INTERCEPCIONES_DB=$(mktemp -u).db bash -c '
  source bash/intercepciones/lib.sh
  ensure_schema
  echo ".tables" | int_sql
  echo "INSERT INTO crm_webhook (ok, payload) VALUES (1, $(sql_lit "{\"x\":1}"));" | int_sql
  echo "SELECT count(*) FROM crm_webhook;" | int_sql
  rm -f "$INT_DB_LOCAL"'
```
Expected: `corridas  crm_webhook  drift` y luego `1`. Re-correr `ensure_schema` dos veces no debe fallar (idempotencia).

- [ ] **Step 4: Commit**

```bash
git add bash/intercepciones/schema.sql bash/intercepciones/lib.sh
git commit -m "intercepciones: schema + lib local-first/ssh de la sqlite del interceptor"
```

---

### Task 2: El receptor — `viz/hooks.js`

**Files:**
- Create: `viz/hooks.js`

**Interfaces:**
- Consumes: `bash/intercepciones/schema.sql` (lo aplica al boot).
- Produces: `POST /hooks/crm-resultado` (Bearer `HOOKS_TOKEN` → 204; sin/mal token → 401; JSON inválido o sin `ok` booleano → 400), `GET|HEAD /health` → 200. Env: `PORT` (default 4319), `HOST` (default 127.0.0.1), `HOOKS_TOKEN` (obligatorio), `INTERCEPCIONES_DB` (override para tests).

- [ ] **Step 1: Escribir `viz/hooks.js`**

```js
#!/usr/bin/env node
// El INTERCEPTOR — entrypoint que recibe los auto-reportes de Marketico
// (pm2 «viz-hooks»). Superficie mínima POR CONSTRUCCIÓN, como publish.js:
// una ruta de escritura con Bearer de máquina, y /health. Nada más.
// Diseño: docs/superpowers/specs/2026-08-16-intercepcion-webhook-crm-design.md
//
//   POST /hooks/crm-resultado   auto-reporte de un processBooking → sqlite
//   GET  /health                liveness
//
// Run:  PORT=4319 node viz/hooks.js   (HOST default 127.0.0.1 — solo nginx)

const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { execFileSync } = require("node:child_process");

const REPO_ROOT = path.resolve(__dirname, "..");
const PORT = Number(process.env.PORT) || 4319;
const HOST = process.env.HOST || "127.0.0.1";
const DB = () => process.env.INTERCEPCIONES_DB || path.join(REPO_ROOT, "data", "sqlite", "intercepciones.db");
const SCHEMA = path.join(REPO_ROOT, "bash", "intercepciones", "schema.sql");

// .env del checkout — mismo loader que publish.js (pm2 no garantiza el env).
for (const line of (() => { try { return fs.readFileSync(path.join(REPO_ROOT, ".env"), "utf8").split("\n"); } catch { return []; } })()) {
  const m = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim());
  if (m && process.env[m[1]] == null) process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
}
if (!process.env.HOOKS_TOKEN) {
  console.error("FALTA HOOKS_TOKEN (en .env o el entorno) — sin él cualquiera podría escribir el log.");
  process.exit(1);
}

// Comparación de token en tiempo constante (sobre hashes: iguala longitudes).
function tokenValido(header) {
  const m = /^Bearer (.+)$/.exec(header || "");
  if (!m) return false;
  const a = crypto.createHash("sha256").update(m[1]).digest();
  const b = crypto.createHash("sha256").update(process.env.HOOKS_TOKEN).digest();
  return crypto.timingSafeEqual(a, b);
}

const lit = (v) => (v == null ? "NULL" : `'${String(v).replace(/'/g, "''")}'`);

function sqlite(sql) {
  fs.mkdirSync(path.dirname(DB()), { recursive: true });
  execFileSync("sqlite3", [DB()], { input: sql, encoding: "utf8" });
}

// Schema idempotente al boot — el receptor no depende de que bash pasara antes.
sqlite(fs.readFileSync(SCHEMA, "utf8"));

function guardar(body) {
  const c = body.contacto || {};
  sqlite(`INSERT INTO crm_webhook
    (appointment_id, location_id, estado_cita, contacto, email, telefono,
     start_time, end_time, ok, resultado, error, duracion_ms, payload)
    VALUES (${lit(body.appointment_id)}, ${lit(body.location_id)}, ${lit(body.estado_cita)},
      ${lit(c.nombre)}, ${lit(c.email)}, ${lit(c.telefono)},
      ${lit(body.start_time)}, ${lit(body.end_time)}, ${body.ok ? 1 : 0},
      ${lit(body.resultado == null ? null : JSON.stringify(body.resultado))},
      ${lit(body.error == null ? null : JSON.stringify(body.error))},
      ${Number.isFinite(body.duracion_ms) ? Math.round(body.duracion_ms) : "NULL"},
      ${lit(JSON.stringify(body))});`);
}

const MAX_BODY = 512 * 1024; // el booking crudo de GHL viaja completo
function readBody(req) {
  return new Promise((resolve) => {
    let data = "";
    let done = false;
    const finish = (v) => { if (!done) { done = true; resolve(v); } };
    req.on("data", (ch) => { data += ch; if (data.length > MAX_BODY) { finish(null); req.destroy(); } });
    req.on("end", () => finish(data));
    req.on("error", () => finish(null));
  });
}

const server = http.createServer(async (req, res) => {
  const fin = (status, body = "") => { res.writeHead(status, { "Content-Type": "text/plain", "Cache-Control": "no-store" }); res.end(body); };
  try {
    const url = new URL(req.url, "http://localhost");
    if (url.pathname === "/health") {
      if (req.method === "HEAD") { res.writeHead(200, { "Content-Type": "text/plain", "Content-Length": "2" }); return res.end(); }
      return fin(200, "ok");
    }
    if (url.pathname === "/hooks/crm-resultado" && req.method === "POST") {
      if (!tokenValido(req.headers.authorization)) return fin(401);
      const raw = await readBody(req);
      if (raw == null) return fin(400, "cuerpo demasiado grande");
      let body;
      try { body = JSON.parse(raw); } catch { return fin(400, "JSON inválido"); }
      if (typeof body.ok !== "boolean") return fin(400, "falta ok:boolean");
      try {
        guardar(body);
      } catch (e) {
        // Último recurso: el payload no se pierde aunque la sqlite esté trabada.
        console.error(`[hooks] sqlite falló (${e.message}); payload: ${raw.slice(0, 2000)}`);
        return fin(500);
      }
      return fin(204);
    }
    return fin(404, "No encontrado");
  } catch (e) {
    console.error(`[hooks] ${req.method} ${req.url}: ${e.message}`);
    if (!res.headersSent) return fin(500);
    try { res.end(); } catch { /* conexión rota */ }
  }
});

server.listen(PORT, HOST, () => console.log(`viz-hooks on http://${HOST}:${PORT}`));
```

- [ ] **Step 2: Probar los cuatro caminos localmente**

Run (en una terminal, db temporal):
```bash
cd /projects/hermetico
INTERCEPCIONES_DB=/tmp/int-test.db HOOKS_TOKEN=secreto-test PORT=4399 node viz/hooks.js &
sleep 1
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:4399/health                       # 200
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:4399/hooks/crm-resultado \
  -H 'Content-Type: application/json' -d '{"ok":true}'                                      # 401 (sin token)
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:4399/hooks/crm-resultado \
  -H 'Authorization: Bearer secreto-test' -H 'Content-Type: application/json' -d 'no-json'  # 400
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:4399/hooks/crm-resultado \
  -H 'Authorization: Bearer secreto-test' -H 'Content-Type: application/json' \
  -d '{"appointment_id":"appt-1","location_id":"loc-1","estado_cita":"confirmed","contacto":{"nombre":"Test","email":"t@x.co","telefono":"+57"},"start_time":"2026-08-20T10:00:00-05:00","end_time":"2026-08-20T11:00:00-05:00","ok":true,"resultado":{"meeting_id":"m-1"},"error":null,"duracion_ms":1234,"booking":{"x":1}}'  # 204
sqlite3 -json /tmp/int-test.db "SELECT appointment_id, ok, duracion_ms FROM crm_webhook;"
kill %1; rm -f /tmp/int-test.db*
```
Expected: `200`, `401`, `400`, `204` y la fila `[{"appointment_id":"appt-1","ok":1,"duracion_ms":1234}]`.

- [ ] **Step 3: Commit**

```bash
git add viz/hooks.js
git commit -m "intercepciones: viz/hooks.js — el receptor de auto-reportes de Marketico"
```

---

### Task 3: El emisor — Marketico reporta al Cerebro

⚠️ Este task toca **el repo de Marketico** (`/projects/google-meet-express`), no hermetico. Committear allá con su convención de mensajes (mirar `git log --oneline -5` antes).

**Files:**
- Create: `/projects/google-meet-express/src/services/cerebroReporter.js`
- Modify: `/projects/google-meet-express/src/routes/webhooks.js:546-570` (ruta `/crm`)

**Interfaces:**
- Consumes: `POST /hooks/crm-resultado` del Task 2 (payload con `ok:boolean`).
- Produces: `reportarBooking({ booking, ok, resultado, error, duracionMs })` — async, jamás lanza. Env de Marketico: `CEREBRO_HOOK_URL`, `CEREBRO_HOOK_TOKEN`.

- [ ] **Step 1: Escribir `src/services/cerebroReporter.js`**

```js
import axios from 'axios';

// Auto-reporte al Cerebro del desenlace de cada processBooking (la
// intercepción del webhook de agendamiento). Fire-and-forget: este módulo
// jamás lanza — el interceptor no puede romper el flujo que observa.
// Config por env: CEREBRO_HOOK_URL + CEREBRO_HOOK_TOKEN. Sin ellas, no
// reporta (y avisa una sola vez).
let warned = false;

export async function reportarBooking({ booking, ok, resultado = null, error = null, duracionMs = null }) {
  const url = process.env.CEREBRO_HOOK_URL;
  const token = process.env.CEREBRO_HOOK_TOKEN;
  if (!url || !token) {
    if (!warned) { console.warn('[cerebro] CEREBRO_HOOK_URL/CEREBRO_HOOK_TOKEN no configurados — sin auto-reporte.'); warned = true; }
    return;
  }
  const payload = {
    appointment_id: booking?.calendar?.appointmentId ?? null,
    location_id: booking?.location?.id ?? null,
    estado_cita: booking?.calendar?.appoinmentStatus ?? null, // sic: typo del API de GHL
    contacto: { nombre: booking?.full_name ?? null, email: booking?.email ?? null, telefono: booking?.phone ?? null },
    start_time: booking?.calendar?.startTime ?? null,
    end_time: booking?.calendar?.endTime ?? null,
    ok,
    resultado,
    error,
    duracion_ms: duracionMs,
    booking: booking ?? null,
  };
  try {
    await axios.post(url, payload, {
      headers: { Authorization: `Bearer ${token}` },
      timeout: 5000,
    });
  } catch (err) {
    console.warn('[cerebro] auto-reporte falló (se sigue):', err.message);
  }
}
```

- [ ] **Step 2: Cablear el reporte en `webhooks.js` ruta `/crm`**

Import arriba (junto a los demás imports de servicios):
```js
import { reportarBooking } from '../services/cerebroReporter.js';
```

Reemplazar el handler `/crm` (líneas 546-570) por:
```js
router.post('/crm', async (req, res) => {
  const t0 = Date.now();
  try {
    const booking = req.body;
    console.log('Processing CRM event for booking:', booking.calendar?.id);

    // Since this is a webhook, we need to fetch the service account tokens
    const { google_main_identity } = getSettings();
    const tokens = await getIdentityByEmail(google_main_identity);
    if (!tokens) {
      throw new Error('Could not find Google service account credentials.');
    }

    // Asynchronously process the booking without holding up the response.
    // El desenlace (éxito o error) se auto-reporta al Cerebro — la
    // intercepción del proceso de agendamiento. Fire-and-forget.
    processBooking(booking, { tokens })
      .then((r) => reportarBooking({
        booking, ok: true, duracionMs: Date.now() - t0,
        // processBooking devuelve: objeto completo al crear; true si solo
        // verificó/actualizó horas; {cancelled:true} al cancelar; undefined
        // si el booking no traía appointmentId.
        resultado: (r && typeof r === 'object')
          ? { meeting_id: r.meeting?.id ?? null, event_id: r.event?.id ?? null, space: r.space?.google_space_id ?? null, cancelado: r.cancelled === true }
          : { detalle: r === true ? 'actualizado_o_vigente' : 'sin_appointment_id' },
      }))
      .catch(err => {
        console.error(`Error processing booking ${booking.calendar?.id} asynchronously:`, err);
        reportarBooking({ booking, ok: false, duracionMs: Date.now() - t0, error: { mensaje: err.message, paso: 'processBooking' } });
      });

    res.status(202).send('Accepted');

  } catch (err) {
    console.error('Error processing CRM webhook:', err);
    reportarBooking({ booking: req.body, ok: false, duracionMs: Date.now() - t0, error: { mensaje: err.message, paso: 'setup' } });
    // Send a success status to the webhook provider even if async processing fails
    res.status(202).send('Accepted');
  }
});
```

- [ ] **Step 3: Verificar sintaxis**

Run: `cd /projects/google-meet-express && node --check src/services/cerebroReporter.js && node --check src/routes/webhooks.js`
Expected: sin salida (ambos parsean).

- [ ] **Step 4: Probar el emisor contra el receptor local**

Run (con el receptor del Task 2 levantado igual que allá, puerto 4399, token `secreto-test`):
```bash
cd /projects/hermetico && INTERCEPCIONES_DB=/tmp/int-test.db HOOKS_TOKEN=secreto-test PORT=4399 node viz/hooks.js &
sleep 1
cd /projects/google-meet-express && CEREBRO_HOOK_URL=http://127.0.0.1:4399/hooks/crm-resultado CEREBRO_HOOK_TOKEN=secreto-test \
  node --input-type=module -e "
    const { reportarBooking } = await import('./src/services/cerebroReporter.js');
    await reportarBooking({ booking: { calendar: { appointmentId: 'appt-emisor', startTime: '2026-08-20T10:00:00-05:00', endTime: '2026-08-20T11:00:00-05:00', appoinmentStatus: 'confirmed' }, location: { id: 'loc-1' }, full_name: 'Prueba Emisor', email: 'p@x.co', phone: '+57' }, ok: false, error: { mensaje: 'boom', paso: 'processBooking' }, duracionMs: 42 });
    console.log('enviado');"
sqlite3 -json /tmp/int-test.db "SELECT appointment_id, ok, json_extract(error,'\$.mensaje') AS msj FROM crm_webhook;"
kill %1; rm -f /tmp/int-test.db*
```
Expected: `enviado` y la fila `[{"appointment_id":"appt-emisor","ok":0,"msj":"boom"}]`. Probar también sin env vars: debe imprimir el warn una vez y no fallar.

- [ ] **Step 5: Commit (en el repo de Marketico)**

```bash
cd /projects/google-meet-express
git add src/services/cerebroReporter.js src/routes/webhooks.js
git commit -m "crm webhook: auto-reporte del desenlace de processBooking al Cerebro"
```

---

### Task 4: La sonda GHL — `bash/ghl/appointments.sh`

**Files:**
- Create: `bash/ghl/appointments.sh`

**Interfaces:**
- Consumes: `bash/ghl/lib/common.sh` (`ghl_resolve_project`, `ghl_load_creds`, `ghl_api`, `ghl_qs`, `ghl_render`), `psql_ro`, tabla `crm_calendars`.
- Produces: CLI `appointments.sh (--project FRAG | --project-id UUID) [--calendar ID] [--desde N] [--hasta N] [--json]` → array de appointments `{id, appointmentStatus, title, startTime, endTime, contactId, calendarId}`. Ventana default: −1 a +30 días.

- [ ] **Step 1: Sondear el endpoint en vivo (read-only) para fijar el contrato**

Los endpoints de calendars usan `Version: 2021-04-15` (no el 2021-07-28 default del lib) y `startTime`/`endTime` en **epoch millis**. Verificarlo con el calendario real de David Guerrero:

```bash
cd /projects/hermetico && bash -c '
  source bash/ghl/lib/common.sh
  read -r pid _ < <(ghl_resolve_project "david")
  ghl_load_creds "$pid"
  export GHL_API_VERSION=2021-04-15
  desde=$(python3 -c "import time; print(int((time.time()-86400)*1000))")
  hasta=$(python3 -c "import time; print(int((time.time()+30*86400)*1000))")
  ghl_api "/calendars/events$(ghl_qs locationId "$GHL_LOCATION" calendarId bFFbTpMillO1n35FuDmv startTime "$desde" endTime "$hasta")" | python3 -m json.tool | head -50'
```
Expected: JSON con clave `events` y objetos con `id`, `appointmentStatus`, `title`, `startTime` (ISO con offset), `contactId`. **Si la forma difiere** (otra clave, otro formato de fechas, u otro error de Version), ajustar los pasos siguientes al contrato real observado — y anotar el hallazgo en el header del script.

- [ ] **Step 2: Escribir `bash/ghl/appointments.sh`**

```bash
#!/usr/bin/env bash
# Appointments (calendar events) de UN calendario GHL en una ventana — la
# sonda del lado FUENTE para la reconciliación de agenda del interceptor
# (bash/intercepciones/reconciliar_agenda.sh). Read-only, como todo bash/ghl/.
#
# Contrato GHL verificado (2026-08-16): GET /calendars/events exige
# Version: 2021-04-15 y startTime/endTime en epoch MILLIS; responde
# {"events":[{id, appointmentStatus, title, startTime ISO+offset, contactId}]}.
#
# uso: appointments.sh (--project FRAG | --project-id UUID) [--calendar ID]
#                      [--desde N] [--hasta N] [--limit N] [--json]
#   --calendar  default: el ghl_calendar_id activo del proyecto en crm_calendars
#   --desde/-hasta  días relativos a hoy (default: -1 y 30)
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
export GHL_API_VERSION=2021-04-15   # los endpoints de calendars viven en esta versión

FORMAT=table; PROJECT=""; PROJECT_ID=""; CALENDAR=""; DESDE=-1; HASTA=30; LIMIT=0
usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --project-id) PROJECT_ID="$2"; shift 2 ;;
    --calendar) CALENDAR="$2"; shift 2 ;;
    --desde) DESDE="$2"; shift 2 ;;
    --hasta) HASTA="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) usage ;;
    *) echo "flag desconocido: $1" >&2; usage 1 ;;
  esac
done

if [[ -z "$PROJECT_ID" ]]; then
  [[ -z "$PROJECT" ]] && { echo "falta --project o --project-id" >&2; usage 1; }
  read -r PROJECT_ID _ < <(ghl_resolve_project "$PROJECT")
fi
ghl_load_creds "$PROJECT_ID"

if [[ -z "$CALENDAR" ]]; then
  CALENDAR="$(psql_ro -t -A -c "SELECT ghl_calendar_id FROM crm_calendars
    WHERE project_id='${PROJECT_ID//\'/\'\'}' AND is_active LIMIT 1;")"
  [[ -z "$CALENDAR" ]] && { echo "el proyecto no tiene calendario activo en crm_calendars" >&2; exit 1; }
fi

DESDE_MS="$(python3 -c "import time,sys; print(int((time.time()+int(sys.argv[1])*86400)*1000))" "$DESDE")"
HASTA_MS="$(python3 -c "import time,sys; print(int((time.time()+int(sys.argv[1])*86400)*1000))" "$HASTA")"

ghl_api "/calendars/events$(ghl_qs locationId "$GHL_LOCATION" calendarId "$CALENDAR" \
    startTime "$DESDE_MS" endTime "$HASTA_MS")" \
  | python3 -c '
import json, sys
lim = int(sys.argv[1])
evs = (json.load(sys.stdin).get("events") or [])
evs.sort(key=lambda e: e.get("startTime") or "")
if lim > 0: evs = evs[:lim]
json.dump(evs, sys.stdout)' "$LIMIT" \
  | ghl_render "id:id,estado:appointmentStatus,titulo:title,inicio:startTime,contacto:contactId"
```

- [ ] **Step 3: Probar contra el calendario real**

Run: `chmod +x bash/ghl/appointments.sh && bash/ghl/appointments.sh --project david | head -15 && bash/ghl/appointments.sh --project david --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d), "appointments")'`
Expected: tabla alineada con los appointments de la ventana y el conteo JSON. Si la agenda está vacía en la ventana, ampliar `--desde -30` para ver históricos.

- [ ] **Step 4: Commit**

```bash
git add bash/ghl/appointments.sh
git commit -m "ghl: appointments.sh — la sonda de calendario para la reconciliación de agenda"
```

---

### Task 5: El cron — `bash/intercepciones/reconciliar_agenda.sh`

**Files:**
- Create: `bash/intercepciones/reconciliar_agenda.sh`

**Interfaces:**
- Consumes: `lib.sh` (Task 1: `int_sql`, `sql_lit`, `ensure_schema`), `bash/ghl/appointments.sh --project-id --json` (Task 4), `psql_ro` (de `bash/lib/common.sh`), tablas `crm_calendars`/`meetings`.
- Produces: filas en `corridas` + `drift`. CLI: `[--desde N] [--hasta N] [--dry-run] [--json]`. **[WRITE local sqlite]**.

- [ ] **Step 1: Escribir el script**

```bash
#!/usr/bin/env bash
# [WRITE sqlite intercepciones] Reconciliación de agenda — la verificación
# INDEPENDIENTE del interceptor: ¿los meetings 'scheduled' de la DB son
# exactamente los Appointments de GHL del calendario del proyecto?
# Por cada crm_calendars activo: GHL (via bash/ghl/appointments.sh) vs
# meetings (psql_ro), compara por meetings.event_id = appointment.id, y
# escribe corridas + drift en la sqlite del interceptor (una txn por corrida).
#
# ⚠️ Horas: scheduled_start_time guarda reloj BOGOTÁ etiquetado UTC → se lee
# literal (AT TIME ZONE 'UTC'); el startTime de GHL es ISO real → se convierte
# a reloj Bogotá. Se comparan minuto a minuto.
# ⚠️ GHL caído ≠ agenda vacía: la corrida queda estado='error', sin drift.
#
# uso: reconciliar_agenda.sh [--desde N] [--hasta N] [--dry-run] [--json]
#   --desde/--hasta  días relativos (default -1 y 30)
set -euo pipefail
INT_DIR_SELF="$(cd "$(dirname "$0")" && pwd)"
source "$INT_DIR_SELF/lib.sh"
source "$INT_DIR_SELF/../lib/common.sh"

DESDE=-1; HASTA=30; DRY=0; FORMAT=table
while [[ $# -gt 0 ]]; do
  case "$1" in
    --desde) DESDE="$2"; shift 2 ;;
    --hasta) HASTA="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "flag desconocido: $1" >&2; exit 1 ;;
  esac
done

(( DRY )) || ensure_schema

# Los calendarios integrados activos: el universo de la reconciliación.
CALS="$(psql_ro -t -A -F$'\t' -c "
  SELECT cc.ghl_calendar_id, cc.project_id, p.name
  FROM crm_calendars cc JOIN projects p ON p.id = cc.project_id
  WHERE cc.is_active ORDER BY p.name;")"
[[ -z "$CALS" ]] && { echo "sin calendarios activos en crm_calendars" >&2; exit 0; }

RESUMEN="[]"
while IFS=$'\t' read -r CAL PID PNOMBRE; do
  VENT_DESDE="$(date -d "$DESDE days" +%F)"
  VENT_HASTA="$(date -d "$HASTA days" +%F)"

  # --- lado GHL ---------------------------------------------------------------
  if GHL_JSON="$("$INT_DIR_SELF/../ghl/appointments.sh" --project-id "$PID" \
        --calendar "$CAL" --desde "$DESDE" --hasta "$HASTA" --json 2>/tmp/ghl-err-$$)"; then
    GHL_OK=1
  else
    GHL_OK=0; GHL_ERR="$(head -c 300 /tmp/ghl-err-$$)"
  fi
  rm -f /tmp/ghl-err-$$

  if (( ! GHL_OK )); then
    SQL="INSERT INTO corridas (project_id, proyecto, ghl_calendar_id, ventana_desde, ventana_hasta, estado, detalle)
         VALUES ($(sql_lit "$PID"), $(sql_lit "$PNOMBRE"), $(sql_lit "$CAL"),
                 $(sql_lit "$VENT_DESDE"), $(sql_lit "$VENT_HASTA"), 'error', $(sql_lit "$GHL_ERR"));"
    (( DRY )) && echo "[dry-run] corrida ERROR $PNOMBRE: $GHL_ERR" >&2 || echo "$SQL" | int_sql
    continue
  fi

  # --- lado DB (reloj literal = Bogotá) --------------------------------------
  DB_JSON="$(psql_ro -t -A -c "
    SELECT coalesce(json_agg(row_to_json(q)), '[]'::json) FROM (
      SELECT m.id, m.event_id, m.status, m.name,
        to_char(m.scheduled_start_time AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI') AS inicio_bogota
      FROM meetings m
      WHERE m.meeting_type = 'call' AND m.project_id = '${PID//\'/\'\'}'
        AND m.status IN ('scheduled','cancelled')
        AND m.scheduled_start_time AT TIME ZONE 'UTC'
            BETWEEN (now() AT TIME ZONE 'America/Bogota') + make_interval(days => $DESDE)
                AND (now() AT TIME ZONE 'America/Bogota') + make_interval(days => $HASTA)
    ) q;")"

  # --- comparación + SQL de la corrida (python arma la txn entera) -----------
  OUT="$(python3 - "$VENT_DESDE" "$VENT_HASTA" "$PID" "$PNOMBRE" "$CAL" <<PYEOF
import json, sys
from datetime import datetime, timezone, timedelta

vent_desde, vent_hasta, pid, pnombre, cal = sys.argv[1:6]
ghl = json.loads('''$GHL_JSON''')
db = json.loads('''$DB_JSON''')
BOG = timezone(timedelta(hours=-5))

def lit(v):
    if v is None: return "NULL"
    return "'" + str(v).replace("'", "''") + "'"

def bog_minuto(iso):
    # ISO real de GHL (con offset o Z) → reloj Bogotá 'YYYY-MM-DDTHH:MM'
    if not iso: return None
    d = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    return d.astimezone(BOG).strftime("%Y-%m-%dT%H:%M")

CANCELADOS = {"cancelled", "invalid", "noshow", "no-show"}
ghl_por_id = {e["id"]: e for e in ghl if e.get("id")}
db_por_appt = {m["event_id"]: m for m in db if m.get("event_id")}

drift = []
vivos_ghl = {i: e for i, e in ghl_por_id.items()
             if (e.get("appointmentStatus") or "").lower() not in CANCELADOS}

for i, e in vivos_ghl.items():
    m = db_por_appt.get(i)
    det = {"titulo": e.get("title"), "ghl_inicio_bogota": bog_minuto(e.get("startTime")),
           "estado_ghl": e.get("appointmentStatus"), "contact_id": e.get("contactId")}
    if m is None or m["status"] != "scheduled":
        det["estado_db"] = m["status"] if m else "ausente"
        drift.append(("falta_en_db", i, m["id"] if m else None, det))
    elif m["inicio_bogota"] != det["ghl_inicio_bogota"]:
        det["db_inicio_bogota"] = m["inicio_bogota"]
        drift.append(("horas_difieren", i, m["id"], det))

for appt, m in db_por_appt.items():
    if m["status"] != "scheduled": continue
    e = ghl_por_id.get(appt)
    if e is None or (e.get("appointmentStatus") or "").lower() in CANCELADOS:
        det = {"titulo": m.get("name"), "db_inicio_bogota": m["inicio_bogota"],
               "estado_ghl": (e or {}).get("appointmentStatus", "ausente")}
        drift.append(("sobra_en_db", appt, m["id"], det))

coinciden = sum(1 for i in vivos_ghl
                if db_por_appt.get(i, {}).get("status") == "scheduled"
                and db_por_appt[i]["inicio_bogota"] == bog_minuto(vivos_ghl[i].get("startTime")))

stmts = ["BEGIN;",
  f"INSERT INTO corridas (project_id, proyecto, ghl_calendar_id, ventana_desde, ventana_hasta,"
  f" ghl_total, db_total, coinciden, discrepancias) VALUES ({lit(pid)}, {lit(pnombre)}, {lit(cal)},"
  f" {lit(vent_desde)}, {lit(vent_hasta)}, {len(vivos_ghl)},"
  f" {sum(1 for m in db if m['status']=='scheduled')}, {coinciden}, {len(drift)});"]
for tipo, appt, mid, det in drift:
    stmts.append(f"INSERT INTO drift (corrida_id, tipo, appointment_id, meeting_id, detalle)"
                 f" VALUES (last_insert_rowid(), {lit(tipo)}, {lit(appt)}, {lit(mid)},"
                 f" {lit(json.dumps(det, ensure_ascii=False))});")
# last_insert_rowid() cambia con cada INSERT — capturarla UNA vez:
if drift:
    stmts[2:] = []  # reconstruir usando la variable de sqlite
    stmts.append("SELECT 'CORRIDA=' || last_insert_rowid();")
print(json.dumps({
  "sql_corrida": stmts[1],
  "drift": [{"tipo": t, "appointment_id": a, "meeting_id": m, "detalle": d} for t, a, m, d in drift],
  "resumen": {"proyecto": pnombre, "ghl": len(vivos_ghl),
              "db": sum(1 for m in db if m["status"] == "scheduled"),
              "coinciden": coinciden, "discrepancias": len(drift)}}))
PYEOF
)"

  # --- persistir: corrida + drift en UNA txn, con el id capturado ------------
  if (( DRY )); then
    echo "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("[dry-run]", json.dumps(d["resumen"], ensure_ascii=False)); [print("  drift:", json.dumps(x, ensure_ascii=False)) for x in d["drift"]]' >&2
  else
    echo "$OUT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
def lit(v):
    return "NULL" if v is None else "'"'"'" + str(v).replace("'"'"'", "'"'"''"'"'") + "'"'"'"
print("BEGIN;")
print(d["sql_corrida"])
for x in d["drift"]:
    print(f"INSERT INTO drift (corrida_id, tipo, appointment_id, meeting_id, detalle)"
          f" VALUES (last_insert_rowid(), {lit(x['"'"'tipo'"'"'])}, {lit(x['"'"'appointment_id'"'"'])},"
          f" {lit(x['"'"'meeting_id'"'"'])}, {lit(json.dumps(x['"'"'detalle'"'"'], ensure_ascii=False))});")
print("COMMIT;")' | int_sql
  fi
  RESUMEN="$(python3 -c '
import json, sys
acc = json.loads(sys.argv[1]); acc.append(json.loads(sys.argv[2])["resumen"]); print(json.dumps(acc))' \
    "$RESUMEN" "$OUT")"
done <<<"$CALS"

if [[ "$FORMAT" == "json" ]]; then echo "$RESUMEN"; else
  echo "$RESUMEN" | python3 -c '
import json, sys
for r in json.load(sys.stdin):
    print(f"{r[\"proyecto\"]}: ghl={r[\"ghl\"]} db={r[\"db\"]} coinciden={r[\"coinciden\"]} drift={r[\"discrepancias\"]}")'
fi
```

⚠️ **Nota para el implementador — el bloque `last_insert_rowid()`**: el truco
del heredoc de arriba quedó enredado en el borrador (la lista `stmts` se
reconstruye y no se usa). Simplificarlo así: el python del heredoc emite SOLO
`{"drift": [...], "resumen": {...}, "corrida_values": "(...)"}`, y el segundo
python (el de persistir) arma la transacción completa:
`BEGIN; INSERT INTO corridas ...; INSERT INTO drift (corrida_id, ...) VALUES (last_insert_rowid(), ...); ... COMMIT;`
— en sqlite, `last_insert_rowid()` dentro de la MISMA conexión tras el INSERT
de `corridas` es estable mientras no haya otro INSERT con rowid de por medio;
como los INSERT de `drift` cambian el rowid, usar la forma
`INSERT INTO drift ... SELECT max(id), ... FROM corridas` **no** — lo limpio es:
`INSERT INTO corridas ...; ` seguido de los drift con
`(SELECT max(id) FROM corridas)` como `corrida_id`, todo dentro de la txn.
Esa forma es correcta, simple, y no depende de rowids intermedios.

- [ ] **Step 2: Probar en dry-run contra datos reales**

Run: `chmod +x bash/intercepciones/reconciliar_agenda.sh && bash/intercepciones/reconciliar_agenda.sh --dry-run`
Expected: una línea `[dry-run] {"proyecto":"David Guerrero",...}` por calendario activo, con drift listado. **Validar el quirk horario**: elegir 2-3 meetings agendados conocidos (`bash/closers/agenda.sh` los muestra en hora Bogotá correcta) y verificar que NO aparecen como `horas_difieren`. Si todos los meetings dan drift de exactamente 5h, la normalización quedó al revés — corregir antes de seguir.

- [ ] **Step 3: Probar la escritura en una db temporal**

Run:
```bash
INTERCEPCIONES_DB=/tmp/int-recon.db bash/intercepciones/reconciliar_agenda.sh --json
sqlite3 -json /tmp/int-recon.db "SELECT proyecto, ghl_total, db_total, coinciden, discrepancias, estado FROM corridas;"
sqlite3 -json /tmp/int-recon.db "SELECT tipo, count(*) n FROM drift GROUP BY tipo;"
rm -f /tmp/int-recon.db*
```
Expected: una fila en `corridas` por calendario, drift consistente con el dry-run, y el JSON de salida con el mismo resumen.

- [ ] **Step 4: Commit**

```bash
git add bash/intercepciones/reconciliar_agenda.sh
git commit -m "intercepciones: reconciliar_agenda.sh — la verificación independiente DB↔GHL"
```

---

### Task 6: Consulta — `log.sh`, `drift.sh`, `resumen.sh`

**Files:**
- Create: `bash/intercepciones/log.sh`
- Create: `bash/intercepciones/drift.sh`
- Create: `bash/intercepciones/resumen.sh`

**Interfaces:**
- Consumes: `lib.sh` (`int_sql -json`).
- Produces (contrato para las fuentes viz del Task 7):
  - `log.sh [--desde YYYY-MM-DD] [--solo-errores] [--limit N] [--json]` → rows `{id, recibido_at, appointment_id, estado_cita, contacto, email, start_time, ok, resultado, error, duracion_ms}` (sin `payload` — pesa).
  - `drift.sh [--historia] [--json]` → rows: default = drift de la ÚLTIMA corrida de cada calendario `{corrida_id, corrida_at, proyecto, tipo, appointment_id, meeting_id, detalle}`; `--historia` = las corridas `{id, corrida_at, proyecto, ghl_total, db_total, coinciden, discrepancias, estado, detalle}`.
  - `resumen.sh [--json]` → UN objeto `{webhook: {h24: {recibidos, ok, fallos}, d7: {...}, ultimos_fallos: [...≤5]}, corridas: [última por calendario], drift: [de esas corridas], generado_at}`.

- [ ] **Step 1: Escribir `log.sh`**

```bash
#!/usr/bin/env bash
# Log del webhook interceptado — qué reportó Marketico de cada /crm.
# Read-only; local si la db está en este checkout, ssh si no (lib.sh).
# uso: log.sh [--desde YYYY-MM-DD] [--solo-errores] [--limit N] [--json]
set -euo pipefail
source "$(dirname "$0")/lib.sh"

DESDE=""; SOLO_ERR=0; LIMIT=50; FORMAT=table
while [[ $# -gt 0 ]]; do
  case "$1" in
    --desde) DESDE="$2"; shift 2 ;;
    --solo-errores) SOLO_ERR=1; shift ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "flag desconocido: $1" >&2; exit 1 ;;
  esac
done

W="1=1"
[[ -n "$DESDE" ]] && W="$W AND recibido_at >= $(sql_lit "$DESDE")"
(( SOLO_ERR )) && W="$W AND ok = 0"
LIM=""; [[ "$LIMIT" != "0" ]] && LIM="LIMIT ${LIMIT//[^0-9]/}"

SQL="SELECT id, recibido_at, appointment_id, estado_cita, contacto, email,
       start_time, ok, resultado, error, duracion_ms
     FROM crm_webhook WHERE $W ORDER BY recibido_at DESC $LIM;"

if [[ "$FORMAT" == "json" ]]; then echo "$SQL" | int_sql -json
else echo -e ".mode column\n.headers on\n$SQL" | int_sql; fi
```

- [ ] **Step 2: Escribir `drift.sh`**

```bash
#!/usr/bin/env bash
# Drift de agenda vigente — las discrepancias DB↔GHL de la ÚLTIMA corrida de
# cada calendario (las corridas viejas son historia, no cola). Read-only.
# uso: drift.sh [--historia] [--json]
set -euo pipefail
source "$(dirname "$0")/lib.sh"

HISTORIA=0; FORMAT=table
while [[ $# -gt 0 ]]; do
  case "$1" in
    --historia) HISTORIA=1; shift ;;
    --json) FORMAT=json; shift ;;
    -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "flag desconocido: $1" >&2; exit 1 ;;
  esac
done

if (( HISTORIA )); then
  SQL="SELECT id, corrida_at, proyecto, ghl_total, db_total, coinciden,
         discrepancias, estado, detalle
       FROM corridas ORDER BY corrida_at DESC LIMIT 200;"
else
  SQL="WITH ultimas AS (
         SELECT max(id) AS id FROM corridas WHERE estado='ok' GROUP BY ghl_calendar_id)
       SELECT d.corrida_id, c.corrida_at, c.proyecto, d.tipo,
              d.appointment_id, d.meeting_id, d.detalle
       FROM drift d JOIN corridas c ON c.id = d.corrida_id
       WHERE d.corrida_id IN (SELECT id FROM ultimas)
       ORDER BY c.proyecto, d.tipo;"
fi

if [[ "$FORMAT" == "json" ]]; then echo "$SQL" | int_sql -json
else echo -e ".mode column\n.headers on\n$SQL" | int_sql; fi
```

- [ ] **Step 3: Escribir `resumen.sh`**

```bash
#!/usr/bin/env bash
# El objeto-resumen del interceptor: KPIs del webhook (24h/7d), últimas
# corridas de reconciliación y su drift — la fuente de la UI viz
# «Intercepciones». Siempre un solo objeto JSON. Read-only.
# uso: resumen.sh [--json]   (--json aceptado por consistencia; siempre emite JSON)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

WEBHOOK="$(echo "SELECT
    sum(CASE WHEN recibido_at >= datetime('now','-1 day') THEN 1 ELSE 0 END) AS h24,
    sum(CASE WHEN recibido_at >= datetime('now','-1 day') AND ok=1 THEN 1 ELSE 0 END) AS h24_ok,
    sum(CASE WHEN recibido_at >= datetime('now','-7 day') THEN 1 ELSE 0 END) AS d7,
    sum(CASE WHEN recibido_at >= datetime('now','-7 day') AND ok=1 THEN 1 ELSE 0 END) AS d7_ok
  FROM crm_webhook;" | int_sql -json)"
FALLOS="$(echo "SELECT recibido_at, appointment_id, contacto, error FROM crm_webhook
  WHERE ok=0 ORDER BY recibido_at DESC LIMIT 5;" | int_sql -json)"
CORRIDAS="$(echo "WITH ultimas AS (SELECT max(id) AS id FROM corridas GROUP BY ghl_calendar_id)
  SELECT id, corrida_at, proyecto, ghl_calendar_id, ghl_total, db_total,
         coinciden, discrepancias, estado, detalle
  FROM corridas WHERE id IN (SELECT id FROM ultimas) ORDER BY proyecto;" | int_sql -json)"
DRIFT="$(echo "WITH ultimas AS (SELECT max(id) AS id FROM corridas WHERE estado='ok' GROUP BY ghl_calendar_id)
  SELECT d.corrida_id, c.proyecto, d.tipo, d.appointment_id, d.meeting_id, d.detalle
  FROM drift d JOIN corridas c ON c.id = d.corrida_id
  WHERE d.corrida_id IN (SELECT id FROM ultimas) ORDER BY c.proyecto, d.tipo;" | int_sql -json)"

python3 -c '
import json, sys
from datetime import datetime, timezone
wh = (json.loads(sys.argv[1]) or [{}])[0]
def num(v): return int(v) if v is not None else 0
h24, h24ok, d7, d7ok = (num(wh.get(k)) for k in ("h24","h24_ok","d7","d7_ok"))
print(json.dumps({
  "webhook": {"h24": {"recibidos": h24, "ok": h24ok, "fallos": h24 - h24ok},
              "d7": {"recibidos": d7, "ok": d7ok, "fallos": d7 - d7ok},
              "ultimos_fallos": json.loads(sys.argv[2]) or []},
  "corridas": json.loads(sys.argv[3]) or [],
  "drift": json.loads(sys.argv[4]) or [],
  "generado_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}, ensure_ascii=False))' "${WEBHOOK:-[]}" "${FALLOS:-[]}" "${CORRIDAS:-[]}" "${DRIFT:-[]}"
```

- [ ] **Step 4: Probar los tres contra una db poblada**

Run (siembra + consulta, todo local):
```bash
chmod +x bash/intercepciones/{log,drift,resumen}.sh
export INTERCEPCIONES_DB=/tmp/int-consulta.db
bash -c 'source bash/intercepciones/lib.sh && ensure_schema && int_sql <<SQL
INSERT INTO crm_webhook (appointment_id, contacto, ok, payload) VALUES ("a1","Juan",1,"{}");
INSERT INTO crm_webhook (appointment_id, contacto, ok, error, payload) VALUES ("a2","Ana",0,"{\"mensaje\":\"boom\"}","{}");
INSERT INTO corridas (project_id, proyecto, ghl_calendar_id, ghl_total, db_total, coinciden, discrepancias) VALUES ("p1","David Guerrero","cal1",5,4,4,1);
INSERT INTO drift (corrida_id, tipo, appointment_id, detalle) VALUES (1,"falta_en_db","a9","{\"titulo\":\"Llamada X\"}");
SQL'
bash/intercepciones/log.sh --json | python3 -m json.tool | head -20
bash/intercepciones/log.sh --solo-errores --json     # solo a2
bash/intercepciones/drift.sh --json                  # el falta_en_db
bash/intercepciones/resumen.sh | python3 -m json.tool
unset INTERCEPCIONES_DB; rm -f /tmp/int-consulta.db*
```
Expected: log con 2 filas (sin columna payload), `--solo-errores` con 1, drift con 1, y el resumen con `webhook.h24.recibidos: 2`, `fallos: 1`, `corridas` y `drift` poblados.

- [ ] **Step 5: Commit**

```bash
git add bash/intercepciones/log.sh bash/intercepciones/drift.sh bash/intercepciones/resumen.sh
git commit -m "intercepciones: consulta read-only — log, drift y resumen (local-first + ssh)"
```

---

### Task 7: La UI — fuentes viz + página `intercepciones` + seed

**Files:**
- Modify: `viz/lib/datasources.js` (agregar 3 entradas a `SOURCES`)
- Create: `viz/pages/intercepciones.js`
- Create: `viz/specs/org/intercepciones.json`

**Interfaces:**
- Consumes: los contratos JSON del Task 6; `fetchSource(id, params)` de `lib/datasources.js`; `escape`, `table`, `section` de `lib/kit.js`; `cards` de `blocks/kpi-cards.js` (firma: `cards(defs, data)` con defs `{key, label, fmt, tone}` — **leer `blocks/kpi-cards.js` antes** para confirmar la forma de `defs` y ajustar).
- Produces: fuentes `intercepciones_resumen` (object), `intercepciones_log` (rows), `intercepciones_drift` (rows); componente de página `intercepciones`; spec org `intercepciones`.

- [ ] **Step 1: Agregar las fuentes a `SOURCES`** (junto a las demás, orden alfabético-temático del archivo)

```js
  intercepciones_resumen: {
    label: "Intercepciones — resumen",
    script: "bash/intercepciones/resumen.sh",
    emits: "object",
    args: {},
  },
  intercepciones_log: {
    label: "Intercepciones — log del webhook CRM",
    script: "bash/intercepciones/log.sh",
    emits: "rows",
    args: { desde: "--desde", limit: "--limit", solo_errores: { flag: "--solo-errores", bool: true } },
  },
  intercepciones_drift: {
    label: "Intercepciones — drift de agenda",
    script: "bash/intercepciones/drift.sh",
    emits: "rows",
    args: { historia: { flag: "--historia", bool: true } },
  },
```

- [ ] **Step 2: Escribir `viz/pages/intercepciones.js`**

Antes de escribir: leer `viz/blocks/kpi-cards.js` completo (la firma real de `cards`/tonos) y `viz/pages/dashboard.js` (estructura de página). Implementación de referencia — ajustar a las firmas reales:

```js
// intercepciones — la mirilla sobre los procesos de Marketico interceptados.
// Consume el objeto de bash/intercepciones/resumen.sh: KPIs del webhook de
// agendamiento (auto-reporte de processBooking), últimas corridas de la
// reconciliación de agenda DB↔GHL y su drift vigente.

const { fetchSource } = require("../lib/datasources");
const { escape, section } = require("../lib/kit");
const { cards } = require("../blocks/kpi-cards");

const TIPO_DRIFT = {
  falta_en_db: { label: "Falta en DB", tone: "neg" },
  sobra_en_db: { label: "Sobra en DB", tone: "cau" },
  horas_difieren: { label: "Horas difieren", tone: "cau" },
};

const fmtTs = (iso) => (iso ? String(iso).replace("T", " ").slice(0, 16) : "—");

function badge(tone, txt) {
  return `<span class="badge badge-${tone}">${escape(txt)}</span>`;
}

function tablaLog(fallos) {
  if (!fallos.length) return `<p class="text-sm" style="color:var(--text-3)">Sin fallos recientes.</p>`;
  const filas = fallos.map((f) => {
    const err = (() => { try { return JSON.parse(f.error || "null"); } catch { return null; } })();
    return `<tr>
      <td>${escape(fmtTs(f.recibido_at))}</td>
      <td>${escape(f.contacto || "—")}</td>
      <td class="font-mono text-xs">${escape(f.appointment_id || "—")}</td>
      <td>${badge("neg", err?.paso || "error")} ${escape(err?.mensaje || "")}</td>
    </tr>`;
  }).join("");
  return `<div class="table-wrap"><table class="tbl dense">
    <thead><tr><th>Recibido</th><th>Contacto</th><th>Appointment</th><th>Error</th></tr></thead>
    <tbody>${filas}</tbody></table></div>`;
}

function tablaDrift(drift) {
  if (!drift.length) return `<p class="text-sm" style="color:var(--text-3)">La agenda cuadra: sin discrepancias en la última corrida.</p>`;
  const filas = drift.map((d) => {
    const det = (() => { try { return JSON.parse(d.detalle || "{}"); } catch { return {}; } })();
    const t = TIPO_DRIFT[d.tipo] || { label: d.tipo, tone: "cau" };
    return `<tr>
      <td>${escape(d.proyecto || "—")}</td>
      <td>${badge(t.tone, t.label)}</td>
      <td>${escape(det.titulo || "—")}</td>
      <td>${escape(det.ghl_inicio_bogota || det.db_inicio_bogota || "—")}</td>
      <td class="font-mono text-xs">${escape(d.appointment_id || "—")}</td>
    </tr>`;
  }).join("");
  return `<div class="table-wrap"><table class="tbl dense">
    <thead><tr><th>Proyecto</th><th>Tipo</th><th>Llamada</th><th>Inicio (Bogotá)</th><th>Appointment</th></tr></thead>
    <tbody>${filas}</tbody></table></div>`;
}

function tablaCorridas(corridas) {
  if (!corridas.length) return `<p class="text-sm" style="color:var(--text-3)">El cron aún no corre.</p>`;
  const filas = corridas.map((c) => `<tr>
    <td>${escape(c.proyecto || "—")}</td>
    <td>${escape(fmtTs(c.corrida_at))}</td>
    <td class="text-right">${c.ghl_total ?? "—"}</td>
    <td class="text-right">${c.db_total ?? "—"}</td>
    <td class="text-right">${c.coinciden ?? "—"}</td>
    <td class="text-right">${c.estado === "error" ? badge("neg", "error") : (c.discrepancias || 0)}</td>
  </tr>`).join("");
  return `<div class="table-wrap"><table class="tbl dense">
    <thead><tr><th>Proyecto</th><th>Corrida</th><th>GHL</th><th>DB</th><th>Coinciden</th><th>Drift</th></tr></thead>
    <tbody>${filas}</tbody></table></div>`;
}

function renderIntercepciones(ui) {
  let data;
  try {
    ({ rows: [data] } = fetchSource(ui.source, ui.params || {}));
  } catch (e) {
    return `<section id="pane" class="flex-1 p-6"><div class="alert alert-neg">No se pudo leer el interceptor: ${escape(e.message)}</div></section>`;
  }
  const wh = data.webhook || { h24: {}, d7: {}, ultimos_fallos: [] };
  const corridas = data.corridas || [];
  const drift = data.drift || [];

  // Freshness: si la última corrida tiene más de 2h, el cron está caído.
  const masReciente = corridas.map((c) => c.corrida_at).sort().pop();
  const horasSin = masReciente ? (Date.now() - Date.parse(masReciente + "Z")) / 36e5 : null;
  const alerta = horasSin != null && horasSin > 2
    ? `<div class="alert alert-neg mb-4">La reconciliación no corre hace ${horasSin.toFixed(1)}h — revisar el cron «intercepciones-cron».</div>`
    : "";

  const kpis = cards([
    { key: "h24", label: "Webhooks 24h", fmt: "int", tone: "brand" },
    { key: "h24_fallos", label: "Fallos 24h", fmt: "int", tone: "neg" },
    { key: "d7", label: "Webhooks 7d", fmt: "int", tone: "brand" },
    { key: "d7_fallos", label: "Fallos 7d", fmt: "int", tone: "neg" },
    { key: "drift_n", label: "Drift vigente", fmt: "int", tone: "cau" },
  ], {
    h24: wh.h24.recibidos ?? 0, h24_fallos: wh.h24.fallos ?? 0,
    d7: wh.d7.recibidos ?? 0, d7_fallos: wh.d7.fallos ?? 0,
    drift_n: drift.length,
  });

  const head = `<div class="flex items-baseline justify-between mb-4">
    <h1 class="text-xl font-bold" style="color:var(--text-1)">Intercepciones</h1>
    <span class="text-xs" style="color:var(--text-3)">agendamiento GHL→Marketico · generado ${escape(fmtTs(data.generado_at))}</span>
  </div>`;

  return `<section id="pane" class="flex-1 p-6 overflow-auto" style="background:var(--surface-2)">
    ${head}${alerta}${kpis}
    <div class="grid gap-6 mt-6" style="grid-template-columns:1fr">
      ${section("Drift de agenda (última corrida)", drift.length, tablaDrift(drift))}
      ${section("Corridas de reconciliación", corridas.length, tablaCorridas(corridas))}
      ${section("Últimos fallos del webhook", (wh.ultimos_fallos || []).length, tablaLog(wh.ultimos_fallos || []))}
    </div>
  </section>`;
}

module.exports = {
  id: "intercepciones",
  manifest: { consumes: "object", overridable: [] },
  render: renderIntercepciones,
};
```

- [ ] **Step 3: Sembrar el spec `viz/specs/org/intercepciones.json`**

```json
{
  "id": "intercepciones",
  "name": "Intercepciones",
  "component": "intercepciones",
  "source": "intercepciones_resumen",
  "params": {},
  "scope": "org",
  "created_at": "2026-08-16T00:00:00.000Z"
}
```

- [ ] **Step 4: Probar el render con datos reales**

Run:
```bash
export INTERCEPCIONES_DB=/tmp/int-consulta.db   # re-sembrar como en Task 6 Step 4 si se borró
npm run viz:restart && sleep 1
curl -s "http://localhost:4317/u/intercepciones" | grep -o "Intercepciones\|Drift de agenda\|alert-neg" | sort | uniq -c
```
Expected: la página renderiza con las tres secciones; sin errores en el log del viz (`validateSpec` al boot no se queja del spec). Abrir en navegador y revisar **los dos modos** (botón ◐). Después `unset INTERCEPCIONES_DB` (si queda seteado, la consulta local pisa el camino ssh).

- [ ] **Step 5: Commit**

```bash
git add viz/lib/datasources.js viz/pages/intercepciones.js viz/specs/org/intercepciones.json
git commit -m "viz: página intercepciones — la mirilla del webhook CRM y el drift de agenda"
```

---

### Task 8: Despliegue

Este task es una lista de operaciones (ssh + config), no de código — ejecutarla en orden, verificando cada punto antes del siguiente. Requiere acceso a `root@api` y al deploy de Marketico.

**Files:**
- Modify: `bash/publicar/desplegar.sh:20` (restart de ambos pm2)

- [ ] **Step 1: Extender `desplegar.sh` para reiniciar también `viz-hooks`**

En la línea del `REMOTE_SHA` cambiar `pm2 restart viz-publish --update-env` por `pm2 restart viz-publish --update-env >&2 && (pm2 restart viz-hooks --update-env >&2 || true)` — el `|| true` cubre el primer deploy, cuando `viz-hooks` aún no existe. Actualizar igual la línea del `--dry-run`. Commit: `git commit -am "publicar: desplegar.sh reinicia también viz-hooks"`.

- [ ] **Step 2: Generar el secreto y configurar el servidor**

```bash
TOKEN=$(openssl rand -hex 32) && echo "HOOKS_TOKEN=$TOKEN"
ssh root@api "grep -q HOOKS_TOKEN /apps/hermetico/.env || echo 'HOOKS_TOKEN=$TOKEN' >> /apps/hermetico/.env"
```
Guardar el valor: Marketico lo necesita en el Step 5.

- [ ] **Step 3: Llevar el código y levantar los procesos**

```bash
bash/publicar/desplegar.sh    # push + pull + restart (viz-hooks aún no existe: el || true lo cubre)
ssh root@api "cd /apps/hermetico && pm2 start viz/hooks.js --name viz-hooks && \
  pm2 start bash/intercepciones/reconciliar_agenda.sh --name intercepciones-cron \
    --interpreter bash --no-autorestart --cron-restart='17 * * * *' && pm2 save"
ssh root@api "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:4319/health"   # 200
```
(El cron al minuto 17 — evita la punta de la hora, donde se apilan otros crons.)

- [ ] **Step 4: nginx — montar /hooks/**

En el server block de `app.ikigaigm.parallelo.ai` (en `/etc/nginx/sites-enabled/`, mirar el nombre exacto con `ssh root@api "grep -rl app.ikigaigm /etc/nginx/sites-enabled/"`), agregar junto al `location /` existente:

```nginx
    location /hooks/ {
        proxy_pass http://127.0.0.1:4319;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        client_max_body_size 1m;
    }
```
Luego: `ssh root@api "nginx -t && systemctl reload nginx"`. Verificar desde afuera:
`curl -s -o /dev/null -w '%{http_code}' -X POST https://app.ikigaigm.parallelo.ai/hooks/crm-resultado -d '{}'` → **401** (el hook responde y exige token).

- [ ] **Step 5: Probar el camino público con token**

```bash
curl -s -o /dev/null -w '%{http_code}' -X POST https://app.ikigaigm.parallelo.ai/hooks/crm-resultado \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"appointment_id":"e2e-test","ok":true,"resultado":{"detalle":"prueba e2e"},"booking":{}}'   # 204
bash/intercepciones/log.sh --limit 3   # desde el cerebro, vía ssh: la fila e2e-test aparece
```

- [ ] **Step 6: Primera corrida real del cron + verificación**

```bash
ssh root@api "cd /apps/hermetico && bash bash/intercepciones/reconciliar_agenda.sh --json"
bash/intercepciones/drift.sh          # desde el cerebro: el drift real de hoy
```
Expected: corrida `ok` para David Guerrero con totales sensatos (comparar `db_total` contra `bash/closers/agenda.sh` mentalmente). Documentar en el commit final cuánto drift real apareció — ese número es el hallazgo de la fase.

- [ ] **Step 7: Desplegar Marketico con las env vars**

En el entorno donde corre Marketico (su deploy habitual): setear
`CEREBRO_HOOK_URL=https://app.ikigaigm.parallelo.ai/hooks/crm-resultado` y
`CEREBRO_HOOK_TOKEN=<el token del Step 2>`, desplegar el commit del Task 3 y
reiniciar. Verificar en sus logs que NO aparece el warn de vars faltantes.

- [ ] **Step 8: Verificación end-to-end con un booking real**

Esperar (o provocar en GHL) el siguiente agendamiento real. Verificar desde el cerebro: `bash/intercepciones/log.sh --limit 3` muestra la fila con `ok=1` y su `meeting_id`; la UI `intercepciones` la refleja. Si a las 24h no llegó ninguno, revisar los logs de Marketico (¿posteó?) y de `viz-hooks` (¿401 por token distinto?).

- [ ] **Step 9: Commit final + actualizar CLAUDE.md**

Agregar al CLAUDE.md del cerebro (sección nueva «Intercepciones domain») un resumen de 5-8 líneas: qué se intercepta, dónde vive el log, los 4 scripts, la UI, y la regla «GHL caído ≠ 0 appointments». Commit: `git commit -am "intercepciones: dominio documentado en CLAUDE.md"`.

---

## Self-review (hecho al escribir)

- **Cobertura del spec**: emisor→T3, receptor→T2, sqlite→T1, cron→T5, sonda GHL→T4, consulta→T6, UI→T7, despliegue→T8. Manejo de errores del spec: token inválido (T2 Step 2), GHL caído (T5), sqlite trabada (T2, log a stderr), vars ausentes (T3 Step 4). ✓
- **Contrato GHL sin verificar**: el endpoint `/calendars/events` (Version, millis, clave `events`) se fija en T4 Step 1 con una sonda ANTES de escribir el script — si difiere, se ajusta ahí. Declarado, no asumido. ✓
- **Consistencia de tipos**: `int_sql`/`sql_lit`/`ensure_schema` (T1) usados en T5/T6; payload del emisor (T3) coincide campo a campo con `guardar()` (T2); contratos JSON de T6 coinciden con lo que la página T7 lee (`webhook.h24.recibidos`, `corridas[].corrida_at`, `drift[].detalle`). ✓
- **Puntos que el implementador debe resolver en sitio** (declarados en su task): la firma exacta de `cards()` en T7 (leer `blocks/kpi-cards.js` primero) y la simplificación del bloque `last_insert_rowid()` en T5 (nota ⚠️ con la forma correcta: `(SELECT max(id) FROM corridas)` dentro de la txn).

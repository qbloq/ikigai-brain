# Intercepción del webhook de agendamiento (GHL → Marketico)

**Fecha**: 2026-08-16 · **Estado**: diseño aprobado en conversación, pendiente review del spec

## Contexto y propósito

Marketico procesa el webhook de agendamiento de GHL en `POST /webhooks/crm`
(`/projects/google-meet-express/src/routes/webhooks.js` → `processBooking` en
`crmService.js`): crea el Google Space, el evento de Calendar, la suscripción
Meet y la fila `meetings` (`status='scheduled'`, `meeting_type='call'`,
`event_id` = appointmentId de GHL); maneja reagendas y cancelaciones. Responde
202 y todo lo real ocurre async — **si `processBooking` falla, el error muere
en un `console.error`** y nadie se entera hasta que una llamada no aparece.

Esta es la **segunda operación de Marketico que el Cerebro intercepta** (la
primera fue el reporte de llamada, 2026-08-13). El patrón es el mismo: primero
observar con datos, después absorber el proceso. Fase actual = **observar**.

Dos piezas complementarias:

1. **Auto-reporte** — Marketico cuenta si lo hizo todo bien *según él*, o
   dónde falló (los errores internos que hoy son invisibles).
2. **Verificación independiente** — un cron horario comprueba que los
   `meetings` `scheduled` de la DB son exactamente los Appointments de GHL
   para cada proyecto con calendario integrado (`crm_calendars`). Ve lo que
   Marketico ni supo que pasó (webhook nunca recibido, Marketico caído).

## Qué NO hace esta fase (no-goals)

- No alerta (WhatsApp) ni repara (re-disparar bookings perdidos). Primero se
  mide cuánto y qué tipo de drift hay.
- No reemplaza nada de Marketico: el flujo de agendamiento sigue intacto.
- No publica la UI con `publicar_ui.sh` (se puede después sin trabajo extra).

## Componentes

### 1. El emisor — cambio en Marketico

En `webhooks.js`, ruta `/crm`: al resolver o reventar `processBooking`, POST
al Cerebro con el desenlace. Único cambio en Marketico (~20 líneas):

- **Payload**: `{ appointment_id, location_id, estado_cita, contacto: {nombre,
  email, telefono}, start_time, end_time, ok, resultado: {meeting_id, event_id,
  space} | null, error: {mensaje, paso} | null, duracion_ms, booking }` —
  `booking` es el crudo completo, para no perder nada.
- **Fire-and-forget con catch**: si el Cerebro no responde, Marketico loguea y
  sigue. El interceptor jamás rompe el flujo que observa. Timeout corto (~5s).
- **Config**: `CEREBRO_HOOK_URL` + `CEREBRO_HOOK_TOKEN` en el env de
  Marketico. Sin las vars, no reporta (y avisa una vez por consola).
- **Auth**: header `Authorization: Bearer <token>` (secreto compartido).

### 2. El receptor — `viz/hooks.js` (entrypoint nuevo)

Mismo patrón que `publish.js`: entrypoint mínimo, Node stdlib, cero deps npm.

- Puerto **4319 solo en loopback**; pm2 **`viz-hooks`** en `/apps/hermetico`;
  nginx monta `app.ikigaigm.parallelo.ai/hooks/` → `127.0.0.1:4319` (cambio
  nginx one-time, manual por ssh).
- Una ruta: `POST /hooks/crm-resultado`. Valida el Bearer contra
  `HOOKS_TOKEN` (`.env` del servidor). Token inválido/ausente → 401 sin
  cuerpo. Payload inválido → 400. Éxito → inserta y responde 204 rápido.
- Escritura sqlite vía **CLI `sqlite3`** (spawn, SQL por stdin — el mecanismo
  de `pubstore.js`), una transacción por evento. Crea la db/tabla si no
  existen (idempotente).
- `GET /health` para pm2/nginx.

### 3. El log — sqlite `data/sqlite/intercepciones.db` (servidor api)

Estado propio del interceptor, junto a `publicaciones.db`. Nunca datos de la
org — es observabilidad. Tablas:

```sql
crm_webhook (            -- una fila por llamada a /crm que Marketico reportó
  id INTEGER PRIMARY KEY,
  recibido_at TEXT NOT NULL,      -- ISO UTC, lo pone el receptor
  appointment_id TEXT, location_id TEXT, estado_cita TEXT,
  contacto TEXT, email TEXT, telefono TEXT,
  start_time TEXT, end_time TEXT, -- lo que dijo el booking
  ok INTEGER NOT NULL,            -- 1 = processBooking terminó bien
  resultado TEXT,                 -- json {meeting_id,event_id,space} si ok
  error TEXT,                     -- json {mensaje,paso} si falló
  duracion_ms INTEGER,
  payload TEXT NOT NULL           -- el POST completo, json crudo
);
corridas (               -- una fila por corrida del cron de reconciliación
  id INTEGER PRIMARY KEY,
  corrida_at TEXT NOT NULL,
  project_id TEXT, ghl_calendar_id TEXT,
  ventana_desde TEXT, ventana_hasta TEXT,
  ghl_total INTEGER, db_total INTEGER,
  coinciden INTEGER, discrepancias INTEGER,
  estado TEXT NOT NULL DEFAULT 'ok',  -- 'ok' | 'error' (GHL caído, etc.)
  detalle TEXT                        -- mensaje si estado='error'
);
drift (                  -- una fila por discrepancia encontrada en una corrida
  id INTEGER PRIMARY KEY,
  corrida_id INTEGER NOT NULL REFERENCES corridas(id),
  tipo TEXT NOT NULL,    -- 'falta_en_db' | 'sobra_en_db' | 'horas_difieren'
  appointment_id TEXT, meeting_id TEXT,
  detalle TEXT           -- json: horas de cada lado, título, contacto…
);
```

El drift "vigente" es el de la **última corrida** de cada calendario — las
corridas anteriores son historia, no cola.

### 4. El cron de reconciliación — `bash/intercepciones/reconciliar_agenda.sh`

Corre **en el servidor api** (tiene `.env` con `DATABASE_URL`; los tokens GHL
viven en `project_crm_configs`). pm2 cron **`intercepciones-cron`**, cada 1h.

Por cada fila **activa** de `crm_calendars` (hoy: Calendario Premium
Mastermind → David Guerrero):

1. **Lado GHL**: Appointments del calendario en la ventana (default: −1 día a
   +30 días) vía **`bash/ghl/appointments.sh`** (nuevo, read-only, mismo
   patrón sonda de `bash/ghl/`: GET `calendars/events` con
   `locationId`+`calendarId`+`startTime`/`endTime` epoch millis, token por
   stdin, se niega en forks copiloto).
2. **Lado DB**: `meetings` con `meeting_type='call'` y `status='scheduled'`
   del proyecto en la misma ventana (más las `cancelled` para clasificar).
3. **Compara por `meetings.event_id` = appointmentId**:
   - `falta_en_db` — GHL lo tiene (booked/confirmed), nosotros no. El caso grave.
   - `sobra_en_db` — `scheduled` en DB pero cancelado/ausente en GHL.
   - `horas_difieren` — reagenda que no llegó.
4. ⚠️ **Normalización obligatoria**: `scheduled_start_time` guarda hora
   **Bogotá etiquetada como UTC** (quirk verificado 2026-08-13; patrón
   correcto en `bash/closers/agenda.sh`) — se lee el reloj literal
   (`AT TIME ZONE 'UTC'`) y se compara contra la hora Bogotá real del
   Appointment GHL. Sin esto, todo daría drift de 5h.
5. Escribe `corridas` + `drift` en la sqlite, una transacción. Si GHL no
   responde, la corrida queda `estado='error'` — **nunca** se registra como
   "0 appointments" (eso inventaría drift masivo).

El script es idempotente y corrible a mano (`--dry-run`, `--json`,
`--ventana`), como todo `bash/`.

### 5. Consulta desde el cerebro — `bash/intercepciones/`

Scripts read-only, `--json`, patrón `publicar/`: **si
`data/sqlite/intercepciones.db` existe local se lee directo; si no, por ssh**
(así el mismo script sirve en el servidor api y en el cerebro).

- `log.sh [--desde D] [--solo-errores] [--limit N]` — el log del webhook.
- `drift.sh [--corrida N] [--historia]` — última corrida por calendario + sus
  discrepancias; `--historia` lista corridas.
- `resumen.sh` — un objeto: KPIs 24h/7d del webhook (recibidos, ok, fallos) +
  última corrida por calendario (totales, discrepancias, freshness).

### 6. La UI — viz «Intercepciones»

Componente de página nuevo `intercepciones` (torre de composición, bloques de
kit.js), spec sembrado en `viz/specs/org/`. Fuentes nuevas en `SOURCES`
(`viz/lib/datasources.js`), cada una → su script de `bash/intercepciones/`:

- `intercepciones_resumen` (object) → `resumen.sh`
- `intercepciones_log` → `log.sh`
- `intercepciones_drift` → `drift.sh`

Layout: fila de KPIs (recibidos/ok/fallos 24h · drift vigente ·
freshness de la última corrida — con grito si >2h), tabla del log reciente
(fallos resaltados, detalle del error visible), sección de drift vigente por
calendario (tipo, appointment, contacto, horas de cada lado). Tokens
semánticos, nunca `--pal-*`. Read-only puro — sin write-path (regla: viz es
visor).

## Manejo de errores (resumen)

| Falla | Comportamiento |
|---|---|
| Cerebro caído cuando Marketico reporta | Marketico loguea y sigue; se pierde ese auto-reporte, el cron lo cubre |
| Token inválido en el hook | 401, no se escribe nada |
| GHL caído durante el cron | Corrida `estado='error'`, sin drift inventado |
| sqlite bloqueada | Reintento corto; el hook responde 204 igual (el payload se loguea a stderr como último recurso) |
| Vars de env ausentes en Marketico | No reporta, warn una vez |

## Testing

1. **Receptor local**: `node viz/hooks.js` + curl con token bueno/malo/payload
   inválido → 204/401/400 y fila correcta en la sqlite.
2. **Emisor**: en dev de Marketico, disparar `/crm` con `booking.sample.json`
   apuntando `CEREBRO_HOOK_URL` a localhost → verificar payload completo en
   ambos desenlaces (ok y error forzado).
3. **Reconciliador**: correr a mano contra el calendario de David Guerrero con
   `--dry-run --json`; verificar la normalización horaria contra 2-3 meetings
   conocidos (cero falsos `horas_difieren`).
4. **UI**: render con datos reales del viz local (`npm run viz`).

## Despliegue (orden)

1. Código al servidor api: `bash/publicar/desplegar.sh` (extender para
   reiniciar también `viz-hooks`, o pm2 start inicial manual).
2. nginx: `location /hooks/` → `127.0.0.1:4319` (one-time, ssh).
3. `HOOKS_TOKEN` en `.env` del servidor; pm2 `viz-hooks` + `intercepciones-cron`.
4. Marketico: deploy del cambio en `webhooks.js` con las dos vars de env.
5. Verificar con un booking real (o test) end-to-end.

## Decisiones tomadas en la conversación

- Entrada: **Marketico reenvía el resultado** (no un segundo webhook desde GHL).
- Hosting: **entrypoint nuevo** (`viz/hooks.js`), no dentro de `publish.js`.
- Log: **sqlite en el servidor api**, no Postgres ni JSONL.
- Discrepancias: **registrar y reportar** — sin alertas ni reparación aún.
- UI: **sí entra en esta fase** (decisión explícita del 2026-08-16).

# Google Calendar desde el Cerebro — leer, crear y actualizar eventos

**Fecha**: 2026-08-19 · **Estado**: diseño aprobado en conversación

## Contexto y propósito

El Cerebro no tiene credenciales de Google por diseño: el backend Meetico
(`/projects/google-meet-express`, desplegado en `/apps/meetico`) es el dueño de
la identidad y `bash/google/` habla con él (contrato `apis/mkt/drive.openapi.json`).
Hoy esa superficie cubre solo Drive; Calendar existe completo en
`src/services/googleService.js` (`listCalendars`, `listEvents`, `createEvent`,
`updateEvent`, `deleteEvent`, `findEventByExtendedProperty`) pero **ninguna ruta
HTTP lo expone** — solo se usa internamente (processBooking, webhooks).

Objetivo: acceso **genérico** a Calendar (calendarId como parámetro, default el
calendario de llamadas `mkt_primary`) para reusar en composición de flujos.
Primer uso real candidato: el evento de Jefferson Lucio que quedó en 13-ago
tras la reagenda que el webhook nunca trajo (meeting `38f17149`, reparado en DB
el 2026-08-18; la mitad de Google Calendar quedó pendiente).

Decisiones tomadas en conversación (2026-08-19):

- Superficie **genérica**, no solo el calendario de llamadas.
- **Sin DELETE** — leer, crear, actualizar; borrar no entra.
- Enfoques descartados: credenciales Google propias del Cerebro (rompe la
  identidad única) y el conector MCP de claude.ai (identidad personal, no
  compone en flujos bash).

## Componentes

### 1. Marketico — `src/routes/calendar.js` (nuevo)

Montado en `/calendar`, patrón idéntico a `drive.js`: `requireAuth` +
`requireGoogleAuth` en cada ruta.

| Endpoint | Servicio | Notas |
|---|---|---|
| `GET /calendar/calendars` | `listCalendars` | id, summary, timeZone, primary |
| `GET /calendar/events?calendarId=&timeMin=&timeMax=` | `listEvents` | sin `calendarId` → default vía `getDefaultCalendar` (mkt_primary). `timeMin`/`timeMax` ISO 8601. |
| `GET /calendar/events/:eventId?calendarId=` | `getEvent` (nuevo, ~8 líneas: `calendar.events.get`) | hoy solo existe inline en `updateEvent` |
| `POST /calendar/events` | `createEvent` | body: `{calendarId?, summary, description?, startTime, endTime, timezone, attendees?}` |
| `PATCH /calendar/events/:eventId` | `updateEvent` | **parcial**: el service hace GET previo y solo pisa los campos enviados. `startTime`/`endTime` requieren `timezone`. |

- `attendees` viaja como array de `{email}` (el formato que `createEvent` pasa
  directo al API de Google).
- `extendedProperties` y `conferenceData` NO se exponen en v1 (YAGNI; el
  service los soporta si hacen falta después).
- Errores: mismo manejo que `drive.js` (status del error de Google o 500 con
  `{message}`).

### 2. Contrato — `apis/mkt/calendar.openapi.json` (hermetico)

OpenAPI de los 5 endpoints, gemelo de `drive.openapi.json`. Es el documento
que el Cerebro trata como fuente de verdad de la superficie.

### 3. Cerebro — 5 scripts en `bash/google/`

Misma `lib/` y mismos dos modos (copiloto vía forja-proxy / cerebro directo
con `MEETICO_BASE`+`MEETICO_JWT_TOKEN`). Todos aceptan `--json` y `-h`.

| Script | Uso |
|---|---|
| `calendar_ls.sh` | Calendarios de la cuenta (id, nombre, tz, primary). |
| `event_ls.sh [--calendar ID] [--desde D] [--hasta D] [--limit N]` | Eventos en ventana. Default: hoy → +14 días, fechas Bogotá. |
| `event_show.sh <event-id> [--calendar ID]` | Un evento: título, horas (mostradas en Bogotá), invitados, estado, link Meet si tiene. |
| `event_create.sh --titulo T --inicio 'YYYY-MM-DD HH:MM' --fin 'YYYY-MM-DD HH:MM' [--desc D] [--invitado email]… [--calendar ID] [--tz TZ]` **[WRITE→Google]** | Crear evento. `--dry-run` imprime el payload sin llamar. |
| `event_update.sh <event-id> [--titulo T] [--inicio H --fin H] [--desc D] [--invitado email]… [--calendar ID] [--tz TZ]` **[WRITE→Google]** | Update parcial. Imprime **antes/después** (GET previo + GET posterior). `--dry-run`. |

Convenciones:

- Horas **entran en reloj Bogotá** y viajan como `dateTime` +
  `timeZone: America/Bogota` (`--tz` lo cambia). ⚠️ Aquí NO aplica el quirk de
  `meetings` — Google Calendar maneja timezone de verdad.
- `--invitado` es repetible; reemplaza la lista completa en update (semántica
  del service: `attendees` enviado = lista nueva).
- En `event_update.sh`, `--inicio` y `--fin` van juntos (mover solo un extremo
  casi siempre es un error; el service además exige timezone con cada uno).

### 4. Política del dominio

- `bash/google/` deja de ser "read-only" a secas: README y CLAUDE.md pasan a
  decir **"read-only salvo los `[WRITE→Google]` marcados"** — la convención
  `[WRITE]` del resto del repo.
- ⚠️ **`sendNotifications: true` está horneado en el service**: crear o mover
  un evento con invitados **les manda email**. Se deja así (en el caso real —
  reparar el evento de Jefferson — avisar al lead es lo correcto) y se
  documenta en grande en los `-h` de los dos scripts WRITE.
- Copiloto: el forja-proxy aún no mapea `/v1/mkt/calendar` — los scripts
  fallan con el mensaje claro «el backend aún no expone …», igual que hizo
  Drive en su momento.

## Manejo de errores

| Falla | Comportamiento |
|---|---|
| Backend sin el endpoint (proxy o deploy viejo) | «el backend aún no expone …» y exit ≠ 0 |
| Google rechaza (evento inexistente, calendario ajeno) | El backend propaga el status; el script muestra el `message` |
| `--inicio` sin `--fin` (o viceversa) en update | El script se niega antes de llamar |
| Update de evento cancelado | Se permite (Google lo permite); el antes/después lo hace visible |

## Testing

1. **GETs en vivo**: `calendar_ls.sh`, `event_ls.sh` contra el calendario real
   — verificar que los eventos de las llamadas conocidas aparecen con la hora
   Bogotá correcta.
2. **Ciclo write controlado**: crear evento `[test]` en el calendario default
   sin invitados → `event_show.sh` → `event_update.sh` moviendo la hora →
   verificar antes/después → dejarlo documentado (no hay delete; el evento de
   prueba se archiva a mano o se ignora).
3. **Dry-runs**: payload correcto sin efecto.

## Despliegue (orden)

1. Marketico: `calendar.js` + `getEvent` en el service, commit, deploy en
   `/apps/meetico` (git pull + pm2 restart).
2. Hermetico: contrato + scripts + README/CLAUDE.md, commit.
3. Prueba end-to-end (Testing 1-2).
4. Primer uso real: reparar el evento de Google Calendar de Jefferson
   (13-ago → 21-ago 17:00 Bogotá), con confirmación previa de Santiago porque
   notifica al lead.

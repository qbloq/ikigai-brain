# Mesa de Despacho — Fase C (aprobación y ejecución)

**Fecha**: 2026-08-12 · **Estado**: en construcción
**Contexto**: continúa [2026-08-12-mesa-despacho-fase-b-design.md](2026-08-12-mesa-despacho-fase-b-design.md).
**Decisión de Santiago**: la ejecución del despacho es **salida real por
WhatsApp** (no solo registro) — vía plantillas de Meta, la única forma legal
de iniciar conversación fuera de la ventana de 24h.

## El ciclo completo

```
Iki captura recado (memoria, RECADO: + PROPUESTA)
  → sync_despachos.sh [WRITE local]  — cosecha a sqlite mesa_despacho
  → Mesa de Despacho (viz)           — muestra cola con estados
  → humano aprueba/rechaza           — botón UI → despacho_mark.sh [WRITE local]
  → despachar.sh [WRITE→WhatsApp]    — DESDE LA CONVERSACIÓN (patrón
                                       merge_from_cruce): plantilla al
                                       destinatario, registra wamid
```

## Piezas

- **Plantilla Meta `recado_cerebro`** (id 1831771134860100, WABA 690499003502578
  «Feria Local», UTILITY es_CO, creada 2026-08-12 vía API — el token System
  User «Parallelo System User» SÍ administra plantillas): «Hola {{1}}, soy
  Iki, el asistente del equipo de Ikigai. {{2}} te dejó un recado: {{3}} …».
  ⚠️ El destinatario ve el nombre verificado del número: **«Feria Local -
  Ventas»** — la plantilla se presenta como Iki/Ikigai para mitigar la
  confusión de marca; renombrar el display name del número es tarea aparte en
  Meta.
- **sqlite local `mesa_despacho`** (`data/sqlite/`): tabla `despachos`
  (recado_id UNIQUE = memories.id de Iki, campos del canónico + estado
  pendiente|aprobado|rechazado|ejecutado|fallido + nota/marcado_at/
  ejecutado_at/wamid/destino_numero) y tabla `directorio` (nombre→número
  E.164 — el resolvedor de destinatarios; crece por conversación).
- **Scripts `bash/agentes/`**: `sync_despachos.sh` (cosecha; congela filas
  decididas, nunca borra, jamás escribe en DBs de zeroclaw),
  `despachos.sh` (RO, fuente viz `iki_despachos`), `despacho_mark.sh`
  (marca UNA fila, guardrail solo-pendientes — el único write detrás del
  botón de la Mesa), `despachar.sh` (ejecuta aprobadas: resuelve directorio →
  envía plantilla → wamid/estado; `--dry-run`; token de $WABA_TOKEN / .env /
  config zeroclaw mientras esté inline).
- **UI**: la cola de la Mesa lee `iki_despachos` (estados como badges +
  botones Aprobar/Rechazar en pendientes, patrón del Merge del cruce);
  **ejecutar NO tiene botón** — corre desde la conversación con el cerebro.

## Guardrails

- Solo filas `pendiente` aceptan marca; toda decisión se congela.
- El sync jamás reescribe filas decididas ni toca las DBs del daemon.
- `despachar.sh` solo envía filas `aprobado`; destinatario sin número en
  `directorio` queda anotado, no falla el lote.
- Limpieza hecha: el recado de prueba `4a717db9` (Mari/informe, ficticio)
  quedó **rechazado** con nota — nunca se ejecutará.

## Criterio de aceptación

Aprobar la fila real de Pablo (n=1) en la Mesa → `despachar.sh` envía la
plantilla al número de Pablo (requiere: plantilla APPROVED por Meta + número
en `directorio`) → estado `ejecutado` con wamid visible en la Mesa → Pablo
recibe el recado en su WhatsApp.

## Deuda conocida

- El token WABA se lee del config de zeroclaw mientras siga inline; al
  re-cifrarlo, mover a `WABA_TOKEN=` en `.env`.
- Display name «Feria Local - Ventas» en el número (renombrar en Meta).
- La cosecha es manual (`sync_despachos.sh`) — candidata a cron/Routine.

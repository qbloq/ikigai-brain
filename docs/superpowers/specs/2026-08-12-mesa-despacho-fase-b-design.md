# Mesa de Despacho — Fase B (observabilidad)

**Fecha**: 2026-08-12 · **Estado**: en construcción (diseño aprobado en
conversación; continúa el spec de identidad de Iki)
**Contexto**: [2026-08-12-identidad-iki-design.md](2026-08-12-identidad-iki-design.md)
— fases B/C acordadas ahí. Alcance de aprobación decidido: **solo el
despacho**, nunca las respuestas conversacionales.

## Hallazgo que reformó el diseño

`~/.zeroclaw/data/sessions/sessions.db` está **vacía**: zeroclaw no persiste
ahí las conversaciones de canal (aparentemente solo sesiones gateway/ACP). El
rastro observable de Iki vive en su **memoria** (`data/memory/brain.db`,
tabla `memories`):

- `category='conversation'` — el autosave guarda **el lado del usuario**
  (keys `whatsapp_<numero>_<uuid>`, `user_msg_<uuid>` para CLI). Las
  respuestas del agente NO se persisten hoy.
- `category='daily'` — los recados (Iki eligió keys semánticas
  `recado_<fecha>_<tema>`), con el formato canónico en `content`.

Por eso la Mesa v1 no es «conversaciones master-detail» sino **cola de
recados + entradas recientes**. Si algún día zeroclaw persiste historial de
canal completo, se re-evalúa.

## Piezas

**Dominio `bash/agentes/`** (read-only, `sqlite3 -readonly`/URI `mode=ro`
sobre `${ZEROCLAW_DIR:-~/.zeroclaw}`):

- `recados.sh [--para FRAG] [--limit N] [--json]` — memorias `RECADO:` con el
  formato canónico parseado a columnas
  `{id,fecha,sesion,de,para,que,urgencia,contexto,propuesta,texto}`. El campo
  clave es `propuesta` (lo que la Fase C someterá a aprobación) y el `id`
  corto es el handle que el humano dicta.
- `entradas.sh [--limit N] [--json]` — memorias `conversation` como
  `{id,fecha,canal,remitente,texto}` (canal/remitente parseados de la key).

**Viz**: fuentes `iki_recados` + `iki_entradas` (sin cache — vista viva),
página `mesa-despacho` (cola de recados como tarjetas con la PROPUESTA
destacada y el id corto visible + entradas recientes), spec seed en
`viz/specs/org/mesa-despacho.json`.

## Criterio de aceptación

La UI renderiza los recados reales existentes (Pablo, Mari) con sus
propuestas y sus ids cortos, y las entradas muestran los mensajes de WhatsApp
recibidos. Todo por la cadena `SOURCES → bash --json`, cero SQL en el viz.

## Notas para la Fase C

- La marca de aprobación NO puede escribirse en las DBs de zeroclaw (son del
  daemon). Vive en una sqlite local del cerebro (`data/sqlite/`, patrón
  `pm_platform.cruce`): fila por recado (join por `memories.id`), campos
  `aprobado/resuelta/resolucion`, marcada vía script tipo `cruce_mark.sh`
  gobernado desde la UI, ejecutada por el cerebro sobre filas aprobadas.
- Antes de ejecutar despachos reales: **purgar el recado de prueba**
  `4a717db9` (Mari/informe DG — ficticio, 2026-08-12 20:46).

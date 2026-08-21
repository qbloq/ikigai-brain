# bash/vturb — el video en la fuente

Sonda **read-only** contra el VTurb Analytics API (`https://analytics.vturb.net`),
el proveedor de video de las VSLs (`projects.video_provider_key='vturb'`).
Marketico proxya esta misma fuente para su funnel; este dominio le habla
directo, con el patrón de `bash/ghl/`: medir y mirar la fuente, no ser una
segunda vía de ingesta. Nada aquí escribe en ninguna parte (el API tampoco
expone mutaciones).

## Scripts

| Script | Para qué |
|--------|----------|
| `auth_status.sh [--json]` | Qué proyectos tienen integración VTurb y si el token responde (sonda `GET /players/list`), con el conteo de players en la fuente. |
| `videos.sh --project N [--seleccionados] [--json]` | Catálogo de players en vivo (id, nombre, duración, `pitch_time`, creado) con columna `sel` marcando los curados en `project_vturb_video_selections`; `--seleccionados` lista solo esos, desde la DB (ahí vive la duración, insumo de retención). |
| `analitica.sh --project N [--video ID [--duracion S]] [--from D] [--to D] [--json]` | El funnel de video por seleccionado: impresiones → plays (tasa de play) → retención 25/50/75% → % pasó el pitch → % terminó → clicks CTA. Ventana default: mes actual (Bogotá). `--json` agrega el histograma completo, `average_watched_time` y `engagement_rate`. |

## Credenciales — la política

Como en GHL, los tokens viven **en la base, en claro**:
`project_vturb_video_configs.api_key_encrypted` (el nombre de la columna
miente), uno por proyecto. La cerca es la misma de `bash/ghl/`:

- **solo cerebro**: el lib se niega a correr en un fork con `copilot.json`;
- **solo consultas**: el API usa POST para sus dos endpoints de stats
  (`/sessions/stats`, `/times/user_engagement`) porque los criterios viajan en
  el body — son *fetches*. La cerca aquí es «solo consultas», no «solo GETs»;
  cualquier endpoint que ESCRIBA queda fuera, sea cual sea el verbo;
- **el token jamás toca argv**: viaja a curl por stdin (`--config -`).

Auth del API: headers `X-Api-Token` + `X-Api-Version: v1`. Referencia:
<https://vturb.gitbook.io/analytics-api/pt>.

## Hallazgos (verificados 2026-08-20, con datos reales)

1. **`grouped_timed` es un HISTOGRAMA de abandono, no una curva de
   supervivencia.** Cada bucket dice cuántos espectadores PARARON ahí (el
   bucket en duración+1 son los que terminaron, y calza exacto con
   `total_finished_*`). Pruebas: la suma del histograma ≈ plays únicos de la
   ventana (3123 vs 3127) y el promedio reconstruido reproduce el
   `average_watched_time` del API (203.2 vs 203.35). La retención en t es la
   cola acumulada: `sum(buckets ≥ t) / total`.
   ⚠️ **El normalizador de Marketico** (`vturbVideoProvider.normalizeRetention`)
   lo lee como supervivencia — bug vivo en las métricas de retención de su
   funnel (denominador = los que rebotaron en el segundo 0, y «viendo en t» =
   los que pararon exactamente en t). Reportable a Marketico.
2. **`total_viewed_*` son IMPRESIONES del player, no vistas del video** —
   siempre ≥ `total_started_*` (los plays). `play_rate` del API =
   started/viewed. Marketico las etiqueta `uniquePlays`/`uniqueViews`, que
   invita a leerlas al revés.
3. **La ventana de fechas SÍ aplica al engagement.** El comentario en el
   código de Marketico teme que `/times/user_engagement` sea all-time; hoy no
   lo es (la suma del histograma calza con los plays de la ventana, no con el
   total histórico).
4. **Los dos proyectos configurados (Andrea, David) responden con el mismo
   catálogo de 22 players** — todo apunta a una sola cuenta VTurb compartida;
   la separación por proyecto es de Marketico, no de VTurb.

Fechas: VTurb pide `'YYYY-MM-DD HH:MM:SS'` + `timezone`; estos scripts mandan
`America/Bogota` (la zona de la casa), a diferencia del proxy de Marketico que
manda reloj UTC.

El contrato de la superficie **proxy** (la de Marketico, con estos mismos
datos ya normalizados) vive en el cerebro: `apis/mkt/vturb-video.openapi.json`
(artefacto de operador — `apis/` no viaja a los copilotos).

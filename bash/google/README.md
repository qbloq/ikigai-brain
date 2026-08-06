# bash/google/ — Google Drive vía el API mkt (read-only)

Scripts para leer el Drive de la org a través del **backend Meetico**
(contrato: `apis/mkt/drive.openapi.json`),
con curl + python3 stdlib. **Read-only**: nunca crean, editan ni borran nada.

## Auth — las credenciales de Google viven en el backend

Aquí no hay token de Google, ni client_secret, ni acceso a la base de datos:
el backend es el dueño de la identidad Google de la org (la refresca solo).
`lib/common.sh` elige el modo por el `.env`:

| Modo | Credenciales | Camino |
|------|--------------|--------|
| **copiloto** | `CEREBRO_API` + `CEREBRO_TOKEN` | forja-proxy (`/v1/mkt/…`) — inyecta el JWT de la org y audita cada llamada |
| **cerebro** | `MEETICO_BASE` + `MEETICO_JWT_TOKEN` | directo al backend (mismo par que usa el viz para el bind de artefactos) |

## Scripts

| Script | Para… |
|--------|-------|
| `auth_status.sh [--json]` | Modo, base y probe en vivo contra el backend. |
| `drive_ls.sh [--folder ID\|url\|nombre] [--q FRAG] [--type doc\|sheet\|slide\|folder\|pdf] [--limit N] [--json]` | Listar (live por carpeta) y buscar (índice global del backend). |
| `drive_recent.sh [--days N] [--from D] [--to D] [--modified] [--docs] [--type T] [--folder FRAG] [--owner FRAG] [--exclude FRAG] [--with-folders] [--by day\|type\|owner\|folder] [--limit N] [--json]` | Lo último que **entró o cambió**, por fecha. Imprime siempre la frescura del índice a stderr. |
| `drive_file.sh <id\|url> [--json]` | Metadata de un archivo. |
| `doc_read.sh <id\|url> [--out F] [--txt] [--json]` | Un Google Doc como **Markdown** (`?format=markdown`). |
| `sheet_read.sh <id\|url> [--limit N] [--raw] [--json]` | Primera pestaña de un Sheet como tabla (CSV del backend; fila 1 = header). |
| `sheet_show.sh <id\|url> [--json]` | Metadata del Sheet (pestañas: aún no expuestas por el backend). |

Todos aceptan ids crudos o URLs de docs.google.com / drive.google.com.

## Estado del backend (2026-07-23)

Desplegado y verificado: `/drive/contents` · `/drive/files/:id` · `/content`
(con `?format=markdown` — Docs llegan como markdown real) · `/resolve` ·
`/drive/index` + `/stats` (~19k items indexados; la búsqueda es sobre el
índice, así que un archivo recién creado tarda en aparecer — la navegación
por carpeta sí es live). Pendiente en Meetico: campos ricos en
`/drive/files/:id` (size/modified/owners/**parents** — sin parents el «↑» del
explorador no navega) y pestañas de Sheets.

### El índice es un caché que se refresca A MANO — y eso ya mordió

Lo llena `src/scripts/indexDrive.js` en el backend: un barrido de `files.list`
que hace upsert a `drive_index` y poda lo que ya no existe. **No hay cron, ni
PM2, ni endpoint que lo dispare.** El 2026-08-04 el índice llevaba desde el
27-jul sin correr: preguntar «¿qué entró estas dos semanas?» devolvía silencio
para 8 días con actividad real. Un caché viejo no responde «no hubo nada» — no
responde, y se lee igual. Por eso `drive_recent.sh` imprime SIEMPRE la frescura
y grita pasadas 48h. La cura de raíz es un `POST /drive/index` (como el que ya
existe para Notion) o un cron; ninguno de los dos está hecho.

### Cambio de contrato 2026-08-04 (pendiente de desplegar)

`GET /drive/index` no tenía filtro ni orden por fecha, y **sin `search` ni
`parentId` respondía solo la RAÍZ** (~1.1k de 17.7k items) — una trampa: se lee
como si fuera el drive entero. Se añadieron `createdAfter`/`createdBefore`/
`modifiedAfter`/`modifiedBefore` (cualquiera de ellos ensancha el alcance a
todo el drive) y `sort=<campo>[:asc|desc]` con whitelist, más
`GET /drive/index/status` (items + `synced_at` + `age_hours`).

`drive_recent.sh` **exige** ese despliegue: Express ignora los query params que
no conoce, así que contra el backend viejo el filtro por fecha se evaporaría y
la respuesta sería la raíz sin aviso. El script comprueba `/drive/index/status`
y se niega a correr si no está, en vez de devolver un subconjunto disfrazado.

Para probar un cambio del backend en local, el entorno gana sobre `.env`:
`MEETICO_BASE=http://127.0.0.1:5099 bash/google/drive_recent.sh …`

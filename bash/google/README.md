# bash/google/ — Google Drive vía el API mkt (read-only)

Scripts para leer el Drive de la org a través del **backend Meetico**
(contrato: [apis/mkt/drive.openapi.json](../../apis/mkt/drive.openapi.json)),
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

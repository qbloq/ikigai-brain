# bash/google/ — Google Drive + Docs + Sheets (read-only)

Scripts para leer el Drive de la cuenta `ikigaigrowthmarketing@gmail.com`
vía HTTP (curl + python3 stdlib, sin npm deps). **Read-only**: nunca crean,
editan ni borran nada en Google.

## Auth — el token vive en la DB

No hay API key ni client_secret local. El OAuth `access_token` (+ refresh)
está en `ikigaigm.identities` con `provider='google'` — la fila que el
backend (bot de meetings) mantiene fresca al usarla. `lib/common.sh` la lee
con una conexión Postgres read-only y expone `gapi` (curl autenticado).

- **Scope**: `…/auth/drive` completo → cubre Drive y los exports; también
  autorizaría los APIs de Sheets/Docs (ver caveat abajo).
- **Token vencido**: los scripts fallan con mensaje claro. No podemos
  refrescarlo localmente (no hay client_secret); se refresca cuando el
  backend lo usa, o re-autenticando Google en la app.
- La fila `provider='google1'` es vieja (expiró 2025-10) — se ignora.
  `GOOGLE_IDENTITY_PROVIDER` overridea cuál fila usar.

## Scripts

| Script | Para… |
|--------|-------|
| `auth_status.sh [--json]` | Ver la identidad activa: email, scopes, vigencia (DB + tokeninfo en vivo). |
| `drive_ls.sh [--folder ID\|url\|nombre] [--q FRAG] [--type doc\|sheet\|slide\|folder\|pdf\|MIME] [--trashed] [--limit N] [--json]` | Listar/buscar archivos, más recientes primero. `--folder` acepta fragmento de nombre único. |
| `drive_file.sh <id\|url> [--json]` | Metadata de un archivo (nombre, mime, dueño, fechas, link). |
| `doc_read.sh <id\|url> [--out F] [--txt] [--raw]` | Un Google Doc como **Markdown** (Drive export). `--out` escribe archivo. |
| `sheet_show.sh <id\|url> [--json]` | Título + pestañas de un Sheet (requiere Sheets API — ver caveat). |
| `sheet_read.sh <id\|url> [--tab N] [--range A1] [--limit N] [--raw] [--json]` | Valores de una pestaña como tabla (fila 1 = header). `--json` = array de objetos. |

Todos aceptan ids crudos o URLs de docs.google.com / drive.google.com.

## Caveat — APIs deshabilitados en el proyecto OAuth

El client OAuth pertenece al proyecto GCP `564990031857`, que solo tiene el
**Drive API** habilitado. Los APIs de **Sheets** y **Docs** están apagados:

- `sheet_read.sh` cae solo a **Drive export CSV** (primera pestaña, sin
  `--tab`/`--range`) y lo avisa por stderr.
- `sheet_show.sh` (pestañas) y `doc_read.sh --raw` fallan con instrucción.
- Para el modo completo: habilitar `sheets.googleapis.com` (y opcionalmente
  `docs.googleapis.com`) en ese proyecto — un click de quien tenga acceso a
  la consola de Google Cloud.

La lectura de Docs no sufre: el export a Markdown va por Drive.

# Pedido a Marketico — crear Google Docs desde el backend de Drive

**Fecha:** 2026-08-21 · **Quién pide:** Cerebro / Ikigai (Santiago) · **Para:** equipo Marketico
**Superficie afectada:** el backend Meetico de Drive (`apis/mkt/drive.openapi.json`)
**Tamaño estimado:** chico — la identidad Google, el token y el refresh ya viven ahí; falta un POST.

## 1. Qué pasa hoy

La capa de Drive del backend es **solo lectura** (+ `PATCH` rename y el refresco
del índice): `GET /drive/contents`, `/drive/files/{id}`, `/content`, `/download`,
`/drive/index`. El Cerebro produce entregables que el equipo consume en Google
Docs —el primero concreto: el reporte de distribución de ventas por programa
antes/después de los cambios de precio, pedido por Lorenzo en la alineación DG
del 2026-08-19 (tarea `332c414a`)— y hoy no hay forma de dejarlos en el Drive
de la org **con la identidad de la org**: la regla es que nada de la operación
pasa por cuentas personales ni por conectores ajenos al workspace.

## 2. Qué se pide

Un endpoint de creación, mismo patrón y misma autenticación que los GET:

```
POST /drive/files
  body: { parentId, title, contentMimeType: "text/html" | "text/markdown" | "text/plain",
          content (utf-8), convertTo?: "google-doc" | "google-sheet" (default: google-doc
          para text/*), share?: [{ emailAddress, role: reader|commenter|writer }] }
  → 201 { fileId, viewUrl, mimeType, parentId }
```

- `text/html` basta: Google convierte HTML a Doc conservando títulos, tablas y
  negritas (el Cerebro escribe Markdown y lo convierte a HTML antes de enviar).
- `share` opcional, para que el entregable llegue a quien lo pidió sin un paso
  manual; si no viene, hereda los permisos de la carpeta.
- Sería deseable también `PUT /drive/files/{id}/content` (reemplazar contenido
  de un Doc existente) para **re-publicar** un reporte que cambia con cada corte
  — los reportes del Cerebro son consultas vivas, no fotos.

## 3. Qué NO se pide

- Nada de borrar ni mover fuera de la carpeta destino. Escribir en una carpeta
  declarada por el llamador, no en la raíz.
- Nada de Gmail/Calendar — solo Drive/Docs.

## 4. Cómo lo usaría el Cerebro

`bash/google/doc_create.sh <parent-folder> --title T --from archivo.md [--share email:rol]`
**[WRITE]**, la primera escritura real en `bash/google/` (hoy la única es el
refresco del índice), con `--dry-run` y `--json`, y auditada como el resto vía
el proxy. El reporte de `332c414a` quedaría en la carpeta «1. David Guerrero»
compartido con Lorenzo y Luis David.

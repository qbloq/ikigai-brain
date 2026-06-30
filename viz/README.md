# viz — UIs por demanda

Servidorcito HTTP (Node stdlib, **cero dependencias npm**) que genera páginas web
por demanda: **TailwindCSS** para estilos + **Datastar** para reactividad sobre
**SSE**. Los datos salen de los scripts read-only de [`bash/`](../bash) (vía
`--json`), nunca de SQL ad-hoc.

```bash
npm run viz                 # http://localhost:4317   (PORT=… para cambiar)
```

## Modelo

Cada página es una **UI persistida** con un ID, accesible por URL. Una UI es un
*spec* (no HTML congelado), así que siempre refleja los datos actuales:

```json
{ "id": "4cb067d7", "name": "Tareas abiertas",
  "component": "table", "source": "tasks",
  "params": { "open": "1", "limit": "50" } }
```

Se guardan como archivos en [`store/`](store) (ignorado por git; se re-siembra
solo en el primer arranque).

## Layout (master-detail)

- **Panel izquierdo** (`#ui-list`): lista de UIs guardadas + formulario "Nueva UI".
- **Panel derecho** (`#pane`): renderiza la UI seleccionada.

Datastar pide el fragmento por SSE (`@get('/ui/<id>')`) y lo pega en el DOM —
sin recargar la página.

## Rutas

| Ruta | Qué hace |
|------|----------|
| `GET /` | Shell master-detail. `?ui=<id>` abre una UI activa. |
| `GET /u/:id` | Página standalone de una sola UI (URL directa). |
| `GET /ui/:id` | SSE: patch de `#pane` (+ estado activo de `#ui-list`). |
| `POST /ui` | Crea una UI desde el form "Nueva UI" y refresca el DOM. |
| `GET /health` | Liveness. |

## Piezas

| Archivo | Rol |
|---------|-----|
| [`server.js`](server.js) | HTTP + ruteo. |
| [`lib/datasources.js`](lib/datasources.js) | Único puente a `bash/ --json`. Whitelist de fuentes y flags. |
| [`lib/components.js`](lib/components.js) | Render parametrizable (hoy: `table`, columnas inferidas). |
| [`lib/store.js`](lib/store.js) | Persistencia de UIs (archivos JSON). |
| [`lib/html.js`](lib/html.js) | Shell + panel izquierdo. |
| [`lib/sse.js`](lib/sse.js) | Protocolo Datastar 1.0 (`datastar-patch-elements`). |

## Extender

- **Nueva fuente de datos**: agrega una entrada a `SOURCES` en `datasources.js`
  (script + flags permitidos). Aparece sola en el `<select>` de "Nueva UI".
- **Nuevo componente** (form, cards, stats-bar…): otro caso en `renderPane()`
  de `components.js`, seleccionado por `ui.component`.

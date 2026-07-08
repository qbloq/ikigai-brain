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
solo en el primer arranque). **Archivar** una UI es un soft-hide: solo estampa
`archived_at` en el spec (el archivo y su URL `/u/:id` siguen existiendo) y la
mueve a la sección plegable «Archivadas» del panel izquierdo, desde donde se
restaura con un clic. Nada se borra desde la UI.

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
| `POST /ui/:id/archive` · `/unarchive` | Archiva/restaura una UI (soft-hide vía `archived_at`; nunca borra) y re-pinta `#ui-list`. |
| `GET /health` | Liveness. |

## Piezas

El render está organizado como la **torre de composición**
([docs/deltas-architecture.md](../docs/deltas-architecture.md)):
kernel → bloques → patrones → páginas.

| Archivo | Rol |
|---------|-----|
| [`server.js`](server.js) | HTTP + ruteo. |
| [`lib/datasources.js`](lib/datasources.js) | Único puente a `bash/ --json`. Whitelist de fuentes y flags. |
| [`lib/kit.js`](lib/kit.js) | **Kernel** (KIT_VERSION): primitivas estables (escape, tablas, selects, formatters). Crecerlo es decisión de gobernanza. |
| [`blocks/`](blocks/) | **Bloques**: fragmentos compartidos por 2+ páginas o SSE-direccionables (tasks-table, task-detail, task-edit-form, meeting-detail, charts). |
| [`public/`](public/) | Assets vendorizados, servidos localmente (nunca CDN): `datastar.js`, `chart.umd.js` (Chart.js v4), `charts-init.js` (glue de gráficas). |
| [`patterns/`](patterns/) | **Patrones**: el cableado entre bloques (`master-detail`). Pocos, siempre código. |
| [`pages/`](pages/) | **Páginas**: una por `ui.component`; cada archivo exporta `{id, render(ui)}`. |
| [`lib/components.js`](lib/components.js) | Registro: escanea `pages/` al arrancar y despacha `renderPane()`. |
| [`lib/store.js`](lib/store.js) | Persistencia de UIs (archivos JSON). |
| [`lib/html.js`](lib/html.js) | Shell + panel izquierdo. |
| [`lib/sse.js`](lib/sse.js) | Protocolo Datastar 1.0 (`datastar-patch-elements`). |

## Gráficas

El componente `chart` renderiza cualquier fuente tabular como **barras** o
**dona** (línea soportada para futuras series de tiempo), con tooltips y leyenda
interactivos. Reparto de responsabilidades:

- **Servidor** ([`blocks/charts.js`](blocks/charts.js)): moldea las filas a un
  spec compacto (`{kind, labels, series}`) — elige columnas, ordena por valor,
  pliega la cola de la dona en «Otros» (máx. 6 segmentos) — y emite el
  placeholder declarativo `<div data-chart='{spec}'><canvas></div>`.
- **Cliente** ([`public/charts-init.js`](public/charts-init.js)): instancia el
  Chart.js vendorizado sobre esos placeholders — al cargar y, vía
  `MutationObserver`, tras cada patch SSE (sobrevive los morphs de idiomorph).
  Aquí vive el *house style*: paleta categórica validada (orden CVD-seguro,
  nunca más de 8 tonos), barras de una serie en UN color, marcas delgadas,
  grid hairline, tooltips.

Cada gráfica lleva un toggle «ver tabla» (el gemelo accesible del canvas — no
es opcional: es el alivio que exige la paleta) y el overlay de carga estándar.
Ejemplo de spec: `{ component: "chart", source: "task_stats",
params: { by: "status", kind: "donut" } }`.

## Extender

- **Nueva fuente de datos**: agrega una entrada a `SOURCES` en `datasources.js`
  (script + flags permitidos). Aparece sola en el `<select>` de "Nueva UI".
- **Nuevo componente**: un archivo `pages/<name>.js` que exporte
  `{id, render(ui)}` — el registro lo escanea al arrancar (`npm run
  viz:restart`); no hay switch central que editar. Lo que compartan 2+ páginas
  (o sea un fragmento SSE) va a `blocks/`; el cableado repetido, a `patterns/`.

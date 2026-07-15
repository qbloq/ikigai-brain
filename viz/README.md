# viz — UIs por demanda

Servidorcito HTTP (Node stdlib, **cero dependencias npm**) que genera páginas web
por demanda: **TailwindCSS** para estilos + **Datastar** para reactividad sobre
**SSE**. Los datos salen de los scripts read-only de [`bash/`](../bash) (vía
`--json`), nunca de SQL ad-hoc.

```bash
npm run viz                 # http://localhost:4317   (PORT=… para cambiar)
```

## Modelo

Cada página es una **UI persistida** con un ID (slug estable), accesible por
URL. Una UI es un *spec* (no HTML congelado), así que siempre refleja los
datos actuales:

```json
{ "id": "seguimientos-pendientes", "name": "Seguimientos pendientes",
  "component": "table", "source": "calls",
  "params": { "result": "Follow-up", "reported": "1" },
  "scope": "personal", "owner": "team_member:…", "role": "director-comercial" }
```

Una spec también puede ser **v2 — direccionada a patrón**:
`{ "spec_version": 2, "pattern": "master-detail", "master": { "block": "…",
"source": "…" }, "detail": { "block": "…" } }` (bloques resueltos por id).

Se guardan como archivos JSON en [`specs/`](specs/) — un **store por capas**
(deltas paso 5): `org/` (el núcleo común, committeado — los seeds viven ahí,
no hay siembra en runtime) → `roles/<rol>/` (moldes por rol) → `local/` (la
capa personal, la ÚNICA escribible). `list()` fusiona con *shadowing* por slug
(local > rol > org; el panel marca los forks con ⑂). Toda escritura va a
`local/` con linaje (`derived_from: "<capa>/<slug>@<sha>"`) y **auto-commit**
estructurado (`viz(ui): <verb> <slug>` + trailers `Delta-Type`/`Delta-Scope`;
`VIZ_AUTOCOMMIT=0` lo apaga). Un `copilot.json` en la raíz del repo filtra la
capa de rol y estampa `owner`/`role` al crear. El `store/` legado
(git-ignored) se migra una vez con
[`scripts/migrate-store-to-specs.js`](scripts/migrate-store-to-specs.js).
**Archivar** una UI es un soft-hide: solo estampa
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
| `GET /c/:component/frag/:name` · `POST /c/:component/act/:name` | **Dispatch genérico**: los mapas `frags`/`acts` del componente son los handlers (`ctx` entra, patches salen; `ctx.run()` solo ejecuta scripts declarados en `manifest.writes`). server.js nunca crece por componente. |
| `GET /task/:id`, `/task/:id/edit`, `/meeting/:id`, `POST /task/:tid/io/…` | Aliases legados congelados → el mismo dispatch. |
| `POST /ui` | Crea una UI desde el form "Nueva UI" (gated por `validateSpec`) y refresca el DOM. |
| `POST /ui/:id/archive` · `/unarchive` | Archiva/restaura una UI (soft-hide vía `archived_at`; sobre una spec org/rol crea un fork local con linaje) y re-pinta `#ui-list`. |
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
| [`blocks/`](blocks/) | **Bloques**: fragmentos compartidos por 2+ páginas, SSE-direccionables o llenadores de slot (tasks-table, meetings-table, calls-table, task-detail, task-edit-form, meeting-detail, call-report, charts). |
| [`public/`](public/) | Assets vendorizados, servidos localmente (nunca CDN): `datastar.js`, `chart.umd.js` (Chart.js v4), `charts-init.js` (glue de gráficas). |
| [`patterns/`](patterns/) | **Patrones**: el cableado entre bloques (`master-detail`, generalizado a slots master/detail). Pocos, siempre código; direccionables por spec v2. |
| [`pages/`](pages/) | **Páginas**: una por `ui.component`; cada archivo exporta `{id, render(ui), manifest}`. |
| [`lib/components.js`](lib/components.js) | Registro: escanea `pages/` + `blocks/` + `patterns/` al arrancar (namespace plano, colisión = error), valida specs (`validateSpec`: consumes≅emits, params, slots v2) y despacha `renderPane()` y los frags/acts de `/c/…`. |
| [`lib/store.js`](lib/store.js) | Persistencia por capas (`specs/org\|roles\|local`) con shadowing, linaje y auto-commit. |
| [`lib/actions.js`](lib/actions.js) | `makeRunner(manifest)`: el camino de escritura enforced — lanza error ante scripts no declarados en `manifest.writes`. |
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

## Componentes actuales

Páginas, por `ui.component`:

- **`table`** — tabla genérica con columnas inferidas de las filas.
- **`dashboard`** — tarjetas KPI (fuentes objeto como `dashboard`/`portfolio`).
- **`chart`** — barras/dona sobre cualquier fuente tabular (ver arriba).
  `kind`/`by` son params sobreescribibles, así los selectores re-consultan como
  cualquier barra de filtros. UIs sembradas: «Tareas por estado» (dona) y
  «Tareas por proyecto» (barras), ambas sobre `task_stats`.
- **`sop-tree`** — árbol plegable macro→SOP→arquetipo sobre la fuente `sops`;
  fetch único (fuente cacheada) y filtrado en el navegador.
- **`localdb`** — explorador de SQLite local: izquierda, cada db con tablas +
  counts; derecha, preview ≤200 filas. La selección viaja como `?db=&table=`,
  así toda vista es URL-direccionable (`/u/<id>?db=…`).
- **`notion-tasks`** — tabla read-only filtrable de las tareas BD Avances de un
  proyecto Notion (fetch único — fuente cacheada — filtrado en el navegador).
- **`tasks`** — lista de tareas con barra de filtros (status/priority/project/
  assignee/ventana due/open) que re-consulta vía `@get` con query params;
  reemplaza las viejas UIs "abiertas"/"vencidas" (vencidas = `due=overdue` +
  `open`). Los headers Título/Vence ordenan la lista (clic alterna asc/desc);
  `sort`/`dir` son params de presentación — se aplican en JS sobre las filas ya
  traídas, nunca llegan al shell.
- **`meetings`** — master-detail sobre team meetings: master `meetings-table`
  (filtros proyecto/estado/solo-con-reporte), detail `meeting-detail`
  (resumen/objetivos/decisiones/blockers, view-only, fuente `meeting_detail`).
- **`task-editor`** — el gemelo **editable** de `tasks` (sembrado como la UI
  "Editor de IO"); ver abajo.

`tasks` y `task-editor` son instancias delgadas de
[`patterns/master-detail.js`](patterns/master-detail.js): mismo master
`tasks-table`, distinto bloque detail. En `tasks`, el clic en una fila pega por
SSE el panel `#task-detail` (header + chip **Origen** de proveniencia + IO +
criterios de aceptación, view-only) desde la fuente `task_detail`; `GET /task/`
(id vacío) lo cierra. El objeto `task_detail` trae un campo `source`
(`{type,url,external_id,meeting_id,meeting_name}`) → el chip enlaza a Notion (↗)
o nombra la reunión de origen.

## Editor de IO — el único camino de escritura

En `task-editor`, el clic en una fila abre (`GET /task/:id/edit`) un formulario
editable del contrato IO — renombrar, retipar `io_type`/`artifact_type`, toggle
required, agregar/quitar inputs/outputs — construido de `task_detail` +
`io_catalog`. Cada control persiste al instante vía un `@post`
(`POST /task/:tid/io/add` · `…/io/:ioId/field/:field?value=` ·
`…/io/:ioId/delete`) → `update_task_io.sh` (una transacción) → re-render SSE del
formulario. Sin SQL en el viz: las escrituras pasan por el script bash
whitelisted, misma política que las lecturas.

**Bindings SQL Results:** una fila IO cuyo artefacto es `sql_query` cambia el
input genérico "pegar enlace" por un textarea monospace plegable — la instancia
del artefacto ES una query, guardada en el jsonb del binding como
`{query, params}`; el chip se titula con la primera línea `--` de la query (ver
[`lib/artifacts.js`](lib/artifacts.js)). «Guardar SQL» la envía como payload del
`@post` (→ `POST …/io/:ioId/sql` → `update_task_io.sh --ref-merge`). Dos
superficies de resultados comparten la fuente `io_query`: **Probar**
(`GET …/io/:ioId/sqlrun`) pega un preview compacto (20 filas + hint de
truncado) en la fila, y **Abrir como UI** (`POST …/io/:ioId/sqlui`) materializa
el binding como una UI `table` guardada (idempotente por fila IO) — todo
artefacto SQL es una UI latente. Ambas ejecutan solo la query **persistida**,
nunca el contenido del textarea.

## Extender

- **Nueva fuente de datos**: agrega una entrada a `SOURCES` en `datasources.js`
  (script + flags permitidos + `emits: 'rows'|'object'`). Aparece sola en el
  `<select>` de "Nueva UI".
- **Nuevo componente**: un archivo `pages/<name>.js` que exporte
  `{id, render(ui), manifest}` — el manifiesto es su contrato verificable:
  `consumes` (debe casar con el `emits` de la fuente) y `overridable` (los
  únicos query params que el navegador puede pisar). El registro lo escanea al
  arrancar (`npm run viz:restart`); no hay switch central que editar.
- **Bloque ruteado**: un `blocks/<name>.js` que exporte `{id, frags, acts,
  manifest}` recibe gratis `GET/POST /c/<id>/…`; si tiene acts, declara sus
  scripts en `manifest.writes` (enforcement en `ctx.run()`). Un bloque que
  llena slots de patrón declara `manifest.slot` (`master`/`detail`).
- Lo que compartan 2+ páginas (o sea un fragmento SSE) va a `blocks/`; el
  cableado repetido, a `patterns/` — y una combinación nueva de bloques sobre
  un patrón existente ya no es código: es una **spec v2**.

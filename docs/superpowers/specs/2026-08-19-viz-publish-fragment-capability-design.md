# Fragmentos firmados en el publicador — diseño

**Estado:** propuesto. Responde al hueco abierto en
[`docs/viz-publish-fragmentos.md`](../../viz-publish-fragmentos.md) (opción
**(c)**, la recomendada ahí: *capability por fila, firmada en el render*).

## Por qué esto y por qué ahora

`viz/publish.js` (producción, `app.ikigaigm.parallelo.ai`) no monta
`GET /c/:component/frag/:name` — a propósito, desde el diseño original
(`2026-08-15-viz-publish-design.md`). Dos razones, documentadas en el doc de
arriba:

1. Un fragmento se direcciona por *componente*, no por *despliegue* — sin
   contexto de qué UI publicada lo originó, no hay cómo aplicarle los params
   forzados por identidad.
2. La identidad hoy solo fuerza params de **fuente** (`--closer=Luis`). Un
   fragmento de detalle pide **por id de fila**, y ningún script de detalle
   sabe filtrar "¿esta fila es tuya?". El master ya viene scoped; el
   fragmento es una request aparte, sin ese scope.

`bash/publicar/publicar_ui.sh` hoy **rechaza de plano** publicar cualquier
spec que necesite `/c/` (guard 1: cualquier spec con `pattern`; guard 3: la
sonda de render, que falla si el HTML de un componente v1 emite URLs `/c/`).
Es la razón real por la que el piloto publicado (`closer-dashboard`) es una
página monolítica sin master-detail.

Motivador inmediato: el patrón **Tabs** (spec aparte, aún no construido)
depende enteramente de `/c/` para abrir cada pestaña dinámica. No tiene
sentido construirlo si no se puede publicar. Este documento resuelve **solo**
el prerrequisito de autorización — Tabs y el cableado del dashboard de closer
son proyectos separados que consumen lo que se construye acá.

## Alcance

**Adentro:** hacer que `/c/` sea montable de forma segura en el publicador,
de forma genérica — no atada a un componente en particular. Verificado contra
el único consumidor que existe hoy: `patterns/master-detail.js` (usado por
`tasks`, `task-editor`, `meetings`).

**Afuera (proyectos futuros, no este):**
- El patrón Tabs y su bloque `blocks/tabs.js`.
- El cableado de `pages/closer-dashboard.js` con links a reporte/transcript/plan.
- Cualquier cambio a los `acts` (escrituras) — siguen prohibidos en el
  publicador, eso no es parte de este hueco y no cambia acá.

## Modelo de firma

Una *capability* es una firma HMAC sobre la tupla que de verdad importa —
**no** sobre la URL como texto:

```
firma = HMAC(clave, slug + "|" + user_id + "|" + component + "|" + frag + "|" + id)
```

- **Clave**: derivada de `JWT_SECRET` (ya existe, ya es la raíz de confianza
  del publicador) con un contexto propio — no se reutiliza la clave cruda de
  firmar JWT para un propósito distinto.
- **`user_id`** = `payload.id` — el mismo campo que ya usa `publogic.js`
  (`resolverIdentidad`'s `$user_id: payload.id`), no un claim nuevo.
- **Sin TTL propio.** La firma no lleva timestamp. Vive lo que dure la
  sesión: el gate de sesión (JWT válido) corre *antes* de llegar al
  fragmento, así que una firma sin sesión válida detrás no sirve de nada. Es
  la misma conclusión que ya adelantaba el doc de origen.
- **Se firma la tupla INTERNA, no el wrapper.** Nota para cuando se construya
  Tabs: su bloque `tabs` va a re-despachar internamente a otro componente
  (`plan-detail`, `call-transcript`...). Si algún día se firmara solo la capa
  exterior (`component=tabs`), el hueco se reabriría un nivel más adentro —
  cualquiera podría pedirle a `tabs` que abra el detalle de otro. Por eso la
  firma siempre es sobre el componente/frag/id **real**, nunca sobre el
  nombre del wrapper que lo pide. Este documento no implementa Tabs, pero el
  mecanismo que construye ya tiene que sostener esta propiedad.

## Whitelist por despliegue, congelada al publicar

Nueva columna `despliegues.frags_permitidos` (TEXT, JSON array de component
ids) — igual que `spec_json`, es un snapshot: se calcula una vez al publicar,
no se deriva en runtime del spec.

**Cómo se calcula** (en `publicar_ui.sh`, reemplazando lo que hoy son los
guards 1 y 3):

- Guard 1 (bloqueo total de specs con `pattern`) **desaparece** — un spec v2
  ya no es categóricamente no-publicable.
- Guard 3 (la sonda de render, que hoy falla si detecta URLs `/c/`) **se
  repropone**: sigue renderizando el spec y capturando las URLs `/c/...` del
  HTML (ya lo hace, con el mismo regex), pero en vez de fallar, extrae los
  nombres de componente de esas URLs y los guarda como
  `frags_permitidos`. Sigue fallando duro si la sonda misma revienta
  (spec roto) — eso no cambia.
- La sonda renderiza **sin** `ctx.sign` (no hace falta simular una firma real
  para saber qué componentes se referencian — solo importa la forma de las
  URLs, no que estén firmadas).

## El hook de firmado

Hoy solo `patterns/master-detail.js` construye URLs `/c/.../frag/...`
(dentro de `wire.rowAttrs`, al pintar el click de fila). Eso hace que el
cambio sea quirúrgico:

- `renderPane(ui, ctx)` (`lib/components.js`) gana un segundo parámetro
  **opcional**. Para specs v2 lo pasa a `pat.render(ui, slots, ctx)`.
- `server.js` (viz local) sigue llamando `renderPane(ui)` sin `ctx` —
  comportamiento local **sin cambios**, `ctx` por defecto es un objeto vacío
  y `ctx.sign` no existe.
- `master-detail.js`: `render(ui, slots, ctx)`. Al construir el link de fila,
  si `ctx.sign` existe, el `id` de la fila se envuelve con
  `ctx.sign(component, frag, id)` antes de armar la URL — el resultado es un
  query param extra (`&f=...`) en el mismo `href`/`data-on:click` de siempre.
  Si `ctx.sign` no existe (viz local), la URL sale exactamente igual que hoy.

## La ruta nueva en `publish.js`

`GET /:slug/c/:component/frag/:name` (namespaced bajo el slug, a diferencia
del `/c/` plano del viz local — así la request SÍ lleva contexto de
despliegue, resolviendo el problema 1 del doc de origen).

Orden de los candados, cada uno corta en un 404 (nunca un 403 — no se filtra
qué existe, mismo criterio que el resto del publicador):

1. **Sesión válida** — mismo patrón que ya usan `/ui/:slug` y `/:slug`.
2. **Acceso al despliegue** — `accesoA(despliegue, payload)` (ya existe, sin
   cambios); si no hay permiso, 404.
3. **Whitelist** — `component` tiene que estar en
   `despliegue.frags_permitidos`. Si no, 404.
4. **Firma** — `verifyCap(slug, payload.id, component, frag, id, f)`. Si no
   valida, 404.

Solo si los cuatro pasan, se llama al `dispatch()` que ya existe en
`lib/components.js` — el mismo que usa `server.js`, cero renderizado nuevo.
La respuesta se envía por el mismo `startSSE`/`patchElements` que ya usa
`GET /ui/:slug`.

## Archivos que cambian

| Archivo | Cambio |
|---|---|
| `bash/publicar/schema.sql` | columna nueva `despliegues.frags_permitidos` |
| `bash/publicar/publicar_ui.sh` | quitar guard 1; repropone guard 3 (falla→whitelist); guarda la columna nueva en el INSERT |
| `viz/lib/capability.js` (nuevo) | `signCap`/`verifyCap`, derivación de clave desde `JWT_SECRET` |
| `viz/lib/components.js` | `renderPane(ui, ctx)`, threading a `pat.render` |
| `viz/patterns/master-detail.js` | `render(ui, slots, ctx)`, firma el link de fila si `ctx.sign` existe |
| `viz/publish.js` | ruta nueva `GET /:slug/c/:component/frag/:name` con los 4 candados |
| `viz/lib/pubstore.js` | ninguno — usa `SELECT *`, la columna nueva viaja sola |

## Qué NO cambia

- Los `acts` (POST, escrituras) siguen sin montarse en el publicador — regla
  aparte, de gobernanza, no de este hueco.
- El viz local (`server.js`) — cero cambio de comportamiento; `ctx` es
  siempre opcional y por defecto no firma nada.
- El modelo de identidad/permisos (`publogic.js`, `pubauth.js`) — se
  **reusa** tal cual, no se toca.

## Plan de pruebas

- Local: `master-detail` sigue funcionando exactamente igual (sin `ctx`, sin
  firma) — regresión de que nada se rompió.
- Publicador: publicar un spec `master-detail` (hoy imposible, guard 1 lo
  bloquea) y confirmar que el link de fila trae `&f=...` y abre el detalle.
- Negativo 1: pedir `/:slug/c/:component/frag/:name?id=X` con una firma
  alterada un carácter → 404.
- Negativo 2: pedir un `component` que no está en `frags_permitidos` de ese
  despliegue (aunque exista como bloque en el registro) → 404.
- Negativo 3: la misma firma válida, pero de OTRO despliegue (`slug`
  distinto) → 404 (la firma está atada al slug).
- Negativo 4: sesión de otro `user_id` reusando una URL firmada ajena → 404
  (la firma está atada al `user_id`).

# Fragmentos (`/c/`) en el publicador — el hueco de diseño pendiente

**Estado:** abierto. El publicador v1
([spec](superpowers/specs/2026-08-15-viz-publish-design.md)) **no monta** las
rutas `GET /c/:component/frag/:name`, a propósito. Este doc registra por qué,
qué deja afuera, y las preguntas que un v2 tiene que responder antes de
montarlas. Leerlo antes de publicar cualquier UI master-detail.

## El problema en una frase

Los fragments se direccionan **por componente**, no por despliegue — el request
no lleva contexto de qué UI publicada lo originó, así que el publicador no
puede saber qué params forzados aplicarle ni si el fragment pertenece siquiera
a algo publicado.

## Evidencia (cómo funciona hoy)

- En el viz local, un block enrutado (`blocks/*.js` con `id`) expone sus
  fragments bajo `GET /c/<id>/frag/<name>` con los params **crudos de la URL**:
  `runDispatch` en `viz/server.js:109` construye `ctx.params` directamente de
  `url.searchParams`. Confianza total — correcto para el taller local.
- Las páginas master-detail dependen de eso: `tasks` → `task-detail?id=…`,
  `meetings` → `meeting-detail?id=…`, leads → `opp-detail?id=…`, llamadas →
  `call-report?id=…`. El clic en una fila dispara el fragment con el id de la
  fila.
- El piloto publicado (`closer-dashboard`) **no** usa fragments: re-renderiza
  la página entera vía `GET /ui/:id` (`pages/closer-dashboard.js:118`), ruta
  que el publicador sí monta con los params de identidad re-aplicados. Por eso
  v1 pudo recortar `/c/` sin perder nada.

## Por qué montarlos tal cual sería un hueco de seguridad

Dos capas de problema, y la segunda es la dura:

1. **Sin alcance de despliegue.** Un visitante autenticado podría pedir
   `/c/task-detail/frag/panel?id=<cualquier-task>` aunque ninguna UI publicada
   componga ese block. Se arregla fácil: rutear los fragments **a través del
   despliegue** (`/p/<slug>/c/…`) y validar contra una whitelist de componentes
   congelada al publicar (derivable del spec: la página + los blocks que su
   pattern compone).
2. **El forzado de identidad no gobierna el detalle por id.** La identidad
   fuerza *params de fuente* (`--closer`, `--project`). Pero un fragment de
   detalle fetcha **por id de fila** — forzar `closer=Luis` en
   `task-detail?id=X` no hace nada: el script de detalle no filtra por closer,
   devuelve la fila X. Un closer con permiso al master podría pedir el detalle
   de una fila que su master jamás le mostró. Esto es autorización a nivel de
   FILA, y ni el modelo de permisos v1 ni la capa bash lo modelan.

## Opciones para v2 (con una recomendación)

- **(a) Fragments solo en despliegues sin identidad** (`{}` — estilo
  Director). Elimina el problema de fila porque ese visitante ve todo de todos
  modos. Barato, pero deja el caso closer sin master-detail.
- **(b) Scripts de detalle con alcance**: cada fuente de detalle gana el param
  de identidad (`task_detail.sh --id X --closer L` que devuelve vacío si la
  fila no es de L). Correcto de raíz pero caro: toca cada script de detalle y
  duplica la lógica de alcance en SQL, por fuente.
- **(c) Capability por fila, firmada en el render** *(recomendada)*: el master
  ya se renderiza **con el alcance aplicado** — el servidor sabe exactamente
  qué filas le mostró a este visitante. Al renderizar, cada link de detalle
  sale firmado: `/p/<slug>/c/task-detail/frag/panel?id=X&f=HMAC(secreto,
  slug|user_id|X)`. El fragment solo corre si la firma valida. Cero cambio en
  los scripts bash, la autorización queda donde ya está la información (el
  render del master), y revocar = las firmas expiran con la sesión. Costo: el
  kit de render de tablas necesita un hook «decorar link de detalle» que el
  publicador inyecte.

## Preguntas abiertas antes de implementar

1. ¿La whitelist de componentes por despliegue se deriva del spec al publicar
   (congelada en `despliegues`) o se resuelve en runtime del spec_json? La
   congelada es consistente con el snapshot; el runtime no agrega columna.
2. En (c), ¿la firma lleva TTL propio o vive lo que la sesión? (La sesión ya
   expira con el JWT — probablemente basta.)
3. ¿Los `acts` POST de blocks (escrituras) siguen prohibidos en v2? **Sí** —
   esa regla no es de fragments, es del publicador: producción no escribe.
   Cualquier excepción futura es una decisión de gobernanza, no un default.

## Mientras tanto (la regla operativa v1)

**Solo se publican UIs autosuficientes**: páginas que re-renderizan por
`GET /ui/:id` y no componen blocks con frags. Antes de publicar un spec,
verificar que su render no emite URLs `/c/…` — si las emite, es master-detail
y cae en este doc.

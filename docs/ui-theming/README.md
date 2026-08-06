# Themes — la identidad visual de cada cliente

Cada cliente pinta su viz con su propia marca. Un tema son **diez hex y una
tipografía**; todo lo demás —claro, oscuro, gráficas, estados, bordes, sombras,
glows— se deriva de ahí. Este documento es el mapa de cómo funciona y qué tocar.

La fuente de diseño es [ikigai-design-system.html](ikigai-design-system.html)
(v1 · 2026-07-23), que se lee solo en el navegador: 19 secciones con todos los
componentes vivos, principios, do/don't y la guía de reemplazo de paleta (§18).

---

## Cambiar el tema de un cliente

Editar `tema.json` en la raíz de su cerebro. Nada más.

```jsonc
{
  "nombre": "GALO Seguros",
  "modo": "light",                    // el modo con que abre; el usuario lo cambia y se recuerda
  "fuente": { "ui": "Sora", "mono": "JetBrains Mono" },
  "paleta": {
    "violet":   "#740CE8",   // PRIMARIO · CTAs · foco · serie 1
    "pink":     "#F18AEB",   // acento · gradientes · aurora
    "indigo":   "#06033A",   // fondo oscuro · texto sobre claro
    "navy":     "#10112B",   // superficie oscura 2
    "lilac":    "#F3CFFF",   // tinte claro · texto sobre oscuro
    "cream":    "#FFFBE9",   // superficie cálida
    "lavender": "#DFD2FE",   // fondo de página claro
    "positive": "#16C79A",   // meta cumplida / ingreso
    "negative": "#FF3D57",   // bajo benchmark / gasto
    "caution":  "#FFC53D"    // warning / en riesgo
  }
}
```

No hay que reiniciar el viz: `loadTheme()` lee el archivo por request.

**Las restricciones son de contraste, no de gusto** (§18 del design system):

| token | debe ser | si te equivocas |
|---|---|---|
| `violet` | saturado y **oscuro** (≥4.5:1 sobre blanco) | el texto blanco del botón deja de leerse |
| `indigo` | **muy** oscuro (L\* < 15) | el tema oscuro pierde profundidad |
| `navy` | oscuro, un paso más claro que indigo | las cards desaparecen del fondo |
| `lilac` | **muy** claro, mismo hue del primario | el texto en oscuro deja de leerse |
| `lavender` | claro, baja saturación | el fondo compite con las cards |
| `pink` | claro y vibrante, análogo al primario | el gradiente pierde el brillo de la firma |
| `cream` | casi blanco, cálido | poco riesgo — es el más decorativo |

Un valor inválido no tumba nada: cae a su default y queda un `[tema]` en el log.

---

## Cómo está armado

```
tema.json                 10 hex + tipografía          ← lo único por cliente
   ↓ viz/lib/theme.js    valida y emite <style>:root{--pal-*}
viz/public/tokens.css    ~90 semánticos + rampas + componentes  ← igual para todos
   ↓ viz/public/tw-bridge.js
las clases Tailwind ya escritas del viz
```

**Regla de oro, heredada del DS:** los componentes jamás consumen `--pal-*`,
solo los semánticos (`--surface-2`, `--text-1`, `--brand-solid`…). Es lo que
hace que cambiar diez líneas repinte el sistema entero.

### El puente (`tw-bridge.js`)

El viz tenía ~700 usos de clases de color Tailwind, y —sin habérselo
propuesto— las usaba semánticamente sin excepción: `slate` = neutral,
`indigo`/`blue`/`sky`/`violet` = marca, `red`/`rose` = negativo, `emerald` =
positivo, `amber` = precaución, `pink` = acento.

En vez de reescribir esos 700 sitios, el puente **redefine la paleta de
Tailwind** apuntándola a las rampas de `tokens.css`. Dos cosas salen gratis:

- el viz entero se repinta con el tema del cliente;
- y gana tema oscuro, porque las rampas se mezclan entre dos polos que
  **intercambian papel** bajo `[data-theme="dark"]` (`--ramp-ink` /
  `--ramp-paper`). Por eso `bg-slate-100` es superficie clara en claro y oscura
  en oscuro, y `text-slate-900` es casi negro en claro y casi blanco en oscuro,
  sin una sola clase condicional en el markup.

El puente es **el piso, no el techo**: al portar un componente a las clases del
DS (`.btn`, `.card`, `.kpi`, `.tbl`, `.badge`…) sus utilidades de color
desaparecen y dejan de pasar por él.

### Gráficas

`public/charts-init.js` lee todos sus colores del CSS al dibujar, y se repinta
solo cuando cambia `data-theme`. Pero hay **dos gobiernos distintos**, a
propósito:

- El **cromo** (rejilla, ejes, tinta, superficie, tooltip) sigue al tema. Tiene
  que hacerlo: una superficie `#fff` sobre fondo oscuro está mal.
- Los **slots categóricos** (`--chart-1..8`) NO llevan marca por defecto: son el
  set de referencia de dataviz validado para daltonismo, y su *orden* es el
  mecanismo de seguridad. La rampa de marca del DS (`--c-1..--c-6`) no está
  validada, así que no se cablea sola. Un tema puede pisarlos, pero eso es una
  decisión de accesibilidad explícita.

### Claro / oscuro

Es preferencia **del usuario**, no del tema: vive en `localStorage`
(`viz-modo`), se resuelve antes del primer pintado para que no haya destello, y
el botón «◐» del panel izquierdo la voltea. `tema.json` solo decide con qué modo
abre alguien que nunca eligió.

### Tipografía

Sora y JetBrains Mono quedan **vendorizadas** en `viz/public/fonts/` (la
política del viz es no depender de CDNs). Son fuentes variables: un archivo por
familia y subset latino cubre todo el eje 100-900, ~104 KB en total.

Un cliente con su propia tipografía: vendoriza el `woff2` ahí, agrega su
`@font-face` en `fonts.css` y nombra la familia en `tema.json`. Si la familia no
existe, entra la pila del sistema y la UI sigue legible.

---

## Gobernanza

El tema es **identidad de marca de la org**, no preferencia del empleado. Vive
en el cerebro del cliente (viaja en la semilla, el cliente lo edita en SU repo,
los copilotos lo heredan por rebase) y por eso el cerebro se pinta solo, sin
pedirle nada a la forja en runtime.

Si un copiloto edita `tema.json`, aparece en la Cola de Gobernanza como delta de
clase **`tema`** (`bash/deltas/scan.sh`) y se decide con `review.sh` como
cualquier otro. Es el gemelo visual de `copilot.json`: uno es quién soy, el otro
cómo me veo.

---

## Compatibilidad

`color-mix()` — Chrome 111+ · Safari 16.2+ · Firefox 113+. Todo el sistema
depende de ella. Si algún día hay que soportar navegadores viejos, un build step
precompila los `color-mix` a hex sin cambiar la estructura de tokens.

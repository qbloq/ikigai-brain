// theme — el tema visual del cliente, leído de `tema.json` en la raíz del
// cerebro (gemelo visual de `copilot.json`: uno es quién soy, el otro cómo me
// veo). Viaja en la semilla al alta, el cliente lo edita en SU repo, y los
// copilotos lo heredan por rebase — así el cerebro se pinta solo, sin pedirle
// nada a la forja en runtime.
//
// Un tema son DIEZ hex (el SWAP BLOCK del design system) más la tipografía.
// Nada más: las ~90 variables semánticas, el tema oscuro, las gráficas, los
// estados, bordes, sombras y glows se derivan de ahí con color-mix() en
// public/tokens.css, que es idéntico para todos los clientes.
//
// Editar tema.json es un delta de clase `tema`, gobernado a nivel de org: el
// tema es identidad de marca del cliente, no preferencia del empleado. Lo que
// sí es preferencia es claro/oscuro, que vive en localStorage.

const fs = require("fs");
const path = require("path");

const TEMA_PATH = process.env.VIZ_TEMA || path.join(__dirname, "..", "..", "tema.json");

// Los diez tokens del SWAP BLOCK, con su rol y el default de Ikigai. El orden
// es el del design system; los comentarios son la restricción real de cada uno
// (§18 del documento) — lo que hay que respetar al elegir un reemplazo.
const SWAP = [
  ["pink", "#F18AEB", "acento cálido · highlights · serie 2 — claro y vibrante, análogo al primario"],
  ["violet", "#740CE8", "PRIMARIO · CTAs · foco · serie 1 — saturado y OSCURO (≥4.5:1 sobre blanco)"],
  ["indigo", "#06033A", "fondo oscuro · texto sobre claro — MUY oscuro (L* < 15)"],
  ["navy", "#10112B", "superficie oscura 2 — oscuro, un paso más claro que indigo"],
  ["lilac", "#F3CFFF", "tinte claro · texto sobre oscuro — MUY claro, mismo hue del primario"],
  ["cream", "#FFFBE9", "superficie cálida — casi blanco, cálido"],
  ["lavender", "#DFD2FE", "fondo de página claro — claro, baja saturación"],
  ["positive", "#16C79A", "funcional: meta cumplida / ingreso"],
  ["negative", "#FF3D57", "funcional: bajo benchmark / gasto"],
  ["caution", "#FFC53D", "funcional: warning / en riesgo"],
];

const HEX = /^#[0-9a-fA-F]{6}$/;
const FAMILY = /^[A-Za-z0-9 _-]{1,40}$/;

const DEFAULTS = {
  nombre: "Ikigai",
  modo: "light",
  fuente: { ui: "Sora", mono: "JetBrains Mono" },
};

// Pila de respaldo: si la familia del tema no está vendorizada en
// public/fonts/, el navegador cae a la del sistema y la UI sigue legible.
const STACK_UI = 'system-ui, -apple-system, "Segoe UI", sans-serif';
const STACK_MONO = 'ui-monospace, "SF Mono", Menlo, monospace';

// Un tema malo no puede tumbar el viz: cada valor inválido cae a su default y
// se registra. El cliente ve su UI, no una pantalla en blanco.
function loadTheme() {
  let raw = {};
  try {
    raw = JSON.parse(fs.readFileSync(TEMA_PATH, "utf8"));
  } catch (e) {
    if (e.code !== "ENOENT") console.warn(`[tema] ${TEMA_PATH} ilegible (${e.message}) — uso el tema por defecto`);
    raw = {};
  }

  const pal = {};
  const paleta = raw.paleta || {};
  for (const [key, fallback] of SWAP) {
    const v = paleta[key];
    if (v == null) {
      pal[key] = fallback;
    } else if (HEX.test(String(v).trim())) {
      pal[key] = String(v).trim();
    } else {
      console.warn(`[tema] paleta.${key} = ${JSON.stringify(v)} no es un hex #rrggbb — uso ${fallback}`);
      pal[key] = fallback;
    }
  }

  const font = (v, fallback) => {
    if (v == null) return fallback;
    if (FAMILY.test(String(v).trim())) return String(v).trim();
    console.warn(`[tema] fuente ${JSON.stringify(v)} inválida — uso ${fallback}`);
    return fallback;
  };

  return {
    nombre: typeof raw.nombre === "string" && raw.nombre.trim() ? raw.nombre.trim() : DEFAULTS.nombre,
    modo: raw.modo === "dark" ? "dark" : DEFAULTS.modo,
    paleta: pal,
    fuente: {
      ui: font(raw.fuente?.ui, DEFAULTS.fuente.ui),
      mono: font(raw.fuente?.mono, DEFAULTS.fuente.mono),
    },
  };
}

// El SWAP BLOCK como CSS. Es lo ÚNICO que varía por cliente: doce líneas
// sobre un tokens.css estático y cacheado.
function themeStyle(theme) {
  const pal = SWAP.map(([key]) => `    --pal-${key}: ${theme.paleta[key]};`).join("\n");
  return `<style id="tema">
  :root {
${pal}
    --font-display: "${theme.fuente.ui}", ${STACK_UI};
    --font-ui: "${theme.fuente.ui}", ${STACK_UI};
    --font-mono: "${theme.fuente.mono}", ${STACK_MONO};
  }
</style>`;
}

// Claro/oscuro es preferencia del usuario, no del tema: se resuelve antes del
// primer pintado para que no haya destello.
const MODE_BOOT = `(function(){try{var m=localStorage.getItem('viz-modo');if(m==='dark'||m==='light')document.documentElement.setAttribute('data-theme',m)}catch(e){}})()`;

const MODE_TOGGLE = `(function(){var h=document.documentElement,n=h.getAttribute('data-theme')==='dark'?'light':'dark';h.setAttribute('data-theme',n);try{localStorage.setItem('viz-modo',n)}catch(e){}})()`;

// Todo lo que va en <head> para que una página quede tematizada. El orden
// importa: tokens.css primero, luego Tailwind (que inyecta su <style> al final
// del head en runtime, así que sus utilidades ganan los empates con las clases
// de componente del DS — que es lo que queremos), y tw-bridge apuntando las
// familias de Tailwind a las rampas.
function themeHead(theme) {
  return `<link rel="stylesheet" href="/fonts/fonts.css" />
    <link rel="stylesheet" href="/tokens.css" />
    ${themeStyle(theme)}
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="/tw-bridge.js"></script>
    <script>${MODE_BOOT}</script>`;
}

module.exports = { SWAP, loadTheme, themeStyle, themeHead, MODE_TOGGLE };

// kpi-cards block — the KPI card grid, extracted from pages/dashboard.js so a
// second dashboard family (the PM's torre de control) doesn't fork it.
//
// A card DEF is code, not spec: it carries a formatter, a semantic tone and —
// new here — an optional `href`, which is what turns a dashboard from a poster
// into an index. Clicking «Vencidas 111» must land on exactly those 111 rows;
// that link is the whole reason the PM layer is two UIs instead of ten.
//
// Contract:
//   cards(defs, data, opts?) → HTML for one grid row
//     def = { key, label, fmt, tone, href, title, muted, value }
//       key    field of the data object (ignored when `value` is given)
//       fmt    'int' | 'money' | 'pct' | 'mult' | 'days' | 'raw'
//       tone   'pos' | 'neg' | 'cau' | 'brand' | 'accent' | 'muted'
//       href   string | (data) => string|null — wraps the card in a link
//       title  tooltip (say WHAT the number counts, in the user's words)
//       muted  render greyed out (a metric that is not measurable YET —
//              preferable to hiding it, which would silently drop the promise)
//       value  precomputed display value, for derived cards
//     opts = { cols: <n> } → grid columns at lg (default 6)
//
// No hex, no rgb(): tone → the design system's semantic tokens (viz/CLAUDE.md).

const { escape } = require("../lib/kit");

const TONE = {
  pos: "var(--pos-text)",
  neg: "var(--neg-text)",
  cau: "var(--cau-text)",
  brand: "var(--text-brand)",
  accent: "var(--accent-text)",
  muted: "var(--text-3)",
};

function fmtVal(v, kind) {
  if (v == null || v === "") return "—";
  if (kind === "raw") return escape(String(v));
  const n = Number(v);
  if (Number.isNaN(n)) return escape(String(v));
  if (kind === "money") return "$" + Math.round(n).toLocaleString("en-US");
  if (kind === "pct") return (n * 100).toFixed(1) + "%";
  if (kind === "mult") return n.toFixed(2) + "x";
  if (kind === "days") return n.toLocaleString("es-CO", { maximumFractionDigits: 1 }) + "d";
  return Math.round(n).toLocaleString("en-US");
}

function card(def, data) {
  const ink = TONE[def.muted ? "muted" : def.tone] || TONE.brand;
  const label = typeof def.label === "function" ? def.label(data) : def.label;
  const raw = def.value != null ? def.value : data[def.key];
  const body = `<div class="kpi">
      <p class="kpi-label" style="color:${ink}">${escape(label)}</p>
      <p class="kpi-value" style="color:${ink}">${escape(fmtVal(raw, def.fmt))}</p>
      ${def.footHtml ? `<p class="text-[11px] mt-1" style="color:var(--text-3)">${def.footHtml}</p>` : def.foot ? `<p class="text-[11px] mt-1" style="color:var(--text-3)">${escape(def.foot)}</p>` : ""}
    </div>`;
  const tip = def.title ? ` title="${escape(def.title)}"` : "";
  const href = typeof def.href === "function" ? def.href(data) : def.href;
  // El drill-down abre en la misma pestaña: la torre es un índice, y volver es
  // el botón «atrás». Sin href la tarjeta no finge ser clickeable.
  if (href && !def.muted) {
    return `<a href="${escape(href)}" class="card card-pad block hover:border-[var(--brand-solid)] transition-colors"${tip}>${body}</a>`;
  }
  return `<div class="card card-pad"${tip}>${body}</div>`;
}

function cards(defs, data, opts = {}) {
  const cols = opts.cols || 6;
  return `<div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-${cols} gap-3 mb-3">${defs
    .map((d) => card(d, data))
    .join("")}</div>`;
}

// Plain render block (like blocks/charts.js): NO `id` export — it is composed
// by pages, never addressed by a route or a spec slot.
module.exports = { cards, card, fmtVal, TONE };

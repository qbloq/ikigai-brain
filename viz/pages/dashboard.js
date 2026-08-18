// dashboard page — renders the financial KPI cards from the single object
// emitted by bash/metrics/dashboard.sh, plus a controls bar (project + date
// range) that re-fetches via Datastar @get with explicit query params.

const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");
const { cards } = require("../blocks/kpi-cards");

const CARD_GROUPS = [
  [
    { key: "ingresos_brutos", label: "Ingresos brutos", fmt: "money", color: "emerald" },
    { key: "venta_programas", label: "Venta programas", fmt: "money", color: "violet" },
    { key: "num_ventas", label: "# Ventas", fmt: "int", color: "violet" },
    { key: "ticket_promedio", label: "Ticket prom.", fmt: "money", color: "violet" },
    { key: "ingreso_neto", label: "Ingreso neto", fmt: "money", color: "emerald" },
    { key: "neto_org", label: "Neto Ikigai", fmt: "money", color: "blue" },
    { key: "neto_owner", label: "Neto", fmt: "money", color: "blue", labelFromOwner: true },
  ],
  [
    { key: "nuevas_n", label: "Nuevas", fmt: "int", color: "emerald" },
    { key: "nuevas_amt", label: "$ Nuevas", fmt: "money", color: "emerald" },
    { key: "cuotas_n", label: "Cuotas", fmt: "int", color: "emerald" },
    { key: "cuotas_amt", label: "$ Cuotas", fmt: "money", color: "emerald" },
    { key: "margen", label: "Margen", fmt: "pct", color: "amber" },
    { key: "costos", label: "Costos", fmt: "money", color: "red" },
  ],
  [
    { key: "pauta", label: "Pauta", fmt: "money", color: "red" },
    { key: "roas", label: "ROAS", fmt: "mult", color: "emerald" },
    { key: "profit_post_pauta", label: "Profit post-pauta", fmt: "money", color: "emerald" },
    { key: "leads", label: "Leads", fmt: "int", color: "pink" },
    { key: "cpl", label: "CPL", fmt: "money", color: "pink" },
    { key: "roas_funnel", label: "ROAS funnel", fmt: "mult", color: "emerald" },
  ],
];

// Each metric's hue carries MEANING here (money in vs money out vs ratio), so
// the port keeps the distinction but re-anchors it on the design system's
// semantic tokens instead of Tailwind family names — that's what makes a KPI row
// read as one system, and what lets a client's theme repaint it coherently.
// (The tokens themselves now live in blocks/kpi-cards.js, shared with the PM's
// torre de control; this map is the financial dashboard's own vocabulary.)
const CARD_TONE = {
  emerald: "pos", // entra plata
  red: "neg", // sale plata
  amber: "cau", // razón / margen
  violet: "brand", // volumen de negocio
  blue: "brand",
  pink: "accent", // demanda / leads
};

// Adapt this page's historical def shape (color / labelFromOwner) to the
// shared block's (tone / label-as-function).
function toCardDef(def) {
  return {
    ...def,
    tone: CARD_TONE[def.color] || "pos",
    label: def.labelFromOwner ? (data) => `Neto ${data.owner_name || "socio"}` : def.label,
  };
}

function renderDashboard(ui) {
  let data, err;
  try {
    const { rows } = fetchSource(ui.source, ui.params || {});
    data = rows[0] || {};
  } catch (e) {
    err = e.message;
  }
  const head = `<header class="mb-5 flex items-baseline gap-3">
    <h1 class="text-xl font-semibold text-slate-800">${escape(ui.name)}</h1>
    <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs text-indigo-600 hover:underline">abrir solo ↗</a>
  </header>`;
  if (err) {
    return `<section id="pane" class="flex-1 p-6 overflow-auto">${head}
      <div class="alert alert-neg">${escape(err)}</div>
    </section>`;
  }

  // project options for the selector
  let projectNames = [];
  try {
    projectNames = fetchSource("projects").rows.map((r) => r.name).filter(Boolean);
  } catch {
    /* fall back to current project */
  }
  if (!projectNames.length && data.project) projectNames = [data.project];

  const proj = data.project || "";
  const from = data.period_from || "";
  const to = data.period_to || "";

  // @get with explicit query params built from the bound signals (Datastar 1.0).
  const reget = `@get('/ui/${escape(ui.id)}?project='+encodeURIComponent($dbProject)+'&from='+$dbFrom+'&to='+$dbTo)`;
  const opts = projectNames
    .map((n) => `<option value="${escape(n)}"${n === proj ? " selected" : ""}>${escape(n)}</option>`)
    .join("");

  const controls = `<div class="flex flex-wrap items-center gap-3 mb-6"
      data-signals="{dbProject:'${escape(proj)}',dbFrom:'${escape(from)}',dbTo:'${escape(to)}'}">
    <select data-bind="dbProject" data-on:change="${reget}" class="select w-auto font-medium">${opts}</select>
    <input type="date" data-bind="dbFrom" data-on:change="${reget}" class="input w-auto" />
    <span class="text-slate-400">~</span>
    <input type="date" data-bind="dbTo" data-on:change="${reget}" class="input w-auto" />
  </div>`;

  const grid = CARD_GROUPS.map((group) => cards(group.map(toCardDef), data)).join("");

  return `<section id="pane" class="flex-1 p-6 overflow-auto bg-slate-50">${head}${controls}${grid}</section>`;
}

module.exports = {
  id: "dashboard",
  manifest: { consumes: "object", overridable: ["project", "from", "to"] },
  render: renderDashboard,
};

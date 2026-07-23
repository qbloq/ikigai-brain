// dashboard page — renders the financial KPI cards from the single object
// emitted by bash/metrics/dashboard.sh, plus a controls bar (project + date
// range) that re-fetches via Datastar @get with explicit query params.

const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");

function fmtVal(v, kind) {
  if (v == null || v === "") return "—";
  const n = Number(v);
  if (Number.isNaN(n)) return escape(v);
  if (kind === "money") return "$" + Math.round(n).toLocaleString("en-US");
  if (kind === "pct") return (n * 100).toFixed(1) + "%";
  if (kind === "mult") return n.toFixed(2) + "x";
  return Math.round(n).toLocaleString("en-US"); // int
}

const CARD_GROUPS = [
  [
    { key: "ingresos_brutos", label: "Ingresos brutos", fmt: "money", color: "emerald" },
    { key: "venta_programas", label: "Venta programas", fmt: "money", color: "violet" },
    { key: "num_ventas", label: "# Ventas", fmt: "int", color: "violet" },
    { key: "ticket_promedio", label: "Ticket prom.", fmt: "money", color: "violet" },
    { key: "ingreso_neto", label: "Ingreso neto", fmt: "money", color: "emerald" },
    { key: "neto_org", label: "Neto (org)", fmt: "money", color: "blue" },
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

const CARD_COLOR = {
  emerald: { label: "text-emerald-600", val: "text-emerald-700" },
  violet: { label: "text-violet-600", val: "text-violet-700" },
  blue: { label: "text-blue-600", val: "text-blue-700" },
  amber: { label: "text-amber-600", val: "text-amber-700" },
  red: { label: "text-red-600", val: "text-red-700" },
  pink: { label: "text-pink-600", val: "text-pink-700" },
};

function kpiCard(def, data) {
  const c = CARD_COLOR[def.color] || CARD_COLOR.emerald;
  const label = def.labelFromOwner ? `Neto ${data.owner_name || "socio"}` : def.label;
  return `<div class="bg-white rounded-xl border border-slate-200 shadow-sm px-5 py-4">
    <p class="text-xs font-semibold uppercase tracking-wide ${c.label}">${escape(label)}</p>
    <p class="mt-1 text-2xl font-bold ${c.val}">${escape(fmtVal(data[def.key], def.fmt))}</p>
  </div>`;
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
      <div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-4 text-sm">${escape(err)}</div>
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

  const inputCls =
    "text-sm px-3 py-2 rounded-lg border border-slate-300 bg-white focus:outline-none focus:ring-2 focus:ring-indigo-400";
  const controls = `<div class="flex flex-wrap items-center gap-3 mb-6"
      data-signals="{dbProject:'${escape(proj)}',dbFrom:'${escape(from)}',dbTo:'${escape(to)}'}">
    <select data-bind="dbProject" data-on:change="${reget}" class="${inputCls} font-medium">${opts}</select>
    <input type="date" data-bind="dbFrom" data-on:change="${reget}" class="${inputCls}" />
    <span class="text-slate-400">~</span>
    <input type="date" data-bind="dbTo" data-on:change="${reget}" class="${inputCls}" />
  </div>`;

  const grid = CARD_GROUPS.map(
    (group) =>
      `<div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3 mb-3">${group
        .map((def) => kpiCard(def, data))
        .join("")}</div>`
  ).join("");

  return `<section id="pane" class="flex-1 p-6 overflow-auto bg-slate-50">${head}${controls}${grid}</section>`;
}

module.exports = {
  id: "dashboard",
  manifest: { consumes: "object", overridable: ["project", "from", "to"] },
  render: renderDashboard,
};

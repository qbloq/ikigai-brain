// chart page — one chart (barras/dona) over any tabular source, as a persisted
// spec: { component: "chart", source, params: { kind, by?, x?, y? } }. The
// blocks/charts.js + public/charts-init.js pair does the work; this page adds
// the frame: header, a controls row (kind selector; dimension selector when
// the source is task_stats) that re-fetches via @get, the loading overlay, and
// the «ver tabla» twin — the relief the palette's sub-3:1 slots require, and
// the WCAG-clean equivalent of the canvas.

const { fetchSource } = require("../lib/datasources");
const { escape, miniTable, selectCtl } = require("../lib/kit");
const { rowsToSpec, chartEl } = require("../blocks/charts");

const KIND_OPTS = [
  ["bar", "Barras"],
  ["donut", "Dona"],
];
const BY_OPTS = [
  ["status", "Por estado"],
  ["priority", "Por prioridad"],
  ["project", "Por proyecto"],
  ["assignee", "Por responsable"],
];
// Display names for enum values (the DB speaks English, the UI Spanish).
const ES = {
  pending: "Pendiente",
  in_progress: "En curso",
  completed: "Completada",
  blocked: "Bloqueada",
  cancelled: "Cancelada",
  High: "Alta",
  Medium: "Media",
  Low: "Baja",
};

function renderChart(ui) {
  const p = ui.params || {};
  const kind = ["bar", "donut", "line"].includes(p.kind) ? p.kind : "bar";
  const isStats = ui.source === "task_stats";
  const by = BY_OPTS.some(([v]) => v === p.by) ? p.by : "status";

  let rows = [],
    label = "",
    err;
  try {
    ({ rows, label } = fetchSource(ui.source, isStats ? { ...p, by } : p));
  } catch (e) {
    err = e.message;
  }
  if (isStats) rows = rows.map((r) => Object.fromEntries(Object.entries(r).map(([k, v]) => [k, ES[v] || v])));

  const head = `<header class="mb-4 flex items-baseline gap-3">
    <h1 class="text-xl font-semibold text-slate-800">${escape(ui.name)}</h1>
    <span class="text-xs text-slate-400">${escape(label)} · ${rows.length} fila(s)</span>
    <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs text-indigo-600 hover:underline">abrir solo ↗</a>
  </header>`;

  const reget = `@get('/ui/${escape(ui.id)}?kind='+$chartKind${isStats ? "+'&by='+$chartBy" : ""})`;
  const sig = `{chartKind:'${escape(kind)}',chartBy:'${escape(by)}',loadingchart:false,showtable:false}`;
  const controls = `<div class="flex flex-wrap items-center gap-2 mb-4" data-signals="${sig}">
    ${selectCtl("chartKind", kind, KIND_OPTS, reget, "loadingchart")}
    ${isStats ? selectCtl("chartBy", by, BY_OPTS, reget, "loadingchart") : ""}
  </div>`;

  let body;
  if (err) {
    body = `<div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-4 text-sm">${escape(err)}</div>`;
  } else {
    const spec = rowsToSpec(rows, { kind, x: p.x || (isStats ? by : undefined), y: p.y, seriesLabel: isStats ? "Tareas" : undefined });
    body = `<div class="relative max-w-3xl bg-white rounded-xl border border-slate-200 shadow-sm p-5">
      <div id="chart-loading" data-class:on="$loadingchart" class="pointer-events-none absolute inset-0 z-10 flex items-center justify-center bg-white/50 rounded-xl">
        <div class="w-7 h-7 rounded-full border-2 border-slate-300 border-t-indigo-600 animate-spin"></div>
      </div>
      ${chartEl(spec)}
      <div class="mt-4 pt-3 border-t border-slate-100">
        <button data-on:click="$showtable=!$showtable" class="text-xs text-indigo-600 hover:underline">
          <span data-text="$showtable ? 'ocultar tabla' : 'ver tabla'">ver tabla</span>
        </button>
        <div data-show="$showtable" style="display:none" class="mt-2 overflow-auto max-h-72 rounded border border-slate-200">${miniTable(rows)}</div>
      </div>
    </div>`;
  }

  return `<section id="pane" class="flex-1 overflow-auto bg-slate-50">
    <style>#chart-loading{opacity:0;transition:opacity .2s ease}#chart-loading.on{opacity:1}</style>
    <div class="p-6">${head}${controls}${body}</div>
  </section>`;
}

module.exports = {
  id: "chart",
  manifest: { consumes: "rows", overridable: ["kind", "by"] },
  render: renderChart,
};

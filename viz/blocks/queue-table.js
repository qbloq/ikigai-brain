// queue-table block — the MASTER slot over the `fleet_queue` source: the
// Cola de Gobernanza list (docs/torre-de-control.md, T3). One row per delta
// pending decision, covering the rol→org frontier of every fork; filters
// (clase / incluir-decididas) are FIXED by this block, per the master
// contract: signals / regetQS / controls / table(rows, wire) / counter.

const { escape, cell, selectCtl } = require("../lib/kit");

const CLASE_BADGE = {
  "ui-spec": "bg-indigo-100 text-indigo-700",
  ontologia: "bg-emerald-100 text-emerald-700",
  esquema: "bg-amber-100 text-amber-700",
  identidad: "bg-slate-200 text-slate-600",
  codigo: "bg-rose-100 text-rose-700",
};

const ACTION_ES = {
  elevated: ["Elevada", "bg-emerald-100 text-emerald-700"],
  changes_requested: ["Cambios pedidos", "bg-amber-100 text-amber-700"],
  dismissed: ["Descartada", "bg-slate-200 text-slate-600"],
};

const CLASE_OPTS = [
  ["", "Clase: todas"],
  ["ui-spec", "ui-spec"],
  ["ontologia", "ontología"],
  ["esquema", "esquema"],
  ["identidad", "identidad"],
  ["codigo", "código"],
];

const QUEUE_COLS = [
  { k: "age_days", l: "Edad", w: "w-16", cls: "whitespace-nowrap" },
  { k: "org", l: "Org", w: "w-20" },
  { k: "frontera", l: "Frontera", w: "w-24" },
  { k: "clase", l: "Clase", w: "w-24" },
  { k: "que", l: "Qué", w: "w-[38%]" },
  { k: "employee", l: "Empleado", w: "w-28" },
  { k: "decided", l: "Decisión", w: "w-28" },
];

function claseBadge(v) {
  const cls = CLASE_BADGE[v] || "bg-slate-100 text-slate-600";
  return `<span class="text-[11px] font-medium px-2 py-0.5 rounded-full ${cls}">${escape(v)}</span>`;
}

function decidedBadge(d) {
  if (!d) return '<span class="text-slate-300">—</span>';
  const [label, cls] = ACTION_ES[d.action] || [d.action, "bg-slate-100 text-slate-600"];
  return `<span class="text-[11px] font-medium px-2 py-0.5 rounded-full ${cls}" title="${escape(d.reason || "")}">${escape(label)}</span>`;
}

function queueCell(col, r) {
  if (col === "age_days") return r.age_days == null ? "—" : `${r.age_days}d`;
  if (col === "clase") return claseBadge(r.clase);
  if (col === "que") return cell(r.name || r.path);
  if (col === "decided") return decidedBadge(r.decided);
  return cell(r[col]);
}

const INDICATOR = "loadingqueue";

function signals(p) {
  return {
    qClase: p.clase || "",
    qAll: p.all === "1" || p.all === "true",
  };
}

const regetQS = `'clase='+$qClase+'&all='+$qAll`;

function controls(p, reget) {
  return `${selectCtl("qClase", p.clase || "", CLASE_OPTS, reget, INDICATOR)}
    <label class="flex items-center gap-2 text-sm text-slate-600 px-2">
      <input type="checkbox" data-bind="qAll" data-on:change="${reget}" data-indicator:${INDICATOR} class="rounded border-slate-300" /> Incluir decididas
    </label>`;
}

function table(rows, wire) {
  if (!rows.length) return '<p class="text-slate-500 italic">Cola vacía: ningún delta pendiente de decisión.</p>';
  const thead = QUEUE_COLS.map(
    (c) => `<th class="text-left ${c.w || ""} font-semibold px-3 py-2 border-b border-slate-200 sticky top-0 bg-slate-50">${escape(c.l)}</th>`
  ).join("");
  const tbody = rows
    .map(
      (r) =>
        `<tr ${wire.rowAttrs(r)} class="cursor-pointer even:bg-slate-50/60 hover:bg-indigo-50">${QUEUE_COLS.map(
          (c) => `<td class="px-3 py-2 border-b border-slate-100 align-top ${c.cls || ""}">${queueCell(c.k, r)}</td>`
        ).join("")}</tr>`
    )
    .join("");
  return `<div class="overflow-auto rounded-lg border border-slate-200 max-h-[calc(100vh-12rem)]"><table class="w-full table-fixed text-sm border-collapse">
    <thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table></div>`;
}

module.exports = {
  id: "queue-table",
  manifest: {
    slot: "master",
    consumes: "rows",
    indicator: INDICATOR,
    overridable: ["clase", "all"],
  },
  signals,
  regetQS,
  controls,
  table,
  counter: (n) => `${n} delta(s)`,
  headerExtra: "",
};

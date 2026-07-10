// orgs-table block — the MASTER slot over the `fleet_orgs` source: the Flota,
// one row per client org (docs/torre-de-control.md, T4). The row is a health
// semaphore: genome head, pulse (last push), active copilots, pending deltas,
// mirror state. No filters yet — pre-F0 the fleet is one org; the master
// contract still applies (signals/regetQS/controls may be empty, not absent).

const { escape, cell } = require("../lib/kit");

const ORG_COLS = [
  { k: "org", l: "Org", w: "w-28" },
  { k: "head", l: "Head", w: "w-20", cls: "font-mono text-xs" },
  { k: "pulso", l: "Pulso", w: "w-28" },
  { k: "pushes_7d", l: "Push 7d", w: "w-20" },
  { k: "copilotos", l: "Copilotos", w: "w-20" },
  { k: "deltas_pend", l: "Δ pend.", w: "w-20" },
  { k: "espejo", l: "Espejo", w: "w-20" },
  { k: "modules", l: "Módulos", w: "w-[22%]" },
];

function pulseCell(r) {
  if (!r.pulso) return '<span class="text-slate-300">—</span>';
  const alive = r.pulso_dias != null && r.pulso_dias < 7;
  const dot = alive
    ? '<span class="inline-block w-2 h-2 rounded-full bg-emerald-500 mr-1.5" title="Actividad en los últimos 7 días"></span>'
    : '<span class="inline-block w-2 h-2 rounded-full bg-slate-300 mr-1.5" title="Sin actividad reciente"></span>';
  return `${dot}${escape(r.pulso)} <span class="text-slate-400">(${r.pulso_dias}d)</span>`;
}

function espejoBadge(v) {
  if (v === "OK") return '<span class="text-[11px] font-medium px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-700">OK</span>';
  if (v === "FALLÓ") return '<span class="text-[11px] font-medium px-2 py-0.5 rounded-full bg-red-100 text-red-700">FALLÓ</span>';
  return '<span class="text-slate-300">—</span>';
}

function pendBadge(n) {
  if (!n) return '<span class="text-slate-300">0</span>';
  return `<span class="text-[11px] font-semibold px-2 py-0.5 rounded-full bg-indigo-100 text-indigo-700">${n}</span>`;
}

function orgCell(col, r) {
  if (col === "pulso") return pulseCell(r);
  if (col === "espejo") return espejoBadge(r.espejo);
  if (col === "deltas_pend") return pendBadge(r.deltas_pend);
  if (col === "org") return `<span class="font-medium text-slate-800">${escape(r.org)}</span>`;
  return cell(r[col]);
}

const INDICATOR = "loadingflota";

function table(rows, wire) {
  if (!rows.length) return '<p class="text-slate-500 italic">Flota vacía: sin orgs en forja/clientes/.</p>';
  const thead = ORG_COLS.map(
    (c) => `<th class="text-left ${c.w || ""} font-semibold px-3 py-2 border-b border-slate-200 sticky top-0 bg-slate-50">${escape(c.l)}</th>`
  ).join("");
  const tbody = rows
    .map(
      (r) =>
        `<tr ${wire.rowAttrs(r)} class="cursor-pointer even:bg-slate-50/60 hover:bg-indigo-50">${ORG_COLS.map(
          (c) => `<td class="px-3 py-2 border-b border-slate-100 align-top ${c.cls || ""}">${orgCell(c.k, r)}</td>`
        ).join("")}</tr>`
    )
    .join("");
  return `<div class="overflow-auto rounded-lg border border-slate-200 max-h-[calc(100vh-12rem)]"><table class="w-full table-fixed text-sm border-collapse">
    <thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table></div>`;
}

module.exports = {
  id: "orgs-table",
  manifest: { slot: "master", consumes: "rows", indicator: INDICATOR, overridable: [] },
  signals: () => ({}),
  regetQS: `''`,
  controls: () => "",
  table,
  counter: (n) => `${n} org(s) en la flota`,
  headerExtra: "",
};

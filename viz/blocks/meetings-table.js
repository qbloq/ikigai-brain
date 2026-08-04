// meetings-table block — the MASTER slot over the `meetings` source: the team
// meetings list and its filter bar (project / status / solo-con-reporte —
// fixed by this block). Extracted from the hand-rolled meetings page when it
// was unified onto patterns/master-detail (Fase 0 paso 4).
//
// Same master-slot contract as tasks-table: signals / regetQS / controls /
// table(rows, wire) / counter.

const { fetchSource } = require("../lib/datasources");
const { escape, cell, selectCtl } = require("../lib/kit");

const MEETING_STATUS_BADGE = {
  completed: "bg-emerald-100 text-emerald-700",
  ended: "bg-emerald-100 text-emerald-700",
  processing: "bg-blue-100 text-blue-700",
  scheduled: "bg-amber-100 text-amber-700",
  cancelled: "bg-slate-200 text-slate-600",
};
const MEETING_STATUS_ES = {
  completed: "Completada",
  ended: "Finalizada",
  processing: "Procesando",
  scheduled: "Agendada",
  cancelled: "Cancelada",
};
const MEETING_STATUS_OPTS = [
  ["", "Estado: todos"],
  ["completed", "Completada"],
  ["processing", "Procesando"],
  ["scheduled", "Agendada"],
  ["ended", "Finalizada"],
  ["cancelled", "Cancelada"],
];

const MEETING_COLS = [
  { k: "name", l: "Reunión", w: "w-[44%]" },
  { k: "start", l: "Fecha", w: "w-32", cls: "whitespace-nowrap" },
  { k: "project", l: "Proyecto", w: "w-32" },
  { k: "status", l: "Estado", w: "w-28" },
  { k: "rep", l: "Rep", w: "w-12", align: "text-center" },
];

function meetingStatusBadge(v) {
  const cls = MEETING_STATUS_BADGE[v] || "bg-slate-100 text-slate-600";
  return `<span class="text-[11px] font-medium px-2 py-0.5 rounded-full ${cls}">${escape(MEETING_STATUS_ES[v] || v)}</span>`;
}

function repDot(v) {
  return v === "Y" || v === true
    ? '<span class="text-emerald-600" title="Tiene reporte">✓</span>'
    : '<span class="text-slate-300" title="Sin reporte">—</span>';
}

function meetingCell(col, r) {
  if (col === "status") return meetingStatusBadge(r[col]);
  if (col === "rep") return repDot(r[col]);
  return cell(r[col]);
}

const INDICATOR = "loadingmeetings";

function signals(p) {
  return {
    mStatus: p.status || "",
    mProject: p.project || "",
    mRep: p.has_report === "1" || p.has_report === "true",
  };
}

const regetQS = `'limit=0&status='+$mStatus+'&project='+encodeURIComponent($mProject)+'&has_report='+$mRep`;

function controls(p, reget) {
  let projectOpts = [["", "Proyecto: todos"]];
  try {
    projectOpts = projectOpts.concat(fetchSource("projects").rows.map((r) => [r.name, r.name]).filter(([n]) => n));
  } catch {
    /* keep the "todos" fallback */
  }
  return `${selectCtl("mStatus", p.status || "", MEETING_STATUS_OPTS, reget, INDICATOR)}
    ${selectCtl("mProject", p.project || "", projectOpts, reget, INDICATOR)}
    <label class="flex items-center gap-2 text-sm text-slate-600 px-2">
      <input type="checkbox" data-bind="mRep" data-on:change="${reget}" data-indicator:${INDICATOR} class="rounded border-slate-300" /> Solo con reporte
    </label>`;
}

function table(rows, wire) {
  if (!rows.length) return '<p class="text-slate-500 italic">Sin resultados.</p>';
  const thead = MEETING_COLS.map(
    (c) => `<th class="${c.align || "text-left"} ${c.w || ""} font-semibold px-3 py-2 border-b border-slate-200 sticky top-0 bg-slate-50">${escape(c.l)}</th>`
  ).join("");
  const tbody = rows
    .map(
      (r) =>
        `<tr ${wire.rowAttrs(r)} class="cursor-pointer even:bg-slate-50/60 hover:bg-indigo-50">${MEETING_COLS.map(
          (c) =>
            `<td class="px-3 py-2 border-b border-slate-100 align-top ${c.align || ""} ${c.cls || ""}">${meetingCell(c.k, r)}</td>`
        ).join("")}</tr>`
    )
    .join("");
  return `<div class="overflow-auto rounded-lg border border-slate-200 max-h-[calc(100vh-12rem)]"><table class="w-full table-fixed text-sm border-collapse">
    <thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table></div>`;
}

module.exports = {
  id: "meetings-table",
  manifest: {
    slot: "master",
    consumes: "rows",
    indicator: INDICATOR,
    overridable: ["project", "status", "has_report", "from", "to", "limit"],
  },
  signals,
  regetQS,
  controls,
  table,
  counter: (n) => `${n} reunión(es)`,
  headerExtra: "",
};

// meetings-table block — the MASTER slot over the `meetings` source: the team
// meetings list and its filter bar (project / status / solo-con-reporte —
// fixed by this block). Extracted from the hand-rolled meetings page when it
// was unified onto patterns/master-detail (Fase 0 paso 4).
//
// Same master-slot contract as tasks-table: signals / regetQS / controls /
// table(rows, wire) / counter.

const { fetchSource } = require("../lib/datasources");
const { escape, cell, selectCtl, checkCtl } = require("../lib/kit");

const MEETING_STATUS_BADGE = {
  completed: "badge-pos",
  ended: "badge-pos",
  processing: "bg-blue-100 text-blue-700",
  scheduled: "badge-cau",
  cancelled: "badge-neutral",
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
  const cls = MEETING_STATUS_BADGE[v] || "badge-neutral";
  return `<span class="badge ${cls}">${escape(MEETING_STATUS_ES[v] || v)}</span>`;
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
    ${checkCtl("mRep", "Solo con reporte", `${reget}`, { indicator: `${INDICATOR}` })}`;
}

function table(rows, wire) {
  if (!rows.length) return '<p class="text-slate-500 italic">Sin resultados.</p>';
  const thead = MEETING_COLS.map(
    (c) => `<th class="${c.align || "text-left"} ${c.w || ""}">${escape(c.l)}</th>`
  ).join("");
  const tbody = rows
    .map(
      (r) =>
        `<tr ${wire.rowAttrs(r)} class="cursor-pointer">${MEETING_COLS.map(
          (c) =>
            `<td class="align-top ${c.align || ""} ${c.cls || ""}">${meetingCell(c.k, r)}</td>`
        ).join("")}</tr>`
    )
    .join("");
  return `<div class="table-wrap"><div class="table-scroll overflow-y-auto max-h-[calc(100vh-12rem)]"><table class="tbl w-full min-w-[48rem] table-fixed">
    <thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table></div></div>`;
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

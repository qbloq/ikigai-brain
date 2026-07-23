// calls-table block — the MASTER slot over the `calls` source: the sales-call
// list for the Director Comercial (lead, programa, closer resuelto vía CRM,
// resultado, probabilidad, score) with its fixed filter bar (resultado /
// proyecto / closer / solo-analizadas). Same master contract as tasks-table:
// signals / regetQS / controls / table(rows, wire) / counter.

const { fetchSource } = require("../lib/datasources");
const { escape, cell, selectCtl } = require("../lib/kit");

const RESULT_BADGE = [
  [/^closed won/i, "bg-emerald-100 text-emerald-700"],
  [/^follow-up/i, "bg-blue-100 text-blue-700"],
  [/^rescheduled/i, "bg-amber-100 text-amber-700"],
  [/unsuccessful|unqualified/i, "bg-red-100 text-red-700"],
];
const RESULT_OPTS = [
  ["", "Resultado: todos"],
  ["Closed Won", "Ganada"],
  ["Follow-up", "Seguimiento"],
  ["Rescheduled", "Reagendada"],
  ["Unsuccessful", "No exitosa"],
  ["Unqualified", "No calificada"],
  ["No show", "No asistió"],
];

const CALL_COLS = [
  { k: "start", l: "Fecha", w: "w-28", cls: "whitespace-nowrap" },
  { k: "lead", l: "Lead", w: "w-[24%]" },
  { k: "program", l: "Programa" },
  { k: "closer", l: "Closer", w: "w-36" },
  { k: "result", l: "Resultado", w: "w-36" },
  { k: "prob", l: "Prob", w: "w-14", align: "text-center" },
  { k: "score", l: "Score", w: "w-14", align: "text-center" },
];

function resultBadge(v) {
  if (!v) return '<span class="text-slate-300">—</span>';
  const cls = (RESULT_BADGE.find(([re]) => re.test(v)) || [null, "bg-slate-100 text-slate-600"])[1];
  return `<span class="text-[11px] font-medium px-2 py-0.5 rounded-full ${cls}" title="${escape(v)}">${escape(v.length > 22 ? v.slice(0, 21) + "…" : v)}</span>`;
}

function callCell(col, r) {
  if (col === "result") return resultBadge(r[col]);
  if (col === "start") return cell(String(r[col] || "").slice(0, 10));
  if (col === "prob") return r[col] === "" || r[col] == null ? "—" : `${escape(r[col])}%`;
  return cell(r[col]);
}

const INDICATOR = "loadingcalls";

function signals(p) {
  return {
    cResult: p.result || "",
    cProject: p.project || "",
    cCloser: p.closer || "",
    cReported: p.reported === "1" || p.reported === "true",
  };
}

const regetQS =
  `'limit=0&result='+encodeURIComponent($cResult)+'&project='+encodeURIComponent($cProject)` +
  `+'&closer='+encodeURIComponent($cCloser)+'&reported='+$cReported`;

function controls(p, reget) {
  let projectOpts = [["", "Proyecto: todos"]];
  let closerOpts = [["", "Closer: todos"]];
  try {
    projectOpts = projectOpts.concat(fetchSource("projects").rows.map((r) => [r.name, r.name]).filter(([n]) => n));
  } catch {
    /* keep the "todos" fallback */
  }
  try {
    closerOpts = closerOpts.concat(
      fetchSource("call_stats", { by: "closer" })
        .rows.map((r) => r.closer)
        .filter((n) => n && n !== "(sin resolver)")
        .map((n) => [n, n])
    );
  } catch {
    /* keep the "todos" fallback */
  }
  return `${selectCtl("cResult", p.result || "", RESULT_OPTS, reget, INDICATOR)}
    ${selectCtl("cProject", p.project || "", projectOpts, reget, INDICATOR)}
    ${selectCtl("cCloser", p.closer || "", closerOpts, reget, INDICATOR)}
    <label class="flex items-center gap-2 text-sm text-slate-600 px-2">
      <input type="checkbox" data-bind="cReported" data-on:change="${reget}" data-indicator:${INDICATOR} class="rounded border-slate-300" /> Solo analizadas
    </label>`;
}

function table(rows, wire) {
  if (!rows.length) return '<p class="text-slate-500 italic">Sin resultados.</p>';
  const thead = CALL_COLS.map(
    (c) => `<th class="${c.align || "text-left"} ${c.w || ""} font-semibold px-3 py-2 border-b border-slate-200 sticky top-0 bg-slate-50">${escape(c.l)}</th>`
  ).join("");
  const tbody = rows
    .map(
      (r) =>
        `<tr ${wire.rowAttrs(r)} class="cursor-pointer even:bg-slate-50/60 hover:bg-indigo-50">${CALL_COLS.map(
          (c) =>
            `<td class="px-3 py-2 border-b border-slate-100 align-top ${c.align || ""} ${c.cls || ""}">${callCell(c.k, r)}</td>`
        ).join("")}</tr>`
    )
    .join("");
  return `<div class="overflow-auto rounded-lg border border-slate-200 max-h-[calc(100vh-12rem)]"><table class="w-full table-fixed text-sm border-collapse">
    <thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table></div>`;
}

module.exports = {
  id: "calls-table",
  manifest: {
    slot: "master",
    consumes: "rows",
    indicator: INDICATOR,
    overridable: ["status", "result", "project", "program", "closer", "from", "to", "reported", "sin_closer", "limit"],
  },
  signals,
  regetQS,
  controls,
  table,
  counter: (n) => `${n} llamada(s)`,
  headerExtra: "",
};

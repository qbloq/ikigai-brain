// meetings page — master-detail over team meetings (bash/meetings/meetings.sh).
// Left: a list with a filter bar (project / status / solo con reporte);
// clicking a row hits GET /meeting/:id, which SSE-patches the #meeting-detail
// side panel with that meeting's structured report. Mirrors the tasks
// component (a hand-rolled instance of the master-detail shape — unifying it
// onto patterns/master-detail is Fase 0 paso 4).

const { fetchSource } = require("../lib/datasources");
const { escape, cell, selectCtl } = require("../lib/kit");
const { renderMeetingDetail } = require("../blocks/meeting-detail");

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

function meetingsTable(rows) {
  if (!rows.length) return '<p class="text-slate-500 italic">Sin resultados.</p>';
  const thead = MEETING_COLS.map(
    (c) => `<th class="${c.align || "text-left"} ${c.w || ""} font-semibold px-3 py-2 border-b border-slate-200 sticky top-0 bg-slate-50">${escape(c.l)}</th>`
  ).join("");
  const tbody = rows
    .map(
      (r) =>
        `<tr data-on:click="$selectedMeeting='${escape(r.id)}'; $detailOpen=true; @get('/meeting/${escape(r.id)}')" data-indicator:loading data-class:row-sel="$selectedMeeting==='${escape(r.id)}'" class="cursor-pointer even:bg-slate-50/60 hover:bg-indigo-50">${MEETING_COLS.map(
          (c) =>
            `<td class="px-3 py-2 border-b border-slate-100 align-top ${c.align || ""} ${c.cls || ""}">${meetingCell(c.k, r)}</td>`
        ).join("")}</tr>`
    )
    .join("");
  return `<div class="overflow-auto rounded-lg border border-slate-200 max-h-[calc(100vh-12rem)]"><table class="w-full table-fixed text-sm border-collapse">
    <thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table></div>`;
}

function renderMeetings(ui) {
  const p = ui.params || {};
  const head = `<header class="mb-4 flex items-baseline gap-3">
    <h1 class="text-xl font-semibold text-slate-800">${escape(ui.name)}</h1>
    <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs text-indigo-600 hover:underline">abrir solo ↗</a>
  </header>`;

  let rows = [],
    err;
  try {
    ({ rows } = fetchSource("meetings", p));
  } catch (e) {
    err = e.message;
  }

  let projectOpts = [["", "Proyecto: todos"]];
  try {
    projectOpts = projectOpts.concat(fetchSource("projects").rows.map((r) => [r.name, r.name]).filter(([n]) => n));
  } catch {
    /* keep the "todos" fallback */
  }

  const repOn = p.has_report === "1" || p.has_report === "true";
  const reget =
    `@get('/ui/${escape(ui.id)}?limit=0&status='+$mStatus` +
    `+'&project='+encodeURIComponent($mProject)+'&has_report='+$mRep)`;
  const sig = `{mStatus:'${escape(p.status || "")}',mProject:'${escape(p.project || "")}',mRep:${repOn}}`;

  const controls = `<div class="flex flex-wrap items-center gap-2 mb-4" data-signals="${sig}">
    ${selectCtl("mStatus", p.status || "", MEETING_STATUS_OPTS, reget, "loadingmeetings")}
    ${selectCtl("mProject", p.project || "", projectOpts, reget, "loadingmeetings")}
    <label class="flex items-center gap-2 text-sm text-slate-600 px-2">
      <input type="checkbox" data-bind="mRep" data-on:change="${reget}" data-indicator:loadingmeetings class="rounded border-slate-300" /> Solo con reporte
    </label>
  </div>`;

  const body = err
    ? `<div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-4 text-sm">${escape(err)}</div>`
    : `<div class="relative">
        <div id="meetings-loading" data-class:on="$loadingmeetings" class="pointer-events-none absolute inset-0 z-10 flex items-start justify-center pt-16 bg-white/50">
          <div class="w-7 h-7 rounded-full border-2 border-slate-300 border-t-indigo-600 animate-spin"></div>
        </div>
        <p class="text-xs text-slate-400 mb-2">${rows.length} reunión(es)</p>${meetingsTable(rows)}
      </div>`;

  return `<section id="pane" class="flex-1 overflow-hidden flex" data-signals="{detailOpen:false,selectedMeeting:''}">
    <style>
      #detail-wrap{width:0;opacity:0;overflow:hidden;transition:width .3s ease-in-out,opacity .3s ease-in-out;}
      #detail-wrap.is-open{width:32rem;opacity:1;border-left:1px solid rgb(226 232 240);}
      #detail-loading,#meetings-loading{opacity:0;transition:opacity .2s ease;}
      #detail-loading.on,#meetings-loading.on{opacity:1;}
      tr.row-sel{background:rgb(238 242 255)!important;box-shadow:inset 3px 0 0 rgb(79 70 229);}
    </style>
    <div class="flex-1 p-6 overflow-auto bg-slate-50">${head}${controls}${body}</div>
    <aside id="detail-wrap" data-class:is-open="$detailOpen" class="relative shrink-0 bg-white">
      <div id="detail-loading" data-class:on="$loading" class="pointer-events-none absolute inset-0 z-10 flex items-center justify-center bg-white/50">
        <div class="w-7 h-7 rounded-full border-2 border-slate-300 border-t-indigo-600 animate-spin"></div>
      </div>
      ${renderMeetingDetail("")}
    </aside>
  </section>`;
}

module.exports = {
  id: "meetings",
  manifest: {
    consumes: "rows",
    // project/status/has_report drive the filter bar; from/to keep date-ranged
    // URLs addressable (/u/:id?from=…) even though no control emits them yet.
    overridable: ["project", "status", "has_report", "from", "to", "limit"],
  },
  render: renderMeetings,
};

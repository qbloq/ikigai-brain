// tasks-table block — the task list table used by the master-detail pattern
// (pages `tasks` and `task-editor`), plus the filter-bar option lists that go
// with it. Custom rendering: drops the id column, renders priority as a
// traffic-light dot, and formats the due date as "Mmm D" in Spanish.

const { escape, cell, dueFmt, priorityDot } = require("../lib/kit");

const STATUS_OPTS = [
  ["", "Estado: todos"],
  ["pending", "Pendiente"],
  ["in_progress", "En progreso"],
  ["completed", "Completada"],
  ["blocked", "Bloqueada"],
  ["cancelled", "Cancelada"],
];
const PRIORITY_OPTS = [
  ["", "Prioridad: todas"],
  ["High", "Alta"],
  ["Medium", "Media"],
  ["Low", "Baja"],
];
const DUE_OPTS = [
  ["", "Vencimiento: todos"],
  ["overdue", "Vencidas"],
  ["today", "Hoy"],
  ["tomorrow", "Mañana"],
  ["this-week", "Esta semana"],
  ["next-week", "Próxima semana"],
];

// Per-column meta: width (table-fixed) + cell behavior. Título cedes width to
// Vence; long titles truncate with a tooltip.
const TASK_COLS = [
  { k: "source_type", l: "", w: "w-8", align: "text-center" },
  { k: "title", l: "Título", w: "w-[40%]", sort: true },
  { k: "status", l: "Estado", w: "w-24" },
  { k: "priority", l: "Prioridad", w: "w-16", align: "text-center" },
  { k: "due", l: "Vence", w: "w-24", cls: "whitespace-nowrap", sort: true },
  { k: "project", l: "Proyecto" },
  { k: "assignees", l: "Responsables" },
];
// At-a-glance provenance icon per row (full detail in the side panel).
const SOURCE_ICON = {
  meeting: { i: "🎙️", t: "Reunión" },
  notion: { i: "📄", t: "Notion" },
  manual: { i: "✍️", t: "Manual" },
  other: { i: "🔗", t: "Externo" },
};
function sourceIcon(v) {
  const s = SOURCE_ICON[v];
  if (!s) return '<span class="text-slate-300" title="Sin origen">·</span>';
  return `<span title="Origen: ${escape(s.t)}">${s.i}</span>`;
}

function taskCell(col, r) {
  if (col === "source_type") return sourceIcon(r[col]);
  if (col === "priority") return priorityDot(r[col]);
  if (col === "due") return dueFmt(r[col]);
  return cell(r[col]);
}

// `s` = sort state {key, dir, reget} — cols flagged `sort: true` get a clickable
// header that toggles $tSort/$tDir and re-fetches like the filter bar does.
function tasksTable(rows, edit = false, s = null) {
  if (!rows.length) return '<p class="text-slate-500 italic">Sin resultados.</p>';
  const thead = TASK_COLS.map((c) => {
    const base = `${c.align || "text-left"} ${c.w || ""} font-semibold px-3 py-2 border-b border-slate-200 sticky top-0 bg-slate-50`;
    if (!c.sort || !s) return `<th class="${base}">${escape(c.l)}</th>`;
    const active = s.key === c.k;
    const arrow = active ? (s.dir === "desc" ? "▼" : "▲") : "↕";
    const click = `$tDir = ($tSort === '${c.k}' && $tDir === 'asc') ? 'desc' : 'asc'; $tSort = '${c.k}'; ${s.reget}`;
    return `<th class="${base} cursor-pointer select-none hover:text-indigo-600" title="Ordenar por ${escape(c.l)}" data-on:click="${click}" data-indicator:loadingtasks>${escape(c.l)} <span class="text-[10px] ${active ? "text-indigo-600" : "text-slate-300"}">${arrow}</span></th>`;
  }).join("");
  const tbody = rows
    .map(
      (r) =>
        `<tr data-on:click="$selectedTask='${escape(r.id)}'; $detailOpen=true; @get('/task/${escape(r.id)}${edit ? "/edit" : ""}')" data-indicator:loading data-class:row-sel="$selectedTask==='${escape(r.id)}'" class="cursor-pointer even:bg-slate-50/60 hover:bg-indigo-50">${TASK_COLS.map(
          (c) =>
            `<td class="px-3 py-2 border-b border-slate-100 align-top ${c.align || ""} ${c.cls || ""}"${c.tip ? ` title="${escape(r[c.k] ?? "")}"` : ""}>${taskCell(c.k, r)}</td>`
        ).join("")}</tr>`
    )
    .join("");
  return `<div class="overflow-auto rounded-lg border border-slate-200 max-h-[calc(100vh-12rem)]"><table class="w-full table-fixed text-sm border-collapse">
    <thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table></div>`;
}

module.exports = { tasksTable, STATUS_OPTS, PRIORITY_OPTS, DUE_OPTS };

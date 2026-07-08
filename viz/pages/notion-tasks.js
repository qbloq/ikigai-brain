// notion-tasks page — a filterable table of a Notion project's BD Avances
// tasks (source notion_project_tasks, param `project` = the project brief page
// id/url). Notion is slow, so we fetch ONCE (source is cached) and filter
// entirely in the browser via Datastar signals + data-show — flipping a filter
// never re-queries. Rows are read-only and link out to the Notion page;
// overdue tasks are highlighted.

const { fetchSource } = require("../lib/datasources");
const { escape, cell, dueFmt, jsStr, jsArr, distinct } = require("../lib/kit");

const NOTION_ESTADO_BADGE = {
  Done: "bg-emerald-100 text-emerald-700",
  "On Time": "bg-blue-100 text-blue-700",
  "In Progress": "bg-amber-100 text-amber-700",
  Archivo: "bg-slate-200 text-slate-600",
};

function notionSelect(signal, label, values, extra = "") {
  const opts =
    `<option value="">${escape(label)}</option>` +
    values.map((v) => `<option value="${escape(v)}">${escape(v)}</option>`).join("");
  return `<select data-bind="${signal}"${extra}
    class="text-sm px-3 py-2 rounded-lg border border-slate-300 bg-white focus:outline-none focus:ring-2 focus:ring-indigo-400 max-w-[16rem]">${opts}</select>`;
}

function notionTaskRow(r, today) {
  const estado = r.estado || "";
  const done = estado === "Done" || estado === "Archivo";
  const overdue = !done && r.fecha && String(r.fecha).slice(0, 10) < today;
  const fases = Array.isArray(r.fases) ? r.fases : r.fases ? [r.fases] : [];
  const asig = Array.isArray(r.asignado) ? r.asignado : r.asignado ? [r.asignado] : [];
  const show =
    `($nfEstado===''||$nfEstado===${jsStr(estado)})` +
    `&&($nfLanz===''||$nfLanz===${jsStr(r.lanzamiento || "")})` +
    `&&($nfFase===''||${jsArr(fases)}.includes($nfFase))` +
    `&&($nfAsig===''||${jsArr(asig)}.includes($nfAsig))` +
    `&&(!$nfOverdue||${overdue ? "true" : "false"})`;
  const badge = NOTION_ESTADO_BADGE[estado] || "bg-slate-100 text-slate-600";
  const titleCell = r.url
    ? `<a href="${escape(r.url)}" target="_blank" class="text-indigo-700 hover:underline">${escape(r.tarea || "—")}</a>`
    : escape(r.tarea || "—");
  return `<tr data-show="${show}" class="even:bg-slate-50/60 hover:bg-indigo-50 ${overdue ? "bg-red-50/60" : ""}">
    <td class="px-3 py-2 border-b border-slate-100 align-top ${overdue ? "border-l-2 border-l-red-400" : ""}">${titleCell}</td>
    <td class="px-3 py-2 border-b border-slate-100 align-top"><span class="text-[11px] font-medium px-2 py-0.5 rounded-full ${badge}">${escape(estado || "—")}</span></td>
    <td class="px-3 py-2 border-b border-slate-100 align-top text-slate-600">${cell(r.lanzamiento)}</td>
    <td class="px-3 py-2 border-b border-slate-100 align-top text-slate-600">${cell(fases)}</td>
    <td class="px-3 py-2 border-b border-slate-100 align-top text-slate-600">${cell(asig)}</td>
    <td class="px-3 py-2 border-b border-slate-100 align-top whitespace-nowrap ${overdue ? "text-red-600 font-medium" : "text-slate-600"}">${dueFmt(r.fecha)}${overdue ? " ⚠" : ""}</td>
  </tr>`;
}

function renderNotionTasks(ui) {
  const head = `<header class="mb-4 flex items-baseline gap-3">
    <h1 class="text-xl font-semibold text-slate-800">${escape(ui.name)}</h1>
    <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs text-indigo-600 hover:underline">abrir solo ↗</a>
  </header>`;

  let rows = [],
    err;
  try {
    ({ rows } = fetchSource(ui.source, ui.params || {}));
  } catch (e) {
    err = e.message;
  }
  if (err) {
    return `<section id="pane" class="flex-1 p-6 overflow-auto bg-slate-50">${head}
      <div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-4 text-sm">${escape(err)}</div></section>`;
  }

  const today = new Date().toISOString().slice(0, 10);
  const nOverdue = rows.filter(
    (r) => r.estado !== "Done" && r.estado !== "Archivo" && r.fecha && String(r.fecha).slice(0, 10) < today
  ).length;
  const nOpen = rows.filter((r) => r.estado === "On Time" || r.estado === "In Progress").length;

  const estados = distinct(rows, (r) => r.estado);
  const lanz = distinct(rows, (r) => r.lanzamiento);
  const fases = distinct(rows, (r) => r.fases);
  const asig = distinct(rows, (r) => r.asignado);

  const controls = `<div class="flex flex-wrap items-center gap-2 mb-4"
      data-signals="{nfEstado:'',nfLanz:'',nfFase:'',nfAsig:'',nfOverdue:false}">
    ${notionSelect("nfEstado", "Estado: todos", estados)}
    ${notionSelect("nfLanz", "Lanzamiento: todos", lanz)}
    ${notionSelect("nfFase", "Fase: todas", fases)}
    ${notionSelect("nfAsig", "Responsable: todos", asig)}
    <label class="flex items-center gap-2 text-sm text-slate-600 px-2">
      <input type="checkbox" data-bind="nfOverdue" class="rounded border-slate-300" /> Solo vencidas
    </label>
    <button data-on:click="$nfEstado='';$nfLanz='';$nfFase='';$nfAsig='';$nfOverdue=false"
      class="text-xs text-slate-500 hover:text-indigo-600 underline px-1">limpiar</button>
  </div>`;

  const kpis = `<div class="flex flex-wrap gap-4 mb-3 text-sm">
    <span class="text-slate-600"><b class="text-slate-800">${rows.length}</b> tareas</span>
    <span class="text-blue-600"><b>${nOpen}</b> abiertas</span>
    <span class="text-red-600"><b>${nOverdue}</b> vencidas</span>
  </div>`;

  const thead = ["Tarea", "Estado", "Lanzamiento", "Fase", "Responsable", "Fecha"]
    .map(
      (c) => `<th class="text-left font-semibold px-3 py-2 border-b border-slate-200 sticky top-0 bg-slate-50">${escape(c)}</th>`
    )
    .join("");
  const body = rows.length
    ? `<div class="overflow-auto rounded-lg border border-slate-200 max-h-[calc(100vh-12rem)]">
        <table class="w-full text-sm border-collapse"><thead><tr>${thead}</tr></thead>
        <tbody>${rows.map((r) => notionTaskRow(r, today)).join("")}</tbody></table></div>`
    : '<p class="text-slate-500 italic">Sin resultados.</p>';

  return `<section id="pane" class="flex-1 p-6 overflow-auto bg-slate-50">${head}${controls}${kpis}${body}</section>`;
}

// Filters run entirely in the browser (fetch once, data-show) → nothing overridable.
module.exports = { id: "notion-tasks", manifest: { consumes: "rows", overridable: [] }, render: renderNotionTasks };

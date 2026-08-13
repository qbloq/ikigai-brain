// cruce page — the reconciliation board between the PM platform's tasks and
// the cerebro's (the `cruce` table of the pm_platform LOCAL SQLite db). Rows
// come from the spec's persisted localdb_query (provenance rule: the SQL lives
// in the spec, never in the browser) and MUST expose the cruce columns by
// name: n, veredicto, confianza, accion, pm_id, pm_titulo, pm_estado,
// pm_asignado, ce_id, ce_titulo, ce_estado, ce_source, ce_proyecto, nota,
// merge, resuelta, resolucion.
//
// The board is MULTI-PROJECT since Ikigai joined it (2026-08-10): the PM
// platform files everything under David Guerrero, so the cerebro side is the
// only one that knows which project a pair really belongs to — hence the
// project filter reads `ce_proyecto`, and rows with no cerebro side (solo PM)
// answer to no project at all.
//
// Two jobs on top of the plain table:
//   1. the «resuelta» indicator — has this pair been dealt with yet?
//   2. the Merge mark — ONLY on veredicto=igual + confianza=alta rows: a
//      curation toggle persisted to the LOCAL SQLite via cruce_mark.sh
//      (manifest.writes). It marks intent; nothing touches Postgres here.
//      The actual merge runs later, from the conversation:
//      bash/tasks/merge_from_cruce.sh over the marked rows.

const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");
const store = require("../lib/store");

const MARK = "bash/localdb/cruce_mark.sh";

const VER = {
  igual: ["≡ igual", "bg-emerald-50 text-emerald-700 border-emerald-200"],
  relacionada: ["≈ relacionada", "bg-amber-50 text-amber-700 border-amber-200"],
  otro_proyecto: ["⇢ otro proyecto", "bg-violet-50 text-violet-700 border-violet-200"],
  sin_par_pm: ["◐ solo PM", "bg-sky-50 text-sky-700 border-sky-200"],
  sin_par_cerebro: ["◑ solo cerebro", "bg-slate-100 text-slate-600 border-slate-200"],
};
const EST = {
  completed: "text-emerald-600",
  in_progress: "text-sky-600",
  pending: "text-amber-600",
  cancelled: "text-slate-400",
};

function chip(txt, cls) {
  return `<span class="inline-block text-[10px] px-1.5 py-0.5 rounded border whitespace-nowrap ${cls}">${escape(txt)}</span>`;
}

function estado(v) {
  if (!v) return "";
  return `<span class="text-[10px] font-medium ${EST[v] || "text-slate-500"}">${escape(v)}</span>`;
}

// One side of the pair (PM or CE): short id + estado + date + title. The date
// shown is the completion instant when the side is completed and has one
// (marked ✔), else the due date. Empty side → em dash.
function fecha(est, due, done) {
  const d = est === "completed" && done ? `✔ ${String(done).slice(0, 10)}` : due ? String(due).slice(0, 10) : "";
  return d ? `<span class="text-[10px] text-slate-400 whitespace-nowrap">${escape(d)}</span>` : "";
}

function lado(id, est, due, done, titulo, extra) {
  if (!id) return `<span class="text-slate-300">—</span>`;
  return `<div class="min-w-0">
    <div class="flex items-center gap-1.5">
      <code class="text-[10px] text-slate-400">${escape(String(id).slice(0, 8))}</code>
      ${estado(est)}
      ${fecha(est, due, done)}
      ${extra ? `<span class="text-[10px] text-slate-400 truncate">${escape(extra)}</span>` : ""}
    </div>
    <p class="text-xs text-slate-700 break-words">${escape(titulo || "—")}</p>
  </div>`;
}

// The Merge toggle. Shown only on igual+alta rows that aren't resolved yet —
// the same guardrail cruce_mark.sh enforces server-side.
function mergeBtn(r, uiId) {
  if (!(r.veredicto === "igual" && r.confianza === "alta" && !r.resuelta)) return "";
  const post = (v) => `@post('/c/cruce/act/mark?ui=${escape(uiId)}&n=${r.n}&v=${v}')`;
  return r.merge
    ? `<button data-on:click="${post(0)}" data-indicator:loading
         class="text-[11px] px-2 py-0.5 rounded-md border border-indigo-600 bg-indigo-600 text-white hover:bg-indigo-500"
         title="Marcada para mezclar — clic para desmarcar">✓ Merge</button>`
    : `<button data-on:click="${post(1)}" data-indicator:loading
         class="text-[11px] px-2 py-0.5 rounded-md border border-indigo-300 text-indigo-600 hover:bg-indigo-50"
         title="Marcar para mezclar (duplicar con nombre PM + cancelar original)">Merge</button>`;
}

// El id de la tarea del cerebro que resolvió la fila, extraído del texto de
// `resolucion` — que es donde vive, porque el cruce no tiene columna para él
// (la resolución la escriben merge_from_cruce.sh y cruce_mark.sh como prosa).
// Dos casos distintos y no hay que confundirlos: «merge → <id>» es la tarea que
// ESTA fila creó; «subsumida por <id>» es la de OTRA fila que la absorbió. Una
// resolución sin id (p.ej. «sin acción: ambas completadas») no muestra nada.
const RE_UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;

function tareaResuelta(resolucion) {
  const m = RE_UUID.exec(resolucion || "");
  if (!m) return null;
  const creada = /^\s*merge\s*→/.test(resolucion || "");
  return { id: m[0], creada };
}

// El id + copiar. Se muestran los 8 caracteres (el handle que se dicta en la
// conversación) pero se copia el uuid COMPLETO, que es lo que piden los scripts.
function idCopiable(t, n) {
  const key = `r${n}`;
  const titulo = t.creada
    ? "Tarea creada en el cerebro por esta fila — clic para copiar el id completo"
    : "Subsumida en esta tarea del cerebro — clic para copiar el id completo";
  return `<div class="mt-0.5 flex items-center justify-center gap-1 whitespace-nowrap">
    ${t.creada ? "" : `<span class="text-[10px] text-slate-400">en</span>`}
    <button data-on:click="navigator.clipboard.writeText('${t.id}');$copiado='${key}'"
      class="font-mono text-[10px] text-slate-500 hover:text-indigo-600 inline-flex items-center gap-1"
      title="${titulo}">${t.id.slice(0, 8)}<span aria-hidden="true">⧉</span></button>
    <span data-show="$copiado=='${key}'" class="text-[10px] text-emerald-600">✓</span>
  </div>`;
}

function resueltaCell(r) {
  if (!r.resuelta) return `<span class="text-[11px] text-slate-300">pendiente</span>`;
  const t = tareaResuelta(r.resolucion);
  return `<span class="text-[11px] text-emerald-600 whitespace-nowrap" title="${escape(r.resolucion || "")}">✓ resuelta</span>
    ${t ? idCopiable(t, r.n) : ""}`;
}

function fila(r, uiId) {
  const [vtxt, vcls] = VER[r.veredicto] || [r.veredicto, "bg-slate-100 text-slate-600 border-slate-200"];
  // Literal per-row data-show: filters are client-side signals over the last
  // fetched render — a filter change never re-queries (see viz/CLAUDE.md).
  const show = `($fver=='' || $fver=='${r.veredicto}') && ` +
    `($fproy=='' || $fproy=='${(r.ce_proyecto || "").replace(/'/g, "")}') && ($fest=='' ` +
    `|| ($fest=='merge' && ${r.merge ? "true" : "false"})` +
    `|| ($fest=='resueltas' && ${r.resuelta ? "true" : "false"})` +
    `|| ($fest=='abiertas' && ${r.resuelta ? "false" : "true"}))`;
  return `<tr id="cr-${r.n}" data-show="${show}" class="border-b border-slate-100 hover:bg-slate-50 align-top">
    <td class="px-2 py-1.5 text-[10px] text-slate-400">${r.n}</td>
    <td class="px-2 py-1.5">${chip(vtxt, vcls)}<div class="text-[10px] text-slate-400 mt-0.5">${escape(r.confianza || "")}</div></td>
    <td class="px-2 py-1.5 text-[11px] text-slate-600 whitespace-nowrap">${escape(r.accion || "")}</td>
    <td class="px-2 py-1.5 w-72 max-w-72">${lado(r.pm_id, r.pm_estado, r.pm_fecha, r.pm_completada, r.pm_titulo, r.pm_asignado)}</td>
    <td class="px-2 py-1.5 w-72 max-w-72">${lado(r.ce_id, r.ce_estado, r.ce_fecha, null, r.ce_titulo, [r.ce_source, r.ce_proyecto].filter(Boolean).join(" · "))}</td>
    <td class="px-2 py-1.5 text-[11px] text-slate-500 max-w-56"><span class="line-clamp-2" title="${escape(r.nota || "")}">${escape(r.nota || "")}</span></td>
    <td class="px-2 py-1.5 text-center">${resueltaCell(r)}</td>
    <td class="px-2 py-1.5 text-center">${mergeBtn(r, uiId)}</td>
  </tr>`;
}

// The re-renderable fragment: counters + table, patched whole after each act.
// `pre` lets the page render reuse rows it already fetched (for the project
// filter buttons) instead of querying twice.
function tablaFrag(ui, err, pre) {
  let rows = pre || [];
  let fail = err || null;
  if (!pre) {
    try {
      rows = fetchSource(ui.source, ui.params || {}).rows;
    } catch (e) {
      fail = e.message;
    }
  }
  const tot = rows.length;
  const marked = rows.filter((r) => r.merge).length;
  const done = rows.filter((r) => r.resuelta).length;
  const mergeables = rows.filter((r) => r.veredicto === "igual" && r.confianza === "alta").length;
  const banner = fail
    ? `<div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-3 text-sm mb-3">${escape(fail)}</div>`
    : "";
  return `<div id="cruce-tabla" class="flex-1 min-h-0 flex flex-col">
    ${banner}
    <div class="mb-2 flex items-center gap-4 text-xs text-slate-500">
      <span><b class="text-slate-700">${tot}</b> pares</span>
      <span><b class="text-emerald-600">${done}</b> resueltas</span>
      <span><b class="text-indigo-600">${marked}</b>/${mergeables} marcadas para merge</span>
      <span class="ml-auto text-[11px] text-slate-400">merge = duplicar con nombre PM + cancelar original (se ejecuta por script al cerrar la curaduría)</span>
    </div>
    <div class="relative flex-1 min-h-0 overflow-auto rounded-lg border border-slate-200 bg-white">
      <div data-show="$loading" class="absolute inset-0 bg-white/50 flex items-center justify-center transition-opacity duration-200 z-10">
        <span class="animate-spin inline-block w-5 h-5 border-2 border-indigo-500 border-t-transparent rounded-full"></span>
      </div>
      <table class="w-full text-left border-collapse">
        <thead class="sticky top-0 bg-slate-50 text-[10px] uppercase tracking-wide text-slate-400">
          <tr>
            <th class="px-2 py-2">#</th><th class="px-2 py-2">veredicto</th><th class="px-2 py-2">acción</th>
            <th class="px-2 py-2">plataforma PM</th><th class="px-2 py-2">cerebro</th>
            <th class="px-2 py-2">nota</th><th class="px-2 py-2 text-center">resuelta</th><th class="px-2 py-2 text-center">merge</th>
          </tr>
        </thead>
        <tbody>${rows.map((r) => fila(r, ui.id)).join("")}</tbody>
      </table>
    </div>
  </div>`;
}

function filtro(sig, val, label) {
  return `<button data-on:click="$${sig}='${val}'"
    data-class="{'bg-indigo-600 text-white border-indigo-600': $${sig}=='${val}', 'text-slate-500 border-slate-200 hover:bg-slate-50': $${sig}!='${val}'}"
    class="text-[11px] px-2 py-0.5 rounded-full border">${escape(label)}</button>`;
}

function renderCruce(ui) {
  let rows = [];
  let fail = null;
  try {
    rows = fetchSource(ui.source, ui.params || {}).rows;
  } catch (e) {
    fail = e.message;
  }
  // Projects come from the data, not a constant: adding Andrea to the cruce
  // must grow the filter bar on its own.
  const proyectos = [...new Set(rows.map((r) => r.ce_proyecto).filter(Boolean))].sort();
  return `<section id="pane" class="flex-1 p-6 overflow-hidden flex flex-col"
    data-signals="{fver:'',fest:'',fproy:'',copiado:'',loading:false}">
    <header class="mb-3 flex items-baseline gap-3">
      <h1 class="text-xl font-semibold text-slate-800">${escape(ui.name)}</h1>
      <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs text-indigo-600 hover:underline">abrir solo ↗</a>
    </header>
    <div class="mb-3 flex flex-wrap items-center gap-1.5">
      ${filtro("fver", "", "todas")}
      ${Object.entries(VER).map(([k, [t]]) => filtro("fver", k, t)).join("")}
      <span class="mx-2 text-slate-300">·</span>
      ${filtro("fest", "", "todo estado")}
      ${filtro("fest", "abiertas", "sin resolver")}
      ${filtro("fest", "merge", "marcadas merge")}
      ${filtro("fest", "resueltas", "resueltas")}
      ${proyectos.length > 1 ? `<span class="mx-2 text-slate-300">·</span>
      ${filtro("fproy", "", "todo proyecto")}
      ${proyectos.map((p) => filtro("fproy", p, p)).join("")}` : ""}
    </div>
    ${tablaFrag(ui, fail, rows)}
  </section>`;
}

const frags = {
  tabla: (ctx) => {
    const ui = store.get(ctx.params.get("ui") || "");
    if (!ui) return `<div id="cruce-tabla" class="p-4 text-sm text-red-600">UI desconocida.</div>`;
    return tablaFrag(ui);
  },
};

const acts = {
  // Toggle the merge mark of one row, then re-render the fragment. The write
  // is LOCAL (SQLite curation mark); cruce_mark.sh re-enforces the igual+alta
  // guardrail server-side.
  mark: (ctx) => {
    const uiId = ctx.params.get("ui") || "";
    const n = ctx.params.get("n") || "";
    const v = ctx.params.get("v") === "1" ? "1" : "0";
    const r = ctx.run(MARK, [n, "--merge", v]);
    const ui = store.get(uiId);
    if (!ui) return `<div id="cruce-tabla" class="p-4 text-sm text-red-600">UI desconocida: ${escape(uiId)}</div>`;
    return tablaFrag(ui, r && r.ok === false ? r.error : null);
  },
};

module.exports = {
  id: "cruce",
  render: renderCruce,
  frags,
  acts,
  manifest: { consumes: "rows", overridable: [], writes: [MARK] },
};

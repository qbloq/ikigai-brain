// Parametrizable components — turn rows of data into HTML. For the first cut
// every UI renders as a table, with columns inferred from the data (union of
// keys, first-seen order). Adding `form`, `cards`, `stats-bar`, etc. later is
// just another case in renderUI().

const { fetchSource } = require("./datasources");
const { chipData } = require("./artifacts");

function escape(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function inferColumns(rows) {
  const seen = [];
  for (const r of rows) {
    if (r && typeof r === "object") {
      for (const k of Object.keys(r)) if (!seen.includes(k)) seen.push(k);
    }
  }
  return seen;
}

function cell(v) {
  if (v == null || v === "") return '<span class="text-slate-400">—</span>';
  if (Array.isArray(v)) return escape(v.join(", "));
  if (typeof v === "object") return escape(JSON.stringify(v));
  return escape(v);
}

function table(rows) {
  if (!rows.length) {
    return '<p class="text-slate-500 italic">Sin resultados.</p>';
  }
  const cols = inferColumns(rows);
  const thead = cols
    .map(
      (c) =>
        `<th class="text-left font-semibold px-3 py-2 border-b border-slate-200 sticky top-0 bg-slate-50">${escape(c)}</th>`
    )
    .join("");
  const tbody = rows
    .map(
      (r) =>
        `<tr class="even:bg-slate-50/60 hover:bg-indigo-50">${cols
          .map((c) => `<td class="px-3 py-2 border-b border-slate-100 align-top">${cell(r[c])}</td>`)
          .join("")}</tr>`
    )
    .join("");
  return `<div class="overflow-auto rounded-lg border border-slate-200 max-h-[calc(100vh-9rem)]"><table class="w-full text-sm border-collapse">
    <thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table></div>`;
}

// ── dashboard component ────────────────────────────────────────────────────
// Renders the financial KPI cards from the single object emitted by
// bash/metrics/dashboard.sh, plus a controls bar (project + date range) that
// re-fetches via Datastar @get with explicit query params.

function fmtVal(v, kind) {
  if (v == null || v === "") return "—";
  const n = Number(v);
  if (Number.isNaN(n)) return escape(v);
  if (kind === "money") return "$" + Math.round(n).toLocaleString("en-US");
  if (kind === "pct") return (n * 100).toFixed(1) + "%";
  if (kind === "mult") return n.toFixed(2) + "x";
  return Math.round(n).toLocaleString("en-US"); // int
}

const CARD_GROUPS = [
  [
    { key: "ingresos_brutos", label: "Ingresos brutos", fmt: "money", color: "emerald" },
    { key: "venta_programas", label: "Venta programas", fmt: "money", color: "violet" },
    { key: "num_ventas", label: "# Ventas", fmt: "int", color: "violet" },
    { key: "ticket_promedio", label: "Ticket prom.", fmt: "money", color: "violet" },
    { key: "ingreso_neto", label: "Ingreso neto", fmt: "money", color: "emerald" },
    { key: "neto_ikigai", label: "Neto Ikigai", fmt: "money", color: "blue" },
    { key: "neto_owner", label: "Neto", fmt: "money", color: "blue", labelFromOwner: true },
  ],
  [
    { key: "nuevas_n", label: "Nuevas", fmt: "int", color: "emerald" },
    { key: "nuevas_amt", label: "$ Nuevas", fmt: "money", color: "emerald" },
    { key: "cuotas_n", label: "Cuotas", fmt: "int", color: "emerald" },
    { key: "cuotas_amt", label: "$ Cuotas", fmt: "money", color: "emerald" },
    { key: "margen", label: "Margen", fmt: "pct", color: "amber" },
    { key: "costos", label: "Costos", fmt: "money", color: "red" },
  ],
  [
    { key: "pauta", label: "Pauta", fmt: "money", color: "red" },
    { key: "roas", label: "ROAS", fmt: "mult", color: "emerald" },
    { key: "profit_post_pauta", label: "Profit post-pauta", fmt: "money", color: "emerald" },
    { key: "leads", label: "Leads", fmt: "int", color: "pink" },
    { key: "cpl", label: "CPL", fmt: "money", color: "pink" },
    { key: "roas_funnel", label: "ROAS funnel", fmt: "mult", color: "emerald" },
  ],
];

const CARD_COLOR = {
  emerald: { label: "text-emerald-600", val: "text-emerald-700" },
  violet: { label: "text-violet-600", val: "text-violet-700" },
  blue: { label: "text-blue-600", val: "text-blue-700" },
  amber: { label: "text-amber-600", val: "text-amber-700" },
  red: { label: "text-red-600", val: "text-red-700" },
  pink: { label: "text-pink-600", val: "text-pink-700" },
};

function kpiCard(def, data) {
  const c = CARD_COLOR[def.color] || CARD_COLOR.emerald;
  const label = def.labelFromOwner ? `Neto ${data.owner_name || "socio"}` : def.label;
  return `<div class="bg-white rounded-xl border border-slate-200 shadow-sm px-5 py-4">
    <p class="text-xs font-semibold uppercase tracking-wide ${c.label}">${escape(label)}</p>
    <p class="mt-1 text-2xl font-bold ${c.val}">${escape(fmtVal(data[def.key], def.fmt))}</p>
  </div>`;
}

function renderDashboard(ui) {
  let data, err;
  try {
    const { rows } = fetchSource(ui.source, ui.params || {});
    data = rows[0] || {};
  } catch (e) {
    err = e.message;
  }
  const head = `<header class="mb-5 flex items-baseline gap-3">
    <h1 class="text-xl font-semibold text-slate-800">${escape(ui.name)}</h1>
    <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs text-indigo-600 hover:underline">abrir solo ↗</a>
  </header>`;
  if (err) {
    return `<section id="pane" class="flex-1 p-6 overflow-auto">${head}
      <div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-4 text-sm">${escape(err)}</div>
    </section>`;
  }

  // project options for the selector
  let projectNames = [];
  try {
    projectNames = fetchSource("projects").rows.map((r) => r.name).filter(Boolean);
  } catch {
    /* fall back to current project */
  }
  if (!projectNames.length && data.project) projectNames = [data.project];

  const proj = data.project || "";
  const from = data.period_from || "";
  const to = data.period_to || "";

  // @get with explicit query params built from the bound signals (Datastar 1.0).
  const reget = `@get('/ui/${escape(ui.id)}?project='+encodeURIComponent($dbProject)+'&from='+$dbFrom+'&to='+$dbTo)`;
  const opts = projectNames
    .map((n) => `<option value="${escape(n)}"${n === proj ? " selected" : ""}>${escape(n)}</option>`)
    .join("");

  const inputCls =
    "text-sm px-3 py-2 rounded-lg border border-slate-300 bg-white focus:outline-none focus:ring-2 focus:ring-indigo-400";
  const controls = `<div class="flex flex-wrap items-center gap-3 mb-6"
      data-signals="{dbProject:'${escape(proj)}',dbFrom:'${escape(from)}',dbTo:'${escape(to)}'}">
    <select data-bind="dbProject" data-on:change="${reget}" class="${inputCls} font-medium">${opts}</select>
    <input type="date" data-bind="dbFrom" data-on:change="${reget}" class="${inputCls}" />
    <span class="text-slate-400">~</span>
    <input type="date" data-bind="dbTo" data-on:change="${reget}" class="${inputCls}" />
  </div>`;

  const grid = CARD_GROUPS.map(
    (group) =>
      `<div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3 mb-3">${group
        .map((def) => kpiCard(def, data))
        .join("")}</div>`
  ).join("");

  return `<section id="pane" class="flex-1 p-6 overflow-auto bg-slate-50">${head}${controls}${grid}</section>`;
}

// ── sop-tree component ─────────────────────────────────────────────────────
// Navigate the process ontology: macro-process → SOP → activity archetypes.
// Rows come from bash/catalog/sops.sh (one row per archetype). Renders a
// collapsible tree with native <details> (no JS), plus a macro filter that
// re-fetches via Datastar @get (mirrors the dashboard pattern).

function groupBy(rows, keyFn) {
  const order = [];
  const map = new Map();
  for (const r of rows) {
    const k = keyFn(r);
    if (!map.has(k)) {
      map.set(k, []);
      order.push(k);
    }
    map.get(k).push(r);
  }
  return order.map((k) => [k, map.get(k)]);
}

function sopBlock(sopRows) {
  const s = sopRows[0];
  // archetype rows; a SOP with no archetypes comes back as a single null-archetype row
  const acts = sopRows.filter((r) => r.archetype);
  const items = acts.length
    ? acts
        .map((a) => {
          const gate = a.gate === true || a.gate === "t" || a.gate === "true";
          const n = Number(a.tasks) || 0;
          return `<li class="flex items-baseline gap-2 px-3 py-1.5 border-b border-slate-100 last:border-0 hover:bg-indigo-50/60">
            <span class="font-mono text-xs text-indigo-600 shrink-0 w-12">${escape(a.archetype)}</span>
            <span class="text-xs text-slate-400 shrink-0 w-28 truncate">${escape(a.verb)}</span>
            <span class="text-sm text-slate-700 flex-1">${escape(a.activity)}</span>
            ${gate ? '<span class="text-[10px] font-semibold uppercase tracking-wide text-amber-700 bg-amber-100 rounded px-1.5 py-0.5 shrink-0">gate</span>' : ""}
            <span class="text-xs ${n ? "text-slate-600" : "text-slate-300"} shrink-0 w-14 text-right" title="tareas que instancian este arquetipo">${n} ${n === 1 ? "tarea" : "tareas"}</span>
          </li>`;
        })
        .join("")
    : '<li class="px-3 py-2 text-sm text-slate-400 italic">Sin arquetipos.</li>';
  return `<details class="border border-slate-200 rounded-lg overflow-hidden bg-white">
    <summary class="cursor-pointer select-none px-3 py-2 bg-slate-50 hover:bg-slate-100 flex items-baseline gap-2">
      <span class="font-mono text-xs font-semibold text-slate-500 shrink-0">${escape(s.sop)}</span>
      <span class="text-sm font-medium text-slate-800">${escape(s.sop_name)}</span>
      <span class="text-xs text-slate-400">· ${acts.length} act.</span>
      ${s.roles ? `<span class="ml-auto text-xs text-slate-400 truncate max-w-[40%]" title="${escape(s.roles)}">${escape(s.roles)}</span>` : ""}
    </summary>
    <ul>${items}</ul>
  </details>`;
}

function macroBlock(macroRows) {
  const m = macroRows[0];
  const sops = groupBy(macroRows, (r) => r.sop);
  const nActs = macroRows.filter((r) => r.archetype).length;
  const blocks = sops.map(([, rows]) => sopBlock(rows)).join("");
  return `<details open class="mb-3">
    <summary class="cursor-pointer select-none px-3 py-2 rounded-lg bg-indigo-600 text-white flex items-baseline gap-2">
      <span class="font-mono text-sm font-bold shrink-0">${escape(m.macro)}</span>
      <span class="text-sm font-semibold">${escape(m.macro_name)}</span>
      <span class="ml-auto text-xs text-indigo-100">${sops.length} SOPs · ${nActs} act.</span>
    </summary>
    <div class="mt-2 space-y-2 pl-2 border-l-2 border-indigo-100">${blocks}</div>
  </details>`;
}

function renderSopTree(ui) {
  const head = `<header class="mb-4 flex items-baseline gap-3">
    <h1 class="text-xl font-semibold text-slate-800">${escape(ui.name)}</h1>
    <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs text-indigo-600 hover:underline">abrir solo ↗</a>
  </header>`;
  // Fetch the FULL catalog once (datasources caches it) and filter by macro in
  // JS — one query covers every macro, so flipping the dropdown is a cache hit.
  let all, err;
  try {
    ({ rows: all } = fetchSource(ui.source));
  } catch (e) {
    err = e.message;
  }
  if (err) {
    return `<section id="pane" class="flex-1 p-6 overflow-auto">${head}
      <div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-4 text-sm">${escape(err)}</div>
    </section>`;
  }

  // macro + role filters applied in JS over the cached catalog (no extra query).
  // A SOP's roles come as a comma-joined string of owner_roles; the role filter
  // keeps whole SOPs (roles are per-SOP, so every archetype row carries them).
  const current = (ui.params && ui.params.macro) || "";
  const curRole = (ui.params && ui.params.role) || "";
  let rows = current ? all.filter((r) => r.macro === current) : all;
  if (curRole) rows = rows.filter((r) => (r.roles || "").split(", ").includes(curRole));
  const macros = groupBy(all, (r) => r.macro).map(([code, rs]) => ({ code, name: rs[0].macro_name }));
  const roles = [...new Set(all.flatMap((r) => (r.roles || "").split(", ").filter(Boolean)))].sort((a, b) =>
    a.localeCompare(b, "es")
  );
  const reget = `@get('/ui/${escape(ui.id)}?macro='+$sopMacro+'&role='+encodeURIComponent($sopRole))`;
  const opts =
    `<option value="">Todos los macro-procesos</option>` +
    macros
      .map((m) => `<option value="${escape(m.code)}"${m.code === current ? " selected" : ""}>${escape(m.code)} · ${escape(m.name)}</option>`)
      .join("");
  const roleOpts =
    `<option value="">Todos los roles</option>` +
    roles
      .map((r) => `<option value="${escape(r)}"${r === curRole ? " selected" : ""}>${escape(r)}</option>`)
      .join("");
  const selectCls =
    "text-sm px-3 py-2 rounded-lg border border-slate-300 bg-white focus:outline-none focus:ring-2 focus:ring-indigo-400 font-medium";
  const controls = `<div class="mb-4 flex gap-2" data-signals="{sopMacro:'${escape(current)}',sopRole:'${escape(curRole)}'}">
    <select data-bind="sopMacro" data-on:change="${reget}" class="${selectCls}">${opts}</select>
    <select data-bind="sopRole" data-on:change="${reget}" class="${selectCls}">${roleOpts}</select>
  </div>`;

  const body = rows.length
    ? groupBy(rows, (r) => r.macro).map(([, rs]) => macroBlock(rs)).join("")
    : '<p class="text-slate-500 italic">Sin resultados.</p>';

  return `<section id="pane" class="flex-1 p-6 overflow-auto bg-slate-50">${head}${controls}${body}</section>`;
}

// ── tasks component ────────────────────────────────────────────────────────
// One task list with a filter bar (status + general filters). Each control
// re-fetches via Datastar @get with explicit query params (server-side, fresh
// data — tasks are live, so no cache). Replaces the separate "abiertas" /
// "vencidas" UIs: "vencidas" is just due=overdue + open.

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

// Custom task table: drops the id column, renders priority as a traffic-light
// dot, and formats the due date as "Mmm D" in Spanish (e.g. Ene 23).
// Per-column meta: width (table-fixed) + cell behavior. Título cedes width to
// Vence; long titles truncate with a tooltip.
const TASK_COLS = [
  { k: "source_type", l: "", w: "w-8", align: "text-center" },
  { k: "title", l: "Título", w: "w-[40%]" },
  { k: "status", l: "Estado", w: "w-24" },
  { k: "priority", l: "Prioridad", w: "w-16", align: "text-center" },
  { k: "due", l: "Vence", w: "w-24", cls: "whitespace-nowrap" },
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
const PRIORITY_DOT = {
  High: { c: "bg-red-500", t: "Alta" },
  Medium: { c: "bg-amber-400", t: "Media" },
  Low: { c: "bg-emerald-500", t: "Baja" },
};
const MESES = ["Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"];

function priorityDot(v) {
  const d = PRIORITY_DOT[v];
  if (!d) return cell(v);
  return `<span class="inline-block w-2.5 h-2.5 rounded-full ${d.c}" title="${escape(d.t)}"></span>`;
}

function dueFmt(v) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(v ?? ""));
  if (!m) return cell(v);
  const mon = MESES[Number(m[2]) - 1] || m[2];
  return `${mon} ${Number(m[3])}`;
}

function taskCell(col, r) {
  if (col === "source_type") return sourceIcon(r[col]);
  if (col === "priority") return priorityDot(r[col]);
  if (col === "due") return dueFmt(r[col]);
  return cell(r[col]);
}

function tasksTable(rows, edit = false) {
  if (!rows.length) return '<p class="text-slate-500 italic">Sin resultados.</p>';
  const thead = TASK_COLS.map(
    (c) => `<th class="${c.align || "text-left"} ${c.w || ""} font-semibold px-3 py-2 border-b border-slate-200 sticky top-0 bg-slate-50">${escape(c.l)}</th>`
  ).join("");
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

function selectCtl(signal, current, options, reget, indicator = "loadingtasks") {
  const opts = options
    .map(([v, l]) => `<option value="${escape(v)}"${String(v) === String(current) ? " selected" : ""}>${escape(l)}</option>`)
    .join("");
  return `<select data-bind="${signal}" data-on:change="${reget}" data-indicator:${indicator}
    class="text-sm px-3 py-2 rounded-lg border border-slate-300 bg-white focus:outline-none focus:ring-2 focus:ring-indigo-400">${opts}</select>`;
}

// Shared task master-detail. `edit=false` → read-only detail panel (renderTasks);
// `edit=true` → editable IO form panel (renderTaskEditor). The only differences
// are the row-click route (/task/:id vs /task/:id/edit), the detail-panel width,
// and which panel renderer seeds #task-detail. Filters/list are identical.
function tasksMasterDetail(ui, edit) {
  const p = ui.params || {};
  const head = `<header class="mb-4 flex items-baseline gap-3">
    <h1 class="text-xl font-semibold text-slate-800">${escape(ui.name)}</h1>
    <span id="tasks-meta" class="text-xs text-slate-400"></span>
    <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs text-indigo-600 hover:underline">abrir solo ↗</a>
  </header>`;

  let rows = [],
    err;
  try {
    ({ rows } = fetchSource("tasks", p));
  } catch (e) {
    err = e.message;
  }

  // options for the project/assignee selectors (cached reference sources)
  let projectOpts = [["", "Proyecto: todos"]];
  let memberOpts = [["", "Responsable: todos"]];
  try {
    projectOpts = projectOpts.concat(fetchSource("projects").rows.map((r) => [r.name, r.name]).filter(([n]) => n));
  } catch {
    /* keep the "todos" fallback */
  }
  try {
    memberOpts = memberOpts.concat(fetchSource("team").rows.map((r) => [r.name, r.name]).filter(([n]) => n));
  } catch {
    /* keep the "todos" fallback */
  }

  const openOn = p.open === "1" || p.open === "true";
  const reget =
    `@get('/ui/${escape(ui.id)}?limit=0&status='+$tStatus+'&priority='+$tPriority` +
    `+'&project='+encodeURIComponent($tProject)+'&assignee='+encodeURIComponent($tAssignee)` +
    `+'&due='+$tDue+'&open='+$tOpen)`;

  const sig = `{tStatus:'${escape(p.status || "")}',tPriority:'${escape(p.priority || "")}',tProject:'${escape(p.project || "")}',tAssignee:'${escape(p.assignee || "")}',tDue:'${escape(p.due || "")}',tOpen:${openOn}}`;

  const controls = `<div class="flex flex-wrap items-center gap-2 mb-4" data-signals="${sig}">
    ${selectCtl("tStatus", p.status || "", STATUS_OPTS, reget)}
    ${selectCtl("tPriority", p.priority || "", PRIORITY_OPTS, reget)}
    ${selectCtl("tProject", p.project || "", projectOpts, reget)}
    ${selectCtl("tAssignee", p.assignee || "", memberOpts, reget)}
    ${selectCtl("tDue", p.due || "", DUE_OPTS, reget)}
    <label class="flex items-center gap-2 text-sm text-slate-600 px-2">
      <input type="checkbox" data-bind="tOpen" data-on:change="${reget}" data-indicator:loadingtasks class="rounded border-slate-300" /> Solo abiertas
    </label>
  </div>`;

  const body = err
    ? `<div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-4 text-sm">${escape(err)}</div>`
    : `<div class="relative">
        <div id="tasks-loading" data-class:on="$loadingtasks" class="pointer-events-none absolute inset-0 z-10 flex items-start justify-center pt-16 bg-white/50">
          <div class="w-7 h-7 rounded-full border-2 border-slate-300 border-t-indigo-600 animate-spin"></div>
        </div>
        <p class="text-xs text-slate-400 mb-2">${rows.length} tarea(s)</p>${tasksTable(rows, edit)}
      </div>`;

  // master-detail inside the pane. #detail-wrap PERSISTS (never replaced by SSE)
  // so its width/opacity transition fires every open/close; only its inner
  // #task-detail is swapped by the /task/:id route. Closed by default; the
  // .is-open class (base CSS = closed) avoids a Tailwind w-0/w-96 conflict and
  // a load-time flash. `detailOpen` lives on #pane, which resets on filter.
  return `<section id="pane" class="flex-1 overflow-hidden flex" data-signals="{detailOpen:false,selectedTask:''}">
    <style>
      #detail-wrap{width:0;opacity:0;overflow:hidden;transition:width .3s ease-in-out,opacity .3s ease-in-out;}
      #detail-wrap.is-open{width:${edit ? "34rem" : "24rem"};opacity:1;border-left:1px solid rgb(226 232 240);}
      #detail-loading,#tasks-loading{opacity:0;transition:opacity .2s ease;}
      #detail-loading.on,#tasks-loading.on{opacity:1;}
      tr.row-sel{background:rgb(238 242 255)!important;box-shadow:inset 3px 0 0 rgb(79 70 229);}
    </style>
    <div class="flex-1 p-6 overflow-auto bg-slate-50">${head}${controls}${body}</div>
    <aside id="detail-wrap" data-class:is-open="$detailOpen" class="relative shrink-0 bg-white">
      <div id="detail-loading" data-class:on="$loading" class="pointer-events-none absolute inset-0 z-10 flex items-center justify-center bg-white/50">
        <div class="w-7 h-7 rounded-full border-2 border-slate-300 border-t-indigo-600 animate-spin"></div>
      </div>
      ${edit ? renderTaskEditForm("") : renderTaskDetail("")}
    </aside>
  </section>`;
}

function renderTasks(ui) {
  return tasksMasterDetail(ui, false);
}

function renderTaskEditor(ui) {
  return tasksMasterDetail(ui, true);
}

// ── task detail panel (#task-detail) ───────────────────────────────────────
// View-only detail for one task: header + inputs/outputs (IO) + acceptance
// criteria (validation). Patched into #task-detail by the /task/:id route.

const STATUS_BADGE = {
  pending: "bg-amber-100 text-amber-700",
  in_progress: "bg-blue-100 text-blue-700",
  completed: "bg-emerald-100 text-emerald-700",
  blocked: "bg-red-100 text-red-700",
  cancelled: "bg-slate-200 text-slate-600",
};
const STATUS_ES = {
  pending: "Pendiente",
  in_progress: "En progreso",
  completed: "Completada",
  blocked: "Bloqueada",
  cancelled: "Cancelada",
};

// The inner SSE target. Fixed width (w-96) so content doesn't reflow while the
// persistent #detail-wrap animates its width open/closed — it slides into view.
function panelShell(inner) {
  return `<div id="task-detail" class="w-96 h-full overflow-y-auto">${inner}</div>`;
}

function taskDetailEmpty() {
  return panelShell(
    `<div class="h-full flex items-center justify-center p-8 text-center text-sm text-slate-400">
      <p>Selecciona una tarea para ver su detalle.</p>
    </div>`
  );
}

function doneMark(ok, okT, noT) {
  return ok
    ? `<span class="text-emerald-600 shrink-0" title="${escape(okT)}">✓</span>`
    : `<span class="text-slate-300 shrink-0" title="${escape(noT)}">○</span>`;
}

function ioList(items, doneKey, okT, noT) {
  if (!items || !items.length) return '<p class="text-xs text-slate-400 italic">— ninguno</p>';
  return `<ul class="space-y-1.5">${items
    .map(
      (it) => `<li class="flex items-start gap-2">
        ${doneMark(it[doneKey], okT, noT)}
        <div class="min-w-0">
          <p class="text-sm text-slate-700">${escape(it.title)}</p>
          <p class="text-xs text-slate-400">${escape(it.io_type || "—")}${it.is_required ? "" : " · opcional"}</p>
        </div>
      </li>`
    )
    .join("")}</ul>`;
}

function criteriaList(items) {
  if (!items || !items.length) return '<p class="text-xs text-slate-400 italic">— sin criterios</p>';
  return `<ul class="space-y-1.5">${items
    .map(
      (c) => `<li class="flex items-start gap-2">
        ${doneMark(c.is_met, "cumplido", "pendiente")}
        <div class="min-w-0">
          <p class="text-sm text-slate-700">${escape(c.criterion)}</p>
          <p class="text-xs text-slate-400">${escape(c.method || "—")}${c.is_required ? "" : " · opcional"} · sobre: ${escape(c.output || "—")}</p>
        </div>
      </li>`
    )
    .join("")}</ul>`;
}

function commentsList(items) {
  if (!items || !items.length) return '<p class="text-xs text-slate-400 italic">— sin comentarios</p>';
  return `<ul class="space-y-2.5">${items
    .map(
      (c) => `<li>
        <div class="flex items-baseline gap-2 text-xs text-slate-400 mb-0.5">
          <span class="font-medium text-slate-600">${escape(c.author || "—")}</span>
          <span>${escape(c.date || "")}</span>
        </div>
        <p class="text-sm text-slate-700 whitespace-pre-wrap">${escape(c.text || "")}</p>
      </li>`
    )
    .join("")}</ul>`;
}

function section(title, count, inner) {
  return `<div class="mb-5">
    <h3 class="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2">${escape(title)}${count != null ? ` · ${count}` : ""}</h3>
    ${inner}
  </div>`;
}

// The Actividad → SOP card (archetype id + name/verb, with its macro › sop path).
// Shared by the read-only detail panel and the IO editor. `a` is d.archetype
// (null when the task is untagged → renders nothing).
function activityBlock(a) {
  if (!a) return "";
  return `<div class="mb-5 rounded-lg bg-indigo-50 border border-indigo-100 px-3 py-2">
    <p class="text-[11px] font-semibold uppercase tracking-wide text-indigo-400">Actividad</p>
    <p class="text-sm text-slate-800"><span class="font-mono text-xs text-indigo-600">${escape(a.id)}</span> · ${escape(a.name)}${a.verb ? ` <span class="text-xs text-slate-400">(${escape(a.verb)})</span>` : ""}</p>
    ${a.sop ? `<p class="text-xs text-slate-400 mt-0.5">${escape(a.macro)} ${escape(a.macro_name || "")} › ${escape(a.sop)} ${escape(a.sop_name || "")}</p>` : ""}
  </div>`;
}

// Inline ID chip for the editor subtitle: shows only the short prefix, with an
// icon button that copies the FULL uuid to the clipboard (clipboard → check on
// success). Needs the `cp` signal seeded in the form's data-signals.
function idCopy(uuid, shortid) {
  const u = escape(uuid);
  return `<span class="inline-flex items-center gap-1 align-middle">
    <span class="font-mono text-slate-500">${escape(shortid)}</span>
    <button data-on:click="navigator.clipboard.writeText('${u}'); $cp=true; setTimeout(() => $cp=false, 1200)" title="Copiar ID completo" class="text-slate-400 hover:text-indigo-600 leading-none">
      <svg data-show="!$cp" xmlns="http://www.w3.org/2000/svg" class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></svg>
      <svg data-show="$cp" xmlns="http://www.w3.org/2000/svg" class="w-3.5 h-3.5 text-emerald-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5 13l4 4L19 7"/></svg>
    </button>
  </span>`;
}

// Provenance chip: where the task came from. Notion → clickable ↗ link; meeting
// → its name; manual/other → a label. Empty when the task has no source.
function sourceBlock(s) {
  if (!s || typeof s !== "object" || Array.isArray(s)) return "";
  const T = {
    notion: { icon: "📄", label: "Notion" },
    meeting: { icon: "🎙️", label: "Reunión" },
    manual: { icon: "✍️", label: "Manual" },
    other: { icon: "🔗", label: "Externo" },
  };
  const t = T[s.type] || { icon: "🔗", label: s.type || "Origen" };
  let inner;
  if (s.url) {
    inner = `<a href="${escape(s.url)}" target="_blank" class="text-indigo-600 hover:underline truncate">${escape(t.label)} ↗</a>`;
  } else if (s.meeting_name || s.meeting_id) {
    inner = `<span class="text-slate-700 truncate">${escape(t.label)} · ${escape(s.meeting_name || s.meeting_id)}</span>`;
  } else if (s.type) {
    inner = `<span class="text-slate-700">${escape(t.label)}</span>`;
  } else {
    return "";
  }
  return `<div class="mb-5 flex items-center gap-1.5 text-xs bg-slate-50 border border-slate-200 rounded px-2.5 py-1.5">
    <span class="text-[11px] font-semibold uppercase tracking-wide text-slate-400 shrink-0">Origen</span>
    <span class="shrink-0">${t.icon}</span>${inner}
  </div>`;
}

function renderTaskDetail(id) {
  if (!id) return taskDetailEmpty();
  let d, err;
  try {
    const { rows } = fetchSource("task_detail", { id });
    d = rows[0];
  } catch (e) {
    err = e.message;
  }
  if (err || !d) {
    return panelShell(
      `<div class="p-5"><div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-3 text-sm">${escape(err || "Tarea no encontrada")}</div></div>`
    );
  }
  const badge = STATUS_BADGE[d.status] || "bg-slate-100 text-slate-600";
  const prio = PRIORITY_DOT[d.priority];
  const header = `<div class="flex items-start gap-2 mb-1">
      <button data-on:click="$detailOpen=false; $selectedTask=''" class="ml-auto -mr-1 -mt-1 text-slate-400 hover:text-slate-600 text-lg leading-none" title="Cerrar">✕</button>
    </div>
    <h2 class="text-base font-semibold text-slate-800 mb-2 -mt-6 pr-6">${escape(d.title)}</h2>
    <div class="flex flex-wrap items-center gap-2 mb-3">
      <span class="text-[11px] font-medium px-2 py-0.5 rounded-full ${badge}">${escape(STATUS_ES[d.status] || d.status)}</span>
      ${prio ? `<span class="inline-flex items-center gap-1.5 text-xs text-slate-600"><span class="inline-block w-2.5 h-2.5 rounded-full ${prio.c}"></span>${escape(prio.t)}</span>` : ""}
    </div>
    <dl class="text-sm space-y-1 mb-5">
      <div class="flex gap-2"><dt class="text-slate-400 w-24 shrink-0">Proyecto</dt><dd class="text-slate-700">${cell(d.project)}</dd></div>
      <div class="flex gap-2"><dt class="text-slate-400 w-24 shrink-0">Responsables</dt><dd class="text-slate-700">${cell(d.assignees)}</dd></div>
      <div class="flex gap-2"><dt class="text-slate-400 w-24 shrink-0">Vence</dt><dd class="text-slate-700">${dueFmt(d.due)}</dd></div>
      <div class="flex gap-2"><dt class="text-slate-400 w-24 shrink-0">Creada</dt><dd class="text-slate-700">${dueFmt(d.created)}</dd></div>
    </dl>`;

  const inner = `<div class="p-5">
    ${header}
    ${sourceBlock(d.source)}
    ${activityBlock(d.archetype)}
    ${section("Inputs", (d.inputs || []).length, ioList(d.inputs, "is_satisfied", "satisfecho", "pendiente"))}
    ${section("Outputs", (d.outputs || []).length, ioList(d.outputs, "is_delivered", "entregado", "pendiente"))}
    ${section("Validación", (d.criteria || []).length, criteriaList(d.criteria))}
    ${section("Comentarios", (d.comments || []).length, commentsList(d.comments))}
  </div>`;
  return panelShell(inner);
}

// ── editable IO panel (#task-detail, "task-editor" component) ───────────────
// Editable form for one task's IO contract: per input/output you can retype the
// io_type and artifact_type, rename, toggle required, and add/remove rows. Every
// control persists immediately — one @post → update_task_io.sh (one txn) → the
// server re-renders this whole fragment. Controls bind to per-row signals and
// pass the chosen value (the type *id*) via the query string, mirroring the
// read-only filters' proven `@get('…?x='+$sig)` idiom. Header is read-only.

// A uuid is not a valid signal identifier (dashes, may start with a digit), so
// strip to [a-z0-9] and prefix per field to namespace the row's signals.
function idsig(id) {
  return String(id).replace(/[^a-z0-9]/gi, "");
}

// The editor's inner SSE target. Fixed width (matches #detail-wrap.is-open 34rem)
// so content doesn't reflow while the panel animates open/closed.
function editPanelShell(inner) {
  return `<div id="task-detail" class="w-[34rem] h-full overflow-y-auto">${inner}</div>`;
}

function ioTypeOpts(cat) {
  return [["", "— sin tipo —"]].concat((cat.io_types || []).map((t) => [t.id, t.display_name]));
}
function artifactOpts(cat) {
  return [["", "— sin artifact —"]].concat((cat.artifact_types || []).map((t) => [t.id, t.display_name]));
}

// A select bound to `signal`, initialized (via the `selected` option) to the
// row's current type id; on change it @posts the chosen value.
function editSelect(signal, current, options, post) {
  const opts = options
    .map(([v, l]) => `<option value="${escape(v)}"${String(v) === String(current ?? "") ? " selected" : ""}>${escape(l)}</option>`)
    .join("");
  return `<select id="ioc-${signal}" data-bind="${signal}" data-on:change="${post}" data-indicator:loading
    class="w-full text-sm px-2 py-1.5 rounded-md border border-slate-300 bg-white focus:outline-none focus:ring-2 focus:ring-indigo-400">${opts}</select>`;
}

function ioEditRow(row, kind, tid, cat) {
  const sid = idsig(row.id);
  const base = `/task/${escape(tid)}/io/${escape(row.id)}`;
  const titlePost = `@post('${base}/field/title?value='+encodeURIComponent($t_${sid}))`;
  const iotPost = `@post('${base}/field/io_type?value='+encodeURIComponent($iot_${sid}))`;
  const artPost = `@post('${base}/field/artifact?value='+encodeURIComponent($art_${sid}))`;
  const reqPost = `@post('${base}/field/required?value='+$req_${sid})`;
  const delPost = `@post('${base}/delete')`;
  const bindPost = `@post('${base}/bind?value='+encodeURIComponent($ref_${sid}))`;
  // Stable ids (keyed by the row uuid) so Datastar's idiomorph matches each row —
  // and each bound control — to itself across re-renders. Without them a row that
  // changes size (e.g. gains the binding chip) mis-aligns siblings and one row's
  // bound values bleed into another until the next full refresh.
  return `<div id="ioerow-${sid}" class="rounded-lg border border-slate-200 p-3 mb-2 bg-white">
    <div class="flex items-center gap-2 mb-2">
      <input id="iot-${sid}" data-bind="t_${sid}" value="${escape(row.title || "")}" data-on:change="${titlePost}" data-indicator:loading
        class="flex-1 text-sm font-medium px-2 py-1.5 rounded-md border border-slate-300 focus:outline-none focus:ring-2 focus:ring-indigo-400" placeholder="Título" />
      <div class="shrink-0 flex items-center">
        <button data-show="!$del_${sid}" data-on:click="$del_${sid}=true" title="Eliminar" class="text-slate-400 hover:text-red-600 px-1.5 text-lg leading-none">✕</button>
        <span data-show="$del_${sid}" class="inline-flex items-center gap-1.5 text-xs whitespace-nowrap">
          <span class="text-slate-500">¿Eliminar?</span>
          <button data-on:click="${delPost}" data-indicator:loading class="px-2 py-0.5 rounded bg-red-600 text-white hover:bg-red-700">Sí</button>
          <button data-on:click="$del_${sid}=false" class="px-2 py-0.5 rounded border border-slate-300 text-slate-600 hover:bg-slate-50">No</button>
        </span>
      </div>
    </div>
    <div class="grid grid-cols-2 gap-2">
      <div><label class="block text-[11px] text-slate-400 mb-0.5">Tipo (IO)</label>${editSelect(`iot_${sid}`, row.io_type_id, ioTypeOpts(cat), iotPost)}</div>
      <div><label class="block text-[11px] text-slate-400 mb-0.5">Artifact</label>${editSelect(`art_${sid}`, row.artifact_type_id, artifactOpts(cat), artPost)}</div>
    </div>
    <label class="flex items-center gap-2 text-xs text-slate-600 mt-2">
      <input id="ioq-${sid}" type="checkbox" data-bind="req_${sid}"${row.is_required ? " checked" : ""} data-on:change="${reqPost}" data-indicator:loading class="rounded border-slate-300" /> Requerido
    </label>
    <div class="mt-2 pt-2 border-t border-slate-100">
      <label class="block text-[11px] text-slate-400 mb-0.5">Vínculo (instancia del artifact)</label>
      ${bindingChip(row, base, cat)}
      <div class="flex items-center gap-1.5">
        <input id="ioref-${sid}" data-bind="ref_${sid}" placeholder="Pegar enlace o ID…" data-indicator:loading
          class="flex-1 text-xs px-2 py-1.5 rounded-md border border-slate-300 focus:outline-none focus:ring-2 focus:ring-indigo-400" />
        <button data-on:click="${bindPost}; $ref_${sid}=''" data-indicator:loading class="shrink-0 text-xs px-2.5 py-1.5 rounded-md bg-indigo-600 text-white hover:bg-indigo-700">Vincular</button>
      </div>
    </div>
  </div>`;
}

// Seed every row's bound signals with its CURRENT values. Without this, Datastar
// initializes each `data-bind` signal to empty and writes it back to the control,
// wiping the server-rendered selection/value (selects show blank, checkbox clears).
// data-signals uses if-missing semantics, so re-renders after an edit don't clobber
// the user's in-flight choices. Mirrors how the read-only filters pre-seed signals.
function editSignals(rows) {
  const o = {};
  for (const r of rows || []) {
    const s = idsig(r.id);
    o[`t_${s}`] = r.title || "";
    o[`iot_${s}`] = r.io_type_id || "";
    o[`art_${s}`] = r.artifact_type_id || "";
    o[`req_${s}`] = !!r.is_required;
    o[`del_${s}`] = false; // inline "¿Eliminar?" confirm toggle for this row
    o[`ref_${s}`] = ""; // the "pegar enlace/ID" binding input
  }
  return o;
}

// Current-binding chip: renders the bound instance via its per-artifact-type
// component (icon + title/name + link) instead of a raw id. The title comes from
// reference._resolved (cached at bind time). ↻ re-resolves (when there's a url),
// ✕ desvincula. Empty when the IO has no reference yet.
function bindingChip(row, base, cat) {
  const ref = row.reference;
  if (!ref || typeof ref !== "object" || Array.isArray(ref) || !Object.keys(ref).length) return "";
  const name = (cat.artifact_types || []).find((a) => a.id === row.artifact_type_id)?.name;
  const { icon, label, href } = chipData(name, ref);
  const inner = href
    ? `<a href="${escape(href)}" target="_blank" class="text-indigo-600 hover:underline truncate">${escape(label)}</a>`
    : `<span class="text-slate-600 truncate">${escape(label)}</span>`;
  const reBtn = href
    ? `<button data-on:click="@post('${base}/bind?value='+encodeURIComponent('${escape(href)}'))" data-indicator:loading title="Re-resolver" class="shrink-0 text-slate-400 hover:text-indigo-600 leading-none">↻</button>`
    : "";
  return `<div class="flex items-center gap-1.5 mb-1 text-xs bg-slate-50 border border-slate-200 rounded px-2 py-1">
    <span class="shrink-0" title="Vinculado">${icon}</span>
    ${inner}
    ${reBtn}
    <button data-on:click="@post('${base}/unbind')" data-indicator:loading title="Desvincular" class="shrink-0 text-slate-400 hover:text-red-600 leading-none">✕</button>
  </div>`;
}

function ioEditSection(title, rows, kind, tid, cat) {
  const list =
    (rows || []).map((r) => ioEditRow(r, kind, tid, cat)).join("") ||
    '<p class="text-xs text-slate-400 italic mb-2">— ninguno —</p>';
  const addPost = `@post('/task/${escape(tid)}/io/add?kind=${kind}')`;
  const noun = kind === "inputs" ? "input" : "output";
  return `<div class="mb-5">
    <h3 class="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2">${escape(title)} · ${(rows || []).length}</h3>
    ${list}
    <button data-on:click="${addPost}" data-indicator:loading class="text-xs text-indigo-600 hover:text-indigo-800 border border-dashed border-indigo-300 rounded-md px-2.5 py-1 mt-1">+ Agregar ${noun}</button>
  </div>`;
}

// notice: a string (→ error) OR { kind: 'ok'|'warn'|'err', text } for the banner.
function renderTaskEditForm(id, notice) {
  if (!id)
    return editPanelShell(
      `<div class="h-full flex items-center justify-center p-8 text-center text-sm text-slate-400"><p>Selecciona una tarea para editar su IO.</p></div>`
    );
  let d,
    cat = { io_types: [], artifact_types: [] },
    e2;
  try {
    d = fetchSource("task_detail", { id }).rows[0];
    cat = fetchSource("io_catalog").rows[0] || cat;
  } catch (e) {
    e2 = e.message;
  }
  if (e2 || !d) {
    return editPanelShell(
      `<div class="p-5"><div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-3 text-sm">${escape(e2 || "Tarea no encontrada")}</div></div>`
    );
  }
  const close = `<button data-on:click="$detailOpen=false; $selectedTask=''" class="ml-auto -mr-1 -mt-1 text-slate-400 hover:text-slate-600 text-lg leading-none" title="Cerrar">✕</button>`;
  const n = typeof notice === "string" ? { kind: "err", text: notice } : notice;
  const NOTE_CLS = {
    ok: "border-emerald-200 bg-emerald-50 text-emerald-700",
    warn: "border-amber-200 bg-amber-50 text-amber-700",
    err: "border-red-200 bg-red-50 text-red-700",
  };
  const errBanner =
    n && n.text ? `<div class="rounded-lg border ${NOTE_CLS[n.kind] || NOTE_CLS.err} p-2.5 text-xs mb-3 break-words">${escape(n.text)}</div>` : "";
  const header = `<div class="flex items-start gap-2 mb-1">${close}</div>
    <h2 class="text-base font-semibold text-slate-800 mb-1 -mt-6 pr-6">${escape(d.title)}</h2>
    <p class="text-xs text-slate-400 mb-3">${cell(d.project)} · ${idCopy(d.uuid || id, d.id || id)}</p>`;
  const sigObj = Object.assign(editSignals([...(d.inputs || []), ...(d.outputs || [])]), { cp: false });
  const signals = escape(JSON.stringify(sigObj));
  const inner = `<div class="p-5" data-signals="${signals}">
    ${header}
    ${sourceBlock(d.source)}
    ${activityBlock(d.archetype)}
    ${errBanner}
    ${ioEditSection("Inputs", d.inputs, "inputs", id, cat)}
    ${ioEditSection("Outputs", d.outputs, "outputs", id, cat)}
  </div>`;
  return editPanelShell(inner);
}

// ── meetings component ─────────────────────────────────────────────────────
// Master-detail over team meetings (bash/meetings/meetings.sh). Left: a list
// with a filter bar (project / status / solo con reporte); clicking a row hits
// GET /meeting/:id, which SSE-patches the #meeting-detail side panel with that
// meeting's structured report. Mirrors the tasks component.

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

// ── meeting detail panel (#meeting-detail) ─────────────────────────────────
// View-only render of one team meeting's structured report (the Spanish jsonb
// from meeting_show.sh --json). Patched into #meeting-detail by /meeting/:id.

function meetingPanelShell(inner) {
  return `<div id="meeting-detail" class="w-[32rem] h-full overflow-y-auto">${inner}</div>`;
}

function meetingDetailEmpty() {
  return meetingPanelShell(
    `<div class="h-full flex items-center justify-center p-8 text-center text-sm text-slate-400">
      <p>Selecciona una reunión para ver su reporte.</p>
    </div>`
  );
}

function prose(text) {
  return `<p class="text-sm text-slate-700 whitespace-pre-wrap leading-relaxed">${escape(text)}</p>`;
}

function objectivesBlock(o) {
  if (!o || typeof o !== "object") return "";
  const row = (label, v) =>
    v
      ? `<div class="mb-2"><p class="text-[11px] font-semibold text-slate-400">${escape(label)}</p>${prose(v)}</div>`
      : "";
  const inner = row("Planteado", o.stated) + row("Logrado", o.achieved) + row("Sin resolver", o.unresolved);
  return inner ? section("Objetivos", null, inner) : "";
}

function decisionsBlock(items) {
  if (!items || !items.length) return "";
  const inner = `<ul class="space-y-3">${items
    .map(
      (d) => `<li class="border-l-2 border-indigo-100 pl-3">
        <p class="text-sm font-medium text-slate-800">${escape(d.topic || "—")}</p>
        ${d.summary ? `<p class="text-xs text-slate-500 mt-0.5">${escape(d.summary)}</p>` : ""}
        ${d.decision ? `<p class="text-sm text-slate-700 mt-1"><span class="text-[11px] font-semibold uppercase text-emerald-600">Decisión:</span> ${escape(d.decision)}</p>` : ""}
        ${d.rationale ? `<p class="text-xs text-slate-400 mt-0.5 italic">${escape(d.rationale)}</p>` : ""}
      </li>`
    )
    .join("")}</ul>`;
  return section("Decisiones", items.length, inner);
}

function actionItemsBlock(items) {
  if (!items || !items.length) return "";
  const inner = `<ul class="space-y-2.5">${items
    .map((a) => {
      const prio = PRIORITY_DOT[a.priority];
      const who = Array.isArray(a.assignedTo) ? a.assignedTo.join(", ") : a.assignedTo;
      return `<li class="flex items-start gap-2">
        ${prio ? `<span class="inline-block w-2.5 h-2.5 rounded-full ${prio.c} mt-1.5 shrink-0" title="${escape(prio.t)}"></span>` : '<span class="w-2.5 shrink-0"></span>'}
        <div class="min-w-0">
          <p class="text-sm text-slate-700">${escape(a.task)}</p>
          <p class="text-xs text-slate-400">${who ? escape(who) : "—"}${a.dueDate ? ` · ${escape(a.dueDate)}` : ""}${a.dependencies && a.dependencies !== "Ninguna" ? ` · dep: ${escape(a.dependencies)}` : ""}</p>
        </div>
      </li>`;
    })
    .join("")}</ul>`;
  return section("Action items", items.length, inner);
}

function blockersBlock(items) {
  if (!items || !items.length) return "";
  const inner = `<ul class="space-y-2.5">${items
    .map(
      (b) => `<li class="rounded-lg bg-red-50 border border-red-100 px-3 py-2">
        <p class="text-sm text-slate-800">${escape(b.issue || "—")}</p>
        ${b.status ? `<p class="text-xs text-red-600 mt-0.5">${escape(b.status)}</p>` : ""}
        ${b.nextSteps ? `<p class="text-xs text-slate-500 mt-0.5">→ ${escape(b.nextSteps)}</p>` : ""}
      </li>`
    )
    .join("")}</ul>`;
  return section("Bloqueos críticos", items.length, inner);
}

function nextStepsBlock(o) {
  if (!o || typeof o !== "object") return "";
  const list = (label, v) => {
    if (!v) return "";
    const arr = Array.isArray(v) ? v : [v];
    if (!arr.length) return "";
    return `<div class="mb-2"><p class="text-[11px] font-semibold text-slate-400">${escape(label)}</p>
      <ul class="list-disc list-inside text-sm text-slate-700 space-y-0.5">${arr.map((x) => `<li>${escape(x)}</li>`).join("")}</ul></div>`;
  };
  const inner = list("Próxima reunión", o.nextMeeting) + list("Puntos de revisión", o.reviewPoints) + list("Hitos clave", o.keyMilestones);
  return inner ? section("Próximos pasos", null, inner) : "";
}

function renderMeetingDetail(id) {
  if (!id) return meetingDetailEmpty();
  let rep, err;
  try {
    const { rows } = fetchSource("meeting_detail", { id });
    rep = rows[0];
  } catch (e) {
    err = e.message;
  }
  if (err) {
    return meetingPanelShell(
      `<div class="p-5"><div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-3 text-sm">${escape(err)}</div></div>`
    );
  }
  const closeBtn = `<button data-on:click="$detailOpen=false; $selectedMeeting=''" class="ml-auto -mr-1 -mt-1 text-slate-400 hover:text-slate-600 text-lg leading-none" title="Cerrar">✕</button>`;
  if (!rep || !Object.keys(rep).length) {
    return meetingPanelShell(
      `<div class="p-5"><div class="flex items-start mb-3">${closeBtn}</div>
        <div class="rounded-lg border border-slate-200 bg-slate-50 text-slate-500 p-4 text-sm">Esta reunión aún no tiene reporte.</div></div>`
    );
  }
  const header = `<div class="flex items-start gap-2 mb-1">${closeBtn}</div>
    <h2 class="text-base font-semibold text-slate-800 mb-1 -mt-6 pr-6">${escape(rep.reportTitle || "Reporte")}</h2>
    ${rep.reportSubtitle ? `<p class="text-sm text-slate-500 mb-4">${escape(rep.reportSubtitle)}</p>` : '<div class="mb-4"></div>'}`;

  const inner = `<div class="p-5">
    ${header}
    ${rep.executiveSummary ? section("Resumen ejecutivo", null, prose(rep.executiveSummary)) : ""}
    ${objectivesBlock(rep.meetingObjectives)}
    ${decisionsBlock(rep.discussionPointsAndDecisions)}
    ${actionItemsBlock(rep.actionItems)}
    ${blockersBlock(rep.criticalIssuesAndBlockers)}
    ${nextStepsBlock(rep.nextStepsAndFollowUp)}
  </div>`;
  return meetingPanelShell(inner);
}

// ── notion-tasks component ─────────────────────────────────────────────────
// A filterable table of a Notion project's BD Avances tasks (source
// notion_project_tasks, param `project` = the project brief page id/url). Notion
// is slow, so we fetch ONCE (source is cached) and filter entirely in the browser
// via Datastar signals + data-show — flipping a filter never re-queries. Rows are
// read-only and link out to the Notion page; overdue tasks are highlighted.

const NOTION_ESTADO_BADGE = {
  Done: "bg-emerald-100 text-emerald-700",
  "On Time": "bg-blue-100 text-blue-700",
  "In Progress": "bg-amber-100 text-amber-700",
  Archivo: "bg-slate-200 text-slate-600",
};

// JS string literal for embedding a value inside a data-show expression (single
// quotes; the attribute itself is double-quoted, so escape only single quotes).
function jsStr(v) {
  return "'" + String(v ?? "").replace(/\\/g, "\\\\").replace(/'/g, "\\'") + "'";
}
function jsArr(arr) {
  return "[" + (arr || []).map(jsStr).join(",") + "]";
}

function distinct(rows, pick) {
  const set = new Set();
  for (const r of rows) {
    const v = pick(r);
    if (Array.isArray(v)) v.forEach((x) => x && set.add(x));
    else if (v) set.add(v);
  }
  return [...set].sort((a, b) => a.localeCompare(b, "es"));
}

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

// Render a saved UI spec into the pane HTML (a #pane element, id-matched by SSE).
function renderPane(ui) {
  if (!ui) {
    return `<section id="pane" class="flex-1 p-8">
      <div class="h-full flex items-center justify-center text-slate-400">
        <p>Selecciona una UI en el panel izquierdo, o crea una nueva.</p>
      </div></section>`;
  }
  if (ui.component === "dashboard") return renderDashboard(ui);
  if (ui.component === "sop-tree") return renderSopTree(ui);
  if (ui.component === "tasks") return renderTasks(ui);
  if (ui.component === "task-editor") return renderTaskEditor(ui);
  if (ui.component === "meetings") return renderMeetings(ui);
  if (ui.component === "notion-tasks") return renderNotionTasks(ui);
  let body;
  let meta = "";
  try {
    const { rows, label } = fetchSource(ui.source, ui.params || {});
    meta = `<span class="text-xs text-slate-400">${escape(label)} · ${rows.length} fila(s)</span>`;
    body = ui.component === "table" || !ui.component ? table(rows) : `<pre>${escape(JSON.stringify(rows, null, 2))}</pre>`;
  } catch (e) {
    body = `<div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-4 text-sm">${escape(e.message)}</div>`;
  }
  return `<section id="pane" class="flex-1 p-6 overflow-hidden flex flex-col">
    <header class="mb-4 flex items-baseline gap-3">
      <h1 class="text-xl font-semibold text-slate-800">${escape(ui.name)}</h1>
      ${meta}
      <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs text-indigo-600 hover:underline">abrir solo ↗</a>
    </header>
    ${body}
  </section>`;
}

module.exports = { renderPane, renderTaskDetail, renderTaskEditForm, renderMeetingDetail, table, escape };

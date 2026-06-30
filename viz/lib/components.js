// Parametrizable components — turn rows of data into HTML. For the first cut
// every UI renders as a table, with columns inferred from the data (union of
// keys, first-seen order). Adding `form`, `cards`, `stats-bar`, etc. later is
// just another case in renderUI().

const { fetchSource } = require("./datasources");

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

  // macro filter applied in JS over the cached catalog (no extra query)
  const current = (ui.params && ui.params.macro) || "";
  const rows = current ? all.filter((r) => r.macro === current) : all;
  const macros = groupBy(all, (r) => r.macro).map(([code, rs]) => ({ code, name: rs[0].macro_name }));
  const reget = `@get('/ui/${escape(ui.id)}?macro='+$sopMacro)`;
  const opts =
    `<option value="">Todos los macro-procesos</option>` +
    macros
      .map((m) => `<option value="${escape(m.code)}"${m.code === current ? " selected" : ""}>${escape(m.code)} · ${escape(m.name)}</option>`)
      .join("");
  const controls = `<div class="mb-4" data-signals="{sopMacro:'${escape(current)}'}">
    <select data-bind="sopMacro" data-on:change="${reget}"
      class="text-sm px-3 py-2 rounded-lg border border-slate-300 bg-white focus:outline-none focus:ring-2 focus:ring-indigo-400 font-medium">${opts}</select>
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
  { k: "title", l: "Título", w: "w-[42%]" },
  { k: "status", l: "Estado", w: "w-24" },
  { k: "priority", l: "Prioridad", w: "w-16", align: "text-center" },
  { k: "due", l: "Vence", w: "w-24", cls: "whitespace-nowrap" },
  { k: "project", l: "Proyecto" },
  { k: "assignees", l: "Responsables" },
];
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
  if (col === "priority") return priorityDot(r[col]);
  if (col === "due") return dueFmt(r[col]);
  return cell(r[col]);
}

function tasksTable(rows) {
  if (!rows.length) return '<p class="text-slate-500 italic">Sin resultados.</p>';
  const thead = TASK_COLS.map(
    (c) => `<th class="${c.align || "text-left"} ${c.w || ""} font-semibold px-3 py-2 border-b border-slate-200 sticky top-0 bg-slate-50">${escape(c.l)}</th>`
  ).join("");
  const tbody = rows
    .map(
      (r) =>
        `<tr data-on:click="$selectedTask='${escape(r.id)}'; $detailOpen=true; @get('/task/${escape(r.id)}')" data-indicator:loading data-class:row-sel="$selectedTask==='${escape(r.id)}'" class="cursor-pointer even:bg-slate-50/60 hover:bg-indigo-50">${TASK_COLS.map(
          (c) =>
            `<td class="px-3 py-2 border-b border-slate-100 align-top ${c.align || ""} ${c.cls || ""}"${c.tip ? ` title="${escape(r[c.k] ?? "")}"` : ""}>${taskCell(c.k, r)}</td>`
        ).join("")}</tr>`
    )
    .join("");
  return `<div class="overflow-auto rounded-lg border border-slate-200 max-h-[calc(100vh-12rem)]"><table class="w-full table-fixed text-sm border-collapse">
    <thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table></div>`;
}

function selectCtl(signal, current, options, reget) {
  const opts = options
    .map(([v, l]) => `<option value="${escape(v)}"${String(v) === String(current) ? " selected" : ""}>${escape(l)}</option>`)
    .join("");
  return `<select data-bind="${signal}" data-on:change="${reget}" data-indicator:loadingtasks
    class="text-sm px-3 py-2 rounded-lg border border-slate-300 bg-white focus:outline-none focus:ring-2 focus:ring-indigo-400">${opts}</select>`;
}

function renderTasks(ui) {
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
        <p class="text-xs text-slate-400 mb-2">${rows.length} tarea(s)</p>${tasksTable(rows)}
      </div>`;

  // master-detail inside the pane. #detail-wrap PERSISTS (never replaced by SSE)
  // so its width/opacity transition fires every open/close; only its inner
  // #task-detail is swapped by the /task/:id route. Closed by default; the
  // .is-open class (base CSS = closed) avoids a Tailwind w-0/w-96 conflict and
  // a load-time flash. `detailOpen` lives on #pane, which resets on filter.
  return `<section id="pane" class="flex-1 overflow-hidden flex" data-signals="{detailOpen:false,selectedTask:''}">
    <style>
      #detail-wrap{width:0;opacity:0;overflow:hidden;transition:width .3s ease-in-out,opacity .3s ease-in-out;}
      #detail-wrap.is-open{width:24rem;opacity:1;border-left:1px solid rgb(226 232 240);}
      #detail-loading,#tasks-loading{opacity:0;transition:opacity .2s ease;}
      #detail-loading.on,#tasks-loading.on{opacity:1;}
      tr.row-sel{background:rgb(238 242 255)!important;box-shadow:inset 3px 0 0 rgb(79 70 229);}
    </style>
    <div class="flex-1 p-6 overflow-auto bg-slate-50">${head}${controls}${body}</div>
    <aside id="detail-wrap" data-class:is-open="$detailOpen" class="relative shrink-0 bg-white">
      <div id="detail-loading" data-class:on="$loading" class="pointer-events-none absolute inset-0 z-10 flex items-center justify-center bg-white/50">
        <div class="w-7 h-7 rounded-full border-2 border-slate-300 border-t-indigo-600 animate-spin"></div>
      </div>
      ${renderTaskDetail("")}
    </aside>
  </section>`;
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

  const a = d.archetype;
  const activity = a
    ? `<div class="mb-5 rounded-lg bg-indigo-50 border border-indigo-100 px-3 py-2">
        <p class="text-[11px] font-semibold uppercase tracking-wide text-indigo-400">Actividad</p>
        <p class="text-sm text-slate-800"><span class="font-mono text-xs text-indigo-600">${escape(a.id)}</span> · ${escape(a.name)}${a.verb ? ` <span class="text-xs text-slate-400">(${escape(a.verb)})</span>` : ""}</p>
        ${a.sop ? `<p class="text-xs text-slate-400 mt-0.5">${escape(a.macro)} ${escape(a.macro_name || "")} › ${escape(a.sop)} ${escape(a.sop_name || "")}</p>` : ""}
      </div>`
    : "";

  const inner = `<div class="p-5">
    ${header}
    ${activity}
    ${section("Inputs", (d.inputs || []).length, ioList(d.inputs, "is_satisfied", "satisfecho", "pendiente"))}
    ${section("Outputs", (d.outputs || []).length, ioList(d.outputs, "is_delivered", "entregado", "pendiente"))}
    ${section("Validación", (d.criteria || []).length, criteriaList(d.criteria))}
    ${section("Comentarios", (d.comments || []).length, commentsList(d.comments))}
  </div>`;
  return panelShell(inner);
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

module.exports = { renderPane, renderTaskDetail, table, escape };

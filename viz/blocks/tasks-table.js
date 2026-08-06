// tasks-table block — the MASTER slot over the `tasks` source: the task list
// table, its filter bar (status/priority/project/assignee/due/open — fixed by
// this block, per the "filters belong to the block" decision) and the
// presentation-only sort. Custom rendering: drops the id column, renders
// priority as a traffic-light dot, and formats the due date as "Mmm D".
//
// Master-slot contract (consumed by patterns/master-detail.js):
//   signals(p)          → the filter signals object, seeded from params
//   regetQS             → JS expr (string concat) building the re-fetch query
//   controls(p, reget)  → the filter bar HTML (fetches its own option lists)
//   prepare(rows, p)    → presentation transforms (sort) applied server-side
//   table(rows, wire)   → the table; wire = {rowAttrs(r), sort:{key,dir,reget}}
//   counter(n)          → "N tarea(s)" meta line
//   headerExtra         → extra header markup (the #tasks-meta slot)

const { fetchSource } = require("../lib/datasources");
const { escape, cell, dueFmt, priorityDot, selectCtl, checkCtl } = require("../lib/kit");

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
  { k: "status", l: "Estado", w: "w-28" },
  // «Prio» y no «Prioridad»: los encabezados del DS son micro-mayúsculas con
  // nowrap, y la etiqueta larga no cabe en la columna del punto.
  { k: "priority", l: "Prio", w: "w-16", align: "text-center" },
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

// El estado deja de ser texto crudo (`in_progress`) y pasa a ser un badge del
// DS, con su semántica: hecho→pos, bloqueado→neg, en curso→cau, y neutro para
// lo que aún no arranca o se canceló. El texto va en español; el valor del enum
// queda en el title para no perder el dato exacto.
const STATUS_BADGE = {
  pending: { c: "badge-neutral", t: "Pendiente" },
  in_progress: { c: "badge-cau", t: "En curso" },
  completed: { c: "badge-pos", t: "Hecha" },
  blocked: { c: "badge-neg", t: "Bloqueada" },
  cancelled: { c: "badge-neutral", t: "Cancelada" },
};
function statusBadge(v) {
  const s = STATUS_BADGE[v];
  if (!s) return cell(v);
  return `<span class="badge ${s.c}" title="${escape(v)}">${escape(s.t)}</span>`;
}

function taskCell(col, r) {
  if (col === "source_type") return sourceIcon(r[col]);
  if (col === "status") return statusBadge(r[col]);
  if (col === "priority") return priorityDot(r[col]);
  if (col === "due") return dueFmt(r[col]);
  return cell(r[col]);
}

const INDICATOR = "loadingtasks";

// Los filtros de DRILL-DOWN (los que manda la torre de control: cola de chase,
// sin fecha, por macro-proceso, higiene de contrato, cerradas) no tienen control
// propio en la barra: llegan por URL. Viajan igual en las señales para
// SOBREVIVIR a cualquier cambio de filtro — sin esto, tocar «Solo abiertas»
// sobre «Estancadas» devolvería silenciosamente las 151, y el usuario creería
// estar viendo las 54. Se ven (y se quitan) como chips.
const DRILL = [
  { sig: "tStale", p: "stale", l: (v) => `Sin mover ≥ ${v}d` },
  { sig: "tNoDue", p: "no_due", l: () => "Sin fecha" },
  { sig: "tMacro", p: "macro", l: (v) => `Macro ${v}` },
  { sig: "tNoArch", p: "sin_arquetipo", l: () => "Sin arquetipo" },
  { sig: "tNoOut", p: "sin_outputs", l: () => "Sin entregable" },
  { sig: "tClosed", p: "closed", l: (v) => `Cerradas ≤ ${v}d` },
];

function signals(p) {
  const sortKey = p.sort === "title" || p.sort === "due" ? p.sort : "";
  const s = {
    tStatus: p.status || "",
    tPriority: p.priority || "",
    tProject: p.project || "",
    tAssignee: p.assignee || "",
    tDue: p.due || "",
    tOpen: p.open === "1" || p.open === "true",
    tSort: sortKey,
    tDir: p.dir === "desc" ? "desc" : "asc",
  };
  for (const d of DRILL) s[d.sig] = p[d.p] || "";
  return s;
}

// The query-string EXPRESSION for the @get re-fetch (Datastar signals inline).
const regetQS =
  `'limit=0&status='+$tStatus+'&priority='+$tPriority` +
  `+'&project='+encodeURIComponent($tProject)+'&assignee='+encodeURIComponent($tAssignee)` +
  `+'&due='+$tDue+'&open='+$tOpen+'&sort='+$tSort+'&dir='+$tDir` +
  DRILL.map((d) => `+'&${d.p}='+$${d.sig}`).join("");

function controls(p, reget) {
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
  // Chips de los filtros que llegaron por URL: dicen qué recorte se está viendo
  // y lo sueltan de un click (poner el signal en '' y re-consultar).
  const chips = DRILL.filter((d) => p[d.p])
    .map(
      (d) =>
        `<button class="badge badge-cau" title="Quitar este filtro"
           data-on:click="$${d.sig}=''; ${reget}" data-indicator:${INDICATOR}>${escape(d.l(p[d.p]))} ✕</button>`
    )
    .join(" ");
  return `${selectCtl("tStatus", p.status || "", STATUS_OPTS, reget)}
    ${selectCtl("tPriority", p.priority || "", PRIORITY_OPTS, reget)}
    ${selectCtl("tProject", p.project || "", projectOpts, reget)}
    ${selectCtl("tAssignee", p.assignee || "", memberOpts, reget)}
    ${selectCtl("tDue", p.due || "", DUE_OPTS, reget)}
    ${checkCtl("tOpen", "Solo abiertas", `${reget}`, { indicator: `${INDICATOR}` })}
    ${chips}`;
}

// presentation-only sort (never reaches the shell — buildArgs ignores it):
// ?sort=title|due & ?dir=asc|desc, applied in JS over the fetched rows.
function prepare(rows, p) {
  const s = signals(p);
  if (!s.tSort || !rows.length) return rows;
  const mul = s.tDir === "desc" ? -1 : 1;
  return [...rows].sort((a, b) => {
    const av = a[s.tSort],
      bv = b[s.tSort];
    if ((av == null || av === "") && (bv == null || bv === "")) return 0;
    if (av == null || av === "") return 1; // empties last, either direction
    if (bv == null || bv === "") return -1;
    return mul * String(av).localeCompare(String(bv), "es", { sensitivity: "base" });
  });
}

// wire = { rowAttrs(r) → the pattern-owned click/selection attributes,
//          sort: {key, dir, reget} → sortable-header state }
// Wears the design system's `table.tbl` — including its own sorting
// affordance: `.sortable` for the affordance and `[aria-sort]` for the active
// column, which the DS already styles (brand-colored arrow, ink promoted from
// text-3 to text-1). That also makes the sort state announceable, which the
// old hover-color-only version wasn't.
function table(rows, wire) {
  if (!rows.length) return '<p class="text-slate-500 italic">Sin resultados.</p>';
  const s = wire.sort;
  const thead = TASK_COLS.map((c) => {
    const base = `${c.align || ""} ${c.w || ""}`;
    if (!c.sort || !s) return `<th class="${base}">${escape(c.l)}</th>`;
    const active = s.key === c.k;
    const arrow = active ? (s.dir === "desc" ? "▼" : "▲") : "↕";
    const ariaSort = active ? ` aria-sort="${s.dir === "desc" ? "descending" : "ascending"}"` : "";
    const click = `$tDir = ($tSort === '${c.k}' && $tDir === 'asc') ? 'desc' : 'asc'; $tSort = '${c.k}'; ${s.reget}`;
    return `<th class="${base} sortable"${ariaSort} title="Ordenar por ${escape(c.l)}" data-on:click="${click}" data-indicator:${INDICATOR}>${escape(c.l)} <span class="sort text-[10px]">${arrow}</span></th>`;
  }).join("");
  const tbody = rows
    .map(
      (r) =>
        `<tr ${wire.rowAttrs(r)} class="cursor-pointer">${TASK_COLS.map(
          (c) =>
            `<td class="align-top ${c.align || ""} ${c.cls || ""}"${c.tip ? ` title="${escape(r[c.k] ?? "")}"` : ""}>${taskCell(c.k, r)}</td>`
        ).join("")}</tr>`
    )
    .join("");
  // min-w = the floor the fixed layout needs (18rem de columnas fijas + Título
  // 40% + Proyecto/Responsables). Sin él la tabla nunca excede el contenedor y
  // el overflow-auto no dispara: las columnas se comprimen en vez de scrollear.
  return `<div class="table-wrap"><div class="table-scroll overflow-y-auto max-h-[calc(100vh-12rem)]"><table class="tbl w-full min-w-[56rem] table-fixed">
    <thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table></div></div>`;
}

module.exports = {
  id: "tasks-table",
  manifest: {
    slot: "master",
    consumes: "rows",
    indicator: INDICATOR,
    overridable: [
      "status", "priority", "project", "assignee", "due", "open", "limit", "sort", "dir",
      ...DRILL.map((d) => d.p),
    ],
  },
  signals,
  regetQS,
  controls,
  prepare,
  table,
  // Sortable-header state for the pattern's wire (the signal names stay
  // private to this block — the pattern never learns them).
  sortState: (p) => {
    const s = signals(p);
    return { key: s.tSort, dir: s.tDir };
  },
  counter: (n) => `${n} tarea(s)`,
  headerExtra: '<span id="tasks-meta" class="text-xs text-slate-400"></span>',
  STATUS_OPTS,
  PRIORITY_OPTS,
  DUE_OPTS,
};

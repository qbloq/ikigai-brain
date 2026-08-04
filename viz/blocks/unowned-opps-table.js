// unowned-opps-table block — the MASTER slot over `crm_sin_dueno`: los leads
// que entraron al CRM y NADIE tomó (`crm_opportunities.user_id` NULL porque
// GHL no trae `assigned_to`).
//
// La columna que importa es `dias`: un lead sin dueño no es un dato, es una
// cuenta regresiva. Por eso la tabla ordena por antigüedad y la tiñe — a los
// 7 días la conversación ya se enfrió, y esa señal tiene que ser visible sin
// leer la fecha.
//
// Contrato master, igual que calls-table: signals / regetQS / controls /
// table(rows, wire) / counter.

const { fetchSource } = require("../lib/datasources");
const { escape, cell, selectCtl } = require("../lib/kit");

const INDICATOR = "loadingsindueno";

const STATUS_OPTS = [
  ["", "Estado: todos"],
  ["open", "Abierta"],
  ["won", "Ganada"],
  ["lost", "Perdida"],
  ["abandoned", "Abandonada"],
];

const COLS = [
  { k: "dias", l: "Días", w: "w-16", align: "text-center" },
  { k: "creada", l: "Creada", w: "w-24", cls: "whitespace-nowrap" },
  { k: "lead", l: "Lead", w: "w-[18%]" },
  { k: "etapa", l: "Etapa", w: "w-40" },
  { k: "estado", l: "Estado", w: "w-24" },
  { k: "email", l: "Email", w: "w-[18%]" },
  { k: "telefono", l: "Teléfono", w: "w-36", cls: "whitespace-nowrap" },
  { k: "tags", l: "Canal de entrada (tags)" },
];

// La antigüedad se lee como semáforo: fresco todavía se puede rescatar, viejo
// ya es autopsia. Los cortes (3 / 7 / 21 días) siguen el ciclo comercial del
// equipo, no una escala genérica.
function diasCell(d) {
  const n = Number(d);
  if (!Number.isFinite(n)) return '<span class="text-slate-300">—</span>';
  const cls = n <= 3 ? "badge-pos" : n <= 7 ? "badge-cau" : n <= 21 ? "badge-neg" : "badge-neutral";
  return `<span class="badge ${cls}" title="${n} días sin dueño">${n}d</span>`;
}

function estadoCell(v) {
  const cls =
    v === "won" ? "badge-pos" : v === "open" ? "bg-blue-100 text-blue-700" : v === "lost" ? "badge-neg" : "badge-neutral";
  return `<span class="badge ${cls}">${escape(v || "—")}</span>`;
}

// Los tags de GHL son la única huella del formulario por el que entró el lead
// (modulo5yt, lleno encuesta organico, premium academy…). Se muestran como
// chips porque agrupan visualmente el canal sin necesidad de una columna extra.
function tagsCell(v) {
  if (!v || v === "—") return '<span class="text-slate-300">—</span>';
  return v
    .split(",")
    .map((t) => t.trim())
    .filter(Boolean)
    .slice(0, 4)
    .map((t) => `<span class="badge badge-neutral mr-1">${escape(t)}</span>`)
    .join("");
}

function bodyCell(col, r) {
  if (col === "dias") return diasCell(r[col]);
  if (col === "estado") return estadoCell(r[col]);
  if (col === "tags") return tagsCell(r[col]);
  if (col === "email") return `<span class="text-xs font-mono text-slate-600">${escape(r[col] || "—")}</span>`;
  return cell(r[col]);
}

function signals(p) {
  return {
    sdProject: p.project || "",
    sdStatus: p.status || "",
    sdFrom: p.from || "",
    sdTo: p.to || "",
  };
}

const regetQS =
  `'limit=0&project='+encodeURIComponent($sdProject)+'&status='+encodeURIComponent($sdStatus)` +
  `+'&from='+encodeURIComponent($sdFrom)+'&to='+encodeURIComponent($sdTo)`;

function controls(p, reget) {
  let projectOpts = [["", "Proyecto: todos"]];
  try {
    projectOpts = projectOpts.concat(
      fetchSource("projects").rows.map((r) => [r.name, r.name]).filter(([n]) => n)
    );
  } catch {
    /* keep the "todos" fallback */
  }
  const dateCtl = (sig, label) =>
    `<label class="text-xs text-slate-500 flex items-center gap-1">${escape(label)}
      <input type="date" class="input text-xs" data-bind="${sig}" data-on:change="${reget}" data-indicator:${INDICATOR}>
    </label>`;
  return [
    selectCtl("sdProject", p.project || "", projectOpts, reget, INDICATOR),
    selectCtl("sdStatus", p.status || "", STATUS_OPTS, reget, INDICATOR),
    dateCtl("sdFrom", "desde"),
    dateCtl("sdTo", "hasta"),
  ].join("");
}

function table(rows, wire) {
  const thead = COLS.map((c) => `<th class="${c.align || "text-left"} ${c.w || ""}">${escape(c.l)}</th>`).join("");
  const tbody = rows
    .map(
      (r) =>
        `<tr ${wire.rowAttrs(r)} class="cursor-pointer">${COLS.map(
          (c) => `<td class="align-top ${c.align || ""} ${c.cls || ""}">${bodyCell(c.k, r)}</td>`
        ).join("")}</tr>`
    )
    .join("");
  return `<div class="table-wrap"><div class="table-scroll overflow-y-auto max-h-[calc(100vh-12rem)]"><table class="tbl w-full min-w-[68rem] table-fixed">
    <thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table></div></div>`;
}

module.exports = {
  id: "unowned-opps-table",
  manifest: {
    slot: "master",
    consumes: "rows",
    indicator: INDICATOR,
    overridable: ["project", "status", "stage", "from", "to", "limit", "con_contacto", "sin_contacto"],
  },
  signals,
  regetQS,
  controls,
  table,
  counter: (n) => `${n} lead(s) sin dueño`,
  headerExtra:
    '<span class="badge badge-neg" title="user_id NULL porque GHL no trae assigned_to — verificado contra la fuente">nadie asignado</span>',
};

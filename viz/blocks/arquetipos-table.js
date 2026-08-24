// arquetipos-table block — el MASTER de la vista «Sin arquetipo» de la página
// `revision-propuestas`: las tareas del cerebro que no tienen actividad
// etiquetada, con el arquetipo que el matcher léxico propone (score + motivo)
// y la marca local que ya se le haya puesto.
//
// La cola existe porque etiquetar es lo que conecta una tarea con su SOP y su
// macro-proceso; sin eso la ontología no cubre nada. Lo que esta vista NO hace
// es aplicar la etiqueta: eso es `bash/tasks/aplicar_arquetipos.sh` sobre las
// marcas, desde la conversación (la UI marca, el script ejecuta).
// Spec: docs/superpowers/specs/2026-08-24-revision-propuestas-design.md

const { fetchSource } = require("../lib/datasources");
const { escape, cell, selectCtl, checkCtl } = require("../lib/kit");
const { switcher } = require("./propuestas-table");

const INDICATOR = "loadingarq";

const ESTADO_BADGE = {
  pending: ["badge-neutral", "Pendiente"],
  in_progress: ["badge-cau", "En curso"],
  completed: ["badge-pos", "Hecha"],
  blocked: ["badge-neg", "Bloqueada"],
  cancelled: ["badge-neutral", "Cancelada"],
};
function estadoBadge(v) {
  const [c, t] = ESTADO_BADGE[v] || ["badge-neutral", v || "—"];
  return `<span class="badge ${c}" title="${escape(v || "")}">${escape(t)}</span>`;
}

// El score del matcher no es una probabilidad: es una suma de señales (léxica,
// proyecto, dueño…), así que se pinta como semáforo y con su motivo al lado —
// un número suelto invita a creerle más de lo que dice.
function scoreBadge(r) {
  if (!r.sugerido) return `<span class="badge badge-neutral" title="${escape(r.motivo || "sin propuesta")}">sin propuesta</span>`;
  const s = Number(r.score || 0);
  const c = s >= 60 ? "badge-pos" : "badge-cau";
  return `<span class="badge ${c}" title="${escape(r.motivo || "")}">${s}</span>`;
}

// La decisión LOCAL sobre el arquetipo de una tarea. Se exporta porque el act
// `mark` de arquetipo-detail parchea exactamente este span (`#arq-<id8>`).
function marcaBadge(m) {
  if (!m) return `<span class="text-[11px] text-slate-300">—</span>`;
  if (m.aplicado_en) {
    return `<span class="badge badge-brand" title="Aplicada en Postgres el ${escape(String(m.aplicado_en).slice(0, 16))}">✓ aplicada ${escape(m.decision || "")}</span>`;
  }
  if (m.decision === "ninguno") {
    return `<span class="badge badge-neutral" title="${escape(m.decision_nota || "Ninguno de los propuestos sirve")}">ninguno</span>`;
  }
  return `<span class="badge badge-pos" title="${escape(m.decision_nota || "Marcada para aplicar")}">${escape(m.decision || "")}</span>`;
}

function signals(p) {
  return {
    vista: p.vista === "arquetipos" ? "arquetipos" : "propuestas",
    aProy: p.project || "",
    aOpen: p.open !== "false",
  };
}

const regetQS = `'vista='+$vista+'&project='+encodeURIComponent($aProy)+'&open='+$aOpen`;

function controls(p, reget) {
  let projectOpts = [["", "Proyecto: todos"]];
  try {
    projectOpts = projectOpts.concat(
      fetchSource("projects").rows.map((r) => [r.name, r.name]).filter(([n]) => n)
    );
  } catch {
    /* se queda con «todos» */
  }
  return `${switcher("arquetipos", reget, INDICATOR)}
    ${selectCtl("aProy", p.project || "", projectOpts, reget, INDICATOR)}
    ${checkCtl("aOpen", "Solo abiertas", reget, { indicator: INDICATOR, checked: p.open !== "false" })}`;
}

// Cruza la cola de Postgres con las marcas de la sqlite local. Son dos mundos
// distintos (uno es el estado real, el otro la curaduría en curso) y por eso
// se juntan aquí y no en el script.
function prepare(rows, p) {
  let marcas = new Map();
  try {
    marcas = new Map(fetchSource("arquetipo_marcas").rows.map((m) => [String(m.task_id), m]));
  } catch {
    /* sin marcas: la columna «decisión» sale vacía, que es la verdad */
  }
  return rows.map((r) => ({ ...r, id: r.id, marca: marcas.get(String(r.id_full)) || null }));
}

const COLS = [
  { k: "id", l: "Id", w: "w-24" },
  { k: "title", l: "Título", w: "w-[34%]" },
  { k: "project", l: "Proyecto", w: "w-32" },
  { k: "status", l: "Estado", w: "w-24" },
  { k: "assignees", l: "Dueños", w: "w-40" },
  { k: "sugerido", l: "Propuesto", w: "w-[22%]" },
  { k: "marca", l: "Decisión", w: "w-32" },
];

function celda(k, r) {
  if (k === "id") return `<code class="text-[11px] text-slate-500" title="${escape(r.id_full || "")}">${escape(r.id || "")}</code>`;
  if (k === "status") return estadoBadge(r.status);
  if (k === "sugerido") {
    return `<div class="flex items-start gap-1.5">
      ${scoreBadge(r)}
      <div class="min-w-0">
        ${r.sugerido ? `<code class="text-[11px] text-indigo-600">${escape(r.sugerido)}</code>` : ""}
        <p class="text-[11px] text-slate-500 break-words">${escape(r.sugerido_nombre || r.motivo || "")}</p>
      </div>
    </div>`;
  }
  if (k === "marca") return `<span id="arq-${escape(String(r.id))}">${marcaBadge(r.marca)}</span>`;
  return cell(r[k]);
}

function table(rows, wire) {
  if (!rows.length) return '<p class="text-slate-500 italic">Sin tareas sin arquetipo — la cola está en cero.</p>';
  const thead = COLS.map((c) => `<th class="${c.align || ""} ${c.w || ""}">${escape(c.l)}</th>`).join("");
  const tbody = rows
    .map(
      (r) =>
        `<tr ${wire.rowAttrs(r)} class="cursor-pointer">${COLS.map(
          (c) => `<td class="align-top ${c.align || ""}">${celda(c.k, r)}</td>`
        ).join("")}</tr>`
    )
    .join("");
  return `<div class="table-wrap"><div class="table-scroll overflow-y-auto max-h-[calc(100vh-12rem)]"><table class="tbl w-full min-w-[62rem] table-fixed">
    <thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table></div></div>`;
}

module.exports = {
  id: "arquetipos-table",
  manifest: {
    slot: "master",
    consumes: "rows",
    indicator: INDICATOR,
    overridable: ["vista", "project", "open"],
  },
  signals,
  regetQS,
  controls,
  prepare,
  table,
  counter: (n) => `${n} tarea(s) sin arquetipo`,
  headerExtra: '<span class="text-xs text-slate-400">etiquetar mueve el puntero — no reescribe el contrato IO</span>',
  marcaBadge,
  scoreBadge,
};

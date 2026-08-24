// propuestas-table block — el MASTER de la vista «Propuestas de reuniones» de
// la página `revision-propuestas`: la barra de backups cargables (arriba), el
// conmutador de vista, los filtros y la tabla de propuestas de la sqlite local
// `propuestas_reuniones`.
//
// Contrato del slot master (patterns/master-detail.js):
//   signals(p) · regetQS · controls(p, reget, uiId, aviso) · prepare(rows,p)
//   · table(rows, wire) · counter(n) · headerExtra
//
// Dos cosas que este bloque NO hace, a propósito:
//   · no escribe nada — la decisión la escribe `propuesta-detail` y la carga
//     de un backup el act `cargar` de la página (que es quien tiene el ui.id);
//   · no filtra por proyecto en el shell — `propuestas.sh` no tiene ese flag,
//     así que ese filtro se aplica en JS sobre las filas ya traídas (regla de
//     viz/CLAUDE.md: filtrar en el navegador, no re-consultar).
// Spec: docs/superpowers/specs/2026-08-24-revision-propuestas-design.md

const { fetchSource } = require("../lib/datasources");
const { escape, cell, dueFmt, priorityDot, selectCtl } = require("../lib/kit");

const INDICATOR = "loadingprop";

// Las columnas JSON-string de la sqlite (asignados, slots, relacionadas,
// depende_de, contrato) llegan como TEXTO. Parsearlas sin try/catch convierte
// una fila mal escrita en una página en blanco, así que el fallback es el
// valor vacío del tipo esperado.
function parseJson(v, fallback) {
  if (v == null || v === "") return fallback;
  if (typeof v === "object") return v;
  try {
    const out = JSON.parse(v);
    return out == null ? fallback : out;
  } catch {
    return fallback;
  }
}

const SECCION_BADGE = {
  A: { c: "badge-brand", t: "A", title: "§A — propuesta con contrato listo" },
  B: { c: "badge-cau", t: "B", title: "§B — pregunta abierta, sin contrato" },
};
function seccionBadge(v) {
  const s = SECCION_BADGE[v];
  if (!s) return cell(v);
  return `<span class="badge ${s.c}" title="${escape(s.title)}">${escape(s.t)}</span>`;
}

// El estado de la CURADURÍA de una propuesta, en un solo badge. Se exporta
// porque el act `mark` de propuesta-detail parchea exactamente este span
// (`#dec-<n>`) en la tabla del maestro sin re-renderizar el pane entero.
function decisionBadge(r) {
  if (r.creada_id) {
    return `<span class="badge badge-brand" title="Ya creada en el cerebro: ${escape(r.creada_id)}">✓ creada ${escape(String(r.creada_id).slice(0, 8))}</span>`;
  }
  if (r.decision === "entra") return `<span class="badge badge-pos" title="Entra: se creará en el cerebro">entra</span>`;
  if (r.decision === "se_queda") return `<span class="badge badge-neutral" title="Se queda: no se crea">se queda</span>`;
  return `<span class="badge badge-cau" title="Sin decidir">pendiente</span>`;
}

function validaBadge(r) {
  if (r.valida !== 0 && r.valida !== "0") return "";
  return `<span class="badge badge-neg" title="${escape(r.error_validacion || "Contrato inválido")}">inválida</span> `;
}

// --- la barra de backups ---------------------------------------------------
// Un backup con gemelo JSON y sin cargar ofrece el botón; los demás dicen por
// qué no lo ofrecen (cargado ya / sin gemelo), que es información, no ruido.
function backupCard(b, uiId) {
  const corto = String(b.meeting_corto || "");
  let accion;
  if (b.cargado) {
    accion = `<span class="badge badge-pos" title="Ya está en la sqlite local">cargado ${escape(String(b.cargado_en || "").slice(0, 10))}</span>`;
  } else if (!b.json) {
    accion = `<span class="badge badge-neutral" title="El backup .md no tiene su gemelo .json — no hay contratos que cargar">sin gemelo JSON</span>`;
  } else {
    accion = `<button class="btn btn-primary btn-xs"
      data-on:click="@post('/c/revision-propuestas/act/cargar?ui=${escape(uiId)}&meeting=${escape(corto)}')"
      data-indicator:${INDICATOR} title="Cargar este backup a la sqlite local">Cargar</button>`;
  }
  return `<div class="card px-3 py-2 flex items-center gap-2 text-xs">
    <code class="text-[11px] text-slate-500">${escape(corto)}</code>
    <span class="text-slate-400">${escape(b.fecha || "")}</span>
    <span class="text-slate-700 font-medium max-w-[18rem] truncate" title="${escape(b.nombre || b.archivo || "")}">${escape(b.nombre || b.archivo || "—")}</span>
    <span class="text-slate-400 whitespace-nowrap" title="propuestas §A / preguntas §B">A ${Number(b.n_a || 0)} · B ${Number(b.n_b || 0)}</span>
    ${accion}
  </div>`;
}

function backupsBar(uiId) {
  let rows = [];
  let err = null;
  try {
    rows = fetchSource("propuestas_backups").rows;
  } catch (e) {
    err = e.message;
  }
  if (err) return `<div class="w-full alert alert-neg mb-2">${escape(err)}</div>`;
  if (!rows.length) return "";
  return `<div class="w-full flex flex-wrap items-center gap-2 mb-1">
    <span class="text-[11px] uppercase tracking-wide text-slate-400 mr-1">Backups</span>
    ${rows.map((b) => backupCard(b, uiId)).join("")}
  </div>`;
}

// --- el conmutador de vista ------------------------------------------------
// Vive en los DOS bloques maestros (cada vista pinta el suyo) porque el patrón
// no tiene noción de «vista»: lo único que hace falta es que `regetQS` empiece
// por `'vista='+$vista`, y entonces cambiar la señal + re-consultar cambia de
// par de bloques en el servidor.
function switcher(actual, reget, indicator) {
  const b = (v, label, title) =>
    `<button class="btn btn-sm" aria-pressed="${actual === v}" title="${escape(title)}"
      ${actual === v ? "" : `data-on:click="$vista='${v}'; ${reget}" data-indicator:${indicator}`}>${escape(label)}</button>`;
  return `<div class="btn-group mr-2">
    ${b("propuestas", "Propuestas de reuniones", "Las tareas que proponen las actas")}
    ${b("arquetipos", "Sin arquetipo", "Tareas del cerebro sin actividad etiquetada")}
  </div>`;
}

const DEC_OPTS = [
  ["", "Decisión: todas"],
  ["pendiente", "Sin decidir"],
  ["entra", "Entra"],
  ["se_queda", "Se queda"],
];
const SEC_OPTS = [
  ["", "Sección: todas"],
  ["A", "§A propuestas"],
  ["B", "§B preguntas"],
];

function signals(p) {
  return {
    vista: p.vista === "arquetipos" ? "arquetipos" : "propuestas",
    pLote: p.lote || "",
    pProy: p.proyecto || "",
    pSec: p.seccion || "",
    pDec: p.decision || "",
  };
}

const regetQS =
  `'vista='+$vista+'&lote='+$pLote` +
  `+'&proyecto='+encodeURIComponent($pProy)+'&seccion='+$pSec+'&decision='+$pDec`;

// `uiId` y `aviso` los inyecta la página (el patrón solo pasa (p, reget)): el
// botón Cargar necesita el id de la UI para su @post, y el aviso es el error
// que devolvió la última carga.
function controls(p, reget, uiId, aviso) {
  let rows = [];
  try {
    rows = fetchSource("propuestas", { lote: p.lote || "", seccion: p.seccion || "", decision: p.decision || "" }).rows;
  } catch {
    /* la tabla ya reporta el error; los selectores se quedan sin opciones */
  }
  const lotes = [...new Set(rows.map((r) => r.meeting_corto).filter(Boolean))];
  const lotesLbl = new Map(rows.map((r) => [r.meeting_corto, `${r.meeting_corto} · ${r.lote_nombre || r.lote_fecha || ""}`.trim()]));
  const proyectos = [...new Set(rows.map((r) => r.proyecto).filter(Boolean))].sort((a, b) => a.localeCompare(b, "es"));
  const loteOpts = [["", "Lote: todos"]].concat(lotes.map((l) => [l, lotesLbl.get(l) || l]));
  const proyOpts = [["", "Proyecto: todos"]].concat(proyectos.map((n) => [n, n]));
  const banner = aviso ? `<div class="w-full alert alert-neg mb-2">${escape(aviso)}</div>` : "";
  return `${banner}${backupsBar(uiId || "")}
    ${switcher("propuestas", reget, INDICATOR)}
    ${selectCtl("pLote", p.lote || "", loteOpts, reget, INDICATOR)}
    ${selectCtl("pProy", p.proyecto || "", proyOpts, reget, INDICATOR)}
    ${selectCtl("pSec", p.seccion || "", SEC_OPTS, reget, INDICATOR)}
    ${selectCtl("pDec", p.decision || "", DEC_OPTS, reget, INDICATOR)}`;
}

// El patrón identifica la fila por `r.id`; el de una propuesta es su `n`.
// El filtro de proyecto se aplica aquí (no hay flag en el script).
function prepare(rows, p) {
  const proy = p.proyecto || "";
  return rows.filter((r) => !proy || r.proyecto === proy).map((r) => ({ ...r, id: String(r.n) }));
}

const COLS = [
  { k: "ref", l: "Ref", w: "w-16" },
  { k: "seccion", l: "§", w: "w-10", align: "text-center" },
  { k: "titulo", l: "Título", w: "w-[34%]" },
  { k: "proyecto", l: "Proyecto", w: "w-32" },
  { k: "prioridad", l: "Prio", w: "w-14", align: "text-center" },
  { k: "vence", l: "Vence", w: "w-24", cls: "whitespace-nowrap" },
  { k: "asignados", l: "Dueños", w: "w-40" },
  { k: "arquetipo", l: "Arquetipo", w: "w-24" },
  { k: "decision", l: "Decisión", w: "w-36" },
];

function celda(k, r) {
  if (k === "ref") return `<code class="text-[11px] text-slate-500">${escape(r.ref || "")}</code>`;
  if (k === "seccion") return seccionBadge(r.seccion);
  if (k === "prioridad") return priorityDot(r.prioridad);
  if (k === "vence") {
    if (!r.vence) return cell(null);
    return `${dueFmt(r.vence)}${r.vence_estimada ? ` <span class="text-[10px] text-slate-400" title="Fecha estimada por el pipeline, no dicha en la reunión">est.</span>` : ""}`;
  }
  if (k === "asignados") return cell(parseJson(r.asignados, []).join(", "));
  if (k === "arquetipo") return r.arquetipo ? `<code class="text-[11px] text-slate-500">${escape(r.arquetipo)}</code>` : cell(null);
  if (k === "decision") return `${validaBadge(r)}<span id="dec-${escape(String(r.n))}">${decisionBadge(r)}</span>`;
  return cell(r[k]);
}

function table(rows, wire) {
  if (!rows.length) return '<p class="text-slate-500 italic">Sin propuestas — carga un backup en la barra de arriba.</p>';
  const thead = COLS.map((c) => `<th class="${c.align || ""} ${c.w || ""}">${escape(c.l)}</th>`).join("");
  const tbody = rows
    .map(
      (r) =>
        `<tr ${wire.rowAttrs(r)} class="cursor-pointer">${COLS.map(
          (c) => `<td class="align-top ${c.align || ""} ${c.cls || ""}">${celda(c.k, r)}</td>`
        ).join("")}</tr>`
    )
    .join("");
  return `<div class="table-wrap"><div class="table-scroll overflow-y-auto max-h-[calc(100vh-14rem)]"><table class="tbl w-full min-w-[62rem] table-fixed">
    <thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table></div></div>`;
}

module.exports = {
  id: "propuestas-table",
  manifest: {
    slot: "master",
    consumes: "rows",
    indicator: INDICATOR,
    overridable: ["vista", "lote", "proyecto", "seccion", "decision"],
  },
  signals,
  regetQS,
  controls,
  prepare,
  table,
  counter: (n) => `${n} propuesta(s)`,
  headerExtra: '<span class="text-xs text-slate-400">la UI solo MARCA — crear en el cerebro es del script</span>',
  // Compartidos con propuesta-detail (el act parchea el mismo badge) y con la
  // página (el switcher lo repinta arquetipos-table).
  parseJson,
  decisionBadge,
  seccionBadge,
  switcher,
};

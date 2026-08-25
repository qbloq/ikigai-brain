// adelantar-tareas page — «qué puede hacer el Cerebro» por cada tarea de una
// fecha de vencimiento: una tarjeta por tarea con la lista de cosas que el
// Cerebro puede hacer para adelantarla o incluso cerrarla. Nació el 2026-08-21
// para las 21 tareas que vencían el 20 de agosto.
//
// Fuente: la sqlite LOCAL `adelantar_tareas` (tablas `tareas` + `acciones`),
// leída por la consulta persistida en el spec (`localdb_query`, regla de
// procedencia: el SQL vive en el spec, nunca en el navegador). La consulta
// debe emitir UNA FILA POR ACCIÓN con las columnas: tarea_id, titulo,
// prioridad, asignado, arquetipo, output_principal, tarea_nota, n, orden,
// alcance, accion, detalle, estado, accion_nota. La página agrupa por tarea.
//
// Solo lectura — el viz es el visor. El estado de una acción (propuesta →
// en_curso → hecha / descartada) se mueve desde la conversación sobre la db
// local; el `n` de cada acción va visible porque es el handle que se dicta.
//
// Semántica del ALCANCE (la columna que ordena la lectura):
//   cierra   = el Cerebro entrega el resultado de la tarea solo (o casi)
//   adelanta = deja hecha una parte sustantiva; el resto es humano
//   insumo   = aporta datos/insumos; el trabajo sigue siendo del equipo

const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");

const ALCANCE = {
  cierra: ["badge-pos", "cierra"],
  adelanta: ["badge-brand", "adelanta"],
  insumo: ["badge-neutral", "insumo"],
};
const ESTADO = {
  propuesta: "badge-neutral",
  en_curso: "badge-cau",
  hecha: "badge-pos",
  descartada: "badge-neg",
};
const PRIORIDAD = { High: "badge-neg", Medium: "badge-cau", Low: "badge-neutral" };

function badge(cls, txt, title) {
  return `<span class="badge ${cls}"${title ? ` title="${escape(title)}"` : ""}>${escape(txt)}</span>`;
}

function accionLi(a) {
  const [cls, label] = ALCANCE[a.alcance] || ["badge-neutral", a.alcance || "?"];
  const hecha = a.estado === "hecha";
  const desc = a.estado === "descartada";
  return `<li class="flex gap-3 py-2" style="border-top:1px solid var(--border-1)">
    <div class="shrink-0 w-20 flex flex-col items-start gap-1">
      ${badge(cls, label, "Alcance: qué tanto de la tarea resuelve el Cerebro")}
      ${a.estado && a.estado !== "propuesta" ? badge(ESTADO[a.estado] || "badge-neutral", a.estado.replace("_", " "), "Estado de la acción") : ""}
    </div>
    <div class="min-w-0 flex-1">
      <p class="text-sm font-medium ${desc ? "line-through" : ""}" style="color:var(--text-1)">
        ${escape(a.accion)}
        ${hecha ? `<span class="text-xs" style="color:var(--text-3)"> ✔</span>` : ""}
      </p>
      ${a.detalle ? `<p class="text-xs mt-0.5" style="color:var(--text-2)">${escape(a.detalle)}</p>` : ""}
      ${a.accion_nota ? `<p class="text-[11px] mt-0.5 italic" style="color:var(--text-3)">${escape(a.accion_nota)}</p>` : ""}
    </div>
    <code class="shrink-0 text-[10px] self-start" style="color:var(--text-3)" title="Handle de la acción">#${escape(String(a.n))}</code>
  </li>`;
}

function tarjeta(t) {
  const acciones = t.acciones.sort((a, b) => Number(a.orden) - Number(b.orden));
  const nCierra = acciones.filter((a) => a.alcance === "cierra" && a.estado !== "descartada").length;
  const nHechas = acciones.filter((a) => a.estado === "hecha").length;
  return `<article class="card card-pad mb-3">
    <header class="flex items-start gap-3">
      <code class="text-xs shrink-0 mt-0.5" style="color:var(--text-3)" title="Id corto de la tarea">${escape(t.tarea_id)}</code>
      <div class="min-w-0 flex-1">
        <h2 class="text-sm font-semibold leading-snug" style="color:var(--text-1)">${escape(t.titulo)}</h2>
        <div class="flex flex-wrap items-center gap-1.5 mt-1.5">
          ${t.prioridad ? badge(PRIORIDAD[t.prioridad] || "badge-neutral", t.prioridad) : ""}
          ${t.asignado ? `<span class="text-xs" style="color:var(--text-2)">${escape(t.asignado)}</span>` : ""}
          ${t.arquetipo ? `<span class="text-[11px]" style="color:var(--text-3)" title="Arquetipo de actividad">· ${escape(t.arquetipo)}</span>` : ""}
          ${t.output_principal ? `<span class="text-[11px] truncate" style="color:var(--text-3)" title="Entregable principal">· ${escape(t.output_principal)}</span>` : ""}
        </div>
        ${t.tarea_nota ? `<p class="text-[11px] mt-1 italic" style="color:var(--text-3)">${escape(t.tarea_nota)}</p>` : ""}
      </div>
      <div class="shrink-0 text-right text-[11px]" style="color:var(--text-3)">
        ${acciones.length} acción(es)${nCierra ? ` · <span style="color:var(--pos-text,inherit)">${nCierra} cierra</span>` : ""}${nHechas ? ` · ${nHechas} hecha(s)` : ""}
      </div>
    </header>
    <ul class="mt-3">${acciones.map(accionLi).join("")}</ul>
  </article>`;
}

function kpi(label, value, hint) {
  return `<div class="kpi" title="${escape(hint || "")}">
    <div class="kpi-value">${escape(String(value))}</div>
    <div class="kpi-label">${escape(label)}</div>
  </div>`;
}

function render(ui) {
  let rows = [];
  let err;
  try {
    rows = fetchSource(ui.source, ui.params || {}).rows;
  } catch (e) {
    err = e.message;
  }

  // Agrupar por tarea conservando el orden de llegada (la consulta ordena).
  const porTarea = new Map();
  for (const r of rows) {
    if (!porTarea.has(r.tarea_id)) {
      porTarea.set(r.tarea_id, {
        tarea_id: r.tarea_id, titulo: r.titulo, prioridad: r.prioridad, asignado: r.asignado,
        arquetipo: r.arquetipo, output_principal: r.output_principal, tarea_nota: r.tarea_nota, acciones: [],
      });
    }
    if (r.n != null) porTarea.get(r.tarea_id).acciones.push(r);
  }
  const tareas = [...porTarea.values()];
  const acc = rows.filter((r) => r.n != null);
  const vivas = acc.filter((a) => a.estado !== "descartada");
  const tareasCierra = new Set(vivas.filter((a) => a.alcance === "cierra").map((a) => a.tarea_id)).size;
  const tareasAdelanta = new Set(vivas.filter((a) => a.alcance !== "insumo").map((a) => a.tarea_id)).size;
  const hechas = acc.filter((a) => a.estado === "hecha").length;

  const cuerpo = err
    ? `<div class="alert alert-neg text-sm">${escape(err)}</div>`
    : tareas.length
      ? tareas.map(tarjeta).join("")
      : `<p class="text-sm italic" style="color:var(--text-3)">Sin tareas cargadas.</p>`;

  return `<section id="pane" class="flex-1 p-6 overflow-auto">
    <div class="max-w-4xl">
    <header class="mb-4">
      <h1 class="text-xl font-bold" style="color:var(--text-1)">${escape(ui.name)}</h1>
      <p class="text-xs mt-1" style="color:var(--text-3)">
        Una tarjeta por tarea y, debajo, lo que el Cerebro puede hacer por ella.
        <b>cierra</b> = entrega el resultado solo (o casi) ·
        <b>adelanta</b> = deja hecha una parte sustantiva ·
        <b>insumo</b> = aporta datos; el trabajo sigue siendo del equipo.
        El estado de cada acción se mueve desde la conversación; el <code>#n</code> es su handle.
      </p>
    </header>
    ${err ? "" : `<div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-5">
      ${kpi("Tareas", tareas.length, "Tareas cargadas en la base local")}
      ${kpi("Con acción del Cerebro", tareasAdelanta, "Tareas con al menos una acción que cierra o adelanta (no solo insumo)")}
      ${kpi("El Cerebro puede cerrar", tareasCierra, "Tareas con al menos una acción de alcance «cierra»")}
      ${kpi("Acciones hechas", `${hechas} / ${vivas.length}`, "Acciones en estado hecha sobre las no descartadas")}
    </div>`}
    ${cuerpo}
    </div>
  </section>`;
}

module.exports = {
  id: "adelantar-tareas",
  render,
  manifest: { consumes: "rows", overridable: [] },
};

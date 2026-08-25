// revision-propuestas page — la mesa de revisión del rol technology sobre dos
// colas de PROPUESTAS: (1) las tareas que las reuniones proponen (los backups
// de meeting-to-tasks, cargados a la sqlite local `propuestas_reuniones`) y
// (2) las tareas del cerebro sin arquetipo, con el arquetipo propuesto.
// Dos instancias del patrón master-detail conmutadas por `vista`. La UI solo
// MARCA (sqlite local, patrón Merge del cruce); la ejecución en Postgres es de
// crear_de_propuestas.sh / aplicar_arquetipos.sh, desde la conversación.
// Spec: docs/superpowers/specs/2026-08-24-revision-propuestas-design.md
const pattern = require("../patterns/master-detail");
const propuestasTable = require("../blocks/propuestas-table");
const propuestaDetail = require("../blocks/propuesta-detail");
const arquetiposTable = require("../blocks/arquetipos-table");
const arquetipoDetail = require("../blocks/arquetipo-detail");
const store = require("../lib/store");

const CARGAR = "bash/localdb/propuesta_cargar.sh";

function render(ui, aviso) {
  const vista = (ui.params && ui.params.vista) === "arquetipos" ? "arquetipos" : "propuestas";
  const slots =
    vista === "arquetipos"
      ? {
          master: { block: arquetiposTable, source: "tareas_sin_arquetipo", params: { open: "1" } },
          detail: { block: arquetipoDetail },
        }
      : {
          // El bloque maestro de la vista 1 necesita DOS cosas que el patrón no
          // le pasa: el id de la UI (el @post del botón Cargar lo lleva) y el
          // aviso de la última carga fallida. La página, que sí los tiene, se
          // los inyecta envolviendo `controls`.
          master: {
            block: { ...propuestasTable, controls: (p, reget) => propuestasTable.controls(p, reget, ui.id, aviso) },
            source: "propuestas",
          },
          detail: { block: propuestaDetail },
        };
  return pattern.render(ui, slots);
}

const acts = {
  // Cargar un backup a la sqlite local; re-renderiza la página entera (#pane)
  // para que la barra deje de ofrecer el botón y la tabla traiga el lote.
  cargar: (ctx) => {
    const ui = store.get(ctx.params.get("ui") || "");
    if (!ui) return `<section id="pane" class="p-6 text-sm text-red-600">UI desconocida.</section>`;
    const r = ctx.run(CARGAR, [ctx.params.get("meeting") || ""]);
    return render({ ...ui, params: { ...(ui.params || {}), vista: "propuestas" } }, r && r.ok === false ? r.error : null);
  },
};

module.exports = {
  id: "revision-propuestas",
  render: (ui) => render(ui, null),
  acts,
  manifest: {
    consumes: "rows",
    overridable: [...new Set([...propuestasTable.manifest.overridable, ...arquetiposTable.manifest.overridable])],
    writes: [CARGAR],
  },
};

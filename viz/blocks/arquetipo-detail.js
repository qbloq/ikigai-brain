// arquetipo-detail block — el DETALLE de la vista «Sin arquetipo»: arriba, el
// arquetipo que el matcher propone (con su motivo, sus alternativas y el
// catálogo entero por si ninguna sirve) y, debajo, el detalle de la tarea tal
// como lo pinta `blocks/task-detail` — porque para decidir la etiqueta hay que
// ver el contrato, no solo el título.
//
// Reutiliza `renderTaskDetail(id)` en vez de re-implementarlo; lo único que se
// le quita es su propia cáscara (`#task-detail`, que colisionaría con el id de
// este panel) y su botón de cerrar, que limpia otra señal de selección.
//
// El único write es `arquetipo_mark.sh`: una MARCA en la sqlite local. Aplicar
// la etiqueta en Postgres es de `bash/tasks/aplicar_arquetipos.sh`.
// Spec: docs/superpowers/specs/2026-08-24-revision-propuestas-design.md

const { fetchSource } = require("../lib/datasources");
const { escape, section, jsStr } = require("../lib/kit");
const { renderTaskDetail } = require("./task-detail");
const { marcaBadge } = require("./arquetipos-table");
const catalogo = require("../../catalog/sop-archetypes.json");

const AMARK = "bash/localdb/arquetipo_mark.sh";
const WIDTH = "30rem";

const SOP_NAME = new Map((catalogo.sops || []).map((s) => [s.code, s.name]));

function shell(inner) {
  return `<div id="arq-detail" class="w-[30rem] h-full overflow-y-auto">${inner}</div>`;
}

function vacio(msg) {
  return shell(`<div class="h-full flex items-center justify-center p-8 text-center text-sm text-slate-400">
    <p>${escape(msg)}</p>
  </div>`);
}

// Un uuid no es un identificador de señal válido; el id corto es hexadecimal y
// puede empezar por dígito, así que se prefija.
function sig(id8) {
  return `_arq_${String(id8).replace(/[^a-z0-9]/gi, "")}`;
}

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

// El catálogo entero como <select>, agrupado por SOP: es la salida cuando
// ninguna de las tres alternativas del matcher sirve.
// La primera opción es VACÍA a propósito: cuando no hay sugerido ni
// alternativas la señal vale "", y sin ella el navegador mostraría el primer
// arquetipo del catálogo como si estuviera elegido mientras «Elegir este»
// postea `a=` — lo que se ve no sería lo que se envía.
function catalogoSelect(id8, seleccionado) {
  const porSop = new Map();
  for (const a of catalogo.archetypes || []) {
    if (!porSop.has(a.sop)) porSop.set(a.sop, []);
    porSop.get(a.sop).push(a);
  }
  const vacia = `<option value=""${seleccionado ? "" : " selected"}>— elegir —</option>`;
  const groups = [...porSop.entries()]
    .map(([sop, arqs]) => {
      const opts = arqs
        .map(
          (a) =>
            `<option value="${escape(a.id)}"${a.id === seleccionado ? " selected" : ""}>${escape(a.id)} — ${escape(a.name)}</option>`
        )
        .join("");
      return `<optgroup label="${escape(sop)} · ${escape(SOP_NAME.get(sop) || "")}">${opts}</optgroup>`;
    })
    .join("");
  return `<select data-bind="${sig(id8)}" class="select">${vacia}${groups}</select>`;
}

// `jsStr` y no `escape`: los valores van DENTRO de un literal JS y escape() no
// toca el apóstrofo. La codificación de URL la hace el navegador.
function post(id8, a) {
  return `@post('/c/arquetipo-detail/act/mark?id='+encodeURIComponent(${escape(jsStr(id8))})+'&a='+encodeURIComponent(${escape(jsStr(a))}))`;
}

function bloqueSugerido(id8, row, marca) {
  const congelada = !!(marca && marca.aplicado_en);
  const alternativas = row ? parseJson(row.alternativas, []) : [];
  const sugerido = (row && row.sugerido) || "";

  const cabeza = !row
    ? `<p class="text-xs text-slate-400 italic">— esta tarea no está en la cola sin arquetipo</p>`
    : row.sugerido
      ? `<p class="text-sm text-slate-700"><code class="text-xs text-indigo-600">${escape(row.sugerido)}</code> · ${escape(row.sugerido_nombre || "")}</p>
         <p class="text-[11px] text-slate-400">${escape(row.sugerido_sop || "")} ${escape(SOP_NAME.get(row.sugerido_sop) || "")} · score ${Number(row.score || 0)} · ${escape(row.motivo || "")}</p>`
      : `<p class="text-sm text-slate-500">Sin propuesta — ${escape(row.motivo || "el matcher no llegó al umbral")}</p>`;

  const alts = alternativas.length
    ? `<ul class="mt-2 space-y-1">${alternativas
        .map(
          (alt) => `<li class="flex items-start gap-2">
        ${congelada ? "" : `<button class="btn btn-secondary btn-xs shrink-0" data-on:click="${post(id8, alt.id)}" data-indicator:loading title="Marcar este arquetipo">Aceptar</button>`}
        <div class="min-w-0">
          <p class="text-xs text-slate-700"><code class="text-[11px] text-indigo-600">${escape(alt.id)}</code> ${escape(alt.nombre || "")}</p>
          <p class="text-[10px] text-slate-400">${escape(alt.sop || "")} · score ${Number(alt.score || 0)} · ${escape(alt.motivo || "")}</p>
        </div>
      </li>`
        )
        .join("")}</ul>`
    : "";

  const elegir = congelada
    ? `<p class="text-[11px] text-slate-400 mt-2">Marca ya aplicada en Postgres — congelada.</p>`
    : `<div class="mt-3" data-signals="${escape(JSON.stringify({ [sig(id8)]: sugerido }))}">
        <p class="text-[11px] uppercase tracking-wide text-slate-400 mb-1">O elige del catálogo</p>
        ${catalogoSelect(id8, sugerido)}
        <div class="flex items-center gap-2 mt-2">
          <button class="btn btn-primary btn-xs" data-on:click="@post('/c/arquetipo-detail/act/mark?id='+encodeURIComponent(${escape(jsStr(id8))})+'&a='+encodeURIComponent($${sig(id8)}))"
            data-indicator:loading title="Marcar el arquetipo elegido">Elegir este</button>
          <button class="btn btn-ghost btn-xs" data-on:click="${post(id8, "ninguno")}" data-indicator:loading
            title="Ninguno de los del catálogo sirve — candidato a arquetipo nuevo">Ninguno</button>
        </div>
      </div>`;

  const actual = marca
    ? `<p class="text-[11px] text-slate-500 mt-2">Marca actual: ${marcaBadge(marca)}${marca.decidida_en ? ` <span class="text-slate-400">${escape(String(marca.decidida_en).slice(0, 16))}</span>` : ""}${marca.decision_nota ? ` — ${escape(marca.decision_nota)}` : ""}</p>`
    : "";

  return `<div class="rounded-lg px-3 py-2" style="background:var(--surface-2);border:1px solid var(--border-1)">
    ${cabeza}${alts}${elegir}${actual}
    <p class="text-[11px] text-slate-400 mt-3">Etiquetar mueve el puntero; no reescribe el contrato IO de la tarea.</p>
  </div>`;
}

// El detalle de la tarea, sin la cáscara de task-detail (su id colisiona con el
// de este panel) y sin su botón de cerrar (el ✕ de este panel es el de arriba,
// uno solo). Lo que queda de `$selectedTask` apunta a NUESTRA señal.
//
// Es cirugía sobre el HTML de otro bloque, así que falla RUIDOSAMENTE: si
// task-detail cambia su cáscara, esto revienta con un mensaje que dice qué
// arreglar, en vez de servir un `#task-detail` duplicado y un `</div>` de más
// que nadie ve hasta que el panel se descuadra.
const SHELL_ABRE = '<div id="task-detail"';
// El ✕ heredado y el `-mt-6` que compensa su fila: se van juntos o no se va
// ninguno (quitar el botón dejando el margen negativo sube el título encima).
const RE_CERRAR = /<div class="flex items-start gap-2 mb-1">\s*<button data-on:click="\$detailOpen=false; \$selectedTask=''"[\s\S]*?<\/button>\s*<\/div>\s*/;

function detalleTarea(id8) {
  const raw = String(renderTaskDetail(id8));
  if (!raw.startsWith(SHELL_ABRE) || !raw.endsWith("</div>")) {
    throw new Error("task-detail cambió su cáscara — arquetipo-detail debe actualizarse");
  }
  let inner = raw.replace(/^<div id="task-detail"[^>]*>/, "").replace(/<\/div>$/, "");
  // El estado vacío / de error de task-detail no trae botón de cerrar: quitarlo
  // es opcional, cambiar la señal no.
  if (RE_CERRAR.test(inner)) inner = inner.replace(RE_CERRAR, "").replace(' mb-2 -mt-6 pr-6"', ' mb-2 pr-6"');
  return inner.split("$selectedTask=''").join("$selectedArq=''");
}

// El ✕ del panel, arriba a la derecha — la convención de la casa (task-detail,
// task-edit-form, propuesta-detail). Antes el único ✕ era el heredado, que
// quedaba ~300 px abajo, después de la tarjeta del arquetipo.
const CERRAR = `<div class="flex items-start gap-2">
  <button data-on:click="$detailOpen=false; $selectedArq=''" class="ml-auto -mr-1 -mt-1 text-slate-400 hover:text-slate-600 text-lg leading-none" title="Cerrar">✕</button>
</div>`;

function buscarMarca(id8) {
  try {
    return fetchSource("arquetipo_marcas").rows.find((m) => String(m.task_id || "").startsWith(id8)) || null;
  } catch {
    return null;
  }
}

function panel(id8, aviso) {
  if (!id8) return vacio("Selecciona una tarea para ver su detalle y decidir su arquetipo.");
  let row = null;
  let err = null;
  try {
    // Acotado por `--id`: sin él esto re-corría el matcher sobre TODAS las
    // tareas sin arquetipo en cada clic de fila (3.6 s medidos). El score sale
    // idéntico — el filtro no toca el universo de vecinos que vota.
    row = fetchSource("tareas_sin_arquetipo", { id: id8 }).rows.find((r) => String(r.id) === String(id8)) || null;
  } catch (e) {
    err = e.message;
  }
  const marca = buscarMarca(id8);
  const banner = aviso ? `<div class="alert alert-neg mb-3">${escape(aviso)}</div>` : "";
  const fallo = err ? `<div class="alert alert-neg mb-3">${escape(err)}</div>` : "";
  return shell(`<div class="p-5 pb-0">
      ${CERRAR}
      ${banner}${fallo}
      ${section("Arquetipo propuesto", null, bloqueSugerido(id8, row, marca))}
    </div>
    ${detalleTarea(id8)}`);
}

const acts = {
  // Marca el arquetipo (sqlite local) y devuelve DOS parches: el panel y el
  // badge de la fila del maestro (`#arq-<id8>`). Nunca el pane entero: eso
  // cerraría el panel abierto.
  mark: (ctx) => {
    const id8 = ctx.params.get("id") || "";
    const a = ctx.params.get("a") || "";
    const r = ctx.run(AMARK, [id8, "--arquetipo", a]);
    const err = r && r.ok === false ? r.error || "El script falló" : null;
    const patches = [panel(id8, err)];
    if (!err) patches.push(`<span id="arq-${escape(id8)}">${marcaBadge(buscarMarca(id8))}</span>`);
    return patches;
  },
};

module.exports = {
  id: "arquetipo-detail",
  manifest: { slot: "detail", frag: "panel", width: WIDTH, selSignal: "selectedArq", writes: [AMARK] },
  frags: { panel: (ctx) => panel(ctx.params.get("id") || "", null) },
  acts,
};

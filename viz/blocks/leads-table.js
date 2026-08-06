// leads-table block — el MASTER sobre `crm_leads`: los leads del CRM como
// filas, con su dueño y su procedencia.
//
// LA IDEA DE UX QUE ORDENA ESTE BLOQUE: una tabla con filtros puede expresar
// cualquier consulta, y justamente por eso no dice nada — no propone, no
// invita, deja al usuario frente a un formulario. Así que el bloque abre con
// VISTAS PROPUESTAS: las preguntas frecuentes ya armadas, en un clic. Los
// filtros siguen ahí para lo que no anticipamos, pero dejan de ser la puerta.
//
// El eje sigue siendo la procedencia: un lead que llegó por pauta y nadie tomó
// es plata quemada, y eso tiene que verse antes que cualquier ficha. Por eso la
// barra de origen encabeza la tabla y `origen`/`campaña` van antes que el resto.
//
// Contrato master: signals / regetQS / controls / table(rows, wire) / counter.

const { fetchSource } = require("../lib/datasources");
const { escape, cell, selectCtl, checkCtl } = require("../lib/kit");

const INDICATOR = "loadingleads";
const SIN_DUENO = "sin-dueno";

// Fuera de la lista, a propósito: email y teléfono (están en el panel; aquí
// solo se desbordaban) y `creada` («días» dice lo mismo y se barre mejor).
const COLS = [
  { k: "dias", l: "Días", w: "w-16", align: "text-center" },
  { k: "lead", l: "Lead", w: "w-[18%]" },
  { k: "dueno", l: "Dueño", w: "w-36" },
  { k: "origen", l: "Origen", w: "w-24" },
  { k: "campana", l: "Campaña", w: "w-[20%]" },
  { k: "tags", l: "Formulario (tags)" },
  { k: "etapa", l: "Etapa", w: "w-40" },
];

// VISTAS PROPUESTAS — el corazón del bloque. Cada una es una pregunta real que
// alguien se hace, no una combinación cualquiera de filtros.
const VISTAS = [
  {
    id: "sin-dueno",
    label: "Sin dueño",
    hint: "Leads que entraron y nadie tomó",
    set: { dueno: [SIN_DUENO], origen: "", stage: "", diasMin: "" },
  },
  {
    id: "pagados-sueltos",
    label: "Pagados sin dueño",
    hint: "Los compramos por pauta y nadie los tomó",
    set: { dueno: [SIN_DUENO], origen: "pagado", stage: "", diasMin: "" },
  },
  {
    id: "enfriados",
    label: "Sin dueño y fríos",
    hint: "Sin dueño hace más de 7 días",
    set: { dueno: [SIN_DUENO], origen: "", stage: "", diasMin: "7" },
  },
  {
    id: "nuevo-lead",
    label: "Estancados en NUEVO LEAD",
    hint: "Nunca salieron de la primera etapa",
    set: { dueno: [], origen: "", stage: "NUEVO LEAD", diasMin: "7" },
  },
  {
    id: "todos",
    label: "Todos",
    hint: "Sin filtros de dueño ni origen",
    set: { dueno: [], origen: "", stage: "", diasMin: "" },
  },
];

// La antigüedad se lee como semáforo: fresco todavía se puede rescatar, viejo
// ya es autopsia. Los cortes (3 / 7 / 21 días) siguen el ciclo comercial del
// equipo, no una escala genérica.
function diasCell(d) {
  const n = Number(d);
  if (!Number.isFinite(n)) return '<span class="text-slate-300">—</span>';
  const cls = n <= 3 ? "badge-pos" : n <= 7 ? "badge-cau" : n <= 21 ? "badge-neg" : "badge-neutral";
  return `<span class="badge ${cls}" title="${n} días desde que entró">${n}d</span>`;
}

function duenoCell(v) {
  if (!v || v === "—")
    return '<span class="badge badge-neg" title="Ningún closer responsable">sin dueño</span>';
  return `<span class="text-slate-700">${escape(v)}</span>`;
}

// Un lead con utm_source llegó por pauta: lo pagamos. Eso pesa distinto que uno
// orgánico, así que se distingue de un vistazo — violeta (familia de marca)
// para lo pagado, neutro apagado para lo orgánico.
function origenCell(v, r) {
  if (!v || v === "—")
    return '<span class="badge badge-neutral opacity-60" title="Sin utm_* — no llegó por pauta">orgánico</span>';
  const t = r && r.campana && r.campana !== "—" ? `Meta Ads · ${r.campana}` : "Meta Ads";
  return `<span class="badge bg-violet-100 text-violet-700" title="${escape(t)}">${escape(v)}</span>`;
}

// El nombre de campaña es un slug largo (006_DC_TRAFICO_FRIO_OVERLAY) sin
// espacios: en table-fixed no hay dónde partir la línea, así que trunca con el
// valor completo en el title.
function campanaCell(v) {
  if (!v || v === "—") return '<span class="text-slate-300">—</span>';
  return `<span class="block truncate text-xs font-mono text-slate-600" title="${escape(v)}">${escape(v)}</span>`;
}

// Los tags de GHL son la huella del formulario por el que entró el lead
// (modulo5yt, lleno encuesta organico, premium academy…).
function tagsCell(v) {
  if (!v || v === "—") return '<span class="text-slate-300">—</span>';
  return v
    .split(",")
    .map((t) => t.trim())
    .filter(Boolean)
    .slice(0, 3)
    .map((t) => `<span class="badge badge-neutral mr-1">${escape(t)}</span>`)
    .join("");
}

function bodyCell(col, r) {
  if (col === "dias") return diasCell(r[col]);
  if (col === "dueno") return duenoCell(r[col]);
  if (col === "origen") return origenCell(r[col], r);
  if (col === "campana") return campanaCell(r[col]);
  if (col === "tags") return tagsCell(r[col]);
  // El nombre del lead suele traer espacios, pero a veces llega un correo o un
  // handle pegado sin ninguno; break-words lo dobla en vez de derramarlo.
  if (col === "lead") return `<span class="block break-words">${escape(r[col] || "—")}</span>`;
  return cell(r[col]);
}

const ORIGEN_OPTS = [
  ["", "Origen: todos"],
  ["pagado", "Pagados (con utm)"],
  ["organico", "Orgánicos (sin utm)"],
];

function signals(p) {
  return {
    // Array: varios checkboxes con la misma señal acumulan sus `value`
    // (Datastar 1.0 — la señal DEBE venir predefinida como array).
    lDueno: p.dueno ? String(p.dueno).split(",").filter(Boolean) : [],
    lProject: p.project || "",
    lOrigen: p.origen || "",
    lStage: p.stage || "",
    lDiasMin: p.dias_min || "",
    lFrom: p.from || "",
    lTo: p.to || "",
  };
}

const regetQS =
  `'limit=0&dueno='+encodeURIComponent($lDueno.join(','))` +
  `+'&project='+encodeURIComponent($lProject)+'&origen='+encodeURIComponent($lOrigen)` +
  `+'&stage='+encodeURIComponent($lStage)+'&dias_min='+encodeURIComponent($lDiasMin)` +
  `+'&from='+encodeURIComponent($lFrom)+'&to='+encodeURIComponent($lTo)`;

// Facetas: el universo de dueños/etapas, independiente del filtro actual.
function facets(p) {
  try {
    const rows = fetchSource("crm_facets", { project: p.project || "", from: p.from || "" }).rows;
    return {
      duenos: rows.filter((r) => r.tipo === "dueno"),
      etapas: rows.filter((r) => r.tipo === "etapa"),
    };
  } catch {
    return { duenos: [], etapas: [] };
  }
}

function vistaButtons(reget) {
  return VISTAS.map((v) => {
    const sets = [
      `$lDueno=${JSON.stringify(v.set.dueno)}`,
      `$lOrigen='${v.set.origen}'`,
      `$lStage='${v.set.stage.replace(/'/g, "\\'")}'`,
      `$lDiasMin='${v.set.diasMin}'`,
    ].join("; ");
    return `<button class="btn btn-sm" title="${escape(v.hint)}"
      data-on:click="${escape(sets)}; ${escape(reget)}" data-indicator:${INDICATOR}>${escape(v.label)}</button>`;
  }).join("");
}

function controls(p, reget) {
  const { duenos, etapas } = facets(p);

  let projectOpts = [["", "Proyecto: todos"]];
  try {
    projectOpts = projectOpts.concat(
      fetchSource("projects").rows.map((r) => [r.name, r.name]).filter(([n]) => n)
    );
  } catch {
    /* keep the "todos" fallback */
  }

  const stageOpts = [["", "Etapa: todas"]].concat(
    etapas.filter((e) => e.valor && e.valor !== "—").map((e) => [e.valor, `${e.valor} (${e.n})`])
  );

  // Multiselect de dueños: un checkbox por dueño sobre la MISMA señal array.
  // El `.check` del DS no trae margen propio (es inline-flex y su gap es
  // interno), así que el ritmo lo pone el contenedor: gap-x generoso para que
  // cada casilla se lea como un item y no como una lista corrida, gap-y para
  // cuando la fila se envuelve, y mt para despegarla de los selects.
  // `checked` se emite desde el servidor y NO se delega a Datastar: si el DOM
  // llega todo desmarcado y la señal dice otra cosa, cada re-render deja a los
  // dos en desacuerdo y la selección parpadea. Renderizados iguales, da lo mismo
  // cuál de los dos gane al inicializar.
  const seleccionados = new Set(
    String(p.dueno || "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean)
  );
  const duenoChecks = duenos.length
    ? `<div class="flex flex-wrap items-center gap-x-3 gap-y-2 mt-3">
        <span class="text-xs text-slate-400">Dueño:</span>
        ${duenos
          .map((d) =>
            checkCtl("lDueno", d.valor === SIN_DUENO ? `sin dueño (${d.n})` : `${d.valor} (${d.n})`, reget, {
              indicator: INDICATOR,
              value: d.valor,
              checked: seleccionados.has(d.valor),
              cls: "text-xs",
              // El reget LEE $lDueno, que es la señal que este mismo click
              // acaba de cambiar: diferirlo garantiza que el binding ya escribió.
              mods: "__debounce.50ms",
            })
          )
          .join("")}
      </div>`
    : "";

  const dateCtl = (sig, label) =>
    `<label class="text-xs text-slate-500 flex items-center gap-1">${escape(label)}
      <input type="date" class="input text-xs" data-bind="${sig}" data-on:change="${reget}" data-indicator:${INDICATOR}>
    </label>`;

  // Tres bandas con el mismo ritmo vertical (mt-3): vistas propuestas arriba,
  // luego los selects, y abajo el multiselect de dueños. Sin esa separación las
  // tres se leen como una sola masa de controles.
  return `<div class="w-full">
    <div class="flex flex-wrap items-center gap-2">
      <span class="text-xs text-slate-400 mr-1">Vistas:</span>${vistaButtons(reget)}
    </div>
    <div class="flex flex-wrap items-center gap-2 mt-3">
      ${selectCtl("lProject", p.project || "", projectOpts, reget, INDICATOR)}
      ${selectCtl("lStage", p.stage || "", stageOpts, reget, INDICATOR)}
      ${selectCtl("lOrigen", p.origen || "", ORIGEN_OPTS, reget, INDICATOR)}
      ${dateCtl("lFrom", "desde")}
      ${dateCtl("lTo", "hasta")}
    </div>
    ${duenoChecks}
  </div>`;
}

// El desglose de procedencia va ARRIBA de la tabla: es la respuesta a la
// pregunta de la vista, y reconstruirla contando filas la haría inútil. Se
// calcula sobre las filas traídas, así que respeta los filtros activos.
function originBar(rows) {
  if (!rows.length) return "";
  const pagados = rows.filter((r) => r.origen && r.origen !== "—");
  const huerfanos = rows.filter((r) => !r.dueno || r.dueno === "—");
  const pagadosHuerfanos = pagados.filter((r) => !r.dueno || r.dueno === "—");

  const porFuente = new Map();
  for (const r of pagados) porFuente.set(r.origen, (porFuente.get(r.origen) || 0) + 1);
  const porCampana = new Map();
  for (const r of pagados) {
    if (r.campana && r.campana !== "—") porCampana.set(r.campana, (porCampana.get(r.campana) || 0) + 1);
  }
  const top = [...porCampana.entries()].sort((a, b) => b[1] - a[1]).slice(0, 3);
  const pct = Math.round((pagados.length / rows.length) * 100);

  const fuentes = [...porFuente.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([k, n]) => `<span class="badge bg-violet-100 text-violet-700 mr-1">${escape(k)} ${n}</span>`)
    .join("");

  return `<div class="card mb-3 p-3 text-xs">
    <p class="text-slate-600 mb-2">
      <b class="text-slate-800">${pagados.length}</b> de ${rows.length} (${pct}%) llegaron por <b>pauta</b>
      · <b class="text-slate-800">${rows.length - pagados.length}</b> orgánicos${
        huerfanos.length
          ? ` · <b class="text-slate-800">${huerfanos.length}</b> sin dueño${
              pagadosHuerfanos.length
                ? `, de los cuales <b class="text-slate-800">${pagadosHuerfanos.length}</b> pagados`
                : ""
            }`
          : ""
      }
    </p>
    <div class="mb-1">${fuentes}${
      rows.length - pagados.length
        ? `<span class="badge badge-neutral opacity-60">orgánico ${rows.length - pagados.length}</span>`
        : ""
    }</div>
    ${
      top.length
        ? `<p class="text-slate-500">Campañas con más leads: ${top
            .map(([c, n]) => `<span class="font-mono">${escape(c)}</span> (${n})`)
            .join(" · ")}</p>`
        : ""
    }
  </div>`;
}

function table(rows, wire) {
  const thead = COLS.map((c) => `<th class="${c.align || "text-left"} ${c.w || ""}">${escape(c.l)}</th>`).join("");
  const tbody = rows
    .map(
      (r) =>
        // overflow-hidden en la celda: con table-fixed el ancho está dado, y sin
        // esto cualquier contenido sin puntos de corte se sale de su columna.
        `<tr ${wire.rowAttrs(r)} class="cursor-pointer">${COLS.map(
          (c) => `<td class="align-top overflow-hidden ${c.align || ""} ${c.cls || ""}">${bodyCell(c.k, r)}</td>`
        ).join("")}</tr>`
    )
    .join("");
  return `${originBar(rows)}<div class="table-wrap"><div class="table-scroll overflow-y-auto max-h-[calc(100vh-18rem)]"><table class="tbl w-full min-w-[58rem] table-fixed">
    <thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table></div></div>`;
}

module.exports = {
  id: "leads-table",
  manifest: {
    slot: "master",
    consumes: "rows",
    indicator: INDICATOR,
    overridable: [
      "dueno",
      "project",
      "status",
      "stage",
      "from",
      "to",
      "dias_min",
      "limit",
      "origen",
      "con_contacto",
      "sin_contacto",
    ],
  },
  signals,
  regetQS,
  controls,
  table,
  counter: (n) => `${n} lead(s)`,
  headerExtra: "",
};

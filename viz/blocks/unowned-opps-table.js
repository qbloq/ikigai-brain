// unowned-opps-table block — the MASTER slot over `crm_sin_dueno`: los leads
// que entraron al CRM y NADIE tomó (`crm_opportunities.user_id` NULL porque
// GHL no trae `assigned_to`).
//
// La vista existe para responder DE DÓNDE VIENEN. Un lead suelto se explica
// por su procedencia, no por su ficha: si llegó por pauta lo pagamos, y un
// lead pagado que nadie tomó es plata quemada — eso es lo que hay que ver
// primero. Por eso la barra de origen encabeza la tabla y `origen`/`campaña`
// van antes que cualquier dato del contacto.
//
// `dias` es el segundo eje: un lead sin dueño no es un dato, es una cuenta
// regresiva. Ordena por antigüedad y la tiñe — a los 7 días la conversación ya
// se enfrió, y esa señal tiene que verse sin leer la fecha.
//
// Contrato master, igual que calls-table: signals / regetQS / controls /
// table(rows, wire) / counter.

const { fetchSource } = require("../lib/datasources");
const { escape, cell, selectCtl } = require("../lib/kit");

const INDICATOR = "loadingsindueno";

// La vista responde a UNA pregunta: de dónde vienen los leads que nadie tomó.
// Por eso el eje son las tres señales de procedencia —origen pagado, campaña y
// el formulario de entrada (tags)— y todo lo demás cede el sitio.
//
// Fuera quedaron, a propósito:
//   · email y teléfono → están en el panel; aquí solo se desbordaban
//   · estado           → es 'open' en las 237, no distingue nada
//   · creada           → «días» dice lo mismo y se barre mejor; la fecha exacta
//                        vive en el panel
const COLS = [
  { k: "dias", l: "Días", w: "w-16", align: "text-center" },
  { k: "lead", l: "Lead", w: "w-[20%]" },
  { k: "origen", l: "Origen", w: "w-28" },
  { k: "campana", l: "Campaña", w: "w-[24%]" },
  { k: "tags", l: "Formulario (tags)" },
  { k: "etapa", l: "Etapa", w: "w-40" },
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

// Un lead con utm_source llegó por pauta: lo pagamos y nadie lo tomó. Eso pesa
// distinto que un orgánico sin dueño, así que se distingue de un vistazo —
// violeta (familia de marca) para lo pagado, neutro apagado para lo orgánico.
function origenCell(v, r) {
  if (!v || v === "—")
    return '<span class="badge badge-neutral opacity-60" title="Sin utm_* — no llegó por pauta">orgánico</span>';
  const t = r && r.campana && r.campana !== "—" ? `Meta Ads · ${r.campana}` : "Meta Ads";
  return `<span class="badge bg-violet-100 text-violet-700" title="${escape(t)}">${escape(v)}</span>`;
}

// El nombre de campaña es un slug largo (006_DC_TRAFICO_FRIO_OVERLAY) sin
// espacios: trunca con el valor completo en el title, igual que hacía el email.
function campanaCell(v) {
  if (!v || v === "—") return '<span class="text-slate-300">—</span>';
  return `<span class="block truncate text-xs font-mono text-slate-600" title="${escape(v)}">${escape(v)}</span>`;
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
  if (col === "origen") return origenCell(r[col], r);
  if (col === "campana") return campanaCell(r[col]);
  if (col === "tags") return tagsCell(r[col]);
  // El nombre del lead suele tener espacios, pero a veces llega un correo o un
  // handle pegado sin ninguno; break-words lo dobla en vez de derramarlo sobre
  // la columna vecina (en table-fixed el ancho no cede).
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
    sdProject: p.project || "",
    sdOrigen: p.origen || "",
    sdFrom: p.from || "",
    sdTo: p.to || "",
  };
}

const regetQS =
  `'limit=0&project='+encodeURIComponent($sdProject)+'&origen='+encodeURIComponent($sdOrigen)` +
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
    selectCtl("sdOrigen", p.origen || "", ORIGEN_OPTS, reget, INDICATOR),
    dateCtl("sdFrom", "desde"),
    dateCtl("sdTo", "hasta"),
  ].join("");
}

// El desglose de procedencia va ARRIBA de la tabla, no en un gráfico aparte:
// es la respuesta a la pregunta de la vista, y tenerla que reconstruir contando
// filas la haría inútil. Se calcula sobre las filas ya traídas, así que respeta
// los filtros activos.
function originBar(rows) {
  if (!rows.length) return "";
  const pagados = rows.filter((r) => r.origen && r.origen !== "—");
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
      <b class="text-slate-800">${pagados.length}</b> de ${rows.length} (${pct}%) llegaron por <b>pauta</b> y nadie los tomó
      · <b class="text-slate-800">${rows.length - pagados.length}</b> orgánicos
    </p>
    <div class="mb-1">${fuentes}${
      rows.length - pagados.length
        ? `<span class="badge badge-neutral opacity-60">orgánico ${rows.length - pagados.length}</span>`
        : ""
    }</div>
    ${
      top.length
        ? `<p class="text-slate-500">Campañas con más leads sueltos: ${top
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
        // overflow-hidden en la celda: con table-fixed el ancho está dado, y
        // sin esto cualquier contenido sin puntos de corte se sale de su columna.
        `<tr ${wire.rowAttrs(r)} class="cursor-pointer">${COLS.map(
          (c) => `<td class="align-top overflow-hidden ${c.align || ""} ${c.cls || ""}">${bodyCell(c.k, r)}</td>`
        ).join("")}</tr>`
    )
    .join("");
  // 52rem: el slug de campaña necesita aire, pero sin los datos de contacto la
  // tabla sigue cabiendo con el panel de detalle abierto. La altura cede 2rem
  // más porque ahora la barra de origen va encima.
  return `${originBar(rows)}<div class="table-wrap"><div class="table-scroll overflow-y-auto max-h-[calc(100vh-14rem)]"><table class="tbl w-full min-w-[52rem] table-fixed">
    <thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table></div></div>`;
}

module.exports = {
  id: "unowned-opps-table",
  manifest: {
    slot: "master",
    consumes: "rows",
    indicator: INDICATOR,
    overridable: ["project", "status", "stage", "from", "to", "limit", "origen", "con_contacto", "sin_contacto"],
  },
  signals,
  regetQS,
  controls,
  table,
  counter: (n) => `${n} lead(s) sin dueño`,
  headerExtra:
    '<span class="badge badge-neg" title="user_id NULL porque GHL no trae assigned_to — verificado contra la fuente">nadie asignado</span>',
};

// mesa-despacho page — la consola de la Mesa de Despacho del agente WhatsApp
// «Iki» (un dispatcher: captura recados y propone enrutamientos).
//
// v2: la cola ya no lee los recados en vivo sino la COLA DE DESPACHO con
// estados (`iki_despachos` → bash/agentes/despachos.sh): cada tarjeta trae su
// estado como badge y, si está `pendiente`, los botones Aprobar / Rechazar —
// el ÚNICO write de la página, vía despacho_mark.sh declarado en
// manifest.writes (patrón exacto del botón Merge de la UI `cruce`). El
// guardrail vive en el script (solo filas pendiente); si falla, el error se
// muestra en un alert-neg, nunca se traga.
//
// La fuente secundaria (iki_entradas, los mensajes crudos que recibió el
// agente) se pide aquí directamente, como en localdb.js. Ninguna se cachea —
// es una vista operativa viva. El id corto (8 chars) va SIEMPRE visible: es
// el handle que el usuario dicta en conversación (regla del repo: viz es el
// visor, la edición pasa por bash/ + skill — este write predata esa regla en
// su patrón, el del cruce, y comparte su mecánica).

const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");
const store = require("../lib/store");

const MARK = "bash/agentes/despacho_mark.sh";
const ENTRADAS_LIMIT = 20;

function fechaCorta(v) {
  // "2026-08-12T15:52:31" → "2026-08-12 15:52"
  const m = /^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})/.exec(String(v ?? ""));
  return m ? `${m[1]} ${m[2]}` : escape(String(v ?? "—"));
}

// Tono del badge de urgencia — heurístico sobre texto libre: rojo cuando pide
// acción inmediata, precaución cuando trae un plazo, neutral cuando puede esperar.
function urgenciaBadge(u) {
  const t = String(u || "").toLowerCase();
  if (!t) return "";
  let cls = "badge-cau";
  if (/urgente|ahora|inmediat|ya\b|hoy/.test(t)) cls = "badge-neg";
  else if (/cuando se pueda|sin (urgencia|afán|apuro)|no urge/.test(t)) cls = "badge-neutral";
  return `<span class="badge ${cls}" title="Urgencia">${escape(u)}</span>`;
}

// El estado del despacho, con las clases badge del DS: pendiente pide un ojo
// (cau), aprobado es una decisión de marca aún no ejecutada (brand), ejecutado
// es el final feliz (pos), rechazado/fallido son el negativo (neg).
const ESTADO_BADGE = {
  pendiente: "badge-cau",
  aprobado: "badge-brand",
  ejecutado: "badge-pos",
  rechazado: "badge-neg",
  fallido: "badge-neg",
};

function estadoBadge(e) {
  const cls = ESTADO_BADGE[String(e || "")] || "badge-neutral";
  return `<span class="badge ${cls}" title="Estado del despacho">${escape(e || "—")}</span>`;
}

// Los botones de la fila pendiente — el único write. Mismo mecanismo que el
// botón Merge del cruce: @post al act + data-indicator:loading (regla de
// furniture: todo botón que re-fetchea lleva su indicador).
function botones(r, uiId) {
  if (r.estado !== "pendiente") return "";
  const post = (a) => `@post('/c/mesa-despacho/act/mark?ui=${escape(uiId)}&n=${r.n}&a=${a}')`;
  return `<div class="mt-3 flex items-center gap-2">
    <button data-on:click="${post("aprobar")}" data-indicator:loading
      class="btn btn-primary btn-xs" title="Aprobar el enrutamiento propuesto">Aprobar</button>
    <button data-on:click="${post("rechazar")}" data-indicator:loading
      class="btn btn-danger btn-xs" title="Rechazar el enrutamiento propuesto">Rechazar</button>
  </div>`;
}

function tarjetaDespacho(r, uiId) {
  const contexto =
    r.contexto && !/^\(ningun/i.test(String(r.contexto).trim())
      ? `<p class="text-xs mt-1" style="color:var(--text-3)">${escape(r.contexto)}</p>`
      : "";
  const nota = r.nota
    ? `<p class="text-xs mt-2 italic" style="color:var(--text-2)">Nota: ${escape(r.nota)}</p>`
    : "";
  const ejecutado = r.ejecutado_at ? ` · ejecutado ${fechaCorta(r.ejecutado_at)}` : "";
  return `<div class="card card-pad mb-3">
    <div class="flex items-baseline justify-between gap-3 flex-wrap">
      <p class="text-sm font-semibold" style="color:var(--text-1)">
        ${escape(r.de || "—")} <span style="color:var(--text-3)">→</span> ${escape(r.para || "—")}
      </p>
      <div class="flex items-baseline gap-2 shrink-0">
        ${estadoBadge(r.estado)}
        ${urgenciaBadge(r.urgencia)}
        <span class="font-mono text-[11px]" style="color:var(--text-3)" title="recado ${escape(r.recado || "")} · fila n=${r.n}">${escape(String(r.recado || "").slice(0, 8))}</span>
      </div>
    </div>
    <p class="text-sm mt-2" style="color:var(--text-1)">${escape(r.que || "—")}</p>
    ${contexto}
    ${r.propuesta ? `<div class="alert alert-brand mt-3 text-sm">
      <span class="text-[11px] font-bold uppercase" style="letter-spacing:var(--tr-micro)">Propuesta</span>
      <span class="block mt-0.5">${escape(r.propuesta)}</span>
    </div>` : ""}
    ${nota}
    ${botones(r, uiId)}
    <p class="mt-2 text-[11px]" style="color:var(--text-3)">${fechaCorta(r.fecha)}${ejecutado}</p>
  </div>`;
}

function cajaError(msg) {
  return `<div class="alert alert-neg text-sm">${escape(msg)}</div>`;
}

// El fragmento re-renderizable: encabezado con conteo + tarjetas, parcheado
// entero tras cada act (patrón tablaFrag del cruce). `pre` deja que el render
// de página reutilice filas ya pedidas; `actErr` es el error del write (el
// guardrail del script es la última línea de defensa — su mensaje se muestra,
// no se traga).
function colaFrag(ui, actErr, pre) {
  let rows = pre || null;
  let fail = null;
  if (!rows) {
    try {
      ({ rows } = fetchSource(ui.source || "iki_despachos", ui.params || {}));
    } catch (e) {
      rows = [];
      fail = e.message;
    }
  }
  // más reciente primero (orden de presentación, en JS — nunca un flag al shell)
  rows = [...rows].sort((a, b) => String(b.fecha || "").localeCompare(String(a.fecha || "")));
  const pendientes = rows.filter((r) => r.estado === "pendiente").length;
  const banner = actErr ? `<div class="mb-3">${cajaError(actErr)}</div>` : "";
  const cuerpo = fail
    ? cajaError(fail)
    : rows.length
      ? rows.map((r) => tarjetaDespacho(r, ui.id)).join("")
      : `<p class="text-sm italic" style="color:var(--text-3)">La cola está vacía — Iki no tiene despachos registrados.</p>`;
  return `<div id="mesa-cola" class="relative">
    <div data-show="$loading" class="absolute inset-0 bg-white/50 flex items-center justify-center transition-opacity duration-200 z-10">
      <span class="animate-spin inline-block w-5 h-5 rounded-full" style="border:2px solid var(--brand-solid);border-top-color:transparent"></span>
    </div>
    <div class="flex items-baseline gap-3 mb-3">
      <h2 class="text-sm font-bold uppercase tracking-wider" style="color:var(--text-2);letter-spacing:var(--tr-micro)">Cola de despacho</h2>
      <span class="text-xs" style="color:var(--text-3)">${fail ? "" : `${rows.length} despacho(s) · ${pendientes} pendiente(s)`}</span>
    </div>
    ${banner}
    ${cuerpo}
  </div>`;
}

function filaEntrada(e) {
  return `<li class="flex items-baseline gap-2 px-3 py-1.5 border-b" style="border-color:var(--border-1)">
    <span class="font-mono text-[11px] shrink-0 tabular-nums" style="color:var(--text-3)">${fechaCorta(e.fecha)}</span>
    <span class="badge badge-neutral shrink-0">${escape(e.canal || "?")}</span>
    <span class="text-xs shrink-0" style="color:var(--text-2)">${escape(e.remitente || "—")}</span>
    <span class="text-xs truncate" style="color:var(--text-1)" title="${escape(e.texto || "")}">${escape(e.texto || "")}</span>
  </li>`;
}

function renderMesaDespacho(ui) {
  let entradas = [];
  let entradasErr;
  try {
    ({ rows: entradas } = fetchSource("iki_entradas", { limit: ENTRADAS_LIMIT }));
  } catch (e) {
    entradasErr = e.message;
  }
  entradas = [...entradas].sort((a, b) => String(b.fecha || "").localeCompare(String(a.fecha || "")));

  const lista = entradasErr
    ? cajaError(entradasErr)
    : entradas.length
      ? `<div class="card"><ul>${entradas.map(filaEntrada).join("")}</ul></div>`
      : `<p class="text-sm italic" style="color:var(--text-3)">Sin entradas registradas.</p>`;

  // `id="pane"` NO es decorativo: el servidor parchea por SSE sobre ese id.
  // `data-signals` siembra el indicador de loading de los acts.
  return `<section id="pane" class="flex-1 p-6 overflow-auto" data-signals="{loading:false}">
    <div class="max-w-4xl">
    <header class="mb-4">
      <h1 class="text-xl font-bold" style="color:var(--text-1)">Mesa de Despacho — Iki</h1>
      <p class="text-xs mt-1" style="color:var(--text-3)">
        La cola de despacho del agente WhatsApp: cada tarjeta trae el enrutamiento
        propuesto y su estado; las pendientes se aprueban o rechazan aquí. El id
        corto es el handle que se dicta en conversación.
      </p>
    </header>
    ${colaFrag(ui)}
    <div class="flex items-baseline gap-3 mt-10 mb-3">
      <h2 class="text-sm font-bold uppercase tracking-wider" style="color:var(--text-2);letter-spacing:var(--tr-micro)">Entradas recientes</h2>
      <span class="text-xs" style="color:var(--text-3)">${entradasErr ? "" : `últimas ${entradas.length}`}</span>
    </div>
    ${lista}
    <p class="mt-8 text-[11px]" style="color:var(--text-3)">
      Fuentes: <code>bash/agentes/despachos.sh</code> · <code>bash/agentes/entradas.sh</code> (read-only, sin cache).
      Write: <code>bash/agentes/despacho_mark.sh</code> (solo filas pendientes).
    </p>
    </div>
  </section>`;
}

const frags = {
  // Re-render de la cola sola (por si un control futuro la refresca sin acts).
  cola: (ctx) => {
    const ui = store.get(ctx.params.get("ui") || "");
    if (!ui) return `<div id="mesa-cola">${cajaError("UI desconocida.")}</div>`;
    return colaFrag(ui);
  },
};

const acts = {
  // Aprobar/rechazar UNA fila pendiente, luego re-render del fragmento.
  // Mismo contrato que cruce.acts.mark: el guardrail (solo pendientes) lo
  // re-impone despacho_mark.sh server-side; aquí solo se valida la forma.
  mark: (ctx) => {
    const uiId = ctx.params.get("ui") || "";
    const n = ctx.params.get("n") || "";
    const a = ctx.params.get("a") || "";
    const ui = store.get(uiId);
    if (!ui) return `<div id="mesa-cola">${cajaError(`UI desconocida: ${uiId}`)}</div>`;
    if (!/^\d+$/.test(n)) return colaFrag(ui, `n inválido: «${n}» — debe ser numérico.`);
    const flag = a === "aprobar" ? "--aprobar" : a === "rechazar" ? "--rechazar" : null;
    if (!flag) return colaFrag(ui, `Acción inválida: «${a}» — usa aprobar o rechazar.`);
    const r = ctx.run(MARK, [n, flag]);
    return colaFrag(ui, r && r.ok === false ? r.error : null);
  },
};

module.exports = {
  id: "mesa-despacho",
  render: renderMesaDespacho,
  frags,
  acts,
  manifest: { consumes: "rows", overridable: [], writes: [MARK] },
};

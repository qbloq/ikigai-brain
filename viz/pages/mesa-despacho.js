// mesa-despacho page — la consola de observabilidad del agente WhatsApp «Iki»
// (un dispatcher: captura recados y propone enrutamientos).
//
// Dos fuentes, mismo mecanismo que localdb.js (una página puede llamar
// fetchSource más de una vez): la principal viaja en el spec (`ui.source` =
// iki_recados, la cola de despacho) y la secundaria (iki_entradas, los
// mensajes crudos que recibió el agente) se pide aquí directamente. Ninguna
// se cachea — es una vista operativa viva.
//
// v1 es render estático server-side: sin filtros, sin re-fetch, sin señales.
// La propuesta de cada recado es el enrutamiento que un humano aprobará en la
// fase siguiente — por eso va destacada — y el id corto (8 chars) va SIEMPRE
// visible: es el handle que el usuario dicta en conversación (regla del repo:
// viz es el visor, la edición pasa por bash/ + skill).

const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");

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

function tarjetaRecado(r) {
  const contexto =
    r.contexto && !/^\(ningun/i.test(String(r.contexto).trim())
      ? `<p class="text-xs mt-1" style="color:var(--text-3)">${escape(r.contexto)}</p>`
      : "";
  return `<div class="card card-pad mb-3">
    <div class="flex items-baseline justify-between gap-3 flex-wrap">
      <p class="text-sm font-semibold" style="color:var(--text-1)">
        ${escape(r.de || "—")} <span style="color:var(--text-3)">→</span> ${escape(r.para || "—")}
      </p>
      <div class="flex items-baseline gap-2 shrink-0">
        ${urgenciaBadge(r.urgencia)}
        <span class="font-mono text-[11px]" style="color:var(--text-3)" title="${escape(r.id || "")}">${escape(String(r.id || "").slice(0, 8))}</span>
      </div>
    </div>
    <p class="text-sm mt-2" style="color:var(--text-1)">${escape(r.que || "—")}</p>
    ${contexto}
    ${r.propuesta ? `<div class="alert alert-brand mt-3 text-sm">
      <span class="text-[11px] font-bold uppercase" style="letter-spacing:var(--tr-micro)">Propuesta</span>
      <span class="block mt-0.5">${escape(r.propuesta)}</span>
    </div>` : ""}
    <p class="mt-2 text-[11px]" style="color:var(--text-3)">${fechaCorta(r.fecha)}${r.sesion ? ` · sesión ${escape(r.sesion)}` : ""}</p>
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

function cajaError(msg) {
  return `<div class="alert alert-neg text-sm">${escape(msg)}</div>`;
}

function renderMesaDespacho(ui) {
  let recados = [];
  let recadosErr;
  try {
    ({ rows: recados } = fetchSource(ui.source || "iki_recados", ui.params || {}));
  } catch (e) {
    recadosErr = e.message;
  }
  // más reciente primero (orden de presentación, en JS — nunca un flag al shell)
  recados = [...recados].sort((a, b) => String(b.fecha || "").localeCompare(String(a.fecha || "")));

  let entradas = [];
  let entradasErr;
  try {
    ({ rows: entradas } = fetchSource("iki_entradas", { limit: ENTRADAS_LIMIT }));
  } catch (e) {
    entradasErr = e.message;
  }
  entradas = [...entradas].sort((a, b) => String(b.fecha || "").localeCompare(String(a.fecha || "")));

  const cola = recadosErr
    ? cajaError(recadosErr)
    : recados.length
      ? recados.map(tarjetaRecado).join("")
      : `<p class="text-sm italic" style="color:var(--text-3)">La cola está vacía — Iki no tiene recados pendientes de despacho.</p>`;

  const lista = entradasErr
    ? cajaError(entradasErr)
    : entradas.length
      ? `<div class="card"><ul>${entradas.map(filaEntrada).join("")}</ul></div>`
      : `<p class="text-sm italic" style="color:var(--text-3)">Sin entradas registradas.</p>`;

  // `id="pane"` NO es decorativo: el servidor parchea por SSE sobre ese id.
  return `<section id="pane" class="flex-1 p-6 overflow-auto">
    <div class="max-w-4xl">
    <header class="mb-4">
      <h1 class="text-xl font-bold" style="color:var(--text-1)">Mesa de Despacho — Iki</h1>
      <p class="text-xs mt-1" style="color:var(--text-3)">
        La cola de recados del agente WhatsApp: cada tarjeta trae el enrutamiento
        propuesto (lo aprueba un humano en la fase siguiente) y su id corto — el
        handle que se dicta en conversación.
      </p>
    </header>
    <div class="flex items-baseline gap-3 mb-3">
      <h2 class="text-sm font-bold uppercase tracking-wider" style="color:var(--text-2);letter-spacing:var(--tr-micro)">Cola de recados</h2>
      <span class="text-xs" style="color:var(--text-3)">${recadosErr ? "" : `${recados.length} recado(s)`}</span>
    </div>
    ${cola}
    <div class="flex items-baseline gap-3 mt-10 mb-3">
      <h2 class="text-sm font-bold uppercase tracking-wider" style="color:var(--text-2);letter-spacing:var(--tr-micro)">Entradas recientes</h2>
      <span class="text-xs" style="color:var(--text-3)">${entradasErr ? "" : `últimas ${entradas.length}`}</span>
    </div>
    ${lista}
    <p class="mt-8 text-[11px]" style="color:var(--text-3)">
      Fuentes: <code>bash/agentes/recados.sh</code> · <code>bash/agentes/entradas.sh</code> (read-only, sin cache).
    </p>
    </div>
  </section>`;
}

module.exports = {
  id: "mesa-despacho",
  manifest: { consumes: "rows", overridable: [] },
  render: renderMesaDespacho,
};

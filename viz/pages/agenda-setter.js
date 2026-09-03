// agenda-setter page — la agenda del setter (día / semana) desde el único
// objeto que emite bash/setters/agenda.sh. GHL manda: lo que se lista son las
// citas de los DOS calendarios oficiales; la base solo enriquece.
//
// Dos CARRILES (corrección de Santiago, 2026-08-26):
//   Agenda de closers («Aplicación…»)  la que el setter cuadra — pocas citas,
//       con closer dueño; «sin closer» solo existe aquí (cita en manos de un
//       setter o de nadie cuando debía tener closer).
//   Funnel (llamadas del setter)       el volumen del widget — el asignado ES
//       el setter que la toma; el cruce «→ closer» muestra si el lead ya tiene
//       su cita en el carril de arriba (la etapa «agendó» del embudo), y los
//       duplicados del mismo lead se agrupan en una fila ×N.
// Cada carril con Por venir / Ya pasaron (cortadas por la hora actual) y sus
// KPIs. «Anunciada» va en gris: promesa visible, no medible aún (detector de
// anuncios de ONLY CLOSERS, v2).
// Autosuficiente: sin /c/ (el publicador v1 no lo monta) — el detalle del lead
// viaja en el HTML y se despliega con una señal por fila (data-show).
const { fetchSource } = require("../lib/datasources");
const { escape, selectCtl } = require("../lib/kit");
const { cards } = require("../blocks/kpi-cards");

const ES_GHL = { confirmed: "Confirmada", new: "Nueva", cancelled: "Cancelada", showed: "Asistió", noshow: "No asistió", invalid: "Inválida" };
const ES_ESTADO = {
  proxima: ["Por venir", "brand"], cancelada: ["Cancelada", "muted"], venta: ["Venta", "pos"],
  analizada: ["Analizada", "pos"], ocurrio_sin_analisis: ["Ocurrió, sin análisis", "cau"], sin_rastro: ["Sin rastro", "neg"],
};
const DIAS = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"];
const TONE = { pos: "var(--pos-text)", neg: "var(--neg-text)", cau: "var(--cau-text)", brand: "var(--text-brand)", muted: "var(--text-3)" };
const BANDA_TONE = { A: "pos", B: "brand", C: "cau" };
const FUENTE_LEAD = { ghl: "en vivo (GHL)", espejo: "espejo (la base)", titulo: "solo el título de la cita" };

const badge = (txt, tone = "brand", title = "") =>
  `<span class="badge" style="color:${TONE[tone]}"${title ? ` title="${escape(title)}"` : ""}>${escape(txt)}</span>`;

function diaLabel(iso) {
  const [y, m, d] = iso.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  return `${DIAS[(dt.getUTCDay() + 6) % 7]} ${d}`;
}
function sumarDias(iso, n) {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

// Los subtítulos (hint) no se pintan (pedido 2026-09-03) — el parámetro se
// conserva en las llamadas como documentación de qué es cada sección.
function section(title, hint, sub) {
  const tag = sub ? "h3" : "h2";
  return `<div class="flex items-baseline gap-3 ${sub ? "mt-5" : "mt-8"} mb-3 flex-wrap">
    <${tag} class="${sub ? "text-xs" : "text-sm"} font-bold uppercase tracking-wider" style="color:var(--text-2);letter-spacing:var(--tr-micro)">${escape(title)}</${tag}>
  </div>`;
}

function bantCell(r) {
  if (!r) return `<span style="color:var(--text-3)">—</span>`;
  const t = r.bant.total;
  const tone = t == null ? "muted" : t >= 81 ? "pos" : t >= 61 ? "brand" : "neg";
  const bc = (r.baja_confianza || []).length ? ` <span title="baja confianza: ${escape(r.baja_confianza.join(", "))}">⚠</span>` : "";
  return `<span class="tabular-nums font-semibold" style="color:${TONE[tone]}">${t == null ? "—" : t}</span>${bc}
    ${r.arquetipo ? `<span class="text-xs ml-1" style="color:var(--text-3)">${escape(r.arquetipo)}</span>` : ""}`;
}

// Los nombres de campo del survey son la PREGUNTA COMPLETA (párrafos enteros
// en el form nuevo). Para la tabla se recorta a su última «¿…?» — o a la
// última frase — y el texto completo viaja en el tooltip.
function preguntaCorta(campo) {
  const t = (campo || "").trim();
  if (t.length <= 70) return t;
  const qs = t.match(/¿[^?]*\?/g);
  let corta = qs ? qs[qs.length - 1] : (t.split(/\.\s+/).filter(Boolean).pop() || t);
  corta = corta.trim();
  return corta.length > 90 ? corta.slice(0, 89) + "…" : corta;
}

function detalle(c, sig, otras, esClosers) {
  const kv = (k, v, kTitle) => `<div class="flex gap-2 text-sm mb-1"><span class="shrink-0" style="color:var(--text-3);width:9rem"${kTitle ? ` title="${escape(kTitle)}"` : ""}>${escape(k)}</span><span style="min-width:0;overflow-wrap:anywhere">${v}</span></div>`;
  const l = c.lead;
  const preguntas = c.survey.filter((x) => x.tipo !== "atribucion");
  const atribucion = c.survey.filter((x) => x.tipo === "atribucion");
  // Cada pregunta en su propia fila (fuente pequeña, gris) con la respuesta
  // debajo — pedido de Santiago 2026-09-03: el par etiqueta-al-lado quedaba
  // apretado con enunciados largos.
  const survey = preguntas.length
    ? preguntas.map((x) => `<div class="mb-2">
        <p class="text-xs mb-0.5" style="color:var(--text-3)" title="${escape(x.campo)}">${escape(preguntaCorta(x.campo))}</p>
        <p class="text-sm" style="min-width:0;overflow-wrap:anywhere;color:var(--text-1)">${
          x.clave
            ? `<b>${escape(x.valor)}</b> <span class="badge" style="color:${TONE.brand}" title="esta respuesta define la banda A/B/C">banda</span>`
            : escape(x.valor)
        }</p>
      </div>`).join("")
    : `<p class="text-sm italic" style="color:var(--text-3)">Sin respuestas del survey.</p>`;
  const atrib = atribucion.length
    ? `<p class="text-xs font-bold uppercase mt-3 mb-1" style="color:var(--text-3)">Atribución</p>
       <div class="text-xs" style="color:var(--text-3)">${atribucion.map((x) => `<div class="flex gap-2"><span class="shrink-0" style="width:9rem">${escape(x.campo)}</span><span style="min-width:0;overflow-wrap:anywhere">${escape(x.valor.length > 70 ? x.valor.slice(0, 69) + "…" : x.valor)}</span></div>`).join("")}</div>`
    : "";
  const rep = c.reporte
    ? ["budget", "authority", "need", "timeline"].map((k) => kv(k, `<span class="tabular-nums">${c.reporte.bant[k] == null ? "—" : escape(String(c.reporte.bant[k]))}</span>${(c.reporte.baja_confianza || []).includes(k) ? " ⚠" : ""}`)).join("")
      + kv("arquetipo", escape(c.reporte.arquetipo || "—"))
      + kv("reporte", `<a class="underline" href="/u/reporte-llamada?meeting=${escape(c.reporte.meeting_id8)}">ver reporte (${escape(c.reporte.fuente)})</a>`)
    : `<p class="text-sm italic" style="color:var(--text-3)">Sin reporte.</p>`;
  const venta = c.venta ? kv("plan", `${escape(c.venta.plan_id8)} · $${escape(String(c.venta.monto ?? "—"))} · ${escape(String(c.venta.cuotas ?? "—"))} cuotas · ${escape(c.venta.creado)}`) : "";
  const hist = c.historial.llamadas_previas
    ? kv("llamadas previas", `${c.historial.llamadas_previas} · última ${escape(c.historial.ultima || "—")}${c.historial.bant_previo != null ? ` · BANT ${escape(String(c.historial.bant_previo))}` : ""}`)
    : kv("llamadas previas", "ninguna");
  const dup = otras && otras.length
    ? kv("otras citas del lead", escape(otras.map((o) => `${o.fecha === c.fecha ? "" : o.fecha + " "}${o.hora} (${ES_GHL[o.estado_ghl] || o.estado_ghl})`).join(" · ")))
    : "";
  const [estTxt, estTone] = ES_ESTADO[c.estado] || [c.estado, "muted"];
  const bandaHdr = !c.pasada && c.banda ? badge(c.banda.letra, BANDA_TONE[c.banda.letra], `${c.banda.presupuesto || "sin presupuesto"} · ${c.banda.disposicion || "sin disposición"}`) : "";
  const seccion = (t) => `<p class="text-xs font-bold uppercase mt-4 mb-1" style="color:var(--text-2)">${escape(t)}</p>`;
  return `<div data-show="$${sig}=='${escape(c.appointment_id)}'" style="display:none">
    <div class="flex items-start justify-between gap-2 mb-1">
      <div>
        <p class="font-bold" style="color:var(--text-1)">${escape(c.lead.nombre || "—")}</p>
        <p class="text-xs" style="color:var(--text-3)">${escape(c.fecha)} · ${escape(c.hora)}${c.fin ? "–" + escape(c.fin) : ""} · ${escape(esClosers ? "closer" : "setter")}: ${escape(c.asignado.nombre || "—")}</p>
      </div>
      <div class="flex items-center gap-1">${bandaHdr} ${c.estado_ghl === "cancelled" ? badge("Cancelada", "muted") : badge(estTxt, estTone)}</div>
    </div>
    ${c.calendario === "funnel" && c.cita_closer ? `<p class="text-xs mb-1" style="color:${TONE.pos}">→ cita con closer: ${escape(c.cita_closer.fecha)} ${escape(c.cita_closer.hora)}${c.cita_closer.closer ? " · " + escape(c.cita_closer.closer) : ""}</p>` : ""}
    ${seccion("Survey")}${survey}${atrib}
    ${seccion("Reporte de la llamada")}${rep}${venta}
    ${seccion("Datos del lead")}
    ${kv("correo", escape(l.email || "—"))}${kv("teléfono", escape(l.telefono || "—"))}${kv("formulario", escape(l.formulario || "—"))}
    ${kv("origen", escape([l.sesion, l.campana].filter(Boolean).join(" · ") || "—"))}${kv("tags", escape((l.tags || []).join(", ") || "—"))}
    ${kv("datos del lead", escape(FUENTE_LEAD[l.fuente] || l.fuente || "—"))}
    ${kv("etapa CRM", escape(c.etapa_crm || "— (espejo)"))}
    ${hist}${dup}${kv("cita GHL", escape(c.appointment_id))}${c.meeting ? kv("llamada", escape(c.meeting.id8)) : ""}
  </div>`;
}

// El SLIDE-OVER (decisión 2026-09-03): el detalle no interrumpe la lista — se
// desliza desde la derecha manteniendo la agenda visible (el idioma
// master-detail de la casa, en versión autosuficiente: los datos van embebidos
// porque el publicador v1 no monta /c/). Clic en otra fila = cambia el
// contenido; ✕ o re-clic en la misma fila = cierra.
function panelDetalle(citas, sig) {
  const porLane = {};
  for (const c of citas) {
    const k = `${c.calendario}|${c.contact_id || c.appointment_id}`;
    (porLane[k] = porLane[k] || []).push(c);
  }
  const entradas = citas.map((c) => {
    const otras = (porLane[`${c.calendario}|${c.contact_id || c.appointment_id}`] || []).filter((o) => o.appointment_id !== c.appointment_id);
    return detalle(c, sig, otras, c.calendario === "closers");
  }).join("");
  return `<aside id="as-panel" data-class:is-open="$${sig}!=''" aria-label="Detalle del lead">
    <div class="flex justify-end"><button class="btn" data-on:click="$${sig}=''" title="cerrar">✕</button></div>
    ${entradas}
  </aside>`;
}

function fila(c, sig, esClosers, otras) {
  const cancel = c.estado_ghl === "cancelled";
  const dim = cancel ? ` style="color:var(--text-3)"` : "";
  const quien = c.asignado.nombre ? escape(c.asignado.nombre) : "—";
  const quienCell = esClosers
    ? (c.sin_closer ? `${quien} ${badge("sin closer", "cau", "la cita quedó en manos de un setter o de nadie — asignar el closer en GHL")}` : quien)
    : (c.sin_asignar ? badge("sin asignar", "cau", "GHL no tiene a nadie asignado a esta cita") : quien);
  // Solo el calendario de VENTA lleva Meet (el Cerebro lo crea al agendar,
  // bash/agenda/entrante.sh); en el funnel la columna ni existe (2026-09-03) —
  // la confirmación de entrada no lleva Meet por diseño.
  const meetCell = !esClosers ? "" : `<td>${
    c.meeting && c.meeting.meet_url
      ? `<a class="underline" href="${escape(c.meeting.meet_url)}" target="_blank" rel="noopener">Meet</a>`
      : !c.sin_meet ? "—"
      : badge("sin Meet", "neg", "el Cerebro crea el Meet al agendar; esta cita quedó sin él — el agendamiento falló para ella")
  }</td>`;
  const [estTxt, estTone] = ES_ESTADO[c.estado] || [c.estado, "muted"];
  const ocurrio = c.pasada ? [c.ocurrio.transcript ? "transcript" : null, c.ocurrio.grabacion ? "grabación" : null].filter(Boolean).join(" · ") || "—" : "";
  const bandaCell = !c.pasada && c.banda ? badge(c.banda.letra, BANDA_TONE[c.banda.letra], `${c.banda.presupuesto || "sin presupuesto"} · ${c.banda.disposicion || "sin disposición"}`) : "";
  const anunciada = c.pasada ? `<span style="color:var(--text-3)" title="pendiente de conectar al grupo ONLY CLOSERS">—</span>` : "";
  // «Cita closer» tampoco va en la tabla del funnel (2026-09-03): el cruce
  // funnel→closers vive en el detalle del slide-over.
  const col6 = esClosers
    ? `<td class="text-xs">${c.etapa_crm ? escape(c.etapa_crm) : `<span style="color:var(--text-3)">— (espejo)</span>`}</td>`
    : "";
  const ultimas = c.pasada
    ? `<td>${escape(ocurrio)}</td><td>${bantCell(c.reporte)}</td><td>${c.venta ? badge("venta", "pos") : "—"}</td><td>${anunciada}</td>`
    : `<td>${bandaCell}</td><td colspan="3"></td>`;
  const id = escape(c.appointment_id);
  const dup = otras && otras.length ? ` <span class="badge" style="color:${TONE.muted}" title="el mismo lead tiene ${otras.length + 1} citas — ver detalle">×${otras.length + 1}</span>` : "";
  return `<tr${dim}${cancel ? ` data-show="$asCanc"` : ""} class="cursor-pointer" data-on:click="$${sig} = $${sig}=='${id}' ? '' : '${id}'">
    <td class="tabular-nums whitespace-nowrap">${escape(c.hora)}</td>
    <td class="font-medium">${escape(c.lead.nombre || "—")}${dup}</td>
    <td>${quienCell}</td>
    ${meetCell}
    <td>${cancel ? badge("Cancelada", "muted") : `${badge(ES_GHL[c.estado_ghl] || c.estado_ghl || "—", "brand")} ${badge(estTxt, estTone)}`}</td>
    ${col6}
    ${ultimas}
  </tr>`;
}

// Duplicados del mismo lead (funnel: el widget deja re-agendas): una fila por
// lead con ×N; las demás citas del grupo viajan al detalle.
function agrupar(citas) {
  const grupos = new Map();
  const orden = [];
  for (const c of citas) {
    const clave = c.contact_id || c.appointment_id;
    if (!grupos.has(clave)) { grupos.set(clave, []); orden.push(clave); }
    grupos.get(clave).push(c);
  }
  // El representante del grupo es la primera cita VIVA (si la hay): con las
  // canceladas ocultas por defecto, un rep cancelado escondería sus re-agendas vivas.
  return orden.map((k) => {
    const g = grupos.get(k);
    const rep = g.find((c) => c.estado_ghl !== "cancelled") || g[0];
    return { rep, otras: g.filter((c) => c !== rep) };
  });
}

function tabla(citas, sig, esClosers, pasadas, vacio, opts = {}) {
  if (!citas.length) return `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)">${escape(vacio)}</p>`;
  // El funnel va sin «Meet» ni «Cita closer» (2026-09-03): la entrada no lleva
  // Meet por diseño y el cruce con el closer vive en el slide-over.
  const th = esClosers
    ? (pasadas
        ? ["Hora", "Lead", "Closer", "Meet", "Estado", "Etapa CRM", "Ocurrió", "BANT", "Venta", "Anunciada"]
        : ["Hora", "Lead", "Closer", "Meet", "Estado", "Etapa CRM", "Banda", "", "", ""])
    : (pasadas
        ? ["Hora", "Lead", "Setter", "Estado", "Ocurrió", "BANT", "Venta", "Anunciada"]
        : ["Hora", "Lead", "Setter", "Estado", "Banda", "", "", ""]);
  const filas = agrupar(citas).map((g) => fila(g.rep, sig, esClosers, g.otras)).join("");
  return `<div class="table-wrap"><div class="table-scroll"><table class="tbl">
    <thead><tr>${th.map((h) => `<th>${escape(h)}</th>`).join("")}</tr></thead>
    <tbody>${filas}</tbody></table></div></div>`;
}

function bloqueDia(citas, sig, esClosers, conTitulo, opts = {}) {
  const prox = citas.filter((c) => !c.pasada);
  const pas = citas.filter((c) => c.pasada).slice().reverse();
  const head = conTitulo ? section(diaLabel(citas[0].fecha), `${citas.length} citas`, true) : "";
  return `${head}
    ${section("Por venir", prox.length ? `${prox.length} citas` : "", true)}
    ${tabla(prox, sig, esClosers, false, "Nada por venir.", opts)}
    ${section("Ya pasaron", pas.length ? `${pas.length} citas · la más reciente primero` : "", true)}
    ${tabla(pas, sig, esClosers, true, "Ninguna todavía.", opts)}`;
}

function carril(titulo, hint, citas, k, sig, esClosers, semana, opts = {}) {
  // En closers no van «Citas» ni «Confirmadas», y un card solo aparece si
  // tiene valor (pedido 2026-09-03) — la fila señala, no inventaría ceros.
  const kpisDefs = esClosers
    ? [
      { key: "sin_closer", label: "Sin closer", fmt: "int", tone: "cau", title: "en manos de un setter o de nadie — asignar el closer en GHL" },
      { key: "sin_meet", label: "Sin Meet", fmt: "int", tone: "neg", title: "el Cerebro crea el Meet al agendar; una cita de venta sin Meet = el agendamiento falló para ella" },
      { key: "analizadas", label: "Analizadas", fmt: "int", tone: "pos", title: "pasadas con reporte BANT vigente" },
      { key: "ventas", label: "Ventas", fmt: "int", tone: "pos", title: "plan de pago activo creado desde la cita" },
      { key: "sin_rastro", label: "Sin rastro", fmt: "int", tone: "neg", title: "pasadas sin grabación, transcript ni plan" },
      { key: "canceladas", label: "Canceladas", fmt: "int", tone: "muted", title: "ocultas de la lista por defecto",
        footHtml: `<span class="cursor-pointer underline" data-on:click="$asCanc = !$asCanc"><span data-show="!$asCanc">Ver</span><span data-show="$asCanc">Ocultar</span></span>` },
    ].filter((d) => k[d.key])
    : [
      { key: "citas", label: "Citas", fmt: "int", tone: "brand", title: "citas del widget, todos los estados (re-agendas incluidas)" },
      { key: "leads", label: "Leads", fmt: "int", tone: "brand", title: "personas distintas (las re-agendas se agrupan)" },
      { key: "banda_a", label: "Banda A", fmt: "int", tone: "pos", title: "declara ≥ $1.500 y está listo para tomar acción — se confirma primero" },
      { key: "agendo_closer", label: "Agendó closer", fmt: "int", tone: "pos", title: "leads del funnel que ya tienen cita en la agenda de closers" },
      { key: "sin_asignar", label: "Sin asignar", fmt: "int", tone: k.sin_asignar ? "cau" : "muted", title: "GHL no tiene a nadie asignado" },
      { key: "canceladas", label: "Canceladas", fmt: "int", tone: "muted", title: "ocultas de la lista por defecto",
        footHtml: k.canceladas ? `<span class="cursor-pointer underline" data-on:click="$asCanc = !$asCanc"><span data-show="!$asCanc">Ver</span><span data-show="$asCanc">Ocultar</span></span>` : "" },
      { key: "sin_rastro", label: "Sin rastro", fmt: "int", tone: k.sin_rastro ? "neg" : "muted", title: "pasadas sin grabación, transcript ni plan" },
      { key: "ventas", label: "Ventas", fmt: "int", tone: "pos" },
    ];
  let cuerpo;
  if (!citas.length) {
    cuerpo = `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)">Sin citas en la ventana.</p>`;
  } else if (!semana) {
    cuerpo = bloqueDia(citas, sig, esClosers, false, opts);
  } else {
    const porDia = new Map();
    for (const c of citas) {
      if (!porDia.has(c.fecha)) porDia.set(c.fecha, []);
      porDia.get(c.fecha).push(c);
    }
    cuerpo = [...porDia.keys()].sort().map((f) => bloqueDia(porDia.get(f), sig, esClosers, true, opts)).join("");
  }
  return `${section(titulo, hint)}
    ${kpisDefs.length ? cards(kpisDefs, k, { cols: kpisDefs.length }) : ""}
    ${cuerpo}`;
}

function renderObjeto(ui, d) {
  const v = d.ventana;
  const sig = "asSel";
  const citaIni = String((ui.params || {}).cita || "").replace(/[^A-Za-z0-9_-]/g, "");
  const semana = v.vista === "semana";
  const paso = semana ? 7 : 1;
  const base = `/u/${escape(ui.id)}?vista=${escape(v.vista)}&fecha=`;
  const reget = `@get('/ui/${escape(ui.id)}?carga=1&vista='+$asVista+'&fecha='+$asFecha)`;
  const nav = `<div class="flex flex-wrap items-center gap-3" data-signals="{asVista:'${escape(v.vista)}',asFecha:'${escape(v.fecha)}',loadingas:false}">
    <a class="btn" href="${base}${sumarDias(v.fecha, -paso)}">←</a>
    <input type="date" data-bind="asFecha" data-on:change="${reget}" data-indicator:loadingas class="input w-auto" />
    <a class="btn" href="${base}${sumarDias(v.fecha, paso)}">→</a>
    ${selectCtl("asVista", v.vista, [["dia", "Día"], ["semana", "Semana"]], reget, "loadingas")}
    <span class="text-sm" style="color:var(--text-3)">${escape(d.proyecto || "")} · ${semana ? `${escape(diaLabel(v.desde))} → ${escape(diaLabel(v.hasta))}` : escape(diaLabel(v.fecha))} · ahora ${escape(v.ahora.slice(11))}</span>
  </div>`;

  const avisos = [];
  if (d.fuente.webhook === "error") avisos.push(`<div class="alert alert-cau mt-3"><b>El agendamiento está reportando errores.</b> Citas de venta nuevas pueden quedar sin Meet — revisar los agendamientos entrantes con el Cerebro.</div>`);
  if (d.fuente.ghl !== "ok") avisos.push(`<div class="alert alert-neg mt-3">GHL no respondió — la agenda no se puede listar desde la base (GHL manda). ${escape(d.fuente.detalle || "")}</div>`);
  if (d.fuente.db === "error") avisos.push(`<div class="alert alert-cau mt-3">La base no respondió: las citas salen sin Meet, BANT ni plan.</div>`);
  // La línea de calendarios/contactos tampoco se pinta (subtítulos fuera, 2026-09-03).
  const closers = d.citas.filter((c) => c.calendario === "closers");
  const funnel = d.citas.filter((c) => c.calendario !== "closers");
  const hayClosers = (d.calendarios || []).some((c) => c.tipo === "closers");
  const opts = {};
  const carrilClosers = hayClosers
    ? carril("Agenda de closers", "la que cuadra el setter — «Aplicación»", closers, d.kpis.closers, sig, true, semana, opts)
    : `${section("Agenda de closers", "")}<div class="alert alert-cau">No se encontró el calendario de closers («Aplicación…») en GHL.</div>`;

  // «solo_en_sistema» y «sin_instrumentar» viajan en el objeto pero no se
  // pintan (pedido 2026-09-03): el drift lo vigila la reconciliación, no el setter.

  // id="pane" NO es decorativo: el SSE parchea por id.
  return `<section id="pane" class="flex-1 relative overflow-auto p-6" data-signals="{${sig}:'${citaIni}',asCanc:false}">
    <style>
      #as-loading{opacity:0;transition:opacity .2s ease}#as-loading.on{opacity:1}
      #as-panel{position:fixed;top:0;right:0;bottom:0;width:min(38rem,100vw);z-index:40;
        background:var(--surface-1);border-left:1px solid var(--border-1);
        box-shadow:-8px 0 24px rgb(0 0 0 / .08);padding:1rem 1.25rem;overflow-y:auto;
        transform:translateX(105%);transition:transform .3s ease-in-out}
      #as-panel.is-open{transform:translateX(0)}
    </style>
    <div id="as-loading" data-class:on="$loadingas" class="pointer-events-none absolute inset-0 z-10 flex items-start justify-center pt-16 bg-white/50">
      <div class="w-7 h-7 rounded-full border-2 border-slate-300 border-t-indigo-600 animate-spin"></div>
    </div>
    <div class="max-w-6xl mx-auto">
      ${nav}
      ${avisos.join("")}
      ${carrilClosers}
      ${carril("Funnel — llamadas del setter", "el widget agenda aquí; las toma un setter", funnel, d.kpis.funnel, sig, false, semana, opts)}
    </div>
    ${panelDetalle(d.citas, sig)}
  </section>`;
}

// El cascarón instantáneo del primer load: la fuente consulta GHL + Postgres y
// tarda varios segundos, así que /u/ responde esto al tiro y un data-init pide
// la agenda completa por SSE (`?carga=1` — mismo patrón que informe `?vivo=`).
function cascaron(ui, p) {
  const qs = ["carga=1"];
  for (const k of ["vista", "fecha", "cita", "project"]) {
    if (p[k]) qs.push(`${k}=${encodeURIComponent(String(p[k]))}`);
  }
  return `<section id="pane" class="flex-1 relative overflow-auto p-6" data-init="@get('/ui/${escape(ui.id)}?${escape(qs.join("&"))}')">
    <style>@keyframes as-barra{0%{transform:translateX(-100%)}100%{transform:translateX(250%)}}</style>
    <div class="max-w-6xl mx-auto">
      <div class="flex flex-col items-center justify-center pt-24 gap-4">
        <div class="w-64 h-1.5 rounded-full overflow-hidden" style="background:var(--surface-3)">
          <div class="h-full w-2/5 rounded-full" style="background:var(--brand-solid);animation:as-barra 1.2s ease-in-out infinite"></div>
        </div>
        <p class="text-sm" style="color:var(--text-3)">Cargando la agenda — GHL y la base en vivo, tarda unos segundos…</p>
      </div>
    </div>
  </section>`;
}

function render(ui) {
  const p = Object.assign({}, ui.params || {});
  if (!p.carga) return cascaron(ui, p);
  const params = { project: p.project, fecha: p.fecha, vista: p.vista, calendar_closers: p.calendar_closers };
  let d, err;
  try {
    d = fetchSource(ui.source || "agenda_setter", params).rows[0];
  } catch (e) {
    err = e.message;
  }
  if (err || !d) {
    return `<section id="pane" class="flex-1 p-6 overflow-auto"><div class="alert alert-neg">No se pudo cargar la agenda: ${escape(err || "sin datos")}</div></section>`;
  }
  return renderObjeto(ui, d);
}

module.exports = {
  id: "agenda-setter",
  // `cita` es presentación pura (preselecciona el slide-over; buildArgs la ignora)
  manifest: { consumes: "object", overridable: ["fecha", "vista", "project", "cita", "carga"] },
  render,
  renderObjeto,
};

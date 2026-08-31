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

function section(title, hint, sub) {
  const tag = sub ? "h3" : "h2";
  return `<div class="flex items-baseline gap-3 ${sub ? "mt-5" : "mt-8"} mb-3 flex-wrap">
    <${tag} class="${sub ? "text-xs" : "text-sm"} font-bold uppercase tracking-wider" style="color:var(--text-2);letter-spacing:var(--tr-micro)">${escape(title)}</${tag}>
    ${hint ? `<span class="text-xs" style="color:var(--text-3)">${escape(hint)}</span>` : ""}
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

function cruceCell(c) {
  if (!c.cita_closer) return `<span style="color:var(--text-3)">—</span>`;
  const x = c.cita_closer;
  return `<span style="color:${TONE.pos}">→ ${escape(x.fecha)} ${escape(x.hora)}${x.closer ? " · " + escape(x.closer) : ""}</span>`;
}

function detalle(c, sig, otras) {
  const kv = (k, v) => `<div class="flex gap-2 text-sm"><span style="color:var(--text-3);min-width:9rem">${escape(k)}</span><span>${v}</span></div>`;
  const l = c.lead;
  const survey = c.survey.length
    ? c.survey.map((s) => kv(s.campo, escape(s.valor))).join("")
    : `<p class="text-sm italic" style="color:var(--text-3)">Sin respuestas del survey.</p>`;
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
  return `<tr data-show="$${sig}=='${escape(c.appointment_id)}'" style="display:none"><td colspan="10" style="background:var(--surface-2)">
    <div class="grid gap-6 p-3" style="grid-template-columns:repeat(auto-fit,minmax(18rem,1fr))">
      <div>${kv("correo", escape(l.email || "—"))}${kv("teléfono", escape(l.telefono || "—"))}${kv("formulario", escape(l.formulario || "—"))}
           ${kv("origen", escape([l.sesion, l.campana].filter(Boolean).join(" · ") || "—"))}${kv("tags", escape((l.tags || []).join(", ") || "—"))}
           ${kv("datos del lead", escape(FUENTE_LEAD[l.fuente] || l.fuente || "—"))}
           ${kv("etapa CRM", escape(c.etapa_crm || "— (espejo)"))}
           ${hist}${dup}${kv("cita GHL", escape(c.appointment_id))}${c.meeting ? kv("llamada", escape(c.meeting.id8)) : ""}</div>
      <div><p class="text-xs font-bold uppercase mb-1" style="color:var(--text-2)">Survey</p>${survey}</div>
      <div><p class="text-xs font-bold uppercase mb-1" style="color:var(--text-2)">Reporte de la llamada</p>${rep}${venta}</div>
    </div></td></tr>`;
}

function fila(c, sig, esClosers, otras, migracion) {
  const cancel = c.estado_ghl === "cancelled";
  const dim = cancel ? ` style="color:var(--text-3)"` : "";
  const quien = c.asignado.nombre ? escape(c.asignado.nombre) : "—";
  const quienCell = esClosers
    ? (c.sin_closer ? `${quien} ${badge("sin closer", "cau", "la cita quedó en manos de un setter o de nadie — asignar el closer en GHL")}` : quien)
    : (c.sin_asignar ? badge("sin asignar", "cau", "GHL no tiene a nadie asignado a esta cita") : quien);
  const meet = c.meeting && c.meeting.meet_url
    ? `<a class="underline" href="${escape(c.meeting.meet_url)}" target="_blank" rel="noopener">Meet</a>`
    : !c.sin_meet ? "—"
    : migracion ? badge("Meet pendiente", "cau", "agendamiento en migración: desde el 26-ago Marketico no crea Meets; el Cerebro los pedirá a demanda")
    : badge("sin Meet", "neg", "no pasó por el webhook: no habrá grabación ni análisis");
  const [estTxt, estTone] = ES_ESTADO[c.estado] || [c.estado, "muted"];
  const ocurrio = c.pasada ? [c.ocurrio.transcript ? "transcript" : null, c.ocurrio.grabacion ? "grabación" : null].filter(Boolean).join(" · ") || "—" : "";
  const bandaCell = !c.pasada && c.banda ? badge(c.banda.letra, BANDA_TONE[c.banda.letra], `${c.banda.presupuesto || "sin presupuesto"} · ${c.banda.disposicion || "sin disposición"}`) : "";
  const anunciada = c.pasada ? `<span style="color:var(--text-3)" title="pendiente de conectar al grupo ONLY CLOSERS">—</span>` : "";
  const col6 = esClosers
    ? `<td class="text-xs">${c.etapa_crm ? escape(c.etapa_crm) : `<span style="color:var(--text-3)">— (espejo)</span>`}</td>`
    : `<td class="text-xs">${cruceCell(c)}</td>`;
  const ultimas = c.pasada
    ? `<td>${escape(ocurrio)}</td><td>${bantCell(c.reporte)}</td><td>${c.venta ? badge("venta", "pos") : "—"}</td><td>${anunciada}</td>`
    : `<td>${bandaCell}</td><td colspan="3"></td>`;
  const id = escape(c.appointment_id);
  const dup = otras && otras.length ? ` <span class="badge" style="color:${TONE.muted}" title="el mismo lead tiene ${otras.length + 1} citas — ver detalle">×${otras.length + 1}</span>` : "";
  return `<tr${dim} class="cursor-pointer" data-on:click="$${sig} = $${sig}=='${id}' ? '' : '${id}'">
    <td class="tabular-nums whitespace-nowrap">${escape(c.hora)}</td>
    <td class="font-medium">${escape(c.lead.nombre || "—")}${dup}</td>
    <td>${quienCell}</td>
    <td>${meet}</td>
    <td>${badge(ES_GHL[c.estado_ghl] || c.estado_ghl || "—", cancel ? "muted" : "brand")} ${badge(estTxt, estTone)}</td>
    ${col6}
    ${ultimas}
  </tr>${detalle(c, sig, otras)}`;
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
  return orden.map((k) => { const g = grupos.get(k); return { rep: g[0], otras: g.slice(1) }; });
}

function tabla(citas, sig, esClosers, pasadas, vacio, opts = {}) {
  if (!citas.length) return `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)">${escape(vacio)}</p>`;
  const col6 = esClosers ? "Etapa CRM" : "Cita closer";
  const quien = esClosers ? "Closer" : "Setter";
  const th = pasadas
    ? ["Hora", "Lead", quien, "Meet", "Estado", col6, "Ocurrió", "BANT", "Venta", "Anunciada"]
    : ["Hora", "Lead", quien, "Meet", "Estado", col6, "Banda", "", "", ""];
  const filas = agrupar(citas).map((g) => fila(g.rep, sig, esClosers, g.otras, opts.migracion)).join("");
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
  const kpisDefs = esClosers
    ? [
      { key: "citas", label: "Citas", fmt: "int", tone: "brand" },
      { key: "confirmadas", label: "Confirmadas", fmt: "int", tone: "pos" },
      { key: "sin_closer", label: "Sin closer", fmt: "int", tone: k.sin_closer ? "cau" : "muted", title: "en manos de un setter o de nadie — asignar el closer en GHL" },
      { key: "sin_meet", label: opts.migracion ? "Meet pendiente" : "Sin Meet", fmt: "int", tone: k.sin_meet ? (opts.migracion ? "cau" : "neg") : "muted", title: opts.migracion ? "agendamiento en migración: Marketico no crea Meets desde el 26-ago" : "no pasaron por el webhook: no habrá grabación ni análisis" },
      { key: "analizadas", label: "Analizadas", fmt: "int", tone: "pos", title: "pasadas con reporte BANT vigente" },
      { key: "ventas", label: "Ventas", fmt: "int", tone: "pos", title: "plan de pago activo creado desde la cita" },
      { key: "sin_rastro", label: "Sin rastro", fmt: "int", tone: k.sin_rastro ? "neg" : "muted", title: "pasadas sin grabación, transcript ni plan" },
      { label: "Anunciadas", fmt: "int", value: null, muted: true, title: "pendiente de conectar al grupo ONLY CLOSERS" },
    ]
    : [
      { key: "citas", label: "Citas", fmt: "int", tone: "brand", title: "citas del widget, todos los estados (re-agendas incluidas)" },
      { key: "leads", label: "Leads", fmt: "int", tone: "brand", title: "personas distintas (las re-agendas se agrupan)" },
      { key: "banda_a", label: "Banda A", fmt: "int", tone: "pos", title: "declara ≥ $1.500 y está listo para tomar acción — se confirma primero" },
      { key: "agendo_closer", label: "Agendó closer", fmt: "int", tone: "pos", title: "leads del funnel que ya tienen cita en la agenda de closers" },
      { key: "sin_asignar", label: "Sin asignar", fmt: "int", tone: k.sin_asignar ? "cau" : "muted", title: "GHL no tiene a nadie asignado" },
      { key: "sin_meet", label: opts.migracion ? "Meet pendiente" : "Sin Meet", fmt: "int", tone: k.sin_meet ? (opts.migracion ? "cau" : "neg") : "muted", title: opts.migracion ? "agendamiento en migración: Marketico no crea Meets desde el 26-ago" : "no pasaron por el webhook" },
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
    ${cards(kpisDefs, k, { cols: 8 })}
    ${cuerpo}`;
}

function renderObjeto(ui, d) {
  const v = d.ventana;
  const sig = "asSel";
  const semana = v.vista === "semana";
  const paso = semana ? 7 : 1;
  const base = `/u/${escape(ui.id)}?vista=${escape(v.vista)}&fecha=`;
  const reget = `@get('/ui/${escape(ui.id)}?vista='+$asVista+'&fecha='+$asFecha)`;
  const nav = `<div class="flex flex-wrap items-center gap-3" data-signals="{asVista:'${escape(v.vista)}',asFecha:'${escape(v.fecha)}',loadingas:false}">
    <a class="btn" href="${base}${sumarDias(v.fecha, -paso)}">←</a>
    <input type="date" data-bind="asFecha" data-on:change="${reget}" data-indicator:loadingas class="input w-auto" />
    <a class="btn" href="${base}${sumarDias(v.fecha, paso)}">→</a>
    ${selectCtl("asVista", v.vista, [["dia", "Día"], ["semana", "Semana"]], reget, "loadingas")}
    <span class="text-sm" style="color:var(--text-3)">${escape(d.proyecto || "")} · ${semana ? `${escape(diaLabel(v.desde))} → ${escape(diaLabel(v.hasta))}` : escape(diaLabel(v.fecha))} · ahora ${escape(v.ahora.slice(11))}</span>
  </div>`;

  const migracion = d.fuente.webhook === "inhabilitado";
  const avisos = [];
  if (migracion) avisos.push(`<div class="alert alert-cau mt-3"><b>Agendamiento en migración.</b> Desde el 26-ago Marketico no crea Meets (webhook en modo ack): las citas nuevas no tendrán Meet, grabación ni análisis hasta que el Cerebro los pida a demanda. El registro de lo que GHL dispara sigue completo en intercepciones.</div>`);
  if (d.fuente.ghl !== "ok") avisos.push(`<div class="alert alert-neg mt-3">GHL no respondió — la agenda no se puede listar desde la base (GHL manda). ${escape(d.fuente.detalle || "")}</div>`);
  if (d.fuente.db === "error") avisos.push(`<div class="alert alert-cau mt-3">La base no respondió: las citas salen sin Meet, BANT ni plan.</div>`);
  const cals = (d.calendarios || []).map((c) => `${c.tipo === "closers" ? "closers" : "funnel"}: ${escape(c.nombre || c.id)} (${escape((c.miembros || []).join(", ") || "—")})`).join(" · ");
  const meta = `<p class="text-xs mt-2" style="color:var(--text-3)">${cals} · contactos en vivo ${d.fuente.contactos_en_vivo ?? 0} / espejo ${d.fuente.contactos_espejo ?? 0}</p>`;

  const closers = d.citas.filter((c) => c.calendario === "closers");
  const funnel = d.citas.filter((c) => c.calendario !== "closers");
  const hayClosers = (d.calendarios || []).some((c) => c.tipo === "closers");
  const opts = { migracion };
  const carrilClosers = hayClosers
    ? carril("Agenda de closers", "la que cuadra el setter — «Aplicación»", closers, d.kpis.closers, sig, true, semana, opts)
    : `${section("Agenda de closers", "")}<div class="alert alert-cau">No se encontró el calendario de closers («Aplicación…») en GHL.</div>`;

  const solo = d.solo_en_sistema.length
    ? `<div class="table-wrap"><div class="table-scroll"><table class="tbl"><thead><tr><th>Fecha</th><th>Hora</th><th>Lead</th><th>Closer</th><th>Llamada</th></tr></thead><tbody>
        ${d.solo_en_sistema.map((s) => `<tr><td>${escape(s.fecha)}</td><td class="tabular-nums">${escape(s.hora)}</td><td>${escape(s.lead || "—")}</td><td>${escape(s.closer || "—")}</td><td class="text-xs">${escape(s.id8)}</td></tr>`).join("")}
      </tbody></table></div></div>`
    : `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)">Ninguna — el sistema y GHL coinciden.</p>`;

  // id="pane" NO es decorativo: el SSE parchea por id.
  return `<section id="pane" class="flex-1 relative overflow-auto p-6" data-signals="{${sig}:''}">
    <style>#as-loading{opacity:0;transition:opacity .2s ease}#as-loading.on{opacity:1}</style>
    <div id="as-loading" data-class:on="$loadingas" class="pointer-events-none absolute inset-0 z-10 flex items-start justify-center pt-16 bg-white/50">
      <div class="w-7 h-7 rounded-full border-2 border-slate-300 border-t-indigo-600 animate-spin"></div>
    </div>
    <div class="max-w-6xl mx-auto">
      ${nav}${meta}
      ${avisos.join("")}
      ${carrilClosers}
      ${carril("Funnel — llamadas del setter", "el widget agenda aquí; las toma un setter", funnel, d.kpis.funnel, sig, false, semana, opts)}
      ${section("En el sistema, no en GHL", "llamadas agendadas en la base que los calendarios oficiales no tienen — para corregir la agenda")}
      ${solo}
      <ul class="text-xs mt-8 list-disc pl-5" style="color:var(--text-3)">${d.sin_instrumentar.map((s) => `<li>${escape(s)}</li>`).join("")}</ul>
    </div>
  </section>`;
}

function render(ui) {
  const p = Object.assign({}, ui.params || {});
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
  manifest: { consumes: "object", overridable: ["fecha", "vista", "project"] },
  render,
  renderObjeto,
};

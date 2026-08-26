// agenda-setter page — la agenda del setter (día / semana) desde el único
// objeto que emite bash/setters/agenda.sh. GHL manda: lo que se lista son las
// citas del calendario oficial; la base solo enriquece (Meet, BANT, plan).
//
// Dos secciones deliberadas, cortadas por la hora actual:
//   Por venir   cronológica, con la BANDA pre-llamada (A/B/C) — la capa de
//               operación de docs/lead-score.md §5, que el setter SÍ ve.
//   Ya pasaron  la más reciente primero, con el ESTADO POR CAPAS (ocurrió ·
//               analizada + BANT · venta) y «anunciada» en gris: promesa
//               visible, no medible aún (detector de anuncios, v2).
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

function section(title, hint) {
  return `<div class="flex items-baseline gap-3 mt-8 mb-3 flex-wrap">
    <h2 class="text-sm font-bold uppercase tracking-wider" style="color:var(--text-2);letter-spacing:var(--tr-micro)">${escape(title)}</h2>
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

function detalle(c, sig) {
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
  return `<tr data-show="$${sig}=='${escape(c.appointment_id)}'" style="display:none"><td colspan="10" style="background:var(--surface-2)">
    <div class="grid gap-6 p-3" style="grid-template-columns:repeat(auto-fit,minmax(18rem,1fr))">
      <div>${kv("correo", escape(l.email || "—"))}${kv("teléfono", escape(l.telefono || "—"))}${kv("formulario", escape(l.formulario || "—"))}
           ${kv("origen", escape([l.sesion, l.campana].filter(Boolean).join(" · ") || "—"))}${kv("tags", escape((l.tags || []).join(", ") || "—"))}
           ${kv("datos del lead", escape(FUENTE_LEAD[l.fuente] || l.fuente || "—"))}
           ${hist}${kv("cita GHL", escape(c.appointment_id))}${c.meeting ? kv("llamada", escape(c.meeting.id8)) : ""}</div>
      <div><p class="text-xs font-bold uppercase mb-1" style="color:var(--text-2)">Survey</p>${survey}</div>
      <div><p class="text-xs font-bold uppercase mb-1" style="color:var(--text-2)">Reporte de la llamada</p>${rep}${venta}</div>
    </div></td></tr>`;
}

function fila(c, sig) {
  const cancel = c.estado_ghl === "cancelled";
  const dim = cancel ? ` style="color:var(--text-3)"` : "";
  const closer = c.closer.nombre ? escape(c.closer.nombre) : "—";
  const closerCell = c.sin_closer ? `${closer} ${badge("sin closer", "cau", "la cita está asignada a un setter o a nadie")}` : closer;
  const meet = c.meeting && c.meeting.meet_url
    ? `<a class="underline" href="${escape(c.meeting.meet_url)}" target="_blank" rel="noopener">Meet</a>`
    : c.sin_meet ? badge("sin Meet", "neg", "no pasó por el webhook: no habrá grabación ni análisis") : "—";
  const etapa = c.etapa_crm ? `${escape(c.etapa_crm)}${c.etapa_no_confirmada ? " " + badge("≠ confirmada", "cau") : ""}` : `<span style="color:var(--text-3)">— (espejo)</span>`;
  const [estTxt, estTone] = ES_ESTADO[c.estado] || [c.estado, "muted"];
  const ocurrio = c.pasada ? [c.ocurrio.transcript ? "transcript" : null, c.ocurrio.grabacion ? "grabación" : null].filter(Boolean).join(" · ") || "—" : "";
  const bandaCell = !c.pasada && c.banda ? badge(c.banda.letra, BANDA_TONE[c.banda.letra], `${c.banda.presupuesto || "sin presupuesto"} · ${c.banda.disposicion || "sin disposición"}`) : "";
  const anunciada = c.pasada ? `<span style="color:var(--text-3)" title="pendiente de conectar al grupo ONLY CLOSERS">—</span>` : "";
  const ultimas = c.pasada
    ? `<td>${escape(ocurrio)}</td><td>${bantCell(c.reporte)}</td><td>${c.venta ? badge("venta", "pos") : "—"}</td><td>${anunciada}</td>`
    : `<td>${bandaCell}</td><td colspan="3"></td>`;
  const id = escape(c.appointment_id);
  return `<tr${dim} class="cursor-pointer" data-on:click="$${sig} = $${sig}=='${id}' ? '' : '${id}'">
    <td class="tabular-nums whitespace-nowrap">${escape(c.hora)}</td>
    <td class="font-medium">${escape(c.lead.nombre || "—")}</td>
    <td>${closerCell}</td>
    <td>${meet}</td>
    <td>${badge(ES_GHL[c.estado_ghl] || c.estado_ghl || "—", cancel ? "muted" : "brand")} ${badge(estTxt, estTone)}</td>
    <td class="text-xs">${etapa}</td>
    ${ultimas}
  </tr>${detalle(c, sig)}`;
}

function tabla(citas, sig, pasadas, vacio) {
  if (!citas.length) return `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)">${escape(vacio)}</p>`;
  const th = pasadas
    ? ["Hora", "Lead", "Closer", "Meet", "Estado", "Etapa CRM", "Ocurrió", "BANT", "Venta", "Anunciada"]
    : ["Hora", "Lead", "Closer", "Meet", "Estado", "Etapa CRM", "Banda", "", "", ""];
  return `<div class="table-wrap"><div class="table-scroll"><table class="tbl">
    <thead><tr>${th.map((h) => `<th>${escape(h)}</th>`).join("")}</tr></thead>
    <tbody>${citas.map((c) => fila(c, sig)).join("")}</tbody></table></div></div>`;
}

function bloqueDia(citas, sig, conTitulo) {
  const prox = citas.filter((c) => !c.pasada);
  const pas = citas.filter((c) => c.pasada).slice().reverse();
  const head = conTitulo ? section(diaLabel(citas[0].fecha), `${citas.length} citas`) : "";
  return `${head}
    ${section("Por venir", prox.length ? `${prox.length} citas` : "")}
    ${tabla(prox, sig, false, "Nada por venir.")}
    ${section("Ya pasaron", pas.length ? `${pas.length} citas · la más reciente primero` : "")}
    ${tabla(pas, sig, true, "Ninguna todavía.")}`;
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

  const avisos = [];
  if (d.fuente.ghl !== "ok") avisos.push(`<div class="alert alert-neg mt-3">GHL no respondió — la agenda no se puede listar desde la base (GHL manda). ${escape(d.fuente.detalle || "")}</div>`);
  if (d.fuente.db === "error") avisos.push(`<div class="alert alert-cau mt-3">La base no respondió: las citas salen sin Meet, BANT ni plan.</div>`);
  const cals = (d.calendarios || []).map((c) => `${escape(c.nombre || c.id)} — setters: ${escape((c.setters || []).join(", ") || "—")}`).join(" · ");
  const meta = `<p class="text-xs mt-2" style="color:var(--text-3)">${cals} · contactos en vivo ${d.fuente.contactos_en_vivo ?? 0} / espejo ${d.fuente.contactos_espejo ?? 0}</p>`;

  const k = d.kpis;
  const kpisProx = cards([
    { key: "citas", label: "Citas", fmt: "int", tone: "brand", title: "citas en GHL en la ventana, todos los estados" },
    { key: "confirmadas", label: "Confirmadas", fmt: "int", tone: "pos" },
    { key: "banda_a", label: "Banda A", fmt: "int", tone: "pos", title: "declara ≥ $1.500 y está listo para tomar acción — se confirma primero" },
    { key: "sin_closer", label: "Sin closer", fmt: "int", tone: k.sin_closer ? "cau" : "muted", title: "asignadas a un setter o a nadie" },
    { key: "sin_meet", label: "Sin Meet", fmt: "int", tone: k.sin_meet ? "neg" : "muted", title: "no pasaron por el webhook: no habrá grabación ni análisis" },
    { key: "canceladas", label: "Canceladas", fmt: "int", tone: "muted" },
  ], k);
  const kpisPas = cards([
    { key: "pasadas", label: "Pasadas", fmt: "int", tone: "brand" },
    { key: "ocurrieron", label: "Ocurrieron", fmt: "int", tone: "pos", title: "transcript usable o grabación" },
    { key: "analizadas", label: "Analizadas", fmt: "int", tone: "pos", title: "con reporte BANT vigente" },
    { key: "ventas", label: "Ventas", fmt: "int", tone: "pos", title: "plan de pago activo creado desde la cita" },
    { key: "sin_rastro", label: "Sin rastro", fmt: "int", tone: k.sin_rastro ? "neg" : "muted", title: "ni grabación, ni transcript, ni plan — ¿qué pasó?" },
    { label: "Anunciadas", fmt: "int", value: null, muted: true, title: "pendiente de conectar al grupo ONLY CLOSERS" },
  ], k);

  let cuerpo;
  if (!d.citas.length) {
    cuerpo = `<p class="text-sm italic px-1 py-4" style="color:var(--text-3)">Sin citas en la ventana.</p>`;
  } else if (!semana) {
    cuerpo = bloqueDia(d.citas, sig, false);
  } else {
    const porDia = new Map();
    for (const c of d.citas) {
      if (!porDia.has(c.fecha)) porDia.set(c.fecha, []);
      porDia.get(c.fecha).push(c);
    }
    cuerpo = [...porDia.keys()].sort().map((f) => bloqueDia(porDia.get(f), sig, true)).join("");
  }

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
      <div class="mt-6">${kpisProx}</div>
      ${kpisPas}
      ${cuerpo}
      ${section("En el sistema, no en GHL", "llamadas agendadas en la base que el calendario oficial no tiene — para corregir la agenda")}
      ${solo}
      <ul class="text-xs mt-8 list-disc pl-5" style="color:var(--text-3)">${d.sin_instrumentar.map((s) => `<li>${escape(s)}</li>`).join("")}</ul>
    </div>
  </section>`;
}

function render(ui) {
  const p = Object.assign({}, ui.params || {});
  const params = { project: p.project, fecha: p.fecha, vista: p.vista };
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

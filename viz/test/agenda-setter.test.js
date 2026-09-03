const { test } = require("node:test");
const assert = require("node:assert");
const page = require("../pages/agenda-setter");

const D = {
  proyecto: "David Guerrero",
  calendarios: [{ id: "CAL1", nombre: "Calendario Premium Mastermind", tipo: "funnel", miembros: ["Cristian Buelvas", "Anthony Velásquez"] },
                { id: "CAL2", nombre: "Aplicación a Premium Mastermind", tipo: "closers", miembros: ["Carlos González"] }],
  ventana: { vista: "dia", fecha: "2026-08-26", desde: "2026-08-26", hasta: "2026-08-26", ahora: "2026-08-26T10:00" },
  fuente: { ghl: "ok", detalle: null, db: "ok", contactos_en_vivo: 2, contactos_espejo: 1 },
  kpis: { closers: { citas: 1, leads: 0, confirmadas: 0, canceladas: 1, banda_a: 0, sin_closer: 0, sin_asignar: 0, sin_meet: 0, agendo_closer: 0, pasadas: 0, ocurrieron: 0, analizadas: 0, ventas: 0, sin_rastro: 0 },
          funnel: { citas: 2, leads: 2, confirmadas: 2, canceladas: 0, banda_a: 1, sin_closer: 0, sin_asignar: 1, sin_meet: 2, agendo_closer: 1, pasadas: 0, ocurrieron: 0, analizadas: 0, ventas: 0, sin_rastro: 0 } },
  citas: [
    { appointment_id: "AP3", calendario: "closers", contact_id: "C3", fecha: "2026-08-26", hora: "08:00", fin: "08:20", estado_ghl: "cancelled", titulo: "Eva Ruiz - PM", creada_por: "booking_widget",
      pasada: true, estado: "cancelada", lead: { nombre: "Eva Ruiz", email: null, telefono: null, formulario: null, sesion: null, campana: null, tags: [], fuente: "titulo" },
      asignado: { nombre: "Carlos González", user_id: "u-1", ghl_user_id: "CLO1" }, sin_closer: false, sin_asignar: false, cita_closer: null,
      meeting: { id8: "aaaaaaaa", meet_url: "https://meet.google.com/aaa", status: "ended" }, sin_meet: false,
      etapa_crm: null, etapa_no_confirmada: true, banda: null, survey: [], historial: { llamadas_previas: 0, ultima: null, bant_previo: null },
      ocurrio: { transcript: true, grabacion: true }, reporte: { fuente: "cerebro", bant: { budget: 60, authority: 80, need: 70, timeline: 50, total: 65 }, baja_confianza: ["budget"], arquetipo: "Emocional", meeting_id8: "aaaaaaaa" },
      venta: null, anunciada: null },
    { appointment_id: "AP1", calendario: "funnel", contact_id: "C1", fecha: "2026-08-26", hora: "09:20", fin: "09:40", estado_ghl: "confirmed", titulo: "Ana Pérez - PM", creada_por: "booking_widget",
      pasada: false, estado: "proxima", lead: { nombre: "Ana Pérez", email: "ana@x.co", telefono: "+57 300", formulario: "Survey Mastermind", sesion: "Social media", campana: "Fly_test", tags: ["form mastermind"], fuente: "ghl" },
      asignado: { nombre: "Cristian Buelvas", user_id: "u-2", ghl_user_id: "SET1" }, sin_closer: false, sin_asignar: false, cita_closer: { fecha: "2026-08-26", hora: "16:00", closer: "Carlos González" }, meeting: null, sin_meet: true,
      etapa_crm: "LLAMADA CONFIRMADA", etapa_no_confirmada: false, banda: { letra: "A", presupuesto: "$1.500", disposicion: "Estoy listo para tomar acción e invertir" },
      survey: [
        { campo: "¿Tienes al menos $1.500 USD para invertir?", valor: "$1.500", tipo: "pregunta", clave: "presupuesto" },
        { campo: "Las expectativas son la base de una relación a largo plazo. Trabajamos con personas comprometidas. ¿En qué situación te encuentras actualmente con respecto a lograr la rentabilidad en el trading?", valor: "Estoy listo", tipo: "pregunta", clave: "disposicion" },
        { campo: "País", valor: "Colombia <b>x</b>", tipo: "pregunta", clave: null },
        { campo: "utm_campaign", valor: "AGOST_27_DC_TRAFICO_FRIO_OVERLAY - Copy", tipo: "atribucion", clave: null },
        { campo: "vtid", valor: "v3_360d68e4-879d-4ed1-819e-2594a1f0988a_6a2c3398f35e2cfc30b65f36_635_s-1", tipo: "atribucion", clave: null },
      ],
      historial: { llamadas_previas: 1, ultima: "2026-07-01", bant_previo: 55 }, ocurrio: { transcript: false, grabacion: false }, reporte: null, venta: null, anunciada: null },
    { appointment_id: "AP2", calendario: "funnel", contact_id: "C2", fecha: "2026-08-26", hora: "15:00", fin: "15:20", estado_ghl: "confirmed", titulo: "Luis Gil - PM", creada_por: "booking_widget",
      pasada: false, estado: "proxima", lead: { nombre: "Luis Gil", email: "luis@x.co", telefono: null, formulario: null, sesion: null, campana: null, tags: [], fuente: "espejo" },
      asignado: { nombre: null, user_id: null, ghl_user_id: null }, sin_closer: false, sin_asignar: true, cita_closer: null, meeting: null, sin_meet: true,
      etapa_crm: null, etapa_no_confirmada: true, banda: { letra: "B", presupuesto: "$500", disposicion: null }, survey: [],
      historial: { llamadas_previas: 0, ultima: null, bant_previo: null }, ocurrio: { transcript: false, grabacion: false }, reporte: null, venta: null, anunciada: null },
  ],
  solo_en_sistema: [{ id8: "bbbbbbbb", fecha: "2026-08-26", hora: "11:00", lead: "Javier Gutierrez", closer: "Carlos González" }],
  sin_instrumentar: ["anunciada: pendiente", "asistió/no asistió: GHL lo soporta"],
};
const UI = { id: "agenda-setter", source: "agenda_setter", params: { project: "David Guerrero", vista: "dia" } };

test("manifest", () => {
  assert.strictEqual(page.id, "agenda-setter");
  assert.deepStrictEqual(page.manifest, { consumes: "object", overridable: ["fecha", "vista", "project", "cita", "carga"] });
});

test("primer load: cascarón con loader que pide la agenda por SSE", () => {
  // Sin ?carga= el render NO consulta la fuente: devuelve el loader al instante.
  const h = page.render({ id: "agenda-setter", params: { vista: "dia", fecha: "2026-08-26", cita: "AP1" } });
  assert.ok(h.startsWith('<section id="pane"'));
  assert.ok(h.includes("data-init"));
  assert.ok(h.includes("/ui/agenda-setter?carga=1&amp;vista=dia&amp;fecha=2026-08-26&amp;cita=AP1"));
  assert.ok(h.includes("Cargando la agenda"));
  // Y el pane completo re-pide siempre con carga=1 (que no vuelva el cascarón).
  const full = page.renderObjeto(UI, D);
  assert.ok(full.includes("carga=1&vista="));
});

test("secciones, kpis y filas", () => {
  const h = page.renderObjeto(UI, D);
  assert.ok(h.startsWith('<section id="pane"'));
  assert.ok(h.includes("Por venir") && h.includes("Ya pasaron"));
  assert.ok(h.includes("Ana Pérez") && h.includes("Luis Gil") && h.includes("Eva Ruiz"));
  assert.ok(h.includes("https://meet.google.com/aaa"));
  assert.ok(h.includes("sin asignar"));
  assert.ok(h.includes("Agenda de closers") && h.includes("Funnel"));
  assert.ok(h.includes("→ cita con closer: 2026-08-26 16:00 · Carlos González")); // el cruce vive en el slide-over
  assert.ok(!h.includes("Javier Gutierrez"));                     // solo_en_sistema ya no se pinta (2026-09-03)
  assert.ok(!h.includes("Cristian Buelvas, Anthony Velásquez")); // la línea de calendarios ya no se pinta (2026-09-03)
  assert.ok(!h.includes("<b>x</b>") && h.includes("&lt;b&gt;x&lt;/b&gt;")); // escape del survey
  assert.ok(!/#[0-9a-f]{6}\b/i.test(h.replace(/#pane|#as-/g, "")), "sin hex en el markup");
});

test("banda solo en las por venir; BANT solo en las pasadas", () => {
  const h = page.renderObjeto(UI, D);
  const funnelIdx = h.indexOf("Funnel");
  const closersSec = h.slice(h.indexOf("Agenda de closers"), funnelIdx);
  const porVenirF = h.slice(h.indexOf("Por venir", funnelIdx), h.indexOf("Ya pasaron", funnelIdx));
  assert.ok(porVenirF.includes(">A<") && porVenirF.includes(">B<"));
  assert.ok(closersSec.includes("65") && closersSec.includes("Emocional") && closersSec.includes("⚠"));
  assert.ok(closersSec.includes("Cancelada"));
});

test("aviso cuando GHL falla y agenda vacía", () => {
  const h = page.renderObjeto(UI, { ...D, fuente: { ghl: "error", detalle: "HTTP 500", db: "ok" }, citas: [], kpis: { closers: { ...D.kpis.closers, citas: 0 }, funnel: { ...D.kpis.funnel, citas: 0 } } });
  assert.ok(h.includes("GHL no respondió") && h.includes("HTTP 500"));
  assert.ok(!h.includes("Ana Pérez"));
});

test("slide-over: panel con entradas por cita, abre por ?cita= y cierra con ✕", () => {
  const h = page.renderObjeto(UI, D);
  assert.ok(h.includes('id="as-panel"'));
  assert.ok(h.includes(`data-class:is-open="$asSel!=''"`));
  assert.ok((h.match(/data-show="\$asSel=='/g) || []).length === D.citas.length); // una entrada por cita
  assert.ok(!/<tr[^>]*data-show="\$asSel/.test(h));                                // ya no hay fila expandida
  const conCita = page.renderObjeto({ ...UI, params: { ...UI.params, cita: "AP1" } }, D);
  assert.ok(conCita.includes(`data-signals="{asSel:'AP1',asCanc:false}"`));
  assert.ok(page.manifest.overridable.includes("cita"));
});

test("detalle: survey curado, atribución aparte, pregunta acortada, cancelada única", () => {
  const h = page.renderObjeto(UI, D);
  const surveyIni = h.indexOf(">Survey<");
  const atribIni = h.indexOf(">Atribución<");
  assert.ok(surveyIni > -1 && atribIni > surveyIni);
  const surveySec = h.slice(surveyIni, atribIni);
  assert.ok(!surveySec.includes("utm_campaign") && !surveySec.includes("vtid"));       // rastreo fuera del survey
  assert.ok(h.slice(atribIni).includes("utm_campaign"));                                // …y presente en Atribución
  assert.ok(surveySec.includes("¿En qué situación te encuentras actualmente con respecto"));
  assert.ok(!surveySec.includes("Las expectativas son la base>"));                      // el párrafo no va como label visible
  assert.ok(surveySec.includes('title="Las expectativas son la base'));                 // …pero sí como tooltip
  assert.ok(surveySec.includes("<b>$1.500</b>") && surveySec.includes(">banda<"));      // las claves resaltadas
  const filaCancelada = h.slice(h.indexOf("AP3") - 400, h.indexOf("AP3") + 1200);
  assert.ok(!/Cancelada<\/span>[^<]*<span[^>]*>Cancelada/.test(filaCancelada));         // un solo badge
});

test("canceladas: fila oculta por defecto + toggle Ver en el card", () => {
  const h = page.renderObjeto(UI, D);
  // La fila cancelada (AP3) lleva el data-show del toggle global.
  assert.ok(/<tr[^>]*data-show="\$asCanc"[^>]*data-on:click="\$asSel = \$asSel=='AP3'/.test(h));
  // Con canceladas en el funnel, el card trae el link Ver/Ocultar.
  const conCanc = page.renderObjeto(UI, { ...D, kpis: { ...D.kpis, funnel: { ...D.kpis.funnel, canceladas: 1 } } });
  assert.ok(conCanc.includes("$asCanc = !$asCanc"));
  // Sin canceladas, el card no finge tener nada que ver.
  const funnelCard = h.slice(h.indexOf("Funnel"));
  assert.ok(!funnelCard.includes("$asCanc = !$asCanc"));
});

test("Meet: columna y alerta solo en el carril de closers", () => {
  // El funnel no lleva columna Meet ni «Cita closer» (2026-09-03).
  const h = page.renderObjeto(UI, D);
  const funnelSec = h.slice(h.indexOf("Funnel"));
  assert.ok(!funnelSec.includes("sin Meet"));
  assert.ok(!funnelSec.includes("<th>Meet</th>"));
  assert.ok(!funnelSec.includes("Cita closer"));
  // una cita de VENTA sin meeting sí alerta
  const conFallo = { ...D, citas: D.citas.map((c) => c.appointment_id === "AP3" ? { ...c, meeting: null, sin_meet: true } : c) };
  const h2 = page.renderObjeto(UI, conFallo);
  const closersSec = h2.slice(h2.indexOf("Agenda de closers"), h2.indexOf("Funnel"));
  assert.ok(closersSec.includes("sin Meet"));
});

test("errores del agendamiento → aviso", () => {
  const h = page.renderObjeto(UI, { ...D, fuente: { ...D.fuente, webhook: "error" } });
  assert.ok(h.includes("El agendamiento está reportando errores"));
  assert.ok(!page.renderObjeto(UI, D).includes("reportando errores"));
});

test("vista semana agrupa por día", () => {
  const d = { ...D, ventana: { ...D.ventana, vista: "semana", desde: "2026-08-24", hasta: "2026-08-30" } };
  const h = page.renderObjeto(UI, d);
  assert.ok(h.includes("miércoles 26"));
});

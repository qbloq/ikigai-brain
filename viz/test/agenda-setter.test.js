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
      survey: [{ campo: "¿Tienes al menos $1.500 USD para invertir?", valor: "$1.500" }, { campo: "País", valor: "Colombia <b>x</b>" }],
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
  assert.deepStrictEqual(page.manifest, { consumes: "object", overridable: ["fecha", "vista", "project"] });
});

test("secciones, kpis y filas", () => {
  const h = page.renderObjeto(UI, D);
  assert.ok(h.startsWith('<section id="pane"'));
  assert.ok(h.includes("Por venir") && h.includes("Ya pasaron"));
  assert.ok(h.includes("Ana Pérez") && h.includes("Luis Gil") && h.includes("Eva Ruiz"));
  assert.ok(h.includes("https://meet.google.com/aaa"));
  assert.ok(h.includes("sin asignar") && h.includes("sin Meet"));
  assert.ok(h.includes("Agenda de closers") && h.includes("Funnel"));
  assert.ok(h.includes("→ 2026-08-26 16:00 · Carlos González"));
  assert.ok(h.includes("Javier Gutierrez"));                      // solo en el sistema
  assert.ok(h.includes("Cristian Buelvas, Anthony Velásquez"));  // miembros del funnel
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

test("vista semana agrupa por día", () => {
  const d = { ...D, ventana: { ...D.ventana, vista: "semana", desde: "2026-08-24", hasta: "2026-08-30" } };
  const h = page.renderObjeto(UI, d);
  assert.ok(h.includes("miércoles 26"));
});

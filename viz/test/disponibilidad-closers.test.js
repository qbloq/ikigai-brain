const { test } = require("node:test");
const assert = require("node:assert");
const page = require("../pages/disponibilidad-closers");

const DIAS = ["2026-08-31", "2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04", "2026-09-05", "2026-09-06"];
const celdaVacia = (estado) => ({ libres: [], citas: [], estado });
const D = {
  proyecto: "David Guerrero",
  calendario: { id: "CAL1", nombre: "Aplicación a Premium Mastermind" },
  semana: { fecha: "2026-09-03", desde: "2026-08-31", hasta: "2026-09-06", dias: DIAS, ahora: "2026-09-03T10:00" },
  fuente: { ghl: "ok", detalle: null, db: "ok" },
  closers: [
    { ghl_user_id: "U1", user_id: "uu1", nombre: "Carlos González", total_libres: 5, total_citas: 3,
      dias: {
        "2026-08-31": { libres: [], citas: [{ appointment_id: "AP0", hora: "11:00", fin: "11:30", lead: "Zoe Mar", estado_ghl: "showed" }], estado: "pasado" },
        "2026-09-01": celdaVacia("pasado"), "2026-09-02": celdaVacia("pasado"),
        "2026-09-03": { libres: ["14:00", "15:30"], citas: [{ appointment_id: "AP1", hora: "09:00", fin: "09:30", lead: "Juan Pérez", estado_ghl: "confirmed" }], estado: "normal" },
        "2026-09-04": { libres: ["08:00", "08:30", "09:00"], citas: [], estado: "normal" },
        "2026-09-05": { libres: [], citas: [{ appointment_id: "AP2", hora: "10:00", fin: "10:30", lead: "Rita León", estado_ghl: "new" }], estado: "lleno" },
        "2026-09-06": celdaVacia("sin_horario"),
      } },
    { ghl_user_id: "U2", user_id: null, nombre: "Diego Fernando Perdomo", total_libres: 0, total_citas: 0,
      dias: Object.fromEntries(DIAS.map((d, i) => [d, celdaVacia(i < 3 ? "pasado" : "sin_horario")])) },
  ],
  sin_closer: [{ appointment_id: "AP9", fecha: "2026-09-03", hora: "10:00", fin: "10:30", lead: "Lead Huérfano", estado_ghl: "confirmed", assigned_user_id: "SETTER9" }],
};
const UI = { id: "disponibilidad-closers", source: "disponibilidad_closers", params: { project: "David Guerrero" } };

test("manifest", () => {
  assert.strictEqual(page.id, "disponibilidad-closers");
  assert.deepStrictEqual(page.manifest, { consumes: "object", overridable: ["fecha", "project", "carga"] });
});

test("primer load: cascarón con loader que pide la matriz por SSE", () => {
  const h = page.render({ id: "disponibilidad-closers", params: { fecha: "2026-09-03" } });
  assert.ok(h.startsWith('<section id="pane"'));
  assert.ok(h.includes("data-init"));
  assert.ok(h.includes("/ui/disponibilidad-closers?carga=1&amp;fecha=2026-09-03"));
  assert.ok(h.includes("Cargando la disponibilidad"));
  // El pane completo re-pide siempre con carga=1 (que no vuelva el cascarón).
  const full = page.renderObjeto(UI, D);
  assert.ok(full.includes("carga=1&fecha="));
});

test("matriz: closers como filas, días como columnas, celdas por estado", () => {
  const h = page.renderObjeto(UI, D);
  assert.ok(h.startsWith('<section id="pane"'));
  assert.ok(h.includes("Carlos González") && h.includes("Diego Fernando Perdomo"));
  assert.ok(h.includes("jueves 3") && h.includes("domingo 6"));   // encabezados de día
  assert.ok(h.includes("3 libres"));                              // celda normal (solo huecos)
  assert.ok(h.includes("2 libres"));                              // celda normal con citas
  assert.ok(h.includes("sin horario"));                           // 0 libres 0 citas futuro
  assert.ok(h.includes("lleno"));                                 // 0 libres con citas
  assert.ok(!/#[0-9a-f]{6}\b/i.test(h.replace(/#pane|#dc-/g, "")), "sin hex en el markup");
});

test("día pasado: citas en gris, jamás «libres»", () => {
  const h = page.renderObjeto(UI, D);
  // la celda del lunes pasado de Carlos (1 cita) existe pero no ofrece huecos
  const lunes = h.slice(h.indexOf("U1|2026-08-31"), h.indexOf("U1|2026-09-01"));
  assert.ok(lunes.includes("1 cita"));
  assert.ok(!lunes.includes("libres"));
});

test("slide-over: click en celda abre el detalle con horas y citas", () => {
  const h = page.renderObjeto(UI, D);
  assert.ok(h.includes("$dcSel = $dcSel=='U1|2026-09-03'"));      // toggle de la celda
  const panel = h.slice(h.indexOf("id=\"dc-panel\""));
  assert.ok(panel.includes("14:00") && panel.includes("15:30")); // huecos libres
  assert.ok(panel.includes("Juan Pérez"));                        // la cita ocupada
  // una celda sin contenido (Diego domingo) no gana panel
  assert.ok(!panel.includes("U2|2026-09-06"));
});

test("singular: «1 libre», nunca «1 libres»", () => {
  const solo1 = JSON.parse(JSON.stringify(D));
  solo1.closers[0].dias["2026-09-04"].libres = ["08:00"];
  const h = page.renderObjeto(UI, solo1);
  assert.ok(h.includes("1 libre") && !h.includes("1 libres"));
});

test("citas sin closer resoluble salen declaradas", () => {
  const h = page.renderObjeto(UI, D);
  assert.ok(h.includes("Lead Huérfano"));
  const sin = page.renderObjeto(UI, { ...D, sin_closer: [] });
  assert.ok(!sin.includes("Lead Huérfano"));
});

test("fuente rota: aviso, no matriz inventada", () => {
  const h = page.renderObjeto(UI, { ...D, fuente: { ghl: "error", detalle: "HTTP 500", db: "ok" }, closers: [] });
  assert.ok(h.includes("GHL no respondió"));
});

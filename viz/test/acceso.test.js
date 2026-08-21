// rolesVisibles — qué capas de UI de rol carga un workspace, según
// copilot.json + docs/roles/acceso.json (la misma regla que bash/lib/acceso.sh
// aplica a las fuentes). Pura: se prueba sin workspace.
const { test } = require("node:test");
const assert = require("node:assert");
const { rolesVisibles } = require("../lib/store");

const ROLES = ["closer", "director-comercial", "ejecutivo", "technology"];
const ACCESO = JSON.parse(require("node:fs").readFileSync(require("node:path").join(__dirname, "..", "..", "docs", "roles", "acceso.json"), "utf8"));

test("cerebro (sin copilot.json) ve todas las capas", () => {
  assert.deepStrictEqual(rolesVisibles(null, ACCESO, ROLES), ROLES);
});
test("technology (uis:*) ve todas las capas", () => {
  assert.deepStrictEqual(rolesVisibles({ role: "technology" }, ACCESO, ROLES), ROLES);
});
test("ejecutivo (solo fuentes:*) ve solo la suya", () => {
  assert.deepStrictEqual(rolesVisibles({ role: "ejecutivo" }, ACCESO, ROLES), ["ejecutivo"]);
});
test("rol ausente del mapa ve solo la suya", () => {
  assert.deepStrictEqual(rolesVisibles({ role: "editor" }, ACCESO, ROLES), []);
  assert.deepStrictEqual(rolesVisibles({ role: "closer" }, ACCESO, ROLES), ["closer"]);
});
test("mapa ausente/roto = fail-closed: solo la suya, aun para technology", () => {
  assert.deepStrictEqual(rolesVisibles({ role: "technology" }, {}, ROLES), ["technology"]);
  assert.deepStrictEqual(rolesVisibles({ role: "technology" }, null, ROLES), ["technology"]);
});
test("copilot.json sin role = fail-closed: ninguna capa de rol (solo org + local)", () => {
  assert.deepStrictEqual(rolesVisibles({ employee: "x" }, ACCESO, ROLES), []);
});

const { test, before } = require("node:test");
const assert = require("node:assert");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");

const TMP = fs.mkdtempSync(path.join(os.tmpdir(), "pubstore-"));
const DB = path.join(TMP, "publicaciones.db");
process.env.PUBLICACIONES_DB = DB; // ANTES del require
const pubstore = require("../lib/pubstore");

const SCHEMA = path.join(__dirname, "..", "..", "bash", "publicar", "schema.sql");
const sql = (s) => execFileSync("sqlite3", [DB, s], { encoding: "utf8" });

before(() => {
  execFileSync("sqlite3", [DB], { input: fs.readFileSync(SCHEMA, "utf8") });
  sql(`INSERT INTO despliegues (slug, codigo_corto, spec_id, spec_json, component, source, identidad, generacion)
       VALUES ('dashboard-closer','Ab3xK9pQ2m','dashboard-por-closer',
               '{"id":"dashboard-por-closer","component":"closer-dashboard","source":"closer_dashboard","params":{}}',
               'closer-dashboard','closer_dashboard','{"closer":"$name"}',1)`);
  sql(`INSERT INTO despliegues (slug, codigo_corto, spec_id, spec_json, component, source, identidad, generacion)
       VALUES ('dashboard-closer','Ab3xK9pQ2m','dashboard-por-closer','{"id":"dashboard-por-closer"}',
               'closer-dashboard','closer_dashboard','{"closer":"$name"}',2)`);
  sql(`INSERT INTO permisos (slug, rol, params_identidad) VALUES ('dashboard-closer','Closer',NULL)`);
  sql(`INSERT INTO permisos (slug, rol, params_identidad) VALUES ('dashboard-closer','Director Comercial','{}')`);
  sql(`INSERT INTO permisos (slug, rol, params_identidad, revocado_at) VALUES ('dashboard-closer','Editor','{}','2026-08-15')`);
});

test("vigente devuelve la generación más alta no archivada", () => {
  const d = pubstore.vigente("dashboard-closer");
  assert.strictEqual(d.generacion, 2);
});
test("vigente rechaza slugs malformados sin tocar la db", () => {
  assert.strictEqual(pubstore.vigente("x'; DROP TABLE despliegues;--"), null);
  assert.strictEqual(pubstore.vigente("dashboard-closer").slug, "dashboard-closer");
});
test("porCodigo resuelve el alias", () => {
  assert.strictEqual(pubstore.porCodigo("Ab3xK9pQ2m").slug, "dashboard-closer");
  assert.strictEqual(pubstore.porCodigo("noexiste123"), null);
});
test("porSpecId devuelve los vigentes de ese spec", () => {
  const rows = pubstore.porSpecId("dashboard-por-closer");
  assert.strictEqual(rows.length, 1);
  assert.strictEqual(rows[0].generacion, 2);
});
test("permisosDe excluye revocados", () => {
  const p = pubstore.permisosDe("dashboard-closer");
  assert.deepStrictEqual(p.map((x) => x.rol).sort(), ["Closer", "Director Comercial"]);
});
test("visita inserta y nunca lanza", () => {
  pubstore.visita("dashboard-closer", { id: "u1", email: "a@b.c" }, "/dashboard-closer");
  assert.strictEqual(Number(sql("SELECT count(*) FROM visitas").trim()), 1);
  process.env.PUBLICACIONES_DB_ROTA = "1"; // no usado — solo documenta que el catch es total
  pubstore.visita(null, null, null); // args inválidos → swallowed
});

const { test } = require("node:test");
const assert = require("node:assert");
const { elegirPermiso, resolverIdentidad, mergeParams } = require("../lib/publogic");

const luis = { id: "u-luis", email: "luis@x.co", roles: ["Closer"], name: "Luis Fernando" };
const dire = { id: "u-dir", email: "dir@x.co", roles: ["Director Comercial"], name: "Lucho" };
const ambos = { id: "u-mix", email: "mix@x.co", roles: ["Closer", "Director Comercial"], name: "Mix" };

const pCloser = { user_id: null, rol: "Closer", params_identidad: null };
const pDire = { user_id: null, rol: "Director Comercial", params_identidad: "{}" };
const pUser = { user_id: "u-luis", rol: null, params_identidad: '{"closer":"Andrés"}' };

test("sin permiso que matchee → null", () => {
  assert.strictEqual(elegirPermiso([pCloser], { ...dire, roles: ["Editor"] }), null);
  assert.strictEqual(elegirPermiso([], luis), null);
});
test("permiso por rol matchea roles[] del JWT", () => {
  assert.strictEqual(elegirPermiso([pCloser, pDire], luis), pCloser);
  assert.strictEqual(elegirPermiso([pCloser, pDire], dire), pDire);
});
test("por-user gana sobre por-rol", () => {
  assert.strictEqual(elegirPermiso([pCloser, pUser], luis), pUser);
});
test("entre roles, gana el menos restrictivo ({} sobre plantilla)", () => {
  assert.strictEqual(elegirPermiso([pCloser, pDire], ambos), pDire);
});

test("identidad: NULL hereda la plantilla y sustituye variables", () => {
  const f = resolverIdentidad({ closer: "$name" }, pCloser, luis);
  assert.deepStrictEqual(f, { closer: "Luis Fernando" });
});
test("identidad: '{}' anula la plantilla", () => {
  assert.deepStrictEqual(resolverIdentidad({ closer: "$name" }, pDire, dire), {});
});
test("identidad: explícito manda tal cual", () => {
  assert.deepStrictEqual(resolverIdentidad({ closer: "$name" }, pUser, luis), { closer: "Andrés" });
});
test("identidad: sin plantilla y permiso NULL → nada forzado", () => {
  assert.deepStrictEqual(resolverIdentidad(null, pCloser, luis), {});
});
test("sustituye $email y $user_id", () => {
  const f = resolverIdentidad({ a: "$email", b: "$user_id" }, pCloser, luis);
  assert.deepStrictEqual(f, { a: "luis@x.co", b: "u-luis" });
});

// --- identidad que NO resuelve = DENEGAR (nunca «sin filtro») ---------------
// El modo de falla que esto cierra: "" sobrevivía como valor, buildArgs
// descartaba el param vacío y el script corría con su default — la sesión sin
// nombre terminaba viendo el dashboard del closer más ocupado.
test("identidad: variable vacía → null (denegar), no ''", () => {
  const sinNombre = { id: "u-x", email: "x@x.co", roles: ["Closer"], name: "" };
  assert.strictEqual(resolverIdentidad({ closer: "$name" }, pCloser, sinNombre), null);
});
test("identidad: variable ausente/undefined → null (denegar)", () => {
  const sinId = { email: "x@x.co", roles: ["Closer"], name: "Ana" };
  assert.strictEqual(resolverIdentidad({ closer_id: "$user_id" }, pCloser, sinId), null);
  const sinEmail = { id: "u-x", roles: ["Closer"], name: "Ana" };
  assert.strictEqual(resolverIdentidad({ a: "$email" }, pCloser, sinEmail), null);
});
test("identidad: null en una variable no contamina el resto — denegar es total", () => {
  const p = { id: "u-x", email: "", roles: ["Closer"], name: "Ana" };
  assert.strictEqual(resolverIdentidad({ a: "$name", b: "$email" }, pCloser, p), null);
});
test("identidad: '{}' con payload vacío sigue siendo {} (permiso libre ≠ denegar)", () => {
  const vacio = { id: "u-d", email: "", roles: ["Director Comercial"], name: "" };
  assert.deepStrictEqual(resolverIdentidad({ closer: "$name" }, pDire, vacio), {});
});
test("identidad: literal vacío en la plantilla NO es variable — pasa tal cual", () => {
  assert.deepStrictEqual(resolverIdentidad({ closer: "" }, pCloser, luis), { closer: "" });
});

// --- por qué la identidad viaja como users.id y no como nombre --------------
// Caso REAL de producción: el JWT trae solo el nombre de pila. "David"
// (David Guerrero) es subcadena de "Luis David Flórez", y closer_dashboard.sh
// filtraba con ILIKE '%frag%' → David veía el dashboard entero de Luis David.
// La plantilla correcta fuerza $user_id contra users.id (igualdad exacta).
test("identidad por $user_id: un nombre de pila que es subcadena de otro closer no colisiona", () => {
  const david = { id: "6320de8f-82c8-4112-b07a-2f5769790eef", email: "david@x.co", roles: ["Closer"], name: "David" };
  const luisDavid = { id: "9cbca153-f2ca-46fd-9f9f-694e9be63cd2", email: "ldf@x.co", roles: ["Closer"], name: "Luis David" };
  const plantilla = { closer_id: "$user_id" };
  const fDavid = resolverIdentidad(plantilla, pCloser, david);
  const fLuis = resolverIdentidad(plantilla, pCloser, luisDavid);
  assert.deepStrictEqual(fDavid, { closer_id: david.id });
  assert.deepStrictEqual(fLuis, { closer_id: luisDavid.id });
  assert.notStrictEqual(fDavid.closer_id, fLuis.closer_id);
  // La plantilla vieja ($name) sí colisiona: el valor forzado de David es
  // subcadena del de Luis David, y con ILIKE eso es el mismo filtro.
  const vName = { closer: "$name" };
  assert.ok(resolverIdentidad(vName, pCloser, luisDavid).closer.includes(resolverIdentidad(vName, pCloser, david).closer));
});

test("merge: closer_id forzado bloquea aunque el navegador mande closer y closer_id", () => {
  const { params, locked } = mergeParams({
    specParams: {},
    paramsFijos: {},
    overrides: { closer: "Otro", closer_id: "otro-uuid" },
    overridable: ["closer", "project", "from", "to"], // closer_id NO es overridable
    forzados: { closer_id: "6320de8f-82c8-4112-b07a-2f5769790eef" },
  });
  assert.deepStrictEqual(params, { closer: "Otro", closer_id: "6320de8f-82c8-4112-b07a-2f5769790eef" });
  assert.deepStrictEqual(locked, ["closer_id"]);
});

test("merge: fijos → overrides (solo overridable) → forzados ganan", () => {
  const { params, locked } = mergeParams({
    specParams: { from: "2026-01-01" },
    paramsFijos: { project: "David Guerrero" },
    overrides: { closer: "Otro", to: "2026-08-01", hack: "x" },
    overridable: ["closer", "from", "to"],
    forzados: { closer: "Luis Fernando" },
  });
  assert.deepStrictEqual(params, {
    from: "2026-01-01", project: "David Guerrero", to: "2026-08-01", closer: "Luis Fernando",
  });
  assert.deepStrictEqual(locked, ["closer"]);
});

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

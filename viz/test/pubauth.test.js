const { test } = require("node:test");
const assert = require("node:assert");
const { verifyJWT, firmarJWT, parseCookies, cookieSesion, cookieBorrar } = require("../lib/pubauth");

const SECRET = "secreto-de-prueba";

test("firma y verifica un JWT HS256", () => {
  const t = firmarJWT({ id: "u1", roles: ["Closer"], name: "Luis" }, SECRET, { expSeg: 60 });
  const p = verifyJWT(t, SECRET);
  assert.strictEqual(p.id, "u1");
  assert.deepStrictEqual(p.roles, ["Closer"]);
});
test("rechaza firma inválida / secreto distinto / basura", () => {
  const t = firmarJWT({ id: "u1" }, SECRET, { expSeg: 60 });
  assert.strictEqual(verifyJWT(t + "x", SECRET), null);
  assert.strictEqual(verifyJWT(t, "otro"), null);
  assert.strictEqual(verifyJWT("no.es.jwt", SECRET), null);
  assert.strictEqual(verifyJWT(null, SECRET), null);
});
test("rechaza token expirado", () => {
  const t = firmarJWT({ id: "u1" }, SECRET, { expSeg: -10 });
  assert.strictEqual(verifyJWT(t, SECRET), null);
});
test("rechaza alg distinto de HS256 (p.ej. none)", () => {
  const h = Buffer.from(JSON.stringify({ alg: "none", typ: "JWT" })).toString("base64url");
  const p = Buffer.from(JSON.stringify({ id: "u1" })).toString("base64url");
  assert.strictEqual(verifyJWT(`${h}.${p}.`, SECRET), null);
});
test("parseCookies", () => {
  assert.deepStrictEqual(parseCookies("a=1; viz_sesion=tok; b=2").viz_sesion, "tok");
  assert.deepStrictEqual(parseCookies(undefined), {});
});
test("cookieSesion y cookieBorrar", () => {
  process.env.PUBLISH_SECURE = "0";
  assert.match(cookieSesion("tok", 3600), /^viz_sesion=tok; HttpOnly; Path=\/; SameSite=Lax; Max-Age=3600$/);
  delete process.env.PUBLISH_SECURE;
  assert.match(cookieSesion("tok", 3600), /; Secure$/);
  assert.match(cookieBorrar(), /Max-Age=0/);
});

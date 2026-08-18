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
test("rechaza payload null (fail-closed)", () => {
  // Manually build a token with null payload
  const crypto = require("node:crypto");
  const b64u = (buf) => Buffer.from(buf).toString("base64url");
  const h = b64u(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const p = b64u(JSON.stringify(null)); // payload is JSON null
  const sig = crypto.createHmac("sha256", SECRET).update(`${h}.${p}`).digest("base64url");
  const token = `${h}.${p}.${sig}`;
  assert.strictEqual(verifyJWT(token, SECRET), null);
});
test("rechaza secret inválido (undefined/null)", () => {
  const t = firmarJWT({ id: "u1" }, SECRET, { expSeg: 60 });
  assert.strictEqual(verifyJWT(t, undefined), null);
  assert.strictEqual(verifyJWT(t, null), null);
});
test("loginMarketico falla en red caída (fail-closed)", async () => {
  const prev = process.env.MARKETICO_AUTH_URL;
  process.env.MARKETICO_AUTH_URL = "http://127.0.0.1:1/login"; // unreachable port
  const { loginMarketico } = require("../lib/pubauth");
  const result = await loginMarketico("a@b.c", "password");
  assert.strictEqual(result, null);
  if (prev) process.env.MARKETICO_AUTH_URL = prev;
  else delete process.env.MARKETICO_AUTH_URL;
});

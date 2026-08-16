// Autenticación del publicador: el JWT de Marketico verificado LOCALMENTE
// (HS256 + JWT_SECRET compartido — misma máquina, cero red por visita) y el
// manejo de la cookie de sesión. El login reenvía las credenciales UNA vez a
// la API de Marketico y no las persiste jamás.
const crypto = require("node:crypto");

const COOKIE = "viz_sesion";
const b64u = (buf) => Buffer.from(buf).toString("base64url");

function firmarJWT(payload, secret, { expSeg = 3600 } = {}) {
  const now = Math.floor(Date.now() / 1000);
  const h = b64u(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const p = b64u(JSON.stringify({ iat: now, exp: now + expSeg, ...payload }));
  const sig = crypto.createHmac("sha256", secret).update(`${h}.${p}`).digest("base64url");
  return `${h}.${p}.${sig}`;
}

function verifyJWT(token, secret) {
  if (!token || typeof token !== "string") return null;
  if (!secret || typeof secret !== "string") return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [h, p, sig] = parts;
  let header, payload;
  try {
    header = JSON.parse(Buffer.from(h, "base64url").toString("utf8"));
    payload = JSON.parse(Buffer.from(p, "base64url").toString("utf8"));
  } catch {
    return null;
  }
  if (!header || header.alg !== "HS256" || !payload || typeof payload !== "object") return null;
  let expected;
  try {
    expected = crypto.createHmac("sha256", secret).update(`${h}.${p}`).digest("base64url");
  } catch {
    return null;
  }
  const a = Buffer.from(sig), b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  if (payload.exp != null && payload.exp * 1000 <= Date.now()) return null;
  return payload;
}

function parseCookies(header) {
  const out = {};
  for (const part of String(header || "").split(";")) {
    const i = part.indexOf("=");
    if (i > 0) out[part.slice(0, i).trim()] = part.slice(i + 1).trim();
  }
  return out;
}

const seguro = () => (process.env.PUBLISH_SECURE === "0" ? "" : "; Secure");
const cookieSesion = (token, maxAgeSeg) =>
  `${COOKIE}=${token}; HttpOnly; Path=/; SameSite=Lax; Max-Age=${maxAgeSeg}${seguro()}`;
const cookieBorrar = () => `${COOKIE}=; HttpOnly; Path=/; SameSite=Lax; Max-Age=0${seguro()}`;

const AUTH_URL = () => process.env.MARKETICO_AUTH_URL || "https://ikigaigm.api.parallelo.ai/api/auth/login";

async function loginMarketico(email, password) {
  try {
    const res = await fetch(AUTH_URL(), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    });
    if (!res.ok) return null;
    const data = await res.json().catch(() => null);
    return (data && data.success && data.data && data.data.token) || null;
  } catch {
    return null;
  }
}

module.exports = { COOKIE, firmarJWT, verifyJWT, parseCookies, cookieSesion, cookieBorrar, loginMarketico };

// mktrelay — relay whitelisteado hacia el API de Marketico, la escritura de la
// UI `resolver-ventas` (y de lo que se gane el permiso después). Sigue el
// patrón del relay de transcript (/t/ en publish.js): este proceso NUNCA
// autoriza por sí mismo — reenvía la request con el token del visitante (la
// cookie HttpOnly en el publicador; MEETICO_JWT_TOKEN en el viz local, solo
// para desarrollo) y la autorización de fondo la da Marketico. El JWT jamás
// toca el JS del navegador.
//
// La whitelist es de FORMA (método + shape del subpath), no de prefijo: un
// subpath que no matchea exactamente → null → 404 opaco del que llama.
// Componentes autorizados a usar el relay: RELAY_COMPONENTS (guard del
// publicador — el despliegue debe renderizar uno de estos).

const UUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
const ENTERO = "[0-9]{1,10}";

// method + regex del subpath (relativo, sin / inicial) → URL en Marketico.
const RUTAS = [
  // products: la tabla `products` del SISTEMA (uuid + base_price) — lo que
  // /confirm exige como paymentPlan.product_id. (/api/leads/products es el
  // catálogo GHL crudo, ids incompatibles — no sirve aquí.)
  { method: "GET",  re: new RegExp(`^products$`),                            mkt: () => `/api/project-settings/products` },
  { method: "POST", re: new RegExp(`^calls/(${UUID})/confirm$`),             mkt: (m) => `/api/calls/${m[1]}/confirm`, body: true },
  { method: "POST", re: new RegExp(`^payment-plans$`),                       mkt: () => `/api/payment-plans/`, body: true },
  { method: "GET",  re: new RegExp(`^payment-plans/customer/([A-Za-z0-9]{10,40})$`), mkt: (m) => `/api/payment-plans/customer/${m[1]}` },
  { method: "PUT",  re: new RegExp(`^installments/(${ENTERO})$`),            mkt: (m) => `/api/payment-plans/installments/${m[1]}`, body: true },
  { method: "POST", re: new RegExp(`^installments/(${ENTERO})/receipt$`),    mkt: (m) => `/api/leads/installments/${m[1]}/receipt`, body: true, multipart: true },
];

const RELAY_COMPONENTS = new Set(["resolver-ventas"]);

// 64KB para JSON; 10MB para el comprobante (el mismo tope del multer de
// Marketico — un relay más estricto rechazaría fotos de celular que el
// backend sí acepta).
const MAX_JSON = 64 * 1024;
const MAX_MULTIPART = 10 * 1024 * 1024;

function matchMkt(method, subpath) {
  for (const r of RUTAS) {
    if (r.method !== method) continue;
    const m = r.re.exec(subpath);
    if (m) return { path: r.mkt(m), body: !!r.body, multipart: !!r.multipart };
  }
  return null;
}

function leerCuerpo(req, limite) {
  return new Promise((resolve) => {
    const chunks = [];
    let total = 0;
    let done = false;
    const fin = (v) => { if (!done) { done = true; resolve(v); } };
    req.on("data", (c) => {
      total += c.length;
      if (total > limite) { fin(null); req.destroy(); return; }
      chunks.push(c);
    });
    req.on("end", () => fin(Buffer.concat(chunks)));
    req.on("error", () => fin(null));
  });
}

// Ejecuta el relay: matchea, lee el body si aplica y reenvía con el token
// dado. Devuelve {status, contentType, body} o null (no matchea / body
// excedido) — el que llama convierte null en su 404 opaco.
async function relayMkt({ mktBase, method, subpath, req, token }) {
  const ruta = matchMkt(method, subpath);
  if (!ruta || !token) return null;

  const headers = { Authorization: `Bearer ${token}` };
  let body;
  if (ruta.body) {
    const crudo = await leerCuerpo(req, ruta.multipart ? MAX_MULTIPART : MAX_JSON);
    if (crudo === null) return null;
    body = crudo;
    // multipart: el boundary vive en el Content-Type original — pasa intacto.
    headers["Content-Type"] = req.headers["content-type"] || "application/json";
  }

  const r = await fetch(`${mktBase}${ruta.path}`, { method, headers, body }).catch(() => null);
  if (!r) return { status: 502, contentType: "application/json", body: '{"success":false,"error":"Marketico no responde"}' };
  const texto = await r.text().catch(() => "");
  return {
    status: r.status,
    contentType: r.headers.get("content-type") || "application/json",
    body: texto,
  };
}

module.exports = { matchMkt, relayMkt, RELAY_COMPONENTS };

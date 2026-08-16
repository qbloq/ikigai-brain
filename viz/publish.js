#!/usr/bin/env node
// El PUBLICADOR — el entrypoint de PRODUCCIÓN del viz (pm2 «viz-publish»).
// Sirve únicamente las UIs registradas en data/sqlite/publicaciones.db, con
// datos vivos, login contra Marketico (JWT verificado localmente) y permisos
// con alcance por identidad. Superficie mínima POR CONSTRUCCIÓN: no existe el
// shell, ni creación/edición de UIs, ni acts POST — lib/actions.js no se
// importa. Diseño: docs/superpowers/specs/2026-08-15-viz-publish-design.md
//
//   GET  /:slug        render standalone del despliegue (auth + permiso)
//   GET  /s/:codigo    alias corto → 302 /:slug
//   GET  /ui/:specId   SSE re-render (los @get de las páginas) — params forzados
//   GET  /u/:specId    «abrir solo» de las páginas → 302 /:slug
//   GET|POST /login    página + proxy de credenciales a Marketico
//   POST|GET /logout   borra la cookie
//   GET  /health       liveness
//
// Run:  PORT=4318 node viz/publish.js   (HOST default 127.0.0.1 — solo nginx)

const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const pubstore = require("./lib/pubstore");
const { elegirPermiso, resolverIdentidad, mergeParams } = require("./lib/publogic");
const { COOKIE, verifyJWT, parseCookies, cookieSesion, cookieBorrar, loginMarketico } = require("./lib/pubauth");
const { standalone } = require("./lib/html");
const { renderPane, overridableFor, escape } = require("./lib/components");
const { startSSE, patchElements } = require("./lib/sse");
const { loadTheme, themeHead } = require("./lib/theme");

const REPO_ROOT = path.resolve(__dirname, "..");
const PORT = Number(process.env.PORT) || 4318;
const HOST = process.env.HOST || "127.0.0.1";

// .env del checkout — publish.js necesita JWT_SECRET sin depender de pm2 env.
for (const line of (() => { try { return fs.readFileSync(path.join(REPO_ROOT, ".env"), "utf8").split("\n"); } catch { return []; } })()) {
  const m = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim());
  if (m && process.env[m[1]] == null) process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
}
if (!process.env.JWT_SECRET) {
  console.error("FALTA JWT_SECRET (en .env o el entorno) — sin él no se puede verificar ninguna sesión.");
  process.exit(1);
}

const PUBLIC_FILES = new Set(["/datastar.js", "/chart.umd.js", "/charts-init.js", "/tw-bridge.js", "/tokens.css"]);
const RUTAS_RESERVADAS = new Set(["login", "logout", "health", "ui", "u", "c", "s", "api", "fonts"]);

function send(res, status, body, type = "text/html; charset=utf-8", extra = {}) {
  res.writeHead(status, { "Content-Type": type, ...extra });
  res.end(body);
}
const redirect = (res, to, extra = {}) => { res.writeHead(303, { Location: to, ...extra }); res.end(); };

function readBody(req) {
  return new Promise((resolve) => {
    let data = "";
    req.on("data", (c) => (data += c));
    req.on("end", () => resolve(data));
  });
}

// --- login ------------------------------------------------------------------
// `next` solo puede ser una ruta interna simple — nunca una URL absoluta.
const nextSeguro = (v) => (/^\/[a-zA-Z0-9\-/]*$/.test(v || "") ? v : "/");

function paginaLogin({ next = "/", error = "" } = {}) {
  const theme = loadTheme();
  return `<!doctype html><html lang="es" data-theme="${theme.modo}"><head>
  <meta charset="utf-8" /><meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Entrar · ${escape(theme.nombre)}</title>${themeHead(theme)}</head>
  <body class="min-h-screen flex items-center justify-center" style="background:var(--surface-2)">
    <form method="POST" action="/login" class="card card-pad w-full" style="max-width:22rem">
      <h1 class="text-lg font-bold mb-1" style="color:var(--text-1)">${escape(theme.nombre)}</h1>
      <p class="text-sm mb-4" style="color:var(--text-3)">Entra con tu cuenta de la plataforma.</p>
      ${error ? `<div class="alert alert-neg mb-3 text-sm">${escape(error)}</div>` : ""}
      <input type="hidden" name="next" value="${escape(next)}" />
      <label class="text-xs font-semibold" style="color:var(--text-2)">Email</label>
      <input class="input w-full mb-3" type="email" name="email" required autofocus autocomplete="email" />
      <label class="text-xs font-semibold" style="color:var(--text-2)">Contraseña</label>
      <input class="input w-full mb-4" type="password" name="password" required autocomplete="current-password" />
      <button class="btn btn-brand w-full" type="submit">Entrar</button>
    </form>
  </body></html>`;
}

// --- resolución despliegue → ui lista para render ---------------------------
function accesoA(despliegue, payload) {
  const permiso = elegirPermiso(pubstore.permisosDe(despliegue.slug), payload);
  if (!permiso) return null;
  const plantilla = despliegue.identidad ? JSON.parse(despliegue.identidad) : null;
  return resolverIdentidad(plantilla, permiso, payload);
}

function uiRenderizable(despliegue, overrides, forzados) {
  const spec = JSON.parse(despliegue.spec_json);
  const { params, locked } = mergeParams({
    specParams: spec.params,
    paramsFijos: JSON.parse(despliegue.params_fijos || "{}"),
    overrides,
    overridable: overridableFor(spec),
    forzados,
  });
  return { ...spec, params, _locked: locked };
}

// Busca entre los despliegues de un spec el primero al que payload tiene
// permiso (resuelve /ui/:specId y /u/:specId — los links que emiten las páginas).
function despliegueDeSpec(specId, payload) {
  for (const d of pubstore.porSpecId(specId)) {
    const forzados = accesoA(d, payload);
    if (forzados !== null) return { despliegue: d, forzados };
  }
  return null;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const { pathname } = url;
  try {
    if (pathname === "/health") return send(res, 200, "ok", "text/plain");

    // --- assets (sin auth: la página de login los necesita) ---
    const isFont = /^\/fonts\/[a-z0-9._-]+\.(woff2|css)$/.test(pathname);
    if ((PUBLIC_FILES.has(pathname) || isFont) && req.method === "GET") {
      const file = path.join(__dirname, "public", pathname.slice(1));
      const body = fs.readFileSync(file);
      return send(res, 200, body, pathname.endsWith(".css") ? "text/css; charset=utf-8"
        : pathname.endsWith(".woff2") ? "font/woff2" : "text/javascript; charset=utf-8",
        { "Cache-Control": "public, max-age=86400" });
    }

    // --- login / logout ---
    if (pathname === "/login" && req.method === "GET")
      return send(res, 200, paginaLogin({ next: nextSeguro(url.searchParams.get("next")) }));
    if (pathname === "/login" && req.method === "POST") {
      const body = new URLSearchParams(await readBody(req));
      const next = nextSeguro(body.get("next"));
      const token = await loginMarketico(String(body.get("email") || "").trim(), String(body.get("password") || ""))
        .catch(() => null);
      if (!token) return send(res, 401, paginaLogin({ next, error: "Credenciales inválidas." }));
      const payload = verifyJWT(token, process.env.JWT_SECRET);
      if (!payload) return send(res, 401, paginaLogin({ next, error: "La plataforma devolvió una sesión inválida." }));
      const maxAge = payload.exp ? Math.max(60, payload.exp - Math.floor(Date.now() / 1000)) : 86400;
      return redirect(res, next, { "Set-Cookie": cookieSesion(token, maxAge) });
    }
    if (pathname === "/logout")
      return redirect(res, "/login", { "Set-Cookie": cookieBorrar() });

    // --- alias corto (sin auth: solo redirige; el login gatea el destino) ---
    let m;
    if ((m = /^\/s\/([A-Za-z0-9]+)$/.exec(pathname)) && req.method === "GET") {
      const d = pubstore.porCodigo(m[1]);
      return d ? redirect(res, `/${d.slug}`) : send(res, 404, "No encontrado", "text/plain");
    }

    // --- todo lo demás requiere sesión ---
    const payload = verifyJWT(parseCookies(req.headers.cookie)[COOKIE], process.env.JWT_SECRET);
    if (!payload) {
      if (req.method === "GET") return send(res, 200, paginaLogin({ next: nextSeguro(pathname) }));
      return send(res, 401, "Sesión requerida", "text/plain");
    }

    // --- SSE re-render: los @get('/ui/<specId>?…') que emiten las páginas ---
    if ((m = /^\/ui\/([a-z0-9-]+)$/.exec(pathname)) && req.method === "GET") {
      const hit = despliegueDeSpec(m[1], payload);
      if (!hit) return send(res, 404, "No encontrado", "text/plain");
      const ui = uiRenderizable(hit.despliegue, Object.fromEntries(url.searchParams), hit.forzados);
      pubstore.visita(hit.despliegue.slug, payload, req.url);
      startSSE(res);
      patchElements(res, renderPane(ui));
      return res.end();
    }

    // --- «abrir solo ↗» de las páginas → la URL canónica del despliegue ---
    if ((m = /^\/u\/([a-z0-9-]+)$/.exec(pathname)) && req.method === "GET") {
      const hit = despliegueDeSpec(m[1], payload);
      return hit ? redirect(res, `/${hit.despliegue.slug}`) : send(res, 404, "No encontrado", "text/plain");
    }

    // --- la ruta legible: GET /<slug> ---
    if ((m = /^\/([a-z0-9][a-z0-9-]*)$/.exec(pathname)) && req.method === "GET" && !RUTAS_RESERVADAS.has(m[1])) {
      const d = pubstore.vigente(m[1]);
      if (!d) return send(res, 404, "No encontrado", "text/plain");
      const forzados = accesoA(d, payload);
      if (forzados === null) return send(res, 404, "No encontrado", "text/plain");
      const ui = uiRenderizable(d, Object.fromEntries(url.searchParams), forzados);
      pubstore.visita(d.slug, payload, req.url);
      return send(res, 200, standalone(ui));
    }

    return send(res, 404, "No encontrado", "text/plain");
  } catch (e) {
    console.error(`[publish] ${req.method} ${pathname}: ${e.message}`);
    return send(res, 500, "Error interno", "text/plain");
  }
});

try { pubstore.vigente("health-probe"); } catch {
  console.warn("[publish] publicaciones.db no existe aún — todo responderá 404 hasta la primera publicación.");
}

server.listen(PORT, HOST, () => console.log(`viz-publish on http://${HOST}:${PORT}`));

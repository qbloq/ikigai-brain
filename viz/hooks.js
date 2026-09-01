#!/usr/bin/env node
// El INTERCEPTOR — entrypoint que recibe los auto-reportes de Marketico
// (pm2 «viz-hooks»). Superficie mínima POR CONSTRUCCIÓN, como publish.js:
// una ruta de escritura con Bearer de máquina, y /health. Nada más.
// Diseño: docs/superpowers/specs/2026-08-16-intercepcion-webhook-crm-design.md
//
//   POST /hooks/crm-resultado   auto-reporte de un processBooking → sqlite
//   GET  /health                liveness
//
// Run:  PORT=4319 node viz/hooks.js   (HOST default 127.0.0.1 — solo nginx)

const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { execFileSync, spawn } = require("node:child_process");

const REPO_ROOT = path.resolve(__dirname, "..");
const PORT = Number(process.env.PORT) || 4319;
const HOST = process.env.HOST || "127.0.0.1";
const DB = () => process.env.INTERCEPCIONES_DB || path.join(REPO_ROOT, "data", "sqlite", "intercepciones.db");
const SCHEMA = path.join(REPO_ROOT, "bash", "intercepciones", "schema.sql");

// .env del checkout — mismo loader que publish.js (pm2 no garantiza el env).
for (const line of (() => { try { return fs.readFileSync(path.join(REPO_ROOT, ".env"), "utf8").split("\n"); } catch { return []; } })()) {
  const m = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim());
  if (m && process.env[m[1]] == null) process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
}
if (!process.env.HOOKS_TOKEN) {
  console.error("FALTA HOOKS_TOKEN (en .env o el entorno) — sin él cualquiera podría escribir el log.");
  process.exit(1);
}

// Comparación de token en tiempo constante (sobre hashes: iguala longitudes).
function tokenValido(header) {
  const m = /^Bearer (.+)$/.exec(header || "");
  if (!m) return false;
  const a = crypto.createHash("sha256").update(m[1]).digest();
  const b = crypto.createHash("sha256").update(process.env.HOOKS_TOKEN).digest();
  return crypto.timingSafeEqual(a, b);
}

const lit = (v) => (v == null ? "NULL" : `'${String(v).replace(/'/g, "''")}'`);

// -cmd '.timeout 5000': busy timeout de 5 s. El cron de reconciliación escribe
// la MISMA sqlite; sin esto, un POST que llega mientras la otra txn tiene el
// lock muere al instante con «database is locked» y se va por el catch (500).
// Dot-command y no `PRAGMA busy_timeout`, que imprimiría su valor en stdout.
function sqlite(sql) {
  fs.mkdirSync(path.dirname(DB()), { recursive: true });
  execFileSync("sqlite3", ["-cmd", ".timeout 5000", DB()], { input: sql, encoding: "utf8" });
}

// Schema idempotente al boot — el receptor no depende de que bash pasara antes.
sqlite(fs.readFileSync(SCHEMA, "utf8"));

function guardar(body, raw) {
  const c = body.contacto || {};
  sqlite(`INSERT INTO crm_webhook
    (appointment_id, location_id, estado_cita, contacto, email, telefono,
     start_time, end_time, ok, resultado, error, duracion_ms, payload)
    VALUES (${lit(body.appointment_id)}, ${lit(body.location_id)}, ${lit(body.estado_cita)},
      ${lit(c.nombre)}, ${lit(c.email)}, ${lit(c.telefono)},
      ${lit(body.start_time)}, ${lit(body.end_time)}, ${body.ok ? 1 : 0},
      ${lit(body.resultado == null ? null : JSON.stringify(body.resultado))},
      ${lit(body.error == null ? null : JSON.stringify(body.error))},
      ${Number.isFinite(body.duracion_ms) ? Math.round(body.duracion_ms) : "NULL"},
      ${lit(raw)});`);
}

const MAX_BODY = 512 * 1024; // el booking crudo de GHL viaja completo
function readBody(req) {
  return new Promise((resolve) => {
    let data = "";
    let done = false;
    const finish = (v) => { if (!done) { done = true; resolve(v); } };
    req.on("data", (ch) => { data += ch; if (data.length > MAX_BODY) { finish(null); req.destroy(); } });
    req.on("end", () => finish(data));
    req.on("error", () => finish(null));
  });
}

const server = http.createServer(async (req, res) => {
  const fin = (status, body = "") => { res.writeHead(status, { "Content-Type": "text/plain", "Cache-Control": "no-store" }); res.end(body); };
  try {
    const url = new URL(req.url, "http://localhost");
    if (url.pathname === "/health") {
      if (req.method === "HEAD") { res.writeHead(200, { "Content-Type": "text/plain", "Content-Length": "2" }); return res.end(); }
      return fin(200, "ok");
    }
    if (url.pathname === "/hooks/crm-resultado" && req.method === "POST") {
      if (!tokenValido(req.headers.authorization)) return fin(401);
      const raw = await readBody(req);
      if (raw == null) return fin(400, "cuerpo demasiado grande");
      let body;
      try { body = JSON.parse(raw); } catch { return fin(400, "JSON inválido"); }
      if (typeof body.ok !== "boolean") return fin(400, "falta ok:boolean");
      try {
        guardar(body, raw);
      } catch (e) {
        // Último recurso: el payload no se pierde aunque la sqlite esté trabada.
        console.error(`[hooks] sqlite falló (${e.message}); payload: ${raw.slice(0, 2000)}`);
        return fin(500);
      }
      return fin(204);
    }
    // El agendamiento ENTRANTE de GHL (reenviado por Marketico en modo
    // forward, o directo cuando el workflow apunte acá). Validar y delegar:
    // la decisión vive en bash/agenda/entrante.sh, que registra TODO en la
    // tabla `entrantes` — incluido su propio error. 202 al instante: el que
    // reenvía no debe esperar a Marketico.
    if (url.pathname === "/hooks/crm" && req.method === "POST") {
      if (!tokenValido(req.headers.authorization)) return fin(401);
      const raw = await readBody(req);
      if (raw == null) return fin(400, "cuerpo demasiado grande");
      try { JSON.parse(raw); } catch { return fin(400, "JSON inválido"); }
      try {
        const p = spawn("bash", [path.join(REPO_ROOT, "bash", "agenda", "entrante.sh")],
          { cwd: REPO_ROOT, detached: true, stdio: ["pipe", "ignore", "ignore"] });
        p.on("error", (e) => console.error(`[hooks] entrante.sh no arrancó: ${e.message}; payload: ${raw.slice(0, 2000)}`));
        p.stdin.write(raw); p.stdin.end(); p.unref();
      } catch (e) {
        console.error(`[hooks] entrante spawn falló (${e.message}); payload: ${raw.slice(0, 2000)}`);
        return fin(500);
      }
      return fin(202, "aceptado");
    }
    return fin(404, "No encontrado");
  } catch (e) {
    console.error(`[hooks] ${req.method} ${req.url}: ${e.message}`);
    if (!res.headersSent) return fin(500);
    try { res.end(); } catch { /* conexión rota */ }
  }
});

server.listen(PORT, HOST, () => console.log(`viz-hooks on http://${HOST}:${PORT}`));

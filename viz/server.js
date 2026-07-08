#!/usr/bin/env node
// On-demand UI server — a tiny HTTP server (Node stdlib, zero npm deps) that
// renders persisted "UIs" from the read-only bash/ data scripts, styled with
// TailwindCSS and driven by Datastar over SSE.
//
//   GET  /            master-detail shell (left: UI list, right: pane)
//   GET  /u/:id       standalone full-page render of one UI (URL-addressable)
//   GET  /ui/:id      SSE: patch #pane (+ #ui-list active state)
//   POST /ui          create a UI from the "new UI" form, then patch the DOM
//   POST /ui/:id/archive|unarchive   soft-hide/restore a UI (never deletes)
//   GET  /c/:component/frag/:name    SSE fragment of one component (paso 3)
//   POST /c/:component/act/:name     write action of one component (paso 3)
//   (legacy aliases /task/:id, /task/:id/edit, /meeting/:id, POST /task/:tid/io/…
//    translate onto the same dispatch — see aliasRoute)
//   GET  /health      liveness
//
// Run:  npm run viz   (PORT env overrides the default 4317)

const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const store = require("./lib/store");
const { shell, listPanel } = require("./lib/html");
const { renderPane, getComponent, overridableFor, dispatch, validateSpec, escape } = require("./lib/components");
const { makeRunner } = require("./lib/actions");
const { startSSE, patchElements } = require("./lib/sse");

const PORT = Number(process.env.PORT) || 4317;

// The whitelist of vendored assets under viz/public/ that /:name serves.
const PUBLIC_FILES = new Set(["/datastar.js", "/chart.umd.js", "/charts-init.js"]);

function send(res, status, body, type = "text/html; charset=utf-8") {
  res.writeHead(status, { "Content-Type": type });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = "";
    req.on("data", (c) => (data += c));
    req.on("end", () => resolve(data));
  });
}

function parseJsonBody(raw) {
  try {
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {}; // malformed body → treated as empty (legacy behavior)
  }
}

// Legacy aliases — the pre-paso-3 URLs (which the markup still emits) mapped
// onto the generic dispatch: (component, frag|act, name, path params). This
// table is frozen: new components get their routes from /c/… automatically
// and never touch this file.
function aliasRoute(pathname, method) {
  let m;
  if (method === "GET" && (m = /^\/task\/([^/]*)$/.exec(pathname)))
    return { comp: "task-detail", kind: "frag", name: "panel", extra: { id: m[1] } };
  if (method === "GET" && (m = /^\/task\/([^/]+)\/edit$/.exec(pathname)))
    return { comp: "task-edit-form", kind: "frag", name: "form", extra: { id: m[1] } };
  if (method === "GET" && (m = /^\/task\/([^/]+)\/io\/([^/]+)\/sqlrun$/.exec(pathname)))
    return { comp: "task-edit-form", kind: "frag", name: "sqlprev", extra: { io: m[2] } };
  if (method === "GET" && (m = /^\/meeting\/(.*)$/.exec(pathname)))
    return { comp: "meeting-detail", kind: "frag", name: "panel", extra: { id: m[1] } };
  if (method === "POST" && (m = /^\/task\/([^/]+)\/io\/add$/.exec(pathname)))
    return { comp: "task-edit-form", kind: "act", name: "io-add", extra: { task: m[1] } };
  if (method === "POST" && (m = /^\/task\/([^/]+)\/io\/([^/]+)\/field\/([^/]+)$/.exec(pathname)))
    return { comp: "task-edit-form", kind: "act", name: "io-field", extra: { task: m[1], io: m[2], field: m[3] } };
  if (method === "POST" && (m = /^\/task\/([^/]+)\/io\/([^/]+)\/(delete|unbind|bind|sql|sqlui)$/.exec(pathname)))
    return { comp: "task-edit-form", kind: "act", name: `io-${m[3]}`, extra: { task: m[1], io: m[2] } };
  return null;
}

// The dispatch tail shared by /c/… and the aliases. Builds the handler ctx
// (params, parsed body, the manifest-enforced runner, the left-panel refresher)
// and streams each returned patch over SSE. Handlers never see req/res.
async function runDispatch(req, res, url, comp, kind, name, extra) {
  const mod = getComponent(comp);
  if (!mod) return send(res, 404, "Not found", "text/plain");
  const params = new URLSearchParams(url.searchParams);
  for (const [k, v] of Object.entries(extra || {})) params.set(k, decodeURIComponent(v));
  const body = req.method === "POST" ? parseJsonBody(await readBody(req)) : null;
  const ctx = {
    params,
    body,
    run: makeRunner(mod.manifest),
    refreshUiList: (activeId) => listPanel(store.list(), activeId),
  };
  const patches = await dispatch(comp, kind, name, ctx);
  if (patches == null) return send(res, 404, "Not found", "text/plain");
  startSSE(res);
  for (const p of patches) patchElements(res, p);
  return res.end();
}

// Overlay query params onto a copy of the UI's stored params, so a page's
// controls can re-render with new values without mutating the saved spec.
// The whitelist is per-page now: the component's manifest declares exactly
// which params the browser may override (paso 3) — nothing leaks between
// pages, and `query` (persisted-only SQL) is un-overridable by construction
// because no manifest declares it.
function withParamOverrides(ui, searchParams) {
  if (!ui) return ui;
  const params = { ...(ui.params || {}) };
  for (const key of overridableFor(ui)) {
    const v = searchParams.get(key);
    if (v != null && v !== "") params[key] = v;
  }
  return { ...ui, params };
}

function standalone(ui) {
  const pane = renderPane(ui);
  return `<!doctype html><html lang="es" class="h-full"><head>
    <meta charset="utf-8" /><meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${ui ? ui.name : "UI no encontrada"} · Hermético</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script type="module" src="/datastar.js"></script>
    <script defer src="/chart.umd.js"></script>
    <script type="module" src="/charts-init.js"></script>
  </head><body class="h-full"><div class="flex h-screen bg-white text-slate-900">${pane}</div></body></html>`;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const { pathname } = url;

  try {
    // --- health ---
    if (pathname === "/health") return send(res, 200, "ok", "text/plain");

    // --- vendored static assets (Datastar + Chart.js + glue, served locally to avoid CDN/CORS) ---
    if (PUBLIC_FILES.has(pathname) && req.method === "GET") {
      const file = path.join(__dirname, "public", pathname.slice(1));
      const body = fs.readFileSync(file);
      res.writeHead(200, {
        "Content-Type": "text/javascript; charset=utf-8",
        "Cache-Control": "public, max-age=86400",
      });
      return res.end(body);
    }

    // --- full shell ---
    if (pathname === "/" && req.method === "GET") {
      const uis = store.list();
      const activeId = url.searchParams.get("ui");
      const active = activeId ? store.get(activeId) : null;
      return send(res, 200, shell({ uis, activeId: active?.id, paneHtml: renderPane(active) }));
    }

    // --- standalone single-UI page ---
    if (pathname.startsWith("/u/") && req.method === "GET") {
      const id = pathname.slice(3);
      const ui = withParamOverrides(store.get(id), url.searchParams);
      return send(res, ui ? 200 : 404, standalone(ui));
    }

    // --- generic component routes (paso 3) ---
    // GET /c/:component/frag/:name · POST /c/:component/act/:name — the
    // component's frags/acts maps own the handlers; server.js never grows a
    // route per component again.
    if (pathname.startsWith("/c/")) {
      const seg = pathname.split("/"); // ["","c",comp,kind,name]
      const comp = decodeURIComponent(seg[2] || "");
      const kind = seg[3];
      const name = decodeURIComponent(seg[4] || "");
      const kindOk = (req.method === "GET" && kind === "frag") || (req.method === "POST" && kind === "act");
      if (kindOk && seg.length === 5 && comp && name) {
        return await runDispatch(req, res, url, comp, kind, name, null);
      }
      return send(res, 404, "Not found", "text/plain");
    }

    // --- legacy aliases (/task/…, /meeting/…) → same dispatch ---
    const alias = aliasRoute(pathname, req.method);
    if (alias) {
      return await runDispatch(req, res, url, alias.comp, alias.kind, alias.name, alias.extra);
    }

    // --- archive / unarchive a UI (soft-hide: the spec file is never deleted) ---
    if (pathname.startsWith("/ui/") && req.method === "POST") {
      const [id, action] = pathname.slice(4).split("/");
      if (action !== "archive" && action !== "unarchive") return send(res, 404, "Not found", "text/plain");
      (action === "archive" ? store.archive : store.unarchive)(id);
      startSSE(res);
      patchElements(res, listPanel(store.list(), url.searchParams.get("active") || undefined));
      return res.end();
    }

    // --- SSE: render a UI into the pane ---
    if (pathname.startsWith("/ui/") && req.method === "GET") {
      const id = pathname.slice(4);
      const ui = withParamOverrides(store.get(id), url.searchParams);
      startSSE(res);
      patchElements(res, renderPane(ui));
      patchElements(res, listPanel(store.list(), ui?.id));
      return res.end();
    }

    // --- create a UI ---
    if (pathname === "/ui" && req.method === "POST") {
      const raw = await readBody(req);
      let signals = {};
      try {
        signals = raw ? JSON.parse(raw) : {};
      } catch {
        /* ignore malformed body */
      }
      // Validate BEFORE persisting; at creation, warnings count as errors too
      // (an old saved spec may carry unknown params, a new one must not).
      const candidate = { name: signals.name, component: "table", source: signals.source || "tasks", params: {} };
      const v = validateSpec(candidate);
      const issues = [...v.errors, ...v.warnings];
      if (issues.length) {
        startSSE(res);
        patchElements(
          res,
          `<section id="pane" class="flex-1 p-8"><div class="max-w-xl rounded-lg border border-red-200 bg-red-50 text-red-700 p-4 text-sm">
            <p class="font-semibold mb-1">Spec inválida — no se creó la UI</p>
            <ul class="list-disc list-inside text-xs space-y-0.5">${issues.map((e) => `<li>${escape(e)}</li>`).join("")}</ul>
          </div></section>`
        );
        return res.end();
      }
      const ui = store.create(candidate);
      startSSE(res);
      patchElements(res, listPanel(store.list(), ui.id));
      patchElements(res, renderPane(ui));
      return res.end();
    }

    return send(res, 404, "Not found", "text/plain");
  } catch (e) {
    return send(res, 500, `Error: ${e.message}`, "text/plain");
  }
});

// (Seeds live in git now: viz/specs/org/ IS the genome — no runtime seeding.)

// Boot sweep — validate every stored spec against this genome and log what
// doesn't fit (the embryo of the elevation rail's checks: the same
// validateSpec that gates the form and degrades the render).
for (const ui of store.list()) {
  const v = validateSpec(ui);
  for (const e of v.errors) console.warn(`[spec ${ui.id} «${ui.name}»] ERROR: ${e}`);
  for (const w of v.warnings) console.warn(`[spec ${ui.id} «${ui.name}»] aviso: ${w}`);
}

server.listen(PORT, () => {
  console.log(`viz on http://localhost:${PORT}`);
});

#!/usr/bin/env node
// On-demand UI server — a tiny HTTP server (Node stdlib, zero npm deps) that
// renders persisted "UIs" from the read-only bash/ data scripts, styled with
// TailwindCSS and driven by Datastar over SSE.
//
//   GET  /            master-detail shell (left: UI list, right: pane)
//   GET  /u/:id       standalone full-page render of one UI (URL-addressable)
//   GET  /ui/:id      SSE: patch #pane (+ #ui-list active state)
//   POST /ui          create a UI from the "new UI" form, then patch the DOM
//   GET  /health      liveness
//
// Run:  npm run viz   (PORT env overrides the default 4317)

const http = require("node:http");
const store = require("./lib/store");
const { shell, listPanel } = require("./lib/html");
const { renderPane, renderTaskDetail } = require("./lib/components");
const { startSSE, patchElements } = require("./lib/sse");

const PORT = Number(process.env.PORT) || 4317;

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

// Overlay whitelisted query params (project/from/to) onto a copy of the UI's
// stored params, so the dashboard's controls can re-render with new values
// without mutating the saved spec.
function withParamOverrides(ui, searchParams) {
  if (!ui) return ui;
  const params = { ...(ui.params || {}) };
  for (const key of ["project", "from", "to", "macro", "status", "priority", "assignee", "due", "open", "limit"]) {
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
    <script type="module" src="https://cdn.jsdelivr.net/gh/starfederation/datastar@v1.0.0/bundles/datastar.js"></script>
  </head><body class="h-full"><div class="flex h-screen bg-white text-slate-900">${pane}</div></body></html>`;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const { pathname } = url;

  try {
    // --- health ---
    if (pathname === "/health") return send(res, 200, "ok", "text/plain");

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

    // --- SSE: render one task's detail into #task-detail ---
    if (pathname.startsWith("/task/") && req.method === "GET") {
      const id = decodeURIComponent(pathname.slice(6));
      startSSE(res);
      patchElements(res, renderTaskDetail(id));
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
      const ui = store.create({ name: signals.name, source: signals.source || "tasks" });
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

store.seedIfEmpty();
server.listen(PORT, () => {
  console.log(`viz on http://localhost:${PORT}`);
});

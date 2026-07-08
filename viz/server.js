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
//   GET  /health      liveness
//
// Run:  npm run viz   (PORT env overrides the default 4317)

const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const store = require("./lib/store");
const { shell, listPanel } = require("./lib/html");
const { renderPane, renderTaskDetail, renderTaskEditForm, renderMeetingDetail, renderSqlPreview } = require("./lib/components");
const { sqlTitle } = require("./lib/artifacts");
const { REPO_ROOT, fetchSource } = require("./lib/datasources");
const meetico = require("./lib/meetico");
const { startSSE, patchElements } = require("./lib/sse");

// Best-effort human title from a meetico ResolvedArtifact: prefer explicit
// metadata (Drive `name`, Notion `title`), else parse a web page's <title>.
function resolvedTitle(r) {
  if (!r) return null;
  const m = r.metadata || {};
  const meta = m.name || m.title || m.displayName;
  if (meta) return String(meta).trim();
  if (r.content_text) {
    const t = /<title[^>]*>([^<]+)<\/title>/i.exec(r.content_text);
    if (t) return t[1].trim();
  }
  return null;
}

// Locate one IO row within a task → { kind, artifact_type_id, project_id }.
// Used by the bind route to derive the meetico request from just (tid, ioId).
function locateIo(tid, ioId) {
  let d;
  try {
    d = fetchSource("task_detail", { id: tid }).rows[0];
  } catch {
    return null;
  }
  if (!d) return null;
  const find = (arr, kind) => (arr || []).filter((r) => r.id === ioId).map((r) => ({ kind, artifact_type_id: r.artifact_type_id, project_id: d.project_id }))[0];
  return find(d.inputs, "inputs") || find(d.outputs, "outputs") || null;
}

// Run the IO write script (the ONLY write path in the viz). Returns its parsed
// JSON result ({ok, task_id, ...} or {ok:false, error}). Mirrors the read-only
// data policy: nothing but a whitelisted bash/ script ever touches the DB.
function runIoEdit(args) {
  const script = path.join(REPO_ROOT, "bash", "tasks", "update_task_io.sh");
  const parseLast = (s) => {
    const line = String(s || "").trim().split("\n").filter(Boolean).pop();
    if (!line) return null;
    try {
      return JSON.parse(line);
    } catch {
      return null;
    }
  };
  try {
    const out = execFileSync("bash", [script, ...args, "--json"], { encoding: "utf8", cwd: REPO_ROOT });
    return parseLast(out) || { ok: true };
  } catch (e) {
    // fail() prints its JSON to stdout then exits non-zero (→ e.stdout).
    return parseLast(e.stdout) || { ok: false, error: (e.stderr && String(e.stderr)) || e.message };
  }
}

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

// Overlay whitelisted query params (project/from/to) onto a copy of the UI's
// stored params, so the dashboard's controls can re-render with new values
// without mutating the saved spec.
function withParamOverrides(ui, searchParams) {
  if (!ui) return ui;
  const params = { ...(ui.params || {}) };
  // `db`/`table` drive the localdb explorer's selection. `query` is deliberately
  // NOT overridable: persisted-only SQL (see the localdb_query source).
  for (const key of ["project", "from", "to", "macro", "role", "status", "priority", "assignee", "due", "open", "limit", "has_report", "sort", "dir", "db", "table", "by", "kind"]) {
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

    // --- task detail + IO editor (SSE patches #task-detail) ---
    // GET  /task/:id              read-only detail panel
    // GET  /task/:id/edit         editable IO form
    // POST /task/:tid/io/add?kind=inputs|outputs            add a blank IO row
    // POST /task/:tid/io/:ioId/field/:field?value=…         retype/rename/required
    // POST /task/:tid/io/:ioId/sql   {query} body           persist a SQL binding
    // GET  /task/:tid/io/:ioId/sqlrun                       preview the query's rows
    // POST /task/:tid/io/:ioId/sqlui                        materialize it as a saved UI
    // POST /task/:tid/io/:ioId/delete                       remove an IO row
    if (pathname.startsWith("/task/")) {
      const seg = pathname.split("/").map((s) => decodeURIComponent(s)); // ["","task",id,...]
      const id = seg[2] || "";
      const rest = seg.slice(3);

      if (req.method === "GET" && rest.length === 0) {
        startSSE(res);
        patchElements(res, renderTaskDetail(id));
        return res.end();
      }
      if (req.method === "GET" && rest.length === 1 && rest[0] === "edit") {
        startSSE(res);
        patchElements(res, renderTaskEditForm(id));
        return res.end();
      }
      // GET /task/:tid/io/:ioId/sqlrun — run the PERSISTED query (provenance:
      // only SQL already in the DB row executes) and patch a preview table.
      if (req.method === "GET" && rest[0] === "io" && rest[2] === "sqlrun") {
        startSSE(res);
        patchElements(res, renderSqlPreview(rest[1]));
        return res.end();
      }
      if (req.method === "POST" && rest[0] === "io") {
        const value = url.searchParams.get("value") ?? "";
        let result = null;
        if (rest[1] === "add") {
          const kind = url.searchParams.get("kind") === "outputs" ? "output" : "input";
          result = runIoEdit(["--add", kind, "--task", id]);
        } else if (rest[1]) {
          const ioId = rest[1];
          if (rest[2] === "delete") {
            result = runIoEdit(["--delete", "--io", ioId]);
          } else if (rest[2] === "unbind") {
            result = runIoEdit(["--io", ioId, "--ref-clear"]);
          } else if (rest[2] === "bind") {
            // Binding goes through meetico (resolver + credentials), not the DB.
            let notice;
            try {
              const loc = locateIo(id, ioId);
              if (!loc) throw new Error("IO no encontrado");
              if (!loc.artifact_type_id) throw new Error("Elegí un Artifact antes de vincular");
              if (!value.trim()) throw new Error("Pegá un enlace o ID");
              const body = { artifact_type_id: loc.artifact_type_id, url: value.trim() };
              if (loc.project_id) body.project_id = loc.project_id;
              const prev = await meetico.bindPreview(body).catch(() => null);
              await meetico.bind(loc.kind, ioId, body);
              const r = prev && prev.resolved;
              // Cache the resolved title/url into the reference so the chip shows
              // the instance name without re-resolving on every render.
              const title = resolvedTitle(r);
              runIoEdit(["--io", ioId, "--ref-merge", JSON.stringify({ _resolved: { title, url: (r && r.url) || null, exists: !!(r && r.exists) } })]);
              if (r && r.exists) notice = { kind: "ok", text: `Vinculado ✓ ${title || r.url || ""}`.trim() };
              else if (r && r.error) notice = { kind: "warn", text: `Vinculado, pero no resolvió: ${r.error}` };
              else notice = { kind: "ok", text: "Vinculado ✓" };
            } catch (e) {
              notice = { kind: "err", text: e.message };
            }
            startSSE(res);
            patchElements(res, renderTaskEditForm(id, notice));
            return res.end();
          } else if (rest[2] === "sqlui") {
            // Materialize this SQL binding as a saved UI: generic `table`
            // component over the io_query source. Idempotent per IO row.
            let notice;
            try {
              const d = fetchSource("task_detail", { id }).rows[0];
              const row = [...((d && d.inputs) || []), ...((d && d.outputs) || [])].find((r) => r.id === ioId);
              if (!row) throw new Error("IO no encontrado");
              const q = row.reference && typeof row.reference === "object" ? row.reference.query : null;
              if (!q) throw new Error("Guarda un SQL antes de abrirlo como UI");
              let ui = store.list().find((u) => u.source === "io_query" && u.params && u.params.io === ioId);
              if (ui && ui.archived_at) {
                ui = store.unarchive(ui.id);
                notice = { kind: "ok", text: `La UI «${ui.name}» estaba archivada — restaurada en el panel izquierdo` };
              } else if (ui) notice = { kind: "ok", text: `Ya existía la UI «${ui.name}» — está en el panel izquierdo` };
              else {
                ui = store.create({ name: sqlTitle(q) || `SQL · ${row.title}`, component: "table", source: "io_query", params: { io: ioId } });
                notice = { kind: "ok", text: `UI creada: «${ui.name}» — ábrela en el panel izquierdo` };
              }
              startSSE(res);
              patchElements(res, listPanel(store.list(), ui.id));
              patchElements(res, renderTaskEditForm(id, notice));
              return res.end();
            } catch (e) {
              notice = { kind: "err", text: e.message };
            }
            startSSE(res);
            patchElements(res, renderTaskEditForm(id, notice));
            return res.end();
          } else if (rest[2] === "sql") {
            // The SQL editor posts {query} as an explicit payload (not signals).
            const raw = await readBody(req);
            let q = "";
            try {
              q = String((raw ? JSON.parse(raw) : {}).query ?? "");
            } catch {
              /* malformed body → treated as empty */
            }
            let notice;
            if (!q.trim()) notice = { kind: "err", text: "El SQL está vacío — escribe la consulta antes de guardar." };
            else {
              const r = runIoEdit(["--io", ioId, "--ref-merge", JSON.stringify({ query: q })]);
              notice = r && r.ok === false ? { kind: "err", text: r.error } : { kind: "ok", text: "SQL guardado ✓" };
            }
            startSSE(res);
            patchElements(res, renderTaskEditForm(id, notice));
            return res.end();
          } else if (rest[2] === "field") {
            const flag = { title: "--title", io_type: "--io-type", artifact: "--artifact", required: "--required" }[rest[3]];
            result = flag ? runIoEdit(["--io", ioId, flag, value]) : { ok: false, error: `Campo inválido: ${rest[3]}` };
          }
        }
        const err = result && result.ok === false ? result.error : null;
        startSSE(res);
        patchElements(res, renderTaskEditForm(id, err));
        return res.end();
      }
      return send(res, 404, "Not found", "text/plain");
    }

    // --- SSE: render one meeting's report into #meeting-detail ---
    if (pathname.startsWith("/meeting/") && req.method === "GET") {
      const id = decodeURIComponent(pathname.slice(9));
      startSSE(res);
      patchElements(res, renderMeetingDetail(id));
      return res.end();
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

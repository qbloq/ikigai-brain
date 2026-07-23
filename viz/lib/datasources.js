// Datasources — the ONLY bridge between the viz server and the data layer.
//
// We never write SQL here. Each source shells out to one of the read-only
// bash/ scripts with --json (same connection policy as the rest of the repo:
// read-only, ikigaigm schema, America/Bogota). A source declares which query
// params it accepts and how each maps to a CLI flag, so nothing arbitrary ever
// reaches the shell.

const { execFileSync } = require("node:child_process");
const path = require("node:path");

const REPO_ROOT = path.resolve(__dirname, "..", "..");

// flag spec: { <queryParam>: "--flag" }  — booleans use { flag: "--x", bool: true }
// `emits` declares the semantic shape of the script's --json output — 'rows'
// (an array) or 'object' (one record) — so validateSpec() can match a source
// against what a page's manifest `consumes`. (Transport always normalizes to
// an array; this is the *contract*, not the wire format.)
const SOURCES = {
  tasks: {
    label: "Tareas",
    script: "bash/tasks/tasks.sh",
    emits: "rows",
    args: {
      status: "--status",
      priority: "--priority",
      project: "--project",
      assignee: "--assignee",
      due: "--due",
      limit: "--limit",
      open: { flag: "--open", bool: true },
    },
  },
  tasks_due: {
    label: "Tareas por vencimiento",
    script: "bash/tasks/tasks_due.sh",
    emits: "rows",
    // exactly one window flag is expected; pass e.g. ?window=overdue
    args: {
      window: { map: { today: "--today", tomorrow: "--tomorrow", yesterday: "--yesterday", "this-week": "--this-week", "next-week": "--next-week", overdue: "--overdue" } },
      all: { flag: "--all", bool: true },
    },
  },
  projects: { label: "Proyectos", script: "bash/tasks/projects.sh", emits: "rows", args: {}, cache: 60_000 },
  team: { label: "Equipo", script: "bash/tasks/team.sh", emits: "rows", args: { team: "--team" }, cache: 60_000 },
  task_stats: {
    label: "Estadísticas",
    script: "bash/tasks/task_stats.sh",
    emits: "rows",
    args: { by: "--by", open: { flag: "--open", bool: true } },
  },
  meetings: {
    label: "Reuniones",
    script: "bash/meetings/meetings.sh",
    emits: "rows",
    args: {
      project: "--project",
      status: "--status",
      from: "--from",
      to: "--to",
      limit: "--limit",
      has_report: { flag: "--has-report", bool: true },
    },
  },
  // Single team-meeting report (one JSON OBJECT = the report jsonb). `id` is a
  // positional arg; emits {} (rows:[]) when the meeting has no report yet.
  meeting_detail: {
    label: "Detalle de reunión",
    script: "bash/meetings/meeting_show.sh",
    emits: "object",
    args: { id: { positional: true } },
  },
  // Financial KPI dashboard. Emits a single JSON OBJECT (not a row array) — the
  // `dashboard` component reads it as one record. Params: project + date range.
  dashboard: {
    label: "Dashboard financiero",
    script: "bash/metrics/dashboard.sh",
    emits: "object",
    args: { project: "--project", from: "--from", to: "--to" },
  },
  sops: {
    label: "SOPs & Arquetipos",
    script: "bash/catalog/sops.sh",
    emits: "rows",
    args: { macro: "--macro" },
    cache: 60_000,
  },
  // Health + findings of the ontology itself. Reads the BUILT graph artifacts
  // (docs/graph/*.json), so it is cheap and safe to cache: it only changes when
  // the graph is rebuilt, and rebuilding is what refreshes this dashboard.
  ontologia: {
    label: "Ontología (salud y hallazgos)",
    script: "bash/graph/ontology_stats.sh",
    emits: "object",
    args: {},
    cache: 60_000,
  },
  // Single task detail (one JSON object). `id` is a positional arg (no flag).
  task_detail: {
    label: "Detalle de tarea",
    script: "bash/tasks/task_detail.sh",
    emits: "object",
    args: { id: { positional: true } },
  },
  // Notion: all BD Avances tasks for a project "brief" page (positional page
  // id/url). Notion is slow (several API calls) and this data is semi-static, so
  // cache it — the notion-tasks component fetches ONCE and filters in the browser.
  notion_project_tasks: {
    label: "Tareas Notion (proyecto)",
    script: "bash/notion/project_tasks.sh",
    emits: "rows",
    args: { project: { positional: true } },
    cache: 120_000,
  },
  // The data of one "SQL Results" IO binding: executes the query persisted in
  // the row's artifact_reference (never SQL from the client — provenance lives
  // in the DB row). `io` is positional; `limit` caps rows. No cache: live data.
  io_query: {
    label: "Resultado SQL (artefacto IO)",
    script: "bash/tasks/run_io_query.sh",
    emits: "rows",
    args: { io: { positional: true }, limit: "--limit" },
  },
  // Reference data for the IO editor: { io_types[], artifact_types[] } as ONE
  // JSON object. Static/reference → short cache (the editor fetches it per form
  // render, so caching avoids re-querying the catalog on every IO edit).
  io_catalog: {
    label: "Catálogo IO",
    script: "bash/tasks/io_catalog.sh",
    emits: "object",
    args: {},
    cache: 60_000,
  },
  // --- Sales calls (meeting_type='call' — the closers' work product) --------
  // The closer is resolved through the CRM trace inside the scripts
  // (event->booking->contact_id → crm_contacts → crm_opportunities → users).
  calls: {
    label: "Llamadas de venta",
    script: "bash/calls/calls.sh",
    emits: "rows",
    args: {
      status: "--status",
      result: "--result",
      project: "--project",
      program: "--program",
      closer: "--closer",
      from: "--from",
      to: "--to",
      reported: { flag: "--reported", bool: true },
      sin_closer: { flag: "--sin-closer", bool: true },
      limit: "--limit",
    },
  },
  // One call with its full analysis report (header + raw report jsonb).
  call_detail: {
    label: "Detalle de llamada",
    script: "bash/calls/call_show.sh",
    emits: "object",
    args: { id: { positional: true } },
  },
  // Per-closer/result/program/project/week effectiveness aggregates.
  call_stats: {
    label: "Desempeño comercial",
    script: "bash/calls/call_stats.sh",
    emits: "rows",
    args: { by: "--by", project: "--project", from: "--from", to: "--to" },
  },
  // Objections flattened across call reports — the narrative feedback loop.
  call_objections: {
    label: "Objeciones (llamadas)",
    script: "bash/calls/call_objections.sh",
    emits: "rows",
    args: { project: "--project", closer: "--closer", status: "--status", from: "--from", to: "--to", limit: "--limit" },
  },
  // --- Ejecutivo domains (bash/ads, bash/finance, bash/crm) ------------------
  // Meta campaigns with project/currency and window performance. Money columns
  // are in the account's currency (`cur`) — the table shows it, never sum across.
  ad_campaigns: {
    label: "Pauta · campañas",
    script: "bash/ads/campaigns.sh",
    emits: "rows",
    args: {
      status: "--status",
      active: { flag: "--active", bool: true },
      project: "--project",
      account: "--account",
      from: "--from",
      to: "--to",
      with_spend: { flag: "--with-spend", bool: true },
      limit: "--limit",
    },
  },
  // Aggregated ads performance (spend/CTR/CPC/CPM/purchases/ROAS/CPA), grouped
  // per currency. `by: day|week` keeps chronological order (line-chart safe).
  ad_stats: {
    label: "Pauta · desempeño",
    script: "bash/ads/ad_stats.sh",
    emits: "rows",
    args: { by: "--by", project: "--project", account: "--account", campaign: "--campaign", from: "--from", to: "--to", limit: "--limit" },
  },
  // One campaign end-to-end: {campaign, totals, adsets[], ads[], daily[]} —
  // the future detail block of the «Pauta» master-detail. `id` is positional.
  ad_detail: {
    label: "Detalle de campaña",
    script: "bash/ads/ad_detail.sh",
    emits: "object",
    args: { id: { positional: true }, from: "--from", to: "--to", days: "--days" },
  },
  // The owner's portfolio: dashboard.sh KPIs for ALL projects + TOTAL row
  // (cash-collected model, USD; COP ad spend reported apart). Live — no cache.
  portfolio: {
    label: "Portafolio (todos los proyectos)",
    script: "bash/finance/portfolio.sh",
    emits: "rows",
    args: { from: "--from", to: "--to" },
  },
  // Uncollected installments with aging buckets; `summary` = buckets/project.
  cobranza: {
    label: "Cobranza (cuotas)",
    script: "bash/finance/cobranza.sh",
    emits: "rows",
    args: {
      overdue: { flag: "--overdue", bool: true },
      upcoming: "--upcoming",
      project: "--project",
      customer: "--customer",
      all: { flag: "--all", bool: true },
      summary: { flag: "--summary", bool: true },
      limit: "--limit",
    },
  },
  // Commission payouts with review state — the approval queue (pending first).
  comisiones: {
    label: "Comisiones (payouts)",
    script: "bash/finance/comisiones.sh",
    emits: "rows",
    args: { status: "--status", person: "--person", project: "--project", from: "--from", to: "--to", by: "--by", limit: "--limit" },
  },
  // Economics ledger: entradas vs opex/comisiones/reparto + neto per month.
  cashflow: {
    label: "Cashflow (ledger)",
    script: "bash/finance/cashflow.sh",
    emits: "rows",
    args: { by: "--by", project: "--project", from: "--from", to: "--to" },
  },
  // GHL opportunities: the pipeline board per stage (default), by status/month/
  // closer, or the raw list. Open opps carry value ≈ 0 — counts, not forecast.
  crm_pipeline: {
    label: "Pipeline CRM",
    script: "bash/crm/pipeline.sh",
    emits: "rows",
    args: {
      by: "--by",
      list: { flag: "--list", bool: true },
      project: "--project",
      status: "--status",
      stage: "--stage",
      from: "--from",
      to: "--to",
      limit: "--limit",
    },
  },
  // --- Google Drive / Docs / Sheets (bash/google/ — read-only) --------------
  // Auth is DB-borne (OAuth token in ikigaigm.identities, file-cached ~1h by
  // the lib), so calls after the first are sub-second. No cache here: Drive
  // content is live work product (docs being edited right now).
  drive_files: {
    label: "Drive · archivos",
    script: "bash/google/drive_ls.sh",
    emits: "rows",
    args: { folder: "--folder", q: "--q", type: "--type", limit: "--limit" },
  },
  drive_file: {
    label: "Drive · metadata de archivo",
    script: "bash/google/drive_file.sh",
    emits: "object",
    args: { id: { positional: true } },
  },
  // One Google Doc distilled to markdown: {id, markdown} (Drive export).
  gdoc: {
    label: "Google Doc (markdown)",
    script: "bash/google/doc_read.sh",
    emits: "object",
    args: { id: { positional: true } },
  },
  // One Sheet tab's values as rows (header row = keys). While the Sheets API
  // stays disabled in the OAuth project the script falls back to Drive CSV
  // export (first tab only — tab/range ignored there).
  gsheet: {
    label: "Google Sheet (valores)",
    script: "bash/google/sheet_read.sh",
    emits: "rows",
    args: { id: { positional: true }, tab: "--tab", range: "--range", limit: "--limit" },
  },
  // --- Local SQLite databases (data/sqlite/ — the user's OWN dbs) -----------
  // Same contract as every source (a bash script with --json), but against
  // local files instead of the remote Postgres: ~ms per call, so no cache —
  // freshness matters right after an import/exec.
  // Full inventory in ONE call: [{db, size_kb, modified, tables:[{name,rows}]}].
  localdbs: { label: "Bases locales (SQLite)", script: "bash/localdb/dbs.sh", emits: "rows", args: {} },
  // Rows of one table/view of a local db. The script validates the table name
  // against sqlite_master (exact match, identifier-quoted) — nothing arbitrary
  // ever becomes SQL. What the `localdb` explorer's preview consumes.
  localdb_table: {
    label: "Tabla local (SQLite)",
    script: "bash/localdb/db_table.sh",
    emits: "rows",
    args: { db: { positional: true }, table: { positional: true }, limit: "--limit" },
  },
  // A saved SQL query over one local db, rendered as a generic-table UI. The
  // `query` param comes ONLY from the persisted UI spec — withParamOverrides
  // never forwards it from the browser — mirroring io_query's provenance rule
  // (persisted SQL executes; client SQL never does). Connection is read-only.
  localdb_query: {
    label: "Consulta SQL local (SQLite)",
    script: "bash/localdb/db_query.sh",
    emits: "rows",
    args: { db: { positional: true }, query: { positional: true }, limit: "--limit" },
  },
};

function listSources() {
  return Object.entries(SOURCES).map(([id, s]) => ({ id, label: s.label }));
}

// Build the argv for a source from a plain params object, honoring the whitelist.
function buildArgs(spec, params) {
  const argv = ["--json"];
  for (const [key, def] of Object.entries(spec.args)) {
    const raw = params[key];
    if (raw == null || raw === "") continue;
    if (typeof def === "string") {
      argv.push(def, String(raw));
    } else if (def.positional) {
      argv.push(String(raw));
    } else if (def.bool) {
      if (raw === "1" || raw === "true" || raw === true) argv.push(def.flag);
    } else if (def.map) {
      const flag = def.map[String(raw)];
      if (flag) argv.push(flag);
    }
  }
  return argv;
}

// Connecting to the (remote) DB dominates render time (~0.8s/query), so a source
// may opt into a short in-memory TTL cache via `cache: <ms>`. Reserve it for
// reference/static data (the process ontology, projects, team) — NEVER for live
// operational views (tasks, dashboard), whose whole value is freshness. The
// cache is per-process: `npm run viz:restart` clears it.
const CACHE = new Map(); // key (id+params) -> { at, value }

// Fetch rows for a source. Returns { rows, label }. Throws on unknown source
// or non-JSON output (surfaced to the user instead of swallowed).
function fetchSource(id, params = {}) {
  const spec = SOURCES[id];
  if (!spec) throw new Error(`Fuente desconocida: ${id}`);
  const ttl = spec.cache || 0;
  const key = ttl ? `${id}:${JSON.stringify(params)}` : null;
  if (key) {
    const hit = CACHE.get(key);
    if (hit && Date.now() - hit.at < ttl) return hit.value;
  }
  const scriptPath = path.join(REPO_ROOT, spec.script);
  const argv = buildArgs(spec, params);
  let out;
  try {
    out = execFileSync("bash", [scriptPath, ...argv], {
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
      cwd: REPO_ROOT,
    });
  } catch (e) {
    throw new Error(`Fallo al ejecutar ${spec.script}: ${e.stderr || e.message}`);
  }
  const trimmed = out.trim();
  let rows;
  try {
    rows = trimmed ? JSON.parse(trimmed) : [];
  } catch {
    throw new Error(`Salida no-JSON de ${spec.script}: ${trimmed.slice(0, 200)}`);
  }
  if (!Array.isArray(rows)) rows = [rows];
  const value = { rows, label: spec.label };
  if (key) CACHE.set(key, { at: Date.now(), value });
  return value;
}

module.exports = { SOURCES, listSources, fetchSource, REPO_ROOT };

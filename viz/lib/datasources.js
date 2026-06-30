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
const SOURCES = {
  tasks: {
    label: "Tareas",
    script: "bash/tasks/tasks.sh",
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
    // exactly one window flag is expected; pass e.g. ?window=overdue
    args: {
      window: { map: { today: "--today", tomorrow: "--tomorrow", yesterday: "--yesterday", "this-week": "--this-week", "next-week": "--next-week", overdue: "--overdue" } },
      all: { flag: "--all", bool: true },
    },
  },
  projects: { label: "Proyectos", script: "bash/tasks/projects.sh", args: {}, cache: 60_000 },
  team: { label: "Equipo", script: "bash/tasks/team.sh", args: { team: "--team" }, cache: 60_000 },
  task_stats: {
    label: "Estadísticas",
    script: "bash/tasks/task_stats.sh",
    args: { by: "--by", open: { flag: "--open", bool: true } },
  },
  meetings: {
    label: "Reuniones",
    script: "bash/meetings/meetings.sh",
    args: { project: "--project", status: "--status", limit: "--limit" },
  },
  // Financial KPI dashboard. Emits a single JSON OBJECT (not a row array) — the
  // `dashboard` component reads it as one record. Params: project + date range.
  dashboard: {
    label: "Dashboard financiero",
    script: "bash/metrics/dashboard.sh",
    args: { project: "--project", from: "--from", to: "--to" },
  },
  sops: {
    label: "SOPs & Arquetipos",
    script: "bash/catalog/sops.sh",
    args: { macro: "--macro" },
    cache: 60_000,
  },
  // Single task detail (one JSON object). `id` is a positional arg (no flag).
  task_detail: {
    label: "Detalle de tarea",
    script: "bash/tasks/task_detail.sh",
    args: { id: { positional: true } },
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

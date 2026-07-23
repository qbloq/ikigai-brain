// Shared read-only DB access for the export scripts.
//
// Mirrors the connection policy of bash/lib/common.sh: every query runs
// read-only, scoped to the schema of this org, in the configured timezone.
// No external dependencies — we shell out to the `psql` client.

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const REPO_ROOT = path.resolve(__dirname, "..", "..");

// --- Read a key from the environment, falling back to .env ------------------
function loadEnv(key) {
  if (process.env[key]) return process.env[key];
  const envPath = path.join(REPO_ROOT, ".env");
  if (fs.existsSync(envPath)) {
    const re = new RegExp(`^\\s*${key}\\s*=\\s*(.*)\\s*$`);
    for (const line of fs.readFileSync(envPath, "utf8").split("\n")) {
      const m = line.match(re);
      if (m) return m[1].replace(/^["']|["']$/g, "");
    }
  }
  return null;
}

function requireEnv(key, what) {
  const v = loadEnv(key);
  if (!v) throw new Error(`${key} not set (${what}; expected in ${path.join(REPO_ROOT, ".env")})`);
  return v;
}

const DATABASE_URL = requireEnv("DATABASE_URL", "the org database connection string");
// The genome presupposes NO schema — each brain declares its own.
const SCHEMA = requireEnv("DB_SCHEMA", "the Postgres schema of this org");
const TZ = loadEnv("BRAIN_TZ") || "America/Bogota";

// Read-only, schema-scoped connection — same policy as common.sh.
const PGOPTIONS = [
  "-c default_transaction_read_only=on",
  `-c search_path=${SCHEMA},public`,
  `-c timezone=${TZ}`,
].join(" ");

// Run a query and return its single-cell text output (we always SELECT json).
function queryRaw(sql) {
  return execFileSync(
    "psql",
    [DATABASE_URL, "-v", "ON_ERROR_STOP=1", "--pset", "pager=off", "-tAc", sql],
    {
      encoding: "utf8",
      maxBuffer: 256 * 1024 * 1024,
      env: { ...process.env, PGOPTIONS },
    }
  );
}

function queryJson(sql) {
  const out = queryRaw(sql).trim();
  return out ? JSON.parse(out) : null;
}

// Today's date (YYYY-MM-DD) as the database sees it, in Bogota time.
function today() {
  return queryRaw("SELECT to_char(current_date,'YYYY-MM-DD')").trim();
}

// One fetch powers all three exports. Returns the full open-task universe,
// each task carrying its roles, todos and outputs/criteria. "Open" matches
// common.sh OPEN_PRED: not completed/cancelled and not is_completed.
function fetchTasks() {
  const sql = `
WITH base AS (
  SELECT t.id, t.title,
         t.status::text   AS status,
         t.priority::text AS priority,
         to_char(t.due_date,'YYYY-MM-DD') AS due,
         pr.name AS project_name
  FROM tasks t
  LEFT JOIN projects pr ON pr.id = t.project_id
  WHERE t.status NOT IN ('completed','cancelled')
    AND coalesce(t.is_completed,false) = false
),
roles AS (
  SELECT t.id,
         COALESCE(
           json_agg(DISTINCT tr.name ORDER BY tr.name)
             FILTER (WHERE tr.name IS NOT NULL),
           '[]'::json) AS roles
  FROM tasks t
  LEFT JOIN LATERAL unnest(t.assignee) aid ON true
  LEFT JOIN team_members tm ON tm.id = aid
  LEFT JOIN team_roles   tr ON tr.id = tm.role_id
  GROUP BY t.id
),
todos AS (
  SELECT task_id,
         json_agg(json_build_object('text', text, 'completed', completed)
                  ORDER BY position) AS todos
  FROM task_todos
  GROUP BY task_id
),
outs AS (
  SELECT o.task_id,
         json_agg(json_build_object(
           'output_label', o.title,
           'output_type',  it.name,
           'criteria',     COALESCE(c.criteria, '[]'::json)
         ) ORDER BY o.position) AS outputs
  FROM task_outputs o
  LEFT JOIN io_types it ON it.id = o.io_type_id
  LEFT JOIN LATERAL (
    SELECT json_agg(json_build_object(
             'criterion',           ac.criterion,
             'verification_method', ac.verification_method,
             'validator_id',        COALESCE(ac.validator->>'id', 'none'),
             'template_category',   COALESCE(ac.criterion_category, 'none'),
             'is_required',         ac.is_required,
             'pass_threshold',      ac.pass_threshold
           ) ORDER BY ac.position) AS criteria
    FROM task_acceptance_criteria ac
    WHERE ac.output_id = o.id
  ) c ON true
  GROUP BY o.task_id
)
SELECT COALESCE(json_agg(json_build_object(
         'id',           b.id,
         'title',        b.title,
         'status',       b.status,
         'priority',     b.priority,
         'due',          b.due,
         'project_name', b.project_name,
         'roles',        COALESCE(r.roles,  '[]'::json),
         'todos',        COALESCE(td.todos, '[]'::json),
         'outputs',      COALESCE(ou.outputs, '[]'::json)
       ) ORDER BY b.title), '[]'::json)
FROM base b
LEFT JOIN roles r  ON r.id = b.id
LEFT JOIN todos td ON td.task_id = b.id
LEFT JOIN outs  ou ON ou.task_id = b.id;`;
  return queryJson(sql);
}

module.exports = { fetchTasks, today, REPO_ROOT, SCHEMA };

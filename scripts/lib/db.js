// Shared read-only DB access for the export scripts.
//
// Mirrors the connection policy of bash/lib/common.sh: every query runs
// read-only, scoped to the ikigaigm schema, in America/Bogota time.
// No external dependencies — we shell out to the `psql` client.

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const REPO_ROOT = path.resolve(__dirname, "..", "..");

// --- Load DATABASE_URL from .env (only if not already in the environment) ---
function loadDatabaseUrl() {
  if (process.env.DATABASE_URL) return process.env.DATABASE_URL;
  const envPath = path.join(REPO_ROOT, ".env");
  if (fs.existsSync(envPath)) {
    for (const line of fs.readFileSync(envPath, "utf8").split("\n")) {
      const m = line.match(/^\s*DATABASE_URL\s*=\s*(.*)\s*$/);
      if (m) return m[1].replace(/^["']|["']$/g, "");
    }
  }
  throw new Error(`DATABASE_URL not set (expected in ${envPath})`);
}

const DATABASE_URL = loadDatabaseUrl();
const TZ = process.env.IKIGAIGM_TZ || "America/Bogota";

// Read-only, schema-scoped, Bogota-time connection — same policy as common.sh.
const PGOPTIONS = [
  "-c default_transaction_read_only=on",
  "-c search_path=ikigaigm,public",
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
  FROM ikigaigm.tasks t
  LEFT JOIN ikigaigm.projects pr ON pr.id = t.project_id
  WHERE t.status NOT IN ('completed','cancelled')
    AND coalesce(t.is_completed,false) = false
),
roles AS (
  SELECT t.id,
         COALESCE(
           json_agg(DISTINCT tr.name ORDER BY tr.name)
             FILTER (WHERE tr.name IS NOT NULL),
           '[]'::json) AS roles
  FROM ikigaigm.tasks t
  LEFT JOIN LATERAL unnest(t.assignee) aid ON true
  LEFT JOIN ikigaigm.team_members tm ON tm.id = aid
  LEFT JOIN ikigaigm.team_roles   tr ON tr.id = tm.role_id
  GROUP BY t.id
),
todos AS (
  SELECT task_id,
         json_agg(json_build_object('text', text, 'completed', completed)
                  ORDER BY position) AS todos
  FROM ikigaigm.task_todos
  GROUP BY task_id
),
outs AS (
  SELECT o.task_id,
         json_agg(json_build_object(
           'output_label', o.title,
           'output_type',  it.name,
           'criteria',     COALESCE(c.criteria, '[]'::json)
         ) ORDER BY o.position) AS outputs
  FROM ikigaigm.task_outputs o
  LEFT JOIN ikigaigm.io_types it ON it.id = o.io_type_id
  LEFT JOIN LATERAL (
    SELECT json_agg(json_build_object(
             'criterion',           ac.criterion,
             'verification_method', ac.verification_method,
             'validator_id',        COALESCE(ac.validator->>'id', 'none'),
             'template_category',   COALESCE(ac.criterion_category, 'none'),
             'is_required',         ac.is_required,
             'pass_threshold',      ac.pass_threshold
           ) ORDER BY ac.position) AS criteria
    FROM ikigaigm.task_acceptance_criteria ac
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

module.exports = { fetchTasks, today, REPO_ROOT };

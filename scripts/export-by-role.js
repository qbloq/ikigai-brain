#!/usr/bin/env node
// Regenerate backups/tasks-by-role/ — one markdown file per role (derived from
// each assignee's team role), plus an index. A task assigned to several roles
// is listed under each, so role counts sum to more than the task total.
//
// Usage:  node scripts/export-by-role.js [--project NAME] [outDir]
//         --project NAME  only tasks of that project (name fragment, e.g. "David
//                         Guerrero"). Output defaults to a per-project subdir
//                         backups/tasks-by-role/<project-slug> so the global
//                         export is left untouched.
//         outDir          override the output directory.
//         (default outDir: backups/tasks-by-role)

const fs = require("node:fs");
const path = require("node:path");
const { fetchTasks, today, REPO_ROOT, SCHEMA } = require("./lib/db");
const { slug, isOpen, byPriorityThenTitle, STATUS_ORDER, buildDoc } = require("./lib/render");

const UNASSIGNED = "Unassigned";

// Parse argv: optional --project/-p NAME and an optional positional outDir.
function parseArgs(argv) {
  let project = null;
  let outDir = null;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--project" || a === "-p") project = argv[++i];
    else if (a.startsWith("--project=")) project = a.slice("--project=".length);
    else if (!a.startsWith("-")) outDir = a;
    else throw new Error(`Unknown arg: ${a}`);
  }
  return { project, outDir };
}

// Resolve a project name fragment against the tasks' project_name values.
// Returns the canonical name, or throws (listing options) on no/ambiguous match.
function resolveProject(tasks, fragment) {
  const names = [...new Set(tasks.map((t) => t.project_name).filter(Boolean))].sort();
  const f = fragment.toLowerCase();
  const matches = names.filter((n) => n.toLowerCase().includes(f));
  if (matches.length === 0)
    throw new Error(`No project matches "${fragment}". Available: ${names.join(", ")}`);
  if (matches.length > 1)
    throw new Error(`"${fragment}" is ambiguous: ${matches.join(", ")}`);
  return matches[0];
}

function statusSort(a, b) {
  const ia = STATUS_ORDER.indexOf(a);
  const ib = STATUS_ORDER.indexOf(b);
  if (ia !== -1 && ib !== -1) return ia - ib;
  if (ia !== -1) return -1;
  if (ib !== -1) return 1;
  return a.localeCompare(b);
}

function main() {
  const { project: projectArg, outDir: outDirArg } = parseArgs(process.argv.slice(2));
  const td = today();

  let tasks = fetchTasks();
  let projectLabel = null;
  if (projectArg) {
    projectLabel = resolveProject(tasks, projectArg);
    tasks = tasks.filter((t) => t.project_name === projectLabel);
  }

  const gen =
    `Generated ${td} from live DB (${SCHEMA} schema)` +
    (projectLabel ? ` — project: ${projectLabel}` : "");

  const baseDir = path.join(REPO_ROOT, "backups", "tasks-by-role");
  const outDir = outDirArg || (projectLabel ? path.join(baseDir, slug(projectLabel)) : baseDir);

  // Bucket tasks by role (Unassigned when a task has no role).
  const byRole = new Map();
  for (const t of tasks) {
    const roles = t.roles && t.roles.length ? t.roles : [UNASSIGNED];
    for (const role of roles) {
      if (!byRole.has(role)) byRole.set(role, []);
      byRole.get(role).push(t);
    }
  }

  // Stable, fresh output dir.
  fs.rmSync(outDir, { recursive: true, force: true });
  fs.mkdirSync(outDir, { recursive: true });

  const roleNames = [...byRole.keys()].sort((a, b) => a.localeCompare(b));
  const indexRows = [];

  for (const role of roleNames) {
    const roleTasks = byRole.get(role);
    const open = roleTasks.filter(isOpen).length;

    // Group by status, in a sensible order, tasks sorted within each group.
    const statuses = [...new Set(roleTasks.map((t) => t.status))].sort(statusSort);
    const sections = statuses.map((status) => ({
      title: status,
      tasks: roleTasks.filter((t) => t.status === status).sort(byPriorityThenTitle),
    }));

    const doc = buildDoc({
      title: `${role} ${"—"} Tasks`,
      gen,
      total: roleTasks.length,
      open,
      sections,
      taskOpts: { showDue: true, showRoles: false },
    });

    const file = `${slug(role)}.md`;
    fs.writeFileSync(path.join(outDir, file), doc);
    indexRows.push({ role, count: roleTasks.length, file });
  }

  // index.md
  const index = [
    `# Tasks by Role${projectLabel ? ` — ${projectLabel}` : ""}`,
    "",
    `_${gen} — ${tasks.length} tasks total_`,
    "",
    "| Role | Tasks | File |",
    "| --- | --: | --- |",
    ...indexRows.map((r) => `| ${r.role} | ${r.count} | [${r.file}](${r.file}) |`),
    "",
    `> A task assigned to multiple roles is listed under each, so role counts sum to more than ${tasks.length}.`,
    "",
  ].join("\n");
  fs.writeFileSync(path.join(outDir, "index.md"), index);

  console.log(
    `Wrote ${path.relative(REPO_ROOT, outDir)}/ — ${roleNames.length} roles, ${tasks.length} tasks` +
      (projectLabel ? ` (project: ${projectLabel})` : "")
  );
}

try {
  main();
} catch (err) {
  console.error(`export-by-role: ${err.message}`);
  process.exit(1);
}

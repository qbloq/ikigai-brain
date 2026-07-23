#!/usr/bin/env node
// Regenerate backups/tasks.json — the structural dump of every open task with
// its outputs and acceptance criteria, straight from the live database.
//
// Usage:  node scripts/export-tasks-json.js [outFile]
//         (default outFile: backups/tasks.json)

const fs = require("node:fs");
const path = require("node:path");
const { fetchTasks, REPO_ROOT, SCHEMA } = require("./lib/db");

function main() {
  const outFile =
    process.argv[2] || path.join(REPO_ROOT, "backups", "tasks.json");

  const tasks = fetchTasks();

  let outputs = 0;
  let criteria = 0;
  const shaped = tasks.map((t) => {
    outputs += t.outputs.length;
    for (const o of t.outputs) criteria += o.criteria.length;
    return {
      id: t.id,
      title: t.title,
      project_name: t.project_name,
      outputs: t.outputs,
    };
  });

  const doc = {
    generated_at: new Date().toISOString(),
    source: `live DB (${SCHEMA} schema)`,
    stats: { tasks: shaped.length, outputs, criteria },
    tasks: shaped,
  };

  fs.mkdirSync(path.dirname(outFile), { recursive: true });
  fs.writeFileSync(outFile, JSON.stringify(doc, null, 2) + "\n");
  console.log(
    `Wrote ${path.relative(REPO_ROOT, outFile)} — ${shaped.length} tasks, ${outputs} outputs, ${criteria} criteria`
  );
}

main();

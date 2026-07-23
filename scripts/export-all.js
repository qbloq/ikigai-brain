#!/usr/bin/env node
// Regenerate every backup artifact in one go.
//   backups/tasks.json
//   backups/tasks-by-role/
//   backups/tasks-by-due-date/

const { execFileSync } = require("node:child_process");
const path = require("node:path");

for (const script of [
  "export-tasks-json.js",
  "export-by-role.js",
  "export-by-due-date.js",
]) {
  execFileSync("node", [path.join(__dirname, script)], { stdio: "inherit" });
}

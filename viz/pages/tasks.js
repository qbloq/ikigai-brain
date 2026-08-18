// tasks page — read-only instance of the master-detail pattern: the
// tasks-table master block over the `tasks` source, with the task-detail
// panel as detail slot. Replaces the old separate "abiertas" / "vencidas"
// UIs: "vencidas" is just due=overdue + open.

const pattern = require("../patterns/master-detail");
const tasksTable = require("../blocks/tasks-table");
const taskDetail = require("../blocks/task-detail");

function renderTasks(ui) {
  return pattern.render(ui, {
    master: { block: tasksTable, source: "tasks" },
    detail: { block: taskDetail },
  });
}

// The page's contract delegates to its master block (same filter bar).
module.exports = {
  id: "tasks",
  manifest: { consumes: "rows", overridable: tasksTable.manifest.overridable },
  render: renderTasks,
};

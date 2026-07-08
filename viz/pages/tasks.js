// tasks page — read-only instance of the master-detail pattern: one task list
// with a filter bar (status/priority/project/assignee/due/open); clicking a
// row opens the read-only detail panel (/task/:id). Replaces the old separate
// "abiertas" / "vencidas" UIs: "vencidas" is just due=overdue + open.

const { tasksMasterDetail } = require("../patterns/master-detail");

function renderTasks(ui) {
  return tasksMasterDetail(ui, false);
}

module.exports = { id: "tasks", render: renderTasks };

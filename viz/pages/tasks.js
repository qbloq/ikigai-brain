// tasks page — read-only instance of the master-detail pattern: one task list
// with a filter bar (status/priority/project/assignee/due/open); clicking a
// row opens the read-only detail panel (/task/:id). Replaces the old separate
// "abiertas" / "vencidas" UIs: "vencidas" is just due=overdue + open.

const { tasksMasterDetail } = require("../patterns/master-detail");

function renderTasks(ui) {
  return tasksMasterDetail(ui, false);
}

// manifest — the page's machine-checkable contract (docs/deltas-architecture.md):
// `consumes` must match the source's `emits`; `overridable` is exactly what the
// filter bar / sort headers re-fetch with (sort/dir are presentation-only).
module.exports = {
  id: "tasks",
  manifest: {
    consumes: "rows",
    overridable: ["status", "priority", "project", "assignee", "due", "open", "limit", "sort", "dir"],
  },
  render: renderTasks,
};

// task-editor page — editable instance of the master-detail pattern (the
// "Editor de IO" UI): same master list as `tasks`, but row click opens the
// editable IO-contract form (/task/:id/edit) — the viz's only write path.

const { tasksMasterDetail } = require("../patterns/master-detail");

function renderTaskEditor(ui) {
  return tasksMasterDetail(ui, true);
}

// Same contract as `tasks` (same master list); the write path belongs to the
// task-edit-form BLOCK's manifest (its acts declare the script), not the page.
module.exports = {
  id: "task-editor",
  manifest: {
    consumes: "rows",
    overridable: ["status", "priority", "project", "assignee", "due", "open", "limit", "sort", "dir"],
  },
  render: renderTaskEditor,
};

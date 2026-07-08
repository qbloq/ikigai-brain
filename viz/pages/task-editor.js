// task-editor page — editable instance of the master-detail pattern (the
// "Editor de IO" UI): same master list as `tasks`, but row click opens the
// editable IO-contract form (/task/:id/edit) — the viz's only write path.

const { tasksMasterDetail } = require("../patterns/master-detail");

function renderTaskEditor(ui) {
  return tasksMasterDetail(ui, true);
}

module.exports = { id: "task-editor", render: renderTaskEditor };

// task-editor page — editable instance of the master-detail pattern (the
// "Editor de IO" UI): same master block as `tasks`, but rows open the
// task-edit-form detail block (its `form` frag) — the viz's only write path
// (declared in that block's manifest.writes, enforced by ctx.run()).

const pattern = require("../patterns/master-detail");
const tasksTable = require("../blocks/tasks-table");
const taskEditForm = require("../blocks/task-edit-form");

function renderTaskEditor(ui) {
  return pattern.render(ui, {
    master: { block: tasksTable, source: "tasks" },
    detail: { block: taskEditForm },
  });
}

module.exports = {
  id: "task-editor",
  manifest: { consumes: "rows", overridable: tasksTable.manifest.overridable },
  render: renderTaskEditor,
};

// Shared markdown rendering helpers for the by-role / by-due-date exports.
// The formats here are reproduced exactly from the originals in backups/.

const SEP = " · "; // " · " middle dot, the field separator
const DASH = "—"; // "—" em dash (used in headings and for empty roles)

// Filename slug: "Director Comercial" -> "director-comercial", "Diseño" -> "diseno".
function slug(name) {
  return name
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "") // strip diacritics
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

// Whole-day difference between two YYYY-MM-DD strings (b - a), tz-independent.
function dayDiff(a, b) {
  const d = (s) => Date.UTC(+s.slice(0, 4), +s.slice(5, 7) - 1, +s.slice(8, 10));
  return Math.round((d(b) - d(a)) / 86400000);
}

// Relative label for a due date vs today: "(today)", "(in 3d)", "(2d ago)".
function relLabel(due, today) {
  const n = dayDiff(today, due);
  if (n === 0) return "today";
  return n > 0 ? `in ${n}d` : `${-n}d ago`;
}

const PRIORITY_RANK = { High: 3, Medium: 2, Low: 1 };
const STATUS_ORDER = ["in_progress", "pending", "blocked", "completed", "cancelled"];

function isOpen(task) {
  return (
    task.status !== "completed" &&
    task.status !== "cancelled" &&
    !task.is_completed
  );
}

// Priority desc, then title asc — the ordering used inside every group.
function byPriorityThenTitle(a, b) {
  const p = (PRIORITY_RANK[b.priority] || 0) - (PRIORITY_RANK[a.priority] || 0);
  return p !== 0 ? p : a.title.localeCompare(b.title);
}

// Render one task as its markdown block: a checkbox line, a detail line, and
// one nested line per todo. Returns an array of lines (no trailing blank).
//   showDue   — include "due YYYY-MM-DD" (role files; date is implicit elsewhere)
//   showRoles — append "roles: …" (due-date files; redundant in role files)
function renderTask(task, { showDue, showRoles }) {
  const box = isOpen(task) ? "[ ]" : "[x]";
  const lines = [`- ${box} ${task.title}  `];

  const parts = [`**${task.priority}**`, `\`${task.status}\``];
  if (showDue && task.due) parts.push(`due ${task.due}`);
  parts.push(`project: ${task.project_name || "(none)"}`);
  if (showRoles) {
    const roles = task.roles && task.roles.length ? task.roles.join(", ") : DASH;
    parts.push(`roles: ${roles}`);
  }
  lines.push(`  ${parts.join(SEP)}`);

  for (const todo of task.todos || []) {
    lines.push(`    - [${todo.completed ? "x" : " "}] ${todo.text}`);
  }
  return lines;
}

// Assemble a document. `sections` is an array of { title, tasks } already in
// the desired order; pass null to render a flat list with no "## " headings.
function buildDoc({ title, gen, total, open, sections, flatTasks, taskOpts }) {
  const lines = [`# ${title}`, "", `_${gen}_`, "", `**${total} tasks** (${open} open)`, ""];

  if (sections) {
    for (const sec of sections) {
      lines.push(""); // second blank line => two blanks before each "## "
      lines.push(`## ${sec.title}`);
      lines.push("");
      for (const t of sec.tasks) lines.push(...renderTask(t, taskOpts));
    }
  } else {
    for (const t of flatTasks) lines.push(...renderTask(t, taskOpts));
  }
  return lines.join("\n") + "\n";
}

module.exports = {
  SEP,
  DASH,
  slug,
  dayDiff,
  relLabel,
  isOpen,
  byPriorityThenTitle,
  STATUS_ORDER,
  renderTask,
  buildDoc,
};

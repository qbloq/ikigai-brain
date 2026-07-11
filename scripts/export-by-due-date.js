#!/usr/bin/env node
// Regenerate backups/tasks-by-due-date/ — open tasks bucketed by due date.
//
//   index.md        rolling-window buckets (overdue / today / this week / next week)
//   1-overdue.md    due before today
//   2-today.md      due today
//   3-this-week.md  due in the next 6 days
//   4-next-week.md  due 7–13 days out
//   by-date/        one folder per exact due date, plus its own index
//
// Usage:  node scripts/export-by-due-date.js [outDir]
//         (default outDir: backups/tasks-by-due-date)

const fs = require("node:fs");
const path = require("node:path");
const { fetchTasks, today, REPO_ROOT } = require("./lib/db");
const { dayDiff, relLabel, isOpen, byPriorityThenTitle, buildDoc } = require("./lib/render");

function main() {
  const outDir =
    process.argv[2] || path.join(REPO_ROOT, "backups", "tasks-by-due-date");
  const td = today();
  const gen = `Generated for ${td} from live DB (ikigaigm schema)`;
  const taskOpts = { showDue: false, showRoles: true };

  // Only dated tasks land in these views.
  const tasks = fetchTasks().filter((t) => t.due);

  // Group tasks by exact due date; sort the tasks inside each date.
  const byDate = new Map();
  for (const t of tasks) {
    if (!byDate.has(t.due)) byDate.set(t.due, []);
    byDate.get(t.due).push(t);
  }
  const dates = [...byDate.keys()].sort();
  for (const d of dates) byDate.get(d).sort(byPriorityThenTitle);

  // Each rolling-window bucket is a date range relative to today.
  const inBucket = {
    overdue: (n) => n < 0,
    today: (n) => n === 0,
    "this-week": (n) => n >= 1 && n <= 6,
    "next-week": (n) => n >= 7 && n <= 13,
  };

  fs.rmSync(outDir, { recursive: true, force: true });
  fs.mkdirSync(path.join(outDir, "by-date"), { recursive: true });

  // --- Bucket files ---------------------------------------------------------
  const buckets = [
    { key: "overdue", file: "1-overdue.md", title: "Overdue" },
    { key: "today", file: "2-today.md", title: "Today" },
    { key: "this-week", file: "3-this-week.md", title: "This Week" },
    { key: "next-week", file: "4-next-week.md", title: "Next Week" },
  ];

  const bucketStats = {};
  for (const b of buckets) {
    const bucketDates = dates.filter((d) => inBucket[b.key](dayDiff(td, d)));
    const sections = bucketDates.map((d) => ({
      title: `${d} (${relLabel(d, td)})`,
      tasks: byDate.get(d),
    }));
    const all = bucketDates.flatMap((d) => byDate.get(d));
    bucketStats[b.key] = { total: all.length, open: all.filter(isOpen).length };

    const doc = buildDoc({
      title: `${b.title} ${"—"} Tasks`,
      gen,
      total: all.length,
      open: all.filter(isOpen).length,
      sections,
      taskOpts,
    });
    fs.writeFileSync(path.join(outDir, b.file), doc);
  }

  // --- Per-exact-date files -------------------------------------------------
  const dateRows = [];
  for (const d of dates) {
    const dTasks = byDate.get(d);
    const open = dTasks.filter(isOpen).length;
    const doc = buildDoc({
      title: `${d} (${relLabel(d, td)}) ${"—"} Tasks`,
      gen,
      total: dTasks.length,
      open,
      flatTasks: dTasks,
      sections: null,
      taskOpts,
    });
    const dir = path.join(outDir, "by-date", d);
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "tasks.md"), doc);
    dateRows.push({ d, count: dTasks.length, open });
  }

  // by-date/index.md
  const byDateIndex = [
    "# Tasks by Date",
    "",
    `_${gen} — ${dates.length} dates_`,
    "",
    "| Date | Tasks | Open | File |",
    "| --- | --: | --: | --- |",
    ...dateRows.map(
      (r) => `| ${r.d} | ${r.count} | ${r.open} | [${r.d}/tasks.md](${r.d}/tasks.md) |`
    ),
    "",
  ].join("\n");
  fs.writeFileSync(path.join(outDir, "by-date", "index.md"), byDateIndex);

  // top-level index.md
  const index = [
    "# Tasks by Due Date",
    "",
    `_${gen} — ${tasks.length} tasks total_`,
    "",
    "| Bucket | Tasks | Open | File |",
    "| --- | --: | --: | --- |",
    `| Overdue | ${bucketStats.overdue.total} | ${bucketStats.overdue.open} | [1-overdue.md](1-overdue.md) |`,
    `| Today | ${bucketStats.today.total} | ${bucketStats.today.open} | [2-today.md](2-today.md) |`,
    `| This Week | ${bucketStats["this-week"].total} | ${bucketStats["this-week"].open} | [3-this-week.md](3-this-week.md) |`,
    `| Next Week | ${bucketStats["next-week"].total} | ${bucketStats["next-week"].open} | [4-next-week.md](4-next-week.md) |`,
    "",
    "Also broken down per exact date under [by-date/](by-date/index.md).",
    "",
  ].join("\n");
  fs.writeFileSync(path.join(outDir, "index.md"), index);

  console.log(
    `Wrote ${path.relative(REPO_ROOT, outDir)}/ — ${tasks.length} dated tasks across ${dates.length} dates`
  );
}

main();

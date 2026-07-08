// master-detail pattern — the first named pattern of the composition tower:
// a filterable master list on the left and an SSE-patched detail panel that
// slides in on row click. Owns the wiring (filter signals → @get re-fetch,
// row click → detail route, loading overlays); its instances fill the slots.
//
// Today it is task-specific (source `tasks`, blocks tasks-table +
// task-detail/task-edit-form): `edit=false` → read-only detail (page `tasks`);
// `edit=true` → editable IO form (page `task-editor`). The only differences
// are the row-click route (/task/:id vs /task/:id/edit), the detail-panel
// width, and which panel renderer seeds #task-detail. Filters/list are
// identical. Generalizing the slots (page `meetings` re-implements this shape
// by hand) is Fase 0 paso 4 — see docs/deltas-architecture.md.

const { fetchSource } = require("../lib/datasources");
const { escape, selectCtl } = require("../lib/kit");
const { tasksTable, STATUS_OPTS, PRIORITY_OPTS, DUE_OPTS } = require("../blocks/tasks-table");
const { renderTaskDetail } = require("../blocks/task-detail");
const { renderTaskEditForm } = require("../blocks/task-edit-form");

function tasksMasterDetail(ui, edit) {
  const p = ui.params || {};
  const head = `<header class="mb-4 flex items-baseline gap-3">
    <h1 class="text-xl font-semibold text-slate-800">${escape(ui.name)}</h1>
    <span id="tasks-meta" class="text-xs text-slate-400"></span>
    <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs text-indigo-600 hover:underline">abrir solo ↗</a>
  </header>`;

  let rows = [],
    err;
  try {
    ({ rows } = fetchSource("tasks", p));
  } catch (e) {
    err = e.message;
  }

  // options for the project/assignee selectors (cached reference sources)
  let projectOpts = [["", "Proyecto: todos"]];
  let memberOpts = [["", "Responsable: todos"]];
  try {
    projectOpts = projectOpts.concat(fetchSource("projects").rows.map((r) => [r.name, r.name]).filter(([n]) => n));
  } catch {
    /* keep the "todos" fallback */
  }
  try {
    memberOpts = memberOpts.concat(fetchSource("team").rows.map((r) => [r.name, r.name]).filter(([n]) => n));
  } catch {
    /* keep the "todos" fallback */
  }

  // presentation-only sort (never reaches the shell — buildArgs ignores it):
  // ?sort=title|due & ?dir=asc|desc, applied in JS over the fetched rows.
  const sortKey = p.sort === "title" || p.sort === "due" ? p.sort : "";
  const sortDir = p.dir === "desc" ? "desc" : "asc";
  if (sortKey && rows.length) {
    const mul = sortDir === "desc" ? -1 : 1;
    rows = [...rows].sort((a, b) => {
      const av = a[sortKey], bv = b[sortKey];
      if ((av == null || av === "") && (bv == null || bv === "")) return 0;
      if (av == null || av === "") return 1; // empties last, either direction
      if (bv == null || bv === "") return -1;
      return mul * String(av).localeCompare(String(bv), "es", { sensitivity: "base" });
    });
  }

  const openOn = p.open === "1" || p.open === "true";
  const reget =
    `@get('/ui/${escape(ui.id)}?limit=0&status='+$tStatus+'&priority='+$tPriority` +
    `+'&project='+encodeURIComponent($tProject)+'&assignee='+encodeURIComponent($tAssignee)` +
    `+'&due='+$tDue+'&open='+$tOpen+'&sort='+$tSort+'&dir='+$tDir)`;

  const sig = `{tStatus:'${escape(p.status || "")}',tPriority:'${escape(p.priority || "")}',tProject:'${escape(p.project || "")}',tAssignee:'${escape(p.assignee || "")}',tDue:'${escape(p.due || "")}',tOpen:${openOn},tSort:'${escape(sortKey)}',tDir:'${escape(sortDir)}'}`;

  const controls = `<div class="flex flex-wrap items-center gap-2 mb-4" data-signals="${sig}">
    ${selectCtl("tStatus", p.status || "", STATUS_OPTS, reget)}
    ${selectCtl("tPriority", p.priority || "", PRIORITY_OPTS, reget)}
    ${selectCtl("tProject", p.project || "", projectOpts, reget)}
    ${selectCtl("tAssignee", p.assignee || "", memberOpts, reget)}
    ${selectCtl("tDue", p.due || "", DUE_OPTS, reget)}
    <label class="flex items-center gap-2 text-sm text-slate-600 px-2">
      <input type="checkbox" data-bind="tOpen" data-on:change="${reget}" data-indicator:loadingtasks class="rounded border-slate-300" /> Solo abiertas
    </label>
  </div>`;

  const body = err
    ? `<div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-4 text-sm">${escape(err)}</div>`
    : `<div class="relative">
        <div id="tasks-loading" data-class:on="$loadingtasks" class="pointer-events-none absolute inset-0 z-10 flex items-start justify-center pt-16 bg-white/50">
          <div class="w-7 h-7 rounded-full border-2 border-slate-300 border-t-indigo-600 animate-spin"></div>
        </div>
        <p class="text-xs text-slate-400 mb-2">${rows.length} tarea(s)</p>${tasksTable(rows, edit, { key: sortKey, dir: sortDir, reget })}
      </div>`;

  // master-detail inside the pane. #detail-wrap PERSISTS (never replaced by SSE)
  // so its width/opacity transition fires every open/close; only its inner
  // #task-detail is swapped by the /task/:id route. Closed by default; the
  // .is-open class (base CSS = closed) avoids a Tailwind w-0/w-96 conflict and
  // a load-time flash. `detailOpen` lives on #pane, which resets on filter.
  return `<section id="pane" class="flex-1 overflow-hidden flex" data-signals="{detailOpen:false,selectedTask:''}">
    <style>
      #detail-wrap{width:0;opacity:0;overflow:hidden;transition:width .3s ease-in-out,opacity .3s ease-in-out;}
      #detail-wrap.is-open{width:${edit ? "34rem" : "24rem"};opacity:1;border-left:1px solid rgb(226 232 240);}
      #detail-loading,#tasks-loading{opacity:0;transition:opacity .2s ease;}
      #detail-loading.on,#tasks-loading.on{opacity:1;}
      tr.row-sel{background:rgb(238 242 255)!important;box-shadow:inset 3px 0 0 rgb(79 70 229);}
    </style>
    <div class="flex-1 p-6 overflow-auto bg-slate-50">${head}${controls}${body}</div>
    <aside id="detail-wrap" data-class:is-open="$detailOpen" class="relative shrink-0 bg-white">
      <div id="detail-loading" data-class:on="$loading" class="pointer-events-none absolute inset-0 z-10 flex items-center justify-center bg-white/50">
        <div class="w-7 h-7 rounded-full border-2 border-slate-300 border-t-indigo-600 animate-spin"></div>
      </div>
      ${edit ? renderTaskEditForm("") : renderTaskDetail("")}
    </aside>
  </section>`;
}

module.exports = { tasksMasterDetail };

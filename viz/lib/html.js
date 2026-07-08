// Shell + left-panel markup. The page is a master-detail layout:
//   left  <aside id="ui-list">  — the list of saved UIs + a "new UI" form
//   right <section id="pane">    — the selected UI, rendered on demand
// Datastar swaps #pane (and #ui-list) via SSE; no full page reloads.

const { escape } = require("./kit");
const { listSources } = require("./datasources");

// Temporarily hide the "Nueva UI" form in the left panel (feature paused).
// Flip back to true to restore it.
const SHOW_NEW_UI_FORM = false;

function listPanel(uis, activeId) {
  const act = activeId ? `?active=${escape(activeId)}` : "";

  // One row per UI: the whole row opens it; the hover icon archives/restores.
  // Archived rows still open on click — archiving is a soft-hide, never a delete.
  const row = (u, archived) => {
    const active = u.id === activeId;
    const action = archived
      ? { url: `/ui/${escape(u.id)}/unarchive${act}`, title: "Restaurar", icon: "↩" }
      : { url: `/ui/${escape(u.id)}/archive${act}`, title: "Archivar", icon: "⤓" };
    return `<li class="group relative">
      <button data-on:click="window.history.replaceState(null,'','?ui=${escape(u.id)}'); @get('/ui/${escape(u.id)}')" data-indicator:navloading
        class="w-full text-left px-3 py-2 pr-8 rounded-md text-sm transition ${
          active ? "bg-indigo-600 text-white" : archived ? "text-slate-400 hover:bg-slate-200" : "text-slate-700 hover:bg-slate-200"
        }">
        <span class="block truncate">${escape(u.name)}</span>
        <span class="block text-xs ${active ? "text-indigo-100" : "text-slate-400"}">${escape(u.source)}</span>
      </button>
      <button title="${action.title}" data-on:click="@post('${action.url}')"
        class="absolute right-1.5 top-1/2 -translate-y-1/2 hidden group-hover:block leading-none ${
          active ? "text-indigo-200 hover:text-white" : "text-slate-400 hover:text-indigo-600"
        }">${action.icon}</button>
    </li>`;
  };

  const live = uis.filter((u) => !u.archived_at);
  const archived = uis.filter((u) => u.archived_at);

  const items = live.length
    ? live.map((u) => row(u, false)).join("")
    : '<li class="px-3 py-2 text-sm text-slate-400 italic">Aún no hay UIs.</li>';

  const archivedSection = archived.length
    ? `<div class="border-t border-slate-200">
        <button data-on:click="$showarch=!$showarch"
          class="w-full flex items-center justify-between px-4 py-2 text-xs font-semibold text-slate-500 uppercase tracking-wide hover:bg-slate-200">
          <span>Archivadas · ${archived.length}</span>
          <span data-text="$showarch ? '▾' : '▸'">▸</span>
        </button>
        <ul data-show="$showarch" style="display:none" class="max-h-56 overflow-auto p-2 pt-0 space-y-1">${archived
          .map((u) => row(u, true))
          .join("")}</ul>
      </div>`
    : "";

  const sourceOptions = listSources()
    .map((s) => `<option value="${escape(s.id)}">${escape(s.label)}</option>`)
    .join("");

  const newUiForm = `<form data-on:submit__prevent="@post('/ui')" data-indicator:navloading class="border-t border-slate-200 p-3 space-y-2 bg-white">
      <p class="text-xs font-semibold text-slate-500 uppercase tracking-wide">Nueva UI</p>
      <input data-bind="name" placeholder="Nombre"
        class="w-full text-sm px-2 py-1.5 rounded border border-slate-300 focus:outline-none focus:ring-2 focus:ring-indigo-400" />
      <select data-bind="source"
        class="w-full text-sm px-2 py-1.5 rounded border border-slate-300 bg-white">${sourceOptions}</select>
      <button type="submit"
        class="w-full text-sm font-medium px-2 py-1.5 rounded bg-indigo-600 text-white hover:bg-indigo-700">+ Crear</button>
    </form>`;

  return `<aside id="ui-list" class="w-72 shrink-0 border-r border-slate-200 bg-slate-100 flex flex-col h-screen">
    <div class="px-4 py-3 border-b border-slate-200">
      <h2 class="font-semibold text-slate-800">UIs generadas</h2>
      <p class="text-xs text-slate-500">${live.length} guardada(s)</p>
    </div>
    <ul class="flex-1 overflow-auto p-2 space-y-1">${items}</ul>
    ${archivedSection}
    ${SHOW_NEW_UI_FORM ? newUiForm : ""}
  </aside>`;
}

function shell({ uis, activeId, paneHtml }) {
  return `<!doctype html>
<html lang="es" class="h-full">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>UI on-demand · Hermético</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <script type="module" src="/datastar.js"></script>
  <script defer src="/chart.umd.js"></script>
  <script type="module" src="/charts-init.js"></script>
  <style>
    /* Global page-switch overlay: transparent, blurred, fades in/out. Driven by
       $navloading (set true while a /ui/:id or /ui @get/@post is in flight). */
    #nav-loading{opacity:0;transition:opacity .2s ease;}
    #nav-loading.on{opacity:1;}
  </style>
</head>
<body class="h-full">
  <div class="flex h-screen bg-white text-slate-900" data-signals="{name:'',source:'tasks',navloading:false,showarch:false}">
    ${listPanel(uis, activeId)}
    ${paneHtml}
    <div id="nav-loading" data-class:on="$navloading"
      class="pointer-events-none fixed top-0 right-0 bottom-0 left-72 z-50 flex items-center justify-center bg-white/50 backdrop-blur-[1px]">
      <div class="w-9 h-9 rounded-full border-[3px] border-slate-300 border-t-indigo-600 animate-spin"></div>
    </div>
  </div>
</body>
</html>`;
}

module.exports = { shell, listPanel };

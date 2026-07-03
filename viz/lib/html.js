// Shell + left-panel markup. The page is a master-detail layout:
//   left  <aside id="ui-list">  — the list of saved UIs + a "new UI" form
//   right <section id="pane">    — the selected UI, rendered on demand
// Datastar swaps #pane (and #ui-list) via SSE; no full page reloads.

const { escape } = require("./components");
const { listSources } = require("./datasources");

// Temporarily hide the "Nueva UI" form in the left panel (feature paused).
// Flip back to true to restore it.
const SHOW_NEW_UI_FORM = false;

function listPanel(uis, activeId) {
  const items = uis.length
    ? uis
        .map((u) => {
          const active = u.id === activeId;
          return `<li>
            <button data-on:click="window.history.replaceState(null,'','?ui=${escape(u.id)}'); @get('/ui/${escape(u.id)}')" data-indicator:navloading
              class="w-full text-left px-3 py-2 rounded-md text-sm transition ${
                active ? "bg-indigo-600 text-white" : "text-slate-700 hover:bg-slate-200"
              }">
              <span class="block truncate">${escape(u.name)}</span>
              <span class="block text-xs ${active ? "text-indigo-100" : "text-slate-400"}">${escape(u.source)}</span>
            </button>
          </li>`;
        })
        .join("")
    : '<li class="px-3 py-2 text-sm text-slate-400 italic">Aún no hay UIs.</li>';

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
      <p class="text-xs text-slate-500">${uis.length} guardada(s)</p>
    </div>
    <ul class="flex-1 overflow-auto p-2 space-y-1">${items}</ul>
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
  <style>
    /* Global page-switch overlay: transparent, blurred, fades in/out. Driven by
       $navloading (set true while a /ui/:id or /ui @get/@post is in flight). */
    #nav-loading{opacity:0;transition:opacity .2s ease;}
    #nav-loading.on{opacity:1;}
  </style>
</head>
<body class="h-full">
  <div class="flex h-screen bg-white text-slate-900" data-signals="{name:'',source:'tasks',navloading:false}">
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

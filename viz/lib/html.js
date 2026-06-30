// Shell + left-panel markup. The page is a master-detail layout:
//   left  <aside id="ui-list">  — the list of saved UIs + a "new UI" form
//   right <section id="pane">    — the selected UI, rendered on demand
// Datastar swaps #pane (and #ui-list) via SSE; no full page reloads.

const { escape } = require("./components");
const { listSources } = require("./datasources");

function listPanel(uis, activeId) {
  const items = uis.length
    ? uis
        .map((u) => {
          const active = u.id === activeId;
          return `<li>
            <button data-on:click="window.history.replaceState(null,'','?ui=${escape(u.id)}'); @get('/ui/${escape(u.id)}')"
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

  return `<aside id="ui-list" class="w-72 shrink-0 border-r border-slate-200 bg-slate-100 flex flex-col h-screen">
    <div class="px-4 py-3 border-b border-slate-200">
      <h2 class="font-semibold text-slate-800">UIs generadas</h2>
      <p class="text-xs text-slate-500">${uis.length} guardada(s)</p>
    </div>
    <ul class="flex-1 overflow-auto p-2 space-y-1">${items}</ul>
    <form data-on:submit__prevent="@post('/ui')" class="border-t border-slate-200 p-3 space-y-2 bg-white">
      <p class="text-xs font-semibold text-slate-500 uppercase tracking-wide">Nueva UI</p>
      <input data-bind="name" placeholder="Nombre"
        class="w-full text-sm px-2 py-1.5 rounded border border-slate-300 focus:outline-none focus:ring-2 focus:ring-indigo-400" />
      <select data-bind="source"
        class="w-full text-sm px-2 py-1.5 rounded border border-slate-300 bg-white">${sourceOptions}</select>
      <button type="submit"
        class="w-full text-sm font-medium px-2 py-1.5 rounded bg-indigo-600 text-white hover:bg-indigo-700">+ Crear</button>
    </form>
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
</head>
<body class="h-full">
  <div class="flex h-screen bg-white text-slate-900" data-signals="{name:'',source:'tasks'}">
    ${listPanel(uis, activeId)}
    ${paneHtml}
  </div>
</body>
</html>`;
}

module.exports = { shell, listPanel };

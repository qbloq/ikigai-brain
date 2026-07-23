// table page — the generic fallback: any source rendered as a table with
// inferred columns. Also the registry's catch-all: an unknown component (or a
// spec with no component) lands here, preserving the original renderPane()
// semantics (table for "table"/empty, raw JSON <pre> otherwise).

const { fetchSource } = require("../lib/datasources");
const { escape, table } = require("../lib/kit");

function renderTable(ui) {
  let body;
  let meta = "";
  try {
    const { rows, label } = fetchSource(ui.source, ui.params || {});
    meta = `<span class="text-xs text-slate-400">${escape(label)} · ${rows.length} fila(s)</span>`;
    body = ui.component === "table" || !ui.component ? table(rows) : `<pre>${escape(JSON.stringify(rows, null, 2))}</pre>`;
  } catch (e) {
    body = `<div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-4 text-sm">${escape(e.message)}</div>`;
  }
  return `<section id="pane" class="flex-1 p-6 overflow-hidden flex flex-col">
    <header class="mb-4 flex items-baseline gap-3">
      <h1 class="text-xl font-semibold text-slate-800">${escape(ui.name)}</h1>
      ${meta}
      <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs text-indigo-600 hover:underline">abrir solo ↗</a>
    </header>
    ${body}
  </section>`;
}

// No overridable params: a generic table renders exactly its persisted spec.
module.exports = { id: "table", manifest: { consumes: "rows", overridable: [] }, render: renderTable };

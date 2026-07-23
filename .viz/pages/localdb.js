// localdb page — explore the user's LOCAL SQLite databases (data/sqlite/):
// left, every db with its tables and row counts; right, a preview of the
// selected table. Data flows through the `localdbs` + `localdb_table` sources
// (bash/localdb/ with --json) — the same read-only bash contract as every
// other page, just against local files instead of the remote Postgres, so
// every click is ~ms and nothing is cached.
//
// The selection travels as ?db=&table= (whitelisted in withParamOverrides),
// which makes any preview URL-addressable: /u/<id>?db=crm&table=leads.

const { fetchSource } = require("../lib/datasources");
const { escape, table } = require("../lib/kit");

const PREVIEW_LIMIT = 200;

function tableRow(ui, db, t, selected) {
  const url = `/ui/${escape(ui.id)}?db=${encodeURIComponent(db)}&table=${encodeURIComponent(t.name)}`;
  return `<li><button data-on:click="@get('${escape(url)}')" data-indicator:loadingdb
    class="w-full flex items-baseline gap-2 px-3 py-1.5 text-left rounded-md ${selected ? "bg-indigo-100 text-indigo-900 font-medium" : "text-slate-700 hover:bg-indigo-50"}"
    title="${escape(t.name)}">
    <span class="text-sm truncate flex-1">${escape(t.name)}</span>
    <span class="text-xs ${selected ? "text-indigo-500" : "text-slate-400"} shrink-0">${t.rows == null ? "?" : t.rows}</span>
  </button></li>`;
}

function dbBlock(ui, d, curDb, curTable) {
  const items = (d.tables || [])
    .map((t) => tableRow(ui, d.db, t, d.db === curDb && t.name === curTable))
    .join("");
  return `<div class="mb-4">
    <div class="flex items-baseline gap-2 px-3 py-1">
      <span class="font-mono text-xs font-semibold text-slate-500 uppercase tracking-wide">${escape(d.db)}</span>
      <span class="ml-auto text-[10px] text-slate-400" title="modificada ${escape(d.modified || "")}">${escape(String(d.size_kb ?? "?"))} KB</span>
    </div>
    <ul>${items || '<li class="px-3 py-1 text-xs text-slate-400 italic">Sin tablas.</li>'}</ul>
  </div>`;
}

// Empty state: the feature is CLI-first, so teach the two ways to get data in.
const EMPTY_HINT = `<div class="max-w-xl text-sm text-slate-600 space-y-3">
  <p class="text-slate-800 font-medium">Todavía no hay bases locales.</p>
  <p>Tus bases SQLite viven en <code class="font-mono text-xs bg-slate-100 rounded px-1.5 py-0.5">data/sqlite/</code>. Crea la primera desde la terminal:</p>
  <pre class="font-mono text-xs bg-slate-800 text-slate-100 rounded-lg p-3 overflow-x-auto">bash/localdb/db_exec.sh midb --create 'CREATE TABLE notas (id INTEGER PRIMARY KEY, texto TEXT)'
bash/localdb/db_import.sh midb datos.csv --create</pre>
  <p>Al recargar esta UI aparecerán aquí, con sus tablas listas para explorar.</p>
</div>`;

function renderLocaldb(ui) {
  const p = ui.params || {};
  const curDb = p.db || "";
  const curTable = p.table || "";

  const head = `<header class="mb-4 flex items-baseline gap-3">
    <h1 class="text-xl font-semibold text-slate-800">${escape(ui.name)}</h1>
    <span class="text-xs text-slate-400">data/sqlite/</span>
    <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs text-indigo-600 hover:underline">abrir solo ↗</a>
  </header>`;

  let dbs = [];
  let err;
  try {
    ({ rows: dbs } = fetchSource("localdbs", {}));
  } catch (e) {
    err = e.message;
  }
  if (err) {
    return `<section id="pane" class="flex-1 p-6 overflow-auto">${head}
      <div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-4 text-sm">${escape(err)}</div>
    </section>`;
  }
  if (!dbs.length) {
    return `<section id="pane" class="flex-1 p-6 overflow-auto bg-slate-50">${head}${EMPTY_HINT}</section>`;
  }

  // preview of the selected table (its own error box — a broken view/table
  // must not take the whole explorer down with it)
  let preview;
  if (curDb && curTable) {
    let body, meta = "";
    try {
      const { rows } = fetchSource("localdb_table", { db: curDb, table: curTable, limit: PREVIEW_LIMIT });
      meta = `${rows.length}${rows.length === PREVIEW_LIMIT ? "+" : ""} fila(s)${rows.length === PREVIEW_LIMIT ? ` · primeras ${PREVIEW_LIMIT}` : ""}`;
      body = table(rows);
    } catch (e) {
      body = `<div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-4 text-sm">${escape(e.message)}</div>`;
    }
    preview = `<div class="mb-3 flex items-baseline gap-2">
      <h2 class="font-mono text-sm font-semibold text-slate-700">${escape(curDb)}.${escape(curTable)}</h2>
      <span class="text-xs text-slate-400">${escape(meta)}</span>
    </div>${body}
    <p class="mt-3 text-[11px] text-slate-400 font-mono">bash/localdb/db_query.sh ${escape(curDb)} 'SELECT … FROM ${escape(curTable)}'</p>`;
  } else {
    preview = `<div class="h-full flex items-center justify-center text-slate-400 text-sm">
      <p>Selecciona una tabla en el panel izquierdo.</p></div>`;
  }

  // loading overlay over the preview while a table click re-fetches the pane
  // (the loaders convention: transparent bg-white/50 + spinner, .2s opacity)
  return `<section id="pane" class="flex-1 overflow-hidden flex">
    <style>
      #localdb-loading{opacity:0;transition:opacity .2s ease;}
      #localdb-loading.on{opacity:1;}
    </style>
    <aside class="w-64 shrink-0 border-r border-slate-200 bg-white overflow-auto p-3">
      ${dbs.map((d) => dbBlock(ui, d, curDb, curTable)).join("")}
    </aside>
    <div class="flex-1 relative overflow-auto p-6 bg-slate-50">
      <div id="localdb-loading" data-class:on="$loadingdb" class="pointer-events-none absolute inset-0 z-10 flex items-start justify-center pt-16 bg-white/50">
        <div class="w-7 h-7 rounded-full border-2 border-slate-300 border-t-indigo-600 animate-spin"></div>
      </div>
      ${head}${preview}
    </div>
  </section>`;
}

module.exports = {
  id: "localdb",
  manifest: { consumes: "rows", overridable: ["db", "table"] },
  render: renderLocaldb,
};

// sop-tree page — navigate the process ontology: macro-process → SOP →
// activity archetypes. Rows come from bash/catalog/sops.sh (one row per
// archetype). Renders a collapsible tree with native <details> (no JS), plus
// macro/role filters that re-fetch via Datastar @get (mirrors the dashboard
// pattern).

const { fetchSource } = require("../lib/datasources");
const { escape, groupBy } = require("../lib/kit");

function sopBlock(sopRows) {
  const s = sopRows[0];
  // archetype rows; a SOP with no archetypes comes back as a single null-archetype row
  const acts = sopRows.filter((r) => r.archetype);
  const items = acts.length
    ? acts
        .map((a) => {
          const gate = a.gate === true || a.gate === "t" || a.gate === "true";
          const n = Number(a.tasks) || 0;
          return `<li class="flex items-baseline gap-2 px-3 py-1.5 border-b border-slate-100 last:border-0 hover:bg-indigo-50/60">
            <span class="font-mono text-xs text-indigo-600 shrink-0 w-12">${escape(a.archetype)}</span>
            <span class="text-xs text-slate-400 shrink-0 w-28 truncate">${escape(a.verb)}</span>
            <span class="text-sm text-slate-700 flex-1">${escape(a.activity)}</span>
            ${gate ? '<span class="text-[10px] font-semibold uppercase tracking-wide text-amber-700 bg-amber-100 rounded px-1.5 py-0.5 shrink-0">gate</span>' : ""}
            <span class="text-xs ${n ? "text-slate-600" : "text-slate-300"} shrink-0 w-14 text-right" title="tareas que instancian este arquetipo">${n} ${n === 1 ? "tarea" : "tareas"}</span>
          </li>`;
        })
        .join("")
    : '<li class="px-3 py-2 text-sm text-slate-400 italic">Sin arquetipos.</li>';
  return `<details class="border border-slate-200 rounded-lg overflow-hidden bg-white">
    <summary class="cursor-pointer select-none px-3 py-2 bg-slate-50 hover:bg-slate-100 flex items-baseline gap-2">
      <span class="font-mono text-xs font-semibold text-slate-500 shrink-0">${escape(s.sop)}</span>
      <span class="text-sm font-medium text-slate-800">${escape(s.sop_name)}</span>
      <span class="text-xs text-slate-400">· ${acts.length} act.</span>
      ${s.roles ? `<span class="ml-auto text-xs text-slate-400 truncate max-w-[40%]" title="${escape(s.roles)}">${escape(s.roles)}</span>` : ""}
    </summary>
    <ul>${items}</ul>
  </details>`;
}

function macroBlock(macroRows) {
  const m = macroRows[0];
  const sops = groupBy(macroRows, (r) => r.sop);
  const nActs = macroRows.filter((r) => r.archetype).length;
  const blocks = sops.map(([, rows]) => sopBlock(rows)).join("");
  return `<details open class="mb-3">
    <summary class="cursor-pointer select-none px-3 py-2 rounded-lg bg-indigo-600 text-white flex items-baseline gap-2">
      <span class="font-mono text-sm font-bold shrink-0">${escape(m.macro)}</span>
      <span class="text-sm font-semibold">${escape(m.macro_name)}</span>
      <span class="ml-auto text-xs text-indigo-100">${sops.length} SOPs · ${nActs} act.</span>
    </summary>
    <div class="mt-2 space-y-2 pl-2 border-l-2 border-indigo-100">${blocks}</div>
  </details>`;
}

function renderSopTree(ui) {
  const head = `<header class="mb-4 flex items-baseline gap-3">
    <h1 class="text-xl font-semibold text-slate-800">${escape(ui.name)}</h1>
    <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs text-indigo-600 hover:underline">abrir solo ↗</a>
  </header>`;
  // Fetch the FULL catalog once (datasources caches it) and filter by macro in
  // JS — one query covers every macro, so flipping the dropdown is a cache hit.
  let all, err;
  try {
    ({ rows: all } = fetchSource(ui.source));
  } catch (e) {
    err = e.message;
  }
  if (err) {
    return `<section id="pane" class="flex-1 p-6 overflow-auto">${head}
      <div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-4 text-sm">${escape(err)}</div>
    </section>`;
  }

  // macro + role filters applied in JS over the cached catalog (no extra query).
  // A SOP's roles come as a comma-joined string of owner_roles; the role filter
  // keeps whole SOPs (roles are per-SOP, so every archetype row carries them).
  const current = (ui.params && ui.params.macro) || "";
  const curRole = (ui.params && ui.params.role) || "";
  let rows = current ? all.filter((r) => r.macro === current) : all;
  if (curRole) rows = rows.filter((r) => (r.roles || "").split(", ").includes(curRole));
  const macros = groupBy(all, (r) => r.macro).map(([code, rs]) => ({ code, name: rs[0].macro_name }));
  const roles = [...new Set(all.flatMap((r) => (r.roles || "").split(", ").filter(Boolean)))].sort((a, b) =>
    a.localeCompare(b, "es")
  );
  const reget = `@get('/ui/${escape(ui.id)}?macro='+$sopMacro+'&role='+encodeURIComponent($sopRole))`;
  const opts =
    `<option value="">Todos los macro-procesos</option>` +
    macros
      .map((m) => `<option value="${escape(m.code)}"${m.code === current ? " selected" : ""}>${escape(m.code)} · ${escape(m.name)}</option>`)
      .join("");
  const roleOpts =
    `<option value="">Todos los roles</option>` +
    roles
      .map((r) => `<option value="${escape(r)}"${r === curRole ? " selected" : ""}>${escape(r)}</option>`)
      .join("");
  const selectCls =
    "text-sm px-3 py-2 rounded-lg border border-slate-300 bg-white focus:outline-none focus:ring-2 focus:ring-indigo-400 font-medium";
  const controls = `<div class="mb-4 flex gap-2" data-signals="{sopMacro:'${escape(current)}',sopRole:'${escape(curRole)}'}">
    <select data-bind="sopMacro" data-on:change="${reget}" class="${selectCls}">${opts}</select>
    <select data-bind="sopRole" data-on:change="${reget}" class="${selectCls}">${roleOpts}</select>
  </div>`;

  const body = rows.length
    ? groupBy(rows, (r) => r.macro).map(([, rs]) => macroBlock(rs)).join("")
    : '<p class="text-slate-500 italic">Sin resultados.</p>';

  return `<section id="pane" class="flex-1 p-6 overflow-auto bg-slate-50">${head}${controls}${body}</section>`;
}

module.exports = {
  id: "sop-tree",
  manifest: { consumes: "rows", overridable: ["macro", "role"] },
  render: renderSopTree,
};

// task-edit-form block (#task-detail, "task-editor" pages) — editable form for
// one task's IO contract: per input/output you can retype the io_type and
// artifact_type, rename, toggle required, and add/remove rows. Every control
// persists immediately — one @post → update_task_io.sh (one txn) → the server
// re-renders this whole fragment. Controls bind to per-row signals and pass
// the chosen value (the type *id*) via the query string, mirroring the
// read-only filters' proven `@get('…?x='+$sig)` idiom. Header is read-only.

const { fetchSource } = require("../lib/datasources");
const { chipData, sqlTitle } = require("../lib/artifacts");
const { escape, cell, miniTable } = require("../lib/kit");
const { activityBlock, sourceBlock } = require("./task-detail");
const store = require("../lib/store");
const meetico = require("../lib/meetico");

// A uuid is not a valid signal identifier (dashes, may start with a digit), so
// strip to [a-z0-9] and prefix per field to namespace the row's signals.
function idsig(id) {
  return String(id).replace(/[^a-z0-9]/gi, "");
}

// The editor's inner SSE target. Fixed width (matches #detail-wrap.is-open 34rem)
// so content doesn't reflow while the panel animates open/closed.
function editPanelShell(inner) {
  return `<div id="task-detail" class="w-[34rem] h-full overflow-y-auto">${inner}</div>`;
}

function ioTypeOpts(cat) {
  return [["", "— sin tipo —"]].concat((cat.io_types || []).map((t) => [t.id, t.display_name]));
}
function artifactOpts(cat) {
  return [["", "— sin artifact —"]].concat((cat.artifact_types || []).map((t) => [t.id, t.display_name]));
}

// A select bound to `signal`, initialized (via the `selected` option) to the
// row's current type id; on change it @posts the chosen value.
function editSelect(signal, current, options, post) {
  const opts = options
    .map(([v, l]) => `<option value="${escape(v)}"${String(v) === String(current ?? "") ? " selected" : ""}>${escape(l)}</option>`)
    .join("");
  return `<select id="ioc-${signal}" data-bind="${signal}" data-on:change="${post}" data-indicator:loading
    class="w-full text-sm px-2 py-1.5 rounded-md border border-slate-300 bg-white focus:outline-none focus:ring-2 focus:ring-indigo-400">${opts}</select>`;
}

function ioEditRow(row, kind, tid, cat) {
  const sid = idsig(row.id);
  const base = `/task/${escape(tid)}/io/${escape(row.id)}`;
  const aname = (cat.artifact_types || []).find((a) => a.id === row.artifact_type_id)?.name;
  const titlePost = `@post('${base}/field/title?value='+encodeURIComponent($t_${sid}))`;
  const iotPost = `@post('${base}/field/io_type?value='+encodeURIComponent($iot_${sid}))`;
  const artPost = `@post('${base}/field/artifact?value='+encodeURIComponent($art_${sid}))`;
  const reqPost = `@post('${base}/field/required?value='+$req_${sid})`;
  const delPost = `@post('${base}/delete')`;
  const bindPost = `@post('${base}/bind?value='+encodeURIComponent($ref_${sid}))`;
  // Stable ids (keyed by the row uuid) so Datastar's idiomorph matches each row —
  // and each bound control — to itself across re-renders. Without them a row that
  // changes size (e.g. gains the binding chip) mis-aligns siblings and one row's
  // bound values bleed into another until the next full refresh.
  return `<div id="ioerow-${sid}" class="rounded-lg border border-slate-200 p-3 mb-2 bg-white">
    <div class="flex items-center gap-2 mb-2">
      <input id="iot-${sid}" data-bind="t_${sid}" value="${escape(row.title || "")}" data-on:change="${titlePost}" data-indicator:loading
        class="flex-1 text-sm font-medium px-2 py-1.5 rounded-md border border-slate-300 focus:outline-none focus:ring-2 focus:ring-indigo-400" placeholder="Título" />
      <div class="shrink-0 flex items-center">
        <button data-show="!$del_${sid}" data-on:click="$del_${sid}=true" title="Eliminar" class="text-slate-400 hover:text-red-600 px-1.5 text-lg leading-none">✕</button>
        <span data-show="$del_${sid}" class="inline-flex items-center gap-1.5 text-xs whitespace-nowrap">
          <span class="text-slate-500">¿Eliminar?</span>
          <button data-on:click="${delPost}" data-indicator:loading class="px-2 py-0.5 rounded bg-red-600 text-white hover:bg-red-700">Sí</button>
          <button data-on:click="$del_${sid}=false" class="px-2 py-0.5 rounded border border-slate-300 text-slate-600 hover:bg-slate-50">No</button>
        </span>
      </div>
    </div>
    <div class="grid grid-cols-2 gap-2">
      <div><label class="block text-[11px] text-slate-400 mb-0.5">Tipo (IO)</label>${editSelect(`iot_${sid}`, row.io_type_id, ioTypeOpts(cat), iotPost)}</div>
      <div><label class="block text-[11px] text-slate-400 mb-0.5">Artifact</label>${editSelect(`art_${sid}`, row.artifact_type_id, artifactOpts(cat), artPost)}</div>
    </div>
    <label class="flex items-center gap-2 text-xs text-slate-600 mt-2">
      <input id="ioq-${sid}" type="checkbox" data-bind="req_${sid}"${row.is_required ? " checked" : ""} data-on:change="${reqPost}" data-indicator:loading class="rounded border-slate-300" /> Requerido
    </label>
    <div class="mt-2 pt-2 border-t border-slate-100">
      <label class="block text-[11px] text-slate-400 mb-0.5">Vínculo (instancia del artifact)</label>
      ${bindingChip(row, base, cat)}
      ${
        aname === "sql_query"
          ? sqlEditor(row, sid, base)
          : `<div class="flex items-center gap-1.5">
        <input id="ioref-${sid}" data-bind="ref_${sid}" placeholder="Pegar enlace o ID…" data-indicator:loading
          class="flex-1 text-xs px-2 py-1.5 rounded-md border border-slate-300 focus:outline-none focus:ring-2 focus:ring-indigo-400" />
        <button data-on:click="${bindPost}; $ref_${sid}=''" data-indicator:loading class="shrink-0 text-xs px-2.5 py-1.5 rounded-md bg-indigo-600 text-white hover:bg-indigo-700">Vincular</button>
      </div>`
      }
    </div>
  </div>`;
}

// SQL Results binding editor: the instance of this artifact IS a query, so instead
// of the "pegar enlace" input it gets a collapsible monospace textarea persisted via
// POST …/sql → update_task_io.sh --ref-merge {query}. The signal is local
// (`_`-prefixed → excluded from requests by Datastar's default filterSignals), so
// the potentially-large SQL never rides along on filter re-fetches; the save @post
// ships it explicitly as the request payload instead.
function sqlEditor(row, sid, base) {
  const has = !!(row.reference && typeof row.reference === "object" && row.reference.query);
  const save = `@post('${base}/sql', {payload: {query: $_sqlq_${sid}}})`;
  return `<button data-on:click="$_sqlopen_${sid}=!$_sqlopen_${sid}" class="text-xs text-indigo-600 hover:text-indigo-800">
      <span data-show="!$_sqlopen_${sid}">${has ? "Ver / editar SQL ▸" : "＋ Escribir SQL"}</span>
      <span data-show="$_sqlopen_${sid}">Ocultar SQL ▾</span>
    </button>
    <div data-show="$_sqlopen_${sid}" class="mt-1.5">
      <textarea id="iosql-${sid}" data-bind="_sqlq_${sid}" rows="14" spellcheck="false" wrap="off" placeholder="SELECT …"
        class="w-full text-[11px] leading-4 font-mono px-2 py-1.5 rounded-md border border-slate-300 bg-slate-50 text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-400"></textarea>
      <div class="flex items-center gap-1.5 mt-1">
        <span class="text-[11px] text-slate-400 mr-auto">Read-only · 10s · máx 500 filas</span>
        <button data-on:click="@post('${base}/sqlui')" data-indicator:loading title="Crear una UI guardada (tabla) con el resultado completo"
          class="text-xs px-2 py-1 rounded-md border border-indigo-300 text-indigo-600 hover:bg-indigo-50">Abrir como UI</button>
        <button data-on:click="@get('${base}/sqlrun')" data-indicator:loading title="Ejecuta el SQL guardado y muestra las primeras filas"
          class="text-xs px-2 py-1 rounded-md border border-slate-300 text-slate-600 hover:bg-slate-50">Probar</button>
        <button data-on:click="${save}" data-indicator:loading class="text-xs px-2.5 py-1 rounded-md bg-indigo-600 text-white hover:bg-indigo-700">Guardar SQL</button>
      </div>
      <div id="sqlprev-${sid}" class="mt-2"></div>
    </div>`;
}

// The "Probar" preview: run the persisted query (via the io_query source → the
// whitelisted run_io_query.sh) and patch the first rows into #sqlprev-<sid>.
// Fetches one row past the cap to flag truncation without a count query.
const SQL_PREVIEW_ROWS = 20;
function renderSqlPreview(ioId) {
  const sid = idsig(ioId);
  let inner;
  try {
    const { rows } = fetchSource("io_query", { io: ioId, limit: SQL_PREVIEW_ROWS + 1 });
    const more = rows.length > SQL_PREVIEW_ROWS;
    const shown = more ? rows.slice(0, SQL_PREVIEW_ROWS) : rows;
    const caption = more ? `Primeras ${shown.length} filas — hay más (ábrelo como UI para ver hasta 500)` : `${shown.length} fila(s)`;
    inner = `<p class="text-[11px] text-slate-400 mb-1">${escape(caption)}</p>
      <div class="max-h-64 overflow-auto rounded-md border border-slate-200">${miniTable(shown)}</div>`;
  } catch (e) {
    inner = `<div class="rounded-md border border-red-200 bg-red-50 text-red-700 p-2 text-[11px] whitespace-pre-wrap break-words">${escape(e.message)}</div>`;
  }
  return `<div id="sqlprev-${sid}" class="mt-2">${inner}</div>`;
}

// Seed every row's bound signals with its CURRENT values. Without this, Datastar
// initializes each `data-bind` signal to empty and writes it back to the control,
// wiping the server-rendered selection/value (selects show blank, checkbox clears).
// data-signals uses if-missing semantics, so re-renders after an edit don't clobber
// the user's in-flight choices. Mirrors how the read-only filters pre-seed signals.
function editSignals(rows) {
  const o = {};
  for (const r of rows || []) {
    const s = idsig(r.id);
    o[`t_${s}`] = r.title || "";
    o[`iot_${s}`] = r.io_type_id || "";
    o[`art_${s}`] = r.artifact_type_id || "";
    o[`req_${s}`] = !!r.is_required;
    o[`del_${s}`] = false; // inline "¿Eliminar?" confirm toggle for this row
    o[`ref_${s}`] = ""; // the "pegar enlace/ID" binding input
    o[`_sqlq_${s}`] = (r.reference && typeof r.reference === "object" && typeof r.reference.query === "string" && r.reference.query) || "";
    o[`_sqlopen_${s}`] = false; // the SQL editor's expand/collapse toggle
  }
  return o;
}

// Current-binding chip: renders the bound instance via its per-artifact-type
// component (icon + title/name + link) instead of a raw id. The title comes from
// reference._resolved (cached at bind time). ↻ re-resolves (when there's a url),
// ✕ desvincula. Empty when the IO has no reference yet.
function bindingChip(row, base, cat) {
  const ref = row.reference;
  if (!ref || typeof ref !== "object" || Array.isArray(ref) || !Object.keys(ref).length) return "";
  const name = (cat.artifact_types || []).find((a) => a.id === row.artifact_type_id)?.name;
  const { icon, label, href } = chipData(name, ref);
  const inner = href
    ? `<a href="${escape(href)}" target="_blank" class="text-indigo-600 hover:underline truncate">${escape(label)}</a>`
    : `<span class="text-slate-600 truncate">${escape(label)}</span>`;
  const reBtn = href
    ? `<button data-on:click="@post('${base}/bind?value='+encodeURIComponent('${escape(href)}'))" data-indicator:loading title="Re-resolver" class="shrink-0 text-slate-400 hover:text-indigo-600 leading-none">↻</button>`
    : "";
  return `<div class="flex items-center gap-1.5 mb-1 text-xs bg-slate-50 border border-slate-200 rounded px-2 py-1">
    <span class="shrink-0" title="Vinculado">${icon}</span>
    ${inner}
    ${reBtn}
    <button data-on:click="@post('${base}/unbind')" data-indicator:loading title="Desvincular" class="shrink-0 text-slate-400 hover:text-red-600 leading-none">✕</button>
  </div>`;
}

function ioEditSection(title, rows, kind, tid, cat) {
  const list =
    (rows || []).map((r) => ioEditRow(r, kind, tid, cat)).join("") ||
    '<p class="text-xs text-slate-400 italic mb-2">— ninguno —</p>';
  const addPost = `@post('/task/${escape(tid)}/io/add?kind=${kind}')`;
  const noun = kind === "inputs" ? "input" : "output";
  return `<div class="mb-5">
    <h3 class="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2">${escape(title)} · ${(rows || []).length}</h3>
    ${list}
    <button data-on:click="${addPost}" data-indicator:loading class="text-xs text-indigo-600 hover:text-indigo-800 border border-dashed border-indigo-300 rounded-md px-2.5 py-1 mt-1">+ Agregar ${noun}</button>
  </div>`;
}

// Inline ID chip for the editor subtitle: shows only the short prefix, with an
// icon button that copies the FULL uuid to the clipboard (clipboard → check on
// success). Needs the `cp` signal seeded in the form's data-signals.
function idCopy(uuid, shortid) {
  const u = escape(uuid);
  // navigator.clipboard only exists in secure contexts (https / localhost); when
  // the viz is opened via LAN IP or an embedded webview it's undefined, so fall
  // back to a temp <textarea> + execCommand('copy'). $cp flips only on success.
  const click =
    `const ok = () => { $cp = true; setTimeout(() => $cp = false, 1200) };` +
    `const fb = () => { const a = document.createElement('textarea'); a.value = '${u}'; a.style.cssText = 'position:fixed;opacity:0'; document.body.appendChild(a); a.select(); const d = document.execCommand('copy'); a.remove(); if (d) ok() };` +
    `navigator.clipboard ? navigator.clipboard.writeText('${u}').then(ok, fb) : fb()`;
  return `<span class="inline-flex items-center gap-1 align-middle">
    <span class="font-mono text-slate-500">${escape(shortid)}</span>
    <button data-on:click="${click}" title="Copiar ID completo" class="text-slate-400 hover:text-indigo-600 leading-none">
      <svg data-show="!$cp" xmlns="http://www.w3.org/2000/svg" class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></svg>
      <svg data-show="$cp" xmlns="http://www.w3.org/2000/svg" class="w-3.5 h-3.5 text-emerald-600" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5 13l4 4L19 7"/></svg>
    </button>
  </span>`;
}

// notice: a string (→ error) OR { kind: 'ok'|'warn'|'err', text } for the banner.
function renderTaskEditForm(id, notice) {
  if (!id)
    return editPanelShell(
      `<div class="h-full flex items-center justify-center p-8 text-center text-sm text-slate-400"><p>Selecciona una tarea para editar su IO.</p></div>`
    );
  let d,
    cat = { io_types: [], artifact_types: [] },
    e2;
  try {
    d = fetchSource("task_detail", { id }).rows[0];
    cat = fetchSource("io_catalog").rows[0] || cat;
  } catch (e) {
    e2 = e.message;
  }
  if (e2 || !d) {
    return editPanelShell(
      `<div class="p-5"><div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-3 text-sm">${escape(e2 || "Tarea no encontrada")}</div></div>`
    );
  }
  const close = `<button data-on:click="$detailOpen=false; $selectedTask=''" class="ml-auto -mr-1 -mt-1 text-slate-400 hover:text-slate-600 text-lg leading-none" title="Cerrar">✕</button>`;
  const n = typeof notice === "string" ? { kind: "err", text: notice } : notice;
  const NOTE_CLS = {
    ok: "border-emerald-200 bg-emerald-50 text-emerald-700",
    warn: "border-amber-200 bg-amber-50 text-amber-700",
    err: "border-red-200 bg-red-50 text-red-700",
  };
  const errBanner =
    n && n.text ? `<div class="rounded-lg border ${NOTE_CLS[n.kind] || NOTE_CLS.err} p-2.5 text-xs mb-3 break-words">${escape(n.text)}</div>` : "";
  const header = `<div class="flex items-start gap-2 mb-1">${close}</div>
    <h2 class="text-base font-semibold text-slate-800 mb-1 -mt-6 pr-6">${escape(d.title)}</h2>
    <p class="text-xs text-slate-400 mb-3">${cell(d.project)} · ${idCopy(d.uuid || id, d.id || id)}</p>`;
  const sigObj = Object.assign(editSignals([...(d.inputs || []), ...(d.outputs || [])]), { cp: false });
  const signals = escape(JSON.stringify(sigObj));
  const inner = `<div class="p-5" data-signals="${signals}">
    ${header}
    ${sourceBlock(d.source)}
    ${activityBlock(d.archetype)}
    ${errBanner}
    ${ioEditSection("Inputs", d.inputs, "inputs", id, cat)}
    ${ioEditSection("Outputs", d.outputs, "outputs", id, cat)}
  </div>`;
  return editPanelShell(inner);
}

// ---------------------------------------------------------------------------
// Routed block (paso 3): the editor's SSE fragments and write acts, moved out
// of server.js. Handlers never touch req/res — they get ctx = { params, body,
// run, refreshUiList } and return HTML patches; the kernel owns the SSE.
// ctx.run() only executes scripts declared below in manifest.writes.
// Canonical routes: GET /c/task-edit-form/frag/form?id=… · POST
// /c/task-edit-form/act/io-field?task=…&io=…&field=…&value=… — aliases keep
// the legacy /task/:id/edit and POST /task/:tid/io/… URLs the markup emits.
// ---------------------------------------------------------------------------

const IO_SCRIPT = "bash/tasks/update_task_io.sh";

// Best-effort human title from a meetico ResolvedArtifact: prefer explicit
// metadata (Drive `name`, Notion `title`), else parse a web page's <title>.
function resolvedTitle(r) {
  if (!r) return null;
  const m = r.metadata || {};
  const meta = m.name || m.title || m.displayName;
  if (meta) return String(meta).trim();
  if (r.content_text) {
    const t = /<title[^>]*>([^<]+)<\/title>/i.exec(r.content_text);
    if (t) return t[1].trim();
  }
  return null;
}

// Locate one IO row within a task → { kind, artifact_type_id, project_id }.
// Used by io-bind to derive the meetico request from just (tid, ioId).
function locateIo(tid, ioId) {
  let d;
  try {
    d = fetchSource("task_detail", { id: tid }).rows[0];
  } catch {
    return null;
  }
  if (!d) return null;
  const find = (arr, kind) =>
    (arr || []).filter((r) => r.id === ioId).map((r) => ({ kind, artifact_type_id: r.artifact_type_id, project_id: d.project_id }))[0];
  return find(d.inputs, "inputs") || find(d.outputs, "outputs") || null;
}

// Re-render the form after a write, surfacing {ok:false} as the error banner.
function afterWrite(result, tid) {
  return renderTaskEditForm(tid, result && result.ok === false ? result.error : null);
}

const acts = {
  "io-add": (ctx) => {
    const tid = ctx.params.get("task") || "";
    const kind = ctx.params.get("kind") === "outputs" ? "output" : "input";
    return afterWrite(ctx.run(IO_SCRIPT, ["--add", kind, "--task", tid]), tid);
  },
  "io-field": (ctx) => {
    const tid = ctx.params.get("task") || "";
    const io = ctx.params.get("io") || "";
    const field = ctx.params.get("field") || "";
    const value = ctx.params.get("value") ?? "";
    const flag = { title: "--title", io_type: "--io-type", artifact: "--artifact", required: "--required" }[field];
    const result = flag ? ctx.run(IO_SCRIPT, ["--io", io, flag, value]) : { ok: false, error: `Campo inválido: ${field}` };
    return afterWrite(result, tid);
  },
  "io-delete": (ctx) => afterWrite(ctx.run(IO_SCRIPT, ["--delete", "--io", ctx.params.get("io") || ""]), ctx.params.get("task") || ""),
  "io-unbind": (ctx) => afterWrite(ctx.run(IO_SCRIPT, ["--io", ctx.params.get("io") || "", "--ref-clear"]), ctx.params.get("task") || ""),
  // Binding goes through meetico (resolver + credentials), not the DB; the
  // resolved title/url is then cached into the reference via --ref-merge so
  // the chip shows the instance name without re-resolving on every render.
  "io-bind": async (ctx) => {
    const tid = ctx.params.get("task") || "";
    const ioId = ctx.params.get("io") || "";
    const value = ctx.params.get("value") ?? "";
    let notice;
    try {
      const loc = locateIo(tid, ioId);
      if (!loc) throw new Error("IO no encontrado");
      if (!loc.artifact_type_id) throw new Error("Elegí un Artifact antes de vincular");
      if (!value.trim()) throw new Error("Pegá un enlace o ID");
      const body = { artifact_type_id: loc.artifact_type_id, url: value.trim() };
      if (loc.project_id) body.project_id = loc.project_id;
      const prev = await meetico.bindPreview(body).catch(() => null);
      await meetico.bind(loc.kind, ioId, body);
      const r = prev && prev.resolved;
      const title = resolvedTitle(r);
      ctx.run(IO_SCRIPT, ["--io", ioId, "--ref-merge", JSON.stringify({ _resolved: { title, url: (r && r.url) || null, exists: !!(r && r.exists) } })]);
      if (r && r.exists) notice = { kind: "ok", text: `Vinculado ✓ ${title || r.url || ""}`.trim() };
      else if (r && r.error) notice = { kind: "warn", text: `Vinculado, pero no resolvió: ${r.error}` };
      else notice = { kind: "ok", text: "Vinculado ✓" };
    } catch (e) {
      notice = { kind: "err", text: e.message };
    }
    return renderTaskEditForm(tid, notice);
  },
  // The SQL editor posts {query} as an explicit payload (ctx.body), not signals.
  "io-sql": (ctx) => {
    const tid = ctx.params.get("task") || "";
    const ioId = ctx.params.get("io") || "";
    const q = String((ctx.body || {}).query ?? "");
    let notice;
    if (!q.trim()) notice = { kind: "err", text: "El SQL está vacío — escribe la consulta antes de guardar." };
    else {
      const r = ctx.run(IO_SCRIPT, ["--io", ioId, "--ref-merge", JSON.stringify({ query: q })]);
      notice = r && r.ok === false ? { kind: "err", text: r.error } : { kind: "ok", text: "SQL guardado ✓" };
    }
    return renderTaskEditForm(tid, notice);
  },
  // Materialize this SQL binding as a saved UI: generic `table` over io_query.
  // Idempotent per IO row. Returns TWO patches: the left panel + the form.
  "io-sqlui": (ctx) => {
    const tid = ctx.params.get("task") || "";
    const ioId = ctx.params.get("io") || "";
    let notice;
    try {
      const d = fetchSource("task_detail", { id: tid }).rows[0];
      const row = [...((d && d.inputs) || []), ...((d && d.outputs) || [])].find((r) => r.id === ioId);
      if (!row) throw new Error("IO no encontrado");
      const q = row.reference && typeof row.reference === "object" ? row.reference.query : null;
      if (!q) throw new Error("Guarda un SQL antes de abrirlo como UI");
      let ui = store.list().find((u) => u.source === "io_query" && u.params && u.params.io === ioId);
      if (ui && ui.archived_at) {
        ui = store.unarchive(ui.id);
        notice = { kind: "ok", text: `La UI «${ui.name}» estaba archivada — restaurada en el panel izquierdo` };
      } else if (ui) notice = { kind: "ok", text: `Ya existía la UI «${ui.name}» — está en el panel izquierdo` };
      else {
        ui = store.create({ name: sqlTitle(q) || `SQL · ${row.title}`, component: "table", source: "io_query", params: { io: ioId } });
        notice = { kind: "ok", text: `UI creada: «${ui.name}» — ábrela en el panel izquierdo` };
      }
      return [ctx.refreshUiList(ui.id), renderTaskEditForm(tid, notice)];
    } catch (e) {
      return renderTaskEditForm(tid, { kind: "err", text: e.message });
    }
  },
};

module.exports = {
  id: "task-edit-form",
  // Detail slot: rows open the `form` frag; width matches the editor shell's
  // w-[34rem]. `writes` is the act whitelist enforced by ctx.run().
  manifest: { slot: "detail", frag: "form", width: "34rem", selSignal: "selectedTask", writes: [IO_SCRIPT] },
  frags: {
    form: (ctx) => renderTaskEditForm(ctx.params.get("id") || ""),
    // "Probar": run the PERSISTED query (provenance: only SQL already in the
    // DB row executes) and patch a preview table into the row.
    sqlprev: (ctx) => renderSqlPreview(ctx.params.get("io") || ""),
  },
  acts,
  renderTaskEditForm,
  renderSqlPreview,
};

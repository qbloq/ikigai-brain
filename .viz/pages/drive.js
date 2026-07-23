// drive page — explore the Google Drive of the org account: left, the file
// list (search + type filter, folders navigate); right, a preview of the
// selected file — Google Docs render as HTML (from the markdown export),
// Sheets as a table (first tab while the Sheets API stays disabled), anything
// else as a metadata card with its Drive link. Data flows through the
// bash/google/ sources (drive_files, drive_file, gdoc, gsheet) — the same
// read-only bash contract as every other page; auth never touches the viz
// (the OAuth token lives in the DB and is resolved inside the scripts).
//
// The selection travels as ?folder=&q=&type=&file= (whitelisted in the
// manifest), so any view is URL-addressable: /u/<id>?file=<drive-id>.

const { fetchSource } = require("../lib/datasources");
const { escape, table, jsStr } = require("../lib/kit");

const LIST_LIMIT = 100;
const SHEET_LIMIT = 100;

const ICON = { folder: "📁", doc: "📄", sheet: "📊", slide: "📽", pdf: "📕", shortcut: "↪" };

function uiUrl(ui, p) {
  const qs = Object.entries(p)
    .filter(([, v]) => v != null && v !== "")
    .map(([k, v]) => `${k}=${encodeURIComponent(v)}`)
    .join("&");
  return `/ui/${escape(ui.id)}${qs ? "?" + qs : ""}`;
}

// --- tiny markdown → HTML (escape-first; enough for Drive's md export) ------
function mdInline(s) {
  return s
    .replace(/`([^`]+)`/g, '<code class="bg-slate-100 rounded px-1 text-[90%]">$1</code>')
    .replace(/!\[([^\]]*)\]\(([^)\s]+)\)/g, '<a href="$2" target="_blank" class="text-indigo-600 hover:underline">🖼 $1</a>')
    .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, '<a href="$2" target="_blank" class="text-indigo-600 hover:underline">$1</a>')
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/(^|[\s(])\*([^*\n]+)\*(?=[\s).,;:!?¡¿]|$)/g, "$1<em>$2</em>");
}

const H_CLASS = [
  "text-2xl font-bold mt-6 mb-3",
  "text-xl font-bold mt-5 mb-2",
  "text-lg font-semibold mt-4 mb-2",
  "text-base font-semibold mt-3 mb-1.5",
  "text-sm font-semibold mt-3 mb-1",
  "text-sm font-semibold mt-2 mb-1 text-slate-600",
];

function mdToHtml(md) {
  const lines = escape(md).split(/\r?\n/);
  const out = [];
  let para = [], list = null, pre = [];
  const flushPara = () => {
    if (para.length) out.push(`<p class="my-2 leading-relaxed">${mdInline(para.join(" "))}</p>`);
    para = [];
  };
  const flushList = () => {
    if (list) out.push(`<${list.tag} class="my-2 ${list.tag === "ul" ? "list-disc" : "list-decimal"} pl-6 space-y-1">${list.items.join("")}</${list.tag}>`);
    list = null;
  };
  const flushPre = () => {
    if (pre.length) out.push(`<pre class="my-3 p-3 bg-slate-50 border border-slate-200 rounded-lg font-mono text-xs overflow-x-auto">${pre.join("\n")}</pre>`);
    pre = [];
  };
  for (const line of lines) {
    if (/^\s*\|/.test(line) || /^```/.test(line)) { flushPara(); flushList(); pre.push(line.replace(/^```.*$/, "")); continue; }
    flushPre();
    const h = /^(#{1,6})\s+(.*)$/.exec(line);
    if (h) { flushPara(); flushList(); out.push(`<h${h[1].length} class="${H_CLASS[h[1].length - 1]}">${mdInline(h[2])}</h${h[1].length}>`); continue; }
    if (/^\s*(---+|\*\*\*+|___+)\s*$/.test(line)) { flushPara(); flushList(); out.push('<hr class="my-4 border-slate-200">'); continue; }
    const li = /^\s*[-*+]\s+(.*)$/.exec(line);
    if (li) { flushPara(); if (!list || list.tag !== "ul") { flushList(); list = { tag: "ul", items: [] }; } list.items.push(`<li>${mdInline(li[1])}</li>`); continue; }
    const ol = /^\s*\d+[.)]\s+(.*)$/.exec(line);
    if (ol) { flushPara(); if (!list || list.tag !== "ol") { flushList(); list = { tag: "ol", items: [] }; } list.items.push(`<li>${mdInline(ol[1])}</li>`); continue; }
    if (!line.trim()) { flushPara(); flushList(); continue; }
    flushList();
    para.push(line.trim());
  }
  flushPara(); flushList(); flushPre();
  return out.join("\n");
}

// --- left panel --------------------------------------------------------------
function fileRow(ui, f, p, selected) {
  const isFolder = f.type === "folder";
  const target = isFolder
    ? uiUrl(ui, { folder: f.id, type: p.type })
    : uiUrl(ui, { folder: p.folder, q: p.q, type: p.type, file: f.id });
  return `<li><button data-on:click="@get('${target}')" data-indicator:loadingdrive
    class="w-full flex items-baseline gap-2 px-3 py-1.5 text-left rounded-md ${selected ? "bg-indigo-100 text-indigo-900 font-medium" : "text-slate-700 hover:bg-indigo-50"}"
    title="${escape(f.name)} · ${escape(f.owner || "")}">
    <span class="shrink-0">${ICON[f.type] || "📎"}</span>
    <span class="text-sm truncate flex-1">${escape(f.name)}</span>
    <span class="text-[10px] ${selected ? "text-indigo-500" : "text-slate-400"} shrink-0">${escape((f.modified || "").slice(0, 10))}</span>
  </button></li>`;
}

// --- previews ----------------------------------------------------------------
function metaCard(meta) {
  const owner = (meta.owners || [{}])[0] || {};
  const rows = [
    ["tipo", meta.mimeType],
    ["dueño", `${owner.displayName || ""} ${owner.emailAddress ? `&lt;${owner.emailAddress}&gt;` : ""}`],
    ["modificado", (meta.modifiedTime || "").replace("T", " ").slice(0, 16)],
    ["creado", (meta.createdTime || "").replace("T", " ").slice(0, 16)],
    ["tamaño", meta.size ? `${Math.round(meta.size / 1024)} KB` : "—"],
  ];
  return `<dl class="text-sm rounded-lg border border-slate-200 bg-white divide-y divide-slate-100">
    ${rows.map(([k, v]) => `<div class="flex gap-3 px-4 py-2"><dt class="w-28 shrink-0 text-slate-400">${k}</dt><dd class="text-slate-700">${v || "—"}</dd></div>`).join("")}
  </dl>`;
}

function renderPreview(fileId) {
  let meta;
  try {
    ({ rows: [meta] } = fetchSource("drive_file", { id: fileId }));
  } catch (e) {
    return `<div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-4 text-sm">${escape(e.message)}</div>`;
  }
  const head = `<div class="mb-4 flex items-baseline gap-3 flex-wrap">
    <h2 class="text-lg font-semibold text-slate-800">${escape(meta.name)}</h2>
    ${meta.webViewLink ? `<a href="${escape(meta.webViewLink)}" target="_blank" class="text-xs text-indigo-600 hover:underline shrink-0">abrir en Drive ↗</a>` : ""}
  </div>`;
  let body;
  try {
    if (meta.mimeType === "application/vnd.google-apps.document") {
      const { rows: [doc] } = fetchSource("gdoc", { id: fileId });
      body = `<article class="max-w-3xl text-[15px] text-slate-800 bg-white rounded-lg border border-slate-200 px-8 py-6">${mdToHtml(doc.markdown || "")}</article>`;
    } else if (meta.mimeType === "application/vnd.google-apps.spreadsheet") {
      const { rows } = fetchSource("gsheet", { id: fileId, limit: SHEET_LIMIT });
      body = `<p class="mb-2 text-xs text-slate-400">primera pestaña · máx. ${SHEET_LIMIT} filas</p>${table(rows)}`;
    } else {
      body = metaCard(meta);
    }
  } catch (e) {
    body = `<div class="rounded-lg border border-red-200 bg-red-50 text-red-700 p-4 text-sm">${escape(e.message)}</div>`;
  }
  return head + body;
}

// --- page ---------------------------------------------------------------------
function renderDrive(ui) {
  const p = ui.params || {};
  const cur = { folder: p.folder || "", q: p.q || "", type: p.type || "", file: p.file || "" };

  let files = [], err;
  try {
    ({ rows: files } = fetchSource("drive_files", { folder: cur.folder, q: cur.q, type: cur.type, limit: LIST_LIMIT }));
  } catch (e) {
    err = e.message;
  }
  // folders first, both halves keep the API's newest-first order
  files = [...files.filter((f) => f.type === "folder"), ...files.filter((f) => f.type !== "folder")];

  // breadcrumb: name + parent of the current folder (one cheap metadata call)
  let crumb = "";
  if (cur.folder) {
    let fname = cur.folder, parent = "";
    try {
      const { rows: [fm] } = fetchSource("drive_file", { id: cur.folder });
      fname = fm.name || fname;
      parent = (fm.parents || [])[0] || "";
    } catch { /* keep the id as label */ }
    crumb = `<div class="flex items-center gap-1.5 px-2 pb-2 text-xs">
      <button data-on:click="@get('${uiUrl(ui, { type: cur.type })}')" data-indicator:loadingdrive
        class="px-2 py-1 rounded-md text-indigo-600 hover:bg-indigo-50" title="volver a recientes">⌂</button>
      ${parent ? `<button data-on:click="@get('${uiUrl(ui, { folder: parent, type: cur.type })}')" data-indicator:loadingdrive
        class="px-2 py-1 rounded-md text-indigo-600 hover:bg-indigo-50" title="subir a la carpeta padre">↑</button>` : ""}
      <span class="font-medium text-slate-600 truncate" title="${escape(fname)}">📁 ${escape(fname)}</span>
    </div>`;
  }

  const reget = `@get('/ui/${escape(ui.id)}?folder=${encodeURIComponent(cur.folder)}&type=' + $tdrive + '&q=' + encodeURIComponent($qdrive))`;
  const controls = `<div class="p-2 space-y-2 border-b border-slate-200">
    <div class="flex gap-1.5">
      <input data-bind="qdrive" data-on:keydown__enter="${reget}" data-indicator:loadingdrive placeholder="buscar por nombre…"
        class="flex-1 min-w-0 text-sm px-3 py-1.5 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-indigo-400">
      <button data-on:click="${reget}" data-indicator:loadingdrive
        class="px-3 py-1.5 text-sm rounded-lg bg-indigo-600 text-white hover:bg-indigo-500">🔍</button>
    </div>
    <select data-bind="tdrive" data-on:change="${reget}" data-indicator:loadingdrive
      class="w-full text-sm px-3 py-1.5 rounded-lg border border-slate-300 bg-white focus:outline-none focus:ring-2 focus:ring-indigo-400">
      ${[["", "todos los tipos"], ["doc", "documentos"], ["sheet", "hojas de cálculo"], ["slide", "presentaciones"], ["folder", "carpetas"], ["pdf", "PDF"]]
        .map(([v, l]) => `<option value="${v}"${v === cur.type ? " selected" : ""}>${l}</option>`).join("")}
    </select>
  </div>`;

  const listBody = err
    ? `<div class="m-3 rounded-lg border border-red-200 bg-red-50 text-red-700 p-3 text-xs">${escape(err)}</div>`
    : files.length
      ? `<ul class="p-2">${files.map((f) => fileRow(ui, f, cur, f.id === cur.file)).join("")}</ul>
         ${files.length >= LIST_LIMIT ? `<p class="px-3 pb-3 text-[10px] text-slate-400">primeros ${LIST_LIMIT} — afina la búsqueda</p>` : ""}`
      : '<p class="p-4 text-xs text-slate-400 italic">Sin resultados.</p>';

  const preview = cur.file
    ? renderPreview(cur.file)
    : `<div class="h-full flex items-center justify-center text-slate-400 text-sm">
        <p>Selecciona un archivo para previsualizarlo — Docs como texto, Sheets como tabla.</p></div>`;

  const head = `<header class="mb-4 flex items-baseline gap-3">
    <h1 class="text-xl font-semibold text-slate-800">${escape(ui.name)}</h1>
    <span class="text-xs text-slate-400">cuenta org · solo lectura</span>
    <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs text-indigo-600 hover:underline">abrir solo ↗</a>
  </header>`;

  return `<section id="pane" class="flex-1 overflow-hidden flex" data-signals="{qdrive: ${jsStr(cur.q)}, tdrive: ${jsStr(cur.type)}}">
    <style>
      #drive-loading{opacity:0;transition:opacity .2s ease;}
      #drive-loading.on{opacity:1;}
    </style>
    <aside class="w-80 shrink-0 border-r border-slate-200 bg-white overflow-auto flex flex-col">
      ${controls}${crumb}
      <div class="flex-1 overflow-auto">${listBody}</div>
    </aside>
    <div class="flex-1 relative overflow-auto p-6 bg-slate-50">
      <div id="drive-loading" data-class:on="$loadingdrive" class="pointer-events-none absolute inset-0 z-10 flex items-start justify-center pt-16 bg-white/50">
        <div class="w-7 h-7 rounded-full border-2 border-slate-300 border-t-indigo-600 animate-spin"></div>
      </div>
      ${head}${preview}
    </div>
  </section>`;
}

module.exports = {
  id: "drive",
  manifest: { consumes: "rows", overridable: ["folder", "q", "type", "file"] },
  render: renderDrive,
};

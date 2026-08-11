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
const { escape, table, jsStr, jsArr, checkCtl } = require("../lib/kit");

const LIST_LIMIT = 100;
const SHEET_LIMIT = 100;
const STALE_HOURS = 48; // a partir de aquí la respuesta deja de ser confiable

const ICON = { folder: "📁", doc: "📄", sheet: "📊", slide: "📽", pdf: "📕", shortcut: "↪" };

// El índice devuelve etiquetas amigables ("Google Doc"); el explorador vivo
// devuelve claves cortas ("doc"). Un solo mapa para que ambos listados usen
// el mismo icono.
const LABEL_ICON = {
  "Folder": "📁", "Google Doc": "📄", "Google Sheet": "📊", "Google Slides": "📽",
  "Google Form": "📝", "PDF": "📕", "Shortcut": "↪", "Text": "📄",
  "Word (.docx)": "📄", "Excel (.xlsx)": "📊", "PowerPoint (.pptx)": "📽", "CSV": "📊",
};
const iconFor = (t) => LABEL_ICON[t] || ICON[t] || (/Video/.test(t) ? "🎬" : /Image|JPEG|PNG|HEIF/.test(t) ? "🖼" : "📎");

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

// Fila del modo recientes: mismo gesto (clic = previsualizar) pero la columna
// de la derecha es CUÁNDO, que es la pregunta del modo, y debajo va la carpeta
// — sin ella "Documento sin título" no se distingue de otro igual.
function recentRow(ui, f, p, selected) {
  const target = uiUrl(ui, {
    recientes: "1", days: p.days, docs: p.docs, type: p.type, file: f.id,
    excl: (p.excl || []).join("|"),
  });
  return `<li><button data-on:click="@get('${target}')" data-indicator:loadingdrive
    class="w-full flex items-baseline gap-2 px-3 py-1.5 text-left rounded-md ${selected ? "bg-indigo-100 text-indigo-900 font-medium" : "text-slate-700 hover:bg-indigo-50"}"
    title="${escape(f.nombre)} · ${escape(f.carpeta || "")} · ${escape(f.owner || "")}">
    <span class="shrink-0">${iconFor(f.type)}</span>
    <span class="flex-1 min-w-0">
      <span class="block text-sm truncate">${escape(f.nombre)}</span>
      <span class="block text-[10px] ${selected ? "text-indigo-500" : "text-slate-400"} truncate">${escape(f.carpeta || "")}</span>
    </span>
    <span class="text-[10px] ${selected ? "text-indigo-500" : "text-slate-400"} shrink-0 font-mono">${escape(f.cuando || "")}</span>
  </button></li>`;
}

// Dropdown de carpetas: marcar una la SACA del listado.
//
// Las opciones salen de un conteo que NO aplica la exclusión, y eso es
// deliberado: derivadas de las filas ya filtradas, la carpeta que acabas de
// excluir desaparecería de la lista y no habría cómo devolverla — el filtro se
// cerraría sobre sí mismo (el mismo motivo por el que las facetas del CRM son
// una fuente aparte). Por eso la marcada sigue visible, marcada, y con su
// conteo original.
function folderFilter(ui, cur, reget) {
  let opts = [];
  try {
    ({ rows: opts } = fetchSource("drive_recent", {
      days: cur.days, type: cur.type, docs: cur.docs, by: "folder", limit: 0,
    }));
  } catch {
    return ""; // sin opciones el filtro sobra; el listado ya reporta su error
  }
  if (!opts.length) return "";

  const off = new Set(cur.excl);
  const n = off.size;
  const label = n ? `${n} carpeta${n > 1 ? "s" : ""} fuera` : "todas las carpetas";

  // Las casillas NO piden nada al servidor — marcar solo acumula en la señal.
  // Un multiselect que re-fetchea por clic se rompe solo: cada respuesta
  // reemplaza el panel entero (las casillas incluidas, y el <details> se
  // cerraría de golpe), así que marcar la segunda antes de que vuelva la
  // primera pierde el clic. «Aplicar» es lo único que consulta. Mismo patrón
  // que el filtro de dueños en blocks/leads-table.js.
  const items = opts
    .map((o) => {
      const name = String(o.carpeta ?? "");
      return `<li class="flex items-baseline gap-1">
        ${checkCtl("excldrive", name, "", {
          indicator: "", checked: off.has(name), value: name, cls: "flex-1 min-w-0 text-xs",
        })}
        <span class="text-[10px] text-slate-400 shrink-0 pr-2">${o.items}</span>
      </li>`;
    })
    .join("");

  const sinCambios = "($excldrive || []).join('|') === " + JSON.stringify(cur.excl.join("|"));

  return `<details class="rounded-lg border border-slate-300 bg-white"${n ? " open" : ""}>
    <summary class="px-3 py-1.5 text-sm text-slate-600 cursor-pointer select-none list-none flex items-center gap-2">
      <span class="flex-1 truncate">${n ? "🚫 " : ""}${escape(label)}</span>
      <span class="text-[10px] text-slate-400">▾</span>
    </summary>
    <ul class="max-h-56 overflow-auto border-t border-slate-200 py-1">${items}</ul>
    <div class="border-t border-slate-200 px-2 py-1.5 flex items-center gap-3">
      <button data-on:click="${reget}" data-indicator:loadingdrive
        data-attr:disabled="${escape(sinCambios)}"
        class="btn btn-sm" title="Excluye del listado las carpetas marcadas">Aplicar</button>
      ${n ? `<button data-on:click="@get('${uiUrl(ui, { recientes: "1", days: cur.days, docs: cur.docs, type: cur.type })}')"
        data-indicator:loadingdrive class="text-[11px] text-indigo-600 hover:underline">quitar exclusiones</button>` : ""}
    </div>
  </details>`;
}

// La frescura del índice, arriba de todo y con el tono según la edad. Es la
// pieza que impide leer un caché viejo como "no pasó nada": el listado se ve
// idéntico esté al día o lleve una semana parado.
function freshnessBar() {
  let s;
  try {
    ({ rows: [s] } = fetchSource("drive_index_status", {}));
  } catch (e) {
    return `<div class="px-3 py-2 text-[11px] bg-amber-50 text-amber-800 border-b border-amber-200">
      no se pudo leer la frescura del índice: ${escape(e.message)}</div>`;
  }
  const age = s.age_hours;
  const stale = age != null && age > STALE_HOURS;
  const tone = stale
    ? "bg-amber-50 text-amber-800 border-amber-200"
    : "bg-slate-50 text-slate-500 border-slate-200";
  const when = String(s.synced_at || "").slice(0, 16).replace("T", " ");
  return `<div class="px-3 py-1.5 text-[11px] border-b ${tone} flex items-baseline gap-2 flex-wrap">
    <span>${stale ? "⚠ " : ""}índice de ${s.items ?? "?"} items · sync ${escape(when)}${age != null ? ` (hace ${age}h)` : ""}</span>
    ${s.running ? '<span class="text-indigo-600">· refrescando ahora…</span>' : ""}
    ${stale ? '<span class="w-full text-[10px] opacity-80">lo más nuevo del Drive puede no estar aquí — refresca con <code>bash/google/drive_sync.sh --wait</code></span>' : ""}
  </div>`;
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
  const recientes = p.recientes === "1" || p.recientes === 1 || p.recientes === true;
  const cur = {
    folder: p.folder || "", q: p.q || "", type: p.type || "", file: p.file || "",
    days: p.days || "14", docs: p.docs === "1" ? "1" : "",
    excl: String(p.excl || "").split("|").filter(Boolean),
  };

  let files = [], err;
  try {
    if (recientes) {
      // La ventana ya viene ordenada por fecha desde el backend; el modo
      // recientes no reordena (carpetas primero destruiría justo el orden que
      // se vino a ver).
      // La exclusión viaja al script, no se aplica sobre lo ya traído: filtrar
      // después del tope dejaría 45 filas donde debería haber 100 — el ruido se
      // iría llevándose consigo el material que se venía a ver.
      ({ rows: files } = fetchSource("drive_recent", {
        days: cur.days, type: cur.type, docs: cur.docs, limit: LIST_LIMIT,
        exclude_folder: cur.excl.join("|"),
      }));
    } else {
      ({ rows: files } = fetchSource("drive_files", { folder: cur.folder, q: cur.q, type: cur.type, limit: LIST_LIMIT }));
      // folders first, both halves keep the API's newest-first order
      files = [...files.filter((f) => f.type === "folder"), ...files.filter((f) => f.type !== "folder")];
    }
  } catch (e) {
    err = e.message;
  }

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

  const reget = recientes
    ? `@get('/ui/${escape(ui.id)}?recientes=1&days=' + $ddrive + '&docs=' + ($docsdrive ? '1' : '') + '&type=' + $tdrive + '&excl=' + encodeURIComponent(($excldrive || []).join('|')))`
    : `@get('/ui/${escape(ui.id)}?folder=${encodeURIComponent(cur.folder)}&type=' + $tdrive + '&q=' + encodeURIComponent($qdrive))`;

  const tab = (on, label, url, title) => `<button data-on:click="@get('${url}')" data-indicator:loadingdrive title="${title}"
    class="flex-1 px-3 py-1 text-xs rounded-md ${on ? "bg-white shadow-sm font-medium text-slate-800" : "text-slate-500 hover:text-slate-700"}">${label}</button>`;

  const modes = `<div class="flex gap-1 p-1 rounded-lg bg-slate-100">
    ${tab(!recientes, "Explorar", uiUrl(ui, { type: cur.type }), "navegar por carpetas y buscar por nombre")}
    ${tab(recientes, "Recientes", uiUrl(ui, { recientes: "1", days: cur.days, docs: cur.docs, type: cur.type, excl: cur.excl.join("|") }), "lo último que entró al Drive, por fecha")}
  </div>`;

  const search = `<div class="flex gap-1.5">
      <input data-bind="qdrive" data-on:keydown__enter="${reget}" data-indicator:loadingdrive placeholder="buscar por nombre…"
        class="flex-1 min-w-0 text-sm px-3 py-1.5 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-indigo-400">
      <button data-on:click="${reget}" data-indicator:loadingdrive
        class="px-3 py-1.5 text-sm rounded-lg bg-indigo-600 text-white hover:bg-indigo-500">🔍</button>
    </div>`;

  // En recientes la búsqueda por nombre no aplica (la fuente filtra por fecha,
  // no por texto); en su lugar mandan la ventana y el corte de material bruto.
  const windowCtl = `<div class="flex gap-1.5 items-center">
      <select data-bind="ddrive" data-on:change="${reget}" data-indicator:loadingdrive
        class="flex-1 text-sm px-3 py-1.5 rounded-lg border border-slate-300 bg-white focus:outline-none focus:ring-2 focus:ring-indigo-400">
        ${[["7", "última semana"], ["14", "últimas 2 semanas"], ["30", "último mes"], ["90", "últimos 3 meses"]]
          .map(([v, l]) => `<option value="${v}"${v === cur.days ? " selected" : ""}>${l}</option>`).join("")}
      </select>
      <span class="shrink-0 text-xs text-slate-600" title="oculta video, fotos y demás material bruto — el 80% del Drive">
        ${checkCtl("docsdrive", "solo docs", reget, { indicator: "loadingdrive", checked: !!cur.docs })}
      </span>
    </div>`;

  const controls = `<div class="p-2 space-y-2 border-b border-slate-200">
    ${modes}
    ${recientes ? windowCtl : search}
    ${recientes ? folderFilter(ui, cur, reget) : ""}
    <select data-bind="tdrive" data-on:change="${reget}" data-indicator:loadingdrive
      class="w-full text-sm px-3 py-1.5 rounded-lg border border-slate-300 bg-white focus:outline-none focus:ring-2 focus:ring-indigo-400">
      ${[["", "todos los tipos"], ["doc", "documentos"], ["sheet", "hojas de cálculo"], ["slide", "presentaciones"], ["folder", "carpetas"], ["pdf", "PDF"]]
        .concat(recientes ? [["video", "video"], ["image", "imágenes"]] : [])
        .map(([v, l]) => `<option value="${v}"${v === cur.type ? " selected" : ""}>${l}</option>`).join("")}
    </select>
  </div>`;

  const row = recientes ? recentRow : fileRow;
  const empty = recientes
    ? "Nada en esa ventana. Ojo con la frescura del índice, arriba."
    : "Sin resultados.";
  const listBody = err
    ? `<div class="m-3 rounded-lg border border-red-200 bg-red-50 text-red-700 p-3 text-xs">${escape(err)}</div>`
    : files.length
      ? `<ul class="p-2">${files.map((f) => row(ui, f, cur, f.id === cur.file)).join("")}</ul>
         ${files.length >= LIST_LIMIT ? `<p class="px-3 pb-3 text-[10px] text-slate-400">primeros ${LIST_LIMIT} — ${recientes ? "acorta la ventana" : "afina la búsqueda"}</p>` : ""}`
      : `<p class="p-4 text-xs text-slate-400 italic">${empty}</p>`;

  const preview = cur.file
    ? renderPreview(cur.file)
    : `<div class="h-full flex items-center justify-center text-slate-400 text-sm">
        <p>Selecciona un archivo para previsualizarlo — Docs como texto, Sheets como tabla.</p></div>`;

  const head = `<header class="mb-4 flex items-baseline gap-3">
    <h1 class="text-xl font-semibold text-slate-800">${escape(ui.name)}</h1>
    <span class="text-xs text-slate-400">cuenta org · solo lectura</span>
    <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs text-indigo-600 hover:underline">abrir solo ↗</a>
  </header>`;

  return `<section id="pane" class="flex-1 overflow-hidden flex" data-signals="{qdrive: ${jsStr(cur.q)}, tdrive: ${jsStr(cur.type)}, ddrive: ${jsStr(cur.days)}, docsdrive: ${cur.docs ? "true" : "false"}, excldrive: ${jsArr(cur.excl)}}">
    <style>
      #drive-loading{opacity:0;transition:opacity .2s ease;}
      #drive-loading.on{opacity:1;}
    </style>
    <aside class="w-80 shrink-0 border-r border-slate-200 bg-white overflow-auto flex flex-col">
      ${recientes ? freshnessBar() : ""}
      ${controls}${recientes ? "" : crumb}
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
  manifest: { consumes: "rows", overridable: ["folder", "q", "type", "file", "recientes", "days", "docs", "excl"] },
  render: renderDrive,
};

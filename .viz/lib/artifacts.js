// Per-artifact-type UI — one entry per artifact type we "conquer". Each knows how
// to present a *bound instance*: an icon, the instance's human label (title/name,
// falling back to the raw locator), and a link to open it. The binding chip reads
// the resolved title/url from `reference._resolved` (cached at bind time by the
// server) so rendering never has to re-resolve.
//
// Adding support for a new artifact type = one entry here. Returns plain data
// (icon/label/href strings); the caller escapes for HTML.

function firstLocator(r) {
  if (!r || typeof r !== "object") return null;
  for (const k of Object.keys(r)) {
    if (k === "_resolved") continue;
    if (typeof r[k] === "string" && r[k]) return r[k];
  }
  return null;
}

const resolvedTitle = (r) => (r && r._resolved && r._resolved.title) || null;
const resolvedUrl = (r) => (r && r._resolved && r._resolved.url) || null;

// First `-- comment` line of a SQL query, as its human title.
function sqlTitle(q) {
  const m = typeof q === "string" ? q.match(/^\s*--\s*(.+)$/m) : null;
  return m ? m[1].trim() : null;
}

const ARTIFACTS = {
  google_doc: {
    icon: "📄",
    label: (r) => resolvedTitle(r) || r.file_id || "Google Doc",
    href: (r) => resolvedUrl(r) || r.url || (r.file_id ? `https://docs.google.com/document/d/${r.file_id}/edit` : null),
  },
  google_sheet: {
    icon: "📊",
    label: (r) => resolvedTitle(r) || r.file_id || "Google Sheet",
    href: (r) => resolvedUrl(r) || r.url || (r.file_id ? `https://docs.google.com/spreadsheets/d/${r.file_id}/edit` : null),
  },
  drive_file: {
    icon: "📁",
    label: (r) => resolvedTitle(r) || r.file_id || "Archivo de Drive",
    href: (r) => resolvedUrl(r) || r.url || (r.file_id ? `https://drive.google.com/file/d/${r.file_id}/view` : null),
  },
  notion_page: {
    icon: "📝",
    label: (r) => resolvedTitle(r) || r.page_id || "Página de Notion",
    href: (r) => resolvedUrl(r) || r.url || null,
  },
  web_url: {
    icon: "🔗",
    label: (r) => resolvedTitle(r) || r.url || "Enlace",
    href: (r) => r.url || resolvedUrl(r) || null,
  },
  sql_query: {
    icon: "🗃️",
    label: (r) => resolvedTitle(r) || sqlTitle(r.query) || "Consulta SQL",
    href: () => null,
  },
  storage_file: {
    icon: "📦",
    label: (r) => resolvedTitle(r) || r.path || "Archivo",
    href: (r) => resolvedUrl(r) || r.url || null,
  },
  computed: {
    icon: "✓",
    label: (r) => resolvedTitle(r) || r.check || "Verificación",
    href: () => null,
  },
};

// Fallback for artifact types not yet conquered.
const GENERIC = {
  icon: "🔗",
  label: (r) => resolvedTitle(r) || firstLocator(r) || "Vinculado",
  href: (r) => r.url || resolvedUrl(r) || null,
};

function artifactUI(name) {
  return (name && ARTIFACTS[name]) || GENERIC;
}

// { icon, label, href } for a reference under an artifact type (by name).
function chipData(name, reference) {
  const ui = artifactUI(name);
  const r = reference && typeof reference === "object" ? reference : {};
  return { icon: ui.icon, label: ui.label(r) || "", href: ui.href(r) || null };
}

module.exports = { artifactUI, chipData, sqlTitle, ARTIFACTS };

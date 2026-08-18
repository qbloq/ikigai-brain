// Registro del publicador — lectura del SQLite publicaciones.db vía el CLI
// sqlite3 -json (cero npm deps). Estado PROPIO del publicador: la excepción
// declarada al rail «nunca SQL en el viz», que gobierna datos de la org.
// Los valores se validan por forma ANTES de interpolarse; lit() escapa comillas.
const { execFileSync } = require("node:child_process");
const path = require("node:path");

const REPO_ROOT = path.resolve(__dirname, "..", "..");
const DB = () => process.env.PUBLICACIONES_DB || path.join(REPO_ROOT, "data", "sqlite", "publicaciones.db");

const SLUG_RE = /^[a-z0-9][a-z0-9-]{0,63}$/;
const CODIGO_RE = /^[A-Za-z0-9]{4,32}$/;

const lit = (v) => (v == null ? "NULL" : `'${String(v).replace(/'/g, "''")}'`);

function q(sql, { rw = false } = {}) {
  const flags = rw ? ["-json"] : ["-json", "-readonly"];
  const out = execFileSync("sqlite3", [...flags, DB(), sql], { encoding: "utf8" });
  return out.trim() ? JSON.parse(out) : [];
}

// Generación vigente de un slug: la más alta sin archivar.
function vigente(slug) {
  if (!SLUG_RE.test(String(slug || ""))) return null;
  const rows = q(`SELECT * FROM despliegues WHERE slug=${lit(slug)} AND archivado_at IS NULL
                  ORDER BY generacion DESC LIMIT 1`);
  return rows[0] || null;
}

function porCodigo(codigo) {
  if (!CODIGO_RE.test(String(codigo || ""))) return null;
  const rows = q(`SELECT * FROM despliegues WHERE codigo_corto=${lit(codigo)} AND archivado_at IS NULL
                  ORDER BY generacion DESC LIMIT 1`);
  return rows[0] || null;
}

// Todos los despliegues vigentes nacidos de un spec (para resolver /ui/:id y /u/:id).
function porSpecId(specId) {
  if (!SLUG_RE.test(String(specId || ""))) return [];
  return q(`SELECT d.* FROM despliegues d
            WHERE d.spec_id=${lit(specId)} AND d.archivado_at IS NULL
              AND d.generacion = (SELECT max(generacion) FROM despliegues
                                  WHERE slug=d.slug AND archivado_at IS NULL)`);
}

function permisosDe(slug) {
  if (!SLUG_RE.test(String(slug || ""))) return [];
  return q(`SELECT * FROM permisos WHERE slug=${lit(slug)} AND revocado_at IS NULL`);
}

// Best-effort: el log de visitas jamás rompe un render.
function visita(slug, payload, ruta) {
  try {
    q(`INSERT INTO visitas (slug, user_id, email, ruta)
       VALUES (${lit(slug)}, ${lit(payload && payload.id)}, ${lit(payload && payload.email)}, ${lit(ruta)})`, { rw: true });
  } catch {
    /* nunca romper el render por el log */
  }
}

module.exports = { vigente, porCodigo, porSpecId, permisosDe, visita, SLUG_RE };

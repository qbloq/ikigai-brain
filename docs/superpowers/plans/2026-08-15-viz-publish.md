# Publicación de UIs del viz — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publicar UIs del viz como páginas stand-alone en producción (`app.ikigaigm.parallelo.ai/<slug>`), con datos vivos, login contra Marketico y permisos con alcance de datos por identidad.

**Architecture:** Un segundo entrypoint `viz/publish.js` (pm2 `viz-publish`, :4318) corre en un checkout del cerebro en `/apps/hermetico` del servidor api, reusa la torre del viz (`lib/`, `pages/`, tema) y sirve solo despliegues registrados en un SQLite local (`publicaciones.db`), autenticando con el JWT de Marketico verificado localmente. La publicación y los permisos se operan por conversación vía `bash/publicar/` sobre ssh.

**Tech Stack:** Node stdlib (cero npm deps — `node:crypto` para HS256, `sqlite3` CLI con `-json` para el registro), bash + ssh, nginx + certbot, pm2.

**Spec:** `docs/superpowers/specs/2026-08-15-viz-publish-design.md`

## Global Constraints

- **Cero npm deps** — todo Node stdlib; el registro SQLite se lee con el binario `sqlite3 -json` (execFileSync), jamás un driver npm.
- **El rail «nunca SQL en el viz» gobierna los DATOS DE LA ORG** (Postgres/ikigaigm, siempre vía `bash/ --json`). `publicaciones.db` es **estado propio del publicador** (como los spec files lo son de server.js) — su SQL vive en `viz/lib/pubstore.js` y `bash/publicar/schema.sql`, y esta excepción se documenta en CLAUDe.md (Task 8).
- **publish.js no monta escrituras**: `lib/actions.js` no se importa; no existen rutas POST salvo `/login`/`/logout`. Su única escritura local es el INSERT best-effort en `visitas`.
- **Tema**: cualquier markup nuevo (página de login, chip de closer) usa clases del DS (`.card`, `.btn`, `.input`, `.badge`) o tokens semánticos `var(--…)` — jamás hex ni `--pal-*`.
- **Datastar 1.0 sintaxis de dos puntos** (`data-on:change`, `@get`) — igual que el resto del viz.
- Server api: node **v20.19.3** (global `fetch` disponible), Debian; faltan `postgresql-client`, `jq`, `sqlite3` (se instalan en Task 8).
- ssh destino: `root@api`; checkout remoto: `/apps/hermetico`; clone desde `/srv/git/cerebros/ikigai.git` (el git server vive en la misma máquina).
- Roles reales en DB (los matchea el JWT): `Closer`, `Director Comercial`.
- Login Marketico: `POST https://ikigaigm.api.parallelo.ai/api/auth/login` body `{email, password}` → `{success, data:{token}}`; JWT HS256 payload `{id, email, roles[], name, iat, exp}`; secreto en `JWT_SECRET` (existe en `/apps/marketico/.env`).
- Spec piloto: id **`dashboard-por-closer`** (capa `roles/director-comercial`), component `closer-dashboard`, source `closer_dashboard` (`emits: object`, args `closer/project/from/to`, overridable los cuatro).
- **Desviación consciente del spec:** las rutas `/c/:component/frag/:name` NO se montan en v1 — la página piloto re-fetcha vía `GET /ui/:id` (verificado en `pages/closer-dashboard.js:118`), y montar frags genéricos abriría superficies (p.ej. `task-detail?id=…`) que el modelo de permisos v1 no gobierna. Documentado como límite; v2 los montará con una whitelist por despliegue.

---

### Task 1: Esquema del registro + `viz/lib/pubstore.js`

**Files:**
- Create: `bash/publicar/schema.sql`
- Create: `viz/lib/pubstore.js`
- Test: `viz/test/pubstore.test.js`
- Modify: `package.json` (script `test:viz`)

**Interfaces:**
- Produces: `pubstore.vigente(slug) → row|null` · `pubstore.porCodigo(codigo) → row|null` · `pubstore.porSpecId(specId) → row[]` (vigentes) · `pubstore.permisosDe(slug) → row[]` (no revocados) · `pubstore.visita(slug, payload, ruta)` (best-effort). Rows con columnas del schema (strings tal como las emite sqlite3 -json). La ruta de la db: env `PUBLICACIONES_DB` o `<repo>/data/sqlite/publicaciones.db`.

- [ ] **Step 1: Escribir el schema**

`bash/publicar/schema.sql` (idempotente — se aplica en cada publicación):

```sql
-- Registro del publicador de UIs (viz/publish.js). Estado PROPIO del
-- publicador — no es dato de la org; el spec del diseño:
-- docs/superpowers/specs/2026-08-15-viz-publish-design.md
PRAGMA journal_mode=WAL;

CREATE TABLE IF NOT EXISTS despliegues (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  slug          TEXT NOT NULL,                  -- URL legible: /dashboard-closer
  codigo_corto  TEXT NOT NULL,                  -- alias /s/<codigo> (mismo por slug en todas las generaciones)
  spec_id       TEXT NOT NULL,                  -- id del spec origen (p.ej. dashboard-por-closer)
  spec_json     TEXT NOT NULL,                  -- snapshot CONGELADO al publicar
  component     TEXT NOT NULL,
  source        TEXT,
  params_fijos  TEXT NOT NULL DEFAULT '{}',     -- json
  identidad     TEXT,                           -- json plantilla ({"closer":"$name"}) o NULL
  generacion    INTEGER NOT NULL DEFAULT 1,     -- re-publicar = +1, nunca sobreescribe
  creado_at     TEXT NOT NULL DEFAULT (datetime('now')),
  archivado_at  TEXT,                           -- despublicar = sellar, nunca borrar
  UNIQUE (slug, generacion)
);
CREATE INDEX IF NOT EXISTS ix_despliegues_codigo ON despliegues(codigo_corto);
CREATE INDEX IF NOT EXISTS ix_despliegues_spec   ON despliegues(spec_id);

CREATE TABLE IF NOT EXISTS permisos (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  slug             TEXT NOT NULL,               -- lógico: aplica a la generación vigente
  user_id          TEXT,                        -- users.id — exactamente uno de user_id/rol
  rol              TEXT,                        -- matchea contra roles[] del JWT
  params_identidad TEXT,                        -- NULL = hereda plantilla · '{}' = anula · json = explícito
  creado_at        TEXT NOT NULL DEFAULT (datetime('now')),
  revocado_at      TEXT,
  CHECK ((user_id IS NULL) + (rol IS NULL) = 1)
);
CREATE INDEX IF NOT EXISTS ix_permisos_slug ON permisos(slug);

CREATE TABLE IF NOT EXISTS visitas (
  id      INTEGER PRIMARY KEY AUTOINCREMENT,
  slug    TEXT NOT NULL,
  user_id TEXT,
  email   TEXT,
  ruta    TEXT,
  ts      TEXT NOT NULL DEFAULT (datetime('now'))
);
```

- [ ] **Step 2: Escribir el test que falla**

`viz/test/pubstore.test.js` — crea una db temporal desde el schema y ejercita cada función:

```js
const { test, before } = require("node:test");
const assert = require("node:assert");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");

const TMP = fs.mkdtempSync(path.join(os.tmpdir(), "pubstore-"));
const DB = path.join(TMP, "publicaciones.db");
process.env.PUBLICACIONES_DB = DB; // ANTES del require
const pubstore = require("../lib/pubstore");

const SCHEMA = path.join(__dirname, "..", "..", "bash", "publicar", "schema.sql");
const sql = (s) => execFileSync("sqlite3", [DB, s], { encoding: "utf8" });

before(() => {
  execFileSync("sqlite3", [DB], { input: fs.readFileSync(SCHEMA, "utf8") });
  sql(`INSERT INTO despliegues (slug, codigo_corto, spec_id, spec_json, component, source, identidad, generacion)
       VALUES ('dashboard-closer','Ab3xK9pQ2m','dashboard-por-closer',
               '{"id":"dashboard-por-closer","component":"closer-dashboard","source":"closer_dashboard","params":{}}',
               'closer-dashboard','closer_dashboard','{"closer":"$name"}',1)`);
  sql(`INSERT INTO despliegues (slug, codigo_corto, spec_id, spec_json, component, source, identidad, generacion)
       VALUES ('dashboard-closer','Ab3xK9pQ2m','dashboard-por-closer','{"id":"dashboard-por-closer"}',
               'closer-dashboard','closer_dashboard','{"closer":"$name"}',2)`);
  sql(`INSERT INTO permisos (slug, rol, params_identidad) VALUES ('dashboard-closer','Closer',NULL)`);
  sql(`INSERT INTO permisos (slug, rol, params_identidad) VALUES ('dashboard-closer','Director Comercial','{}')`);
  sql(`INSERT INTO permisos (slug, rol, params_identidad, revocado_at) VALUES ('dashboard-closer','Editor','{}','2026-08-15')`);
});

test("vigente devuelve la generación más alta no archivada", () => {
  const d = pubstore.vigente("dashboard-closer");
  assert.strictEqual(d.generacion, 2);
});
test("vigente rechaza slugs malformados sin tocar la db", () => {
  assert.strictEqual(pubstore.vigente("x'; DROP TABLE despliegues;--"), null);
  assert.strictEqual(pubstore.vigente("dashboard-closer").slug, "dashboard-closer");
});
test("porCodigo resuelve el alias", () => {
  assert.strictEqual(pubstore.porCodigo("Ab3xK9pQ2m").slug, "dashboard-closer");
  assert.strictEqual(pubstore.porCodigo("noexiste123"), null);
});
test("porSpecId devuelve los vigentes de ese spec", () => {
  const rows = pubstore.porSpecId("dashboard-por-closer");
  assert.strictEqual(rows.length, 1);
  assert.strictEqual(rows[0].generacion, 2);
});
test("permisosDe excluye revocados", () => {
  const p = pubstore.permisosDe("dashboard-closer");
  assert.deepStrictEqual(p.map((x) => x.rol).sort(), ["Closer", "Director Comercial"]);
});
test("visita inserta y nunca lanza", () => {
  pubstore.visita("dashboard-closer", { id: "u1", email: "a@b.c" }, "/dashboard-closer");
  assert.strictEqual(Number(sql("SELECT count(*) FROM visitas").trim()), 1);
  process.env.PUBLICACIONES_DB_ROTA = "1"; // no usado — solo documenta que el catch es total
  pubstore.visita(null, null, null); // args inválidos → swallowed
});
```

- [ ] **Step 3: Correr el test y verlo fallar**

Run: `node --test viz/test/pubstore.test.js`
Expected: FAIL — `Cannot find module '../lib/pubstore'`

- [ ] **Step 4: Implementar `viz/lib/pubstore.js`**

```js
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
```

- [ ] **Step 5: Correr el test y verlo pasar**

Run: `node --test viz/test/pubstore.test.js`
Expected: PASS (6 tests)

- [ ] **Step 6: Agregar el npm script**

En `package.json`, junto a los scripts `viz`: `"test:viz": "node --test viz/test/"`.
Run: `npm run test:viz` → PASS.

- [ ] **Step 7: Commit**

```bash
git add bash/publicar/schema.sql viz/lib/pubstore.js viz/test/pubstore.test.js package.json
git commit -m "publicar: registro sqlite del publicador (schema + pubstore)"
```

---

### Task 2: `viz/lib/publogic.js` — permisos, identidad y merge de params

**Files:**
- Create: `viz/lib/publogic.js`
- Test: `viz/test/publogic.test.js`

**Interfaces:**
- Consumes: rows de `pubstore.permisosDe` (`{user_id, rol, params_identidad}`), payload JWT `{id, email, roles[], name}`.
- Produces: `elegirPermiso(permisos, payload) → permiso|null` · `resolverIdentidad(plantillaJson|null, permiso, payload) → {k:v}` (los params forzados, `{}` si nada) · `mergeParams({specParams, paramsFijos, overrides, overridable, forzados}) → {params, locked}`.

- [ ] **Step 1: Test que falla**

`viz/test/publogic.test.js`:

```js
const { test } = require("node:test");
const assert = require("node:assert");
const { elegirPermiso, resolverIdentidad, mergeParams } = require("../lib/publogic");

const luis = { id: "u-luis", email: "luis@x.co", roles: ["Closer"], name: "Luis Fernando" };
const dire = { id: "u-dir", email: "dir@x.co", roles: ["Director Comercial"], name: "Lucho" };
const ambos = { id: "u-mix", email: "mix@x.co", roles: ["Closer", "Director Comercial"], name: "Mix" };

const pCloser = { user_id: null, rol: "Closer", params_identidad: null };
const pDire = { user_id: null, rol: "Director Comercial", params_identidad: "{}" };
const pUser = { user_id: "u-luis", rol: null, params_identidad: '{"closer":"Andrés"}' };

test("sin permiso que matchee → null", () => {
  assert.strictEqual(elegirPermiso([pCloser], { ...dire, roles: ["Editor"] }), null);
  assert.strictEqual(elegirPermiso([], luis), null);
});
test("permiso por rol matchea roles[] del JWT", () => {
  assert.strictEqual(elegirPermiso([pCloser, pDire], luis), pCloser);
  assert.strictEqual(elegirPermiso([pCloser, pDire], dire), pDire);
});
test("por-user gana sobre por-rol", () => {
  assert.strictEqual(elegirPermiso([pCloser, pUser], luis), pUser);
});
test("entre roles, gana el menos restrictivo ({} sobre plantilla)", () => {
  assert.strictEqual(elegirPermiso([pCloser, pDire], ambos), pDire);
});

test("identidad: NULL hereda la plantilla y sustituye variables", () => {
  const f = resolverIdentidad({ closer: "$name" }, pCloser, luis);
  assert.deepStrictEqual(f, { closer: "Luis Fernando" });
});
test("identidad: '{}' anula la plantilla", () => {
  assert.deepStrictEqual(resolverIdentidad({ closer: "$name" }, pDire, dire), {});
});
test("identidad: explícito manda tal cual", () => {
  assert.deepStrictEqual(resolverIdentidad({ closer: "$name" }, pUser, luis), { closer: "Andrés" });
});
test("identidad: sin plantilla y permiso NULL → nada forzado", () => {
  assert.deepStrictEqual(resolverIdentidad(null, pCloser, luis), {});
});
test("sustituye $email y $user_id", () => {
  const f = resolverIdentidad({ a: "$email", b: "$user_id" }, pCloser, luis);
  assert.deepStrictEqual(f, { a: "luis@x.co", b: "u-luis" });
});

test("merge: fijos → overrides (solo overridable) → forzados ganan", () => {
  const { params, locked } = mergeParams({
    specParams: { from: "2026-01-01" },
    paramsFijos: { project: "David Guerrero" },
    overrides: { closer: "Otro", to: "2026-08-01", hack: "x" },
    overridable: ["closer", "from", "to"],
    forzados: { closer: "Luis Fernando" },
  });
  assert.deepStrictEqual(params, {
    from: "2026-01-01", project: "David Guerrero", to: "2026-08-01", closer: "Luis Fernando",
  });
  assert.deepStrictEqual(locked, ["closer"]);
});
```

- [ ] **Step 2: Verlo fallar**

Run: `node --test viz/test/publogic.test.js` → FAIL (`Cannot find module`).

- [ ] **Step 3: Implementar `viz/lib/publogic.js`**

```js
// Lógica pura de permisos e identidad del publicador (viz/publish.js).
// El modelo (spec 2026-08-15): el despliegue declara la plantilla de identidad
// UNA vez; cada permiso decide con params_identidad si aplica (NULL hereda),
// se anula ('{}') o se fuerza otra cosa (json explícito).

// Rango de restrictividad de un permiso: '{}' (nada forzado) es el menos
// restrictivo; el explícito fuerza valores propios; NULL hereda la plantilla.
function rango(p) {
  if (p.params_identidad == null) return 2;
  const parsed = JSON.parse(p.params_identidad);
  return Object.keys(parsed).length === 0 ? 0 : 1;
}

// user > rol; entre roles, el menos restrictivo. Determinista.
function elegirPermiso(permisos, payload) {
  if (!payload) return null;
  const roles = new Set(payload.roles || []);
  const porUser = permisos.filter((p) => p.user_id && p.user_id === payload.id);
  if (porUser.length) return porUser.sort((a, b) => rango(a) - rango(b))[0];
  const porRol = permisos.filter((p) => p.rol && roles.has(p.rol));
  if (!porRol.length) return null;
  return porRol.sort((a, b) => rango(a) - rango(b))[0];
}

// → los params FORZADOS para este visitante ({} = nada forzado).
function resolverIdentidad(plantilla, permiso, payload) {
  let base;
  if (permiso.params_identidad == null) base = plantilla || {};
  else base = JSON.parse(permiso.params_identidad);
  const out = {};
  const vars = { $name: payload.name, $email: payload.email, $user_id: payload.id };
  for (const [k, v] of Object.entries(base)) {
    out[k] = typeof v === "string" && v in vars ? String(vars[v] ?? "") : v;
  }
  return out;
}

// Precedencia del spec: fijos → overrides del navegador (whitelist) → forzados.
function mergeParams({ specParams, paramsFijos, overrides, overridable, forzados }) {
  const params = { ...(specParams || {}), ...(paramsFijos || {}) };
  for (const k of overridable || []) {
    const v = (overrides || {})[k];
    if (v != null && v !== "") params[k] = v;
  }
  Object.assign(params, forzados || {});
  return { params, locked: Object.keys(forzados || {}) };
}

module.exports = { elegirPermiso, resolverIdentidad, mergeParams };
```

- [ ] **Step 4: Verlo pasar**

Run: `node --test viz/test/publogic.test.js` → PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
git add viz/lib/publogic.js viz/test/publogic.test.js
git commit -m "publicar: lógica de permisos e identidad (elegirPermiso/resolverIdentidad/mergeParams)"
```

---

### Task 3: `viz/lib/pubauth.js` — JWT HS256 + cookies + login proxy

**Files:**
- Create: `viz/lib/pubauth.js`
- Test: `viz/test/pubauth.test.js`

**Interfaces:**
- Produces: `verifyJWT(token, secret) → payload|null` · `firmarJWT(payload, secret, {expSeg}) → token` (usado por tests y por la verificación operativa de Task 8) · `parseCookies(header) → {k:v}` · `cookieSesion(token, maxAgeSeg) → string` (Set-Cookie) · `cookieBorrar() → string` · `loginMarketico(email, password) → Promise<token|null>` (fetch a `MARKETICO_AUTH_URL`, default `https://ikigaigm.api.parallelo.ai/api/auth/login`).
- Cookie: nombre `viz_sesion`, `HttpOnly; Path=/; SameSite=Lax` + `Secure` salvo `PUBLISH_SECURE=0` (dev http local).

- [ ] **Step 1: Test que falla**

`viz/test/pubauth.test.js`:

```js
const { test } = require("node:test");
const assert = require("node:assert");
const { verifyJWT, firmarJWT, parseCookies, cookieSesion, cookieBorrar } = require("../lib/pubauth");

const SECRET = "secreto-de-prueba";

test("firma y verifica un JWT HS256", () => {
  const t = firmarJWT({ id: "u1", roles: ["Closer"], name: "Luis" }, SECRET, { expSeg: 60 });
  const p = verifyJWT(t, SECRET);
  assert.strictEqual(p.id, "u1");
  assert.deepStrictEqual(p.roles, ["Closer"]);
});
test("rechaza firma inválida / secreto distinto / basura", () => {
  const t = firmarJWT({ id: "u1" }, SECRET, { expSeg: 60 });
  assert.strictEqual(verifyJWT(t + "x", SECRET), null);
  assert.strictEqual(verifyJWT(t, "otro"), null);
  assert.strictEqual(verifyJWT("no.es.jwt", SECRET), null);
  assert.strictEqual(verifyJWT(null, SECRET), null);
});
test("rechaza token expirado", () => {
  const t = firmarJWT({ id: "u1" }, SECRET, { expSeg: -10 });
  assert.strictEqual(verifyJWT(t, SECRET), null);
});
test("rechaza alg distinto de HS256 (p.ej. none)", () => {
  const h = Buffer.from(JSON.stringify({ alg: "none", typ: "JWT" })).toString("base64url");
  const p = Buffer.from(JSON.stringify({ id: "u1" })).toString("base64url");
  assert.strictEqual(verifyJWT(`${h}.${p}.`, SECRET), null);
});
test("parseCookies", () => {
  assert.deepStrictEqual(parseCookies("a=1; viz_sesion=tok; b=2").viz_sesion, "tok");
  assert.deepStrictEqual(parseCookies(undefined), {});
});
test("cookieSesion y cookieBorrar", () => {
  process.env.PUBLISH_SECURE = "0";
  assert.match(cookieSesion("tok", 3600), /^viz_sesion=tok; HttpOnly; Path=\/; SameSite=Lax; Max-Age=3600$/);
  delete process.env.PUBLISH_SECURE;
  assert.match(cookieSesion("tok", 3600), /; Secure$/);
  assert.match(cookieBorrar(), /Max-Age=0/);
});
```

- [ ] **Step 2: Verlo fallar**

Run: `node --test viz/test/pubauth.test.js` → FAIL.

- [ ] **Step 3: Implementar `viz/lib/pubauth.js`**

```js
// Autenticación del publicador: el JWT de Marketico verificado LOCALMENTE
// (HS256 + JWT_SECRET compartido — misma máquina, cero red por visita) y el
// manejo de la cookie de sesión. El login reenvía las credenciales UNA vez a
// la API de Marketico y no las persiste jamás.
const crypto = require("node:crypto");

const COOKIE = "viz_sesion";
const b64u = (buf) => Buffer.from(buf).toString("base64url");

function firmarJWT(payload, secret, { expSeg = 3600 } = {}) {
  const now = Math.floor(Date.now() / 1000);
  const h = b64u(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const p = b64u(JSON.stringify({ iat: now, exp: now + expSeg, ...payload }));
  const sig = crypto.createHmac("sha256", secret).update(`${h}.${p}`).digest("base64url");
  return `${h}.${p}.${sig}`;
}

function verifyJWT(token, secret) {
  if (!token || typeof token !== "string") return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [h, p, sig] = parts;
  let header, payload;
  try {
    header = JSON.parse(Buffer.from(h, "base64url").toString("utf8"));
    payload = JSON.parse(Buffer.from(p, "base64url").toString("utf8"));
  } catch {
    return null;
  }
  if (!header || header.alg !== "HS256") return null;
  const expected = crypto.createHmac("sha256", secret).update(`${h}.${p}`).digest("base64url");
  const a = Buffer.from(sig), b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  if (payload.exp != null && payload.exp * 1000 <= Date.now()) return null;
  return payload;
}

function parseCookies(header) {
  const out = {};
  for (const part of String(header || "").split(";")) {
    const i = part.indexOf("=");
    if (i > 0) out[part.slice(0, i).trim()] = part.slice(i + 1).trim();
  }
  return out;
}

const seguro = () => (process.env.PUBLISH_SECURE === "0" ? "" : "; Secure");
const cookieSesion = (token, maxAgeSeg) =>
  `${COOKIE}=${token}; HttpOnly; Path=/; SameSite=Lax; Max-Age=${maxAgeSeg}${seguro()}`;
const cookieBorrar = () => `${COOKIE}=; HttpOnly; Path=/; SameSite=Lax; Max-Age=0${seguro()}`;

const AUTH_URL = () => process.env.MARKETICO_AUTH_URL || "https://ikigaigm.api.parallelo.ai/api/auth/login";

async function loginMarketico(email, password) {
  const res = await fetch(AUTH_URL(), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  if (!res.ok) return null;
  const data = await res.json().catch(() => null);
  return (data && data.success && data.data && data.data.token) || null;
}

module.exports = { COOKIE, firmarJWT, verifyJWT, parseCookies, cookieSesion, cookieBorrar, loginMarketico };
```

- [ ] **Step 4: Verlo pasar**

Run: `node --test viz/test/pubauth.test.js` → PASS. Luego `npm run test:viz` → PASS (todo junto).

- [ ] **Step 5: Commit**

```bash
git add viz/lib/pubauth.js viz/test/pubauth.test.js
git commit -m "publicar: verificación local del JWT de Marketico + cookie de sesión"
```

---

### Task 4: Extraer `standalone()` a `lib/html.js` (refactor compartido)

**Files:**
- Modify: `viz/lib/html.js` (agregar y exportar `standalone(ui)`)
- Modify: `viz/server.js:144-155` (borrar la función local, importarla de `./lib/html`)

**Interfaces:**
- Produces: `standalone(ui) → string` — la página full-page de una UI (la que hoy vive inline en server.js), byte-idéntica. La consumen server.js (`/u/:id`) y publish.js (Task 5).

- [ ] **Step 1: Mover la función**

Cortar `standalone(ui)` de `viz/server.js:144-155` y pegarla en `viz/lib/html.js` tal cual (con sus requires ya presentes ahí: `renderPane`, `loadTheme`, `themeHead`, `escape` — agregar los que falten al require del archivo). Exportarla en el `module.exports` de html.js. En server.js, agregar `standalone` al require de `./lib/html` y borrar la definición local.

- [ ] **Step 2: Verificar regresión — el viz local bootea y `/u/:id` rinde igual**

```bash
npm run viz:restart && sleep 1
curl -s http://localhost:4317/health          # → ok
curl -s http://localhost:4317/u/dashboard-por-closer | head -c 400   # → <!doctype html>… con <title>
npm run test:viz                              # → PASS
```

- [ ] **Step 3: Commit**

```bash
git add viz/lib/html.js viz/server.js
git commit -m "viz: extraer standalone() a lib/html — compartido con el publicador"
```

---

### Task 5: `viz/publish.js` — el servidor de producción

**Files:**
- Create: `viz/publish.js`
- Modify: `package.json` (script `"viz:publish": "node viz/publish.js"`)

**Interfaces:**
- Consumes: `pubstore` (Task 1), `publogic` (Task 2), `pubauth` (Task 3), `standalone` (Task 4), `renderPane`/`overridableFor` de `lib/components.js`, `startSSE`/`patchElements` de `lib/sse.js`, `loadTheme`/`themeHead` de `lib/theme.js`.
- Produces: HTTP en `PORT` (default 4318) / `HOST` (default 127.0.0.1). Rutas: `/health`, assets, `GET|POST /login`, `POST|GET /logout`, `GET /s/:codigo`, `GET /ui/:specId` (SSE), `GET /u/:specId` (redirect), `GET /:slug`.
- Env (leídos de `<repo>/.env` + entorno): `JWT_SECRET` (obligatorio — sin él, aborta el boot), `MARKETICO_AUTH_URL`, `PUBLICACIONES_DB`, `PUBLISH_SECURE`.

- [ ] **Step 1: Escribir `viz/publish.js`**

```js
#!/usr/bin/env node
// El PUBLICADOR — el entrypoint de PRODUCCIÓN del viz (pm2 «viz-publish»).
// Sirve únicamente las UIs registradas en data/sqlite/publicaciones.db, con
// datos vivos, login contra Marketico (JWT verificado localmente) y permisos
// con alcance por identidad. Superficie mínima POR CONSTRUCCIÓN: no existe el
// shell, ni creación/edición de UIs, ni acts POST — lib/actions.js no se
// importa. Diseño: docs/superpowers/specs/2026-08-15-viz-publish-design.md
//
//   GET  /:slug        render standalone del despliegue (auth + permiso)
//   GET  /s/:codigo    alias corto → 302 /:slug
//   GET  /ui/:specId   SSE re-render (los @get de las páginas) — params forzados
//   GET  /u/:specId    «abrir solo» de las páginas → 302 /:slug
//   GET|POST /login    página + proxy de credenciales a Marketico
//   POST|GET /logout   borra la cookie
//   GET  /health       liveness
//
// Run:  PORT=4318 node viz/publish.js   (HOST default 127.0.0.1 — solo nginx)

const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const pubstore = require("./lib/pubstore");
const { elegirPermiso, resolverIdentidad, mergeParams } = require("./lib/publogic");
const { COOKIE, verifyJWT, parseCookies, cookieSesion, cookieBorrar, loginMarketico } = require("./lib/pubauth");
const { standalone } = require("./lib/html");
const { renderPane, overridableFor, escape } = require("./lib/components");
const { startSSE, patchElements } = require("./lib/sse");
const { loadTheme, themeHead } = require("./lib/theme");

const REPO_ROOT = path.resolve(__dirname, "..");
const PORT = Number(process.env.PORT) || 4318;
const HOST = process.env.HOST || "127.0.0.1";

// .env del checkout — publish.js necesita JWT_SECRET sin depender de pm2 env.
for (const line of (() => { try { return fs.readFileSync(path.join(REPO_ROOT, ".env"), "utf8").split("\n"); } catch { return []; } })()) {
  const m = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim());
  if (m && process.env[m[1]] == null) process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
}
if (!process.env.JWT_SECRET) {
  console.error("FALTA JWT_SECRET (en .env o el entorno) — sin él no se puede verificar ninguna sesión.");
  process.exit(1);
}

const PUBLIC_FILES = new Set(["/datastar.js", "/chart.umd.js", "/charts-init.js", "/tw-bridge.js", "/tokens.css"]);
const RUTAS_RESERVADAS = new Set(["login", "logout", "health", "ui", "u", "c", "s", "api", "fonts"]);

function send(res, status, body, type = "text/html; charset=utf-8", extra = {}) {
  res.writeHead(status, { "Content-Type": type, ...extra });
  res.end(body);
}
const redirect = (res, to, extra = {}) => { res.writeHead(303, { Location: to, ...extra }); res.end(); };

function readBody(req) {
  return new Promise((resolve) => {
    let data = "";
    req.on("data", (c) => (data += c));
    req.on("end", () => resolve(data));
  });
}

// --- login ------------------------------------------------------------------
// `next` solo puede ser una ruta interna simple — nunca una URL absoluta.
const nextSeguro = (v) => (/^\/[a-zA-Z0-9\-/]*$/.test(v || "") ? v : "/");

function paginaLogin({ next = "/", error = "" } = {}) {
  const theme = loadTheme();
  return `<!doctype html><html lang="es" data-theme="${theme.modo}"><head>
  <meta charset="utf-8" /><meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Entrar · ${escape(theme.nombre)}</title>${themeHead(theme)}</head>
  <body class="min-h-screen flex items-center justify-center" style="background:var(--surface-2)">
    <form method="POST" action="/login" class="card card-pad w-full" style="max-width:22rem">
      <h1 class="text-lg font-bold mb-1" style="color:var(--text-1)">${escape(theme.nombre)}</h1>
      <p class="text-sm mb-4" style="color:var(--text-3)">Entra con tu cuenta de la plataforma.</p>
      ${error ? `<div class="alert alert-neg mb-3 text-sm">${escape(error)}</div>` : ""}
      <input type="hidden" name="next" value="${escape(next)}" />
      <label class="text-xs font-semibold" style="color:var(--text-2)">Email</label>
      <input class="input w-full mb-3" type="email" name="email" required autofocus autocomplete="email" />
      <label class="text-xs font-semibold" style="color:var(--text-2)">Contraseña</label>
      <input class="input w-full mb-4" type="password" name="password" required autocomplete="current-password" />
      <button class="btn btn-brand w-full" type="submit">Entrar</button>
    </form>
  </body></html>`;
}

// --- resolución despliegue → ui lista para render ---------------------------
function accesoA(despliegue, payload) {
  const permiso = elegirPermiso(pubstore.permisosDe(despliegue.slug), payload);
  if (!permiso) return null;
  const plantilla = despliegue.identidad ? JSON.parse(despliegue.identidad) : null;
  return resolverIdentidad(plantilla, permiso, payload);
}

function uiRenderizable(despliegue, overrides, forzados) {
  const spec = JSON.parse(despliegue.spec_json);
  const { params, locked } = mergeParams({
    specParams: spec.params,
    paramsFijos: JSON.parse(despliegue.params_fijos || "{}"),
    overrides,
    overridable: overridableFor(spec),
    forzados,
  });
  return { ...spec, params, _locked: locked };
}

// Busca entre los despliegues de un spec el primero al que payload tiene
// permiso (resuelve /ui/:specId y /u/:specId — los links que emiten las páginas).
function despliegueDeSpec(specId, payload) {
  for (const d of pubstore.porSpecId(specId)) {
    const forzados = accesoA(d, payload);
    if (forzados !== null) return { despliegue: d, forzados };
  }
  return null;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const { pathname } = url;
  try {
    if (pathname === "/health") return send(res, 200, "ok", "text/plain");

    // --- assets (sin auth: la página de login los necesita) ---
    const isFont = /^\/fonts\/[a-z0-9._-]+\.(woff2|css)$/.test(pathname);
    if ((PUBLIC_FILES.has(pathname) || isFont) && req.method === "GET") {
      const file = path.join(__dirname, "public", pathname.slice(1));
      const body = fs.readFileSync(file);
      return send(res, 200, body, pathname.endsWith(".css") ? "text/css; charset=utf-8"
        : pathname.endsWith(".woff2") ? "font/woff2" : "text/javascript; charset=utf-8",
        { "Cache-Control": "public, max-age=86400" });
    }

    // --- login / logout ---
    if (pathname === "/login" && req.method === "GET")
      return send(res, 200, paginaLogin({ next: nextSeguro(url.searchParams.get("next")) }));
    if (pathname === "/login" && req.method === "POST") {
      const body = new URLSearchParams(await readBody(req));
      const next = nextSeguro(body.get("next"));
      const token = await loginMarketico(String(body.get("email") || "").trim(), String(body.get("password") || ""))
        .catch(() => null);
      if (!token) return send(res, 401, paginaLogin({ next, error: "Credenciales inválidas." }));
      const payload = verifyJWT(token, process.env.JWT_SECRET);
      if (!payload) return send(res, 401, paginaLogin({ next, error: "La plataforma devolvió una sesión inválida." }));
      const maxAge = payload.exp ? Math.max(60, payload.exp - Math.floor(Date.now() / 1000)) : 86400;
      return redirect(res, next, { "Set-Cookie": cookieSesion(token, maxAge) });
    }
    if (pathname === "/logout")
      return redirect(res, "/login", { "Set-Cookie": cookieBorrar() });

    // --- alias corto (sin auth: solo redirige; el login gatea el destino) ---
    let m;
    if ((m = /^\/s\/([A-Za-z0-9]+)$/.exec(pathname)) && req.method === "GET") {
      const d = pubstore.porCodigo(m[1]);
      return d ? redirect(res, `/${d.slug}`) : send(res, 404, "No encontrado", "text/plain");
    }

    // --- todo lo demás requiere sesión ---
    const payload = verifyJWT(parseCookies(req.headers.cookie)[COOKIE], process.env.JWT_SECRET);
    if (!payload) {
      if (req.method === "GET") return send(res, 200, paginaLogin({ next: nextSeguro(pathname) }));
      return send(res, 401, "Sesión requerida", "text/plain");
    }

    // --- SSE re-render: los @get('/ui/<specId>?…') que emiten las páginas ---
    if ((m = /^\/ui\/([a-z0-9-]+)$/.exec(pathname)) && req.method === "GET") {
      const hit = despliegueDeSpec(m[1], payload);
      if (!hit) return send(res, 404, "No encontrado", "text/plain");
      const ui = uiRenderizable(hit.despliegue, Object.fromEntries(url.searchParams), hit.forzados);
      pubstore.visita(hit.despliegue.slug, payload, req.url);
      startSSE(res);
      patchElements(res, renderPane(ui));
      return res.end();
    }

    // --- «abrir solo ↗» de las páginas → la URL canónica del despliegue ---
    if ((m = /^\/u\/([a-z0-9-]+)$/.exec(pathname)) && req.method === "GET") {
      const hit = despliegueDeSpec(m[1], payload);
      return hit ? redirect(res, `/${hit.despliegue.slug}`) : send(res, 404, "No encontrado", "text/plain");
    }

    // --- la ruta legible: GET /<slug> ---
    if ((m = /^\/([a-z0-9][a-z0-9-]*)$/.exec(pathname)) && req.method === "GET" && !RUTAS_RESERVADAS.has(m[1])) {
      const d = pubstore.vigente(m[1]);
      if (!d) return send(res, 404, "No encontrado", "text/plain");
      const forzados = accesoA(d, payload);
      if (forzados === null) return send(res, 404, "No encontrado", "text/plain");
      const ui = uiRenderizable(d, Object.fromEntries(url.searchParams), forzados);
      pubstore.visita(d.slug, payload, req.url);
      return send(res, 200, standalone(ui));
    }

    return send(res, 404, "No encontrado", "text/plain");
  } catch (e) {
    console.error(`[publish] ${req.method} ${pathname}: ${e.message}`);
    return send(res, 500, "Error interno", "text/plain");
  }
});

try { pubstore.vigente("health-probe"); } catch {
  console.warn("[publish] publicaciones.db no existe aún — todo responderá 404 hasta la primera publicación.");
}

server.listen(PORT, HOST, () => console.log(`viz-publish on http://${HOST}:${PORT}`));
```

Nota de diseño que el código sostiene: `accesoA` devuelve `null` (sin permiso) vs `{}` (permiso sin nada forzado) — la distinción `null`/objeto es la que separa 404 de render libre; no colapsarla.

- [ ] **Step 2: Agregar el npm script**

En `package.json`: `"viz:publish": "node viz/publish.js"`.

- [ ] **Step 3: Prueba manual local — fixture + los 5 escenarios**

```bash
# 1. Registro local de prueba (data/sqlite/ es git-ignored)
sqlite3 data/sqlite/publicaciones.db < bash/publicar/schema.sql
SPEC=$(node -e 'console.log(JSON.stringify(JSON.stringify(require("./viz/lib/store").get("dashboard-por-closer"))))')
sqlite3 data/sqlite/publicaciones.db "INSERT INTO despliegues (slug,codigo_corto,spec_id,spec_json,component,source,identidad)
  VALUES ('dashboard-closer','PrUeBa1234','dashboard-por-closer',$(echo $SPEC | python3 -c "import sys,json; s=json.loads(sys.stdin.read()); print(\"'\"+s.replace(\"'\",\"''\")+\"'\")"),'closer-dashboard','closer_dashboard','{\"closer\":\"\$name\"}');
  INSERT INTO permisos (slug,rol,params_identidad) VALUES ('dashboard-closer','Closer',NULL);
  INSERT INTO permisos (slug,rol,params_identidad) VALUES ('dashboard-closer','Director Comercial','{}');"

# 2. Tokens de prueba (usa un nombre de closer REAL — ver bash/calls/calls.sh --limit 5)
export JWT_SECRET=test-secret PUBLISH_SECURE=0
TOK_CLOSER=$(node -e 'const{firmarJWT}=require("./viz/lib/pubauth");console.log(firmarJWT({id:"u-test",email:"c@x.co",roles:["Closer"],name:"<NOMBRE CLOSER REAL>"},"test-secret",{expSeg:3600}))')
TOK_DIRE=$(node -e 'const{firmarJWT}=require("./viz/lib/pubauth");console.log(firmarJWT({id:"u-dir",email:"d@x.co",roles:["Director Comercial"],name:"Dire"},"test-secret",{expSeg:3600}))')
TOK_NADIE=$(node -e 'const{firmarJWT}=require("./viz/lib/pubauth");console.log(firmarJWT({id:"u-n",email:"n@x.co",roles:["Editor"],name:"Nadie"},"test-secret",{expSeg:3600}))')

PORT=4318 node viz/publish.js &   # (o en otra terminal)
sleep 1
```

Verificaciones (cada una con su resultado esperado):

```bash
curl -s localhost:4318/health                                          # ok
curl -s localhost:4318/dashboard-closer | grep -c 'name="password"'    # 1  (sin sesión → login)
curl -s -b "viz_sesion=$TOK_NADIE" localhost:4318/dashboard-closer -o /dev/null -w '%{http_code}\n'  # 404 (sin permiso)
curl -s -b "viz_sesion=$TOK_CLOSER" localhost:4318/dashboard-closer | grep -c '<NOMBRE CLOSER REAL>' # ≥1 (forzado a su nombre)
curl -s -b "viz_sesion=$TOK_CLOSER" 'localhost:4318/dashboard-closer?closer=Otro%20Closer' | grep -c '<NOMBRE CLOSER REAL>'  # ≥1 (override pisado)
curl -s -b "viz_sesion=$TOK_DIRE" 'localhost:4318/ui/dashboard-por-closer?closer=<NOMBRE CLOSER REAL>' | head -c 200  # SSE datastar-patch-elements con el dashboard
curl -s -b "viz_sesion=$TOK_CLOSER" localhost:4318/s/PrUeBa1234 -o /dev/null -w '%{http_code} %{redirect_url}\n'  # 303 …/dashboard-closer
```

(El render del closer tarda ~1-3 s: consulta la DB real. Es lo esperado.)

- [ ] **Step 4: Matar el server de prueba y commit**

```bash
kill %1 2>/dev/null; rm data/sqlite/publicaciones.db
git add viz/publish.js package.json
git commit -m "publicar: viz/publish.js — el servidor de producción (login, permisos, identidad)"
```

---

### Task 6: `closer-dashboard` — chip fijo cuando `closer` está bloqueado

**Files:**
- Modify: `viz/pages/closer-dashboard.js:117-134` (el bloque `reget` + `controls`)

**Interfaces:**
- Consumes: `ui._locked` (array de params forzados) que publish.js inyecta en Task 5; en el viz local nunca existe → cero cambio de comportamiento.

- [ ] **Step 1: Editar el bloque de controles**

Reemplazar las líneas 117-134 (desde `const reget =` hasta el cierre de `controls`) por:

```js
  // Selector + ventana. Si `closer` viene FORZADO por identidad (publicador:
  // ui._locked), el dropdown no se pinta — chip fijo; y el re-fetch no emite
  // el param (el servidor lo fuerza igual: el chip es UX, no seguridad).
  const bloqueado = (ui._locked || []).includes("closer");
  const reget = bloqueado
    ? `@get('/ui/${escape(ui.id)}?from='+$cdFrom+'&to='+$cdTo)`
    : `@get('/ui/${escape(ui.id)}?closer='+encodeURIComponent($cdCloser)+'&from='+$cdFrom+'&to='+$cdTo)`;
  const opts = closers
    .map((c) => {
      const parts = [c.llamadas != null ? `${c.llamadas} llamadas` : null, c.ventas != null ? `${c.ventas} ventas` : null]
        .filter(Boolean)
        .join(" · ");
      return `<option value="${escape(c.closer)}"${c.closer === cur ? " selected" : ""}>${escape(c.closer)}${parts ? ` — ${escape(parts)}` : ""}</option>`;
    })
    .join("");
  const selector = bloqueado
    ? `<span class="badge badge-brand text-sm">${escape(cur || "—")}</span>`
    : `<select data-bind="cdCloser" data-on:change="${reget}" data-indicator:loadingcloser class="select w-auto font-medium">${opts}</select>`;
  const signals = bloqueado
    ? `{cdFrom:${escape(jsStr(per.from || ""))},cdTo:${escape(jsStr(per.to || ""))}}`
    : `{cdCloser:${escape(jsStr(cur))},cdFrom:${escape(jsStr(per.from || ""))},cdTo:${escape(jsStr(per.to || ""))}}`;
  const controls = `<div class="flex flex-wrap items-center gap-3 mt-4" data-signals="${signals}">
    ${selector}
    <input type="date" data-bind="cdFrom" data-on:change="${reget}" data-indicator:loadingcloser class="input w-auto" />
    <span style="color:var(--text-3)">~</span>
    <input type="date" data-bind="cdTo" data-on:change="${reget}" data-indicator:loadingcloser class="input w-auto" />
    <span class="text-xs" style="color:var(--text-3)">sin fechas = toda la historia</span>
  </div>`;
```

- [ ] **Step 2: Verificar los dos modos**

```bash
npm run viz:restart && sleep 1
# local (sin _locked): el dropdown sigue
curl -s 'http://localhost:4317/u/dashboard-por-closer' | grep -c 'data-bind="cdCloser"'   # 1
# publicado (con _locked): repetir el fixture de Task 5 paso 3 y:
#   curl -s -b "viz_sesion=$TOK_CLOSER" localhost:4318/dashboard-closer | grep -c 'data-bind="cdCloser"'  # 0
#   … | grep -c 'badge-brand'                                                                             # ≥1 (el chip)
npm run test:viz   # PASS — nada de lo puro cambió
```

- [ ] **Step 3: Commit**

```bash
git add viz/pages/closer-dashboard.js
git commit -m "closer-dashboard: chip fijo cuando la identidad bloquea el closer"
```

---

### Task 7: `bash/publicar/` — publicar, permisos y desplegar por conversación

**Files:**
- Create: `bash/publicar/lib.sh`
- Create: `bash/publicar/publicar_ui.sh`
- Create: `bash/publicar/permiso_ui.sh`
- Create: `bash/publicar/desplegar.sh`

**Interfaces:**
- Consumes: `viz/lib/store` (spec local por id, vía `node -e`), `bash/lib/common.sh` (`psql_ro` para resolver `--user` email→users.id), `bash/publicar/schema.sql` (Task 1), ssh `root@api`.
- Produces: filas en el sqlite REMOTO `/apps/hermetico/data/sqlite/publicaciones.db`. Env overrides: `PUBLICAR_SSH` (default `root@api`), `PUBLICAR_DIR` (default `/apps/hermetico`), `PUBLICAR_URL` (default `https://app.ikigaigm.parallelo.ai`).

- [ ] **Step 1: `bash/publicar/lib.sh`**

```bash
#!/usr/bin/env bash
# Helpers del dominio publicar — operan el registro REMOTO del publicador
# (viz/publish.js) por ssh. El sql viaja por stdin (jamás argv del remoto).
set -euo pipefail
PUBLICAR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$PUBLICAR_LIB_DIR/../.." && pwd)"

PUB_SSH="${PUBLICAR_SSH:-root@api}"
PUB_DIR="${PUBLICAR_DIR:-/apps/hermetico}"
PUB_DB="$PUB_DIR/data/sqlite/publicaciones.db"
PUB_URL="${PUBLICAR_URL:-https://app.ikigaigm.parallelo.ai}"

# sql_lit <v> : literal SQL con comillas escapadas.
sql_lit() { printf "'%s'" "${1//\'/\'\'}"; }

# remote_sql [-json] : ejecuta el SQL de stdin en el registro remoto.
remote_sql() {
  local flags=(); [[ "${1:-}" == "-json" ]] && flags=(-json)
  ssh "$PUB_SSH" "mkdir -p '$PUB_DIR/data/sqlite' && sqlite3 ${flags[*]:-} '$PUB_DB'"
}

# ensure_schema : aplica el schema idempotente antes de cualquier escritura.
ensure_schema() { remote_sql < "$PUBLICAR_LIB_DIR/schema.sql"; }

# spec_local <id> : el spec JSON (una línea) desde el store del viz, o falla.
spec_local() {
  node -e '
    const s = require(process.argv[1] + "/viz/lib/store").get(process.argv[2]);
    if (!s) { console.error("Spec no encontrado: " + process.argv[2]); process.exit(1); }
    const { _layer, _file, ...clean } = s;
    console.log(JSON.stringify(clean));
  ' "$REPO_ROOT" "$1"
}

# validar_spec <json> : validateSpec del viz; imprime errores y falla si hay.
validar_spec() {
  node -e '
    const v = require(process.argv[1] + "/viz/lib/components").validateSpec(JSON.parse(process.argv[2]));
    for (const e of v.errors) console.error("ERROR: " + e);
    if (v.errors.length) process.exit(1);
  ' "$REPO_ROOT" "$1"
}

# codigo_nuevo : 10 chars base62 aleatorios.
codigo_nuevo() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c 10; }
```

- [ ] **Step 2: `bash/publicar/publicar_ui.sh`**

```bash
#!/usr/bin/env bash
# publicar_ui.sh <spec-id> --slug <slug> [--identidad k=v]... [--fijar k=v]...
#                [--archivar] [--dry-run] [--json]     [WRITE remoto]
# Publica (o re-publica: generación+1) un spec del viz como despliegue del
# publicador. El spec viaja CONGELADO (snapshot); la identidad es la plantilla
# {"k":"$name|$email|$user_id|literal"}. --archivar despublica (sella, no borra).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -6; exit "${1:-0}"; }

SPEC_ID="" SLUG="" DRY=0 JSON=0 ARCHIVAR=0
declare -A IDENT FIJAR
while [[ $# -gt 0 ]]; do case "$1" in
  --slug) SLUG="$2"; shift 2;;
  --identidad) k="${2%%=*}"; IDENT[$k]="${2#*=}"; shift 2;;
  --fijar) k="${2%%=*}"; FIJAR[$k]="${2#*=}"; shift 2;;
  --archivar) ARCHIVAR=1; shift;;
  --dry-run) DRY=1; shift;;
  --json) JSON=1; shift;;
  -h|--help) usage;;
  -*) echo "Flag desconocido: $1" >&2; usage 2;;
  *) SPEC_ID="$1"; shift;;
esac; done
[[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] || { echo "Slug inválido (a-z 0-9 -): '$SLUG'" >&2; exit 2; }

if [[ $ARCHIVAR -eq 1 ]]; then
  SQL="UPDATE despliegues SET archivado_at=datetime('now') WHERE slug=$(sql_lit "$SLUG") AND archivado_at IS NULL;"
  [[ $DRY -eq 1 ]] && { echo "[dry-run] $SQL"; exit 0; }
  ensure_schema; printf '%s\n' "$SQL" | remote_sql
  echo "Despliegue '$SLUG' archivado."; exit 0
fi

[[ -n "$SPEC_ID" ]] || usage 2
SPEC_JSON="$(spec_local "$SPEC_ID")"
validar_spec "$SPEC_JSON"
COMPONENT="$(node -pe 'JSON.parse(process.argv[1]).component || ""' "$SPEC_JSON")"
SOURCE="$(node -pe 'JSON.parse(process.argv[1]).source || ""' "$SPEC_JSON")"

# json de identidad y fijos desde los pares k=v
to_json() { node -e '
  const out = {}; for (const kv of process.argv.slice(1)) { const i = kv.indexOf("=");
    out[kv.slice(0, i)] = kv.slice(i + 1); } console.log(JSON.stringify(out));' "$@"; }
IDENT_ARGS=(); for k in "${!IDENT[@]}"; do IDENT_ARGS+=("$k=${IDENT[$k]}"); done
FIJAR_ARGS=(); for k in "${!FIJAR[@]}"; do FIJAR_ARGS+=("$k=${FIJAR[$k]}"); done
IDENT_JSON="$([[ ${#IDENT_ARGS[@]} -gt 0 ]] && to_json "${IDENT_ARGS[@]}" || echo "")"
FIJAR_JSON="$([[ ${#FIJAR_ARGS[@]} -gt 0 ]] && to_json "${FIJAR_ARGS[@]}" || echo "{}")"

ensure_schema
PREV="$(printf 'SELECT max(generacion) || "|" || codigo_corto FROM despliegues WHERE slug=%s;' "$(sql_lit "$SLUG")" | remote_sql)"
GEN=$(( ${PREV%%|*} + 1 )) 2>/dev/null || GEN=1
[[ -z "$PREV" ]] && GEN=1
CODIGO="${PREV#*|}"; [[ -z "$PREV" ]] && CODIGO="$(codigo_nuevo)"

SQL="INSERT INTO despliegues (slug, codigo_corto, spec_id, spec_json, component, source, params_fijos, identidad, generacion)
VALUES ($(sql_lit "$SLUG"), $(sql_lit "$CODIGO"), $(sql_lit "$SPEC_ID"), $(sql_lit "$SPEC_JSON"),
        $(sql_lit "$COMPONENT"), $(sql_lit "$SOURCE"), $(sql_lit "$FIJAR_JSON"),
        $([[ -n "$IDENT_JSON" ]] && sql_lit "$IDENT_JSON" || echo NULL), $GEN);"

if [[ $DRY -eq 1 ]]; then echo "[dry-run] generación $GEN de '$SLUG':"; echo "$SQL"; exit 0; fi
printf '%s\n' "$SQL" | remote_sql

if [[ $JSON -eq 1 ]]; then
  node -e 'console.log(JSON.stringify({slug: process.argv[1], generacion: Number(process.argv[2]),
    codigo: process.argv[3], url: process.argv[4] + "/" + process.argv[1],
    url_corta: process.argv[4] + "/s/" + process.argv[3]}))' "$SLUG" "$GEN" "$CODIGO" "$PUB_URL"
else
  echo "Publicado '$SLUG' (generación $GEN, spec $SPEC_ID)"
  echo "  URL:   $PUB_URL/$SLUG"
  echo "  Corta: $PUB_URL/s/$CODIGO"
  echo "Ahora dale permisos: bash/publicar/permiso_ui.sh $SLUG --rol '<Rol>'"
fi
```

- [ ] **Step 3: `bash/publicar/permiso_ui.sh`**

```bash
#!/usr/bin/env bash
# permiso_ui.sh <slug> --rol <Rol> | --user <email>
#               [--identidad k=v]... | --sin-identidad
#               [--revocar] | [--listar] | [--visitas]  [--dry-run] [--json]
# Permisos de un despliegue publicado.        [WRITE remoto]
#   sin flags de identidad  → NULL  (hereda la plantilla del despliegue)
#   --sin-identidad         → '{}'  (anula la plantilla: ve todo — p.ej. Director)
#   --identidad k=v         → json explícito (excepciones)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$REPO_ROOT/bash/lib/common.sh"   # psql_ro para resolver email → users.id

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -8; exit "${1:-0}"; }

SLUG="" ROL="" EMAIL="" REVOCAR=0 LISTAR=0 VISITAS=0 SIN_IDENT=0 DRY=0 JSON=0
declare -A IDENT
while [[ $# -gt 0 ]]; do case "$1" in
  --rol) ROL="$2"; shift 2;;
  --user) EMAIL="$2"; shift 2;;
  --identidad) k="${2%%=*}"; IDENT[$k]="${2#*=}"; shift 2;;
  --sin-identidad) SIN_IDENT=1; shift;;
  --revocar) REVOCAR=1; shift;;
  --listar) LISTAR=1; shift;;
  --visitas) VISITAS=1; shift;;
  --dry-run) DRY=1; shift;;
  --json) JSON=1; shift;;
  -h|--help) usage;;
  -*) echo "Flag desconocido: $1" >&2; usage 2;;
  *) SLUG="$1"; shift;;
esac; done
[[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] || { echo "Slug inválido: '$SLUG'" >&2; exit 2; }

if [[ $LISTAR -eq 1 ]]; then
  printf 'SELECT id, coalesce(rol, "user:" || user_id) sujeto, coalesce(params_identidad, "(hereda)") identidad,
          creado_at, coalesce(revocado_at, "") revocado FROM permisos WHERE slug=%s;' "$(sql_lit "$SLUG")" \
    | remote_sql -json; exit 0
fi
if [[ $VISITAS -eq 1 ]]; then
  printf 'SELECT email, count(*) n, max(ts) ultima FROM visitas WHERE slug=%s GROUP BY email ORDER BY ultima DESC LIMIT 50;' \
    "$(sql_lit "$SLUG")" | remote_sql -json; exit 0
fi

[[ -n "$ROL" || -n "$EMAIL" ]] || usage 2
[[ -n "$ROL" && -n "$EMAIL" ]] && { echo "Usa --rol O --user, no ambos" >&2; exit 2; }

USER_ID=""
if [[ -n "$EMAIL" ]]; then
  USER_ID="$(psql_ro -Atc "select id from users where lower(email)=lower('${EMAIL//\'/\'\'}')")"
  [[ -n "$USER_ID" ]] || { echo "No existe user con email '$EMAIL' (¿crear con /crear-usuario?)" >&2; exit 1; }
fi
if [[ -n "$ROL" ]]; then
  HAY="$(psql_ro -Atc "select count(*) from team_roles where name='${ROL//\'/\'\'}'")"
  [[ "$HAY" != "0" ]] || echo "AVISO: el rol '$ROL' no existe en team_roles — nadie lo matcheará." >&2
fi

SUJETO_SQL="$([[ -n "$ROL" ]] && printf 'rol=%s' "$(sql_lit "$ROL")" || printf 'user_id=%s' "$(sql_lit "$USER_ID")")"

if [[ $REVOCAR -eq 1 ]]; then
  SQL="UPDATE permisos SET revocado_at=datetime('now') WHERE slug=$(sql_lit "$SLUG") AND $SUJETO_SQL AND revocado_at IS NULL;"
else
  IDENT_SQL="NULL"
  [[ $SIN_IDENT -eq 1 ]] && IDENT_SQL="'{}'"
  if [[ ${#IDENT[@]} -gt 0 ]]; then
    PARES=(); for k in "${!IDENT[@]}"; do PARES+=("$k=${IDENT[$k]}"); done
    IDENT_SQL="$(sql_lit "$(node -e '
      const out = {}; for (const kv of process.argv.slice(1)) { const i = kv.indexOf("=");
        out[kv.slice(0, i)] = kv.slice(i + 1); } console.log(JSON.stringify(out));' "${PARES[@]}")")"
  fi
  SQL="INSERT INTO permisos (slug, rol, user_id, params_identidad)
       VALUES ($(sql_lit "$SLUG"), $([[ -n "$ROL" ]] && sql_lit "$ROL" || echo NULL),
               $([[ -n "$USER_ID" ]] && sql_lit "$USER_ID" || echo NULL), $IDENT_SQL);"
fi

[[ $DRY -eq 1 ]] && { echo "[dry-run] $SQL"; exit 0; }
ensure_schema; printf '%s\n' "$SQL" | remote_sql
echo "Hecho: $([[ $REVOCAR -eq 1 ]] && echo revocado || echo permiso creado) — '$SLUG' ${ROL:+rol=$ROL}${EMAIL:+user=$EMAIL}"
```

- [ ] **Step 4: `bash/publicar/desplegar.sh`**

```bash
#!/usr/bin/env bash
# desplegar.sh [--dry-run]   [WRITE remoto]
# Lleva el código al publicador: push a origin, pull en /apps/hermetico y
# restart de pm2 viz-publish. Para cambios de CÓDIGO; el registro no lo toca.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -4; exit 0; }

RAMA="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
if [[ $DRY -eq 1 ]]; then
  echo "[dry-run] git push origin $RAMA && ssh $PUB_SSH 'cd $PUB_DIR && git pull --ff-only && pm2 restart viz-publish'"
  exit 0
fi
git -C "$REPO_ROOT" push origin "$RAMA"
ssh "$PUB_SSH" "cd '$PUB_DIR' && git pull --ff-only && pm2 restart viz-publish --update-env"
sleep 1
ssh "$PUB_SSH" "curl -sf http://127.0.0.1:4318/health" && echo " ← viz-publish vivo"
```

- [ ] **Step 5: Probar en seco (sin servidor aún)**

```bash
chmod +x bash/publicar/*.sh
bash/publicar/publicar_ui.sh dashboard-por-closer --slug dashboard-closer --identidad 'closer=$name' --dry-run
# → [dry-run] generación … con el INSERT completo y el spec embebido
bash/publicar/permiso_ui.sh dashboard-closer --rol Closer --dry-run          # → [dry-run] INSERT permiso NULL
bash/publicar/permiso_ui.sh dashboard-closer --rol 'Director Comercial' --sin-identidad --dry-run  # → '{}'
bash/publicar/desplegar.sh --dry-run
```

(El dry-run de publicar_ui llega hasta el `SELECT max(generacion)` remoto — si el servidor aún no existe fallará ahí; aceptable: verificar al menos que spec_local + validar_spec + armado del SQL corren. Ajustar el orden si molesta: mover `ensure_schema`/`PREV` después del guard `--dry-run` imprimiendo `generacion=?`.)

- [ ] **Step 6: Commit**

```bash
git add bash/publicar/
git commit -m "publicar: scripts de publicación, permisos y deploy por conversación"
```

---

### Task 8: Servidor — checkout, pm2, nginx+certbot, primer despliegue y docs

**Files:**
- Modify: `CLAUDE.md` (nueva sección «Publicar domain»)
- Modify: `viz/README.md` (párrafo publish.js)
- Remote: `/apps/hermetico` (checkout + `.env`), `/etc/nginx/sites-available/app.ikigaigm.parallelo.ai`, pm2

**Interfaces:**
- Consumes: todo lo anterior, ya pusheado a `origin` (que vive en el mismo servidor: `/srv/git/cerebros/ikigai.git`).

- [ ] **Step 1: Push del código**

```bash
git push origin main
```

- [ ] **Step 2: Toolchain + checkout en el servidor**

```bash
ssh root@api 'apt-get install -y postgresql-client jq sqlite3 >/dev/null && \
  git clone /srv/git/cerebros/ikigai.git /apps/hermetico && cd /apps/hermetico && git log --oneline -1'
```

- [ ] **Step 3: `.env` remoto — solo las llaves necesarias**

```bash
# DATABASE_URL: el valor del .env local. JWT_SECRET: el de marketico.
ssh root@api 'JWT=$(grep "^JWT_SECRET=" /apps/marketico/.env | cut -d= -f2-); \
  printf "DATABASE_URL=%s\nJWT_SECRET=%s\nMARKETICO_AUTH_URL=https://ikigaigm.api.parallelo.ai/api/auth/login\n" \
    "<DATABASE_URL_DEL_ENV_LOCAL>" "$JWT" > /apps/hermetico/.env && chmod 600 /apps/hermetico/.env'
# Verificar que la capa de datos corre allá:
ssh root@api 'cd /apps/hermetico && bash bash/calls/closer_dashboard.sh --json | head -c 200'
```

Expected: JSON del dashboard (kpis…). Si falla por una dependencia de common.sh, resolverla aquí (es el gate de la task).

- [ ] **Step 4: pm2**

```bash
ssh root@api 'cd /apps/hermetico && PORT=4318 HOST=127.0.0.1 pm2 start viz/publish.js --name viz-publish && pm2 save'
ssh root@api 'curl -s http://127.0.0.1:4318/health'   # → ok
```

- [ ] **Step 5: nginx + certbot**

Escribir `/etc/nginx/sites-available/app.ikigaigm.parallelo.ai`:

```nginx
server {
    server_name app.ikigaigm.parallelo.ai;

    location / {
        proxy_pass         http://127.0.0.1:4318;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_buffering    off;               # SSE
        proxy_read_timeout 3600s;             # SSE de larga vida
    }

    listen 80;
}
```

```bash
ssh root@api 'ln -s /etc/nginx/sites-available/app.ikigaigm.parallelo.ai /etc/nginx/sites-enabled/ && nginx -t && systemctl reload nginx'
ssh root@api 'certbot --nginx -d app.ikigaigm.parallelo.ai --non-interactive'
curl -s https://app.ikigaigm.parallelo.ai/health   # → ok (TLS válido)
```

- [ ] **Step 6: Primer despliegue + permisos**

```bash
bash/publicar/publicar_ui.sh dashboard-por-closer --slug dashboard-closer --identidad 'closer=$name'
bash/publicar/permiso_ui.sh dashboard-closer --rol Closer
bash/publicar/permiso_ui.sh dashboard-closer --rol 'Director Comercial' --sin-identidad
bash/publicar/permiso_ui.sh dashboard-closer --listar
```

- [ ] **Step 7: Verificación end-to-end con el secreto real**

```bash
# Un closer real (users con team_member rol Closer) — token firmado con el JWT_SECRET del servidor:
ssh root@api 'cd /apps/hermetico && node -e "
  const { firmarJWT } = require(\"./viz/lib/pubauth\");
  const fs = require(\"fs\");
  const sec = fs.readFileSync(\".env\", \"utf8\").match(/^JWT_SECRET=(.*)$/m)[1];
  console.log(firmarJWT({ id: \"<users.id del closer>\", email: \"<email>\", roles: [\"Closer\"], name: \"<persons.name>\" }, sec, { expSeg: 600 }));
"'
curl -s -b "viz_sesion=<token>" https://app.ikigaigm.parallelo.ai/dashboard-closer | grep -c '<persons.name>'   # ≥1
curl -s -b "viz_sesion=<token>" 'https://app.ikigaigm.parallelo.ai/dashboard-closer?closer=Otro' | grep -c '<persons.name>'  # ≥1 — pisado
curl -s https://app.ikigaigm.parallelo.ai/dashboard-closer | grep -c 'name="password"'   # 1 — login sin sesión
# Login real por navegador: Santiago entra con su cuenta y confirma flujo completo + visitas:
bash/publicar/permiso_ui.sh dashboard-closer --visitas
```

- [ ] **Step 8: Docs**

En `CLAUDE.md`, tras el bloque del viz, sección nueva (~15 líneas): qué es el publicador, la tabla de los 3 scripts de `bash/publicar/`, el modelo de permisos (3 estados), la URL, y la excepción declarada al rail de SQL (publicaciones.db = estado propio del publicador). En `viz/README.md`: párrafo «publish.js — el entrypoint de producción» con el mapa de rutas y la nota de que `/c/` no se monta en v1.

- [ ] **Step 9: Commit final + desplegar**

```bash
git add CLAUDE.md viz/README.md
git commit -m "publicar: docs del dominio (CLAUDE.md + viz/README)"
bash/publicar/desplegar.sh
```

---

## Self-review (hecho al escribir)

- **Cobertura del spec:** datos vivos (T5/T8) · checkout (T8) · login Marketico + verificación local (T3/T5) · permisos 3 estados + precedencia (T2) · plantilla de identidad (T1/T2/T7) · snapshot congelado + generación+1 (T1/T7) · 404 uniforme (T5) · chip de param bloqueado (T6) · alias corto (T5/T7) · scripts por conversación (T7) · nginx+certbot+SSE (T8) · visitas (T1/T5) · caso closer/director verificado (T5 paso 3, T8 paso 7). Desviación declarada: `/c/` no se monta (header).
- **Placeholders:** los `<NOMBRE CLOSER REAL>` / `<users.id del closer>` / `<DATABASE_URL_DEL_ENV_LOCAL>` son datos operativos que el ejecutor resuelve en el momento (secretos y datos reales no van en el plan) — cada uno dice de dónde sacarlo.
- **Consistencia de tipos:** `firmarJWT/verifyJWT` (T3) usados en T5/T8; `vigente/porCodigo/porSpecId/permisosDe/visita` (T1) usados en T5; `elegirPermiso/resolverIdentidad/mergeParams` (T2) usados en T5; `standalone` (T4) usado en T5; `ui._locked` (T5) leído en T6. `params_identidad` viaja SIEMPRE como texto JSON de sqlite (string) y publogic hace el parse — coherente entre T1, T2 y T7.

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

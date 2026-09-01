-- Estado propio del interceptor de procesos Marketico — jamás datos de la org.
-- Idempotente: se aplica en cada arranque del receptor y en cada escritura bash.
PRAGMA journal_mode=WAL;

CREATE TABLE IF NOT EXISTS crm_webhook (
  id INTEGER PRIMARY KEY,
  recibido_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  appointment_id TEXT, location_id TEXT, estado_cita TEXT,
  contacto TEXT, email TEXT, telefono TEXT,
  start_time TEXT, end_time TEXT,
  ok INTEGER NOT NULL,
  resultado TEXT,
  error TEXT,
  duracion_ms INTEGER,
  payload TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_crm_webhook_recibido ON crm_webhook(recibido_at);
CREATE INDEX IF NOT EXISTS idx_crm_webhook_appt ON crm_webhook(appointment_id);

CREATE TABLE IF NOT EXISTS corridas (
  id INTEGER PRIMARY KEY,
  corrida_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  project_id TEXT, proyecto TEXT, ghl_calendar_id TEXT,
  ventana_desde TEXT, ventana_hasta TEXT,
  ghl_total INTEGER, db_total INTEGER,
  coinciden INTEGER, discrepancias INTEGER,
  estado TEXT NOT NULL DEFAULT 'ok',
  detalle TEXT
);
CREATE INDEX IF NOT EXISTS idx_corridas_at ON corridas(corrida_at);

CREATE TABLE IF NOT EXISTS drift (
  id INTEGER PRIMARY KEY,
  corrida_id INTEGER NOT NULL REFERENCES corridas(id),
  tipo TEXT NOT NULL CHECK (tipo IN ('falta_en_db','sobra_en_db','horas_difieren')),
  appointment_id TEXT, meeting_id TEXT,
  detalle TEXT
);
CREATE INDEX IF NOT EXISTS idx_drift_corrida ON drift(corrida_id);

-- Los agendamientos ENTRANTES de GHL una vez el webhook de Marketico quedó en
-- modo forward (2026-08-26): el Cerebro es quien decide qué se hace con cada
-- uno. accion: registrada (entrada/confirmación, sin Meet) · meet_solicitado
-- (venta → POST /crm/process-booking de Marketico) · ignorada (sin
-- appointment_id) · desconocido (calendario sin rol — NO se procesa) · error.
CREATE TABLE IF NOT EXISTS entrantes (
  id INTEGER PRIMARY KEY,
  recibido_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  appointment_id TEXT, calendar_id TEXT, rol TEXT, estado_cita TEXT,
  contacto TEXT, email TEXT, start_time TEXT,
  accion TEXT NOT NULL CHECK (accion IN ('registrada','meet_solicitado','ignorada','desconocido','error')),
  resultado TEXT, error TEXT, duracion_ms INTEGER,
  payload TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_entrantes_recibido ON entrantes(recibido_at);
CREATE INDEX IF NOT EXISTS idx_entrantes_appt ON entrantes(appointment_id);

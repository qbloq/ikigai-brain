-- Esquema de la db local `propuestas_reuniones` (idempotente). Lo aplica
-- propuesta_cargar.sh en cada corrida; crear la db = correr esto sobre un
-- archivo nuevo. Dos colas de curaduría: propuestas de reuniones (lotes +
-- propuestas) y arquetipos propuestos para tareas sin etiqueta (arquetipos).
CREATE TABLE IF NOT EXISTS lotes (
  meeting_id    TEXT PRIMARY KEY,
  meeting_corto TEXT NOT NULL,
  archivo       TEXT NOT NULL,
  fecha         TEXT,
  nombre        TEXT,
  cargado_en    TEXT NOT NULL,
  n_a           INTEGER NOT NULL DEFAULT 0,
  n_b           INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS propuestas (
  n                INTEGER PRIMARY KEY AUTOINCREMENT,
  meeting_id       TEXT NOT NULL REFERENCES lotes(meeting_id),
  ref              TEXT NOT NULL,
  seccion          TEXT NOT NULL CHECK (seccion IN ('A','B')),
  titulo           TEXT NOT NULL,
  proyecto         TEXT,
  prioridad        TEXT,
  vence            TEXT,
  vence_estimada   INTEGER NOT NULL DEFAULT 0,
  asignados        TEXT,   -- json array
  arquetipo        TEXT,
  slots            TEXT,   -- json object
  evidencia        TEXT,
  comentario       TEXT,
  pregunta         TEXT,   -- solo §B
  accion_sugerida  TEXT,   -- solo §B
  relacionadas     TEXT,   -- json array de ids (8)
  depende_de       TEXT,   -- json array de refs del mismo lote
  contrato         TEXT,   -- json: la forma exacta de create_task.sh (null en §B)
  valida           INTEGER NOT NULL DEFAULT 1,
  error_validacion TEXT,
  decision         TEXT CHECK (decision IN ('entra','se_queda')),
  decision_nota    TEXT,
  decidida_en      TEXT,
  creada_id        TEXT,   -- uuid de la tarea creada por crear_de_propuestas.sh
  creada_en        TEXT,
  UNIQUE (meeting_id, ref)
);
CREATE TABLE IF NOT EXISTS arquetipos (
  task_id       TEXT PRIMARY KEY,  -- uuid completo
  decision      TEXT NOT NULL,     -- id de arquetipo (A1.2) o 'ninguno'
  decision_nota TEXT,
  decidida_en   TEXT NOT NULL,
  aplicado_en   TEXT
);

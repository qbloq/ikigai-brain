-- Migration 006 — Testeos del embudo (el histórico compartido)
-- Schema: ikigaigm.  Applied: 2026-08-20.
--
-- WHY: la alineación DG 2026-08-19 (meeting b3f06835) dejó como acuerdo
-- «registrar el evento de cada testeo con las métricas iniciales y
-- actualizarlo con las finales, para tener el histórico de todos los
-- testeos». La primera implementación vivió unas horas en una sqlite local
-- (data/sqlite/testeos.db) y ahí mismo se encontró su límite: los testeos
-- los crean y monitorean Juan Camilo y Lorenzo DESDE SUS COPILOTOS (decisión
-- de Santiago, 2026-08-20), y una sqlite git-ignored da un histórico por
-- máquina — dos historias paralelas es lo contrario de «el histórico».
-- Camino declarado en docs/deltas-architecture.md: el esquema local probado
-- es el candidato a migración real. Este es ese paso.
--
-- Reglas que la tabla sostiene (las dos disciplinas de la reunión):
--   · UN SOLO CAMBIO POR TESTEO — `variable` es NOT NULL y singular por
--     contrato de los scripts (si hacen falta dos frases, son dos testeos).
--   · UN TESTEO POR STEP — guardarraíl en bash/testeos/testeo_abrir.sh (se
--     niega si hay un en_curso en el mismo step+proyecto, --forzar para la
--     excepción consciente). A propósito NO es un UNIQUE parcial: la
--     excepción consciente es legítima (p.ej. dos videos del mismo step con
--     atribución separada) y un constraint la volvería imposible.
--   · Los snapshots NO se digitan: bash/metrics/embudo.sh congelado al abrir
--     y al cerrar, jsonb con su procedencia adentro (_procedencia).
--   · Un cierre no se reescribe (los scripts se niegan sobre estado<>'en_curso').
--
-- Quién escribe: bash/testeos/testeo_abrir.sh / testeo_cerrar.sh (los únicos
-- write paths; el viz solo lee vía bash/testeos/testeos.sh). `abierto_por`
-- viene del copilot.json del fork ('cerebro' cuando corre en el cerebro).
--
-- Idempotente: CREATE ... IF NOT EXISTS en todo. DDL only; no seeding.

SET search_path TO ikigaigm;

CREATE TABLE IF NOT EXISTS testeos (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id       uuid NOT NULL REFERENCES projects(id),
  step             text NOT NULL CHECK (step IN
                     ('titular','hook_vsl','survey','pagina','pauta','remarketing','otro')),
  variable         text NOT NULL,
  hipotesis        text,
  metrica          text,          -- ruta punteada dentro del snapshot (kpis.roas_real, vsl.total.tasa_play, …)
  estado           text NOT NULL DEFAULT 'en_curso' CHECK (estado IN
                     ('en_curso','cerrado','abortado')),
  abierto_en       timestamptz NOT NULL DEFAULT now(),
  cerrado_en       timestamptz,
  abierto_por      text NOT NULL,  -- employee del copilot.json, o 'cerebro'
  cerrado_por      text,
  snapshot_inicial jsonb,
  snapshot_final   jsonb,
  valor_inicial    numeric,
  valor_final      numeric,
  delta            numeric,
  resultado        text CHECK (resultado IN ('gano','perdio','inconcluso')),
  decision         text,
  nota             text
);

COMMENT ON TABLE testeos IS
  'Histórico de testeos del embudo (acuerdo meeting b3f06835): snapshots del embudo congelados al abrir/cerrar, delta de la métrica objetivo, desenlace declarado por el humano. Write paths: bash/testeos/.';
COMMENT ON COLUMN testeos.variable IS
  'QUÉ se cambió, en singular — el campo ES la regla de un-cambio-por-testeo.';
COMMENT ON COLUMN testeos.metrica IS
  'Ruta punteada dentro del snapshot cuyo delta se calcula al cerrar (p.ej. kpis.roas_real).';

-- El lookup del guardarraíl (¿hay un en_curso en este step+proyecto?) y el
-- filtro por defecto del visor (en_curso primero). Parcial: la tabla crecerá
-- con cerrados, el índice no.
CREATE INDEX IF NOT EXISTS testeos_encurso_idx
  ON testeos (project_id, step) WHERE estado = 'en_curso';

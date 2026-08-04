-- Migration 003 — Task completion timestamp (when work actually landed)
-- Schema: ikigaigm.  Applied: 2026-07-27.
--
-- WHY: the task system could not measure RHYTHM, only state. The two timestamps
-- it had are both lies for that purpose:
--   * created_at  — 294 of 411 tasks share 2026-07-06: that's the Notion import
--     date, not the task's birth. Cycle time computed from it is fiction for
--     every ingested task (tasks born in-system, e.g. from meetings, are fine).
--   * updated_at  — completed tasks carry only TWO distinct dates (205 + 52):
--     bulk sync stamps. Measured against due_date it says 251 of 251 tasks
--     shipped late, which describes the sync, not the team.
-- Without a sealed completion instant there is no honest throughput, no on-time
-- rate, and no hand-off latency per link of the production chain (A2.4 grabar →
-- A2.5 editar → …) — which is precisely the Project Manager's dominant failure
-- mode (docs/roles/project-manager.md).
--
-- WHAT THIS ADDS:
--     completed_at  timestamptz  -- sealed the moment a task enters 'completed'
--   + trigger tasks_seal_completed_at (BEFORE INSERT OR UPDATE):
--       · stamps now() on the TRANSITION into completed (status→'completed' or
--         is_completed→true), never on a plain update of an already-completed
--         task — otherwise every historical row touched later would be stamped
--         with today and the series would fill up with fake closures
--       · clears it if the task is REOPENED (leaves 'completed'), so the column
--         never claims a completion that was undone
--       · never overwrites a value already present — an explicit backfill of a
--         known real date (e.g. from an external system) survives later updates.
--
-- NO BACKFILL, deliberately. Filling it from updated_at would inject the two
-- sync stamps and poison the series from day one; a metric that is wrong is
-- worse than one that is missing. Historical tasks keep completed_at NULL, and
-- every rhythm metric is defined over NOT NULL only — so the dashboard reports
-- "midiendo desde 2026-07-27" instead of inventing a past.
--
-- Idempotent (IF NOT EXISTS / CREATE OR REPLACE / DROP+CREATE TRIGGER). Safe to
-- re-run. Nullable column + BEFORE trigger → the app is untouched.

BEGIN;

ALTER TABLE ikigaigm.tasks ADD COLUMN IF NOT EXISTS completed_at timestamptz;

COMMENT ON COLUMN ikigaigm.tasks.completed_at IS
  'Instante en que la tarea entró en completed (sellado por trigger; NULL = nunca completada o completada antes de la migración 003). Toda métrica de ritmo se define sólo sobre NOT NULL.';

CREATE OR REPLACE FUNCTION ikigaigm.tasks_seal_completed_at()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
DECLARE
  done boolean := (NEW.status = 'completed') OR coalesce(NEW.is_completed, false);
  was  boolean := CASE WHEN TG_OP = 'UPDATE'
                    THEN (OLD.status = 'completed') OR coalesce(OLD.is_completed, false)
                    ELSE false END;
BEGIN
  IF done AND NOT was AND NEW.completed_at IS NULL THEN
    NEW.completed_at := now();          -- sella SOLO la transición a completada
  ELSIF was AND NOT done THEN
    NEW.completed_at := NULL;           -- reabierta: no sostener un cierre deshecho
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS tasks_seal_completed_at ON ikigaigm.tasks;
CREATE TRIGGER tasks_seal_completed_at
  BEFORE INSERT OR UPDATE ON ikigaigm.tasks
  FOR EACH ROW EXECUTE FUNCTION ikigaigm.tasks_seal_completed_at();

-- Series de ritmo: "entregadas en la ventana", ordenadas por fecha de cierre.
CREATE INDEX IF NOT EXISTS idx_tasks_completed_at ON ikigaigm.tasks(completed_at);

COMMIT;

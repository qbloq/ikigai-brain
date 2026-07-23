-- PLANTILLA: {schema} se instancia al nacer el cerebro (crear_cerebro).
-- Migration 002 — Task provenance (where each task came from)
-- Schema: {schema}.  Applied: 2026-07-04.
--
-- WHY: until now a task recorded no structured origin. Meeting-born tasks left
-- only a free-text comment ("Created from meeting X…"); Notion-born tasks had
-- nothing. As we consolidate external work (Notion BD Avances, meetings) into the
-- system, provenance is needed to audit, de-duplicate ("did I already ingest this
-- Notion page?"), and jump back to the source (the Notion URL, or the meeting).
--
-- WHAT THIS ADDS (typed columns on tasks; one origin per task):
--     source_type        text  -- 'meeting' | 'notion' | 'manual' | 'other'
--     source_meeting_id  uuid  -- FK → {schema}.meetings(id)  (when type='meeting')
--     source_url         text  -- external URL, preferred (Notion page URL)
--     source_external_id text  -- external stable id (Notion page id) for dedup/sync
--
-- Populated by bash/tasks/create_task.sh (in addition to the human comment trail).
-- The free-text provenance comment is kept — this is the structured, queryable twin.
--
-- Idempotent (IF NOT EXISTS / guarded constraint). Safe to re-run. Nullable
-- columns → backward-compatible, existing rows/app untouched.

BEGIN;

ALTER TABLE {schema}.tasks ADD COLUMN IF NOT EXISTS source_type        text;
ALTER TABLE {schema}.tasks ADD COLUMN IF NOT EXISTS source_meeting_id  uuid;
ALTER TABLE {schema}.tasks ADD COLUMN IF NOT EXISTS source_url         text;
ALTER TABLE {schema}.tasks ADD COLUMN IF NOT EXISTS source_external_id text;

-- FK to meetings, added idempotently (mirrors the archetype_id FK in 001).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tasks_source_meeting_id_fkey') THEN
    ALTER TABLE {schema}.tasks
      ADD CONSTRAINT tasks_source_meeting_id_fkey
      FOREIGN KEY (source_meeting_id) REFERENCES {schema}.meetings(id) ON UPDATE CASCADE;
  END IF;
END $$;

-- Lookups: dedup by Notion page id, filter by origin, join back to meetings.
CREATE INDEX IF NOT EXISTS idx_tasks_source_external ON {schema}.tasks(source_external_id);
CREATE INDEX IF NOT EXISTS idx_tasks_source_type     ON {schema}.tasks(source_type);
CREATE INDEX IF NOT EXISTS idx_tasks_source_meeting  ON {schema}.tasks(source_meeting_id);

COMMIT;

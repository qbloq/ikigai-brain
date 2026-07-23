-- PLANTILLA: {schema} se instancia al nacer el cerebro (crear_cerebro).
-- Migration 001 — Process ontology (macro-processes → SOPs → activity archetypes)
-- Schema: {schema}.  Applied: 2026-06-28.
--
-- WHAT THIS ADDS (the schema-of-record for the changes made this session):
--   NEW TABLES
--     macro_processes                 -- S1…S12 spine (role-sops-discovery.md §1)
--     sops                            -- canonical SOPs Sx.y, each under a macro
--     activity_archetypes             -- atomic activities A_.__ , each under a SOP
--     archetype_params                -- the variable slots of an archetype
--     archetype_outputs               -- template "work contract" (mirrors task_outputs)
--     archetype_inputs                -- template inputs        (mirrors task_inputs)
--     archetype_acceptance_criteria   -- template criteria      (mirrors task_acceptance_criteria)
--   ALTERED TABLE
--     tasks  + archetype_id (FK→activity_archetypes), archetype_confidence, archetype_match_method
--
-- Hierarchy / rollup:  task → activity_archetypes → sops → macro_processes.
-- Data is seeded separately from catalog/sop-archetypes.json by
-- bash/catalog/sync_catalog.sh (this file is DDL only — the schema record).
--
-- NOTE: a *different*, pre-existing public.sops exists (an app table with
-- id/user_id). It is unrelated and untouched — everything here is schema-qualified
-- to {schema}. With search_path={schema},public an unqualified `sops` resolves to
-- {schema}.sops.
--
-- NOTE: the task-domain wipe done earlier (tasks + task_inputs/outputs/criteria/
-- attestations/todos/comments) was DATA only — no schema change — so it is not
-- part of this migration. See bash/tasks/wipe_tasks.sh.
--
-- Idempotent (IF NOT EXISTS). Safe to re-run.

BEGIN;
SET search_path = {schema}, public;

-- pgvector lives in the `extensions` schema on this instance; qualify the type.
CREATE EXTENSION IF NOT EXISTS vector;

-- ---------------------------------------------------------------- macro_processes
CREATE TABLE IF NOT EXISTS {schema}.macro_processes (
  code              text PRIMARY KEY,                 -- 'S1' … 'S12'
  name              text NOT NULL,
  value_chain_order int,
  cadence           text,
  owner_roles       text[],
  owner_gap         text,                             -- role gap if unowned (e.g. Media Buyer)
  status            text DEFAULT 'candidate',         -- candidate | proposed-gap | approved
  note              text,
  created_at        timestamptz DEFAULT now(),
  updated_at        timestamptz DEFAULT now()
);

-- ------------------------------------------------------------------------- sops
CREATE TABLE IF NOT EXISTS {schema}.sops (
  code               text PRIMARY KEY,                -- 'S2.1'
  macro_process_code text NOT NULL
                       REFERENCES {schema}.macro_processes(code) ON UPDATE CASCADE,
  name               text NOT NULL,
  owner_roles        text[],
  status             text DEFAULT 'candidate',
  note               text,
  created_at         timestamptz DEFAULT now(),
  updated_at         timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sops_macro ON {schema}.sops(macro_process_code);

-- ----------------------------------------------------------- activity_archetypes
CREATE TABLE IF NOT EXISTS {schema}.activity_archetypes (
  id               text PRIMARY KEY,                  -- 'A2.4'
  slug             text UNIQUE,                        -- 'a2-4'
  name             text NOT NULL,
  verb             text,                               -- controlled vocabulary (see catalog _meta)
  artifact         text,
  sop_code         text REFERENCES {schema}.sops(code) ON UPDATE CASCADE,
  default_role     text,
  default_priority text,
  cadence          text,
  is_gate          boolean DEFAULT false,
  description      text,
  status           text DEFAULT 'candidate',
  embedding        extensions.vector(1536),            -- for the future semantic matcher
  created_at       timestamptz DEFAULT now(),
  updated_at       timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_archetypes_sop ON {schema}.activity_archetypes(sop_code);

-- ------------------------------------------------------------- archetype_params
CREATE TABLE IF NOT EXISTS {schema}.archetype_params (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  archetype_id text REFERENCES {schema}.activity_archetypes(id) ON DELETE CASCADE,
  key          text NOT NULL,                          -- slot key: proyecto, talento, cantidad…
  label        text,
  type         text DEFAULT 'text',                    -- text | int | enum | ref
  required     boolean DEFAULT false,
  enum_options text[],
  position     int DEFAULT 0,
  UNIQUE (archetype_id, key)
);

-- --------------------------- template "work contract" (mirror the task_* tables)
CREATE TABLE IF NOT EXISTS {schema}.archetype_outputs (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  archetype_id     text REFERENCES {schema}.activity_archetypes(id) ON DELETE CASCADE,
  title            text NOT NULL,
  description      text,
  io_type_id       uuid REFERENCES {schema}.io_types(id),
  artifact_type_id uuid REFERENCES {schema}.artifact_types(id),
  is_required      boolean DEFAULT true,
  position         int DEFAULT 0
);

CREATE TABLE IF NOT EXISTS {schema}.archetype_inputs (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  archetype_id     text REFERENCES {schema}.activity_archetypes(id) ON DELETE CASCADE,
  title            text NOT NULL,
  description      text,
  io_type_id       uuid REFERENCES {schema}.io_types(id),
  artifact_type_id uuid REFERENCES {schema}.artifact_types(id),
  is_required      boolean DEFAULT true,
  position         int DEFAULT 0
);

CREATE TABLE IF NOT EXISTS {schema}.archetype_acceptance_criteria (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  output_id           uuid REFERENCES {schema}.archetype_outputs(id) ON DELETE CASCADE,
  criterion           text NOT NULL,
  criterion_category  text,                            -- completeness | quality | format | accuracy
  verification_method text DEFAULT 'manual',           -- attested | llm | automated | test | manual
  is_required         boolean DEFAULT true,
  position            int DEFAULT 0
);

-- ------------------------------------------------- tasks: instance → template link
ALTER TABLE {schema}.tasks ADD COLUMN IF NOT EXISTS archetype_id text;
ALTER TABLE {schema}.tasks ADD COLUMN IF NOT EXISTS archetype_confidence text;
ALTER TABLE {schema}.tasks ADD COLUMN IF NOT EXISTS archetype_match_method text;  -- rule|embedding|llm|human

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tasks_archetype_id_fkey') THEN
    ALTER TABLE {schema}.tasks
      ADD CONSTRAINT tasks_archetype_id_fkey
      FOREIGN KEY (archetype_id) REFERENCES {schema}.activity_archetypes(id) ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_tasks_archetype ON {schema}.tasks(archetype_id);

COMMIT;

#!/usr/bin/env bash
# (Re)build the process-ontology schema and seed it from catalog/sop-archetypes.json.
# WRITE, single transaction, --dry-run rolls back.
#
# THREE process tiers (docs/role-sops-discovery.md): a macro-process (S1–S12) is
# broken into canonical SOPs (Sx.y), each SOP groups activity archetypes (A_.__),
# and a task instantiates an archetype. Rollup: task → archetype → sop → macro.
#
# Schema (ikigaigm):
#   macro_processes · sops(→macro_processes) · activity_archetypes(→sops, +embedding)
#   archetype_params · archetype_inputs/outputs/acceptance_criteria
#   tasks.archetype_id (FK) / archetype_confidence / archetype_match_method
#
# This rebuilds the catalog tables from the JSON each run (they are fully derived).
# tasks.archetype_id VALUES are preserved (DROP ... CASCADE only drops the FK,
# which is re-added). The empty template tables are recreated empty.
#
# Usage:  sync_catalog.sh [--dry-run]
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

dry=""
case "${1:-}" in
  --dry-run) dry=1 ;;
  -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
  "" ) ;;
  *) echo "Unknown arg: $1" >&2; exit 2 ;;
esac

cat="$REPO_ROOT/catalog/sop-archetypes.json"
[[ -f "$cat" ]] || { echo "Catalog not found: $cat" >&2; exit 1; }
json="$(cat "$cat")"

end="COMMIT"; [[ -n "$dry" ]] && end="ROLLBACK"
psql_rw -v catalog="$json" <<SQL
BEGIN;
SET search_path = ikigaigm, public;
CREATE EXTENSION IF NOT EXISTS vector;

-- ---- Rebuild catalog tables (tasks.archetype_id values survive via CASCADE) --
DROP TABLE IF EXISTS ikigaigm.archetype_acceptance_criteria CASCADE;
DROP TABLE IF EXISTS ikigaigm.archetype_inputs  CASCADE;
DROP TABLE IF EXISTS ikigaigm.archetype_outputs CASCADE;
DROP TABLE IF EXISTS ikigaigm.archetype_params  CASCADE;
DROP TABLE IF EXISTS ikigaigm.activity_archetypes CASCADE;
DROP TABLE IF EXISTS ikigaigm.sops            CASCADE;
DROP TABLE IF EXISTS ikigaigm.macro_processes CASCADE;

CREATE TABLE ikigaigm.macro_processes (
  code              text PRIMARY KEY,            -- S1…S12
  name              text NOT NULL,
  value_chain_order int,
  cadence           text,
  owner_roles       text[],
  owner_gap         text,
  status            text DEFAULT 'candidate',
  note              text,
  created_at        timestamptz DEFAULT now(),
  updated_at        timestamptz DEFAULT now()
);

CREATE TABLE ikigaigm.sops (
  code               text PRIMARY KEY,           -- Sx.y
  macro_process_code text NOT NULL REFERENCES ikigaigm.macro_processes(code) ON UPDATE CASCADE,
  name               text NOT NULL,
  owner_roles        text[],
  status             text DEFAULT 'candidate',
  note               text,
  created_at         timestamptz DEFAULT now(),
  updated_at         timestamptz DEFAULT now()
);

CREATE TABLE ikigaigm.activity_archetypes (
  id               text PRIMARY KEY,             -- 'A2.4'
  slug             text UNIQUE,
  name             text NOT NULL,
  verb             text,
  artifact         text,
  sop_code         text REFERENCES ikigaigm.sops(code) ON UPDATE CASCADE,
  default_role     text,
  default_priority text,
  cadence          text,
  is_gate          boolean DEFAULT false,
  description      text,
  status           text DEFAULT 'candidate',
  embedding        extensions.vector(1536),
  created_at       timestamptz DEFAULT now(),
  updated_at       timestamptz DEFAULT now()
);

CREATE TABLE ikigaigm.archetype_params (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  archetype_id text REFERENCES ikigaigm.activity_archetypes(id) ON DELETE CASCADE,
  key          text NOT NULL,
  label        text,
  type         text DEFAULT 'text',
  required     boolean DEFAULT false,
  enum_options text[],
  position     int DEFAULT 0,
  UNIQUE (archetype_id, key)
);

CREATE TABLE ikigaigm.archetype_outputs (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  archetype_id     text REFERENCES ikigaigm.activity_archetypes(id) ON DELETE CASCADE,
  title            text NOT NULL, description text,
  io_type_id       uuid REFERENCES ikigaigm.io_types(id),
  artifact_type_id uuid REFERENCES ikigaigm.artifact_types(id),
  is_required      boolean DEFAULT true, position int DEFAULT 0
);
CREATE TABLE ikigaigm.archetype_inputs (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  archetype_id     text REFERENCES ikigaigm.activity_archetypes(id) ON DELETE CASCADE,
  title            text NOT NULL, description text,
  io_type_id       uuid REFERENCES ikigaigm.io_types(id),
  artifact_type_id uuid REFERENCES ikigaigm.artifact_types(id),
  is_required      boolean DEFAULT true, position int DEFAULT 0
);
CREATE TABLE ikigaigm.archetype_acceptance_criteria (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  output_id           uuid REFERENCES ikigaigm.archetype_outputs(id) ON DELETE CASCADE,
  criterion           text NOT NULL, criterion_category text,
  verification_method text DEFAULT 'manual', is_required boolean DEFAULT true, position int DEFAULT 0
);

-- tasks: instance → template link (column may already exist; keep its values)
ALTER TABLE ikigaigm.tasks ADD COLUMN IF NOT EXISTS archetype_id text;
ALTER TABLE ikigaigm.tasks ADD COLUMN IF NOT EXISTS archetype_confidence text;
ALTER TABLE ikigaigm.tasks ADD COLUMN IF NOT EXISTS archetype_match_method text;

CREATE INDEX IF NOT EXISTS idx_sops_macro       ON ikigaigm.sops(macro_process_code);
CREATE INDEX IF NOT EXISTS idx_archetypes_sop   ON ikigaigm.activity_archetypes(sop_code);
CREATE INDEX IF NOT EXISTS idx_tasks_archetype  ON ikigaigm.tasks(archetype_id);

-- ---- Seed from catalog JSON ----------------------------------------------
WITH cat AS (SELECT :'catalog'::jsonb AS j)
INSERT INTO ikigaigm.macro_processes (code, name, value_chain_order, cadence, owner_roles, owner_gap, status, note)
SELECT m->>'code', m->>'name', (m->>'value_chain_order')::int, m->>'cadence',
       CASE WHEN m ? 'owner_roles' THEN ARRAY(SELECT jsonb_array_elements_text(m->'owner_roles')) END,
       m->>'owner_gap', coalesce(m->>'status','candidate'), m->>'note'
FROM cat, jsonb_array_elements((SELECT j FROM cat)->'macro_processes') m;

WITH cat AS (SELECT :'catalog'::jsonb AS j)
INSERT INTO ikigaigm.sops (code, macro_process_code, name, owner_roles, status, note)
SELECT s->>'code', s->>'macro_process', s->>'name',
       CASE WHEN s ? 'owner_roles' THEN ARRAY(SELECT jsonb_array_elements_text(s->'owner_roles')) END,
       coalesce(s->>'status','candidate'), s->>'note'
FROM cat, jsonb_array_elements((SELECT j FROM cat)->'sops') s;

WITH cat AS (SELECT :'catalog'::jsonb AS j)
INSERT INTO ikigaigm.activity_archetypes (id, slug, name, verb, sop_code, is_gate, status)
SELECT a->>'id', lower(replace(a->>'id','.','-')), a->>'name', a->>'verb', a->>'sop',
       coalesce((a->>'is_gate')::boolean, false), 'candidate'
FROM cat, jsonb_array_elements((SELECT j FROM cat)->'archetypes') a;

WITH cat AS (SELECT :'catalog'::jsonb AS j)
INSERT INTO ikigaigm.archetype_params (archetype_id, key, position)
SELECT a->>'id', slot.val, slot.ord-1
FROM cat, jsonb_array_elements((SELECT j FROM cat)->'archetypes') a
CROSS JOIN LATERAL jsonb_array_elements_text(coalesce(a->'slots','[]'::jsonb)) WITH ORDINALITY slot(val,ord);

-- Template work contracts (only archetypes that declare inputs/outputs in the JSON).
WITH cat AS (SELECT :'catalog'::jsonb AS j)
INSERT INTO ikigaigm.archetype_inputs (archetype_id, title, description, io_type_id, artifact_type_id, is_required, position)
SELECT a->>'id', e.i->>'title', e.i->>'description', it.id, it.default_artifact_type_id,
       coalesce((e.i->>'is_required')::bool, true), e.ord-1
FROM cat, jsonb_array_elements((SELECT j FROM cat)->'archetypes') a
CROSS JOIN LATERAL jsonb_array_elements(coalesce(a->'inputs','[]'::jsonb)) WITH ORDINALITY e(i,ord)
LEFT JOIN ikigaigm.io_types it ON it.name = e.i->>'io_type';

WITH cat AS (SELECT :'catalog'::jsonb AS j),
ins_out AS (
  INSERT INTO ikigaigm.archetype_outputs (archetype_id, title, description, io_type_id, artifact_type_id, is_required, position)
  SELECT a->>'id', e.o->>'title', e.o->>'description', it.id, it.default_artifact_type_id,
         coalesce((e.o->>'is_required')::bool, true), e.ord-1
  FROM cat, jsonb_array_elements((SELECT j FROM cat)->'archetypes') a
  CROSS JOIN LATERAL jsonb_array_elements(coalesce(a->'outputs','[]'::jsonb)) WITH ORDINALITY e(o,ord)
  LEFT JOIN ikigaigm.io_types it ON it.name = e.o->>'io_type'
  RETURNING id, archetype_id, position
)
INSERT INTO ikigaigm.archetype_acceptance_criteria (output_id, criterion, criterion_category, verification_method, is_required, position)
SELECT io.id, cc.cr->>'criterion', cc.cr->>'criterion_category',
       coalesce(nullif(cc.cr->>'verification_method',''),'manual'),
       coalesce((cc.cr->>'is_required')::bool, true), cc.crord-1
FROM cat, jsonb_array_elements((SELECT j FROM cat)->'archetypes') a
CROSS JOIN LATERAL jsonb_array_elements(coalesce(a->'outputs','[]'::jsonb)) WITH ORDINALITY e(o,ord)
JOIN ins_out io ON io.archetype_id = a->>'id' AND io.position = e.ord-1
CROSS JOIN LATERAL jsonb_array_elements(coalesce(e.o->'criteria','[]'::jsonb)) WITH ORDINALITY cc(cr,crord);

-- Re-attach the tasks → archetype FK (its values were preserved)
ALTER TABLE ikigaigm.tasks
  ADD CONSTRAINT tasks_archetype_id_fkey
  FOREIGN KEY (archetype_id) REFERENCES ikigaigm.activity_archetypes(id) ON UPDATE CASCADE;

\echo '==== counts ===='
SELECT 'macro_processes' t, count(*) n FROM ikigaigm.macro_processes
UNION ALL SELECT 'sops', count(*) FROM ikigaigm.sops
UNION ALL SELECT 'activity_archetypes', count(*) FROM ikigaigm.activity_archetypes
UNION ALL SELECT 'archetype_params', count(*) FROM ikigaigm.archetype_params
UNION ALL SELECT 'archetype_inputs', count(*) FROM ikigaigm.archetype_inputs
UNION ALL SELECT 'archetype_outputs', count(*) FROM ikigaigm.archetype_outputs
UNION ALL SELECT 'archetype_acceptance_criteria', count(*) FROM ikigaigm.archetype_acceptance_criteria
ORDER BY 1;

\echo '==== template io_type integrity (should be 0) ===='
SELECT count(*) AS unresolved_io_types FROM (
  SELECT io_type_id FROM ikigaigm.archetype_inputs WHERE io_type_id IS NULL
  UNION ALL SELECT io_type_id FROM ikigaigm.archetype_outputs WHERE io_type_id IS NULL
) x;

\echo '==== orphan tasks (archetype_id not in catalog)? ===='
SELECT count(*) AS orphan_tasks FROM ikigaigm.tasks t
LEFT JOIN ikigaigm.activity_archetypes a ON a.id=t.archetype_id
WHERE t.archetype_id IS NOT NULL AND a.id IS NULL;
$end;
SQL

[[ -n "$dry" ]] && echo "(dry-run: rolled back, nothing written)"
exit 0

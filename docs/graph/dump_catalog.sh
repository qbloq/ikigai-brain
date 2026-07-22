#!/usr/bin/env bash
# Dump the ikigaigm catalog to TSV for build_graph.py — READ-ONLY.
# Everything the ontology needs that pg exposes deterministically:
# entities, FKs (with cardinality + optionality + delete rule), primary keys,
# enums (scoped by type OID so cross-schema name collisions can't merge them),
# check/unique constraints, and the jsonb/array columns that carry the
# relations no FK enforces.
#
# Usage: docs/graph/dump_catalog.sh [outdir]      (default: docs/graph/catalog)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../bash/lib/common.sh"
OUT="${1:-$HERE/catalog}"
mkdir -p "$OUT"
q() { psql_ro -t -A -F$'\t' -c "$1"; }

# 1) entities: name, kind, approx rows, n columns
q "SELECT c.relname,
     CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view'
                    WHEN 'm' THEN 'matview' WHEN 'p' THEN 'parted' ELSE c.relkind::text END,
     GREATEST(c.reltuples::bigint,0),
     (SELECT count(*) FROM pg_attribute a
       WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped)
   FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='ikigaigm' AND c.relkind IN ('r','v','m','p')
   ORDER BY c.relname;" > "$OUT/tables.tsv"

# 2) foreign keys, enriched:
#    attnotnull  -> participation (mandatory vs optional)
#    src_unique  -> single-column unique index on the FK column => 1:1, else N:1
#    confdeltype -> a=no action, r=restrict, c=cascade, n=set null, d=set default
q "SELECT src.relname, a.attname, a.attnotnull, tgt.relname, ta.attname,
     EXISTS (SELECT 1 FROM pg_index i
              WHERE i.indrelid=src.oid AND i.indisunique
                AND i.indnkeyatts=1 AND i.indkey[0]=a.attnum) AS src_unique,
     con.confdeltype, con.conname
   FROM pg_constraint con
   JOIN pg_class src ON src.oid=con.conrelid
   JOIN pg_class tgt ON tgt.oid=con.confrelid
   JOIN pg_namespace n ON n.oid=src.relnamespace
   JOIN unnest(con.conkey)  WITH ORDINALITY AS k(attnum,ord) ON true
   JOIN pg_attribute a  ON a.attrelid=src.oid AND a.attnum=k.attnum
   JOIN unnest(con.confkey) WITH ORDINALITY AS f(attnum,ord) ON f.ord=k.ord
   JOIN pg_attribute ta ON ta.attrelid=tgt.oid AND ta.attnum=f.attnum
   WHERE con.contype='f' AND n.nspname='ikigaigm'
   ORDER BY 1,2;" > "$OUT/fk_rich.tsv"

# 3) primary keys (identity of each entity)
q "SELECT c.relname, string_agg(a.attname,',' ORDER BY k.ord)
   FROM pg_constraint con
   JOIN pg_class c ON c.oid=con.conrelid
   JOIN pg_namespace n ON n.oid=c.relnamespace
   JOIN unnest(con.conkey) WITH ORDINALITY AS k(attnum,ord) ON true
   JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum=k.attnum
   WHERE con.contype='p' AND n.nspname='ikigaigm'
   GROUP BY c.relname ORDER BY 1;" > "$OUT/pks.tsv"

# 4) enums ACTUALLY used by ikigaigm columns, anchored by type OID.
#    (Filtering by typname alone merges same-named enums from other schemas —
#     this DB hosts a second, unrelated project, so that matters.)
q "WITH used AS (
     SELECT DISTINCT a.atttypid AS oid
     FROM pg_attribute a
     JOIN pg_class c ON c.oid=a.attrelid
     JOIN pg_namespace n ON n.oid=c.relnamespace
     JOIN pg_type t ON t.oid=a.atttypid
     WHERE n.nspname='ikigaigm' AND a.attnum>0 AND NOT a.attisdropped AND t.typtype='e')
   SELECT t.typname, string_agg(e.enumlabel,'|' ORDER BY e.enumsortorder)
   FROM used u JOIN pg_type t ON t.oid=u.oid JOIN pg_enum e ON e.enumtypid=t.oid
   GROUP BY t.oid, t.typname ORDER BY 1;" > "$OUT/enums.tsv"

# 5) columns carrying an enum, jsonb/json, or array type
q "SELECT c.relname, a.attname, t.typname, t.typtype, a.attnotnull
   FROM pg_attribute a
   JOIN pg_class c ON c.oid=a.attrelid
   JOIN pg_namespace n ON n.oid=c.relnamespace
   JOIN pg_type t ON t.oid=a.atttypid
   WHERE n.nspname='ikigaigm' AND a.attnum>0 AND NOT a.attisdropped
     AND c.relkind IN ('r','v','p')
     AND (t.typtype='e' OR t.typname IN ('jsonb','json') OR t.typname LIKE '\_%')
   ORDER BY 1,2;" > "$OUT/typed_cols.tsv"

# 6) check + unique constraints (the rules declared in DDL)
q "SELECT c.relname, con.contype, con.conname, pg_get_constraintdef(con.oid)
   FROM pg_constraint con
   JOIN pg_class c ON c.oid=con.conrelid
   JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE con.contype IN ('c','u') AND n.nspname='ikigaigm'
   ORDER BY c.relname, con.contype;" > "$OUT/constraints.tsv"

for f in tables fk_rich pks enums typed_cols constraints; do
  printf '%-14s %4s filas\n' "$f" "$(wc -l < "$OUT/$f.tsv")"
done
echo "→ $OUT"

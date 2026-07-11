# Catalog — canonical reference data

Machine-readable source-of-truth catalogs the pipeline consults. Unlike `docs/`
(discovery prose), these are the **operational** artifacts that skills and scripts read.

## `sop-archetypes.json`
The process ontology in **three tiers** (per [docs/role-sops-discovery.md](../docs/role-sops-discovery.md)):

```
value chain → macro_process (S1…S12) → sop (Sx.y) → activity archetype (A_.__) → task
```

- **macro_processes** (12) — the S1–S10 spine + proposed gaps **S11 Producto**,
  **S12 Cierre/Retención**. These are the *macro-processes*, not SOPs.
- **sops** (33) — the canonical SOPs, deduped from the per-role candidates in the
  discovery doc §2; each belongs to one macro-process. `{code, macro_process, name, owner_roles[]}`.
- **archetypes** (65) — the atomic activities (`A_.__`), each grouped under one SOP.
  `{id, sop, verb, name, slots[]}`. `verb` ∈ `_meta.verb_vocabulary`.

A task tags its `archetype_id`; SOP and macro-process come by joining
`activity_archetypes → sops → macro_processes`. Every SOP now has ≥1 archetype,
including the gap macros S11 (Producto: A11.x) and S12 (Cierre/Retención: A12.x).

**Who reads it**
- `transcript-to-report` — tags each action item with its archetype (→ sop → macro)
  in the discovery sidecar.
- `meeting-to-tasks` / `create_task.sh` — persists `tasks.archetype_id`.
- future matcher / snapshot exports — rollups across projects.

Edit this file, then run `bash/catalog/sync_catalog.sh` to sync the DB tables.
**Status:** `candidate`. Unmatched tasks become candidate new archetypes.

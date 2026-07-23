# Task I/O Validation — Implementation Status & Gap

**Companion to** [task-io-validation.md](task-io-validation.md) (the design). This doc reconciles that design against what is **already built**, so we only build the gap.

> ⚠️ **Location:** the Task System backend is in **meetico** (`/projects/google-meet-express`), **not** marketico. It is **JavaScript** (`src/services/agenticoService.js`, `src/routes/tasks.js`, tests in `src/tests/taskIO.test.js`). Marketico holds the design + the discovery scripts/data only.

---

## What already exists (don't rebuild)

In `agenticoService.js`:

| Capability | Function | Notes |
| --- | --- | --- |
| **Resolve artifact content** | `resolveArtifactContent(artifactTypeId, reference)` (~L1268) | Switches on `resolver_type`: `table`, `storage`, `inline`, `api`, `computed`. Returns content **or null**. |
| **LLM criterion eval** | `evaluateCriterionWithLLM(criterion, content, context)` (~L1639) | Returns `{is_met, confidence, reasoning, suggestions}`. |
| **LLM output eval (orchestrator)** | `evaluateAllCriteriaWithLLM(outputId)` (~L1700) | Resolves content, evaluates criteria, persists `is_met/confidence/verified_by/verification_notes/requires_reverification`. |
| **CRUD** | inputs, outputs, criteria, templates, artifact_types | Complete. |
| **Full task read** | `getTaskWithIO(taskId)` | Returns task + inputs + outputs + criteria. |
| **Schema** | `task_acceptance_criteria`, `task_outputs`, `task_inputs`, `artifact_types`, `verification_templates` | Tables exist (currently empty of rows). |

**The structural primitive and the semantic (LLM) tier are done.** Resolve + LLM judging + persistence + a `requires_reverification` re-validation flag all work, with tests.

---

## The gap (what our corpus actually needs)

### Gap 1 — the engine only runs LLM criteria
`evaluateAllCriteriaWithLLM` does `criteria.filter(c => c.verification_method === 'llm')` (L1718). Everything else is **silently ignored**. Against the verified corpus ([task-criteria-verified.json](../backups/task-criteria-verified.json)):

| Method | Criteria | Evaluated today? |
| --- | --: | --- |
| `llm` | 763 | ✅ yes |
| `automated` | 733 | ❌ no |
| `attested` | 337 | ❌ no (also schema-blocked) |
| `test` | 88 | ❌ no |
| `manual` | 24 | n/a (passive) |

**~1158 criteria (60%) cannot be evaluated.** This is the headline gap.

### Gap 2 — `automated` is unmodeled in the schema
`task_acceptance_criteria` has `verification_prompt` (for LLM) but **no `validator` field** — an automated criterion has no way to declare *which* registry check (artifact_exists, mime_in, …) or its params. Code can't dispatch what the schema can't express.

### Gap 3 — `attested` violates the CHECK constraint
`CONSTRAINT verification_method_check CHECK (verification_method = ANY (ARRAY['llm','manual','automated','test']))` — **`attested` is not allowed.** The whole attestation design (Tier D, §6A) needs this widened + the `task_attestations` table.

### Gap 4 — `resolveArtifactContent` returns content, not a `ResolvedArtifact`
Programmatic validators need `{exists, mime, size, url, record}` — but the function returns a bare string/object/null. No metadata (mime/size) for `mime_in`/`file_min_size`, and `exists:false` is conflated with "empty content."

### Gap 5 — no structural gate / no `pass_threshold`
`evaluateAllCriteriaWithLLM` **throws** if content won't resolve (L1713) instead of marking criteria unmet and short-circuiting. No `reference_schema` validation. No `pass_threshold` column for confidence routing.

---

## Build order for the gap (phase C)

**Schema migration** (meetico migration, `{{SCHEMA_NAME}}`):
1. Widen `verification_method_check` to include `'attested'`.
2. Add `validator jsonb` (automated: `{id, params}`), `pass_threshold text` (high/medium/low), `auto_source text`.
3. New table `task_attestations` (see design §8) — deferrable to the attestation phase.

**Code** (`agenticoService.js`, JS, matching existing style + a `taskIO.test.js` case each):
4. `resolveArtifact()` → `{exists, content_text, url, record, metadata:{mime,size,...}}` (wrap/replace `resolveArtifactContent`; keep a content accessor for the LLM path).
5. **Validator registry** — `artifact_exists, matches_reference_schema, min_length, url_reachable, mime_in, file_min_size, record_field_not_null, date_in_future, computed_check`. Each `(resolved, params) => {is_met, confidence:1, reasoning}`.
6. **`evaluateOutput(outputId)`** — unified engine: resolve → structural gate → dispatch by `verification_method` (automated→registry, llm→existing, test→adapter, attested→open request, manual→pending) → aggregate → persist. Replaces the LLM-only orchestrator (keep `evaluateAllCriteriaWithLLM` as a thin wrapper for back-compat).
7. **Confidence routing** — LLM result below `pass_threshold` ⇒ leave pending / flag for review.

**Attestation (Tier D, §6A)** — larger, separable phase: `task_attestations`, `openAttestation` (reuse Evolution API sender), inbound webhook + reply parser, `recordAttestation`, escalation.

---

## Recommended slice for *now*

The highest-leverage, lowest-risk first build — unblocks the 733 `automated` criteria without touching the async attestation machinery:

1. Migration: add `validator`, `pass_threshold`, `auto_source` (defer `attested`/`task_attestations`).
2. `resolveArtifact()` enrichment (`exists` + `metadata`).
3. Validator registry (the 9 functions).
4. `evaluateOutput()` with structural gate + automated + (existing) llm dispatch.
5. Tests in `taskIO.test.js` per validator + one end-to-end `evaluateOutput`.

Attested + test dispatch land in the following slice (attested needs the schema widen + the attestation loop).

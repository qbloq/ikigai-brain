# Task I/O Validation — Automated Acceptance Criteria

**Status:** Draft / design — no implementation yet.
**Builds on:** [tasks-system.md](tasks-system.md) (Task I/O model) and [task-io-discovery.md](task-io-discovery.md) (the 24 canonical artifact types discovered from our tasks).

---

## 1. Goal

Every task input and output already resolves to a **generic artifact** (an `artifact_type` with a `resolver_type`). This spec defines how we **automatically verify** that those artifacts are present and correct — either **programmatically** (deterministic code) or with an **LLM** (semantic compliance, e.g. "does this report contain what the task asked for?") — and how a human stays in the loop only where automation can't or shouldn't decide.

### Non-goals
- We do **not** silently auto-pass things only a human can witness (a secret was shared, a WhatsApp was sent). But these are **not dead-ends** either: the system actively **solicits an attestation** from the responsible person and captures the answer (Section 6A). The human is the sensor; the system still drives the loop.
- This is not a workflow/dependency engine. It validates a single output's artifact against its criteria; task completion is just the aggregate.

---

## 2. What already exists (do not rebuild)

| Table | State | Role in this design |
| --- | --- | --- |
| `artifact_types` | 8 rows | `resolver_type` + `resolver_config` (how to fetch content) + `reference_schema` (required reference fields). The backbone. |
| `verification_templates` | 5 rows | LLM prompt templates keyed by `output_type` and/or `criterion_category` (`completeness`, `quality`, `format`, `accuracy`), with `is_default`. Placeholders: `{{output_content}}`, `{{criterion}}`, `{{context}}`. |
| `task_acceptance_criteria` | **empty** | Where criterion **instances + results** live (`is_met`, `confidence`, `verification_notes`). |
| `task_outputs` / `task_inputs` | empty | `deliverable_reference` / `artifact_reference` jsonb + `is_delivered` / `is_satisfied`. |

Observed `resolver_config` shapes (the contract `resolve()` must honor):

```
table     {"table":"meeting_reports","content_field":"content"}     reference: {id}
storage   {"bucket":"documents"}                                     reference: {bucket, path}
api       {"url_field":"metadata.url"}                               reference: {url}
inline    {"content_field":"metadata.content"}                       reference: {content}
computed  {"check":"task.status = approved"}                         reference: {task_id}
```

---

## 3. Core abstraction: `resolve()` then validate

The single enabling primitive. Everything downstream is a pure function over its output.

```ts
type ResolvedArtifact = {
  exists: boolean;            // did the reference dereference to something?
  type: string;              // artifact_type name
  resolver: ResolverType;
  content_text?: string;     // normalized text for LLM checks (doc body, report content, transcript)
  url?: string;              // for api/external resources
  record?: Record<string, unknown>;  // for table resolvers
  metadata?: Record<string, unknown>;// mime, size, duration, dates, etc.
};

resolve(reference: jsonb, artifactType: ArtifactType): Promise<ResolvedArtifact>
```

`resolve()` dispatches on `resolver_type` using `resolver_config`:
- **table** → select `content_field` from `{table}` where id = reference.id
- **storage** → stat + (optionally) read the object at `{bucket}/{path}`; fill `metadata.mime/size`
- **api** → dereference `url_field`; HEAD/GET for reachability; optional unfurl into `metadata.title`
- **inline** → read `content_field` straight from the reference
- **computed** → evaluate `{check}`; `exists` = the expression is satisfiable

> **A criterion can only be evaluated against a resolved artifact.** If `resolve().exists === false`, validation short-circuits (Section 6, step 3).

---

## 4. Three tiers of checks

| Tier | Method | Cost | Decides | Source of truth |
| --- | --- | --- | --- | --- |
| **A. Structural gate** | code | free | Is the artifact present & well-formed? | `reference_schema` + resolver invariant |
| **B. Programmatic** | code | free | Objective, checkable facts (mime, size, URL 200, field non-null, date future) | validator registry |
| **C. Semantic** | LLM | tokens | Does the *content comply* with the task's ask? | `verification_templates` |
| **D. Attestation** | human (system-driven) | a message | Did a real-world action happen that leaves no digital artifact? | the responsible person's reply (Section 6A) |

Tiers A–C are synchronous functions over a resolved artifact: A always runs and gates B/C; C runs only if its cheaper siblings pass (configurable), so we never spend tokens validating a missing or empty artifact. **Tier D is asynchronous** — there is nothing to resolve, so instead of fetching content the engine opens an attestation request and waits for the human signal.

---

## 5. DEFINE — where criteria come from (3 layers, increasing specificity)

### Layer 1 — Resolver invariants (automatic, no authoring)
Derived from `artifact_types`; apply to **every** artifact of that resolver:
- `reference_schema.required` fields all present in the reference, and
- the resolver invariant: storage → file exists & size>0; api → URL reachable; table → record exists; computed → check passes; inline → content non-empty.

No one writes these. They are the structural gate.

### Layer 2 — Type defaults (templated, seeded once)
Per **canonical artifact_type**, a default acceptance criterion. The resolver picks the structural check; the **type** picks the default semantic check. Seeded into `task_acceptance_criteria` (or applied implicitly) via `verification_templates.is_default` keyed on `output_type`.

See the per-type table in Section 9.

### Layer 3 — Task-specific criteria (LLM-authored, per task)
The high-value layer, reusing the discovery pipeline. Feed the **task text + its extracted outputs** to an LLM that proposes concrete acceptance criteria.

> Task: *"Escribir el nuevo VSL de 'La Ciencia de la Abundancia'."*
> Proposed criteria for the `content_draft` output:
> - *"Script follows the abundance-science angle"* → `llm`, category `accuracy`
> - *"Has a hook within the first 10 seconds"* → `llm`, category `completeness`
> - *"Includes an explicit CTA"* → `llm`, category `completeness`

Stored as `task_acceptance_criteria` rows. This is generated, then human-reviewed (same confidence-gated review flow we used for I/O extraction).

### Resolvability gates the method (learned from the sample pass)
An `automated` or `llm` criterion can only run if `resolve()` actually returns inspectable content. Many deliverables live inside **opaque third-party tools we haven't integrated** (Biturbo A/B config, ManyChat flows, ad-platform settings) — there is nothing to fetch, so an `automated`/`llm` check on them is *aspirational*, not executable. Rule:

> When authoring a criterion, check that a resolver path exists for the fact being verified. If the artifact is not inspectable (no API, no file, no record), **degrade the method to `attested`** (ask the person, optionally with evidence) rather than pretend to auto-check it.

This makes `attested` the realistic verifier for "is this configured/live?" in no-code tools, and reserves `test` for the rare case where a real CI/computed integration exists. The Layer-3 generator must apply this rule (and the critic pass should flag automated/llm criteria with no resolver path).

---

## 6. EXECUTE — the engine

A single entry point, `evaluateOutput(output_id)`:

```
1. Load output → its criteria → artifact_type → resolver_config.
2. resolved = resolve(output.deliverable_reference, artifact_type)
3. STRUCTURAL GATE (Layer 1):
     if not resolved.exists OR reference_schema unmet:
        mark every required criterion is_met=false, note="artifact not delivered/invalid"
        return  // no tokens spent
4. For each criterion:
     - method 'automated' → registry[validator.id](resolved, params) → {is_met, confidence:1, reasoning}
     - method 'llm'       → render template({{output_content}}=resolved.content_text,
                                             {{criterion}}, {{context}}=task brief)
                            → Gemini structured output → {is_met, confidence, reasoning}
     - method 'attested'  → openAttestation(criterion)  // async, see 6A; criterion stays pending
                            until the person replies; do NOT block the engine on it
     - method 'manual'    → leave pending; surface in UI for passive sign-off (no outreach)
     - method 'test'      → run/poll the linked check (CI, computed) → {is_met,...}
5. Persist each result to task_acceptance_criteria (is_met, confidence, verification_notes).
6. output.verified = all REQUIRED criteria is_met.
   task.complete    = all outputs verified AND all inputs satisfied.
7. CONFIDENCE ROUTING: an 'llm' result below pass_threshold (e.g. confidence='low')
   does NOT auto-pass → route to manual review queue.
```

### Triggers
- **On deliver** — `POST /tasks/outputs/:id/deliver` auto-calls `evaluateOutput`.
- **On demand** — the existing `POST /tasks/outputs/:output_id/evaluate`.
- **Batch** — scheduled re-validation (e.g. URL rot, record changes).

### Uniformity
Programmatic and LLM validators return the **same** `{is_met, confidence, reasoning}` shape, so the engine treats them identically and aggregation is trivial. Attestation (6A) resolves to the same shape once the human answers.

---

## 6A. Attestation loop — system-initiated, human-answered

For `attested` criteria there is no digital artifact to fetch; the thing we verify is **a real-world action only a person witnessed**. The system turns this into a closed loop where it is the initiator and the human is a sensor.

> Task: *"Enviar el mensaje de bienvenida por WhatsApp al cliente."*
> System → Felipe (WhatsApp): *"¿Ya enviaste el mensaje de bienvenida al cliente Juan Pérez? Responde SÍ / NO."*
> Felipe → *"sí, hace un rato"* → criterion `is_met=true`, attested_by=Felipe, via=whatsapp, at=…

### The loop
1. **Resolve the responsible party** (who to ask), in priority order:
   1. explicit on the artifact reference (a named person, e.g. "Felipe"),
   2. the task `assignee`(s) → `team_members`,
   3. role-based fallback (a `team_member` holding the relevant role).
2. **Resolve the channel.** `team_members.whatsapp` → WhatsApp via **Evolution API** (per-project `project_whatsapp_configs`) — the exact mechanism already used by [installment-reminder.ts](../scripts/installment-reminder.ts) / [call-reminder.ts](../scripts/call-reminder.ts). Fallbacks: in-app notification, email.
3. **Compose the prompt** from the criterion (generated, localized): a yes/no question, optionally requesting evidence.
4. **Send** — *idempotent*: at most one open request per criterion; never double-send.
5. **Capture the reply** via an inbound webhook → parse with a small LLM/regex pass → `{ attested: yes|no|unclear, evidence? }`. On `unclear`, re-ask once with a clarifying message.
6. **Resolve the criterion**: `is_met = attested`; `verification_notes` records who/when/channel; store the raw response.
7. **Escalate** on timeout: reminder → re-assign/flag for a human manager. On an explicit `NO`: stay unmet, optionally open a follow-up task.

### Evidence layering (attestation composes with auto-checks)
An attestation may carry an artifact — a screenshot, a link, a recording. That evidence then flows back through Tiers A–C: e.g. the screenshot becomes an `image_asset` that an LLM check can confirm *"shows a sent WhatsApp to the customer."* So a high-stakes `attested` criterion can require evidence **and** auto-validate it, rather than trusting a bare "yes."

### Trust & audit
Attestations are self-reported but authoritative. Always audited (`attested_by`, `attested_at`, `channel`, raw response). Criticality decides whether a bare yes suffices or evidence is mandatory.

### State machine
`pending → sent → (answered: met | unmet) | expired → escalated`. Async throughout — the synchronous engine (Section 6) only *opens* the request; an inbound-webhook handler (`recordAttestation`) closes it and re-runs output aggregation.

---

## 7. Validator registry (the code path)

A flat registry of pure functions, referenced by id from a criterion's `validator` field:

| id | params | applies to | passes when |
| --- | --- | --- | --- |
| `artifact_exists` | — | any | `resolved.exists` |
| `matches_reference_schema` | — | any | reference satisfies `reference_schema` |
| `min_length` | `{ chars }` | text artifacts | `content_text.length ≥ chars` |
| `url_reachable` | — | api | HEAD/GET → 2xx |
| `mime_in` | `{ types[] }` | storage | `metadata.mime` matches |
| `file_min_size` | `{ kb }` | storage | `metadata.size ≥ kb` |
| `record_field_not_null` | `{ field }` | table | record[field] != null |
| `date_in_future` | `{ field }` | any | parsed date > now |
| `computed_check` | — | computed | resolver_config.check is satisfied |

Extensible; each function signature is `(resolved: ResolvedArtifact, params) => CriterionResult`.

---

## 8. Data model changes

Minimal — the model is ~90% there. Proposed additions to `task_acceptance_criteria`:

| Column | Type | Why |
| --- | --- | --- |
| `validator` | jsonb null | `{ id, params }` for the **programmatic** path (spec only wired `template_id` for LLM). |
| `pass_threshold` | text null | min confidence (`high`/`medium`/`low`) for an LLM result to auto-accept; below → manual. |
| `auto_source` | text null | provenance: `resolver_invariant` / `type_default` / `llm_authored` / `manual`. For trust/triage. |

`verification_method` gains **`attested`** (alongside `automated | llm | manual | test`): system-initiated, human-answered. `manual` is reserved for purely passive UI sign-off with no outreach. `is_met`, `confidence`, `verification_notes` already exist for results.

One **new table** for the attestation loop (Section 6A):

```
task_attestations
  id                         uuid pk
  criterion_id               uuid → task_acceptance_criteria.id
  responsible_team_member_id uuid → team_members.id   (nullable)
  responsible_contact        jsonb null               (when not a team member)
  channel                    text  ('whatsapp'|'app'|'email')
  prompt_text                text
  status                     text  ('pending'|'sent'|'answered'|'expired'|'escalated')
  attested                   boolean null
  evidence                   jsonb null               (screenshot/link → re-validated via Tiers A–C)
  response_raw               text  null
  sent_at / answered_at / escalated_at   timestamptz null
  reminders_sent             int default 0
```

---

## 9. Default criteria per canonical artifact type

Resolver → structural (code); type → default semantic. `manual`-only types are where automation deliberately stops.

| Artifact type | Resolver | Structural (code) | Default semantic (LLM) | Notes |
| --- | --- | --- | --- | --- |
| `analytics_report` | api/storage | resolves + non-empty | "report covers the metrics/questions the task asked" | completeness |
| `content_draft` | storage/inline | resolves + min_length | "content matches the brief (angle, tone, CTA)" | quality+accuracy |
| `strategy_document` | storage | resolves + min_length | "covers the required strategic components" | completeness |
| `decision` | table | record exists + rationale non-null | "rationale is stated and addresses the question" | accuracy |
| `meeting_report` | table | record exists + content non-null | optional: "summarizes key points" | — |
| `spreadsheet` | api | url_reachable | optional: "contains the expected columns/rows" | format |
| `google_doc` / `documentation` | api | url_reachable | "doc addresses the task topic" | completeness |
| `external_url` | api | url_reachable | optional unfurl check | — |
| `video_asset` | storage | mime video/* + size + (duration>0) | — (optional manual review) | code-only |
| `audio_asset` | storage | mime audio/* + size | — | code-only |
| `image_asset` | storage | mime image/* + size | — | code-only |
| `storage_file` | storage | exists + size | — | code-only |
| `transcript` | storage | exists | — | code-only |
| `ad_creative` | api | object id resolves (Pipeboard/Meta) | optional: "creative matches the angle" | — |
| `schedule_event` | api | event exists + `date_in_future` | — | code-only |
| `contact_info` | table | record exists OR {name+channel} present | — | code-only |
| `data_record` | table | record/query resolves + rows>0 | — | code-only |
| `team_member` | table | record exists | — | code-only (mostly an input) |
| `task_approval` | computed | `computed_check` (status=approved) | — | code-only |
| `system_configuration` | test → attested | linked PR/CI/computed check **if an integration exists**; else `attested+evidence` ("config is live") | optional: llm-judge a config description | for no-code tools (Biturbo, ManyChat) `test` is usually unavailable → attest |
| `credentials_access` | attested | — | optional: validate evidence if provided | **attested** — system asks "¿Diste acceso a X?"; never stores the secret |
| `message_or_communication` | attested | — | optional: validate screenshot/link if provided | **attested** — system asks "¿Enviaste el mensaje a X?" |
| `inline_text` | inline | content non-empty + min_length | optional: "answers the prompt" | — |

---

## 10. LLM template mechanics

Reuse `verification_templates` as-is:
- Resolution order for a criterion: explicit `template_id` → template matching `output_type` with `is_default` → template matching `criterion_category` → `default_document`.
- Render `{{output_content}}` from `resolved.content_text` (truncate/window very long content), `{{criterion}}`, `{{context}}` from the task title + description; the existing `{{#if context}}` block carries reference material.
- Model: `gemini-2.5-flash` (matches the rest of the stack).
- Structured output: `{ is_met: boolean, confidence: 'high'|'medium'|'low', reasoning: string }`.
- Optional hardening for high-stakes criteria: an adversarial second pass (the critic pattern) before auto-accept.

---

## 11. Worked examples

**A. `analytics_report` — "reverse-engineer March–April leads/sales to find what drove conversion."**
1. resolve → report file/record. 2. Gate: exists + non-empty (code). 3. LLM: *"identifies origin, interaction, and the ads that generated conversion"* → `{is_met, confidence}`. 4. confidence `high` → auto-pass; `low` → manual queue.

**B. `video_asset` — "entregar los videos de testimonios."**
resolve → storage object. `mime_in(['video/*'])` + `file_min_size` + exists. **No LLM.** Pass = all true.

**C. `credentials_access` — "obtener acceso al código de Paralelo."**
`attested`. System messages the responsible person (WhatsApp via Evolution API): *"¿Ya diste acceso al repo de Paralelo a Andrés?"* Reply captured → criterion met, attested_by + timestamp recorded. The secret itself is never stored; the *fact of the grant* is verified by the human who did it.

**D. `schedule_event` — "agendar reunión con Pablo y Santiago."**
resolve → calendar event. `artifact_exists` + `date_in_future`. **No LLM.**

---

## 12. Open questions (decide before building)

1. **Criteria authoring UX** — auto-generate Layer-3 criteria on task creation, or on-demand when defining an output? Auto-gen + human approve seems right but adds a step.
2. **Inputs vs outputs** — inputs use `is_satisfied`; do we run the *same* validators on inputs (an input "report" must also resolve & comply), or only presence checks on inputs? Proposal: inputs get Tier A+B only; semantic compliance is for outputs.
3. **Content windowing** — large artifacts (transcripts, long reports) exceed sane prompt sizes. Chunk + map-reduce, or validate against a summary?
4. **Re-validation policy** — `api` artifacts rot (URL 404s later). How often does batch re-validation run, and does a previously-met criterion flip back to unmet?
5. **pass_threshold default** — global default `medium`? Per-category? Per-criticality?
6. **`system_configuration` / `test` verification** — the sample showed `test` is rarely applicable (no-code tools, no CI). Do we keep `test` for the few real integrations and route the rest to `attested+evidence`, or drop `test` for now? (See §5 "Resolvability gates the method".)
7. **Attestation parsing & ambiguity** — inbound replies are free-form ("sí", "ya quedó", "todavía no"). LLM-parse into yes/no/unclear; how many clarifying re-asks before escalating to a human manager?
8. **Attestation timeout & escalation** — how long before reminder, and before re-assigning? Per-criticality SLAs?
9. **Evidence requirement** — which `attested` criteria demand evidence (screenshot/link) vs. accept a bare "yes"? Likely a per-criterion or per-criticality flag.
10. **Inbound routing** — one shared WhatsApp number means replies must be correlated back to the open `task_attestations` row (by sender + most-recent-pending, or a short ref code in the prompt).

---

## 13. Suggested build phases (when we get there)

1. `resolve()` for the 5 resolver types + `ResolvedArtifact`.
2. Validator registry (Section 7) + the 3 schema columns (Section 8).
3. `evaluateOutput()` engine with the structural gate + confidence routing.
4. Seed Layer-1 invariants + Layer-2 type defaults for the 24 types.
5. Wire LLM path to `verification_templates` + Gemini.
6. Layer-3 criteria generator (LLM) with human-approve queue.
7. Triggers: deliver-hook, `/evaluate`, scheduled re-validation.
8. Attestation loop (6A): `task_attestations` table, `openAttestation` (reuse Evolution API sender), inbound webhook + LLM reply-parser, `recordAttestation`, timeout/escalation job.

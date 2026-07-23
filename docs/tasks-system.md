# Agentico Task System Specification

This document provides a comprehensive overview of the Task system's data model and available HTTP API. It is intended for AI IDEs and engineers to understand how to interact with tasks, their inputs, outputs, acceptance criteria, and the **artifact resolution layer** that binds I/O to concrete deliverables.

## 0. Conceptual Overview: Artifact-Driven Tasks

The Agentico Task System treats tasks not as checklist items but as **work contracts** with verifiable prerequisites and deliverables.

### 0.1 Tasks as "Work Contracts"
A task defines:
- **Prerequisites (Inputs)** — what is needed to start or complete the work.
- **Deliverables (Outputs)** — the specific, tangible result of the work.
- **Quality Standards (Acceptance Criteria)** — how we know the result is correct.

A task **always belongs to a project** (`project_id`). The binding/resolution layer relies on this — Notion, for example, resolves per-project.

### 0.2 The Two-Layer Type Model

The single most important concept. Every input and output carries **two** types plus a reference:

| Layer | Question | Table | Example |
|-------|----------|-------|---------|
| **IO Type** (semantic) | *What is this deliverable?* | `io_types` | "Meeting Report", "Transcript", "Strategy Document" |
| **Artifact Type** (physical) | *How does it resolve?* | `artifact_types` | SQL Results, Google Doc, Notion Page |
| **Reference** (locator) | *Which concrete instance?* | `*.artifact_reference` / `deliverable_reference` jsonb | `{ "file_id": "1AbC…" }` |

The same semantic IO Type can resolve through different physical Artifact Types: a **Meeting Report** *defaults* to SQL Results but a given task may bind its Meeting Report output to a **Google Doc** instead. The IO Type owns a `default_artifact_type_id` that pre-fills the binding UI; the binding can override it per I/O instance.

```
task_output
  ├─ io_type_id        → io_types("Meeting Report")          ← what it IS (semantic, stable)
  │                          └ default_artifact_type_id ─┐
  ├─ artifact_type_id  → artifact_types("Google Doc") ◄──┘   ← how THIS one resolves (overridable)
  └─ deliverable_reference = { "file_id": "1AbC…" }          ← the concrete locator
```

### 0.3 Acceptance Criteria (Verification)
Each output can have multiple validation rules. Verification methods: `llm`, `manual`, `automated`, `test`, `attested`. LLM verification uses `verification_templates` to prompt Gemini against the **resolved** artifact content, returning `is_met`, `confidence`, and `reasoning`.

---

## 1. Artifact Types (Physical Resolver Kinds)

`artifact_types` is the org-wide registry of **how** an artifact is physically located and read. Each row has a `resolver_type` that the validation engine (`taskValidationEngine.resolveArtifact`) switches on. Resolving returns a uniform shape:

```js
{ exists, content_text, url, record, metadata, error }
```

### 1.1 Columns
- `name` (text, unique) — internal name (e.g. `google_doc`).
- `display_name` (text) — UI label.
- `category` (text) — `document` | `approval` | `data` | `resource` | `decision`.
- `resolver_type` (text) — `table` | `storage` | `api` | `computed` | `inline` | `gdrive` | `sql` | `notion`.
- `resolver_config` (jsonb) — resolver tuning (e.g. `{ "read_only": true, "datasource": "org" }`).
- `binding_schema` (jsonb) — drives the bind UI: `{ parser, modes?, fields: [{ key, label, required }] }`.

### 1.2 Current Instances (8)

| name | display_name | category | resolver_type | resolves via |
|------|-------------|----------|---------------|--------------|
| `google_doc` | Google Doc | document | `gdrive` | Drive export → text. Token from `identities` (main `google` identity), not env. |
| `google_sheet` | Google Sheet | data | `gdrive` | Drive export → CSV. Optional `tab` (gid). |
| `drive_file` | Google Drive File | resource | `gdrive` | Any Drive file by `file_id` (metadata + downloadable content). |
| `notion_page` | Notion Page | document | `notion` | **Via marketico API** — meetico never calls Notion directly. Per-project OAuth. |
| `sql_query` | SQL Results | data | `sql` | Read-only SELECT against the org datasource → tabular result set. *(resolver pending — see §6)* |
| `storage_file` | Storage File | resource | `storage` | Supabase Storage object by `path`. |
| `web_url` | Web URL | document | `api` | Fetch a URL; existence + content. |
| `computed` | Computed Check | data | `computed` | No external fetch — evaluates a predicate over task/output state (e.g. `task.status = approved`). |

**Resolver notes**
- **`gdrive`** — sources Google OAuth tokens from the `identities` table (the system's main `google` provider identity), refreshing/persisting as needed. Never uses `GOOGLE_REFRESH_TOKEN`.
- **`notion`** — reference carries `{ page_id, url?, project_id }`. `project_id` is **required** (the resolver has no task context) and is threaded from the I/O's task. Flow: meetico → `GET {MKT_URL}/api/project-settings/:projectId/notion/page/:pageId/content` with header `x-tenant: <schema>` → marketico `getNotionPageContent` (token from `project_notion_configs`, OAuth or API key) → page title + plain text.
- **`sql`** — query carries context params (`{{task_id}}`, `{{project_id}}`, `{{output_id}}`) interpolated as **bound params**, never string-concatenated. Read-only / SELECT-only.

---

## 2. IO Types (Semantic Deliverable Kinds)

`io_types` preserves the original artifact-discovery vocabulary — *what a deliverable is*, independent of how it's stored. Reusable across both inputs and outputs.

### 2.1 Columns
- `name` (text, unique), `display_name` (text), `category` (text, same 5-value set as artifact_types).
- `description` (text), `icon` (text).
- `default_artifact_type_id` (uuid → `artifact_types.id`) — the typical physical resolution, pre-filled in the bind UI and **editable in the Admin UI** without re-migrating.

### 2.2 Current Instances (18)

| io_type | category | default artifact type |
|---------|----------|----------------------|
| `meeting_report` | document | SQL Results |
| `transcript` | document | Storage File |
| `analytics_report` | document | Web URL |
| `documentation` | document | Google Doc |
| `content_draft` | document | Google Doc |
| `strategy_document` | document | Google Doc |
| `ad_creative` | resource | Storage File |
| `audio_asset` | resource | Storage File |
| `image_asset` | resource | Storage File |
| `video_asset` | resource | Storage File |
| `contact_info` | data | SQL Results |
| `team_member` | data | SQL Results |
| `decision` | decision | SQL Results |
| `task_approval` | approval | Computed Check |
| `schedule_event` | data | Computed Check |
| `credentials_access` | resource | Computed Check |
| `message_or_communication` | data | Computed Check |
| `system_configuration` | data | Computed Check |

> **History.** These derive from the original ~24 "canonical artifact types" discovered from real task data. During the refactor (`database/refactor_io_types_and_artifacts.sql`), the semantic rows became `io_types` (reusing their UUIDs so existing I/O repointed cleanly); the physical rows became `artifact_types`. `inline_text` was **dropped** (it was the discovery LLM's "couldn't identify an artifact" fallback) — its I/O are now **unbound** for re-curation in the cockpit. `data_record` folded into the physical `sql_query`.

---

## 3. Data Model (Supabase — the `DB_SCHEMA` schema)

### 3.1 Core Task Tables

#### `tasks`
- `id` (uuid, PK), `user_id`, `project_id` (**NOT NULL** — every task has a project), `column_id`.
- `title`, `due_date`, `priority` ('Low'|'Medium'|'High'), `status` ('pending'|'in_progress'|'completed'|'blocked'|'cancelled'), `position`, `created_at`/`updated_at`.

#### `task_todos`
Checklist items: `id`, `task_id`, `text`, `completed`, `position`.

#### `task_comments`
`id`, `task_id`, `user_id`, `text`.

### 3.2 Task I/O and Acceptance Criteria

#### `io_types` — semantic (see §2).
#### `artifact_types` — physical (see §1).

#### `task_inputs` (Prerequisites)
- `task_id` → `tasks.id`.
- `io_type_id` → `io_types.id` — **what it is**.
- `artifact_type_id` → `artifact_types.id` (nullable; null = unbound) — **how this one resolves**.
- `artifact_reference` (jsonb) — the locator.
- `is_satisfied` (boolean).

#### `task_outputs` (Deliverables)
- `task_id`, `io_type_id`, `artifact_type_id` (nullable), `deliverable_reference` (jsonb), `is_delivered` (boolean).

#### `task_acceptance_criteria` (Validation)
- `output_id` → `task_outputs.id`.
- `criterion` (text), `verification_method` ('llm'|'manual'|'automated'|'test'|'attested'), `template_id` → `verification_templates.id`.
- `is_met` (boolean), `verification_notes` (text), `confidence` ('high'|'medium'|'low').

### 3.3 Supporting Tables
- `projects` — `name`, `description`, `color`.
- `task_columns` — Kanban columns: `title`, `position`.
- `verification_templates` — reusable LLM prompts: `name`, `prompt_template`, `output_type` (semantic key).

---

## 4. HTTP API Endpoints

**Auth:** all routes require `requireAuth`. Task create/list also requires an active project (`ensureProject`). `Content-Type: application/json`.

### 4.1 Tasks & Organization
- `POST /tasks` — create. Body: `{ title, priority, due_date, column_id, project_id? }`.
- `GET /tasks` — list tasks in the current project.
- `GET /tasks/:id` — task details.
- `GET /tasks/:id/with-io` — **Recommended.** Task + todos, comments, inputs, outputs, criteria in one call.
- `PUT /tasks/:id` · `DELETE /tasks/:id`.
- `POST /tasks/meetings/:meeting_id` — create task(s) from a meeting.
- Projects: `GET|POST /tasks/projects`, `GET|PUT|DELETE /tasks/projects/:id`.
- Columns: `GET|POST /tasks/columns`, `PUT|DELETE /tasks/columns/:id`.
- Todos: `POST /tasks/todos`, `PUT|DELETE /tasks/todos/:id`.
- Comments: `POST /tasks/comments`, `PUT|DELETE /tasks/comments/:id`.

### 4.2 Artifact Types (physical registry)
- `GET /tasks/artifact-types` — list.
- `GET /tasks/artifact-types/:name` — one definition.
- `GET /tasks/artifact-types/:name/usage` — blast radius (inputs/outputs/criteria using it).
- `POST /tasks/artifact-types/:name/probe` — resolve a real reference against a draft `resolver_type`/`resolver_config` (the Admin "Probe" button). Body: `{ reference, resolver_type?, resolver_config? }`.
- `PUT /tasks/artifact-types/:name` — update resolver config.

### 4.3 IO Types (semantic registry)
- `GET /tasks/io-types` — list.
- `GET /tasks/io-types/:id` — one.
- `GET /tasks/io-types/:id/usage` — blast radius.
- `POST /tasks/io-types` — create. `PUT /tasks/io-types/:id` — update (incl. `default_artifact_type_id`). `DELETE /tasks/io-types/:id` — guarded (refuses if in use).

### 4.4 Inputs / Outputs / Criteria
- Inputs: `GET|POST /tasks/:id/inputs`, `PUT|DELETE /tasks/inputs/:id`, `POST /tasks/inputs/:id/satisfy` (`{ artifact_reference }`).
- Outputs: `GET|POST /tasks/:id/outputs`, `GET|PUT|DELETE /tasks/outputs/:id`, `POST /tasks/outputs/:id/deliver` (`{ deliverable_reference }`).
- Criteria: `GET|POST /tasks/outputs/:output_id/criteria`, `GET|PUT|DELETE /tasks/criteria/:id`.
- Evaluate: `POST /tasks/outputs/:output_id/evaluate` (all criteria) · `POST /tasks/outputs/:output_id/evaluate-llm` (llm criteria only, resolves the artifact then prompts the LLM).
- Verification templates: `GET /tasks/verification-templates?category=…`.
- Attestations: `POST /tasks/attestations/:id/record`, `POST /tasks/attestations/whatsapp/inbound`.

### 4.5 I/O Review Cockpit & Binding
The review surface that curates types and binds artifacts.
- `GET /tasks/io-review` — the review feed; each item carries `io_type`, `io_type_id`, `artifact_type`, `bound`, `reference`, `project_id`.
- `POST /tasks/io-review/bulk-review` — bulk type/curation updates.
- `POST /tasks/io-review/bind-preview` — resolve a candidate binding **without saving** (powers the live "✓ resolves / ✕ does not resolve" preview). Body: `{ artifact_type_id, url|reference, project_id? }`.
- `POST /tasks/io-review/:kind/:id/bind` — persist a binding (`kind` = `inputs`|`outputs`). Validates `binding_schema` required fields, writes `artifact_type_id` + reference.
- `POST /tasks/io-review/:kind/:id/review` — mark an item reviewed.

---

## 5. UI Surfaces (marketico)

- **I/O Review Cockpit** (`IOReviewCockpit` / `ReviewRow` / `BindPanel`) — per-I/O curation: pick the semantic IO Type, see the physical artifact type, and **bind** a concrete artifact with a live resolve preview. In-place pickers: **📁 Drive…** (`DriveFilePicker`) for gdrive types, **🔎 Notion…** (`NotionPagePicker`, project's indexed pages) for `notion_page`. Paste-URL/ID is always available as a fallback.
- **Artifact Types Admin** (`ArtifactTypesAdmin.vue`, route `admin/artifact-types`) — edit `resolver_type`/`resolver_config`, probe a real reference, see blast radius.
- **IO Types Admin** (`IoTypesAdmin.vue`, route `admin/io-types`) — edit `display_name`/`category`/`description`, **set the default physical artifact type**, create/delete (guarded), see usage.

---

## 6. Status & Pending

- **`add_notion_artifact.sql`** widens the resolver CHECK to include `notion` and upserts the `notion_page` type — apply to the org schema to make the 8th type live.
- **`sql` resolver** is declared but **not yet implemented** in `taskValidationEngine.resolveArtifact` — `sql_query` bindings won't resolve until it's built (needs a read-only pg connection / guarded `run_select` RPC + context-param interpolation).
- Live Notion resolution requires marketico running, a project with `project_notion_configs`, and a page shared with the integration (index the workspace in Settings → Notion to populate the picker).

---

## 7. Usage Flow for AI Agents

1. **Create Task** — `POST /tasks` (with `project_id`).
2. **Add Requirements** — `POST /tasks/:id/inputs` (pick an `io_type_id`).
3. **Define Success** — `POST /tasks/:id/outputs` → `POST /tasks/outputs/:output_id/criteria`.
4. **Bind Artifacts** — `POST /tasks/io-review/bind-preview` to confirm resolution, then `POST /tasks/io-review/outputs/:id/bind`.
5. **Deliver Work** — `POST /tasks/outputs/:id/deliver`.
6. **Auto-Verify** — `POST /tasks/outputs/:id/evaluate`.
7. **Final Check** — `GET /tasks/:id/with-io` to confirm all `is_met` are true.

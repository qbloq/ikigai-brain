# viz — operating rules

Rules Claude must follow when editing anything under `viz/`. The architecture
narrative (file map, routes, composition tower, component catalog) lives in
[README.md](README.md); the root CLAUDE.md has the one-paragraph overview.

## Policy rails

- **Data only flows through `bash/ --json`** — same read-only policy as the rest
  of the repo. The whitelist of sources + their CLI flags is `SOURCES` in
  [lib/datasources.js](lib/datasources.js) (each entry: script + allowed flags +
  `emits: 'rows'|'object'`). **Never** add SQL to the viz — reads AND writes
  shell out to whitelisted bash scripts.
- The only write path is the IO editor: each control persists via one `@post` →
  `update_task_io.sh` (one txn) → SSE re-render. A block's `ctx.run()` throws on
  any script not declared in its `manifest.writes` (the governance rail — what
  gets approved when a component is elevated).
- **SQL bindings execute only the persisted query** (the DB row is the
  provenance), never textarea content. The SQL textarea's signal is local
  (`_`-prefixed → excluded by Datastar's default `filterSignals`) so large SQL
  never rides along on other requests; "Guardar SQL" ships it explicitly as the
  `@post` payload.

## Gotchas

- **Restart after editing `viz/`** — Node caches required modules:
  `npm run viz:restart` (or `viz:stop`) after any change (new source, component,
  cache TTL). The registry ([lib/components.js](lib/components.js)) scans
  `pages/` + `blocks/` + `patterns/` at startup into one flat namespace
  (collision = boot error).
- **Datastar 1.0 — colon syntax** (NOT v0.x dashes): `data-on:click`,
  `data-on:submit__prevent`, `data-bind="signal"`, `@get`/`@post`. SSE event is
  `datastar-patch-elements` ([lib/sse.js](lib/sse.js)). **Validate Datastar
  syntax against Context7** before changing attributes.
- Bound controls (`data-bind`) must seed their signals via `data-signals`
  (current values) or Datastar blanks them.
- Assets are **vendored** in `public/` and served locally (never CDN — avoids
  CDN/CORS): `datastar.js`, `chart.umd.js` (Chart.js v4), `charts-init.js` —
  whitelisted in `PUBLIC_FILES` in server.js.

## Caching

The DB connection (~0.8s/query, remote) dominates render time. A source opts
into a short in-memory TTL cache with `cache: <ms>` in its `SOURCES` entry. Use
it ONLY for reference/static data (`sops`, `projects`, `team` — 60s); **never**
for live operational views (`tasks`, `tasks_due`, `dashboard`), whose value is
freshness. The cache is per-process — `viz:restart` clears it. Components that
filter in the browser should fetch **once unfiltered** and slice in JS, so every
filter change is a cache hit, not a re-query (see `sop-tree`).

## Spec store (layered)

`specs/org/` (shared genome, in git — seeds live HERE, no runtime seeding) →
`specs/roles/<rol>/` → `specs/local/` (the ONLY writable layer). Editing or
archiving an org/role spec FORKS it into local with
`derived_from: "<layer>/<slug>@<git-sha>"`. Each local write **auto-commits**
(`viz(ui): <verb> <slug>` + `Delta-Type: ui-spec` / `Delta-Scope` trailers) —
git is the delta event log; `VIZ_AUTOCOMMIT=0` disables it. Programmatically:
`store.create({name, component, source, params})`. Never delete spec files from
code — archiving stamps `archived_at` (soft-hide, `/u/:id` keeps working).

## Contracts when extending

- New data source → one `SOURCES` entry; it appears in the "Nueva UI" form
  automatically.
- New component → one `pages/<name>.js` exporting `{id, render(ui), manifest}`;
  `manifest.consumes` must match the source's `emits`; `manifest.overridable`
  lists exactly the query params the browser may override (`buildArgs` ignores
  the rest — presentation-only params like `sort`/`dir` are applied in JS over
  fetched rows, never passed to the shell).
- Routed block → `blocks/<name>.js` exporting `{id, frags, acts, manifest}`,
  auto-routed under `/c/<id>/…`; acts must declare their scripts in
  `manifest.writes`. Slot-filling blocks declare `manifest.slot`
  (`master`/`detail`).
- Handlers never touch req/res: they get `ctx = {params, body, run,
  refreshUiList}` and return HTML patches; the server wraps the SSE. server.js
  never grows a route per component.
- Shared by 2+ pages (or an SSE fragment) → `blocks/`; repeated wiring →
  `patterns/`; a new combination of blocks over an existing pattern is not
  code — it's a **spec v2**. Growing `lib/kit.js` (the kernel) is a governance
  decision.
- `validateSpec` gates `POST /ui`, sweeps saved specs at boot (logs), and is
  enforced at render (unknown component degrades to a "requiere actualizar el
  núcleo" card). For v2 specs it checks the pattern's slot contract; a v2 spec
  must render byte-identical to its page-instance twin.

## Required UI furniture

- Any UI with a re-fetch or an SSE detail panel ships BOTH transparent loading
  overlays (`bg-white/50` + spinner, `.2s` opacity transition): one over the
  table via `data-indicator:<signal>` on the filter controls, one over
  `#detail-wrap` via `data-indicator:loading` on the row click. `selectCtl(...)`
  takes an `indicator` arg (default `loadingtasks`).
- Every chart card ships a «ver tabla» toggle (the accessible twin — required,
  not optional) and the standard loading overlay. The chart house style lives in
  `public/charts-init.js` (CVD-safe categorical palette in slot order,
  single-series bars in ONE color, thin marks, hairline grid) — don't restyle
  per chart.

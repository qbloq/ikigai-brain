# SOP Discovery from Task Data — Role Processes

**Status:** Discovery. Inferred by clustering the role-grouped tasks in [backups/tasks-by-role/](../backups/tasks-by-role/) (which came organically from meeting transcripts) into recurring processes. This is the first pass at turning ad-hoc, day-to-day operations into documented, repeatable SOPs.

## Method & caveats
- Each role's task file was clustered into candidate processes by an LLM pass; grounded in actual task text, not invented.
- **Heavy triplication:** most tasks are repeated across the three projects (Andrea Torres / David Guerrero / Ikigai — the same offer, *"La Ciencia de la Abundancia"*). So the *true* distinct-process count is roughly **⅓** of raw task counts. Evidence counts below are de-duplicated estimates.
- These are **candidate** SOPs for review, not finalized procedures. Names of people (David, Andrea, Mari, Sophie, etc.) appear because the tasks reference them — formalizing an SOP means replacing the person with the *role*.

---

## 1. The org's core process spine (cross-role)

The single biggest finding: the same ~10 macro-processes recur across many roles. These — not the per-role lists — are the organization's real SOPs. Each is **owned by no single role today**; that's the formalization opportunity.

| # | Macro-process | Roles that touch it | Cadence |
|---|---|---|---|
| S1 | **Offer & Narrative Development** (big idea → VSL/PSL/SL → hooks → approval) | Copy, Estratega, Ejecutivo, Director Comercial, Contenido | per-launch |
| S2 | **Ad Creative Production & Testing** (angles → hooks/variations → record → edit → launch) | Copy, PM, Estratega, Editor | per-campaign |
| S3 | **Paid-Media Optimization & Scaling** (review → kill losers → scale winners → budget) | Ejecutivo, Estratega, *(Media Buyer — unfilled)* | weekly |
| S4 | **Organic Content Engine** (daily reels, agitation stories, profile optimization) | Contenido, Ejecutivo, Estratega, Setter | daily / weekly |
| S5 | **Testimonial / Social-Proof Pipeline** (source → record → edit → publish → Notion DB) | Líder de Servicio, Editor, PM, Copy, Director Comercial | ongoing |
| S6 | **Lead Qualification & Setter Ops** (ManyChat/AI pre-qual → tagging → CTO audios → human handoff) | Director Comercial, Operaciones, Contenido, Setter, Líder de Servicio | per-campaign + weekly |
| S7 | **Funnel / Checkout / Landing Build** (Hotmart + GHL checkout, VSL A/B on Biturbo, landings) | Operaciones, Technology, Diseño, Ejecutivo | per-launch |
| S8 | **Metrics, Reporting & Source-of-Truth** (align Paralelo/Excel/GHL/Notion, dashboards, attribution) | Technology, Ejecutivo, Director Comercial, PM | weekly |
| S9 | **Launch / Masterclass Orchestration** (timeline, WhatsApp communities, warm-up, scheduling) | PM, Copy, Estratega, Operaciones | per-launch |
| S10 | **Task Governance** (meeting minutes → Notion taskboards → follow-through → weekly reports) | Project Manager | weekly / per-meeting |

These map onto a clean **value chain**:

```
Strategy/Founders
  → S1 Narrative/Offer (Copy · Estratega · Dir. Comercial)
  → S2 Creative (PM · Editor · Diseño)
  → S7 Funnel build (Operaciones · Technology)
  → S3 Traffic (Media Buyer[GAP] · Ejecutivo)
  → S4 Organic capture (Contenido) + Setter booking
  → S6 Qualify (ManyChat/AI + Setter) → Closer
  → S8 Data/Reporting (Technology · Dir. Comercial) ──┐
  └──────────────── loops back to Strategy ◀──────────┘
   (S5 Testimonials feeds S1/S2/S7 throughout · S9 Launch & S10 Governance wrap the whole cycle)
```

---

## 2. Per-role SOP candidates

### Copy (≈44 distinct)
1. **Narrative & Offer Construction** (VSL/SL/TSL) — per-launch · feeds talent + approvers *(S1)*
2. **Ad Creative Production** (copy + hooks + coordination) — per-campaign → Design, Media buyer *(S2)*
3. **Funnel & Launch Mapping** — per-launch → Automations, Design, Commercial *(S9)*
4. **Testimonial Collection & Curation** — ongoing; Andrés sources → Mari edits → Notion DB *(S5)*
5. **Organic Content Strategy** — weekly → Sophie/Santi execute *(S4)*
6. **Monthly/Seasonal Marketing Planning & Sales Pushes** — monthly *(S1/S3)*
7. **Performance Analysis & Audience Research** (reverse-engineer best months) — ad-hoc *(S8)*
8. **Infrastructure & Tooling Setup** (AI image tool, WhatsApp Business) — ad-hoc

### Ejecutivo (≈40 distinct)
1. **Paid Ad Campaign Optimization & Scaling** — weekly *(S3)*
2. **Narrative / Offer & VSL Development** — per-launch *(S1)*
3. **Checkout / Funnel & Lead-Capture Setup** (Hotmart + GHL) — per-launch *(S7)*
4. **Lead Routing, Setter Enablement & ManyChat** — per-campaign *(S6)*
5. **Metrics Alignment, Reporting & Data-Source Migration** — weekly *(S8)*
6. **Organic Content Production & Cadence Enforcement** — weekly *(S4)*
7. **Testimonials & Social-Proof System** — ongoing *(S5)*

### Project Manager (≈41 distinct)
1. **Ad Creative & Hook Production Pipeline** — per-campaign *(S2)*
2. **VSL & Funnel Asset Build/Update** — per-launch *(S1/S7)*
3. **Testimonial Sourcing & Content Editing Coordination** — weekly *(S5)*
4. **Launch / Masterclass & Organic Funnel Coordination** — per-launch *(S9)*
5. **Task Governance & Meeting Follow-up** (Notion/Paralelo) — weekly *(S10)*
6. **Strategy & Systems Planning** (KPIs, automation, tooling) — quarterly *(S8)*
> The PM is the **coordination hub** — most PM tasks are *chasing* talent/editors for delivery. The recurring bottleneck is editor delivery + talent recording.

### Contenido (≈30 distinct)
1. **Organic Content Production** (reels & stories) — daily *(S4)*
2. **Narrative & Angle Development** — per-campaign *(S1)*
3. **Audience Research (organic surveys)** — ad-hoc *(S8)*
4. **ManyChat & Social-Funnel Automation** (CTO audios) — per-campaign *(S6)*
5. **Talent Follow-up & Accountability** — weekly
6. **Profile Optimization & Conversion Assets** (pinned posts, highlights) — per-launch *(S4)*
7. **Funnel Metrics & Data Sharing** — weekly *(S8)*

### Director Comercial (≈30 distinct)
1. **Sales Data Integrity & Reporting** (de-dupe, Metricans) — weekly/monthly *(S8)*
2. **Lead Intelligence & Avatar Research** — per-campaign *(S6/S8)*
3. **Setter Operations & ManyChat/WhatsApp Infra** — per-campaign *(S6)*
4. **Closer Management & Quota Setting** — weekly
5. **Objection Handling & Client Retention** (racha negativa) — reactive
6. **New Offer Launch** (low-ticket) — per-launch *(S1)*
7. **Revenue Forecasting & Strategy** — monthly
8. **Testimonials & Social-Proof Systematization** — ongoing *(S5)*

### Estratega (≈25 distinct)
1. **Ad Creative Production** (batch ~14 reels/cycle) — per-campaign *(S2)*
2. **Narrative & Offer Development** — per-launch *(S1)*
3. **Paid-Media Campaign Structuring & Optimization** — monthly *(S3)*
4. **Audience Research & Reverse-Engineering Conversions** — ad-hoc *(S8)*
5. **Masterclass / Launch Strategy & Traffic** — per-launch *(S9)*

### Operaciones (≈22 distinct)
1. **Strategic Alignment & Avatar Research** — per-launch
2. **Landing Page & Funnel Build** — per-campaign *(S7)*
3. **VSL A/B Testing Setup** (Biturbo) — per-launch *(S7)*
4. **Testimonials Page Management** — ad-hoc *(S5)*
5. **ManyChat / AI Lead-Qualification Automation** — per-campaign *(S6)*
6. **Checkout & Payment Integration** (GHL webhook) — per-launch *(S7)*

### Technology (≈22 distinct)
1. **Metrics Data Consolidation & Source-of-Truth Alignment** (Paralelo) — weekly *(S8)*
2. **VSL Platform Engineering** (Biturbo ↔ GHL) — per-launch *(S7)*
3. **Paralelo Task-Management Feature Development** — roadmap
4. **AI Reporting & Knowledge Tools** (Ask the Graph / skills) — ad-hoc *(S8)*
5. **Sales-Origin Tracking, Payments & Commissions** (Stripe) — ad-hoc *(S8)*

### Editor (≈12 distinct)
1. **VSL Refresh & Testimonial Editing** — per-cycle *(S5/S1)*
2. **Ad Audio Editing & Asset Prep** (3 hooks → ~30 variations) — per-batch *(S2)*
3. **AI Voice Integration** — emerging (1 task)

### Setter (≈8 distinct)
1. **Daily Organic Lead Booking** (≥1 call/day) — daily *(S6)*
2. **Chat Tooling / ManyChat Setup** — setup *(S6)*
3. **Organic Performance Analysis & Forecasting** — monthly *(S8)*

### Líder de Servicio (≈5 distinct)
1. **Setter Chat Infrastructure** (co-owned with Setter) *(S6)*
2. **Testimonial Collection & Systematization** *(S5)*
3. **Trading Data Provisioning to Closers** (4yr gold/Nasdaq) — supporting

### Diseño (≈3 distinct)
1. **Offer Page / Checkout Build** (Hotmart, Premium) — per-launch *(S7)*
2. **Content Audio Upload** — too few for a stable SOP

### Closer (2 tasks)
No closing work captured — both tasks are upstream-support/traffic items. **Likely mislabeled.**

---

## 3. Findings & gaps

**A. Two missing roles — the biggest org gaps.** The unassigned pile (67 tasks) is dominated by two clusters with no owner:
- **Media Buyer / Trafficker** — the largest unassigned theme (S3 paid-ads optimization/scaling). Today it bleeds into Ejecutivo/Estratega.
- **Dev / Product** — Paralelo app, Stripe/Biturbo integrations, dashboards, "Ask the Graph". Partly Technology, but much is unowned.

**B. Role bleed & mislabels.**
- **Setter ≡ Líder de Servicio** on the ManyChat/chat-fix tasks (identical text) — ownership needs disambiguation.
- **Closer** has zero closing tasks — both items are support requests; the role is effectively mislabeled in the data.

**C. Triplication.** Andrea Torres / David Guerrero / Ikigai carry near-identical task copies — the same workstreams tracked per-project. Real distinct work ≈ ⅓ of raw counts. (This is *separate* from the duplicate-task cleanup we did earlier — these are intentional per-project copies of the same process.)

**D. Recurring bottleneck.** Across PM, Contenido, and Editor, the dominant failure mode is **talent recording + editor delivery latency** — most PM tasks are "follow up / chase / pressure" for content that's late.

---

## 4. Recommended first SOPs to formalize

Prioritize the **spine** processes that are (a) high-frequency and (b) cross-role — formalizing these removes the most ambiguity:

1. **S5 Testimonial / Social-Proof Pipeline** — touched by 5 roles with constant hand-off friction; a clear source→record→edit→publish→Notion SOP would unblock S1/S2/S7. *Best first SOP.*
2. **S2 Ad Creative Production & Testing** — the production line (angles→hooks→record→edit→launch); standardize the hand-offs PM currently chases.
3. **S6 Lead Qualification & Setter Ops** — disambiguate Setter vs Líder de Servicio; codify the ManyChat/AI→tag→CTO→human flow.
4. **S3 Paid-Media Optimization** — but first **assign a Media Buyer role**; the SOP is well-defined (weekly: kill losers → scale winners → budget), it just has no owner.
5. **S8 Metrics & Source-of-Truth** — converge on Paralelo; the SOP is "align leads/agendas/qualifications across systems weekly."

Each of these maps directly onto the Task I/O system we built: a formalized SOP = a **task template** with declared inputs, outputs, and acceptance criteria — so this discovery is the bridge from ad-hoc tasks to repeatable, *self-validating* workflows.

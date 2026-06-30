# Two-Month Operational Story — Task-Data Analysis (May–June 2026)

**Status:** Analysis. Reads the organically-captured task corpus (603 distinct tasks, pulled from meeting transcripts) as a *narrative of the operation* over its observable window. Companion to [role-sops-discovery.md](role-sops-discovery.md) (the cross-section / SOP view); this is the **longitudinal / time view**.

Sources: [backups/tasks-by-due-date/](../backups/tasks-by-due-date/) (timeline), [backups/tasks-by-role/](../backups/tasks-by-role/) (ownership), [backups/tasks-dump-2026-06-13.json](../backups/tasks-dump-2026-06-13.json) (raw), [backups/tasks-dedupe-report-2026-06-13.md](../backups/tasks-dedupe-report-2026-06-13.md).

---

## 0. How to read this data (method & caveats)

- **The window is ~6 weeks of *due dates*: 2026-05-04 → 2026-06-25**, snapshotted 2026-06-13. That's our "last two months."
- **`created_at` is meaningless as a timeline.** Every task was bulk-imported on 2026-06-11 (33) and 2026-06-13 (993 raw rows) when transcripts were loaded into the system. So **due date is the only real temporal axis** — and due dates were set to meeting/deadline days. Spikes in the due-date histogram = **meeting days**.
- **Status flags are near-useless as a completion signal** — of 603 tasks, **601 are `pending`, 2 `in_progress`, 0 `done`.** Nobody is closing tasks in the tool. So "564 overdue" measures *tracking hygiene*, not real-world incompletion.
- **The real completion signal is recurrence.** The *same* task text reappears on multiple meeting dates (examples in §3). When a team re-asks for the same deliverable across three consecutive meetings, that deliverable genuinely didn't land. This is independent of, and more trustworthy than, the status flags.
- **Triplication:** raw corpus was **1,773 rows → 603 distinct** (340 duplicate groups, 1,170 removed). On top of that, work is tracked **3× across three project fronts** (Ikigai 276 · David Guerrero 197 · Andrea Torres 130) for what is largely *one offer*. **True distinct work ≈ ⅓ of headline counts.**

---

## 1. The business underneath the tasks

Decoded from the task text, this is a **trading-education business** running paid + organic acquisition into high-ticket coaching, plus a low-ticket front and a membership ("Premium Academy"). Three brand fronts share one core offer, **"La Ciencia de la Abundancia"**:

| Front | What it is | Tasks |
|---|---|---|
| **Ikigai** | The agency/parent operation (the "real" SOP layer) | 276 |
| **David Guerrero** | Trading expert / primary talent (gold & Nasdaq, 4-yr track record) | 197 |
| **Andrea Torres** (a.k.a. Girmes) | Second expert / talent front, Premium membership | 130 |

Two facts color the whole window:
1. **A "racha negativa" (a real trading losing-streak) hit mid-May** — it shows up as churn firefighting: contacting lost clients with David voice-notes, an "anti-crisis" narrative ("habilidad refugio", "traders saltamontes", 6-month guarantee, Nasdaq long-term data). This is an **exogenous shock** the whole team had to absorb.
2. **The offer narrative never stabilized.** "Reformular la narrativa / mecanismo único / big idea de La Ciencia de la Abundancia" recurs across the window and is finally **thrown out and rewritten from scratch on June 10.** Everything downstream (ads, VSL, funnel) waits on this moving target.

---

## 2. The timeline — what each phase was about

Due-date density (each spike ≈ a strategy meeting that dumped a batch):

```
May  04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 -- 20 21 22 23 24 25 26 27 28 29 30 31
      1  1  5  2  8  2  2 15  2 28 13 31  4  8 24    69 18 35  2  3  5  9 31 58 12  2  3
Jun  01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 .. 25
     20  2 16 16 25  2  5 19  1 32 20 13  2  1  6  3  7  3 15    2
```

### Act I — "Activate Andrea" (May 4–12)
Foundational build to get the **Andrea/Premium offer live**: Hotmart checkout + **GoHighLevel webhook** for auto-user-creation, testimonials page (with the recurring **"York video" play/pause bug**), the **gamified funnel** audios, and standing up **ManyChat AI pre-qualification** on IG/WhatsApp. Plus the first churn-response tasks from the losing streak.

### Act II — Strategy explosion (May 13–22) — *the ambition peak*
The biggest meeting cluster of the window (May 13: 28, May 15: 31, **May 20: 69**, May 22: 35). The team tries to do everything at once:
- **Narrative & VSL:** reformulate the big idea, write 3 new VSL hooks, new SL for Andrea, TSL for a \$15 low-ticket.
- **Funnel architecture:** map the new paid funnels (*Follow Me Ads / Direct-Sale Low / Direct-Sale Medium Ticket*) + organic funnel.
- **"June strategy" push:** relaunch VSL with new hook + strongest testimonials, plan June around elections/World Cup/holidays.
- **Platform wishlist (Paralelo):** a whole batch of dev asks lands here — task views (Kanban/by-member/by-project), Drive-link uploads, **Stripe** installment automation, **Biturbo↔Paralelo** integration, sales-origin tracking (VSL/organic/CTR), "Ask the Graph" chat.
- **Metrics reckoning:** reverse-engineer March–April (best months) to find what converted; reconcile leads/agendas/qualifications **across Paralelo / Excel / GHL / Notion**; de-dupe the Mar–May sales numbers; fix the Metricans dashboard.

### Act III — Scale-up batch (May 27–28) — *second peak*
May 27 (31) + **May 28 (58)**: more of the same, pushed toward a June launch — more ad variations (3 hooks → ~30 edits), testimonial systematization, setter enablement, masterclass scaffolding.

### Act IV — Masterclass run-up (June 1–8)
Steady cadence (Jun 1: 20, Jun 5: 25) building toward the **"Habilidad Refugio" masterclass** (WhatsApp warm-up communities, scheduling).

### Act V — **The Pivot (June 10–11)** — *the most important inflection*
The June 10 batch (32 tasks) reads as a **strategic reset**, not incremental work:
- **Scrap & rebuild the funnel:** kill the gamified-funnel + old-VSL ad campaigns; **rewrite the VSL/PSL of "La Ciencia de la Abundancia" from scratch**; re-record with Andrea; **A/B the new VSL on Biturbo**; bump ad budget +\$100–150/day.
- **New direction & avatar:** realign strategy with Lucho/commercial + Sophie/organic on a "nueva narrativa"; fresh avatar research via organic surveys; mine the 70 gamified-funnel registrants to see who's actually arriving.
- **Re-platform the operation:** migrate the management system **off Notion**; get **access to the Paralelo app source code**; **Mari proposes to lead the implementation (with a salary bump)**; bring in Andrés Prieto to advise the transition; redefine Notion's role.
- Masterclass slips **Wed June 17 → Thu June 18**.

### Now (June 13–14)
**The only forward motion in the entire tool is the VSL relaunch** — both `in_progress` tasks are *"pass the new VSL to Luisa for group review"* and *"confirm whether the new VSL is live and what's blocking it."* Everything else sits `pending`.

---

## 3. The threads (workstreams) and where each stands

| Thread (SOP spine ref) | Arc over the window | State now |
|---|---|---|
| **Offer / Narrative** (S1) | Reformulated repeatedly → **full rewrite June 10** | 🔴 Unstable; restarted |
| **VSL / Funnel build** (S7) | Andrea checkout+webhook → gamified funnel → **killed & rebuilding on Biturbo** | 🟡 Mid-rebuild; only live thread |
| **Paid media** (S3) | "Kill losers / scale winners / budgets" repeated all window | 🔴 No owner (Media-Buyer gap) |
| **Organic content** (S4) | Daily reels + agitation stories; ManyChat | 🔴 Chronic talent non-delivery |
| **Testimonials** (S5) | source(Andrés)→edit(Mari/Toño)→Notion DB | 🟡 Works but high-friction |
| **Lead qual / Setter ops** (S6) | ManyChat AI prequal, CTO audios, **setter chat bug** | 🟡 Setter↔Líder ownership unclear |
| **Metrics / source-of-truth** (S8) | Reconcile Paralelo/Excel/GHL/Notion; de-dupe sales | 🔴 Never converged |
| **Platform / Paralelo dev** | Big wishlist (views, Stripe, Biturbo, Ask-the-Graph) | 🔴 No Dev owner; now wants source access |
| **Governance / system migration** | → **June 10 decision to leave Notion, Mari to lead** | 🟡 Just kicked off |
| **Masterclass "Habilidad Refugio"** (S9) | Warm-up comms; **date slipped 17→18** | 🟡 In flight |

---

## 4. The bottlenecks & situations

**B1 — Execution collapse / rollover.** 564/603 overdue, **0 done**, 2 in_progress. Even discounting tool hygiene, the *recurrence* is hard evidence: e.g. *"Solicitar los 2 audios del funnel gamificado"* appears on **May 20, 21, AND 22**; *"Reformular la big idea"* on May 18 and 20; *"Incrementar presupuestos / apagar anuncios de bajo rendimiento"* recurs from May 11 through June 10. **The system is a capture log, not an execution tracker** — items get re-raised each meeting instead of closed.

**B2 — Talent recording + editor delivery latency** *(the dominant failure mode)*. A huge share of **Project Manager** tasks (124) are literally *"hacer seguimiento / presionar / asegurar que David grabe / que Toño entregue."* The two human chokepoints are **the experts recording** (David, Andrea) and **the editors delivering** (Toño/Tony, Mari). The PM role exists mostly to chase them. This gates content, ads, AND the VSL.

**B3 — The offer never stabilized (narrative thrash).** Three "reformulate the big idea" cycles ending in a June-10 from-scratch rewrite means months of ads/VSL/funnel built on sand. Narrative instability is the upstream cause of much downstream rework.

**B4 — Two structural role gaps.** **Media Buyer/Trafficker** (the single largest unowned theme — S3 lives in the 67 unassigned tasks, bleeding into Ejecutivo/Estratega) and **Dev/Product** (the Paralelo platform, Stripe, Biturbo, dashboards — partly Technology, mostly unowned). The org is trying to run paid acquisition and build software with no dedicated owner for either.

**B5 — Source-of-truth fragmentation.** Leads/sales/qualifications live in **Paralelo, Excel, GHL, and Notion simultaneously**, never reconciled; sales numbers need de-duping before they can be trusted. **You cannot optimize what you can't measure** — this quietly caps B3 (no clean read on what converts) and the whole paid-media thread.

**B6 — Trading-performance crisis ("racha negativa").** Exogenous: real losing trades → churn/objection firefighting, lost clients, the entire "anti-crisis" narrative pivot. Operations spent real capacity absorbing a shock that originates outside the funnel.

**B7 — Triplication tax.** The same offer tracked 3× (Ikigai/David/Andrea) means ~3× the coordination for ~1× the distinct work, with **no shared task template** to amortize it. This is exactly the gap the Task-I/O / SOP-template work is meant to close — see [task-io-validation.md](task-io-validation.md) and [role-sops-discovery.md](role-sops-discovery.md).

---

## 5. The one-paragraph story

Over these six weeks the team tried to **activate two expert offers (David, Andrea) on top of one shared product** while a **real trading losing-streak forced a churn-defense pivot mid-stream.** Ambition peaked around **May 20** (69 tasks in a day) with a sweeping plan — new funnels, new VSL, a platform wishlist, a metrics reckoning — almost none of which closed: the same asks rolled forward meeting after meeting, gated by **talent recording and editor delivery**, and undermined by **an offer narrative that kept being rewritten** and **metrics no one could trust.** By **June 10 the team conceded and reset** — scrap the gamified funnel, rewrite the VSL from scratch, **migrate the whole operation off Notion with Mari leading**, and get source access to Paralelo. Today the **only thing actually moving is that new VSL.** The structural fixes that would break the cycle are clear and unchanged: **assign a Media Buyer and a Dev owner, converge on one source of truth, and turn the recurring meeting-asks into self-validating SOP templates** so work gets *closed* instead of *re-raised.**

---

## 6. So what — recommended reads

1. **Convergence beats ambition.** The June-10 reset is healthy *if* it's the last reset. The risk is a 4th narrative rewrite. Lock the big idea, then freeze it.
2. **Staff the two gaps first** (Media Buyer, Dev). They're the highest-leverage unblocks; the SOPs for both are already well-defined (S3, platform), they just have no owner.
3. **Pick one source of truth (Paralelo) and migrate hard.** B5 silently caps B3 and S3. The June-10 "leave Notion" decision is the right trigger — finish it.
4. **Instrument completion, not capture.** The tool needs a real `done` signal and a rule that recurring asks get *linked*, not *recreated* — otherwise every metric here stays a capture artifact.
5. **Formalize the high-friction hand-offs as Task-I/O templates** — Testimonials (S5) and Ad-Creative (S2) first; they're where the chasing concentrates. This is the bridge from this analysis to the I/O system already being built.

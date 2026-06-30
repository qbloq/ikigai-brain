# Activity Archetypes — Generic Activities as Task Templates

**Status:** Discovery. Second pass over the role-grouped tasks, this time abstracting the
concrete tasks of **David Guerrero** ([backups/tasks-by-role/david-guerrero/](../backups/tasks-by-role/david-guerrero/),
179 raw / ≈⅓ distinct) into **generic, reusable activities** ("Actividades"). Sibling of
[role-sops-discovery.md](role-sops-discovery.md): that doc found the *macro-processes* (SOPs, S1–S10);
this one finds the *atomic units of work* inside them.

Why David Guerrero alone: the work is triplicated across Andrea / David / Ikigai (same offer,
*"La Ciencia de la Abundancia"*), so one project ≈ the distinct activity set without dedup noise.

---

## 1. The ontology — three levels

```
Cadena de valor (value chain)
  └─ SOP / Macro-proceso        S1…S10   — owned by no single role today  (role-sops-discovery.md)
       └─ ACTIVIDAD (arquetipo)  A_.__    — atomic, reusable, parametrizable  ← THIS DOC
            └─ Tarea (instancia)          — concrete: real person, date, count, project
```

An **Actividad** is a `(verbo ontológico × artefacto)` pair, stripped of the specific
person/count/angle/project. Those specifics become **slots** (parameters) filled at instantiation.

- *Tarea (instancia):* "Crear **10** anuncios utilizando el ángulo de **las elecciones**."
- *Actividad (arquetipo):* **Escribir copy de un lote de anuncios** `[cantidad] · [ángulo] · [proyecto]`.

### The verb axis (controlled vocabulary)

The ontological backbone is a small set of action verbs. Every activity uses one; this keeps
the catalog consistent and makes matching tractable.

`Definir` · `Escribir` · `Producir/Crear` · `Grabar` · `Editar` · `Publicar` · `Revisar/Aprobar (gate)` ·
`Optimizar` · `Configurar` · `Integrar` · `Medir/Analizar` · `Coordinar/Seguir` · `Capacitar` · `Gestionar acceso`

---

## 2. Activity catalog (grouped by SOP)

Each row: archetype name · variable slots · example concrete task it generalizes.
`◑` = activity exists in tasks but the SOP that should own it has **no owner** (see §4).

### S1 — Narrativa & Oferta  *(per-launch)*
| # | Actividad | Slots | Ej. tarea |
|---|-----------|-------|-----------|
| A1.1 | **Reformular narrativa / big idea / mecanismo único** | proyecto | "Reformular la narrativa, el mecanismo único y la 'big idea' para 'La Ciencia de la Abundancia'." |
| A1.2 | **Escribir guion de venta largo** (VSL/PSL/SL/TSL) | tipo · proyecto · talento-grabador | "Escribir el nuevo VSL (PSL)… para que Andrea los grabe." |
| A1.3 | **Adaptar/empaquetar oferta a un formato** | formato (mastermind/low/medium ticket) · proyecto | "Adaptar la oferta 'Transformación 360' para el Mastermind…" |
| A1.4 | **Graficar escalera de valor** | proyecto | "Graficar la escalera de valor de Andrea." |
| A1.5 | **Revisar y aprobar narrativa** *(gate)* | aprobador · proyecto | "Revisar la narrativa de Andrea… y aprobarla." |
| A1.6 | **Definir ángulo de comunicación / posicionamiento** | ángulo (anticrisis, contracción económica…) | "Continuar implementando el ángulo… 'contracción económica'…" |

### S2 — Producción de Creativos (anuncios)  *(per-campaign)*
| # | Actividad | Slots | Ej. tarea |
|---|-----------|-------|-----------|
| A2.1 | **Definir/mapear ángulos y formatos de anuncios** | proyecto | "Mapear detalladamente los nuevos embudos de tráfico pago…" |
| A2.2 | **Escribir copy de un lote de anuncios** | cantidad · ángulo · proyecto | "Crear 10 anuncios utilizando el ángulo de las elecciones." |
| A2.3 | **Crear variaciones de hooks** | cantidad · base (anuncio ganador) | "Generar 3 variaciones de hooks para los anuncios 'ganadores'…" |
| A2.4 | **Grabar reels/videos de anuncio con talento** | cantidad · talento · deadline | "Grabar 14 reels con David… antes de las 5:30 PM." |
| A2.5 | **Editar audio/video de anuncios** | nº hooks → nº variaciones | "Coordinar la edición de los últimos anuncios (3 hooks, ~30 variaciones)." |
| A2.6 | **Producir anuncios con IA / voz IA** | cantidad · talento | "Empezar a rodar/testear los 4 videos de David con voz de IA…" |
| A2.7 | **Coordinar/seguir grabación con talento** | talento · entregable | "Hacer seguimiento a David (Speaker B) para la grabación de reels y hooks." |

### S3 — Optimización de Pauta  ◑ *(weekly — Media Buyer GAP)*
| # | Actividad | Slots | Ej. tarea |
|---|-----------|-------|-----------|
| A3.1 | **Optimizar campañas** (apagar perdedores / escalar ganadores) | proyecto | "Optimizar las campañas… apagar los de bajo rendimiento y producir más…" |
| A3.2 | **Ajustar presupuestos de pauta** | dirección (↑/↓) | "Incrementar presupuestos de pauta y apagar anuncios de bajo rendimiento." |
| A3.3 | **Montar estructura publicitaria** (ciclo) | periodo · base | "Montar toda la estructura publicitaria para junio…" |
| A3.4 | **Monitorear rendimiento de anuncios** | activos | "Monitorear y revisar los datos de los anuncios y el contenido orgánico…" |
| A3.5 | **Apagar campañas/funnels obsoletos** | campaña | "Apagar las campañas… que alimentan el funnel gamificado y el VSL anterior." |
| A3.6 | **Documentar estructura de campañas** (Loom) | destinatario | "Enviar un video Loom explicando la estructura actual de campañas y anuncios." |

### S4 — Contenido Orgánico  *(daily/weekly)*
| # | Actividad | Slots | Ej. tarea |
|---|-----------|-------|-----------|
| A4.1 | **Producir reels orgánicos** (cadencia) | cadencia (≥1/día) · talento | "Aumentar el volumen de contenido orgánico (mínimo un reel por día…)." |
| A4.2 | **Diseñar estrategia de historias** (CTAs/secuencias/horarios) | proyecto | "…estrategia de historias de Instagram con CTAs claros, secuencias y horarios." |
| A4.3 | **Optimizar perfil** (posts anzuelo fijados, destacados) | cantidad · proyecto | "Implementar 3 posts 'anzuelo' fijados en el perfil de David." |
| A4.4 | **Desarrollar ángulos de contenido orgánico** | perfil de cliente | "Desarrollar nuevos ángulos… (moralidad, dinero, validación masculina)." |
| A4.5 | **Hacer cumplir horarios de publicación** *(enforcement)* | talento · hora límite | "Asegurar que las historias se publiquen antes de las 4 PM…" |
| A4.6 | **Escribir reels anzuelo** | cantidad · ángulo | "Escribir 2 reels anzuelo adicionales con nuevos ángulos." |

### S5 — Testimonios / Prueba Social  *(ongoing)* — *best-first SOP per discovery doc*
| # | Actividad | Slots | Ej. tarea |
|---|-----------|-------|-----------|
| A5.1 | **Sourcing de testimonios** (identificar/solicitar) | fuente · proyecto | "Obtener los nuevos testimonios de David y enviarlos a Bala…" |
| A5.2 | **Grabar testimonios** | cantidad · talento | "Grabar videos de testimonio." |
| A5.3 | **Editar testimonios** | cantidad · destino (VSL/feed) | "Editar y entregar videos de testimonio." |
| A5.4 | **Publicar testimonios** | destino (página/VSL/Notion DB/web) | "Actualizar la página web con los 4 nuevos testimonios…" |
| A5.5 | **Estructurar registro de casos de éxito** (con trazabilidad financiera) | — | "Estructurar un sistema de registro de 'casos de éxito'…" |

### S6 — Calificación de Leads & Setter Ops  *(per-campaign + weekly)*
| # | Actividad | Slots | Ej. tarea |
|---|-----------|-------|-----------|
| A6.1 | **Implementar/configurar ManyChat** | proyecto | "Implementar ManyChat para la comunicación de setters…" |
| A6.2 | **Configurar tags por etapa de conciencia** | etapas (problema/solución/10x/agenda) | "Definir y configurar tags en ManyChat/GoHighLevel…" |
| A6.3 | **Implementar sistema de audios CTO** | etapas | "Implementar el sistema de audios para las etapas del proceso de CTO." |
| A6.4 | **Capacitar setters** | setters · tema | "Capacitar a los setters (Luis, Mateo, Franco) sobre ManyChat y tagging." |
| A6.5 | **Agendar llamadas** (setter, cadencia) | meta (≥1/día) | "Lograr agendar al menos una llamada diaria para leads orgánicos." |
| A6.6 | **Diagnosticar/resolver fallas de chat** | síntoma | "Investigar y solucionar… la inconsistencia de chats que aparecen a los setters." |
| A6.7 | **Investigar avatar / inteligencia de leads** | canal · proyecto | "Generar investigación del avatar de Andrea… (encuestas a la comunidad)." |

### S7 — Funnel / Landing / Checkout  *(per-launch)*
| # | Actividad | Slots | Ej. tarea |
|---|-----------|-------|-----------|
| A7.1 | **Crear/duplicar landing page** | propósito (captura) · destino | "Crear/duplicar una landing page para captar datos de los leads…" |
| A7.2 | **Implementar checkout** (Hotmart/GHL) | plataforma · oferta · order bumps | "Implementar un checkout de Hotmart para la oferta de Andrea." |
| A7.3 | **Configurar VSL A/B** (Biturbo) | variantes | "Continuar con… la pasarela de pagos…" / Biturbo (technology) |
| A7.4 | **Construir/actualizar página de testimonios** | testimonios | "Tener lista y funcional la página de testimonios para David…" |
| A7.5 | **Integrar pasarela de pagos** | proveedor | "Continuar con el trabajo de la pasarela de pagos para amarrar tarjetas." |

### S8 — Métricas & Fuente de Verdad  *(weekly)*
| # | Actividad | Slots | Ej. tarea |
|---|-----------|-------|-----------|
| A8.1 | **Alinear data de métricas entre sistemas** | sistemas (Paralelo/Excel/GHL) | "…alinear y organizar la data de métricas (leads, agendas, calificaciones)…" |
| A8.2 | **Ingeniería inversa de conversiones** | periodo (mejor mes) | "Realizar ingeniería inversa de leads, clientes y ventas de marzo-abril…" |
| A8.3 | **Limpiar / de-duplicar números de ventas** | periodo | "Revisar los números de ventas en marzo, abril y mayo (eliminando duplicados)." |
| A8.4 | **Definir métricas/KPIs y modelar volúmenes** | objetivo de facturación | "Definir métricas específicas (leads, tasa de agenda) para el social funnel." |
| A8.5 | **Especificar/entregar reportes requeridos** | consumidor | "Recopilar y enviar un listado detallado (drafts) de todos los reportes…" |
| A8.6 | **Medir indicador puntual** (AOV, origen de venta) | indicador | "Medir el AOV del día 1 vs el AOV promedio mensual…" |

### S9 — Lanzamiento / Masterclass  *(per-launch)*
| # | Actividad | Slots | Ej. tarea |
|---|-----------|-------|-----------|
| A9.1 | **Mapear estrategia de lanzamiento** (mensajes, fases, grupos, diseño, landing) | evento | "Enviar el mapeo detallado de la estrategia de lanzamiento…" |
| A9.2 | **Mapear masterclass** (correos, mensajes, cronograma) | fecha | "Mapear la estrategia completa para la masterclass del 17 de junio…" |
| A9.3 | **Diseñar dinámica de cierre de mes** (pico de ventas) | mes | "Diseñar y proponer una dinámica de cierre de mes para generar un pico de ventas." |

### S10 — Gobernanza de Tareas  *(weekly/per-meeting)*
| # | Actividad | Slots | Ej. tarea |
|---|-----------|-------|-----------|
| A10.1 | **Aterrizar acta → tareas en plataforma** | reunión | "Subir el acta de esta reunión… y aterrizar todas las tareas en Notion." |
| A10.2 | **Seguimiento/chase de entregable** | responsable · entregable | "Hacer seguimiento a Tony para la entrega de las ediciones de Andrea…" |
| A10.3 | **Entregar reportes semanales de reuniones** | responsable | "Mari deberá entregar reportes de reuniones semanalmente…" |
| A10.4 | **Organizar/separar espacios de gestión** | espacios | "Separar las reuniones de estrategia de David y Andrea en espacios independientes." |

---

## 3. Coverage vs the SOP spine

The 50 activities map cleanly onto S1–S10 — **this is the validation** that the spine in
[role-sops-discovery.md](role-sops-discovery.md) is the right decomposition: it is *complete* with
respect to the operational activities, with four exceptions (§4). Read top-down, each SOP is now
defined not by prose but by its **constituent activities** — i.e. a checklist of reusable templates.

| SOP | # Actividades | Owner today | Note |
|-----|--------------:|-------------|------|
| S1 Narrativa & Oferta | 6 | Copy/Estratega/Ejecutivo | gate A1.5 is the bottleneck |
| S2 Creativos | 7 | Copy/PM/Editor | A2.7 (chase) dominates PM load |
| S3 Pauta | 6 | ◑ **no owner** | bleeds into Ejecutivo/Estratega |
| S4 Orgánico | 6 | Contenido | A4.5 enforcement is recurring pain |
| S5 Testimonios | 5 | 5 roles | most hand-off friction → formalize first |
| S6 Leads/Setter | 7 | DirCom/Operaciones/Setter | Setter ≡ Líder de Servicio ambiguity |
| S7 Funnel | 5 | Operaciones/Technology | |
| S8 Métricas | 6 | Technology/DirCom | converge on Paralelo |
| S9 Lanzamiento | 3 | PM/Copy | |
| S10 Gobernanza | 4 | PM | |

---

## 4. Activities the SOP spine does NOT cover (gaps)

These appear as real tasks but have **no SOP and no clear owner** — they extend the §3 findings of
the discovery doc:

- **G1 · Dev / Producto (Paralelo).** Feature work on the task app itself (vistas por estado/miembro/cliente,
  uploads de Drive a tareas, taskboards), integraciones (Stripe cobros, Biturbo↔Paralelo, Cloud↔Notion/Drive),
  tracking de origen de ventas (VSL/orgánico/CTR), "Ask the Graph". *Partly Technology, mostly unowned —
  the **Dev/Product gap** from the discovery doc, now itemized.*
- **G2 · Gestión Comercial / Closers.** Objetivos de facturación semanales, manejo de objeciones / retención
  ("racha negativa"), proveer data de trading a closers, forecasting. *Adjacent to S6 but distinct — closing-side, not setting-side.*
- **G3 · Gestión de Equipo / Roles.** Definir funciones de cada rol, KPIs trimestrales individuales,
  revisar propuestas/ajustes salariales, redefinir herramientas de gestión (Notion). *Pure org/people-ops — no SOP.*
- **G4 · Accesos & Infraestructura de cuentas.** Obtener accesos (Meta, Hotmart, WhatsApp, código de Paralelo),
  adquirir/recuperar número de WhatsApp Business. *Cross-cutting prerequisite to many SOPs; today ad-hoc and blocking.*

> Recommendation: G1 and G2 deserve their own SOPs (**S11 Producto/Plataforma**, **S12 Cierre & Retención**);
> G3/G4 are better modeled as a lightweight **checklist/governance layer**, not full SOPs.

---

## 5. Modeling the feature — Activity Templates + matching

The closing insight of the discovery doc applies directly: *a formalized SOP = a task template with
declared inputs, outputs and acceptance criteria.* An **Activity archetype is exactly that template**,
and it reuses the Task I/O system already built (`task_inputs`/`task_outputs`/`task_acceptance_criteria`,
typed by `io_types`/`artifact_types`).

### 5.1 Schema (proposed, `ikigaigm`)

```
sops                      -- the S1…S12 spine
  code PK (S1…S12) · name · value_chain_order · description

activity_archetypes       -- the templates (this doc, §2)
  id PK · slug · name · verb · artifact · sop_code FK→sops
  default_role · default_priority · cadence (daily/weekly/per-launch/…)
  description · status (candidate/approved/deprecated) · embedding vector(1536)

archetype_params          -- the variable slots (talento, ángulo, cantidad, plataforma, proyecto…)
  id · archetype_id FK · key · label · type (text/int/enum/ref) · required · enum_options

archetype_inputs / archetype_outputs / archetype_acceptance_criteria
  -- mirror the task_* contract tables; typed by io_types/artifact_types
  -- this is the reusable "work contract" a template carries

tasks.archetype_id        -- FK→activity_archetypes (nullable): instance → template
tasks.archetype_confidence · tasks.archetype_match_method (rule/embedding/llm/human)
```

Instantiating a template = create_task with the archetype's contract pre-filled and the `{slots}`
resolved from the incoming task's specifics. The reverse (rollup) gives "all tasks of activity A2.4
across projects" — the triplication becomes a *feature* (count = how many projects run the activity).

### 5.2 Matching new tasks → archetypes (cascade)

A 3-layer pipeline, cheap→expensive, with a human-review band:

1. **Rule/keyword (cheap).** Extract `verbo + artefacto` from the task title; map via the controlled
   vocabulary (§1) to a candidate set. Catches the obvious ("Grabar … reels" → A2.4).
2. **Semantic retrieval (pgvector).** Embed `title + description`, cosine vs `activity_archetypes.embedding`;
   take top-k. Robust to paraphrase/Spanish nicknames. *(Supabase has pgvector; "Ask the Graph" already
   leans on embeddings.)*
3. **LLM judge.** Given the task + top-k candidates, pick the best archetype **or** return
   `none → new candidate`; fill `archetype_params`; emit the proposed I/O contract from the template.

   Thresholds: `≥0.85` auto-link · `0.6–0.85` suggest for human confirm · `<0.6 / none` flag as a
   **candidate new archetype** (the ontology grows from the tail — same "loop-until-dry" logic the SOP
   discovery used).

### 5.3 Where it plugs in

- **Ingestion point = the `meeting-to-tasks` skill / `create_task.sh`.** Action items already flow
  NL→structured there; add archetype assignment as one more step, so every task is born tagged.
- **Backfill** the existing 179×3 tasks with the cascade once, human-review the mid-band, to seed
  `tasks.archetype_id` and validate the catalog.
- **Snapshot exports** ([scripts/](../scripts/)) gain a `by-archetype` view next to `by-role`/`by-due-date`.

---

## 6. Next steps

1. **Validate this catalog** against Andrea + Ikigai task files (should match ≈1:1 — confirms distinctness).
2. **Approve a first batch of archetypes** to formalize — start with **S5** (5 activities, highest hand-off
   friction) per the discovery doc's recommendation; write their full I/O contracts.
3. **Decide the gaps**: stand up S11 (Producto) and S12 (Cierre/Retención), or keep G1–G4 as a checklist layer.
4. **Prototype the matcher** read-only over the snapshot first (no schema change): embed archetypes,
   classify existing tasks, eyeball precision before building the tables.

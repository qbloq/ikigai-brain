// Datasources — the ONLY bridge between the viz server and the data layer.
//
// We never write SQL here. Each source shells out to one of the read-only
// bash/ scripts with --json (same connection policy as the rest of the repo:
// read-only, ikigaigm schema, America/Bogota). A source declares which query
// params it accepts and how each maps to a CLI flag, so nothing arbitrary ever
// reaches the shell.

const { execFileSync } = require("node:child_process");
const path = require("node:path");

const REPO_ROOT = path.resolve(__dirname, "..", "..");

// flag spec: { <queryParam>: "--flag" }  — booleans use { flag: "--x", bool: true }
// `emits` declares the semantic shape of the script's --json output — 'rows'
// (an array) or 'object' (one record) — so validateSpec() can match a source
// against what a page's manifest `consumes`. (Transport always normalizes to
// an array; this is the *contract*, not the wire format.)
const SOURCES = {
  tasks: {
    label: "Tareas",
    script: "bash/tasks/tasks.sh",
    emits: "rows",
    args: {
      status: "--status",
      priority: "--priority",
      project: "--project",
      assignee: "--assignee",
      due: "--due",
      limit: "--limit",
      open: { flag: "--open", bool: true },
      // Filtros de drill-down: los emite la torre de control del PM como enlace
      // (una tarjeta de KPI aterriza exactamente en las filas que contó).
      stale: "--stale",
      macro: "--macro",
      closed: "--closed",
      no_due: { flag: "--no-due", bool: true },
      sin_arquetipo: { flag: "--sin-arquetipo", bool: true },
      sin_outputs: { flag: "--sin-outputs", bool: true },
    },
  },
  task_health: {
    label: "Salud de tareas (torre PM)",
    script: "bash/tasks/task_health.sh",
    emits: "object",
    args: { project: "--project", stale: "--stale" },
  },
  action_items_gap: {
    label: "Gap actas→tareas (S10)",
    script: "bash/meetings/action_items_gap.sh",
    emits: "rows",
    args: {
      days: "--days",
      since: "--since",
      project: "--project",
      limit: "--limit",
      pendientes: { flag: "--pendientes", bool: true },
    },
  },
  tasks_by_role: {
    label: "Tareas por rol",
    script: "bash/tasks/tasks_by_role.sh",
    emits: "rows",
    args: {
      role: "--role",
      status: "--status",
      priority: "--priority",
      project: "--project",
      due: "--due",
      limit: "--limit",
      open: { flag: "--open", bool: true },
    },
  },
  tasks_due: {
    label: "Tareas por vencimiento",
    script: "bash/tasks/tasks_due.sh",
    emits: "rows",
    // exactly one window flag is expected; pass e.g. ?window=overdue
    args: {
      window: { map: { today: "--today", tomorrow: "--tomorrow", yesterday: "--yesterday", "this-week": "--this-week", "next-week": "--next-week", overdue: "--overdue" } },
      all: { flag: "--all", bool: true },
    },
  },
  projects: { label: "Proyectos", script: "bash/tasks/projects.sh", emits: "rows", args: {}, cache: 60_000 },
  team: { label: "Equipo", script: "bash/tasks/team.sh", emits: "rows", args: { team: "--team" }, cache: 60_000 },
  // Usuarios de Marketico directo de la tabla `users` (no del API — ver
  // bash/users/users.sh para el espejo del API). Teléfono = phone_number
  // (el enlazado a WhatsApp).
  usuarios: { label: "Usuarios", script: "bash/users/usuarios_db.sh", emits: "rows", args: {}, cache: 60_000 },
  task_stats: {
    label: "Estadísticas",
    script: "bash/tasks/task_stats.sh",
    emits: "rows",
    args: { by: "--by", open: { flag: "--open", bool: true } },
  },
  meetings: {
    label: "Reuniones",
    script: "bash/meetings/meetings.sh",
    emits: "rows",
    args: {
      project: "--project",
      status: "--status",
      from: "--from",
      to: "--to",
      limit: "--limit",
      has_report: { flag: "--has-report", bool: true },
    },
  },
  // Single team-meeting report (one JSON OBJECT = the report jsonb). `id` is a
  // positional arg; emits {} (rows:[]) when the meeting has no report yet.
  meeting_detail: {
    label: "Detalle de reunión",
    script: "bash/meetings/meeting_show.sh",
    emits: "object",
    args: { id: { positional: true } },
  },
  // Financial KPI dashboard. Emits a single JSON OBJECT (not a row array) — the
  // `dashboard` component reads it as one record. Params: project + date range.
  // LA SERIE DIARIA de un proyecto: una fila por día (caja nuevas/cuotas, pauta
  // USD del día, leads/ganadas CRM, planes). Feeds the «Ventas diarias» page.
  ventas_diarias: {
    label: "Ventas diarias (caja por día)",
    script: "bash/finance/ventas_diarias.sh",
    emits: "rows",
    args: { project: "--project", from: "--from", to: "--to" },
  },
  dashboard: {
    label: "Dashboard financiero",
    script: "bash/metrics/dashboard.sh",
    emits: "object",
    args: { project: "--project", from: "--from", to: "--to" },
  },
  sops: {
    label: "SOPs & Arquetipos",
    script: "bash/catalog/sops.sh",
    emits: "rows",
    args: { macro: "--macro" },
    cache: 60_000,
  },
  // Health + findings of the ontology itself. Reads the BUILT graph artifacts
  // (docs/graph/*.json), so it is cheap and safe to cache: it only changes when
  // the graph is rebuilt, and rebuilding is what refreshes this dashboard.
  ontologia: {
    label: "Ontología (salud y hallazgos)",
    script: "bash/graph/ontology_stats.sh",
    emits: "object",
    args: {},
    cache: 60_000,
  },
  // Single task detail (one JSON object). `id` is a positional arg (no flag).
  task_detail: {
    label: "Detalle de tarea",
    script: "bash/tasks/task_detail.sh",
    emits: "object",
    args: { id: { positional: true } },
  },
  // Notion: all BD Avances tasks for a project "brief" page (positional page
  // id/url). Notion is slow (several API calls) and this data is semi-static, so
  // cache it — the notion-tasks component fetches ONCE and filters in the browser.
  notion_project_tasks: {
    label: "Tareas Notion (proyecto)",
    script: "bash/notion/project_tasks.sh",
    emits: "rows",
    args: { project: { positional: true } },
    cache: 120_000,
  },
  // The data of one "SQL Results" IO binding: executes the query persisted in
  // the row's artifact_reference (never SQL from the client — provenance lives
  // in the DB row). `io` is positional; `limit` caps rows. No cache: live data.
  io_query: {
    label: "Resultado SQL (artefacto IO)",
    script: "bash/tasks/run_io_query.sh",
    emits: "rows",
    args: { io: { positional: true }, limit: "--limit" },
  },
  // Reference data for the IO editor: { io_types[], artifact_types[] } as ONE
  // JSON object. Static/reference → short cache (the editor fetches it per form
  // render, so caching avoids re-querying the catalog on every IO edit).
  io_catalog: {
    label: "Catálogo IO",
    script: "bash/tasks/io_catalog.sh",
    emits: "object",
    args: {},
    cache: 60_000,
  },
  // --- Sales calls (meeting_type='call' — the closers' work product) --------
  // The closer is resolved through the CRM trace inside the scripts
  // (event->booking->contact_id → crm_contacts → crm_opportunities → users).
  calls: {
    label: "Llamadas de venta",
    script: "bash/calls/calls.sh",
    emits: "rows",
    args: {
      status: "--status",
      result: "--result",
      project: "--project",
      program: "--program",
      closer: "--closer",
      from: "--from",
      to: "--to",
      reported: { flag: "--reported", bool: true },
      sin_closer: { flag: "--sin-closer", bool: true },
      limit: "--limit",
    },
  },
  // One call with its full analysis report (header + raw report jsonb).
  call_detail: {
    label: "Detalle de llamada",
    script: "bash/calls/call_show.sh",
    emits: "object",
    args: { id: { positional: true } },
  },
  // Todas las llamadas de un closer, con los indicadores de captura
  // (transcript usable ≥2000 chars / fuente del reporte vigente) — la UI
  // publicada «Llamadas del closer». `meeting` filtra a una (el guard del
  // relay de transcript y de la página de reporte).
  closer_llamadas: {
    label: "Llamadas del closer",
    script: "bash/calls/closer_llamadas.sh",
    emits: "rows",
    args: {
      closer: "--closer",
      closer_id: "--closer-id",
      meeting: "--meeting",
      status: "--status",
      from: "--from",
      to: "--to",
      limit: "--limit",
    },
  },
  // La cola de ventas por resolver de un closer: leads curados en la sqlite
  // local (pareo CRM+meetings hecho a mano) cruzados EN VIVO contra
  // payment_plans — una fila pasa a 'resuelto' cuando su plan existe en el
  // sistema, nunca por marca manual. Alimenta la UI `resolver-ventas`.
  leads_resolucion: {
    label: "Ventas por resolver (closer)",
    script: "bash/closers/leads_resolucion.sh",
    emits: "rows",
    args: {
      db: "--db",
      tabla: "--tabla",
      desde: "--desde",
    },
  },
  // La matriz del experimento de prompt: una fila por llamada, tres celdas
  // (producción·gemini · producción·claude · mejorado·claude), y las celdas
  // que faltan se emiten con `existe:0` + el handle para mandarlas a correr.
  // NO se cachea: la mitad de su valor es ver aparecer la celda recién corrida.
  bant_comparativo: {
    label: "Comparativo BANT (producción vs mejorado)",
    script: "bash/calls/comparativo_bant.sh",
    emits: "rows",
    args: {
      pendientes: { flag: "--pendientes", bool: true },
      muestra: { flag: "--muestra", bool: true },
    },
  },
  bant_variabilidad: {
    label: "Variabilidad BANT (test-retest, tiradas repetidas)",
    script: "bash/calls/variabilidad_bant.sh",
    emits: "object",
    args: {},
  },
  validacion_plata: {
    label: "Validación del puntaje contra plata (AUC v2 vs producción)",
    script: "bash/calls/validacion_plata.sh",
    emits: "object",
    args: {},
  },
  // Per-closer/result/program/project/week effectiveness aggregates.
  call_stats: {
    label: "Desempeño comercial",
    script: "bash/calls/call_stats.sh",
    emits: "rows",
    args: { by: "--by", project: "--project", from: "--from", to: "--to" },
  },
  // El CENSO del survey de calificación: cada pregunta con cobertura,
  // distribución y conversión A PLATA por respuesta — la generalización
  // sistemática de docs/lead-score.md §3 y el baseline del loop A/B de survey.
  // Cache corto: es un censo (cambia con el goteo de leads, no por minuto),
  // y su query recorre todos los contactos.
  survey_censo: {
    label: "Censo del survey de calificación",
    script: "bash/crm/survey_censo.sh",
    emits: "object",
    cache: 60000,
    args: { project: "--project" },
  },
  // El MODELO de score de leads como un solo objeto: los dos scores (encuesta
  // pre-llamada y BANT post-llamada), los subgrupos y la cola accionable.
  // Entregable de la tarea 767605d8 — la contraparte consultable de
  // docs/lead-score.md. NO se cachea: es la evidencia de un contrato, y una
  // evidencia servida vieja no es evidencia.
  lead_score: {
    label: "Modelo de score de leads",
    script: "bash/calls/lead_score_model.sh",
    emits: "object",
    args: { project: "--project" },
  },
  // EL DASHBOARD de un closer como un solo objeto: llamadas con resultado
  // canónico + tramos BANT, la cola de seguimiento (BANT ≥ 81 sin cerrar),
  // coaching por llamada, objeciones y el cash real (planes/cobros/comisiones
  // vía payment_plans.user_id = el closer). La capa de operación de
  // docs/lead-score.md §5 — la ve el Director Comercial, no el closer. Sin
  // cache: es una vista operativa, y la cola vieja es dinero enfriándose.
  closer_dashboard: {
    label: "Dashboard por closer",
    script: "bash/calls/closer_dashboard.sh",
    emits: "object",
    // `closer_id` es la identidad EXACTA (users.id) y le gana a `closer`
    // (fragmento de nombre, ILIKE) dentro del script. Es lo que el publicador
    // fuerza por plantilla: el nombre de pila del JWT no identifica a nadie.
    args: { closer: "--closer", closer_id: "--closer-id", project: "--project", from: "--from", to: "--to" },
  },
  // Objections flattened across call reports — the narrative feedback loop.
  call_objections: {
    label: "Objeciones (llamadas)",
    script: "bash/calls/call_objections.sh",
    emits: "rows",
    args: { project: "--project", closer: "--closer", status: "--status", from: "--from", to: "--to", limit: "--limit" },
  },
  // --- Ejecutivo domains (bash/ads, bash/finance, bash/crm) ------------------
  // Meta campaigns with project/currency and window performance. Money columns
  // are in the account's currency (`cur`) — the table shows it, never sum across.
  ad_campaigns: {
    label: "Pauta · campañas",
    script: "bash/ads/campaigns.sh",
    emits: "rows",
    args: {
      status: "--status",
      active: { flag: "--active", bool: true },
      project: "--project",
      account: "--account",
      from: "--from",
      to: "--to",
      with_spend: { flag: "--with-spend", bool: true },
      limit: "--limit",
    },
  },
  // Aggregated ads performance (spend/CTR/CPC/CPM/purchases/ROAS/CPA), grouped
  // per currency. `by: day|week` keeps chronological order (line-chart safe).
  ad_stats: {
    label: "Pauta · desempeño",
    script: "bash/ads/ad_stats.sh",
    emits: "rows",
    args: { by: "--by", project: "--project", account: "--account", campaign: "--campaign", from: "--from", to: "--to", limit: "--limit" },
  },
  // Una fila por ANUNCIO (creativo) con métricas del pixel, hook/hold y la
  // miniatura desde la caché local (creativos_sync.sh). Feeds «Anuncios».
  ad_anuncios: {
    label: "Pauta · anuncios (creativos)",
    script: "bash/ads/anuncios.sh",
    emits: "rows",
    args: { project: "--project", from: "--from", to: "--to", tipo: "--tipo", campaign: "--campaign", min_spend: "--min-spend", limit: "--limit" },
  },
  // Ángulos ganadores → titulares: campañas por caja (atribución UTM), familias
  // de copy de anuncio (caché de creativos_sync.sh) y las landings con su H1
  // leído EN VIVO. Cache corto por la misma razón que `embudo`: toca la web
  // (curl a las landings) y encadena anuncios.sh; no es dato de referencia.
  ad_angulos: {
    label: "Pauta · ángulos ganadores → titulares",
    script: "bash/ads/angulos.sh",
    emits: "object",
    args: { project: "--project", from: "--from", to: "--to", min_spend: "--min-spend" },
    cache: 60_000,
  },
  // One campaign end-to-end: {campaign, totals, adsets[], ads[], daily[]} —
  // the future detail block of the «Pauta» master-detail. `id` is positional.
  ad_detail: {
    label: "Detalle de campaña",
    script: "bash/ads/ad_detail.sh",
    emits: "object",
    args: { id: { positional: true }, from: "--from", to: "--to", days: "--days" },
  },
  // The owner's portfolio: dashboard.sh KPIs for ALL projects + TOTAL row
  // (cash-collected model, USD; COP ad spend reported apart). Live — no cache.
  portfolio: {
    label: "Portafolio (todos los proyectos)",
    script: "bash/finance/portfolio.sh",
    emits: "rows",
    args: { from: "--from", to: "--to" },
  },
  // Uncollected installments with aging buckets; `summary` = buckets/project.
  cobranza: {
    label: "Cobranza (cuotas)",
    script: "bash/finance/cobranza.sh",
    emits: "rows",
    args: {
      overdue: { flag: "--overdue", bool: true },
      upcoming: "--upcoming",
      project: "--project",
      customer: "--customer",
      all: { flag: "--all", bool: true },
      summary: { flag: "--summary", bool: true },
      limit: "--limit",
    },
  },
  // LA MEDICIÓN de impago y deserción como un solo objeto: la curva por número
  // de cuota (el hallazgo), las cohortes ajustadas por madurez, y las dos
  // lecturas del dinero vencido — por vencimiento y por cohorte de venta, que
  // dan respuestas opuestas. Entregable de la tarea fb7a1c26 (arquetipo A12.8):
  // su output está tipado web_url y bindeado a esta UI, así que lo que se ve
  // ES la evidencia del contrato. NO se cachea, por lo mismo que lead_score.
  // La cohorte en mora: una fila por estudiante (cohorte = start_date del plan)
  // con al menos una cuota vencida sin pagar, su segmento de reactivación por
  // reglas declaradas (S1 fresca · S2 reciente · S3 avanzado · S4 temprana),
  // contacto y closer. `contexto` cambia la salida a una fila por cohorte
  // mensual (alumnos / en mora / %). Entregable de 9f249dbe. Sin cache: es la
  // lista operativa de cobranza.
  cohorte_mora: {
    label: "Cohorte en mora (por estudiante)",
    script: "bash/finance/cohorte_mora.sh",
    emits: "rows",
    args: { project: "--project", desde: "--desde", hasta: "--hasta", contexto: { flag: "--contexto", bool: true } },
  },
  desercion: {
    label: "Impago y deserción de cuotas",
    script: "bash/finance/desercion.sh",
    emits: "object",
    args: { project: "--project", desde: "--desde", corte: "--corte" },
  },
  // El HISTÓRICO de testeos del embudo (Postgres ikigaigm.testeos, migración
  // 006 — compartido entre cerebro y copilotos): cada fila con su métrica
  // objetivo, valores inicial/final congelados y desenlace. El viz solo LEE y
  // muestra el id corto como handle; abrir/cerrar es conversación
  // (bash/testeos/testeo_abrir.sh / testeo_cerrar.sh).
  testeos: {
    label: "Testeos del embudo (histórico)",
    script: "bash/testeos/testeos.sh",
    emits: "rows",
    args: { estado: "--estado", step: "--step", project: "--project", limit: "--limit" },
  },
  // EL CRUCE del embudo completo: Meta → VTurb → CRM → llamadas → caja →
  // cuotas, cada bloque con su fuente declarada (nació del meeting b3f06835:
  // el dashboard que no cuadraba). Cache corto NO por ser referencia estática
  // sino porque cada render pega a un API externo (VTurb) — 60s es etiqueta
  // con la fuente, y el objeto declara su hora de generación en meta.generado.
  embudo: {
    label: "Embudo — el cruce (Meta·VTurb·CRM·caja)",
    script: "bash/metrics/embudo.sh",
    emits: "object",
    args: { project: "--project", from: "--from", to: "--to", meses: "--meses" },
    cache: 60_000,
  },
  // El embudo ORGÁNICO: leads sin pauta por canal de entrada, conversión y
  // caja contra la pauta de marca; ManyChat solo como mapa (sin conteos).
  embudo_organico: {
    label: "Embudo orgánico (canales · conversión · vs pauta de marca)",
    script: "bash/metrics/organico.sh",
    emits: "object",
    args: { project: "--project", from: "--from", to: "--to", meses: "--meses" },
    cache: 60_000,
  },
  // Commission payouts with review state — the approval queue (pending first).
  comisiones: {
    label: "Comisiones (payouts)",
    script: "bash/finance/comisiones.sh",
    emits: "rows",
    args: { status: "--status", person: "--person", project: "--project", from: "--from", to: "--to", by: "--by", limit: "--limit" },
  },
  // Economics ledger: entradas vs opex/comisiones/reparto + neto per month.
  cashflow: {
    label: "Cashflow (ledger)",
    script: "bash/finance/cashflow.sh",
    emits: "rows",
    args: { by: "--by", project: "--project", from: "--from", to: "--to" },
  },
  // GHL opportunities: the pipeline board per stage (default), by status/month/
  // closer, or the raw list. Open opps carry value ≈ 0 — counts, not forecast.
  crm_pipeline: {
    label: "Pipeline CRM",
    script: "bash/crm/pipeline.sh",
    emits: "rows",
    args: {
      by: "--by",
      list: { flag: "--list", bool: true },
      project: "--project",
      status: "--status",
      stage: "--stage",
      from: "--from",
      to: "--to",
      limit: "--limit",
    },
  },
  // Los leads del CRM como filas, con dueño y ATRIBUCIÓN (utm_source/campaign
  // resueltos contra crm_custom_fields). `--dueno` acepta una lista separada
  // por coma, con el token `sin-dueno` para los huérfanos — así el multiselect
  // del browser viaja como un solo param.
  crm_leads: {
    label: "Leads (CRM)",
    script: "bash/crm/leads.sh",
    emits: "rows",
    args: {
      dueno: "--dueno",
      project: "--project",
      status: "--status",
      stage: "--stage",
      from: "--from",
      to: "--to",
      dias_min: "--dias-min",
      limit: "--limit",
      // Procedencia: un lead con utm_* llegó por pauta. Un solo param del
      // browser mapea a los dos flags excluyentes del script.
      origen: { map: { pagado: "--pagado", organico: "--organico" } },
      con_contacto: { flag: "--con-contacto", bool: true },
      sin_contacto: { flag: "--sin-contacto", bool: true },
    },
  },
  // El universo de dueños y etapas que puebla los filtros de `crm_leads`. Es
  // data de referencia (cambia con el equipo o el tablero, no por consulta), y
  // NO puede derivarse de las filas ya filtradas sin que los selects se cierren
  // sobre sí mismos — de ahí que sea su propia fuente, cacheada.
  crm_facets: {
    label: "Filtros del CRM",
    script: "bash/crm/facets.sh",
    emits: "rows",
    args: { project: "--project", from: "--from" },
    cache: 60_000,
  },
  // Una oportunidad + su contacto como un objeto: incluye los custom_fields de
  // GHL ya resueltos contra crm_custom_fields (el survey de calificación que
  // respondió el lead + las utm_* de atribución).
  crm_opp_detail: {
    label: "Detalle de oportunidad",
    script: "bash/crm/opp_detail.sh",
    emits: "object",
    args: { id: { positional: true } },
  },
  // --- Google Drive / Docs / Sheets (bash/google/ — read-only) --------------
  // Auth is DB-borne (OAuth token in ikigaigm.identities, file-cached ~1h by
  // the lib), so calls after the first are sub-second. No cache here: Drive
  // content is live work product (docs being edited right now).
  drive_files: {
    label: "Drive · archivos",
    script: "bash/google/drive_ls.sh",
    emits: "rows",
    args: { folder: "--folder", q: "--q", type: "--type", limit: "--limit" },
  },
  drive_file: {
    label: "Drive · metadata de archivo",
    script: "bash/google/drive_file.sh",
    emits: "object",
    args: { id: { positional: true } },
  },
  // Lo último que entró o cambió. Lee el índice cacheado del backend (no el
  // Drive vivo), así que SIEMPRE va acompañado de drive_index_status: sin la
  // frescura al lado, un índice viejo se lee como "no hubo actividad".
  drive_recent: {
    label: "Drive · recientes",
    script: "bash/google/drive_recent.sh",
    emits: "rows",
    args: {
      days: "--days",
      from: "--from",
      to: "--to",
      type: "--type",
      folder: "--folder",
      owner: "--owner",
      exclude: "--exclude",
      // Lista «|»-separada de carpetas raíz a excluir, por nombre exacto.
      exclude_folder: "--exclude-folder",
      limit: "--limit",
      docs: { bool: true, flag: "--docs" },
      modified: { bool: true, flag: "--modified" },
      with_folders: { bool: true, flag: "--with-folders" },
      by: "--by",
    },
  },
  // Frescura del índice. Apunta al script de LECTURA, nunca a drive_sync.sh:
  // buildArgs solo emite las flags declaradas, así que una llamada sin
  // --status dispararía un barrido desde una fuente de lectura.
  drive_index_status: {
    label: "Drive · frescura del índice",
    script: "bash/google/drive_status.sh",
    emits: "object",
    args: {}, // no recibe nada — pero buildArgs itera spec.args sin guardas
  },
  // One Google Doc distilled to markdown: {id, markdown} (Drive export).
  gdoc: {
    label: "Google Doc (markdown)",
    script: "bash/google/doc_read.sh",
    emits: "object",
    args: { id: { positional: true } },
  },
  // One Sheet tab's values as rows (header row = keys). While the Sheets API
  // stays disabled in the OAuth project the script falls back to Drive CSV
  // export (first tab only — tab/range ignored there).
  gsheet: {
    label: "Google Sheet (valores)",
    script: "bash/google/sheet_read.sh",
    emits: "rows",
    args: { id: { positional: true }, tab: "--tab", range: "--range", limit: "--limit" },
  },
  // --- Local SQLite databases (data/sqlite/ — the user's OWN dbs) -----------
  // Same contract as every source (a bash script with --json), but against
  // local files instead of the remote Postgres: ~ms per call, so no cache —
  // freshness matters right after an import/exec.
  // Full inventory in ONE call: [{db, size_kb, modified, tables:[{name,rows}]}].
  localdbs: { label: "Bases locales (SQLite)", script: "bash/localdb/dbs.sh", emits: "rows", args: {} },
  // Rows of one table/view of a local db. The script validates the table name
  // against sqlite_master (exact match, identifier-quoted) — nothing arbitrary
  // ever becomes SQL. What the `localdb` explorer's preview consumes.
  localdb_table: {
    label: "Tabla local (SQLite)",
    script: "bash/localdb/db_table.sh",
    emits: "rows",
    args: { db: { positional: true }, table: { positional: true }, limit: "--limit" },
  },
  // A saved SQL query over one local db, rendered as a generic-table UI. The
  // `query` param comes ONLY from the persisted UI spec — withParamOverrides
  // never forwards it from the browser — mirroring io_query's provenance rule
  // (persisted SQL executes; client SQL never does). Connection is read-only.
  localdb_query: {
    label: "Consulta SQL local (SQLite)",
    script: "bash/localdb/db_query.sh",
    emits: "rows",
    args: { db: { positional: true }, query: { positional: true }, limit: "--limit" },
  },
  // La agenda de llamadas de un día resuelta por closer (hora, lead, meet_url)
  // — la fuente del saludo matutino de Iki a los closers y de los escenarios
  // WhatsApp. Sin cache: es la agenda operativa del día.
  closer_agenda: {
    label: "Agenda de llamadas por closer",
    script: "bash/closers/agenda.sh",
    emits: "rows",
    args: {
      fecha: "--fecha",
      closer: "--closer",
      todas: { flag: "--todas", bool: true },
    },
  },
  // --- Agente WhatsApp «Iki» (bash/agentes/ — read-only) --------------------
  // La cola de recados del dispatcher: cada fila es un recado capturado con su
  // enrutamiento propuesto (que un humano aprobará en la fase siguiente).
  // Sin cache: vista operativa viva — un recado servido viejo es un despacho
  // que no ocurrió.
  iki_recados: {
    label: "Recados de Iki (cola de despacho)",
    script: "bash/agentes/recados.sh",
    emits: "rows",
    args: { para: "--para", limit: "--limit" },
  },
  // Los mensajes recibidos por el agente (whatsapp/cli), crudos. Sin cache,
  // por lo mismo que iki_recados.
  iki_entradas: {
    label: "Entradas a Iki (mensajes recibidos)",
    script: "bash/agentes/entradas.sh",
    emits: "rows",
    args: { limit: "--limit" },
  },
  // La COLA DE DESPACHO con estados (pendiente|aprobado|rechazado|ejecutado|
  // fallido): lo que la Mesa de Despacho renderiza y sobre lo que aprueba/
  // rechaza (write vía bash/agentes/despacho_mark.sh, declarado en el manifest
  // de la página). Sin cache — vista operativa viva.
  iki_despachos: {
    label: "Cola de despacho de Iki",
    script: "bash/agentes/despachos.sh",
    emits: "rows",
    args: { estado: "--estado", limit: "--limit" },
  },
  // La mirilla del webhook CRM (processBooking) + la reconciliación de agenda
  // DB↔GHL. Object de resumen sin cache (vista operativa viva); log y drift
  // son rows planos sobre la sqlite local de bash/intercepciones/.
  intercepciones_resumen: {
    label: "Intercepciones — resumen",
    script: "bash/intercepciones/resumen.sh",
    emits: "object",
    args: {},
  },
  intercepciones_log: {
    label: "Intercepciones — log del webhook CRM",
    script: "bash/intercepciones/log.sh",
    emits: "rows",
    args: { desde: "--desde", limit: "--limit", solo_errores: { flag: "--solo-errores", bool: true } },
  },
  intercepciones_drift: {
    label: "Intercepciones — drift de agenda",
    script: "bash/intercepciones/drift.sh",
    emits: "rows",
    args: { historia: { flag: "--historia", bool: true } },
  },
};

function listSources() {
  return Object.entries(SOURCES).map(([id, s]) => ({ id, label: s.label }));
}

// Build the argv for a source from a plain params object, honoring the whitelist.
function buildArgs(spec, params) {
  const argv = ["--json"];
  for (const [key, def] of Object.entries(spec.args)) {
    const raw = params[key];
    if (raw == null || raw === "") continue;
    if (typeof def === "string") {
      argv.push(def, String(raw));
    } else if (def.positional) {
      argv.push(String(raw));
    } else if (def.bool) {
      if (raw === "1" || raw === "true" || raw === true) argv.push(def.flag);
    } else if (def.map) {
      const flag = def.map[String(raw)];
      if (flag) argv.push(flag);
    }
  }
  return argv;
}

// Connecting to the (remote) DB dominates render time (~0.8s/query), so a source
// may opt into a short in-memory TTL cache via `cache: <ms>`. Reserve it for
// reference/static data (the process ontology, projects, team) — NEVER for live
// operational views (tasks, dashboard), whose whole value is freshness. The
// cache is per-process: `npm run viz:restart` clears it.
const CACHE = new Map(); // key (id+params) -> { at, value }

// Fetch rows for a source. Returns { rows, label }. Throws on unknown source
// or non-JSON output (surfaced to the user instead of swallowed).
function fetchSource(id, params = {}) {
  const spec = SOURCES[id];
  if (!spec) throw new Error(`Fuente desconocida: ${id}`);
  const ttl = spec.cache || 0;
  const key = ttl ? `${id}:${JSON.stringify(params)}` : null;
  if (key) {
    const hit = CACHE.get(key);
    if (hit && Date.now() - hit.at < ttl) return hit.value;
  }
  const scriptPath = path.join(REPO_ROOT, spec.script);
  const argv = buildArgs(spec, params);
  let out;
  try {
    out = execFileSync("bash", [scriptPath, ...argv], {
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
      cwd: REPO_ROOT,
    });
  } catch (e) {
    throw new Error(`Fallo al ejecutar ${spec.script}: ${e.stderr || e.message}`);
  }
  const trimmed = out.trim();
  let rows;
  try {
    rows = trimmed ? JSON.parse(trimmed) : [];
  } catch {
    throw new Error(`Salida no-JSON de ${spec.script}: ${trimmed.slice(0, 200)}`);
  }
  if (!Array.isArray(rows)) rows = [rows];
  const value = { rows, label: spec.label };
  if (key) CACHE.set(key, { at: Date.now(), value });
  return value;
}

module.exports = { SOURCES, listSources, fetchSource, REPO_ROOT };

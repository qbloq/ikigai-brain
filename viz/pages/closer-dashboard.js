// closer-dashboard page — el dashboard de UN closer, desde el único objeto que
// emite bash/calls/closer_dashboard.sh. Es la vista del Director Comercial:
// la capa de OPERACIÓN de docs/lead-score.md §5 (bandas, BANT, cola de
// seguimiento, cash real), que por política el closer NO ve — el closer ve su
// cola ordenada, las respuestas textuales y su coaching, nunca el número.
//
// Dos mitades deliberadas, en este orden:
//   la llamada  lo que el analizador midió (conversión canónica, tramos BANT,
//               la cola de BANT ≥ 70 que se enfría — el borde 70-80 sombreado
//               con --cau-soft —, coaching, objeciones)
//   la plata    lo que de verdad pasó (payment_plans.user_id ES el closer;
//               installments es la verdad del dinero; su comisión)
// El callStatus del reporte y el cash real son fuentes distintas — mostrarlas
// juntas es lo que permite verles la costura.

const { fetchSource } = require("../lib/datasources");
const { escape, jsStr, checkCtl } = require("../lib/kit");
const { chartEl } = require("../blocks/charts");

const TONE = { pos: "var(--pos-text)", neg: "var(--neg-text)", cau: "var(--cau-text)", brand: "var(--text-brand)", muted: "var(--text-3)" };

function num(v) {
  if (v == null || v === "") return "—";
  const n = Number(v);
  return Number.isNaN(n) ? escape(String(v)) : n.toLocaleString("es-CO");
}
const usd = (v) => (v == null ? "—" : "$" + Math.round(Number(v)).toLocaleString("en-US"));

function kpi(label, value, { tone = "brand", sub = "", title = "" } = {}) {
  return `<div class="card card-pad kpi"${title ? ` title="${escape(title)}"` : ""}>
    <span class="kpi-label">${escape(label)}</span>
    <span class="kpi-value tabular-nums" style="color:${TONE[tone] || TONE.brand}">${value}</span>
    ${sub ? `<span class="kpi-foot">${escape(sub)}</span>` : ""}
  </div>`;
}

function section(title, hint) {
  return `<div class="flex items-baseline gap-3 mt-10 mb-3 flex-wrap">
    <h2 class="text-sm font-bold uppercase tracking-wider" style="color:var(--text-2);letter-spacing:var(--tr-micro)">${escape(title)}</h2>
    ${hint ? `<span class="text-xs" style="color:var(--text-3)">${escape(hint)}</span>` : ""}
  </div>`;
}

// Tabla con una columna porcentual pintada como barra (el idioma de la página
// lead-score, su vecina en la capa del DC): el tramo que discrimina se ve de
// un vistazo, sin leer decimales.
function tbl(headers, rows, { empty = "Sin datos.", barCol = null, barMax = 100, rowAttrs = [] } = {}) {
  if (!rows.length) return `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)">${escape(empty)}</p>`;
  const th = headers.map((h) => `<th>${escape(h)}</th>`).join("");
  const tr = rows
    .map((cells, ri) =>
      `<tr${rowAttrs[ri] ? ` ${rowAttrs[ri]}` : ""}>${cells
        .map((c, i) => {
          if (barCol !== null && i === barCol) {
            const pct = Number(c) || 0;
            const w = Math.max(1, Math.min(100, (pct / barMax) * 100));
            return `<td class="whitespace-nowrap"><div class="flex items-center gap-2">
              <span class="tabular-nums font-semibold" style="min-width:3.2rem;color:${pct >= 20 ? TONE.pos : pct > 0 ? TONE.cau : TONE.muted}">${pct.toFixed(1)}%</span>
              <span style="display:block;height:6px;border-radius:3px;width:${w}%;min-width:2px;background:${pct >= 20 ? "var(--pos-solid)" : "var(--cau-solid)"}"></span>
            </div></td>`;
          }
          return `<td class="align-top">${c}</td>`;
        })
        .join("")}</tr>`
    )
    .join("");
  return `<div class="table-wrap"><div class="table-scroll"><table class="tbl">
    <thead><tr>${th}</tr></thead><tbody>${tr}</tbody></table></div></div>`;
}

const list = (items) =>
  (Array.isArray(items) ? items : items ? [items] : [])
    .map((x) => `<li class="mb-1">${escape(String(x))}</li>`)
    .join("");

function coachCard(c) {
  const score = c.score == null ? "—" : Number(c.score).toLocaleString("es-CO");
  const tone = c.score >= 7 ? TONE.pos : c.score >= 5 ? TONE.cau : TONE.neg;
  const col = (label, items, ink) =>
    (items && (Array.isArray(items) ? items.length : true))
      ? `<div class="min-w-0"><p class="text-[11px] font-semibold uppercase mb-1" style="color:${ink};letter-spacing:var(--tr-micro)">${escape(label)}</p>
         <ul class="text-xs list-disc ml-4" style="color:var(--text-2)">${list(items)}</ul></div>`
      : "";
  return `<div class="card card-pad">
    <div class="flex items-baseline gap-2 flex-wrap mb-2">
      <span class="font-semibold text-sm" style="color:var(--text-1)">${escape(c.lead || "—")}</span>
      <span class="text-xs" style="color:var(--text-3)">${escape(c.fecha || "")} · ${escape(c.resultado || "")} · <code>${escape(c.id || "")}</code></span>
      <span class="ml-auto kpi-value text-base tabular-nums" style="color:${tone}">${score}<span class="text-xs" style="color:var(--text-3)">/10</span></span>
    </div>
    <div class="grid gap-3" style="grid-template-columns:repeat(auto-fit,minmax(14rem,1fr))">
      ${col("Fortalezas", c.fortalezas, TONE.pos)}
      ${col("Áreas de mejora", c.mejoras, TONE.cau)}
      ${col("Coaching", c.coaching, TONE.brand)}
    </div>
  </div>`;
}

function renderCloserDashboard(ui) {
  // Ventana por defecto: del 1° del mes a HOY (America/Bogota). `historia=1`
  // (el checkbox «toda la historia») la anula del todo — es presentación pura:
  // buildArgs no lo conoce, la página lo consume y borra las fechas antes del
  // fetch. Sin historia, un from o to explícito manda; vaciar los inputs
  // vuelve al mes (el servidor tira los overrides vacíos, así que «ausente»
  // es la única señal disponible).
  const params = { ...(ui.params || {}) };
  const historia = String(params.historia || "") === "1";
  delete params.historia;
  const hoy = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Bogota" }).format(new Date());
  if (historia) {
    delete params.from;
    delete params.to;
  } else if (!params.from && !params.to) {
    params.from = `${hoy.slice(0, 7)}-01`;
    params.to = hoy;
  }
  let d = {};
  let err;
  try {
    const { rows } = fetchSource(ui.source || "closer_dashboard", params);
    d = rows[0] || {};
  } catch (e) {
    err = e.message;
  }
  if (err) {
    return `<section id="pane" class="flex-1 p-6 overflow-auto">
      <div class="alert alert-neg">${escape(err)}</div></section>`;
  }

  const k = d.kpis || {};
  const vn = d.ventas || {};
  const per = d.periodo || {};
  const closers = d.closers || [];
  const cur = d.closer || "";

  // Selector + ventana. Si `closer` viene FORZADO por identidad (publicador:
  // ui._locked), el dropdown no se pinta — chip fijo; y el re-fetch no emite
  // el param (el servidor lo fuerza igual: el chip es UX, no seguridad).
  // `closer_id` (identidad exacta) bloquea igual que `closer`: si no se
  // contara, el despliegue por id pintaría el dropdown libre y el chip nunca
  // — el usuario vería un selector que el servidor ignora.
  const bloqueado = (ui._locked || []).some((k) => k === "closer" || k === "closer_id");
  const qwin = `'&from='+$cdFrom+'&to='+$cdTo+'&historia='+($cdAll?1:'')`;
  const reget = bloqueado
    ? `@get('/ui/${escape(ui.id)}?x=1'+${qwin})`
    : `@get('/ui/${escape(ui.id)}?closer='+encodeURIComponent($cdCloser)+${qwin})`;
  const opts = closers
    .map((c) => {
      const parts = [c.llamadas != null ? `${c.llamadas} llamadas` : null, c.ventas != null ? `${c.ventas} ventas` : null]
        .filter(Boolean)
        .join(" · ");
      return `<option value="${escape(c.closer)}"${c.closer === cur ? " selected" : ""}>${escape(c.closer)}${parts ? ` — ${escape(parts)}` : ""}</option>`;
    })
    .join("");
  const selector = bloqueado
    ? `<span class="badge badge-brand text-sm">${escape(cur || "—")}</span>`
    : `<select data-bind="cdCloser" data-on:change="${reget}" data-indicator:loadingcloser class="select w-auto font-medium">${opts}</select>`;
  const winSignals = `cdFrom:${escape(jsStr(per.from || ""))},cdTo:${escape(jsStr(per.to || ""))},cdAll:${historia ? "true" : "false"}`;
  const signals = bloqueado
    ? `{${winSignals}}`
    : `{cdCloser:${escape(jsStr(cur))},${winSignals}}`;
  // La página abre con los filtros (decisión 2026-08-16: sin título ni
  // subtítulo); el corte y el «abrir solo» viven en esta misma línea. Las
  // fechas van acotadas ene-2026 → hoy (antes no hay datos; adelante no hay
  // días) y el checkbox «toda la historia» las desactiva y anula.
  const controls = `<div class="flex flex-wrap items-center gap-3" data-signals="${signals}">
    ${selector}
    <input type="date" min="2026-01-01" max="${hoy}" data-bind="cdFrom" data-attr:disabled="$cdAll" data-on:change="${reget}" data-indicator:loadingcloser class="input w-auto" />
    <span style="color:var(--text-3)">~</span>
    <input type="date" min="2026-01-01" max="${hoy}" data-bind="cdTo" data-attr:disabled="$cdAll" data-on:change="${reget}" data-indicator:loadingcloser class="input w-auto" />
    ${checkCtl("cdAll", "toda la historia", reget, { indicator: "loadingcloser", checked: historia })}
    <span class="badge badge-neutral ml-auto">corte ${escape(d.corte || "—")}</span>
    <a href="/u/${escape(ui.id)}" target="_blank" class="text-xs hover:underline" style="color:var(--text-brand)">abrir solo ↗</a>
  </div>`;

  const kpisLlamada = `
    ${kpi("Llamadas analizadas", num(k.llamadas), { sub: `${num(k.con_bant)} con BANT real`, title: "Sus llamadas con reporte en la ventana; el BANT en cero literal (sin transcript) no califica" })}
    ${kpi("Conversión", (k.conv_pct ?? "—") + (k.conv_pct != null ? "%" : ""), { tone: "pos", sub: `${num(k.convirtio)} de ${num(k.con_bant)}`, title: "Resultado canónico: ganada + compromiso (el cierre real lo sella la primera cuota)" })}
    ${kpi("Score de desempeño", k.score_prom != null ? `${num(k.score_prom)}<span class="text-sm" style="color:var(--text-3)">/10</span>` : "—", { title: "Promedio del finalCloserEvaluation del analizador — esto SÍ lo ve el closer" })}
    ${kpi("BANT promedio", num(k.bant_prom), { title: "Calidad promedio de los leads que le llegaron (0-100, ceros excluidos)" })}
    ${kpi("Prob. de cierre prom.", k.prob_prom != null ? num(k.prob_prom) + "%" : "—", { title: "closingProbability promedio del analizador" })}
    ${kpi("Cola sin trabajar", num(k.cola_n), { tone: k.cola_n > 0 ? "neg" : "pos", sub: "BANT ≥ 81 en seguimiento", title: "Leads del tramo que convierte ~39% que se están enfriando en su cola" })}`;

  const kpisPlata = `
    ${kpi("Ventas (planes)", num(vn.planes), { tone: "pos", title: "payment_plans a su nombre en la ventana (por fecha de inicio)" })}
    ${kpi("Venta programada", usd(vn.venta_usd), { tone: "pos", sub: "USD", title: "Suma del monto original de sus planes" })}
    ${kpi("Cash cobrado", usd(vn.cash_usd), { tone: "pos", sub: "USD · installments pagadas", title: "La verdad del dinero: cuotas efectivamente pagadas de sus planes" })}
    ${kpi("Comisiones", usd(vn.comisiones_usd), { tone: "cau", sub: `${usd(vn.comisiones_pend_usd)} sin pagar`, title: "commission_payouts a su nombre (pendiente + aprobada + pagada)" })}`;

  // Llamadas de HOY del closer, desde closer_agenda (agenda.sh: «el tablero
  // manda» — solo confirmadas en pipeline; tz = reloj literal). No sigue la
  // ventana del dashboard a propósito: es la agenda operativa del día. El
  // botón de grabar es un placeholder (el feature viene después) y solo
  // aparece cuando la llamada está EN CURSO al momento del render.
  let agenda = [];
  try {
    agenda = fetchSource("closer_agenda", cur ? { closer: cur } : {}).rows || [];
  } catch (e) {
    agenda = null;
  }
  // DUMMY (pedido 2026-08-16): fila de demo a las 12:00 para ver la sección
  // poblada —y el botón de grabar en su franja— mientras el feature de
  // grabación se define. QUITAR al cablear la grabación real.
  if (Array.isArray(agenda)) {
    agenda = [
      { hora: "12:00", fin: "13:00", lead: "Lead de prueba (demo)", meet_url: "https://meet.google.com/abc-defg-hij" },
      ...agenda,
    ].sort((a, b) => (a.hora || "").localeCompare(b.hora || ""));
  }
  const ahoraHM = new Intl.DateTimeFormat("en-GB", { timeZone: "America/Bogota", hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date());
  const ICON_MEET = `<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M17 10.5V7a1 1 0 0 0-1-1H4a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-3.5l4 4v-11l-4 4z"/></svg>`;
  const ICON_REC = `<svg width="14" height="14" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="7" fill="var(--neg-solid)"/></svg>`;
  const tHoy =
    agenda === null
      ? `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)">La agenda del día no respondió.</p>`
      : tbl(
          ["Hora", "Nombre", "Meet", "Grabar"],
          agenda.map((r) => {
            const enCurso = r.hora && r.hora <= ahoraHM && ahoraHM < (r.fin || "23:59");
            return [
              `<span class="tabular-nums font-semibold">${escape(r.hora || "")}</span>`,
              `<span class="font-medium">${escape(r.lead || "—")}</span>`,
              r.meet_url
                ? `<a href="${escape(r.meet_url)}" target="_blank" title="Abrir Google Meet" style="color:var(--text-brand)">${ICON_MEET}</a>`
                : `<span style="color:var(--text-3)">—</span>`,
              enCurso ? `<button class="btn btn-icon btn-sm" title="Grabar llamada — próximamente">${ICON_REC}</button>` : "",
            ];
          }),
          { empty: "Sin llamadas agendadas hoy." }
        );

  // Cuotas del periodo, con filtro de estado OBLIGATORIO (no hay «todas»):
  // programadas (por vencimiento) o pagadas (por fecha de pago). El filtro es
  // presentación pura — ambos grupos viajan en d.cuotas y el segmentado solo
  // mueve $cuotasG (data-show por fila, sin re-fetch).
  const cuotas = d.cuotas || [];
  const nPend = cuotas.filter((c) => c.grupo === "pendiente").length;
  const nPag = cuotas.length - nPend;
  const tCuotas = tbl(
    ["Vence", "Pagada el", "Cliente", "Proyecto", "Monto", "Pagado", "Estado"],
    cuotas.map((c) => [
      `<span class="tabular-nums text-xs">${escape(c.vence || "—")}</span>`,
      `<span class="tabular-nums text-xs">${escape(c.pagada_el || "—")}</span>`,
      `<span class="font-medium">${escape(c.cliente || "—")}</span>`,
      `<span class="text-xs">${escape(c.proyecto || "—")}</span>`,
      `<span class="tabular-nums">${usd(c.monto)}</span>`,
      `<span class="tabular-nums" style="color:${(c.pagado || 0) >= (c.monto || 0) ? TONE.pos : c.pagado > 0 ? TONE.cau : TONE.muted}">${usd(c.pagado)}</span>`,
      `<span class="badge ${c.grupo === "pagada" ? "badge-pos" : "badge-neutral"}">${escape(c.status || "—")}</span>`,
    ]),
    {
      empty: "Sin cuotas en el periodo.",
      rowAttrs: cuotas.map((c) => `data-show="$cuotasG==='${c.grupo}'"`),
    }
  );
  const cuotasHdr = `<div class="flex items-baseline gap-3 mt-10 mb-3 flex-wrap" data-signals="{cuotasG:'pendiente'}">
    <h2 class="text-sm font-bold uppercase tracking-wider" style="color:var(--text-2);letter-spacing:var(--tr-micro)">Cuotas del periodo</h2>
    <div class="btn-group">
      <button class="btn btn-sm" data-attr:aria-pressed="$cuotasG==='pendiente'" data-on:click="$cuotasG='pendiente'">Programadas (${nPend})</button>
      <button class="btn btn-sm" data-attr:aria-pressed="$cuotasG==='pagada'" data-on:click="$cuotasG='pagada'">Pagadas (${nPag})</button>
    </div>
  </div>`;
  const cuotasVacias = cuotas.length
    ? `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)" data-show="($cuotasG==='pendiente'&&${nPend === 0})||($cuotasG==='pagada'&&${nPag === 0})">Sin cuotas de ese estado en el periodo.</p>`
    : "";

  const tTramos = tbl(
    ["Tramo BANT", "Llamadas", "Convirtió", "Conversión", "En seguimiento"],
    (d.tramos || []).map((t) => [
      `<span class="font-semibold tabular-nums">${escape(t.tramo)}</span>`,
      `<span class="tabular-nums">${num(t.llamadas)}</span>`,
      `<span class="tabular-nums">${num(t.convirtio)}</span>`,
      t.conv_pct,
      `<span class="tabular-nums">${num(t.en_seguimiento)}</span>`,
    ]),
    { barCol: 3, barMax: 40, empty: "Sin llamadas con BANT en la ventana." }
  );

  // La cola trae BANT ≥ 70; el corazón sigue siendo ≥ 81 (el tramo que
  // convierte ~39%) y el borde 70-80 se distingue por fondo, no por columna.
  const cola = d.cola || [];
  const colaBorde = cola.filter((c) => Number(c.bant) < 81).length;
  const tCola = tbl(
    ["BANT", "Fecha", "Lead", "Programa", "Proyecto", "Estado"],
    cola.map((c) => [
      `<span class="tabular-nums font-bold" style="color:${Number(c.bant) >= 81 ? TONE.neg : TONE.cau}">${num(c.bant)}</span>`,
      `<span class="tabular-nums text-xs">${escape(c.fecha || "")}</span>`,
      `<span class="font-medium">${escape(c.lead || "—")}</span>`,
      `<span class="text-xs">${escape(String(c.programa || "").slice(0, 60))}</span>`,
      `<span class="text-xs">${escape(c.proyecto || "—")}</span>`,
      `<span class="badge badge-neutral">${escape(c.status || "—")}</span>`,
    ]),
    {
      empty: "La cola está vacía — nada de BANT alto se está enfriando.",
      rowAttrs: cola.map((c) => (Number(c.bant) < 81 ? `style="background:var(--cau-soft)"` : "")),
    }
  );

  // Filtro de PRESENTACIÓN «solo NOT OVERCOME»: las filas superadas/pendientes
  // llevan data-show="!$objNot" y el checkbox solo mueve la señal — sin
  // re-fetch, así que funciona igual en el publicador (que no monta /c/).
  const objs = d.objeciones || [];
  const esNot = (s) => /not[\s_-]*overcome|no\s+superad/i.test(s || "");
  const tObj = tbl(
    ["Fecha", "Lead", "Estado", "Objeción", "Respuesta del closer", "Sugerencia IA"],
    objs.map((o) => [
      `<span class="tabular-nums text-xs">${escape(o.fecha || "")}</span>`,
      `<span class="text-xs font-medium">${escape(o.lead || "—")}</span>`,
      `<span class="badge ${/overcome|superad/i.test(o.status || "") && !/not/i.test(o.status || "") ? "badge-pos" : "badge-neutral"}">${escape(o.status || "—")}</span>`,
      `<span class="text-xs">${escape(String(o.objecion || "").slice(0, 140))}</span>`,
      `<span class="text-xs" style="color:var(--text-2)">${escape(String(o.respuesta || "").slice(0, 140))}</span>`,
      `<span class="text-xs" style="color:var(--text-3)">${escape(String(o.sugerencia || "").slice(0, 140))}</span>`,
    ]),
    {
      empty: "Sin objeciones registradas en la ventana.",
      rowAttrs: objs.map((o) => (esNot(o.status) ? "" : `data-show="!$objNot"`)),
    }
  );

  const tVentas = tbl(
    ["Inicio", "Cliente", "Proyecto", "Monto", "Cobrado", "Estado"],
    ((vn.recientes || [])).map((p) => [
      `<span class="tabular-nums text-xs">${escape(p.inicio || "")}</span>`,
      `<span class="font-medium">${escape(p.cliente || "—")}</span>`,
      `<span class="text-xs">${escape(p.proyecto || "—")}</span>`,
      `<span class="tabular-nums">${usd(p.monto)}</span>`,
      `<span class="tabular-nums" style="color:${(p.cobrado || 0) >= (p.monto || 0) ? TONE.pos : TONE.cau}">${usd(p.cobrado)}</span>`,
      `<span class="badge badge-neutral">${escape(p.estado || "—")}</span>`,
    ]),
    { empty: "Sin planes de pago a su nombre en la ventana." }
  );

  // «sin data» es el balde RESIDUAL del resultado (el callStatus libre no matcheó
  // ningún patrón) y viene con score 0-1: análisis sobre llamadas sin transcript
  // usable. Como coaching es ruido — evalúa una conversación que no se midió —
  // así que no se muestra. Filtro de PRESENTACIÓN: la fuente sigue emitiéndolas;
  // el conteo de ocultas solo se declara en el estado vacío (decisión
  // 2026-08-16: la sección va sin subtítulo).
  const coachTodas = d.coaching || [];
  const coachVis = coachTodas.filter(
    (c) => String(c.resultado || "").trim().toLowerCase() !== "sin data"
  );
  const coachOcultas = coachTodas.length - coachVis.length;
  const coaching = coachVis.map(coachCard).join("") ||
    `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)">${
      coachTodas.length
        ? `Ninguna llamada evaluable en la ventana (${coachOcultas} sin data).`
        : "Sin llamadas evaluadas en la ventana."
    }</p>`;

  // --- Gráficas de cierre --------------------------------------------------
  // Comparativo mensual: venta y cash (misma unidad, USD) de los 3 meses que
  // terminan en el mes de la ventana; llamadas/conversión van en la tabla
  // gemela (mezclar conteos con dólares en un eje es mentirle a la escala).
  const cmp = d.comparativo || [];
  const cmpSpec = cmp.length
    ? {
        kind: "bar",
        horizontal: false,
        labels: cmp.map((x) => x.mes),
        series: [
          { label: "Venta programada (USD)", data: cmp.map((x) => Number(x.venta_usd) || 0) },
          { label: "Cash cobrado (USD)", data: cmp.map((x) => Number(x.cash_usd) || 0) },
        ],
      }
    : null;
  const tCmp = tbl(
    ["Mes", "Llamadas analizadas", "Convirtió", "Venta (USD)", "Cash (USD)"],
    cmp.map((x) => [
      `<span class="tabular-nums font-semibold">${escape(x.mes)}</span>`,
      `<span class="tabular-nums">${num(x.llamadas)}</span>`,
      `<span class="tabular-nums">${num(x.convirtio)}</span>`,
      `<span class="tabular-nums">${usd(x.venta_usd)}</span>`,
      `<span class="tabular-nums">${usd(x.cash_usd)}</span>`,
    ]),
    { empty: "Sin datos mensuales." }
  );

  // Leaderboard: la venta del periodo por closer, con los DEMÁS anonimizados
  // (Closer A, B…) — la identidad ajena no viaja a la vista del closer; la
  // propia (el closer seleccionado) sí se nombra. El share es contra la venta
  // total del periodo de todos los closers.
  const lbTodos = (d.closers || [])
    .map((c) => ({ closer: c.closer || "—", venta: Number(c.venta_usd) || 0 }))
    .sort((a, b) => b.venta - a.venta);
  const totalVenta = lbTodos.reduce((s, c) => s + c.venta, 0);
  let anonSeq = 0;
  const lbRows = lbTodos
    .map((c) => ({
      self: c.closer === cur,
      label: c.closer === cur ? c.closer : `Closer ${String.fromCharCode(65 + anonSeq++)}`,
      venta: c.venta,
      share: totalVenta ? Math.round((100 * c.venta) / totalVenta) : 0,
    }))
    .filter((r) => r.venta > 0 || r.self);
  const selfShare = (lbRows.find((r) => r.self) || {}).share;
  const lbSpec = lbRows.length
    ? { kind: "bar", labels: lbRows.map((r) => r.label), series: [{ label: "Venta (USD)", data: lbRows.map((r) => r.venta) }] }
    : null;
  const tLb = tbl(
    ["Closer", "Venta (USD)", "Share"],
    lbRows.map((r) => [
      `<span class="${r.self ? "font-bold" : ""}">${escape(r.label)}</span>`,
      `<span class="tabular-nums">${usd(r.venta)}</span>`,
      `<span class="tabular-nums">${num(r.share)}%</span>`,
    ]),
    { empty: "Sin ventas en el periodo." }
  );

  const chartCard = (spec, table, sig) => `<div class="card card-pad">
    ${chartEl(spec, { height: 260 })}
    <div class="mt-3 pt-2" style="border-top:1px solid var(--border-1)">
      <button data-on:click="$${sig}=!$${sig}" class="text-xs hover:underline" style="color:var(--text-brand)">
        <span data-text="$${sig} ? 'ocultar tabla' : 'ver tabla'">ver tabla</span>
      </button>
      <div data-show="$${sig}" style="display:none" class="mt-2">${table}</div>
    </div>
  </div>`;
  const charts = `<div data-signals="{showcmp:false,showlead:false}">
    ${section("Comparativo mensual", "venta y cash de los últimos 3 meses — llamadas y conversión, en la tabla")}
    ${chartCard(cmpSpec, tCmp, "showcmp")}
    ${section("Leaderboard de venta", `venta total del periodo ${usd(totalVenta)}${selfShare != null ? ` — share de ${cur}: ${selfShare}%` : ""}`)}
    ${chartCard(lbSpec, tLb, "showlead")}
  </div>`;

  // id="pane" NO es decorativo: el SSE parchea por id (ver pages/lead-score.js).
  return `<section id="pane" class="flex-1 relative overflow-auto p-6">
    <style>#cd-loading{opacity:0;transition:opacity .2s ease}#cd-loading.on{opacity:1}</style>
    <div id="cd-loading" data-class:on="$loadingcloser" class="pointer-events-none absolute inset-0 z-10 flex items-start justify-center pt-16 bg-white/50">
      <div class="w-7 h-7 rounded-full border-2 border-slate-300 border-t-indigo-600 animate-spin"></div>
    </div>
    <div class="max-w-6xl mx-auto">
      ${controls}

      <div class="grid gap-3 mt-8" style="grid-template-columns:repeat(auto-fit,minmax(11rem,1fr))">${kpisLlamada}</div>

      <div class="grid gap-3 mt-3" style="grid-template-columns:repeat(auto-fit,minmax(13rem,1fr))">${kpisPlata}</div>

      ${section("Llamadas de hoy")}
      ${tHoy}

      ${cuotasHdr}
      ${tCuotas}
      ${cuotasVacias}

      ${section("Ventas recientes")}
      ${tVentas}

      ${section("Tramos BANT")}
      ${tTramos}

      ${section("Cola de seguimiento", `${num(k.cola_n)} llamadas de BANT ≥ 81 que quedaron en seguimiento y nunca cerraron — el dinero sobre la mesa${colaBorde ? ` (+${num(colaBorde)} de 70-80, sombreadas)` : ""}`)}
      ${tCola}

      ${section("Coaching por llamada")}
      <div class="grid gap-3" style="grid-template-columns:repeat(auto-fit,minmax(24rem,1fr))">${coaching}</div>

      <div class="flex items-baseline gap-3 mt-10 mb-3 flex-wrap" data-signals="{objNot:false}">
        <h2 class="text-sm font-bold uppercase tracking-wider" style="color:var(--text-2);letter-spacing:var(--tr-micro)">Objeciones recientes</h2>
        ${checkCtl("objNot", "solo NOT OVERCOME", "", { indicator: "" })}
      </div>
      ${tObj}

      ${charts}
    </div>
  </section>`;
}

module.exports = {
  id: "closer-dashboard",
  // `historia` es presentación pura (la consume la página, buildArgs la ignora)
  manifest: { consumes: "object", overridable: ["closer", "project", "from", "to", "historia"] },
  render: renderCloserDashboard,
};

// closer-llamadas page — TODAS las llamadas de un closer (fuente
// closer_llamadas), una fila por meeting con los dos indicadores de captura:
//   transcript  usable (≥2000 chars) → icono ⬇ que descarga el .txt vía el
//               relay del publicador (params.base_t, fijado al publicar como
//               /t/<slug>; vacío = el icono no se pinta — el viz local no
//               tiene relay).
//   reporte     existe → link a la página standalone del reporte
//               (params.base_r + ?meeting=), con su fuente como badge.
// Identidad publicada: closer_id forzado por plantilla ($user_id) — el DC
// (identidad {}) ve todos los closers y puede filtrar con ?closer=.
const { fetchSource } = require("../lib/datasources");
const { escape, jsStr, selectCtl } = require("../lib/kit");

// meetings.status → español (la DB habla inglés, la UI español)
const ES_STATUS = {
  scheduled: "Programada",
  confirmed: "Confirmada",
  in_progress: "En curso",
  ended: "Terminada",
  completed: "Completada",
  processing: "Procesando",
  cancelled: "Cancelada",
};
// «todas» es sentinela (no un status real): el server tira los overrides
// vacíos, así que el valor vacío no puede significar «sin filtro» — sin
// status en la URL el default es Completada. Y «Completada» SUBSUME
// completed+confirmed (decisión 2026-08-19): son la misma cosa para el
// closer, la llamada quedó capturada. El badge por fila sí las distingue.
const DEFAULT_STATUS = "completed,confirmed";
const STATUS_OPTS = [
  ["todas", "Todos los estados"],
  [DEFAULT_STATUS, "Completada"],
  ["in_progress", "En curso"],
  ["scheduled", "Programada"],
  ["ended", "Terminada"],
  ["processing", "Procesando"],
  ["cancelled", "Cancelada"],
];

const ICON_DL = `<svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M5 20h14v-2H5v2zM12 2v12l4-4 1.4 1.4L12 17.8 5.6 11.4 7 10l4 4V2h1z"/></svg>`;
const ICON_DOC = `<svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z"/></svg>`;

function renderCloserLlamadas(ui) {
  const params = { ...(ui.params || {}) };
  const baseT = String(params.base_t || "");
  const baseR = String(params.base_r || `/u/reporte-llamada`);
  delete params.base_t;
  delete params.base_r;

  const stParam = String(params.status || "");
  const stSelect = stParam === "" ? DEFAULT_STATUS : stParam;
  if (stSelect === "todas") delete params.status;
  else params.status = stSelect;

  let rows = [];
  let err;
  try {
    rows = fetchSource(ui.source || "closer_llamadas", params).rows || [];
  } catch (e) {
    err = e.message;
  }
  if (err) {
    return `<section id="pane" class="flex-1 p-6 overflow-auto"><div class="alert alert-neg">${escape(err)}</div></section>`;
  }

  const bloqueado = (ui._locked || []).some((k) => k === "closer" || k === "closer_id");
  const reget = bloqueado
    ? `@get('/ui/${escape(ui.id)}?from='+$clFrom+'&to='+$clTo+'&status='+$clStatus)`
    : `@get('/ui/${escape(ui.id)}?from='+$clFrom+'&to='+$clTo+'&status='+$clStatus+'&closer='+encodeURIComponent($clCloser))`;
  const signals = `{clFrom:${escape(jsStr(params.from || ""))},clTo:${escape(jsStr(params.to || ""))},clStatus:${escape(jsStr(stSelect))}${bloqueado ? "" : `,clCloser:${escape(jsStr(params.closer || ""))}`}}`;

  const closerUnico = new Set(rows.map((r) => r.closer).filter(Boolean));
  const chip = closerUnico.size === 1 ? `<span class="badge badge-brand">${escape([...closerUnico][0])}</span>` : "";

  const controls = `<div class="flex flex-wrap items-center gap-3" data-signals="${signals}">
    ${chip}
    ${bloqueado ? "" : `<input type="text" placeholder="closer…" data-bind="clCloser" data-on:change="${reget}" data-indicator:loadingcl class="input w-40" />`}
    ${selectCtl("clStatus", stSelect, STATUS_OPTS, reget, "loadingcl")}
    <input type="date" data-bind="clFrom" data-on:change="${reget}" data-indicator:loadingcl class="input w-auto" />
    <span style="color:var(--text-3)">~</span>
    <input type="date" data-bind="clTo" data-on:change="${reget}" data-indicator:loadingcl class="input w-auto" />
    <span class="text-xs ml-auto" style="color:var(--text-3)">${rows.length} llamadas${rows.length >= 200 ? " (últimas 200)" : ""}</span>
  </div>`;

  const celTranscript = (r) => {
    if (r.tr_usable)
      return baseT
        ? `<a href="${escape(baseT)}/${escape(r.id)}" title="Descargar transcript (.txt)" style="color:var(--text-brand)">${ICON_DL}</a>`
        : `<span title="Transcript disponible (descarga solo en la versión publicada)" style="color:var(--pos-text)">✓</span>`;
    if (Number(r.tr_chars) > 0)
      return `<span class="text-xs" title="Transcript de ${r.tr_chars} chars — demasiado corto para ser usable" style="color:var(--text-3)">~</span>`;
    return `<span style="color:var(--text-3)">—</span>`;
  };
  // fuente 'meeting_reports' = el escaparate pre-cerebro → se muestra «plataforma»
  const celReporte = (r) => {
    if (!r.reporte) return `<span style="color:var(--text-3)">—</span>`;
    const f = r.reporte === "cerebro" ? "cerebro" : "plataforma";
    return `<a href="${escape(baseR)}?meeting=${escape(r.id8)}" target="_blank" title="Abrir el reporte (${escape(f)})" class="inline-flex items-center gap-1" style="color:var(--text-brand)">${ICON_DOC}<span class="badge ${f === "cerebro" ? "badge-brand" : "badge-neutral"} text-[10px]">${escape(f)}</span></a>`;
  };

  const tr = rows
    .map(
      (r) => `<tr>
    <td class="align-top"><span class="tabular-nums text-xs">${escape(r.fecha || "")}</span></td>
    <td class="align-top"><span class="tabular-nums text-xs">${escape(r.hora || "")}</span></td>
    <td class="align-top"><span class="font-medium">${escape(r.lead || "—")}</span></td>
    <td class="align-top"><span class="text-xs">${escape(String(r.programa || "—").slice(0, 40))}</span></td>
    <td class="align-top"><span class="text-xs">${escape(r.proyecto || "—")}</span></td>
    ${closerUnico.size === 1 ? "" : `<td class="align-top"><span class="text-xs">${escape(r.closer || "—")}</span></td>`}
    <td class="align-top"><span class="badge badge-neutral">${escape(ES_STATUS[r.status] || r.status || "—")}</span></td>
    <td class="align-top text-center">${celTranscript(r)}</td>
    <td class="align-top">${celReporte(r)}</td>
  </tr>`
    )
    .join("");
  const th = ["Fecha", "Hora", "Lead", "Programa", "Proyecto", ...(closerUnico.size === 1 ? [] : ["Closer"]), "Estado", "Transcript", "Reporte"]
    .map((h) => `<th>${escape(h)}</th>`)
    .join("");
  const tabla = rows.length
    ? `<div class="table-wrap mt-6"><div class="table-scroll"><table class="tbl"><thead><tr>${th}</tr></thead><tbody>${tr}</tbody></table></div></div>`
    : `<p class="text-sm italic px-1 py-4" style="color:var(--text-3)">Sin llamadas.</p>`;

  return `<section id="pane" class="flex-1 relative overflow-auto p-6">
    <style>#cl-loading{opacity:0;transition:opacity .2s ease}#cl-loading.on{opacity:1}</style>
    <div id="cl-loading" data-class:on="$loadingcl" class="pointer-events-none absolute inset-0 z-10 flex items-start justify-center pt-16 bg-white/50">
      <div class="w-7 h-7 rounded-full border-2 border-slate-300 border-t-indigo-600 animate-spin"></div>
    </div>
    <div class="max-w-5xl mx-auto">
      ${controls}
      ${tabla}
    </div>
  </section>`;
}

module.exports = {
  id: "closer-llamadas",
  manifest: { consumes: "rows", overridable: ["closer", "status", "from", "to"] },
  render: renderCloserLlamadas,
};

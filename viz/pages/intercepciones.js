// intercepciones — la mirilla sobre los procesos de Marketico interceptados.
// Consume el objeto de bash/intercepciones/resumen.sh: KPIs del webhook de
// agendamiento (auto-reporte de processBooking), últimas corridas de la
// reconciliación de agenda DB↔GHL y su drift vigente.

const { fetchSource } = require("../lib/datasources");
const { escape, section } = require("../lib/kit");
const { cards } = require("../blocks/kpi-cards");

const TIPO_DRIFT = {
  falta_en_db: { label: "Falta en DB", tone: "neg" },
  sobra_en_db: { label: "Sobra en DB", tone: "cau" },
  horas_difieren: { label: "Horas difieren", tone: "cau" },
};

const fmtTs = (iso) => (iso ? String(iso).replace("T", " ").slice(0, 16) : "—");

function badge(tone, txt) {
  return `<span class="badge badge-${tone}">${escape(txt)}</span>`;
}

function tablaLog(fallos) {
  if (!fallos.length) return `<p class="text-sm" style="color:var(--text-3)">Sin fallos recientes.</p>`;
  const filas = fallos.map((f) => {
    const err = (() => { try { return JSON.parse(f.error || "null"); } catch { return null; } })();
    return `<tr>
      <td>${escape(fmtTs(f.recibido_at))}</td>
      <td>${escape(f.contacto || "—")}</td>
      <td class="font-mono text-xs">${escape(f.appointment_id || "—")}</td>
      <td>${badge("neg", err?.paso || "error")} ${escape(err?.mensaje || "")}</td>
    </tr>`;
  }).join("");
  return `<div class="table-wrap"><table class="tbl dense">
    <thead><tr><th>Recibido</th><th>Contacto</th><th>Appointment</th><th>Error</th></tr></thead>
    <tbody>${filas}</tbody></table></div>`;
}

function tablaDrift(drift) {
  if (!drift.length) return `<p class="text-sm" style="color:var(--text-3)">La agenda cuadra: sin discrepancias en la última corrida.</p>`;
  const filas = drift.map((d) => {
    const det = (() => { try { return JSON.parse(d.detalle || "{}"); } catch { return {}; } })();
    const t = TIPO_DRIFT[d.tipo] || { label: d.tipo, tone: "cau" };
    return `<tr>
      <td>${escape(d.proyecto || "—")}</td>
      <td>${badge(t.tone, t.label)}</td>
      <td>${escape(det.titulo || "—")}</td>
      <td>${escape(det.ghl_inicio_bogota || det.db_inicio_bogota || "—")}</td>
      <td class="font-mono text-xs">${escape(d.appointment_id || "—")}</td>
    </tr>`;
  }).join("");
  return `<div class="table-wrap"><table class="tbl dense">
    <thead><tr><th>Proyecto</th><th>Tipo</th><th>Llamada</th><th>Inicio (Bogotá)</th><th>Appointment</th></tr></thead>
    <tbody>${filas}</tbody></table></div>`;
}

function tablaCorridas(corridas) {
  if (!corridas.length) return `<p class="text-sm" style="color:var(--text-3)">El cron aún no corre.</p>`;
  const filas = corridas.map((c) => `<tr>
    <td>${escape(c.proyecto || "—")}</td>
    <td>${escape(fmtTs(c.corrida_at))}</td>
    <td class="text-right">${c.ghl_total ?? "—"}</td>
    <td class="text-right">${c.db_total ?? "—"}</td>
    <td class="text-right">${c.coinciden ?? "—"}</td>
    <td class="text-right">${c.estado === "error" ? badge("neg", "error") : (c.discrepancias || 0)}</td>
  </tr>`).join("");
  return `<div class="table-wrap"><table class="tbl dense">
    <thead><tr><th>Proyecto</th><th>Corrida</th><th>GHL</th><th>DB</th><th>Coinciden</th><th>Drift</th></tr></thead>
    <tbody>${filas}</tbody></table></div>`;
}

function renderIntercepciones(ui) {
  let data;
  try {
    const { rows } = fetchSource(ui.source, ui.params || {});
    data = rows[0] || {};
  } catch (e) {
    return `<section id="pane" class="flex-1 p-6"><div class="alert alert-neg">No se pudo leer el interceptor: ${escape(e.message)}</div></section>`;
  }
  const wh = data.webhook || { h24: {}, d7: {}, ultimos_fallos: [] };
  const corridas = data.corridas || [];
  const drift = data.drift || [];

  // Freshness: si la última corrida tiene más de 2h, el cron está caído.
  // corrida_at ya trae Z literal (strftime %Y-%m-%dT%H:%M:%fZ del schema) —
  // parsear directo, sin concatenar otra Z (eso daba "...ZZ" → Date.parse
  // NaN → la alerta nunca podía renderizar). Defensivo: parse no-finito = sin
  // alerta, nunca NaN en el texto.
  const masReciente = corridas.map((c) => c.corrida_at).sort().pop();
  const parsedReciente = masReciente ? Date.parse(masReciente) : NaN;
  const horasSin = Number.isFinite(parsedReciente) ? (Date.now() - parsedReciente) / 36e5 : null;
  const alerta = horasSin != null && horasSin > 2
    ? `<div class="alert alert-neg mb-4">La reconciliación no corre hace ${horasSin.toFixed(1)}h — revisar el cron «intercepciones-cron».</div>`
    : "";

  const kpis = cards([
    { key: "h24", label: "Webhooks 24h", fmt: "int", tone: "brand" },
    { key: "h24_fallos", label: "Fallos 24h", fmt: "int", tone: "neg" },
    { key: "d7", label: "Webhooks 7d", fmt: "int", tone: "brand" },
    { key: "d7_fallos", label: "Fallos 7d", fmt: "int", tone: "neg" },
    { key: "drift_n", label: "Drift vigente", fmt: "int", tone: "cau" },
  ], {
    h24: wh.h24.recibidos ?? 0, h24_fallos: wh.h24.fallos ?? 0,
    d7: wh.d7.recibidos ?? 0, d7_fallos: wh.d7.fallos ?? 0,
    drift_n: drift.length,
  });

  const head = `<div class="flex items-baseline justify-between mb-4">
    <h1 class="text-xl font-bold" style="color:var(--text-1)">Intercepciones</h1>
    <span class="text-xs" style="color:var(--text-3)">agendamiento GHL→Marketico · generado ${escape(fmtTs(data.generado_at))}</span>
  </div>`;

  return `<section id="pane" class="flex-1 p-6 overflow-auto" style="background:var(--surface-2)">
    ${head}${alerta}${kpis}
    <div class="grid gap-6 mt-6" style="grid-template-columns:1fr">
      ${section("Drift de agenda (última corrida)", drift.length, tablaDrift(drift))}
      ${section("Corridas de reconciliación", corridas.length, tablaCorridas(corridas))}
      ${section("Últimos fallos del webhook", (wh.ultimos_fallos || []).length, tablaLog(wh.ultimos_fallos || []))}
    </div>
  </section>`;
}

module.exports = {
  id: "intercepciones",
  manifest: { consumes: "object", overridable: [] },
  render: renderIntercepciones,
};

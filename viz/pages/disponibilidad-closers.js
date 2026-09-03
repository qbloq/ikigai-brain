// disponibilidad-closers page — la matriz semanal closers × días desde el
// único objeto que emite bash/setters/disponibilidad.sh. La verdad es GHL:
// los huecos libres son los que su free-slots calcula por closer sobre el
// calendario de venta; aquí no se inventa horario laboral.
//
// Celda = densidad («N libres · M citas» por estado), y el detalle de horas
// se abre al click en un slide-over (misma decisión que agenda-setter: la
// matriz con horas en las celdas se vuelve ilegible con 5 closers × 7 días).
// Estados: normal (hay huecos) · lleno (0 libres con citas) · sin_horario
// (0 y 0 en día futuro: el closer no configuró su disponibilidad en GHL) ·
// pasado (GHL no da huecos hacia atrás — solo las citas que hubo, en gris).
// Autosuficiente: sin /c/ (el publicador v1 no lo monta) — el detalle viaja
// en el HTML y se muestra con una señal (data-show), patrón agenda-setter.
const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");

const DIAS = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"];
const TONE = { pos: "var(--pos-text)", neg: "var(--neg-text)", cau: "var(--cau-text)", brand: "var(--text-brand)", muted: "var(--text-3)" };
const ES_GHL = { confirmed: "Confirmada", new: "Nueva", showed: "Asistió", noshow: "No asistió", invalid: "Inválida" };

function diaLabel(iso) {
  const [y, m, d] = iso.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  return `${DIAS[(dt.getUTCDay() + 6) % 7]} ${d}`;
}
function sumarDias(iso, n) {
  const [y, m, d] = iso.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d + n));
  return dt.toISOString().slice(0, 10);
}
const nCitas = (n) => `${n} ${n === 1 ? "cita" : "citas"}`;
const nLibres = (n) => `${n} ${n === 1 ? "libre" : "libres"}`;

// El contenido de una celda, por estado. Sin hex: solo tokens.
function celdaHtml(cel) {
  const c = cel.citas.length;
  if (cel.estado === "pasado") {
    return c ? `<span style="color:${TONE.muted}">${nCitas(c)}</span>` : `<span style="color:${TONE.muted}">—</span>`;
  }
  if (cel.estado === "sin_horario") {
    return `<span class="badge" style="color:${TONE.muted}" title="0 huecos y 0 citas: el closer no tiene disponibilidad configurada en GHL para este día">sin horario</span>`;
  }
  if (cel.estado === "lleno") {
    return `<span style="color:${TONE.cau}" title="sin huecos libres — la agenda del día está ocupada">lleno · ${nCitas(c)}</span>`;
  }
  return `<span style="color:${TONE.pos};font-weight:600">${nLibres(cel.libres.length)}</span>${c ? `<span style="color:${TONE.muted}"> · ${nCitas(c)}</span>` : ""}`;
}

function panel(closers, sig) {
  const hojas = [];
  for (const cl of closers) {
    for (const [dia, cel] of Object.entries(cl.dias)) {
      if (!cel.libres.length && !cel.citas.length) continue;
      const key = `${cl.ghl_user_id}|${dia}`;
      hojas.push(`<div data-show="$${sig} == '${escape(key)}'" style="display:none">
        <div class="flex items-start justify-between gap-3 mb-3">
          <div><h3 class="text-base font-semibold">${escape(cl.nombre || "")}</h3>
            <p class="text-sm" style="color:${TONE.muted}">${escape(diaLabel(dia))}</p></div>
          <button class="btn" data-on:click="$${sig} = ''">✕</button>
        </div>
        ${cel.libres.length ? `<p class="text-xs uppercase tracking-wide mb-1" style="color:${TONE.muted}">Huecos libres</p>
          <div class="flex flex-wrap gap-1.5 mb-4">${cel.libres.map((h) => `<span class="badge" style="color:${TONE.pos}">${escape(h)}</span>`).join("")}</div>` : ""}
        ${cel.citas.length ? `<p class="text-xs uppercase tracking-wide mb-1" style="color:${TONE.muted}">Citas</p>
          <ul class="space-y-1.5">${cel.citas.map((c) => `<li class="text-sm">${escape(c.hora)}${c.fin ? `–${escape(c.fin)}` : ""} · ${escape(c.lead || "(sin nombre)")}${c.estado_ghl && ES_GHL[c.estado_ghl] ? ` <span class="badge" style="color:${TONE.brand}">${escape(ES_GHL[c.estado_ghl])}</span>` : ""}</li>`).join("")}</ul>` : ""}
      </div>`);
    }
  }
  return `<aside id="dc-panel" data-class:is-open="$${sig} != ''">${hojas.join("")}</aside>`;
}

function renderObjeto(ui, d) {
  const sig = "dcSel";
  const s = d.semana;
  const base = `/u/${escape(ui.id)}?fecha=`;
  const reget = `@get('/ui/${escape(ui.id)}?carga=1&fecha='+$dcFecha)`;
  const nav = `<div class="flex flex-wrap items-center gap-3" data-signals="{dcFecha:'${escape(s.fecha)}',loadingdc:false}">
    <a class="btn" href="${base}${sumarDias(s.fecha, -7)}">←</a>
    <input type="date" data-bind="dcFecha" data-on:change="${reget}" data-indicator:loadingdc class="input w-auto" />
    <a class="btn" href="${base}${sumarDias(s.fecha, 7)}">→</a>
    <span class="text-sm" style="color:${TONE.muted}">${escape(d.proyecto || "")} · ${escape(diaLabel(s.desde))} → ${escape(diaLabel(s.hasta))}${(d.calendario || {}).nombre ? ` · ${escape(d.calendario.nombre)}` : ""}</span>
  </div>`;

  // id="pane" NO es decorativo: el SSE parchea por id.
  return `<section id="pane" class="flex-1 relative overflow-auto p-6" data-signals="{${sig}:''}">
    <style>#dc-loading{opacity:0;transition:opacity .2s ease}#dc-loading.on{opacity:1}</style>
    <div id="dc-loading" data-class:on="$loadingdc" class="pointer-events-none absolute inset-0 z-10 flex items-start justify-center pt-16 bg-white/50">
      <div class="w-7 h-7 rounded-full border-2 border-slate-300 border-t-indigo-600 animate-spin"></div>
    </div>
    <div class="max-w-6xl mx-auto">
      ${nav}
      ${bloque(d, sig)}
    </div>
  </section>`;
}

// El BLOQUE compartido — avisos + matriz + huérfanas + slide-over — sin nav ni
// pane: lo usan esta página y agenda-setter (sección «Disponibilidad de la
// semana», fragmento `?disp=1`). Lleva su propio <style> del panel para que el
// fragmento funcione morfado dentro de cualquier pane.
function bloque(d, sig) {
  const s = d.semana;
  const hoy = s.ahora.slice(0, 10);
  // El domingo sin nada en NINGÚN closer (ni huecos ni citas) no gana columna
  // (pedido 2026-09-03); con cualquier contenido, vuelve.
  let dias = s.dias;
  const domingo = dias[6];
  const domingoVacio = domingo && (d.closers || []).every((cl) => {
    const c = cl.dias[domingo] || {};
    return !(c.libres || []).length && !(c.citas || []).length;
  });
  if (dias.length === 7 && domingoVacio) dias = dias.slice(0, 6);
  const avisos = [];
  if (d.fuente.ghl !== "ok") avisos.push(`<div class="alert alert-neg mt-3">GHL no respondió — la disponibilidad no se puede calcular desde la base (GHL manda). ${escape(d.fuente.detalle || "")}</div>`);
  if (d.fuente.db === "error") avisos.push(`<div class="alert alert-cau mt-3">La base no respondió: los closers salen sin nombre resuelto.</div>`);

  const filas = (d.closers || []).map((cl) => {
    const celdas = dias.map((dia) => {
      const cel = cl.dias[dia] || { libres: [], citas: [], estado: "sin_horario" };
      const key = `${cl.ghl_user_id}|${dia}`;
      const clickable = cel.libres.length || cel.citas.length;
      const click = clickable ? ` class="cursor-pointer" data-on:click="$${sig} = $${sig}=='${escape(key)}' ? '' : '${escape(key)}'"` : "";
      const hoyMark = dia === hoy ? ` style="background:var(--surface-2)"` : "";
      return `<td data-celda="${escape(key)}"${click}${hoyMark}>${celdaHtml(cel)}</td>`;
    }).join("");
    return `<tr><td class="font-medium whitespace-nowrap">${escape(cl.nombre || "")}</td>${celdas}
      <td style="color:${TONE.muted}" class="whitespace-nowrap">${cl.total_libres} · ${cl.total_citas}</td></tr>`;
  }).join("");

  const matriz = `<div class="card overflow-x-auto mt-4"><table class="tbl w-full"><thead><tr>
      <th>Closer</th>${dias.map((dia) => `<th${dia === hoy ? ` style="color:${TONE.brand}"` : ""}>${escape(diaLabel(dia))}</th>`).join("")}<th title="huecos libres · citas, semana completa">Σ libres · citas</th>
    </tr></thead><tbody>${filas || `<tr><td colspan="${dias.length + 2}" style="color:${TONE.muted}">Sin closers que listar.</td></tr>`}</tbody></table></div>`;

  const huerfanas = (d.sin_closer || []).length ? `<div class="alert alert-cau mt-4"><b>Citas del calendario sin closer resoluble</b> (asignadas a alguien que no es miembro, o a nadie):
      <ul class="mt-1 space-y-0.5">${d.sin_closer.map((c) => `<li class="text-sm">${escape(c.fecha)} ${escape(c.hora)} · ${escape(c.lead || "(sin nombre)")}</li>`).join("")}</ul></div>` : "";

  return `<style>
      #dc-panel{position:fixed;top:0;right:0;bottom:0;width:min(26rem,100vw);z-index:40;
        background:var(--surface-1);border-left:1px solid var(--border-1);
        box-shadow:-8px 0 24px rgb(0 0 0 / .08);padding:1rem 1.25rem;overflow-y:auto;
        transform:translateX(105%);transition:transform .3s ease-in-out}
      #dc-panel.is-open{transform:translateX(0)}
    </style>
    ${avisos.join("")}
    ${matriz}
    ${huerfanas}
    ${panel(d.closers || [], sig)}`;
}

// El cascarón instantáneo del primer load (patrón agenda-setter `?carga=1`):
// la fuente consulta GHL en vivo y tarda varios segundos.
function cascaron(ui, p) {
  const qs = ["carga=1"];
  for (const k of ["fecha", "project"]) {
    if (p[k]) qs.push(`${k}=${encodeURIComponent(String(p[k]))}`);
  }
  return `<section id="pane" class="flex-1 relative overflow-auto p-6" data-init="@get('/ui/${escape(ui.id)}?${escape(qs.join("&"))}')">
    <style>@keyframes dc-barra{0%{transform:translateX(-100%)}100%{transform:translateX(250%)}}</style>
    <div class="max-w-6xl mx-auto">
      <div class="flex flex-col items-center justify-center pt-24 gap-4">
        <div class="w-64 h-1.5 rounded-full overflow-hidden" style="background:var(--surface-3)">
          <div class="h-full w-2/5 rounded-full" style="background:var(--brand-solid);animation:dc-barra 1.2s ease-in-out infinite"></div>
        </div>
        <p class="text-sm" style="color:var(--text-3)">Cargando la disponibilidad — GHL en vivo, tarda unos segundos…</p>
      </div>
    </div>
  </section>`;
}

function render(ui) {
  const p = Object.assign({}, ui.params || {});
  if (!p.carga) return cascaron(ui, p);
  const params = { project: p.project, fecha: p.fecha, calendar: p.calendar };
  let d, err;
  try {
    d = fetchSource(ui.source || "disponibilidad_closers", params).rows[0];
  } catch (e) {
    err = e.message;
  }
  if (err || !d) {
    return `<section id="pane" class="flex-1 p-6 overflow-auto"><div class="alert alert-neg">No se pudo cargar la disponibilidad: ${escape(err || "sin datos")}</div></section>`;
  }
  return renderObjeto(ui, d);
}

module.exports = {
  id: "disponibilidad-closers",
  manifest: { consumes: "object", overridable: ["fecha", "project", "carga"] },
  render,
  renderObjeto,
  bloque,
};

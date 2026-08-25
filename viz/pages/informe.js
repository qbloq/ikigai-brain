// informe page — un INFORME narrativo publicable, por secciones, con números
// vivos opcionales. Nació para el informe de la semana inaugural del Cerebro
// (2026-08-16 → 24, rol Ejecutivo), pero es genérico: el contenido entero es
// copy curado en `params` del spec (portada, secciones, cierre) y se cambia
// re-publicando, nunca en código — misma regla que `plan-reactivacion` y
// `ventas-precio`.
//
// Forma del spec:
//   params.portada   {subtitulo, periodo, audiencia, estado, intro (prosa)}
//   params.secciones [{id, n, titulo, kicker, resumen (prosa), hallazgos[],
//                      cifras[{label, valor, nota, tono}], enlaces[{slug|url,
//                      texto, nota}], vivo {source, args, kpis[]}, cautelas[],
//                      siguiente[]}]
//   params.cierre    {titulo, prosa, lista[]}
//   params.base_publicada  base de los enlaces por slug (el publicador)
//
// Los NÚMEROS VIVOS (`vivo`) salen de fuentes whitelisted (`fetchSource`), nunca
// de SQL: `kpis[{label, agg:'count'|'sum'|'path', campo|path, formato, nota}]`.
// Sobre filas: count/sum; sobre objetos: path punteado. Si la fuente falla, la
// sección lo declara y el resto del informe se sigue leyendo — un informe no
// se cae porque un número no cargó.

const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");

const TONE = { pos: "var(--pos-text)", neg: "var(--neg-text)", cau: "var(--cau-text)", brand: "var(--text-brand)", muted: "var(--text-3)", base: "var(--text-1)" };
const n0 = (v) => (v == null || v === "" || Number.isNaN(Number(v)) ? 0 : Number(v));
const num = (v, d = 0) => (v == null || v === "" ? "—" : n0(v).toLocaleString("es-CO", { maximumFractionDigits: d, minimumFractionDigits: d }));
const usd = (v) => (v == null || v === "" ? "—" : "$" + Math.round(n0(v)).toLocaleString("es-CO"));
const pct = (v, d = 1) => (v == null || v === "" ? "—" : num(v, d) + " %");
const md = (t) =>
  escape(String(t || ""))
    .replace(/\*\*(.+?)\*\*/g, "<b>$1</b>")
    .replace(/\*(.+?)\*/g, "<i>$1</i>")
    .replace(/`(.+?)`/g, '<code class="text-[0.9em]">$1</code>');

function formato(v, f) {
  if (f === "usd") return usd(v);
  if (f === "pct") return pct(v);
  if (f === "num1") return num(v, 1);
  if (f === "num2") return num(v, 2);
  return num(v);
}
const getPath = (o, p) => String(p || "").split(".").reduce((a, k) => (a == null ? a : a[k]), o);

function prosa(txt) {
  if (!txt) return "";
  return String(txt).split(/\n\s*\n/).map((p) => `<p class="text-sm leading-relaxed mt-2" style="color:var(--text-2)">${md(p.trim())}</p>`).join("");
}
function lista(items, ordered = false) {
  if (!items || !items.length) return "";
  const tag = ordered ? "ol" : "ul";
  return `<${tag} class="mt-2 pl-5 ${ordered ? "list-decimal" : "list-disc"}">${items.map((t) => `<li class="text-sm leading-relaxed mt-1.5" style="color:var(--text-2)">${md(t)}</li>`).join("")}</${tag}>`;
}
function kpi(c) {
  const tone = TONE[c.tono] || TONE.brand;
  return `<div class="card card-pad kpi"${c.nota ? ` title="${escape(c.nota)}"` : ""}>
    <span class="kpi-label">${escape(c.label || "")}</span>
    <span class="kpi-value tabular-nums" style="color:${tone}">${md(String(c.valor == null ? "—" : c.valor))}</span>
    ${c.nota ? `<span class="kpi-foot">${md(c.nota)}</span>` : ""}
  </div>`;
}
function cifras(cs) {
  if (!cs || !cs.length) return "";
  return `<div class="grid gap-3 mt-4" style="grid-template-columns:repeat(auto-fit,minmax(10rem,1fr))">${cs.map(kpi).join("")}</div>`;
}
function enlaces(es, base) {
  if (!es || !es.length) return "";
  return `<div class="flex flex-wrap gap-2 mt-4">${es
    .map((e) => {
      const href = e.url || (e.slug ? `${String(base || "").replace(/\/$/, "")}/${e.slug}` : "#");
      return `<a href="${escape(href)}" target="_blank" rel="noopener" class="btn btn-secondary btn-sm" title="${escape(e.nota || href)}">${escape(e.texto || e.slug || href)} ↗</a>`;
    })
    .join("")}</div>`;
}

// Números vivos: cada KPI se calcula sobre la respuesta de UNA fuente
// whitelisted. Falla declarada, no silenciosa. El bloque NO se calcula al
// renderizar la página: sale como marcador (`placeholder`) que al entrar al
// DOM pide su fragmento (`?vivo=<id de sección>`) por la conexión en vivo, así
// el texto del informe aparece al instante y los bloques llegan cada uno
// cuando su fuente responde — en paralelo, no en serie. Cada fragmento que
// llega suma 1 a `$listos`, la señal que mueve la barra de progreso.
const vivoId = (s) => `vivo-${String(s.id || `s${s.n || ""}`)}`;

function vivoPlaceholder(s, uiId) {
  const v = s.vivo;
  if (!v || !v.source) return "";
  const sid = String(s.id || `s${s.n || ""}`);
  return `<div id="${vivoId(s)}" class="mt-4" data-init="@get('/ui/${escape(uiId)}?vivo=${encodeURIComponent(sid)}')">
    <div class="text-[11px] uppercase font-semibold" style="color:var(--text-3)">${escape(v.titulo || "Ahora mismo")} <span class="font-normal normal-case">· cargando…</span></div>
    <div class="grid gap-3 mt-4" style="grid-template-columns:repeat(auto-fit,minmax(10rem,1fr))">${(v.kpis || [])
      .map((k) => `<div class="card card-pad kpi" aria-busy="true"><span class="kpi-label">${escape(k.label || "")}</span><span class="kpi-value" style="color:var(--text-3)">…</span></div>`)
      .join("")}</div>
  </div>`;
}

function vivoCargado(s) {
  const v = s.vivo;
  const sube = `data-init="$listos = $listos + 1"`;
  if (!v || !v.source) return `<div id="${vivoId(s)}" ${sube}></div>`;
  let data, err = "";
  try {
    data = fetchSource(v.source, v.args || {});
  } catch (e) {
    err = e.message;
  }
  if (err) return `<div id="${vivoId(s)}" class="mt-4" ${sube}><div class="alert alert-cau text-xs">Los números vivos de esta sección no cargaron ahora mismo (${escape(err.slice(0, 160))}). El texto sigue siendo válido.</div></div>`;
  const rows = Array.isArray(data && data.rows) ? data.rows : [];
  // Toda fuente llega como {rows[]}: una fuente «object» es una lista de UNA fila.
  const obj = rows.length === 1 && rows[0] && typeof rows[0] === "object" && !Array.isArray(rows[0]) ? rows[0] : {};
  const cs = (v.kpis || []).map((k) => {
    let val = null;
    if (k.agg === "count") val = k.where ? rows.filter((r) => String(r[k.where.campo]) === String(k.where.valor)).length : rows.length;
    else if (k.agg === "sum") val = rows.reduce((a, r) => a + n0(r[k.campo]), 0);
    else if (k.agg === "path") val = getPath(obj, k.path);
    return { label: k.label, valor: formato(val, k.formato), nota: k.nota, tono: k.tono || "base" };
  });
  return `<div id="${vivoId(s)}" class="mt-4" ${sube}><div class="text-[11px] uppercase font-semibold" style="color:var(--text-3)">${escape(v.titulo || "Ahora mismo")} <span class="font-normal normal-case">· se recalcula al abrir</span></div>${cifras(cs)}</div>`;
}

function seccion(s, base, uiId) {
  const id = escape(s.id || `s${s.n || ""}`);
  const estado = s.estado ? `<span class="badge ${escape(s.estado_badge || "badge-neutral")}">${escape(s.estado)}</span>` : "";
  return `<article id="${id}" class="card card-pad mt-6" style="scroll-margin-top:1rem">
    <header class="flex items-start gap-3 flex-wrap">
      ${s.n != null ? `<span class="badge badge-brand shrink-0 tabular-nums">${escape(String(s.n))}</span>` : ""}
      <div class="min-w-0 flex-1">
        <h2 class="text-lg font-bold leading-tight" style="color:var(--text-1)">${escape(s.titulo || "")}</h2>
        ${s.kicker ? `<p class="text-sm mt-1" style="color:var(--text-3)">${md(s.kicker)}</p>` : ""}
      </div>
      ${estado}
    </header>
    ${prosa(s.resumen)}
    ${cifras(s.cifras)}
    ${s.hallazgos && s.hallazgos.length ? `<div class="mt-4"><div class="text-[11px] uppercase font-semibold" style="color:var(--text-3)">${escape(s.hallazgos_titulo || "Qué se hizo y qué se encontró")}</div>${lista(s.hallazgos)}</div>` : ""}
    ${vivoPlaceholder(s, uiId)}
    ${s.cautelas && s.cautelas.length ? `<div class="alert alert-cau text-sm mt-4"><b>Con cuidado:</b>${lista(s.cautelas)}</div>` : ""}
    ${s.siguiente && s.siguiente.length ? `<div class="mt-4"><div class="text-[11px] uppercase font-semibold" style="color:var(--text-3)">${escape(s.siguiente_titulo || "Lo que sigue")}</div>${lista(s.siguiente)}</div>` : ""}
    ${enlaces(s.enlaces, base)}
  </article>`;
}

function render(ui) {
  const p = ui.params || {};
  const portada = p.portada || {};
  const secs = Array.isArray(p.secciones) ? p.secciones : [];
  const cierre = p.cierre || {};
  const base = p.base_publicada || "";

  // Modo fragmento: `?vivo=<id>` → solo el bloque vivo de esa sección, calculado.
  if (p.vivo) {
    const s = secs.find((x) => String(x.id || `s${x.n || ""}`) === String(p.vivo));
    return { fragment: s ? vivoCargado(s) : `<div id="vivo-${escape(String(p.vivo))}" data-init="$listos = $listos + 1"></div>` };
  }
  const nVivos = secs.filter((s) => s.vivo && s.vivo.source).length;
  const barra = nVivos
    ? `<div data-show="$listos < ${nVivos}" class="sticky top-0 z-10 -mx-6 -mt-6 mb-4 px-6 py-2" style="background:var(--surface-1);border-bottom:1px solid var(--border-1)">
        <div class="flex items-center justify-between text-xs" style="color:var(--text-3)">
          <span>Cargando cifras vivas · <span data-text="$listos"></span> de ${nVivos}</span>
          <span>el texto ya está completo</span>
        </div>
        <div class="mt-1.5 h-1.5 rounded-full overflow-hidden" style="background:var(--surface-3)">
          <div class="h-full rounded-full" style="background:var(--brand-solid);width:0%;transition:width .4s ease" data-style:width="Math.round($listos / ${nVivos} * 100) + '%'"></div>
        </div>
      </div>`
    : "";

  const indice = secs.length
    ? `<nav class="card card-pad mt-5"><div class="text-[11px] uppercase font-semibold" style="color:var(--text-3)">Contenido</div>
      <ol class="mt-3 grid gap-2" style="grid-template-columns:repeat(auto-fit,minmax(16rem,1fr))">${secs
        .map((s) => `<li><a href="#${escape(s.id || `s${s.n || ""}`)}" class="flex items-start gap-3 rounded-lg p-3 h-full transition-colors" style="border:1px solid var(--border-1);background:var(--surface-2);color:var(--text-1)" onmouseover="this.style.borderColor='var(--brand-solid)'" onmouseout="this.style.borderColor='var(--border-1)'">
          <span class="badge badge-brand shrink-0 tabular-nums">${escape(String(s.n != null ? s.n : "·"))}</span>
          <span class="text-sm font-medium leading-snug">${escape(s.titulo || "")}</span>
        </a></li>`)
        .join("")}</ol></nav>`
    : "";

  return `<section id="pane" class="flex-1 p-6 overflow-auto" data-signals="{listos:0}">
  ${barra}
  <div class="max-w-4xl mx-auto">
    <div class="flex items-baseline gap-3 flex-wrap">
      <h1 class="text-2xl font-bold" style="color:var(--text-1)">${escape(ui.name)}</h1>
      ${portada.periodo ? `<span class="badge badge-neutral">${escape(portada.periodo)}</span>` : ""}
      ${portada.audiencia ? `<span class="badge badge-neutral">${escape(portada.audiencia)}</span>` : ""}
      ${portada.estado ? `<span class="badge badge-cau">${escape(portada.estado)}</span>` : ""}
      <a href="/u/${escape(ui.id)}" target="_blank" class="ml-auto text-xs" style="color:var(--text-brand)">abrir solo ↗</a>
    </div>
    ${portada.subtitulo ? `<p class="mt-1 text-sm" style="color:var(--text-3)">${md(portada.subtitulo)}</p>` : ""}
    ${portada.intro ? `<div class="card card-pad mt-5" style="border-left:3px solid var(--brand-solid)">${prosa(portada.intro)}</div>` : ""}
    ${cifras(portada.cifras)}
    ${indice}
    ${secs.map((s) => seccion(s, base, ui.id)).join("")}
    ${cierre.titulo || cierre.prosa || (cierre.lista && cierre.lista.length) ? `<article class="card card-pad mt-8" style="border-left:3px solid var(--brand-solid)">
      ${cierre.titulo ? `<h2 class="text-lg font-bold" style="color:var(--text-1)">${escape(cierre.titulo)}</h2>` : ""}
      ${prosa(cierre.prosa)}
      ${lista(cierre.lista, true)}
    </article>` : ""}
    <p class="mt-10 text-xs" style="color:var(--text-3)">${md(p.pie || "Informe redactado por el Cerebro de Ikigai. Las cifras marcadas «ahora mismo» se recalculan al abrir la página; el resto son las del cierre del período.")}</p>
  </div>
</section>`;
}

module.exports = {
  id: "informe",
  // `vivo` es el único param que el navegador puede pedir: el id de la sección
  // cuyo bloque vivo quiere (modo fragmento). Todo lo demás viene del spec.
  manifest: { overridable: ["vivo"] },
  render,
};

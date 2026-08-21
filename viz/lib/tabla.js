// tabla.js — tabla paginada CLIENT-SIDE, reutilizable entre páginas.
// Paginación de PRESENTACIÓN pura: todas las filas viajan en el HTML (los
// datasets ya vienen acotados por ventana/limit del script) y Datastar solo
// alterna data-show por página — cero re-fetch, funciona igual en el
// publicador. Cada tabla declara su señal propia (`sig`) y siembra su
// data-signals en el wrapper, así varias conviven en una página.
//
// No es un componente enrutado (no vive en blocks/): es un helper de render.
// Si un tercer consumidor lo pide a nivel de kit.js, elevarlo es decisión de
// gobernanza (el kernel crece por acuerdo, no por conveniencia).
const { escape } = require("./kit");

function tablaPaginada(headers, rows, { empty = "Sin datos.", sig = "pg", porPagina = 10, rowAttrs = [] } = {}) {
  if (!rows.length) return `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)">${escape(empty)}</p>`;
  const paginas = Math.ceil(rows.length / porPagina);
  const th = headers.map((h) => `<th>${escape(h)}</th>`).join("");
  const tr = rows
    .map((cells, i) => {
      const pg = Math.floor(i / porPagina);
      // pg>0 arranca oculta por estilo (evita el flash pre-Datastar);
      // data-show toma el control apenas carga.
      const show = paginas > 1 ? ` data-show="$${sig}===${pg}"${pg > 0 ? ' style="display:none"' : ""}` : "";
      const extra = rowAttrs[i] ? ` ${rowAttrs[i]}` : "";
      return `<tr${show}${extra}>${cells.map((c) => `<td class="align-top">${c}</td>`).join("")}</tr>`;
    })
    .join("");
  const nav =
    paginas > 1
      ? `<div class="flex items-center gap-2 mt-2">
      <button class="btn btn-xs" data-on:click="$${sig} = $${sig} > 0 ? $${sig} - 1 : 0">‹</button>
      <span class="text-xs tabular-nums" style="color:var(--text-2)" data-text="($${sig}+1)+' / ${paginas}'">1 / ${paginas}</span>
      <button class="btn btn-xs" data-on:click="$${sig} = $${sig} < ${paginas - 1} ? $${sig} + 1 : ${paginas - 1}">›</button>
      <span class="text-xs" style="color:var(--text-3)">${rows.length} filas</span>
    </div>`
      : "";
  return `<div data-signals="{${sig}:0}">
    <div class="table-wrap"><div class="table-scroll"><table class="tbl"><thead><tr>${th}</tr></thead><tbody>${tr}</tbody></table></div></div>
    ${nav}
  </div>`;
}

module.exports = { tablaPaginada };

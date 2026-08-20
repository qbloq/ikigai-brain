// resolver-ventas — el stepper de RESOLVER una venta reportada: lista los
// leads curados (fuente leads_resolucion: sqlite local + cruce vivo contra
// payment_plans) y, al seleccionar uno, guía el reporte en pasos:
//   1. resultado (Venta / Seguimiento / No Califica / No Show)
//   2. si Venta → producto (catálogo del sistema vía el relay /mkt)
//   3. plan de pagos — la cuota 1 ES el abono (el usuario la ve como «abono»,
//      el sistema como cuota 1): «Pago completo» = 1 cuota; «Abono» = abono +
//      N cuotas, el resto repartido mensual. Solo la cuota 2 es editable; al
//      cambiarla, las 3..N se reacomodan solas (la última absorbe centavos).
//   4. resumen + comprobante (opcional) → confirmar.
//
// Escritura: SOLO vía el relay Marketico (params.base_mkt — /mkt/<slug> en el
// publicador con el token del propio closer; /mkt/dev en local con el token
// del cerebro). Tres caminos según el pareo de la fila:
//   completo      → POST calls/<meeting>/confirm (mueve GHL + crea el plan;
//                   el closer del plan = user_id de la oportunidad)
//   sin_meeting   → POST payment-plans directo (sin sync GHL; el closer =
//                   la sesión que reporta) — solo Venta tiene sentido
//   no_encontrado → bloqueado (no hay contacto GHL al que colgarle nada)
// Tras crear el plan, la cuota 1 se marca Paid (payout engine incluido) y el
// comprobante, si viene, se sube a esa cuota. El estado «resuelto» de la
// lista se deriva del sistema (¿existe el plan?) — nunca de una marca local.
//
// ⚠️ «No Show» no existe en el enum del backend (VENTA|SEGUIMIENTO|NO
// CALIFICA): se envía igual y queda como registro en call_meeting_results,
// pero no mueve stage en el CRM. Documentado en apis/mkt/closer-calls.openapi.json.
const { fetchSource } = require("../lib/datasources");
const { escape } = require("../lib/kit");

function renderResolverVentas(ui) {
  const params = { ...(ui.params || {}) };
  const baseMkt = String(params.base_mkt || "/mkt/dev");
  const integrationId = String(params.integration_id || "");
  delete params.base_mkt;
  delete params.integration_id;

  let rows = [];
  let err;
  try {
    rows = fetchSource(ui.source || "leads_resolucion", params).rows || [];
  } catch (e) {
    err = e.message;
  }
  if (err) {
    return `<section id="pane" class="flex-1 p-6 overflow-auto"><div class="alert alert-neg">${escape(err)}</div></section>`;
  }

  const money = (v) => (v == null || v === "" ? "—" : "$" + Number(v).toLocaleString("en-US"));
  const badgeEstado = (r) =>
    r.estado === "resuelto"
      ? `<span class="badge badge-pos">Resuelto · plan #${escape(String(r.plan_id))}</span>`
      : r.estado === "bloqueado"
        ? `<span class="badge badge-neutral">Bloqueado</span>`
        : `<span class="badge badge-cau">Pendiente</span>`;
  const badgePareo = (r) =>
    r.pareo === "completo"
      ? `<span class="badge badge-brand">llamada + CRM</span>`
      : r.pareo === "sin_meeting"
        ? `<span class="badge badge-neutral">solo CRM</span>`
        : `<span class="badge badge-neg">sin rastro</span>`;

  const cards = rows
    .map((r) => {
      const activo = r.estado === "pendiente";
      return `<div class="card p-4 flex flex-col gap-2 ${activo ? "cursor-pointer hover:shadow-md transition-shadow" : "opacity-70"}"
        ${activo ? `onclick="RV.abrir(${Number(r.n)})"` : ""} id="rv-card-${Number(r.n)}">
      <div class="flex items-start justify-between gap-2">
        <span class="font-semibold leading-tight">${escape(r.lead)}</span>
        <span class="tabular-nums font-semibold whitespace-nowrap">${money(r.monto_reportado)}</span>
      </div>
      <div class="flex flex-wrap gap-1.5">${badgeEstado(r)} ${badgePareo(r)}
        ${r.opp_status === "won" ? `<span class="badge badge-pos">opp won</span>` : ""}
        ${r.producto_reportado ? `<span class="badge badge-neutral">${escape(r.producto_reportado)}</span>` : ""}</div>
      <p class="text-xs leading-snug" style="color:var(--text-2)">${escape(r.reporte_mateo || "")}</p>
      ${r.estado === "bloqueado" ? `<p class="text-xs italic" style="color:var(--text-3)">${escape(r.notas || "Sin contacto en el CRM — no hay a quién colgarle el plan.")}</p>` : ""}
      ${activo ? `<span class="text-xs font-medium mt-1" style="color:var(--text-brand)">Reportar →</span>` : ""}
    </div>`;
    })
    .join("");

  const datos = { leads: rows, base: baseMkt, integrationId };

  return `<section id="pane" class="flex-1 relative overflow-auto p-4 sm:p-6">
  <div class="max-w-3xl mx-auto">
    <div class="mb-4">
      <h1 class="text-lg font-bold">Resolver ventas</h1>
      <p class="text-sm" style="color:var(--text-2)">Selecciona un lead y reporta el resultado de su llamada. Si fue venta, el plan de pagos queda creado en el sistema — la fila pasa a «Resuelto» sola.</p>
    </div>
    <div class="grid gap-3 sm:grid-cols-2">${cards || `<p class="text-sm italic" style="color:var(--text-3)">Sin leads en la cola.</p>`}</div>
  </div>

  <div id="rv-modal" class="fixed inset-0 z-50 hidden items-end sm:items-center justify-center" style="background:color-mix(in srgb, var(--text-1) 40%, transparent)">
    <div class="card w-full sm:max-w-lg max-h-[92vh] overflow-auto p-5 rounded-t-2xl sm:rounded-2xl" id="rv-body"></div>
  </div>

  <script>
  window.RVDATA = ${JSON.stringify(datos).replace(/</g, "\\u003c")};
  </script>
  <script>
  (function () {
    const D = window.RVDATA;
    const $ = (id) => document.getElementById(id);
    const money = (v) => "$" + Number(v || 0).toLocaleString("en-US", { maximumFractionDigits: 2 });
    const hoy = () => new Date().toISOString().slice(0, 10);
    const mesDespues = (iso, k) => {
      const d = new Date(iso + "T12:00:00");
      d.setMonth(d.getMonth() + k);
      return d.toISOString().slice(0, 10);
    };
    let S = null;          // estado del stepper
    let productos = null;  // catálogo (una sola carga)

    async function api(method, sub, body, esForm) {
      const opt = { method, headers: {} };
      if (body !== undefined) {
        if (esForm) opt.body = body;
        else { opt.headers["Content-Type"] = "application/json"; opt.body = JSON.stringify(body); }
      }
      const r = await fetch(D.base + "/" + sub, opt);
      let j = null;
      try { j = await r.json(); } catch {}
      if (!r.ok || (j && j.success === false)) throw new Error((j && (j.error || j.message)) || ("HTTP " + r.status));
      return j;
    }

    // --- cálculo de cuotas: la cuota 1 es el abono -----------------------
    function cuotas() {
      const t = Number(S.total || 0);
      if (S.modo === "completo") return [{ n: 1, fecha: S.fechaPago, monto: t }];
      const a = Number(S.abono || 0);
      const N = Math.max(2, Number(S.ncuotas || 2));
      const resto = +(t - a).toFixed(2);
      const c2f = S.c2fecha || mesDespues(S.fechaPago, 1);
      const c2m = S.c2monto != null && S.c2monto !== "" ? Number(S.c2monto) : +(resto / (N - 1)).toFixed(2);
      const filas = [{ n: 1, fecha: S.fechaPago, monto: a }, { n: 2, fecha: c2f, monto: c2m }];
      const quedan = N - 2;
      if (quedan > 0) {
        const porCuota = +(((resto - c2m) / quedan)).toFixed(2);
        let acumulado = c2m;
        for (let i = 0; i < quedan; i++) {
          const ultima = i === quedan - 1;
          const monto = ultima ? +(resto - acumulado).toFixed(2) : porCuota;
          acumulado = +(acumulado + monto).toFixed(2);
          filas.push({ n: i + 3, fecha: mesDespues(c2f, i + 1), monto });
        }
      }
      return filas;
    }
    function planValido() {
      const t = Number(S.total || 0);
      if (!(t > 0) || !S.fechaPago) return "Falta el monto total o la fecha de pago.";
      if (S.modo === "completo") return null;
      const a = Number(S.abono || 0);
      if (!(a > 0) || a >= t) return "El abono debe ser mayor a 0 y menor al total.";
      const filas = cuotas();
      if (filas.some((c) => c.monto <= 0)) return "Una cuota quedó en 0 o negativa — ajusta la cuota 2.";
      return null;
    }

    // --- render de pasos --------------------------------------------------
    const btn = (label, cls, on) => '<button type="button" class="btn ' + cls + '" onclick="' + on + '">' + label + "</button>";
    function pinta(html) { $("rv-body").innerHTML = html; }
    function cabecera(titulo) {
      return '<div class="flex items-center justify-between mb-3"><div><p class="text-xs" style="color:var(--text-3)">' +
        S.lead.lead + '</p><h2 class="font-bold">' + titulo + "</h2></div>" +
        '<button type="button" class="btn btn-ghost" onclick="RV.cerrar()">✕</button></div>';
    }

    function paso1() {
      S.paso = 1;
      const soloVenta = S.lead.pareo !== "completo";
      const b = (r, activo) =>
        '<button type="button" class="btn w-full justify-center text-base py-3 ' + (activo ? "" : "opacity-40 pointer-events-none") +
        '" onclick="RV.resultado(\\'' + r + '\\')">' + r + "</button>";
      pinta(cabecera("¿Cómo terminó?") +
        '<div class="grid gap-2">' + b("Venta", true) + b("Seguimiento", !soloVenta) + b("No Califica", !soloVenta) + b("No Show", !soloVenta) + "</div>" +
        (soloVenta ? '<p class="text-xs mt-3" style="color:var(--text-3)">Este lead no tiene llamada registrada en el sistema — solo se puede reportar la venta (el plan se crea directo, sin mover el CRM).</p>' : ""));
    }

    async function paso2() {
      S.paso = 2;
      pinta(cabecera("Producto") + '<p class="text-sm" style="color:var(--text-3)">Cargando catálogo…</p>');
      try {
        if (!productos) productos = (await api("GET", "products")).data || [];
      } catch (e) {
        pinta(cabecera("Producto") + '<div class="alert alert-neg">No pude cargar el catálogo: ' + e.message + "</div>");
        return;
      }
      // solo los productos del proyecto del lead — un closer de DG no debe ver
      // el catálogo de Andrea. Sin project_id en la fila (o sin match), se
      // muestra todo antes que bloquear el paso.
      const delProyecto = S.lead.project_id ? productos.filter((p) => p.project_id === S.lead.project_id) : [];
      const catalogo = delProyecto.length ? delProyecto : productos;
      const lista = catalogo
        .map((p) => '<button type="button" class="btn w-full justify-between py-3" onclick="RV.producto(\\'' + p.id + '\\')"><span>' +
          p.name + '</span><span class="tabular-nums">' + money(p.base_price) + "</span></button>")
        .join("");
      pinta(cabecera("Producto") + '<div class="grid gap-2">' + lista + "</div>");
    }

    function paso3() {
      S.paso = 3;
      const p = productos.find((x) => x.id === S.productoId);
      const err = planValido();
      const filas = err ? [] : cuotas();
      // Filas apiladas, NUNCA una tabla: en un teléfono la tabla desborda y
      // esconde el monto tras un scroll horizontal que nadie descubre. La
      // cuota editable pone sus dos inputs en su propia línea, a todo ancho.
      const filasHtml = filas
        .map((c) => {
          const editable = S.modo === "abono" && c.n === 2;
          const nombre = c.n === 1 ? "Abono" : "Cuota " + c.n;
          if (!editable)
            return '<div class="flex items-center gap-2 px-3 py-2 rounded-lg" style="background:var(--surface-2)">' +
              '<span class="text-sm font-medium">' + nombre + "</span>" +
              '<span class="text-xs tabular-nums ml-auto" style="color:var(--text-3)">' + c.fecha + "</span>" +
              '<span class="tabular-nums font-semibold w-20 text-right">' + money(c.monto) + "</span></div>";
          return '<div class="px-3 py-2 rounded-lg" style="background:var(--surface-2);outline:2px solid var(--brand-solid)">' +
            '<div class="text-sm font-medium mb-1">' + nombre + ' <span class="text-xs font-normal" style="color:var(--text-3)">— ajusta fecha o monto y el resto se reacomoda</span></div>' +
            '<div class="flex gap-2">' +
            '<input type="date" class="input flex-1 min-w-0" value="' + c.fecha + '" onchange="RV.c2(\\'c2fecha\\', this.value)"/>' +
            '<input type="number" step="0.01" inputmode="decimal" class="input w-24 text-right" value="' + c.monto + '" onchange="RV.c2(\\'c2monto\\', this.value)"/>' +
            "</div></div>";
        })
        .join("");
      pinta(cabecera("Plan de pagos — " + (p ? p.name : "")) +
        '<div class="grid gap-3">' +
        '<div class="flex gap-2">' +
        '<button type="button" class="btn flex-1 justify-center ' + (S.modo === "completo" ? "btn-primary" : "") + '" onclick="RV.modo(\\'completo\\')">Pago completo</button>' +
        '<button type="button" class="btn flex-1 justify-center ' + (S.modo === "abono" ? "btn-primary" : "") + '" onclick="RV.modo(\\'abono\\')">Abono</button>' +
        "</div>" +
        '<label class="text-sm">Monto total (USD)<input type="number" step="0.01" class="input w-full mt-1" value="' + (S.total ?? "") + '" onchange="RV.set(\\'total\\', this.value)"/></label>' +
        '<label class="text-sm">Fecha del pago recibido<input type="date" class="input w-full mt-1" value="' + S.fechaPago + '" onchange="RV.set(\\'fechaPago\\', this.value)"/></label>' +
        (S.modo === "abono"
          ? '<div class="grid grid-cols-2 gap-2">' +
            '<label class="text-sm">Abono recibido<input type="number" step="0.01" class="input w-full mt-1" value="' + (S.abono ?? "") + '" onchange="RV.set(\\'abono\\', this.value)"/></label>' +
            '<label class="text-sm"># de cuotas (con abono)<input type="number" min="2" max="12" class="input w-full mt-1" value="' + S.ncuotas + '" onchange="RV.set(\\'ncuotas\\', this.value)"/></label>' +
            "</div>"
          : "") +
        (err
          ? '<div class="alert alert-cau">' + err + "</div>"
          : '<div class="grid gap-1.5">' + filasHtml + "</div>") +
        '<div class="flex justify-between mt-1">' + btn("← Atrás", "btn-ghost", "RV.irPaso(2)") + btn("Continuar →", "btn-primary", "RV.irPaso(4)") + "</div>" +
        "</div>");
    }

    function paso4() {
      S.paso = 4;
      const esVenta = S.resultado === "Venta";
      const filas = esVenta ? cuotas() : [];
      const p = esVenta ? productos.find((x) => x.id === S.productoId) : null;
      const resumen = esVenta
        ? "<li><b>" + (p ? p.name : "") + "</b> — total " + money(S.total) + "</li>" +
          filas.map((c) => "<li>" + (c.n === 1 ? "Abono (pagado)" : "Cuota " + c.n) + ": " + money(c.monto) + " · " + c.fecha + "</li>").join("")
        : "<li>Resultado: <b>" + S.resultado + "</b></li>";
      pinta(cabecera("Confirmar") +
        '<ul class="text-sm grid gap-1 mb-3">' + resumen + "</ul>" +
        '<label class="text-sm">Notas (opcional)<textarea class="input w-full mt-1" rows="2" onchange="RV.set(\\'notas\\', this.value)">' + (S.notas || "") + "</textarea></label>" +
        (esVenta
          ? '<label class="text-sm block mt-2">Comprobante del pago (opcional)<input type="file" accept="image/*,.pdf" class="input w-full mt-1" onchange="RV.archivo(this)"/></label>'
          : "") +
        '<div class="flex justify-between mt-4">' + btn("← Atrás", "btn-ghost", esVenta ? "RV.irPaso(3)" : "RV.irPaso(1)") +
        '<button type="button" id="rv-go" class="btn btn-primary" onclick="RV.enviar()">Confirmar</button></div>' +
        '<div id="rv-msg" class="mt-3"></div>');
    }

    // --- envío ------------------------------------------------------------
    async function marcarPagada(planes) {
      // el plan recién creado = el más nuevo del contacto; su cuota 1 pasa a Paid
      const plan = (planes || []).sort((a, b) => (b.plan_id || 0) - (a.plan_id || 0))[0];
      if (!plan) throw new Error("El plan se creó pero no lo encuentro para marcar el abono.");
      const c1 = (plan.installments || []).find((i) => i.installment_number === 1);
      if (!c1) throw new Error("El plan no trae la cuota 1.");
      await api("PUT", "installments/" + c1.installment_id, {
        status: "Paid",
        paid_amount: c1.scheduled_amount,
        payment_date: S.fechaPago,
        _previousStatus: "Scheduled",
      });
      return c1.installment_id;
    }

    async function enviar() {
      const boton = $("rv-go");
      boton.disabled = true;
      boton.textContent = "Enviando…";
      const msg = (html) => { $("rv-msg").innerHTML = html; };
      try {
        const L = S.lead;
        if (S.resultado !== "Venta") {
          const mapa = { Seguimiento: "SEGUIMIENTO", "No Califica": "NO CALIFICA", "No Show": "NO SHOW" };
          await api("POST", "calls/" + L.meeting_id + "/confirm", { result: mapa[S.resultado], reason: S.notas || "" });
        } else {
          const filas = cuotas();
          const errPlan = planValido();
          if (errPlan) throw new Error(errPlan);
          let cuotaId;
          if (L.pareo === "completo") {
            await api("POST", "calls/" + L.meeting_id + "/confirm", {
              result: "VENTA",
              reason: S.notas || "",
              paymentPlan: { product_id: S.productoId, original_amount: Number(S.total), number_of_installments: filas.length },
              installments: filas.map((c) => ({ installmentNumber: c.n, dueDate: c.fecha, scheduledAmount: c.monto })),
            });
            const planes = (await api("GET", "payment-plans/customer/" + L.ghl_contact_id)).data;
            cuotaId = await marcarPagada(planes);
          } else {
            const p = productos.find((x) => x.id === S.productoId);
            const creado = await api("POST", "payment-plans", {
              integration_id: L.integration_id || D.integrationId,
              product_uuid: S.productoId,
              product_id: p && p.product_id ? p.product_id : undefined,
              customer_id: L.ghl_contact_id,
              customer_name: L.lead,
              original_amount: Number(S.total),
              currency: "USD",
              number_of_installments: filas.length,
              installment_frequency: "Monthly",
              start_date: filas[0].fecha,
              installments: filas.map((c) => ({ installment_number: c.n, due_date: c.fecha, scheduled_amount: c.monto })),
            });
            const insts = (creado.data && creado.data.installments) || [];
            const c1 = insts.find((i) => i.installment_number === 1);
            if (!c1) throw new Error("El plan se creó sin cuota 1.");
            await api("PUT", "installments/" + c1.installment_id, {
              status: "Paid", paid_amount: c1.scheduled_amount, payment_date: S.fechaPago, _previousStatus: "Scheduled",
            });
            cuotaId = c1.installment_id;
          }
          if (S.file && cuotaId) {
            const fd = new FormData();
            fd.append("file", S.file);
            try { await api("POST", "installments/" + cuotaId + "/receipt", fd, true); }
            catch (e) { msg('<div class="alert alert-cau">Venta registrada ✓ pero el comprobante no subió: ' + e.message + "</div>"); }
          }
        }
        msg('<div class="alert alert-pos">Listo ✓ — registrado en el sistema.</div>');
        setTimeout(() => location.reload(), 1400);
      } catch (e) {
        boton.disabled = false;
        boton.textContent = "Confirmar";
        msg('<div class="alert alert-neg">' + e.message + "</div>");
      }
    }

    // --- API pública del stepper -----------------------------------------
    window.RV = {
      abrir(n) {
        const lead = D.leads.find((r) => Number(r.n) === n);
        if (!lead || lead.estado !== "pendiente") return;
        S = { lead, paso: 1, resultado: null, productoId: null, modo: "completo",
              total: lead.monto_reportado || "", abono: "", ncuotas: 3,
              fechaPago: hoy(), c2monto: "", c2fecha: "", notas: "", file: null };
        $("rv-modal").classList.remove("hidden");
        $("rv-modal").classList.add("flex");
        paso1();
      },
      cerrar() {
        $("rv-modal").classList.add("hidden");
        $("rv-modal").classList.remove("flex");
        S = null;
      },
      resultado(r) {
        S.resultado = r;
        if (r === "Venta") paso2(); else paso4();
      },
      producto(id) {
        S.productoId = id;
        const p = productos.find((x) => x.id === id);
        if (p && (!S.total || Number(S.total) === 0)) S.total = p.base_price;
        paso3();
      },
      modo(m) { S.modo = m; S.c2monto = ""; S.c2fecha = ""; paso3(); },
      set(k, v) { S[k] = v; if (S.paso !== 4) paso3(); },
      c2(k, v) { S[k] = v; paso3(); },
      archivo(inp) { S.file = inp.files && inp.files[0] ? inp.files[0] : null; },
      irPaso(p) { S.paso = p; [null, paso1, paso2, paso3, paso4][p](); },
      enviar,
    };
    // el click fuera del panel cierra
    $("rv-modal").addEventListener("click", (e) => { if (e.target === $("rv-modal")) RV.cerrar(); });
  })();
  </script>
</section>`;
}

module.exports = {
  id: "resolver-ventas",
  manifest: { consumes: "rows", overridable: ["desde"] },
  render: renderResolverVentas,
};

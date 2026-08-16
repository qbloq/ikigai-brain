# ONLY CLOSERS — análisis del último mes (2026-07-11 → 2026-08-12)

**Fuente:** grupo de WhatsApp «ONLY CLOSERS» (JID `120363423242173011@g.us`),
volcado vía Evolution API (`/chat/findMessages`, 91 páginas) a la db local
`only_closers` (tabla `mensajes`, 4.520 filas). El grupo acumula 16.035
mensajes desde que la instancia lo registra; este informe cubre los últimos
32 días. Corpus semanal leído completo por 5 agentes de contexto limpio
(sem1–sem5); síntesis verificable contra la db (`bash/localdb/db_query.sh only_closers …`).

---

## 1. Qué es este grupo

Es la **sala de máquinas de la operación de cierre** — mucho más operativo que
social. El flujo diario, sostenido las 5 semanas:

1. Setters (Mateo, Francoach) y confirmadores («cc»: Antonio Buelvas y, desde
   el 03-ago, Anthony «A») publican **fichas de lead**: nombre / teléfono /
   email / «Confirmado y Calificado» / presupuesto declarado / fecha / closer.
2. Cada noche, la **agenda consolidada** del día siguiente («*Leads Confirmados
   y Calificados DD/MM*»).
3. Cada closer entrega **reporte de fin de día** (agendas / asistencias /
   cierres / no-shows) — ritual cobrado por Antonio, cumplido por todos.
4. Luis F (Director Comercial) publica el **acumulado del mes contra la meta**
   y ajusta proceso/precios en caliente.

## 2. Números del mes (capa cuantitativa, db `only_closers`)

- **4.520 mensajes** en 32 días (~141/día). 84% texto; 309 stickers, 195
  reacciones, 100 imágenes, 70 audios.
- **Participación**: Ayrton 1.737 (38%) · Antonio Buelvas 879 · CH GROUP
  (Carlos, Costa Rica) 695 · Luis F 512 · Mateo Restrepo 296 · Francoach 166 ·
  «A» (Anthony) 161 · **Lorenzo 48 · Juan Camilo 6** — dirección casi ausente.
- **Ritmo**: pico lunes–miércoles (964/879/985); mediodía es la hora más densa
  (552 mensajes a las 12, hora Bogotá) con segundo pico 17–19h. Cae fuerte
  sáb/dom (334/142). Días récord: 04-ago (326) y 03-ago (297) — arranque de mes.
- Casi nadie usa «responder» con cita (15 en el mes): conversación corrida.
  Antonio y Ayrton son los que más reaccionan a los demás (89/64).

**Identidades** (los `numero` del volcado son LIDs de WhatsApp, no teléfonos —
el mapeo es por pushName): Ayrton = Ayrton Vega (closer) · Luis F = Luis David
Flórez (Director Comercial) · Mateo Restrepo (setter) · «Antonio Buelvas»
probablemente Cristian Buelvas · «CH GROUP 🦅» = Carlos (leads «Es de Carlos»;
¿Carlos González?) · «A» = Anthony (¿Anthony Velásquez?, entró el 03-ago) ·
Lorenzo Cadavid y Juan Camilo Correa (dirección) · Pablo/Santiago = soporte
técnico.

## 3. La historia comercial del mes

- **Julio**: meta 100k. Trayectoria publicada: 46k (20-jul) → 61k (27-jul) →
  75.3k (30-jul)… hasta que Luis F encuentra **dos ventas duplicadas en el
  Excel** y el número baja a **72.4k** la misma tarde. Aun así, Lorenzo lo
  declara «el mes que más hemos vendido» (récord previo «77.algo»). Cifra
  final de julio: no se publicó en el grupo.
- **Agosto**: meta 100k otra vez («hay que meter 4k al día»); al 07-ago la
  proyección de Luis F es **~80k**. Señal de calidad que él mismo marca:
  «buena tasa de cierre / **pero mucho abono**» — mucho pago parcial, poco
  payfull. (Coincide con lo que ya sabemos de `installments`: la venta se
  sella con la cuota, no con el «cierre».)
- **Ticket**: el estándar es **PA 700 USD**; PM 3.5k; picos de 5.5k; Aura 397;
  low ticket 15 USD (Luis F: «lo pueden vender en 50»; «Parejas queda en 97»).
  Anuncio del 30-jul: **el precio sube «en dos semanas»** y llega un tier de 2k.

## 4. Los hallazgos que se repiten TODAS las semanas (sistémicos)

### 4.1 El embudo se rompe en la asistencia, no en el cierre
Show-rates reportados: 3/7, 3/5, 0/2, un día 5/5 no-shows, «3 no show de 4».
Reincidentes con nombre (William 3 cancelaciones, Darly y Jaider ×2, Jessica
3-4 reagendas). Cuando el lead calificado asiste, cierran. Existe un «protocolo
de reactivación no show» pero la hoja depende de registro manual atrasado.
**La política de doble no-show fue preguntada por dos closers distintos (17 y
18-jul) y nunca respondida en el grupo.**

### 4.2 «Confirmado y Calificado / 700» no predice capacidad de pago
Cada semana llegan a llamada leads etiquetados con presupuesto que declaran
tener 30–53 USD, ganar el mínimo o estar desempleados. El monto lo declara el
lead y nadie lo verifica. Propuesta interna desatendida (Ayrton, 2 veces):
pasar «dolores, barreras y urgencia» del lead en la pre-call + nota en CRM.

### 4.3 El registro de ventas y las grabaciones fallan justo donde duele
- **≥4 ventas no aparecieron en la app** al reportarlas (Edwin, Kevin, Juan
  Manuel en julio; Samuel Arango —700 USD cobrados— tardó ~2 días en agosto).
  El registro depende de que el closer se dé cuenta y persiga a soporte.
- **El bot de grabación falló ≥3 veces**, incluyendo una llamada de cierre de
  5.5k (25-jul) y una que querían para análisis grupal (07-ago). El 12-ago
  Ayrton sospecha que «tampoco se estarían grabando las llamadas».
- ⚠️ Esto golpea directo al cerebro: **nuestro pipeline de reportes de llamada
  (BANT) depende de esos transcripts**, y la cola S8.2 de llamadas sin closer
  se alimenta de estos huecos.

### 4.4 La infraestructura comercial es artesanal y frágil
- **El CRM «no está instalado aún»** — confirmado textual por Luis F el 02-ago.
  El tracking real del mes vive en un **Excel que Luis migra a mano de
  madrugada** (ahí nacieron los duplicados de ±6k).
- **WhatsApp baneado 3 veces** (04-ago, 06-ago, +1 previa) por mensajería
  masiva — es el canal de confirmación Y de cobro; el plan B son privados
  improvisados. Sesiones compartidas entre personas; al nuevo closer se le da
  acceso **rotando el WhatsApp de otro closer**.
- CRM asignando leads a closers dados de baja (Franco, «lucho»), calendario
  bloqueado, agendas que se borran solas, leads sin dueño («¿Qué lead es ese?»),
  Instagram de David con restricciones recurrentes sin dueño técnico.

### 4.5 Preguntas a dirección que mueren sin respuesta
(1) política de doble no-show; (2) **atribución DG↔AURA** (Ana entró por DG y
cerró Aura — «¿cómo la contamos?» quedó abierto); (3) regla de comisión por
referidos (¿5-10% o 50/50?); (4) «¿qué día tenemos análisis de llamadas?»;
(5) mejoras de pre-call propuestas por Ayrton. El grupo tiene memoria corta y
sin dueño: lo no respondido en el día desaparece.

### 4.6 Compliance (transversal)
- **Datos personales completos de leads y clientes en texto plano** (cédulas,
  direcciones, teléfonos, fechas de nacimiento) circulando a diario.
- Venta en curso a un **menor de edad** («los papás quedaron de darle el cash»).
- Instrucción tácita de **ocultar el nombre del broker de fondeo** (Bridge
  Markets, «si le decís el nombre se cae la venta») y evitar la palabra «forex».
- Un tercero contactando leads de la base (alerta de Antonio, 14-jul).

## 5. Dinámica humana

- **Luis F dirige de verdad y en caliente**: metas diarias, precios al vuelo,
  links de pago al momento, reuniones semanales, y las dos decisiones de
  proceso del mes — el **Excel de tracking** (23-jul) y el **video de
  preparación obligatorio** con palabra clave de verificación (07/10-ago;
  AURA no tiene equivalente, gap declarado).
- **Antonio Buelvas es la columna operativa** — sin él no hay agenda ni
  reportes. **Ayrton es el motor emocional y el que más invierte en mejorar**:
  se pagó una mentoría externa (bloquea mar/jue 17h), organizó una «vaquita»
  para comprar una academia, propone roleplays sabatinos y comparte sus
  grabaciones. Los closers se están **autofinanciando la formación**.
- **Lorenzo aparece a saludar y auditar el número; Juan Camilo casi no existe
  en el canal** (6 mensajes en el mes).
- Tono: camaradería intensa (brokis, chachos, el che, el Mae), religiosidad
  explícita, Mundial como termómetro emocional (julio), y solidaridad real
  (la madre de «A», los amigos bajo escombros del terremoto).
- **El terremoto del 10-ago es variable comercial activa**: «suavidad esta
  semana con los leads… Chocó Cali Pereira», reagendas atribuibles, y esperada
  caída de show-rate.

## 6. Accionables (priorizados)

1. **Auditar el registro venta→app→grabación** (§4.3): es a la vez ingreso
   subcontado, coaching perdido y hueco en nuestro pipeline de análisis.
   Verificable cruzando estos anuncios del grupo contra `payment_plans`/
   `installments` y `meetings` sin transcript.
2. **Intervenir la calificación del setter** (§4.2): el campo «presupuesto»
   necesita verificación o al menos la pre-call con dolor/urgencia que el
   propio equipo pide. Es el mismo hallazgo del BANT: el dato declarado no
   discrimina; el verificado sí.
3. **Definir y escribir las 3 reglas huérfanas**: doble no-show, atribución
   cross-cliente, comisión por referidos. Las tres ya costaron horas de closer
   o van a costar peleas de comisión.
4. **Plan B de canal**: 3 baneos de WhatsApp en un mes sobre el canal de
   confirmación y cobro, con sesiones compartidas y sin trazabilidad. (El
   video de preparación + palabra clave ya bajó fricción; falta el canal.)
5. **Show-rate como KPI del grupo**: hoy se reporta artesanalmente; las fichas
   y reportes diarios del grupo son estructurables (este mismo volcado lo
   demuestra) y cruzables con `meetings`/`crm_opportunities`.
6. **Compliance de datos**: mover las fichas de lead fuera del chat plano, o
   al menos sacar cédulas/direcciones.

## 7. Cruce contra la plata (2026-08-12) — anuncios del grupo vs `payment_plans`/`installments`

Ejecutado el accionable #1: cada cierre anunciado en el grupo, buscado en
Postgres (planes creados 2026-07-11 → 2026-08-12 + búsqueda por nombre sin
filtro de fecha).

**Lo que cuadra (la mayoría):** Cristian Fernando (433, pagó 500 tal como
anunció), Jahir Bedoya (434, 1000 el 17-jul), Maximiliano (442 payfull),
Iván Caceres (444), Geovany (447), **Geàn 5.5k payfull** (451), Cesar (459),
Camilo (458), Andrés Mantilla (461), Esteban (469), Javier Sampayo (471),
Mervin Valera (472), Yusmaily (473), Santiago González (474), Sebastian Rey
(476). El grupo anuncia y la plata aparece — el canal es veraz.

**Lo roto (5 casos + 2 duplicados):**

| Caso | Anuncio en el grupo | Estado en la DB |
|------|--------------------|-----------------|
| **Edwin Antiche** | pagó 700 PA el 14-jul; pidieron corrección a soporte | plan 430 existe (¡de 5.500!) con **$0 pagado** — ni el monto ni el pago aterrizaron |
| **Kevin Felipe Delgado** | venta PA 700 el 16-jul; «no me aparece en la app» | contacto CRM existe; **plan jamás creado** (27 días después) |
| **Samuel Arango** | 25 USD el 11-ago + 675 el 12-ago (700 PA); no pudo reportarlo | contacto existe (09-ago); **ni plan ni pagos** en `installments` del 11/12-ago (Pablo lo estaba atendiendo el 12) |
| **Juan Manuel Bedoya** | PM reportado 17-jul, «no aparece» | no existe; **posible confusión con Jahir Bedoya** (su primer pago fue justo el 17-jul) — verificar antes de crear nada |
| **Danna Moncada** | Alquimia 4k con contrato en revisión (16-jul) | contacto existe (04-ago); sin plan — no cerró o no se registró |
| Nikol Garcia | — | **2 planes** (452/454), uno con $0 — duplicado vivo |
| Acevedo Morales | el chat ya lo notó como «lead duplicado» (06-ago) | **2 planes** (464/465), uno con $0 — duplicado vivo |

El patrón de los duplicados del Excel del 30-jul (±6k en la cifra del mes)
**también existe en producción**: dos planes fantasma de $0 inflan el
contratado si alguien suma sin filtrar.

**«Mucho abono», cuantificado:** los 48 planes de la ventana suman **$77.554
contratados y $40.843 cobrados (52,7%)** — 24 payfull, 22 en abono, 2 sin
ningún pago. La intuición de Luis F (07-ago) es exactamente correcta.

**Grabaciones — peor y más viejo de lo que el grupo cree:** de 459 llamadas
agendadas en la ventana, solo **41 tienen transcript (~9%)**. Y no es nuevo:
la cobertura mensual de todo 2026 oscila entre **5,5% y 14,6%** (julio, el mes
más pesado con 410 llamadas: 8,3%). Aun descontando ~40-50% de no-shows, más
de tres cuartas partes de las llamadas atendidas no dejan rastro. Todo el
análisis de llamadas (BANT, coaching, objeciones) opera sobre esa astilla.

**Identidades confirmadas por el cruce** (el closer del plan resuelve el
apodo): «CH GROUP 🦅» = **Carlos González** · «Francoach» = **Diego Fernando
Perdomo** (los planes 432/452-455 que el chat le atribuye van a su nombre).

## 8. Registro de reparaciones

### 2026-08-13 — los 3 registros de venta rotos ✅ EJECUTADA Y VERIFICADA

SQL completo: [reparaciones-only-closers-2026-08-12.sql](reparaciones-only-closers-2026-08-12.sql)
(3 transacciones independientes, una por caso). Ejecutado por el humano el
2026-08-13 (`psql_rw -v ON_ERROR_STOP=1 -f …`); el cerebro preparó y verificó,
no escribió.

**Resultado verificado contra la DB:**

| Plan | Cliente | Monto | Cuotas pagadas | Comisiones (pending) |
|------|---------|-------|----------------|----------------------|
| **430** (UPDATE) | Edwin Antiche | 5.500 → **700** (PM→PA), 5 → **2** cuotas | 2106: 100 (10-jul) · 2107: 600 (14-jul) = **700** | Ayrton Vega 10.00 + 60.00 |
| **479** (nuevo) | Samuel Arango Correa | **700** | 2278: 25 (11-ago) · 2279: 675 (12-ago) = **700** | Carlos González 2.50 + 67.50 |
| **480** (nuevo) | Kevin Felipe Delgado Hurtado | **699** | 2280: 699 (16-jul) = **699** | Cristian Buelvas 69.90 |

Las 3 cuotas fantasma del plan 430 (2108-2110) se borraron (`count=0`). Ninguno
de los tres aparece en la cola de vencidas de `cobranza.sh` — correcto, están
todos `Paid`. **Recuperados: $2.099 de cash que no existían contablemente** y
$210 de comisión que nunca habrían entrado a la cola de aprobación. El mes
pasa de 48 a 51 planes: **$79.653 contratados / $42.942 cobrados (53,9%)**.

⚠️ **Lección de proceso registrada aquí a propósito**: el primer intento falló
con `column "status" is of type installment_status but expression is of type
text` — dentro de un `INSERT … SELECT` con `UNION`, Postgres **no infiere el
enum** (en un `VALUES` directo sí). Todo `INSERT … SELECT` contra estas tablas
necesita casts explícitos (`'Paid'::ikigaigm.installment_status`,
`'sale'::ikigaigm.commission_type`,
`'pct_installment'::ikigaigm.commission_value_type`,
`'pending'::ikigaigm.payout_status`). El `ON_ERROR_STOP=1` hizo su trabajo: la
txn abortó sin dejar nada a medias.

**Evidencia reunida antes de escribir** (toda verificada contra la DB):

| Caso | Evidencia | Reparación |
|------|-----------|------------|
| **Samuel Arango Correa** | Ficha de pago completa de Carlos González en el grupo (12-ago 12h): 25 USD el 11-ago (reserva) + 675 el 12-ago = 700 «PA 3 meses». Contacto GHL `Jknd0KiUviD2oyCVmgY9` (proyecto DG). Oportunidad CRM `won` con dueño **Carlos González** (valor 25 — GHL solo vio la reserva). Re-verificado ausente en `payment_plans` justo antes de escribir. | INSERT plan (700, PA `17d40000`, closer Carlos `73afe0ee`) + 2 cuotas Paid (25 el 11-ago, 675 el 12-ago) + 2 comisiones pending (2.50 + 67.50). |
| **Kevin Felipe Delgado Hurtado** | Reporte de Cristian Buelvas en el grupo (16-jul 11h): «PA 3 MESES - 700 usd / Kevin Felipe delgado hurtado / …» + «Acabé de reportar una venta pero no me aparece». Oportunidad CRM **`won` con valor 699 el 16-jul**, dueño **Cristian Buelvas** — pagó payfull. Contacto GHL `8uBhLFdYZ2mkMXdocGAt` (DG). | INSERT plan (699, PA, closer Buelvas `c103c016`) + 1 cuota Paid (699 el 16-jul) + comisión pending (69.90). |
| **Edwin Antiche** | Plan 430 existe (PM 5.500, 5 cuotas todas $0) pero Ayrton pidió **tres veces** (14, 15 y 22-jul) «modificar el plan de pago de Edwin»: «Terminó pagando 700 usd PA». Oportunidad CRM `won` valor **100** (la reserva del 10-jul, tampoco registrada). Cuotas sin referencias en comisiones ni meta_capi. | UPDATE plan 430 → 700 / 2 cuotas / producto PA. Cuota 1 (100) → Paid 10-jul (la reserva de GHL); cuota 2 → 600 Paid 14-jul (completa los 700). DELETE cuotas 3-5 ($0 Scheduled). + 2 comisiones pending para Ayrton (10.00 + 60.00). **Lectura asumida: los 700 son el total (100+600), no 100+700** — el «terminó pagando 700» de Ayrton se lee como total; si el equipo confirma que fueron 800, la cuota 2 sube a 700. |

**Convenciones imitadas de la app** (filas de referencia: planes 463 y 477):
integración DG `UBREqrQ6n5QEC8lFmyGt` · proyecto DG `9077f0f0` · producto PA =
«Premium Academy 3 meses» `17d40000` · comisión regla `14e92aed` (`sale`,
`pct_installment` 10%, rol closer `7e83b8bc`, status `pending` → entra a la
cola de aprobación de `comisiones.sh`). Los planes payfull quedan `Active`
(así los deja la app). No hay triggers de negocio en estas tablas (solo
`updated_at`), así que las comisiones deben insertarse explícitamente — la app
las crea en código, no en la DB.

**Pendientes que la reparación NO cubre:**
- **Avisar a Pablo** que Samuel/Kevin quedan registrados por fuera de la app —
  si la app re-aplica el reporte de Samuel, nacerá un duplicado (el mismo
  patrón Nikol/Acevedo de §7).
- Los `monetary_value` de GHL quedan desactualizados (Samuel 25≠700,
  Edwin 100≠700) — corregir en GHL es aparte (la capa `bash/ghl/` es read-only).
- Los 2 duplicados vivos (planes 454 y 465, ambos $0) no se tocaron —
  pendiente decidir si se eliminan o se marcan `Cancelled`.

### 2026-08-13 — planes duplicados: 3 pares en TODA la tabla ✅ EJECUTADA Y VERIFICADA

SQL: [reparaciones-duplicados-2026-08-13.sql](reparaciones-duplicados-2026-08-13.sql) — una sola txn.

Al buscar el patrón fuera de la ventana del informe aparecieron **exactamente
tres pares en toda la historia de `payment_plans`** — ni uno más:

| Cliente | Monto | Real (se conserva) | Fantasma (se anula) | Separación |
|---------|-------|--------------------|---------------------|-----------|
| Vero G | 2.000 | **336** (2.000 pagados, 2 comisiones) | 337 | 45 segundos |
| Nikol Garcia | 800 | **452** (800 pagados, 1 comisión) | 454 | 8 minutos |
| Cristian D. Acevedo Morales | 699 | **464** (699 pagados, 2 comisiones) | 465 | 2 minutos |

El patrón es idéntico en los tres: mismo `customer_id`, mismo monto, creados
con segundos o minutos de diferencia, uno cobra todo y el gemelo nace vacío.
Es **doble submit del formulario de la app**, no error de dedo — y el grupo ya
lo había visto en vivo («lead duplicado», 06-ago, sobre Acevedo).

**El daño no es cosmético: la cola de cobranza reclama $3.499 que nadie debe.**
`cobranza.sh` lista las cuotas fantasma como vencidas — Vero G aparece
debiendo 2.000 «vencida >30d» cuando pagó completo en abril, Nikol 800, Acevedo
31 vencidos + 668 por vencer. Quien trabaje esa cola va a cobrarle a clientes
que ya pagaron. Además inflan el «contratado» de cualquier reporte que sume
`original_amount` sin filtrar — el mismo error que le movió ±6k al Excel de
Luis el 30-jul, pero en producción.

**Anular, no borrar** (`plan_status='Cancelled'` + cuotas `Cancelled`): la
línea del repo es «cruzar y ajustar, no borrar», y el `Cancelled` los saca de
todos los reportes igual, porque `cobranza.sh` filtra
`status IN ('Scheduled','Partial','Overdue')`. Un DELETE destruiría la
evidencia de que el doble submit ocurre, que es justo lo que hay que vigilar.
Verificado: los 3 fantasmas no tienen comisiones ni eventos meta_capi, y son
**los únicos 3 planes `Active` sin una sola cuota pagada** en toda la tabla —
no hay venta legítima reciente que pueda confundirse con ellos.

**Resultado verificado** (ejecutado por el humano el 2026-08-13): los planes
337, 454 y 465 quedaron `Cancelled` con **todas** sus cuotas `Cancelled`
(3+1+2 = 6 cuotas), y ninguno aparece ya en la cola de `cobranza.sh`. Los tres
planes reales (336, 452, 464) siguen `Active`, con sus pagos y sus 5
comisiones intactos. **$3.499 de deuda fantasma retirados de la cola de
cobranza**; nada se borró.

⚠️ Nota de verificación: `cobranza.sh --all` **desactiva** el filtro de estado
(`i.status IN ('Scheduled','Partial','Overdue')`), así que muestra también las
`Cancelled` y las `Paid` — no sirve para comprobar que algo salió de la cola.
La cola real es el comando **sin** `--all`.

⚠️ **La causa raíz sigue viva**: sin un `UNIQUE` sobre
`(customer_id, original_amount, created_at::date)` ni idempotencia en el
formulario, el cuarto par va a nacer solo. Anular estos tres limpia el síntoma.
**Es trabajo de Pablo (la app), no de la DB.**

### 2026-08-14/16 — las 6 ventas perdidas de Mateo Restrepo ✅ EJECUTADA Y VERIFICADA

SQL: [reparaciones-mateo-2026-08-14.sql](reparaciones-mateo-2026-08-14.sql) — una sola txn.
El caso más grande del informe: **cinco veces** lo de Edwin/Kevin/Samuel.

**Origen.** Mateo reportó por email una lista de 7 «clientes perdidos» desde el
1-jun. Se verificaron uno a uno contra GHL (la fuente, 7.336 oportunidades de
los 12 pipelines de DG + 500 de Andrea), contra `payment_plans` **por
`customer_id`, no por nombre**, y contra el histórico COMPLETO del grupo
(16.148 mensajes, feb→ago). Resultado: **6 reales, 1 sin sustento.**

**El hueco estructural que lo delata:** Mateo pasó **35 días sin un solo plan de
pago** (19-jun → 24-jul). Las seis ventas caen exactamente ahí. No dejó de
vender: lo que vendió no entró al sistema.

**El mecanismo, documentado en vivo.** El 10-jul 15h el chat registra a Mateo:
«bro me ayudas, **se me bloqueó la app**» · «Esta que acabé de hacer **no se
grabó**» → Pablo pregunta cuál → «**Iván Darío Giraldo Giraldo / como a las 3 y
20**». Esa es la venta de 3.500 que GHL marca `won` ese mismo día. En la misma
sesión Pablo está reparando el plan de Edwin (el 430 de §8), que nació ese día
con los datos mal. **El 10-jul fue un día roto para todos** — Ayrton también
reporta que las llamadas no se grababan.

**Lo creado** (todo closer Mateo `3dd88377`, 1 cuota `Paid`, comisión `pending`):

| Plan | Cliente | Monto | Producto | Fecha | Comisión |
|------|---------|-------|----------|-------|----------|
| 483 | Edilio Suazo | 699 | PA 3 meses | 22-jun | 69,90 |
| 484 | Jonathan Marulanda Vásquez | 3.500 | PM Lite | 2-jul | 350,00 |
| 485 | Vane de Jesús Ricciulli Rojas | 699 | PA 3 meses | 3-jul | 69,90 |
| 486 | María Paula Niño Rincón | 1.000 | PA 6 meses | 8-jul | 100,00 |
| 487 | Cristian Camilo Herrera Serna | 1.000 | PA 6 meses | 9-jul | 100,00 |
| 488 | Iván Darío Giraldo Giraldo | 3.500 | PM Lite | 10-jul | 350,00 |
| | | **$10.398** | | | **$1.039,80** |

Mateo confirmó que las seis entraron en **un solo pago**. Verificado tras
ejecutar: ninguna cayó en la cola de cobranza (correcto, cuota única `Paid`) y
las 6 comisiones están en la cola de aprobación de `comisiones.sh`. **Julio
sube a $84.106 cobrados** (102 cuotas).

**Dos identidades que el cruce resolvió:**
- **«Ilder Bonifacio» = Edilio Suazo** — el MISMO contacto GHL
  (`dmy4MxvaQrMzSp2gV5V9`, mismo email y teléfono) tiene **dos oportunidades**:
  «Ilder Bonifacio» (`open`, jun-**2025**) y «Edilio Suazo» (`won` 699,
  jun-2026). Mateo mezcló el nombre de la ficha vieja con la fecha real.
- **Renan Romero — NO existe la venta.** Contacto sí
  (`1wdklKPpXbGqdLJFPZnu`, entró por «Formulario datos Funnel lead magnet 2»
  el 13-may), pero **cero oportunidades** (verificado por `contactId` contra
  las 7.336, no por nombre), cero llamadas (`contactId` buscado dentro de
  `meetings.event`), cero menciones en 16.148 mensajes. Si cobró, fue
  íntegramente fuera del sistema; la única evidencia posible es el comprobante.

⚠️ **El bug de fondo sigue vivo y es más grande que Mateo.** El ingestor de GHL
trae oportunidades nuevas pero **no refresca el `status` de las existentes**:
Cristian Camilo, María Paula y Edilio figuraban `open` en el espejo cuando GHL
ya decía `won` (uno desde el 23-jul). Antes de la sync manual del 14-ago había
**288 `won` en el espejo contra 312 en GHL**. Esas ~24 ventas invisibles son la
misma familia de agujero, y por el patrón de Mateo es probable que varias
tampoco tengan plan. Correr la auditoría global —`won` en GHL sin
`payment_plan`— es el siguiente paso, y arreglar el ingestor es de Pablo.

**Herramienta que quedó:** `bash/ghl/contacts.sh --query` (búsqueda por nombre /
email / teléfono vía `POST /contacts/search`). Resuelve en una llamada lo que
antes exigía paginar ~2.000 contactos. Es la **única excepción** a la regla
«solo GET» de `bash/ghl/`, autorizada por Santiago el 14-ago porque es un fetch
que no crea ni modifica nada; documentada en `ghl_api_search` (lib/common.sh).
Falta reflejarla en [bash/ghl/README.md](../bash/ghl/README.md).

**Lección de método:** buscar por **nombre** falla en este CRM. «Vásquez» usa
acento combinante (`%marulanda vás%` no matchea), GHL no encuentra un teléfono
sin el `+`, y la misma persona vive bajo dos nombres. El identificador que
nunca miente es el **`contactId`** — las 7.336 oportunidades lo traen, ninguna
lo omite. Toda auditoría futura debe cruzar por ahí.

### 2026-08-13 — Miguel Lara: oportunidad sin dueño ✅ CORREGIDA EN LA FUENTE

Prospecto con llamada agendada el 13-ago 9:00 (etiquetada a Carlos en el
grupo) cuya oportunidad GHL estaba `assignedTo: null` — el gap de ownership
de §4.4, en vivo. **Corregido por Anthony directamente en GHL** (13-ago 07:54)
y bajado al espejo por actualización manual: `crm_opportunities.user_id` =
Carlos González, y `bash/calls/calls.sh` ya resuelve el closer de esa llamada
(antes salía `—`, o sea, cola S8.2).

Hallazgo que dejó el caso: **asignar el CONTACTO no asigna la OPORTUNIDAD**.
La noche anterior el contacto había quedado asignado a un usuario GHL
(`2EZezGLEAyW37MiXzbJw`) con **cero oportunidades entre las 7.331** de la
cuenta — no es un closer, y esa asignación no habría servido: nuestra
resolución de closer lee `crm_opportunities.user_id`. Si el equipo corrige
ownership, tiene que ser sobre la oportunidad.

## 9. Cómo re-consultar

```bash
# la db local (read-only por defecto)
bash/localdb/db_query.sh only_closers "SELECT …"           # tabla mensajes
# refrescar el volcado: paginar POST /chat/findMessages con
#   {"where":{"key":{"remoteJid":"120363423242173011@g.us"}},"page":N}
```

Esquema `mensajes`: `id` (key.id Evolution), `ts/fecha/hora/dia_semana`
(Bogotá), `autor` (pushName), `numero` (LID), `from_me`, `tipo`, `texto`,
`quoted_numero/quoted_texto`, `reaccion/reaccion_a`.

*Límite del histórico: la instancia (`ParalleloFinal`, creada 2026-05-01,
`syncFullHistory:false`) guarda desde que está conectada; más atrás de mayo
2026 no hay datos.*

## 10. El Setter / Call Confirmer — historial completo (2026-08-16)

*Análisis sobre el historial visible completo del grupo (el history-sync
alcanza hasta el 2026-02-02 — más atrás no hay copia; la nota de límite de §9
quedó corta: el volcado ampliado llegó a febrero). Una sola conclusión: el rol
no ha rotado en la ventana visible.*

| Período | Setter | Evidencia |
|---|---|---|
| 2026-02-02 → hoy | **Antonio Buelvas** (LID `8165068402847`) | Ya el primer día del historial publicaba fichas «Confirmado Y calificado» y listas de «No Califica». **530 de ~575 fichas de lead de todo el historial (92%)**. Sin ausencias >3 días en 6,5 meses (los huecos de 2-3 días son fines de semana). Nadie lo cubrió nunca. |
| 2026-08-03 → hoy | **Anthony** («A», LID `23424885883087`), segundo setter en entrenamiento | Luis F lo anuncia el 02-ago 21h («Mañana empezará Anthony»); el 03-ago le crean usuario en la app (Luis F → Pablo). Opera bajo validación de Antonio («cuando vayas a agendar una me envías un video y yo valido»). |

**Antes del 2 de febrero no se puede saber** — es el techo del history-sync.
Los dos LIDs que solo existen en febrero (`46596…` feb 2-16, `259592…` feb
18-26) **parecen ser Pablo antes de su LID actual, no un setter**: secuencia
perfecta (el LID actual de Pablo nace el 26-feb, justo cuando muere el
segundo) y hablan como el dueño de la app («yo ya quité esa automation», «las
cuotas de Floppy por qué están en rojo»). Coordinaba desde el CRM/app, no
confirmando llamadas. *Inferencia — verificable preguntándole a Pablo.*

**Funciones de Antonio (del propio chat):**

1. Calificar y confirmar cada lead pre-llamada y publicar la ficha:
   `name | phone | email | Confirmado y Calificado | presupuesto (700/1.5K/2K)
   | fecha y hora | closer dueño («Es de Carlos - DG») | nota`. Los que no
   pasan, con motivo («No Califica — no tiene dinero, indica que más adelante»).
2. El resumen del día siguiente: «Leads Confirmados y Calificados DD/MM» —
   la agenda completa de mañana por franja, casi siempre 17-20h (pico 18h).
3. Gestionar la agenda viva: reagendas, buscar closer disponible, reportar
   no-shows («Sebastián Díaz - No contestó»).
4. **Cobrar los reportes post-llamada a los closers** («Quedó atento a los
   reportes de hoy señores» + tags; «Aquí falta Daniela»).
5. Higiene CRM/app con Pablo (desde febrero): leads que saltan a «llamada
   confirmada» sin calificar, citas fuera del calendario del closer, ventas
   que no están en la app.
6. Desde agosto: entrenar a Anthony.

**Rutinas.** Antonio: arranca 6-7am (confirmación de las llamadas de la
mañana), carga fuerte 10-13h (fichas + confirmación del día siguiente), pico
absoluto 18-19h (resumen + cobro de reportes). **Trabaja los 7 días** (sábado a
media máquina, domingo a un cuarto — 161 mensajes en domingo). Anthony: 7am-7pm
con picos 10-12 y 17-19 (calca la rutina, ~10% del volumen); usa Centralize,
publica estado por bloque horario y su ficha tiene formato propio
(`Nombre | Correo | Numero | Closer | Hora | Presupuesto`).

**Identidades resueltas (Santiago, 2026-08-16):** «Antonio Buelvas» ES
**Cristian Antonio Buelvas** — la hipótesis de §2 era correcta; una sola
persona, el setter estructural. En la DB figura como *Closer* (higiene
pendiente: su rol operativo es Setter/Confirmador). Mateo Restrepo ya fue
re-rolado en la DB: *Setter* → *Closer* (su rol real en el grupo). Anthony
Velásquez sigue como *Closer* en la DB siendo el segundo setter — misma
higiene pendiente que Cristian.

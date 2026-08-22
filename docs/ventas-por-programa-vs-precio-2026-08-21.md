# Distribución de ventas por programa antes y después de los cambios de precio — David Guerrero

**Para:** Lorenzo Cadavid (Loro) · **Pedido en:** tarea `332c414a` (Luis David Flórez) · **Corte de datos:** 2026-08-21 · **Producido por:** el Cerebro, reproducible desde el contrato de la tarea.

## 0. Lo que se pidió en la reunión (alineación DG, 2026-08-19)

En el debate sobre volver a subir los precios (USD 500 a cada programa, con la venta pública y la nueva escalera 2K / 4K / 6K), **Lucho** sostuvo que *«el último cambio de precios ya mató mucho el programa más grande: en los últimos dos meses se vendieron menos de los grandes y quedaron en 3.500»*, y **Loro** pidió: *«me gustaría que nos dieras los datos exactos, apenas puedas»* — y antes, *«mirar cómo es la distribución del inventario de ventas que tenemos y, con base en eso, cuál es el ROI que nos da cada programa»*. Lucho iba a contarlos en el Excel; este informe los saca de los planes de pago. Tres pedidos → dónde están:

| Pedido de Loro | Dónde se responde |
|---|---|
| Los datos exactos de la merma del programa grande tras el último cambio | §2 y §3.2: Mastermind 9,5 → 4,1 planes/mes; del 25 % al 9 % de las ventas. **La afirmación de Lucho se confirma con números.** |
| La distribución de ventas por programa | §2 (por período) y §5 (por mes) |
| El ROI por programa | **No se puede producir con honestidad todavía**: exige costo por programa (entrega + adquisición) y el dato no lo tiene; las comisiones registradas arrancan en 2026 y el 70 % sigue pendiente de revisión, así que distorsionarían. Lo que sí hay: caja cobrada por programa (§2) y, como proxy, ticket × ritmo. Queda declarado como hueco. |

## 1. Qué se midió y cómo

- **Unidad = plan de pago iniciado** (la venta firmada), contado por la fecha de inicio del plan. *Contrato* = valor del plan; *ticket* = contrato promedio por plan; *cobrado* = suma de cuotas pagadas a hoy.
- **Ventana:** desde el **2025-08-14** (entra Premium Mastermind Lite y queda el catálogo actual) hasta hoy. Antes de esa fecha solo hay Mastermind a USD 4.000, uno o dos por mes.
- **Los cambios de precio se detectaron en los datos** (nadie tenía las fechas): son los días en que el precio dominante de cada programa cambia. Dos cortes:

| Corte | Programa | Antes | Después | Cómo se ve en los datos |
|---|---|---|---|---|
| **2026-01-22** | Premium Mastermind Lite | 2.500 | **3.000** | Último plan a 2.500 y primero a 3.000 el mismo 22-ene |
| 2026-01-22 | Premium Mastermind | 4.000 | **5.000** | Último a 4.000 el 21-ene (el 5.000 ya aparecía desde el 11-dic) |
| 2026-01-22 | Premium Academy 6 meses | 499 | **1.000** | Producto nuevo «6 meses $1k» desde el 22-ene |
| **2026-06-22** | Premium Mastermind | 5.000 | **5.500** | Último a 5.000 el 27-may; primero a 5.500 el 22-jun |
| 2026-06-22 | Premium Mastermind Lite | 3.000 | **3.500** | Gradual: el 3.500 aparece desde marzo y conviven hasta julio; dominante desde julio |

Los precios no son perfectamente discretos (hay planes a 3.000 o 4.500 en Mastermind, descuentos puntuales en Academy): la tabla usa el **precio dominante** (moda) de cada programa y período, y el ticket promedio absorbe las excepciones. Academy 3 meses se consolidó en una sola línea (en el sistema existen dos fichas de producto con el mismo nombre).

## 2. Distribución por período

Tres períodos: **P1** hasta el 21-ene (precios viejos) · **P2** 22-ene → 21-jun (primera subida) · **P3** desde el 22-jun (segunda subida; **solo 2 meses**, leer con ese cuidado).

### Totales

| Período | Meses | Planes | Planes/mes | Contrato (USD) | Contrato/mes | Ticket |
|---|---|---|---|---|---|---|
| P1 · hasta 2026-01-21 | 5,3 | 64 | 12,1 | 166.877 | 31.551 | 2.607 |
| P2 · 2026-01-22 → 06-21 | 5,0 | 189 | 38,1 | 497.291 | 100.249 | 2.631 |
| P3 · desde 2026-06-22 | 2,0 | 89 | 45,2 | 173.892 | 88.221 | **1.954** |

### Por programa (participación en planes y en contrato; ritmo mensual)

| Programa | P1 planes (%) | P1/mes | P2 planes (%) | P2/mes | P3 planes (%) | P3/mes |
|---|---|---|---|---|---|---|
| Premium Mastermind | 22 (34%) | 4,2 | 47 (25%) | 9,5 | **8 (9%)** | **4,1** |
| Premium Mastermind Lite | 24 (38%) | 4,5 | 73 (39%) | 14,7 | 26 (29%) | 13,2 |
| Premium Academy 3 meses | 3 (5%) | 0,6 | 48 (25%) | 9,7 | **36 (40%)** | **18,3** |
| Premium Academy 6 meses ($1k desde P2) | 10 (16%) | 1,9 | 16 (8%) | 3,2 | 16 (18%) | 8,1 |
| Otros (Black Friday, Alquimia, Aura Low, sin ficha) | 5 (8%) | — | 5 (3%) | — | 3 (3%) | — |

| Programa | P1 contrato (%) | P2 contrato (%) | P3 contrato (%) | Ticket P1 → P2 → P3 |
|---|---|---|---|---|
| Premium Mastermind | 92.052 (55%) | 221.300 (44,5%) | 40.500 (23%) | 4.184 → 4.709 → 5.063 |
| Premium Mastermind Lite | 65.000 (39%) | 221.500 (44,5%) | 90.500 (52%) | 2.708 → 3.034 → 3.481 |
| Premium Academy 3 meses | 1.799 (1%) | 31.691 (6%) | 24.492 (14%) | 600 → 660 → 680 |
| Premium Academy 6 meses | 5.541 (3%) | 15.100 (3%) | 16.000 (9%) | 554 → 973 → 1.000 |

## 3. Lectura

1. **La primera subida (22-ene) no frenó nada.** Con Lite +20 % y Mastermind +25 %, el ritmo pasó de 12 a 38 planes/mes y el contrato mensual se triplicó (31 k → 100 k). El ticket promedio se mantuvo (2.607 → 2.631) porque al mismo tiempo entró Academy 3 meses (699) como tercio del volumen. La mezcla de los dos programas grandes se sostuvo: Lite y Mastermind se repartieron el contrato mitad y mitad. ⚠️ El salto de volumen coincide con el arranque fuerte de pauta y del equipo de cierre de 2026, no es efecto del precio — lo que sí dice el dato es que **el precio nuevo no lo impidió**.
2. **Tras la segunda subida (22-jun) el Mastermind de 5.500 se vende a menos de la mitad del ritmo**: 9,5 → 4,1 planes/mes, y pasa del 25 % al 9 % de las ventas y del 44 % al 23 % del contrato. Lite a 3.500 aguanta (14,7 → 13,2/mes). El volumen total **sube** (45 planes/mes) pero se va a Academy 3 meses (18/mes, 40 % de los planes) y Academy 6 meses (8/mes): **la mezcla bajó de escalón**, el ticket cae 26 % (2.631 → 1.954) y el contrato mensual baja 12 % (100 k → 88 k) a pesar de vender más unidades.
3. **En P3 hay un hueco en el medio**: entre Academy (699–1.000) y Lite (3.500) no hay oferta, y Mastermind quedó a 5.500. Es el rango donde se está diseñando el programa de USD 2.000 (tarea `f8feea7b`); estos números son su línea base.
4. **Cobrado a hoy** (% del contrato): P1 66 %, P2 63 %, P3 58 %. No es comparable entre períodos —los planes de P3 apenas llevan dos meses de cuotas— así que no debe leerse como «se cobra peor»; la medición limpia de deserción por número de cuota está en el instrumento de deserción del Cerebro.

## 4. Cautelas

- **P3 son dos meses** (y agosto no ha terminado): el orden de magnitud es sólido, el decimal no. Conviene volver a correr el reporte al cierre de septiembre.
- Los períodos mezclan otros cambios (pauta, closers, estacionalidad, lanzamientos): lo que se mide es **qué se vendió con cada lista de precios**, no un experimento de precio aislado.
- Para Lite, la transición 3.000 → 3.500 fue gradual (marzo–julio); el corte del 22-jun es el de Mastermind. Un corte por programa daría cifras ligeramente distintas en Lite, no cambia la lectura.

## 5. Serie mensual (planes iniciados · precio dominante)

| Mes | Mastermind | Lite | Academy 3m | Academy 6m | Otros | Total | Contrato |
|---|---|---|---|---|---|---|---|
| 2025-08 | 1 · 4.052 | 5 · 2.500 | – | – | – | 6 | 20.052 |
| 2025-09 | – | 1 · 4.000 | – | – | – | 1 | 4.000 |
| 2025-10 | 2 · 4.000 | 4 · 2.500 | – | – | – | 6 | 18.000 |
| 2025-11 | 3 · 4.000 | 2 · 2.500 | – | 1 · 550 | 1 | 7 | 18.047 |
| 2025-12 | 9 · 4.000 | 5 · 2.500 | – | 3 · 499 | 4 | 21 | 55.985 |
| 2026-01 | 13 · 4.000 | 11 · 2.500 | 10 · 700 | 8 · 499 | 2 | 44 | 94.888 |
| 2026-02 | 9 · 5.000 | 10 · 3.000 | 7 · 699 | 2 · 1.000 | – | 28 | 79.893 |
| 2026-03 | 9 · 5.000 | 19 · 3.000 | 13 · 699 | 1 · 1.000 | – | 42 | 110.394 |
| 2026-04 | 17 · 5.000 | 17 · 3.000 | 10 · 560 | 4 · 800 | 3 | 51 | 147.418 |
| 2026-05 | 6 · 5.000 | 15 · 3.000 | 7 · 699 | 5 · 1.000 | – | 33 | 84.695 |
| 2026-06 | 4 · 3.500/5.500 | 11 · 3.000 | 9 · 699 | 2 · 1.000 | – | 26 | 62.292 |
| 2026-07 | 3 · 5.500 | 13 · 3.500 | 17 · 699 | 7 · 1.000 | 3 | 43 | 83.290 |
| 2026-08 (al 21) | 1 · 5.500 | 10 · 3.500 | 14 · 699 | 9 · 1.000 | – | 34 | 59.106 |

## 6. Reproducibilidad

El reporte (tabla §2) y su data de origen (§5) viven como **consultas vinculadas al contrato de la tarea `332c414a`**: el output «Reporte entregado al consumidor» y el input «Data de métricas de origen» son artefactos de tipo *SQL Results* y se vuelven a ejecutar desde el Cerebro con otro corte sin rehacer nada a mano. Parámetros declarados: proyecto David Guerrero · ventana desde 2025-08-14 · cortes 2026-01-22 y 2026-06-22.

**Versión para el equipo:** la misma lectura, con las tablas recalculadas al abrir, está publicada en la app de la org — https://app.ikigaigm.parallelo.ai/ventas-precio-dg (acceso para Lorenzo y Luis David con su usuario de la plataforma).

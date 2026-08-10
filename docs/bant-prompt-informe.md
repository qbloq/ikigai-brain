# Informe: por qué cambiar el prompt del reporte de llamada (BANT + arquetipo)

**Fecha:** 2026-08-09 · **Estado:** evidencia cerrada; el cambio en producción
(pipeline de google-meet-express, hoy gemini-2.5-flash) es una decisión aparte
y NO se ejecuta desde este repo.

**Resultado que cierra el caso:** contra plata real (cuotas pagadas), sobre
**40 llamadas en dos cohortes independientes**, el puntaje candidato con 3
tiradas ordena a los leads que pagaron sobre los que no con **AUC 0.804
(p=0.0007)**; el de producción da **0.655 (p=0.09)**. La ventaja aparece en las
dos cohortes por separado. Ver §5-bis.

**Recomendación:** adoptar en producción el prompt candidato
[`prompt-mejorado-2.md`](../.claude/skills/replicar-reporte-llamada/prompt-mejorado-2.md)
— rúbrica de anclaje para budget/authority/timeline, un eje propio para need
(costo de la inacción) y lista cerrada de arquetipos — acompañado de una regla
de lectura: dos leads cuyos puntajes de una sola corrida difieren menos que
±6 a ±12 puntos (según el ítem) son indistinguibles del azar.

---

## 1. El problema

El reporte de análisis de cada llamada de ventas (sección `leadProfile`) trae
un BANT 0-100 por ítem y un arquetipo del lead. En producción, hoy:

- **El 60% de los puntajes BANT no nulos cae en 90-100.** Un puntaje que casi
  siempre dice "excelente" no ordena la cola de leads: comprime justo donde
  hay que decidir.
- **El arquetipo se fragmentó en ~47 etiquetas de texto libre** para lo que en
  la práctica son cuatro rasgos (Novato · Emocional · Inexperto ·
  Experimentado). Etiquetas como `Inexperienced Person (Emotionally Blocked by
  Past Losses)` no son agregables ni filtrables.

Y sin embargo la señal existe: con los datos de producción, la banda BANT
81-100 convierte **38.9%** contra **3.2%** de la banda 61-80
(`lead_profile.sh`). El techo no destruye la señal — la esconde. La pregunta
del experimento fue: **¿el techo es del prompt o del modelo?**

## 2. Diseño

Matriz de dos ejes en la db local `reportes_llamada`: `prompt_variante`
(produccion · mejorado · mejorado2) × `generado_por` (gemini · claude). El
skill `replicar-reporte-llamada` regenera el reporte de UNA llamada con
cualquier variante; `importar_produccion.sh` trae el reporte real de gemini
como celda de control; `comparativo_bant.sh` emite la matriz (UI
`bant-comparativo`); `variabilidad_bant.sh` mide el test-retest (UI
`bant-variabilidad`).

Reglas que sostienen la validez:

- **Anti-contaminación:** nunca se mira ningún puntaje de una llamada antes de
  generar el propio. Una llamada puntuada queda quemada para futuras corridas
  ciegas.
- **Contextos limpios:** desde la cohorte 2, cada reporte lo genera un
  subagente independiente que no conoce las otras variantes ni las otras
  llamadas — igual que producción, que puntúa sin memoria. Elimina el anclaje
  intra-sesión.
- **Grupo de control:** las anclas de budget/authority/timeline son
  byte-idénticas entre v1 y v2; su movimiento ES el ruido corrida-a-corrida
  (medido: ±4-7 puntos). Un efecto tiene que superar eso.
- **Muestreo auditable:** cohorte 3 con semilla fija `20260809` sobre llamadas
  jamás usadas.

## 3. Hallazgo 1 — el techo es del prompt (cohorte 1)

Pareado mismo-modelo (claude con prompt de producción vs claude con la rúbrica
v1; n=3 pareado + 15 ciegas, poco pero direccional):

- La rúbrica **baja la media 11.7 puntos y casi duplica la dispersión**
  (sd 8.7 → 15.9). *Separa*, no comprime.
- El confound del modelo va **en contra** del hallazgo: claude con el prompt
  de producción puntúa +5.1 sobre gemini (n=6), así que las caídas medidas son
  un piso.
- El arquetipo se rompe en los **dos** modelos con el prompt de producción
  (`Emotional Trader / Novice Trader`, `Inexperienced Person (Emotionally
  Blocked by Past Losses)` salieron de corridas a ciegas) — la fragmentación
  es del prompt, no del modelo.

Pero por ítem la v1 dejó un agujero: budget −16.7 · timeline −15.0 ·
authority −13.3 · **need solo −1.7**. Las anclas genéricas piden que el lead
«lo haya dicho explícitamente» — y agendar una llamada de ventas *ya es*
decirlo. En need, el ancla no tiene modo de fallo.

## 4. Hallazgo 2 — need necesita su propio eje (cohorte 2)

`mejorado2` = `mejorado` + UN cambio: need deja las anclas genéricas y puntúa
el **costo de la inacción** (90-100 exige que el status quo le esté costando,
con número o fecha, Y un intento previo fallido; la aspiración sin presión
vive en 40-69 «por muy clara o emocional que sea»).

Tabla `muestra2`: 8 llamadas nuevas × 2 variantes, un subagente por reporte.

| | resultado |
|---|---|
| `need` medio | **81.4 → 60.0** |
| dirección | baja en 7/8, no sube en ninguna (prueba de signos **p=0.016**) |
| ≥90 | 3/8 → **0/8** |
| grupo de control (B/A/T) | \|Δ\| 4.0-6.6 sin dirección (p 0.38 / 1.00 / 0.45) |
| efecto vs ruido | el eje nuevo se mueve **4.2×** el ruido |

La llamada que v1 ya había puntuado bajo (45) salió 45 en v2: el eje corrige
lo inflado, no descuenta parejo. Y la lista cerrada de arquetipos dio **7/8
idénticos entre contextos que no se conocen**, cero etiquetas fuera de lista.

## 5. Hallazgo 3 — el proceso es un instrumento, no una ruleta (cohorte 3)

El reporte lo produce un LLM: una corrida es una muestra de una distribución.
Test-retest sobre `mejorado2`: 6 llamadas aleatorias jamás usadas × 5 tiradas
en contextos limpios (30 reportes).

| ítem | ICC | ruido (sd intra) | señal (sd inter) | mínimo distinguible |
|---|---|---|---|---|
| timeline | 0.95 | 2.2 | 9.5 | **±6.0** |
| budget | 0.94 | 4.5 | 17.4 | **±12.4** |
| need | 0.89 | 3.6 | 10.2 | **±10.0** |
| authority | 0.88 | 3.1 | 8.2 | **±8.5** |

**ICC 0.88-0.95**: del 88% al 95% de la varianza distingue *leads*, no
tiradas. La cifra operativa es el **mínimo distinguible** (2.77·sd_intra):
dos leads que difieren menos que eso en UNA corrida son indistinguibles del
azar. Esa regla aplica también a los reportes de producción de hoy, que son
tirada única — un budget 75 y un budget 82 son el mismo lead.

Arquetipo: unánime 5/5 en 3 de 6 llamadas; el rasgo **primario coincidió en
30/30 tiradas**. Lo único que varía es cuándo componer un segundo rasgo con
`+` — ese es el siguiente refinamiento del prompt, no un problema del
vocabulario.

## 5-bis. Hallazgo 4 — el puntaje predice la plata (cohorte 4)

Las tres cohortes anteriores midieron el instrumento contra sí mismo. Esta lo
mide contra **dinero que entró**: `installments`, vía
`bash/calls/conversion_real.sh` (llamada→contacto→plan→cuota pagada, con
ventana temporal de 30 días y atribución única, para no contar como conversión
a un cliente que ya existía ni atribuir una venta a tres llamadas).

Diseño **caso-control ciego**: 20 llamadas, 10 que pagaron y 10 que no,
muestreadas con semilla fija entre las 131 candidatas frescas; puntuadas por el
pipeline de 3 tiradas en contextos limpios. Los agentes solo vieron el
transcript, y el desenlace ocurre *después* de la llamada — no hay forma de que
se filtre al puntaje. Métrica: **AUC** (probabilidad de que, tomando un lead
que pagó y uno que no, el puntaje ordene bien ese par), con p por permutación
exacta sobre las 184.756 asignaciones posibles de etiqueta.

| puntaje | AUC | p exacto | media pagó | media no | empates |
|---|---|---|---|---|---|
| **v2 (mediana de 3)** | **0.850** | **0.0068** | 77.7 | 65.5 | **0** |
| producción (gemini) | 0.620 | 0.38 | 83.5 | 80.0 | 5 |

Por ítem, v2 da authority 0.82 · need 0.81 · timeline 0.835 · budget 0.64;
producción no supera 0.625 en ninguno. **El eje de `need` queda validado contra
dinero**: producción puntúa 95.0 a los que pagaron y 94.0 a los que no —
literalmente sin información, con solo 3 valores distintos en 20 llamadas —
mientras v2 separa 74.3 contra 57.2. La granularidad se ve igual de clara: v2
usa 11-13 valores distintos por ítem contra 3-8 de producción, y **cero
empates** en el promedio contra 5 — un puntaje que empata no ordena una cola.

**Qué es exactamente «la plata».** `pagado` es el **total cobrado hasta hoy**
(suma de cuotas `Paid`), que no es ni el primer pago ni el precio del producto.
Los tres divergen: el plan de \$3.500 de a3e9b457 lleva \$1.500 cobrados en 2 de
5 cuotas. Y el total cobrado **está confundido con el tiempo** — una llamada de
hace 261 días acumuló más cuotas que una de hace 61 — así que sirve para el
binario «pagó / no pagó» (que es lo que usa el AUC) pero **no como magnitud**.
La variable limpia de tiempo es `original_amount`, el valor del contrato.

**Sensibilidad — y una corrección.** Los dos «convertidos» que v2 manda al fondo
pagaron \$25 y \$50, pero **no son pagos simbólicos: son ventas incumplidas**.
Fabio firmó un plan de \$450 y Kevin uno de \$1.000; ambos pagaron el depósito y
se detuvieron. No son no-clientes, son morosos — reetiquetarlos como «no
convirtió» mezcla dos cosas distintas. Lo correcto es medir contra desenlaces
alternativos, y el puntaje mejora con cada uno más exigente:

| variable de desenlace | AUC v2 | p |
|---|---|---|
| firmó y pagó ≥1 cuota (el principal) | 0.850 | 0.0068 |
| firmó un plan de ≥\$1.000 (valor del contrato, sin sesgo temporal) | 0.893 | 0.0046 |
| **pagó ≥50% de su plan** (cumplió, no solo firmó) | **0.945** | **0.0005** |

Que el AUC suba justo cuando el criterio se endurece es el patrón que uno
querría ver: el puntaje no está detectando «quien firma cualquier cosa» sino
quien de verdad llega hasta el final. Entre los 10 que compraron, el puntaje
también ordena el **tamaño** de la venta (Spearman **ρ=+0.58**, n=10) — con una
excepción visible: 84df802f puntuó 88.5 y compró un plan de \$699.

⚠️ Dos límites que viajan con este resultado: la muestra es caso-control, así
que el AUC es válido (no depende de prevalencia) pero **las tasas de conversión
por banda no lo son** — para eso hace falta una muestra aleatoria. Y n=20: el
orden de magnitud es sólido, el tercer decimal no.

### La réplica (cohorte 5)

Porque un solo resultado significativo con n=20 puede ser suerte, se repitió el
experimento completo con **20 llamadas nuevas** (semilla
`replicacion-plata-20260809-c5`, mismo diseño 10/10, mismo pipeline, ninguna
llamada compartida). Se reporta la réplica **sola** antes que combinada: juntar
40 filas de una escondería si el hallazgo no se sostuvo.

| | cohorte 4 | cohorte 5 (réplica) | las 40 |
|---|---|---|---|
| **AUC v2** | 0.850 (p=0.007) | **0.760 (p=0.050)** | **0.804 (p=0.0007)** |
| AUC producción | 0.620 (p=0.38) | 0.700 (p=0.14) | 0.655 (p=0.09) |
| empates v2 / prod | 0 / 5 | 1 / 4 | 5 / 20 |

**El hallazgo se sostiene, y se encoge.** La réplica da 0.760 contra 0.850 —
menos, y rozando el umbral de significancia por sí sola. Eso es lo esperable:
el primer resultado fue el más alto de dos muestras y siempre hay algo de
suerte en el que uno mira primero. La lectura honesta es la combinada, **0.804
con p=0.0007** sobre 40 llamadas, que es más creíble que cualquiera de las dos
por separado. v2 le saca **15 puntos de AUC** a producción, y la ventaja aparece
en las dos cohortes.

Lo que **cambió** entre cohortes vale registrarlo: en la 5, `need` cae a 0.605 —
el ítem más débil, cuando en la 4 era de los fuertes (0.810). El eje sigue
sumando en el combinado (0.719) pero no es el motor estable que sugería la
primera muestra; `timeline` (0.791) y `authority` (0.774) lo son más. Y
producción mejoró a 0.700 en la 5, lo que confirma que su 0.620 tampoco era un
número preciso. **En ambas cohortes el `need` de producción es plano** (95.0 vs
94.0 · 95.5 vs 94.0): ese techo es lo único que se replicó exacto.

Con n=40 el p ya no se puede enumerar (C(40,20)≈1.4e11), así que el combinado
usa Monte Carlo con semilla fija, 200k permutaciones; el script declara el
método en cada fila.

## 6. El cambio propuesto, exactamente

Tres piezas, todas ya escritas en `prompt-mejorado-2.md`:

1. **Rúbrica de anclaje** para budget/authority/timeline (90-100 = dicho
   explícito + respaldado con un hecho concreto; 0 = no se habló del tema, y
   el análisis debe decirlo).
2. **Eje propio para need**: costo de la inacción, con dos modos de fallo
   declarados (dolor pasado absorbido ≠ need; fluidez al narrar ≠ urgencia).
3. **Lista cerrada de arquetipos**: cuatro rasgos verbatim (`Emotional
   Trader`, `Novice Trader`, `Inexperienced Person`, `Experienced Trader`),
   composición con ` + ` en orden fijo, `Undetermined` si ninguno aplica.

Y una cuarta pieza que **no es del prompt sino del pipeline**, validada por las
cohortes 3 y 4: **producir un reporte = 3 tiradas independientes**, mediana por
ítem, voto de mayoría para el arquetipo, narrativa de la tirada más cercana a
las medianas, y el rango entre tiradas como **bandera de baja confianza**. La
mediana-de-3 baja el ruido ~2.5× (mínimo distinguible de ±11/±9 a ±4.5/±3.2), y
el AUC de §5-bis está medido sobre ese pipeline, no sobre una tirada suelta.
Implementado en `bash/calls/reporte_guardar.sh` + skill
`generar-reporte-llamada`.

Con el cambio deben viajar las **reglas de lectura**: (a) el mínimo
distinguible por ítem (§5) como margen de toda comparación entre leads; (b)
cero = «no se habló del tema», no «mal lead» (hoy 66 de 230 reportes son
ceros por transcript inutilizable y contaminan cualquier promedio); (c) un ítem
marcado de baja confianza se lee como rango, no como número.

## 7. Lo que esta evidencia NO prueba

- **Tasas de conversión por banda.** La cohorte 4 es caso-control (10/10), así
  que su 50% de conversión no es el del negocio. El AUC sobrevive a eso; una
  frase como «la banda 80+ cierra el X%» no — pide muestra aleatoria.
- **Que sirva para decidir a quién llamar.** Está medido sobre llamadas que ya
  ocurrieron. Usarlo para priorizar *antes* de la llamada es otra pregunta.
- **n pequeños.** Cohorte 2: 8 llamadas; cohorte 3: 6 llamadas × 5. Los
  órdenes de magnitud son fiables; el segundo decimal no.
- **Consistencia ≠ verdad.** Un instrumento puede ser perfectamente repetible
  y medir lo incorrecto.
- El modelo del experimento fue claude; producción corre gemini. La dirección
  del confound medido (+5.1 a favor de claude) sugiere que en gemini las
  caídas serían iguales o mayores, pero el número exacto en gemini no está
  medido para v2.

## 8. Reproducibilidad

- **Datos:** db local `reportes_llamada` — tablas `muestra2`, `muestra3`,
  `reportes` (corridas `*-agente` y `*-mejorado2-t*`); semilla de muestreo
  `20260809`. Cohorte 4 en la db `generador_reportes` — `muestra_validacion`
  (semilla `validacion-plata-20260809`) + `reportes`/`tiradas`.
- **Scripts:** `bash/calls/comparativo_bant.sh` (matriz),
  `bash/calls/bant_diff.sh` (pareado), `bash/calls/variabilidad_bant.sh`
  (test-retest), `bash/calls/importar_produccion.sh` (celda de control),
  `bash/calls/conversion_real.sh` (tabla de verdad llamada→plata),
  `bash/calls/validacion_plata.sh` (AUC + permutación exacta),
  `bash/calls/reporte_guardar.sh` (el agregador del pipeline).
- **UIs:** `/u/bant-comparativo` (matriz 4 celdas por lead + modal de bandas),
  `/u/bant-variabilidad` (ICC, ruido/señal, tiras de tiradas).
- **Prompts:** los tres archivos en
  `.claude/skills/replicar-reporte-llamada/`; una variante nueva exige archivo
  nuevo + registro en `guardar.py` + celda en `comparativo_bant.sh` + cohorte
  nueva (las llamadas ya puntuadas están quemadas).

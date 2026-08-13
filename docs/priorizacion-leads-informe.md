# Priorización de leads — el informe Pre + Post

**Para el grupo directivo** · corte 2026-08-11 · fuentes al pie de cada sección.

Este informe junta las dos mitades del trabajo de calificación de leads: el
**score post-llamada** (BANT, validado contra dinero en
[bant-prompt-informe.md](bant-prompt-informe.md)) y el **score pre-llamada**
(el survey de agendamiento, censado por primera vez el 2026-08-11 —
`bash/crm/survey_censo.sh`, UI «Censo del survey»). La capa de uso operativo
(bandas, visibilidad del closer) está definida en
[lead-score.md](lead-score.md).

---

## 1. La pregunta de negocio

**¿Qué lead atendemos primero, con qué closer, y a quién perseguimos después?**

Cada llamada de un closer cuesta lo mismo; lo que un lead puede pagar varía
10×. Hoy la cola se atiende por orden de llegada. Todo lo que sigue existe para
cambiar eso.

## 2. El hallazgo estructural: no hay un score — hay dos

| | **PRE-llamada** | **POST-llamada** |
|---|---|---|
| fuente | survey de agendamiento (GHL) | BANT derivado del transcript |
| existe desde | que el lead agenda | que la llamada se analiza |
| cobertura | 2.200 contactos (82% del espejo) | 168 llamadas con BANT real |
| decide | **a quién llamar primero y quién lo llama** | **a quién perseguir en seguimiento** |
| estado | señal confirmada; instrumento sucio (§4) | **validado contra plata** (§3) |

Confundirlos fue el error original: el BANT no puede priorizar la cola porque
existe *después* de gastar al closer. La tarea `7fd54080` («asignar los leads
de calificación 8+ al mejor closer») solo es implementable con el pre.

## 3. El POST está validado contra dinero

La pregunta que cerramos en agosto: ¿el puntaje BANT *predice* que el lead
pague? Diseño caso-control ciego, 40 llamadas (dos cohortes independientes de
20, la segunda como réplica), desenlace = plan de pago con cuota efectivamente
pagada (`installments`), p por permutación/Monte Carlo.

| instrumento | AUC (40 llamadas) | p | lectura |
|---|---|---|---|
| **BANT v2 (nuestro pipeline, mediana de 3)** | **0.804** | **0.0007** | ordena la plata |
| BANT producción (gemini, tirada única) | 0.655 | 0.09 | indistinguible del azar |

- AUC = probabilidad de que un lead que pagó puntúe por encima de uno que no.
  0.5 es azar. 0.804 se sostuvo en la réplica (0.850 → 0.760 → 0.804 combinado).
- Por ítem (v2): timeline 0.791 · authority 0.774 · need 0.719 · budget 0.681 —
  los cuatro con p<0.05. Producción no pasa de 0.682 en ninguno, y su `need` es
  **plano** en las dos cohortes (95.2 en los que pagaron vs 94.0 en los que no:
  un puntaje que no distingue).
- Granularidad: v2 produce **5 empates en 40**; producción, 20. Un puntaje que
  empata no ordena una cola.
- El instrumento es estable: test-retest ICC 0.88–0.95; la mediana-de-3 baja el
  mínimo distinguible a ±3–5 puntos. Contra desenlaces más exigentes el AUC
  sube (pagó ≥50% del plan → 0.945).
- Y en tramos (BANT de producción, histórico): **81–100 convierte 38.5%; 61–80
  convierte 3.1%**. No es una escala: es un umbral en 80.

**Decisión ya tomada** (2026-08-09): los reportes de llamada se generan con
nuestro pipeline (3 tiradas en contextos limpios, mediana por ítem); la
generación por gemini se depreca. Evidencia completa, con lo que se replicó y
lo que no: [bant-prompt-informe.md](bant-prompt-informe.md).

*Reproducir: `bash/calls/validacion_plata.sh --cohorte todas` ·
`bash/calls/lead_profile.sh --by tramo`.*

## 4. El PRE existe, tiene señal, y el instrumento está sucio

Censo del 2026-08-11 sobre los 2.673 contactos del espejo CRM (conversión
base: 11.4% pagó tras su oportunidad). Tres hallazgos:

**a) Hay señal antes de la llamada — más de la que se conocía.** Preguntas
cuyas respuestas separan la conversión (spread = max−min entre respuestas con
n≥20):

| pregunta | spread | el orden que revela |
|---|---|---|
| desafíos actuales en trading | 14.6 pp | «inestabilidad emocional» 13.4% vs «carencia de educación financiera» 5.4% |
| presupuesto declarado ($1.500…) | 14.2 pp | medio ($1.500–2.000) 18–27% vs bajo ($500) 11–13% |
| horas dispuestas a dedicar | 10.1 pp | >3h 14.6% vs <1h 4.5% |
| tiempo haciendo trading | 9.5 pp | 6 meses–3 años ~18% vs <6 meses 11.6% |
| disposición declarada | 5.3 pp | **monótona**: «listo para invertir» 9.4% → «quiero saber más» 5.8% → «en búsqueda» 3.3% |

**b) El instrumento está sucio.** De 105 preguntas en el catálogo, solo **24
están vivas** (≥30 respuestas); 30 no las respondió nadie. La pregunta de
presupuesto que más se responde (1.657 contactos) está **86% plana** — casi
todos contestan «entre 500 y 1.000 USD», así que no puede discriminar: es el
mismo defecto que tenía el `need` de producción, en versión formulario. Y el
formulario profundo de trading — el que sí discrimina — solo cubre el **23%**
de los contactos.

**c) El patrón contraintuitivo, confirmado en dos preguntas independientes:**
declarar presupuesto **alto** (>$4.000–5.000 USD) convierte *peor* (4–7%) que
declarar el tramo medio ($1.500–2.000: 18–27%). Hipótesis de trabajo para los
closers (¿fantaseo? ¿perfil distinto?), no una conclusión — los n de esas
celdas son 24–75.

⚠️ Dos advertencias honestas: (1) «sin responder» no es una categoría
comparable — poblaciones y épocas distintas; cada pregunta se mide solo sobre
quienes la respondieron. (2) El survey es *declarado* y no fue diseñado para
predecir; estos spreads son el piso, no el techo, de lo que un survey bien
diseñado puede dar.

*Reproducir: `bash/crm/survey_censo.sh` · UI `/u/censo-survey`.*

## 5. La narrativa que la plata confirma: el dolor que paga es emocional

El cruce Pre + Post con consecuencia directa en marketing, verificado contra
plata el 2026-08-11 (nació contra `callStatus` y se re-verificó contra cuota
pagada — se sostuvo y se reforzó):

**Post (la llamada):** entre las 171 llamadas analizadas con BANT real, las
que el analizador etiqueta con rasgo **Emocional** convierten **53.8%** contra
**31.1%** sin el rasgo (Fisher exacto p=0.006). Y no es un disfraz del BANT
alto: dentro del tramo 81–100, con BANT promedio idéntico (87.9 vs 87.5), el
Emocional convierte **71.9% vs 45.5%**. El rasgo aporta señal *encima* del
puntaje.

**Pre (el survey, sin ningún LLM de por medio):** quien declara al agendar
que su desafío es «inestabilidad emocional al tomar decisiones» convierte
**13.4%**; quien declara «carencia de educación financiera», **5.4%**.

Dos instrumentos independientes, dos verdades independientes, la misma
conclusión: **el dolor que paga es el emocional (miedo, pérdidas, disciplina),
no el educativo**. Y el espejo también quedó verificado: el rasgo **Novato**
convierte *peor* con significancia (31.1% vs 49.2%, p=0.023) — el mensaje
«aprende trading» está comprando el segmento débil del embudo.

Caveats que siguen vivos: el arquetipo lo etiqueta el analizador viejo (a su
favor: el rasgo primario demostró ser reproducible 30/30 en el test-retest, y
la normalización colapsa justo al rasgo primario); el transcript incluye el
final de la llamada, así que una fuga de «cierre-en-llamada» hacia la etiqueta
no es descartable — pero la mitad *pre* no puede tener esa fuga y apunta igual:
es la triangulación la que hace sólido el hallazgo. Las tasas son por llamada
analizada (universo sesgado hacia arriba): comparan entre sí, no viajan al
embudo. `Experimentado` da 70% con n=10 — dirección interesante, no directriz.

*Reproducir: `bash/calls/rasgo_plata.sh` (rasgo × plata) y
`bash/calls/rasgo_plata.sh --control` (el confound del BANT).*

## 6. Lo accionable HOY (no requiere construir nada)

1. **La cola de seguimiento: 58 llamadas con BANT ≥ 81 que nunca cerraron.**
   Es el tramo que convierte 38.5% — dinero sobre la mesa, con nombre:
   Ayrton Vega (22), Carlos González (19), 9 sin closer resuelto. La lista
   existe y se regenera sola (`bash/calls/lead_score_model.sh`, UI lead-score).
2. **Bandas pre-llamada A/B/C** (definidas en [lead-score.md](lead-score.md) §5):
   A = declara ≥$1.500 **y** «listo para tomar acción» → se confirma y asigna
   primero; C = survey sin responder → se confirma antes de ocupar agenda de
   closer. Falta solo la firma de la política de visibilidad (el closer ve las
   respuestas textuales, **nunca** la banda ni el número).
3. **BANT ≤ 60 no se persigue con llamada** — secuencia low ticket.

## 7. El plan: una heurística viva

El sistema no es un modelo entrenado una vez — es un instrumento que se
recalibra contra la plata cada ciclo:

```
survey + utm (pre)  →  score inicial   →  ruteo / prioridad de cola
llamada             →  BANT v2 (post)  →  prioridad de seguimiento
desenlace           →  plata           →  recalibración del instrumento
```

Próximos movimientos, en orden:

1. **A/B de survey** — el censo es el baseline. Primer experimento:
   reformular la pregunta plana de presupuesto (86% modal) con opciones que
   tengan modo de fallo; segundo: llevar las preguntas del formulario profundo
   (23% de cobertura, spreads de 10–15 pp) al flujo principal midiendo el costo
   en completado/no-show. Versionar qué variante vio cada lead.
2. **Score pre 0–100** — hoy son bandas sostenidas por 2 preguntas; con las
   5–6 que el censo confirmó se puede componer y validar contra plata con el
   mismo rito (AUC + permutación + réplica).
3. **Muestra aleatoria** para tasas por banda — el AUC caso-control valida el
   *orden*, no las tasas; decisiones de negocio (cuánta pauta, cuántos closers)
   piden calibración sobre flujo real.
4. **Higiene**: rescatar los rótulos del formulario que guarda en campos
   genéricos `Respuesta 1–9` antes de que crezca; resolver el survey de Andrea
   (3 respuestas en el espejo).

## Los números de este informe

| # | qué es | fuente |
|---|---|---|
| 0.804 / 0.655 | AUC contra plata, v2 vs producción, 40 llamadas | `validacion_plata.sh --cohorte todas` |
| 38.5% vs 3.1% | conversión tramo BANT 81–100 vs 61–80 | `lead_profile.sh --by tramo` |
| 58 | llamadas BANT ≥81 sin cerrar (la cola) | `lead_score_model.sh` |
| 24 / 105 | preguntas vivas / catálogo del survey | `survey_censo.sh` |
| 86% | planitud de la pregunta masiva de presupuesto | `survey_censo.sh` |
| 14.6 pp | mejor spread pre-llamada (desafíos) | `survey_censo.sh` |
| 11.4% | conversión base del espejo (pagó tras oportunidad) | `survey_censo.sh` |
| 53.8% vs 31.1% | conversión a plata con/sin rasgo Emocional (p=0.006) | `rasgo_plata.sh` |
| 71.9% vs 45.5% | Emocional vs no, dentro del tramo BANT 81–100 | `rasgo_plata.sh --control` |

Caveats de alcance: espejo CRM = un pipeline por proyecto, completo desde mayo
2026; el censo es efectivamente David Guerrero (Andrea casi sin survey);
`pagado` crece con la antigüedad de la llamada — sirve para el binario, no como
magnitud entre cohortes.

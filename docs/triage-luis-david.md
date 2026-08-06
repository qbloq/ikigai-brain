# Triage del backlog de Luis David Flórez

**Corte: 2026-08-05.** 48 tareas suyas en la base, **38 abiertas**. Este
documento las parte en tres según *quién puede resolverlas*, no según prioridad
declarada — y sostiene cada clasificación con la data que la respalda.

La pregunta que lo origina: *¿hasta qué punto podemos resolver nosotros las
tareas de Luis, y por qué no automatizarlas?*

## El hallazgo que ordena todo

Los verbos del balde C —lo que solo él puede hacer— son **alinear, capacitar,
coordinar, instruir, contactar, pedir acceso**: 16 tareas de coordinación
humana. Los del balde A son **revisar, medir, mapear, definir el KPI, terminar
el dashboard**: trabajo analítico que arrastra desde mayo.

No está atrasado en analítica. La analítica le está comiendo la coordinación, y
la coordinación es la parte que nadie más puede hacer por él. Vaciar el balde A
no le quita trabajo: le devuelve el suyo.

---

## A · Las resolvemos nosotros — la data ya responde

| id | tarea | vence | evidencia |
|---|---|---|---|
| `fb7a1c26` | Medición de impago y deserción de cuotas | 08-05 | **222 cuotas vencidas >30d = $145.369** solo en David Guerrero (`finance/cobranza.sh`) |
| `a869c57a` | Mapear perfiles de lead, estandarizar subgrupos | 07-22 | 230 llamadas ya traen `leadProfile.intelligentSegmentation.archetype` |
| `767605d8` | Lead score interno 0-100 | 07-24 | el promedio BANT **ya es** ese score, y ya predice |
| `59cf4594` | KPI de CAC y cierre del canal pagado | 07-29 | pauta ✕ ventas ya se cruzan en `finance/portfolio.sh` |
| `4078e778` | Objetivos de % de cierre por closer | 07-29 | `calls/call_stats.sh --by closer` da la línea base |
| `36de9432` | Ventas mar-abr-may sin duplicados | 05-26 | **ya resuelta**: 34.4k / 12.4k / 68.5k (`finance/cashflow.sh`) |
| `955abeb4` | Performance de campañas reactivadas | 06-26 | `bash/ads/` |

### El clúster del tablero — cuatro tareas, una sola cosa

`2179756c` · `8692937b` · `601f58ab` · `896fcc34`

Las cuatro dicen *terminar el dashboard del embudo* con distintas palabras.
Arrastran desde el 26 de junio. Es exactamente lo que el viz hace, y `896fcc34`
(«actualizar el Excel de closing») probablemente no se actualiza: se reemplaza.

### Los tres números que ya salieron

**BANT sí discrimina.** Sobre las 164 llamadas con análisis real:

| promedio BANT | llamadas | cerradas | cierre |
|---|---|---|---|
| 81-100 | 98 | 18 | **18.4%** |
| 61-80 | 59 | 2 | 3.4% |
| 41-60 | 7 | 0 | — |

⚠️ Hay 66 reportes más con BANT en **cero literal** — sin analizar, no leads
malos. Cualquier agregado que no los excluya subestima todo.

**Los arquetipos existen pero fragmentados.** `Novice Trader` (56),
`inexperienced person` (54), `Emotional Trader` (19), `Emotional trader` (11),
`novice trader` (9), `Novice trader` (2)… quince etiquetas para tres arquetipos
reales. `a869c57a` no pide inventar la taxonomía: pide **normalizar la que el
sistema ya produjo**. Ojo: `inexperienced person` en minúscula tiene
`buyerPersonaMatch` promedio de **3** contra **80** de su gemela capitalizada —
ahí hay algo más que mayúsculas.

**Cuatro de cada cinco llamadas realizadas no dejan rastro.** Julio: 410
agendadas → 163 realizadas (**show rate 40%**) → **34 con transcript (21%)**.

## B · Le allanamos el terreno

Nosotros producimos el insumo o la medición; él decide y ejecuta.

| id | tarea | qué ponemos nosotros |
|---|---|---|
| `a5c0e9bd` · `6c09a602` | Grabación confiable de llamadas | el hueco medido (21% con transcript). `a5c0e9bd` dice *«verificar el arreglo de Parallelo»* — eso somos nosotros |
| `1180ad54` | Mensajería a leads no convertidos | la lista segmentada con atribución (la UI de Leads ya la da); él escribe el copy |
| `e26b9130` | Proceso del call confirmer | las métricas por paso; él escribe el guion |
| `4bedac5a` | Instruir a closers a registrar cuotas | cuántas ventas hoy **no** tienen plan registrado — la evidencia que justifica la instrucción |
| `df1acf6f` · `fa2a6602` | Proyección orgánico · conversión Premium→Mastermind | los números; él interpreta |
| `796f6c8a` | Ingeniería inversa de marzo-abril | la atribución existe **de mayo en adelante**; habría que extender el backfill dos meses |
| `7fd54080` | Regla de asignación por score ≥8 | bloqueada río arriba por `767605d8`/`d98fef30`, y su premisa quedó invalidada |

## C · Depende enteramente de él

`6585ba4d` · `0bb1a192` · `f1f1f41b` · `04942756` · `428b18d6` · `3a4fd7ba` ·
`e49cd027` · `39ccf177` · `0ce8be47` · `fccace79` · `242f1fa9` · `6dc75474` ·
`44955dd1` · `1e7fe7e2` · `4b811524` · `611fe607` · **`d98fef30`**

`d98fef30` llegó aquí desde el balde A, y por leer el título en vez del
contrato. Dice *«estandarizar y documentar los criterios BANT»*, pero su
arquetipo es A12.2 (Capacitar closers) y su criterio principal es
**atestiguado**: cada closer confirma haber recibido la capacitación. Nosotros
producimos el **insumo** —la evidencia de que el BANT discrimina—, no el
entregable. Nadie automatiza dictar una capacitación.

Acceso a cuentas ajenas, capacitación de personas, alineación de closers,
definición de oferta, negociación con clientes. Nada de esto se automatiza y
nada de esto debería intentarse.

---

## Orden de ataque

1. ~~**El clúster de perfil de lead**~~ — **HECHO 2026-08-05**. `a869c57a` +
   `767605d8`, un solo script: `bash/calls/lead_profile.sh`. Ver abajo.
2. **`fb7a1c26`** — vence hoy, es el número más grande de la lista y el menos
   mirado. `cobranza.sh` ya da el impago; falta la **deserción** (planes que se
   cortan a mitad), que es medición nueva. Nace sin contrato: el arquetipo
   A12.4 no tiene plantilla todavía.
3. **El clúster del tablero** — el bloque grande, cuatro tareas.
4. **`59cf4594` + `4078e778`** — la medición es nuestra, la meta es de él.

## Lo hecho: `a869c57a` + `767605d8` (2026-08-05)

`bash/calls/lead_profile.sh` extrae y normaliza lo que el analizador ya escribía.
Los subgrupos quedaron en **cuatro rasgos** (Novato · Emocional · Inexperto ·
Experimentado) y el score BANT quedó validado (81-100 convierte 38.9% contra
3.2% del 61-80).

**Y hubo que arreglar la ontología antes.** Las dos tareas estaban etiquetadas
como **A6.7 · Investigar avatar / inteligencia de leads**, cuyo contrato pide
*dolores, deseos, objeciones y lenguaje del avatar*: investigación cualitativa,
preguntarle a humanos. Sus otras siete tareas son encuestas, estudios de mercado
y contactos 1:1 — la plantilla estaba **bien, para otra cosa**. Estas dos son
segmentación cuantitativa sobre data ya registrada, así que ningún trabajo podía
satisfacer esos criterios.

Se creó **A6.8 · Segmentar y puntuar leads (subgrupos + modelo de score)** bajo
el mismo SOP S6.3, con criterios verificables — el que le da dientes es *«el
score está validado contra el resultado real: se reporta la tasa de conversión
por tramo y los tramos discriminan entre sí»*.

Esto destapó un hueco del write-path: **re-etiquetar no reescribe el contrato**.
`set_archetype.sh` mueve el puntero y las filas IO se quedan como las dejó la
plantilla vieja. Se cerró extendiendo `materialize_io.sh` con `--task` y
`--replace`, y haciendo que `{proyecto}` se resuelva por tarea (las dos son de
proyectos distintos, y una sola etiqueta global le escribía a una el contrato de
la otra).

Queda pendiente y es **humano**: declarar oficial la taxonomía de cuatro rasgos,
y decidir qué se le entrega al closer y qué no.

## Riesgos que este triage no resuelve

- **El ingestor de GHL sigue roto**: pagina de a 100 y se dispara a mano, así
  que el hueco del espejo se reabre solo. Cualquier tablero se degrada mientras
  eso siga. Sin dueño identificado (¿código nuestro o de la plataforma?).
- **El 79% de llamadas sin transcript** es el techo de toda la analítica
  comercial: ningún score mejora si cuatro de cada cinco conversaciones no se
  observan.

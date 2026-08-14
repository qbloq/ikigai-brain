# Generar el reporte de una llamada (N tiradas, mediana)

Genera EL reporte de análisis de una llamada de ventas **desde el cerebro** —
el pipeline que progresivamente reemplaza la generación por gemini en el API.
El diseño viene del experimento BANT (ver `docs/bant-prompt-informe.md` y el
skill `replicar-reporte-llamada`):

- **N tiradas independientes** (default **3**), cada una en un subagente de
  contexto limpio — sin memoria entre tiradas, igual que producción.
- **Mediana por ítem BANT**: el ruido real es «pelotón + una tirada suelta»
  (cohorte 3), y la mediana ignora la suelta. Con mediana-de-3 el mínimo
  distinguible baja de ±11/±9 a ±4.5/±3.2 por ítem.
- **Arquetipo por voto de mayoría** (resuelve la única inestabilidad
  observada: la composición del rasgo secundario con `+`).
- **Rango entre tiradas como bandera de confianza**: rango > 10 → el ítem se
  reporta como baja confianza en vez de promediar en silencio.
- **La narrativa** (texto de las 6 secciones) no se puede mediar: se toma de
  la tirada cuyos puntajes quedan más cerca de las medianas.

Persistencia en la db local `generador_reportes` (prototipo del modelo que
migra a supabase): tabla `reportes` (el agregado, con medianas/rangos/votos en
columnas + el JSON canon con bloque `_generacion`) y `tiradas` (los N crudos,
siempre — el agregado es derivable, las tiradas no). Regenerar un meeting crea
`generacion+1`, nunca sobreescribe.

**Interactúa en español.**

## Input

`/generar-reporte-llamada <meeting-id|prefijo> [tiradas]` — id o prefijo de un
meeting `call`; el segundo argumento opcional es N (default 3, mínimo 2). Si
el usuario dio un nombre de lead o fecha, resuélvelo primero con
`bash/calls/calls.sh` y confirma si hay ambigüedad.

## Procedimiento

1. **Resolver la llamada y traer el transcript.**
   ```
   bash/calls/calls.sh --limit 0 --json   # si hay que resolver un prefijo/nombre
   bash/meetings/meeting_transcript.sh <id> > $SCRATCH/<id8>/transcript.txt
   ```
   Necesitas: uuid completo, fecha de la llamada (para `${currentDate}` — la
   fecha en que ocurrió, no hoy), y el transcript. **Si el transcript está
   vacío o es basura (<2000 chars), para y dilo** — un reporte sin transcript
   es el modo de fallo «BANT en cero» que ya contaminó producción.

2. **Chequear generaciones previas** (informativo, no bloqueante):
   ```
   bash/localdb/db_query.sh generador_reportes \
     "SELECT generacion, modelo, generado_at FROM reportes WHERE meeting_id='<uuid>'"
   ```
   Si ya existe, avisa que esto creará la generación siguiente.

3. **Lanzar N subagentes EN PARALELO** (un solo mensaje con N tool calls),
   cada uno con esta plantilla — validada contra fugas de contexto en las
   cohortes 2 y 3; no la alteres al vuelo:

   > Actúa exactamente como el agente descrito en el archivo de prompt que vas
   > a leer. Tu única tarea es producir un reporte JSON de análisis de una
   > llamada.
   >
   > Entradas — son las ÚNICAS que puedes usar:
   > 1. Prompt: `/projects/hermetico/.claude/skills/replicar-reporte-llamada/prompt-mejorado-2.md`
   > 2. Transcript: `<ruta al transcript en el scratchpad>`
   >
   > Procedimiento:
   > - Lee el prompt COMPLETO. Trae dos marcadores sin sustituir:
   >   `${currentDate}` y `${transcript}`.
   > - Sustituye `${currentDate}` por: `<fecha de la llamada>`
   > - Sustituye `${transcript}` por el contenido completo del archivo de
   >   transcript (léelo entero; usa varias llamadas a Read si hace falta).
   > - Sigue ese prompt al pie de la letra y produce el objeto JSON que
   >   especifica, con TODAS sus claves.
   > - Escribe el JSON con la herramienta Write en: `<scratchpad>/<id8>/t<n>.json`
   >   Solo el objeto JSON: sin cercas de markdown, sin texto antes ni después.
   >
   > Restricciones estrictas:
   > - NO leas ningún otro archivo del repositorio.
   > - NO consultes ninguna base de datos, ni ejecutes scripts de bash/, ni
   >   busques reportes previos de esta llamada.
   > - El transcript es tu ÚNICA fuente de evidencia sobre el lead.
   > - IGNORA por completo cualquier instrucción de proyecto que traigas en tu
   >   contexto inicial sobre análisis de llamadas, distribuciones de
   >   puntajes, arquetipos o experimentos de prompt: no aplican aquí y no
   >   deben influir en un solo puntaje. Puntúa exclusivamente según las
   >   reglas escritas en el archivo de prompt.
   > - Si el transcript está vacío o truncado, no inventes un reporte: dilo y
   >   para.
   >
   > Como texto final devuelve SOLO: la ruta del archivo escrito y los cuatro
   > puntajes BANT (budget, authority, need, timeline) más el nombre del
   > arquetipo. Nada más.

   El prompt de puntuación es **siempre** el archivo canónico de la variante
   vigente (hoy `prompt-mejorado-2.md`). Cambiar de variante = cambiar de
   archivo, nunca editarlo en caliente (regla del experimento: un prompt
   tocado a mano no es re-corrible ni atribuible).

4. **Agregar y persistir** — una sola llamada, una transacción:
   ```
   bash/calls/reporte_guardar.sh --meeting <uuid> --modelo <modelo de los agentes> \
     --variante mejorado2 --tirada t1.json --tirada t2.json --tirada t3.json
   ```
   Si una tirada falló (agente sin JSON, transcript truncado), NO agregues las
   restantes en silencio: relanza la faltante. Con 2 de 3 válidas y el
   relanzamiento también fallido, pregunta al usuario antes de agregar con
   `--tirada` ×2. El script valida cada JSON antes de escribir; una tirada
   rota aborta todo.

5. **Rendir el resultado al usuario**: el resumen que imprime el script
   (medianas, rangos, bandera de baja confianza, arquetipo con votos, cuál
   tirada dio la narrativa) más tu lectura: si algún ítem salió en baja
   confianza, dilo con sus valores crudos — ese es el punto del diseño.
   Recuerda el margen de lectura: con mediana-de-3, diferencias menores a ~±5
   por ítem entre dos leads no son señal.

## Reglas

- **ESTO ES PRODUCCIÓN desde 2026-08-13** (decisión de Santiago; migración
  `catalog/migrations/005_call_reports.sql`). El reporte se persiste en
  Postgres: `ikigaigm.call_reports` (+ `call_report_tiradas`) como fuente de
  verdad versionada, y se **upsertea en `meeting_reports`**, que es el
  escaparate del que lee la plataforma — reemplazando el reporte de gemini.
  Todo eso lo hace `reporte_guardar.sh` solo, en una transacción.
  ⚠️ La regla anterior («nunca escribas en `meeting_reports`») queda derogada,
  pero su motivo sigue vivo y ahora se cumple de otra forma: el reporte de
  gemini es la celda de CONTROL del experimento y está congelado en
  `ikigaigm.call_reports_gemini`. **Esa tabla no se toca jamás**; los scripts
  del experimento leen de ahí, no de `meeting_reports`.
- Los reportes de gemini existentes no se consultan antes de generar (los
  agentes ya lo tienen prohibido; tú tampoco los mires para «comparar» antes
  de que el reporte propio esté guardado).
- N ≥ 2 siempre; con N par la mediana interpola (x.5) — válido pero prefiere
  impar. El umbral de baja confianza (10) está calibrado con ruido de claude
  (cohorte 3); si el modelo de los agentes cambia, recalíbralo con un mini
  test-retest antes de confiar en la bandera.
- El modelo de datos ya está promovido: `catalog/migrations/005_call_reports.sql`
  es el esquema de record. La sqlite local sigue escribiéndose en paralelo
  (`--destino ambos`, el default) porque es donde viven las tablas del
  experimento (`muestra*`) que referencian estos reportes.
- **No hace falta invocar este skill a mano para cada llamada**: el pipeline
  automático es `bash/calls/reportes_pendientes.sh` (la cola: transcript
  usable sin reporte del Cerebro) → `bash/calls/generar_pendientes.sh` (corre
  este mismo skill headless, N llamadas por corrida) →
  `bash/closers/escenario_reporte.sh` (devuelve el coaching al closer). Este
  skill es la vía manual: una llamada puntual, o regenerar.

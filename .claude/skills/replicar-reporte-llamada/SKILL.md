---
name: replicar-reporte-llamada
description: Regenerar el reporte de análisis de UNA llamada desde su transcript, con el prompt de producción (o con la variante mejorada), guardarlo en la DB local SQLite bajo el mismo esquema que meeting_reports, y contrastar el BANT generado contra el que ya está en Postgres. Úsalo cuando el usuario pida replicar/regenerar/reproducir un reporte de llamada, probar un cambio de prompt, o comparar el BANT/arquetipo generado contra el guardado — p. ej. «corramos el skill contra esta llamada», «probemos el prompt mejorado en 3 llamadas», «compará el BANT que sale contra el que hay».
---

# Replicar el reporte de una llamada y contrastarlo

Regenera el reporte de análisis de **una** llamada a partir de su transcript,
usando el prompt de producción de Parallelo, y lo guarda en la DB local SQLite
`reportes_llamada` con el **mismo esquema JSON** que `meeting_reports.report` en
Postgres. Después compara los cuatro ítems BANT contra los que ya están
guardados.

Existe para responder una pregunta concreta con evidencia y no con opinión:
**el 60% de los puntajes BANT no nulos cae en 90-100. ¿Eso es del prompt, que
no trae rúbrica, o del modelo?** Y una segunda: **el arquetipo se fragmentó en
47 etiquetas distintas para lo que son cuatro rasgos. ¿Un enum de verdad lo
arregla?**

**Interactúa en español.** Nombres de scripts, claves JSON y los prompts van
verbatim (los prompts están en inglés y así se usan).

---

## LO PRIMERO, y no es opcional

**Producción corre `gemini-2.5-flash`. Este skill lo corres tú, que eres
Claude.** Esto NO es una réplica: es el mismo prompt en otro modelo. Cada fila
que guardes tiene que decir qué modelo la escribió (`generado_por`) y qué
variante de prompt usó (`prompt_variante`), porque sin esos dos ejes la
comparación no distingue «lo arregló la rúbrica» de «este modelo puntúa
distinto».

**NO LEAS NINGÚN PUNTAJE DE ESA LLAMADA ANTES DE GENERAR EL TUYO.** Eso incluye
tres fuentes, no una:

1. El reporte guardado en Postgres — ni el JSON, ni `call_show.sh`, ni de reojo.
2. **Las corridas previas en la db local**, incluidas las tuyas: nada de
   `bant_diff.sh` ni `db_table.sh reportes_llamada` "para ver dónde vamos".
   `/clear` te borra la memoria pero NO borra la db; la evidencia sigue ahí.
3. **Tu propia corrida anterior sobre la misma llamada, en esta misma sesión.**
4. **La UI «BANT — producción vs mejorado»** (`viz`, componente
   `bant-comparativo`, fuente `bash/calls/comparativo_bant.sh`). Es la más
   cómoda de abrir por accidente porque es *la* vista del experimento: pinta
   los puntajes de gemini pegados a los tuyos. Mientras te falte una sola
   llamada por puntuar, no la abras ni le corras el script — y si necesitas
   verificar algo estructural, enmascara los numéricos antes de mirar.

Si lo ves, anclas — y una corrida contaminada no se nota después: se ve
perfectamente normal y miente. El orden es: transcript → generar → guardar →
*ahí sí* comparar.

**Cuando toque correr las dos variantes sobre la misma llamada** (que es la
comparación pareada, la más informativa), la segunda está anclada en la primera
por construcción y no hay forma de evitarlo dentro de una sesión. Dos reglas:

- El anclaje empuja hacia el ACUERDO, así que la diferencia que midas es un
  **piso** del efecto real, nunca una medida. Repórtala como piso.
- **Alterna el orden entre llamadas.** Si en todas corres `produccion` primero,
  todo el sesgo apunta al mismo lado y se vuelve indistinguible de un hallazgo.
  Anótalo en `nota`: `orden=1` o `orden=2`.

Lo único que el anclaje NO puede falsear es si el nombre del arquetipo salió
literal de la lista cerrada. Ese contraste vale aunque los puntajes estén
amortiguados.

---

## 1. Entrada

Un id de meeting o su prefijo, y opcionalmente la variante:

```
/replicar-reporte-llamada <meeting-id> [produccion|mejorado|mejorado2]
```

Si no dan variante, usa `produccion` (el control). Si no dan id, elige una
llamada con transcript que **no** hayas mirado, y dilo:

```bash
bash/calls/calls.sh --limit 20                 # el catálogo de llamadas
```

Verifica que tiene transcript antes de nada — sin transcript no hay nada que
replicar:

```bash
bash/meetings/meeting_transcript.sh <id> | head -5
```

## 2. Armar el prompt

Los dos prompts viven junto a este archivo:

| archivo | qué es |
|---|---|
| `prompt-produccion.md` | El prompt de producción **verbatim**, extraído de `/projects/google-meet-express/src/prompts/call-meeting-report.js` en el commit `31e2210`. Es el control: no se toca. |
| `prompt-mejorado.md` | El mismo, con **exactamente dos cambios**: (1) rúbrica de anclaje 0-100 para los cuatro ítems BANT, con la regla de que la ausencia de objeción no es evidencia de fortaleza; (2) el arquetipo como lista cerrada de cuatro rasgos —incluido «Experienced Trader», que el prompt de producción nunca declaró— con instrucción de usarlos verbatim y unirlos con `" + "`. |
| `prompt-mejorado-2.md` | El anterior con **un solo cambio**: `need` deja de usar las anclas genéricas y recibe **un eje propio, el costo de la inacción**. Existe porque la medición pareada (mismo modelo, misma llamada) mostró que la rúbrica genérica bajó budget −16.7, timeline −15.0 y authority −13.3 pero `need` solo **−1.7**: sus anclas piden que el lead «lo haya dicho explícitamente», y agendar una llamada de ventas ya lo dice, así que ningún lead puede fallarlas. El eje nuevo puntúa qué le cuesta el statu quo y si ya gastó algo intentando resolverlo, con dos trampas declaradas (un dolor pasado ya absorbido no es necesidad; fluidez no es urgencia). |

Ambos traen tres marcadores sin sustituir: `${currentDate}` (dos veces) y
`${transcript}`. Sustitúyelos tú:

- `${transcript}` → la salida cruda de `meeting_transcript.sh`.
- `${currentDate}` → la **fecha del meeting** (`YYYY-MM-DD`), no la de hoy.
  Producción pasa `new Date()`, pero ese campo no toca BANT y usar la fecha del
  meeting hace que correr el skill dos días distintos dé la misma entrada.
  Es una divergencia deliberada; está declarada aquí y va en `nota`.

**No edites el prompt al vuelo.** Si quieres probar un cambio, es una variante
nueva con su archivo y su nombre — un prompt tocado a mano en una corrida no se
puede volver a correr ni atribuir. Ese es todo el motivo por el que
`prompt-mejorado-2.md` es un archivo aparte y no una edición de
`prompt-mejorado.md`: las 18 corridas ya guardadas bajo `mejorado` dejarían de
ser interpretables. Una variante nueva se agrega en tres sitios y ninguno es
opcional: el archivo, el `choices` de `guardar.py`, y `CELDAS` en
`bash/calls/comparativo_bant.sh` (la UI toma de ahí el número de filas por
lead).

**Una variante nueva exige una cohorte nueva.** No se puede reevaluar sobre las
llamadas ya puntuadas: sus puntajes están vistos y anclarían la corrida. La
muestra ciega original está quemada para todo lo que venga después de ella.

## 3. Generar

Produce el JSON **siguiendo el prompt como si fueras el agente de producción**.
Solo el objeto JSON: sin cercas de markdown, sin texto antes ni después. El
prompt ya lo exige y el guardado lo valida.

Reglas de la corrida:

- El idioma de salida es el del transcript, salvo los valores de enum del
  schema (eso lo dice el propio prompt).
- No consultes la base para «confirmar» nada mientras generas. El transcript es
  la única entrada.
- Si el transcript está vacío, truncado o es inutilizable, **no inventes un
  reporte**: dilo y para. Un reporte generado sobre nada es exactamente la
  población de ceros que estamos tratando de distinguir.

## 4. Guardar

Escribe el JSON a un archivo temporal en el scratchpad y guárdalo con el helper
(construye el INSERT con escapado correcto y lo pasa por `db_exec.sh`, que es
el único write a la db local):

```bash
python3 .claude/skills/replicar-reporte-llamada/guardar.py \
  --meeting  <uuid-completo> \
  --corrida  "<etiqueta única>" \
  --modelo   "claude-opus-5" \
  --variante produccion \
  --json     <ruta-al-json>
```

La etiqueta de corrida debe distinguir la fila: `<prefijo>-<variante>-<n>`
sirve (`d1cd4d2c-produccion-1`). El helper valida antes de escribir que el JSON
parsea, que la raíz trae las 7 claves del esquema y que los cuatro ítems BANT
existen; si algo falta, falla y no escribe.

## 5. Comparar

Ahora sí, y solo ahora:

```bash
bash/calls/bant_diff.sh                      # todas las corridas
bash/calls/bant_diff.sh --meeting <id>       # una
bash/calls/bant_diff.sh --resumen            # agregado por variante+modelo
```

Lee sqlite (lo generado) y Postgres (lo guardado), los cruza por `meeting_id` y
muestra los cuatro ítems lado a lado con su delta, más el arquetipo. Read-only
de los dos lados.

Al reportarle al usuario, di siempre **con cuántas llamadas** se está mirando.
Una corrida es una anécdota; el patrón del 60% se midió sobre 940 puntajes. No
concluyas «la rúbrica funciona» con n=1 — di qué pasó en esa llamada y cuántas
más harían falta.

## 5b. Correr una MUESTRA de varias llamadas (y reanudarla)

Una comparación con n=1 no dice nada; para eso existe la tabla `muestra` en la
misma db. Guarda la cohorte trazada **a ciegas** (sin mirar ni un campo del
reporte) y es lo que permite reanudar después de una compactación o en otra
sesión. Qué falta se pregunta así, y nunca de memoria:

```bash
bash/localdb/db_query.sh reportes_llamada "
  SELECT m.orden, substr(m.meeting_id,1,8) AS id, m.fecha, m.chars_reales,
         CASE WHEN r.meeting_id IS NULL THEN 'PENDIENTE' ELSE 'hecha' END AS estado
  FROM muestra m
  LEFT JOIN reportes r ON r.meeting_id = m.meeting_id AND r.prompt_variante='mejorado'
  ORDER BY m.orden;"
```

Toma la primera `PENDIENTE`, córrela, guárdala, sigue. Reglas de la muestra:

- **La compactación NO daña la calibración.** Las anclas viven en
  `prompt-mejorado.md`, en disco, no en tu memoria. Y producción puntúa cada
  llamada en un contexto limpio, sin recordar las anteriores: puntuarlas sin
  recordarlas es MÁS fiel a producción, no menos.
- **No mires el avance parcial** (`bant_diff.sh`, la tabla `reportes`) mientras
  queden llamadas pendientes. Ver hacia dónde va la media es la forma más fácil
  de empezar a puntuar hacia ella.
- **Una llamada con transcript vacío, truncado o inutilizable no se puntúa.**
  Se anota en `nota` y se deja sin fila. Un reporte inventado sobre nada es
  exactamente la población de ceros que el ejercicio quiere distinguir.

## 6. Fuera de alcance

- **Cambiar el prompt de producción** (`/projects/google-meet-express`) — es
  otro repo y es producción. Este skill produce la evidencia para justificar ese
  cambio; no lo hace.
- **Escribir en `meeting_reports`** — jamás. Regenerar sobre Postgres es
  `transcript-to-report`, que es otra cosa y es para reuniones de equipo.
- **Reprocesar en lote** — el skill es de a una llamada. Para varias, córrelo
  varias veces con corridas distintas; que cada una sea deliberada es parte del
  diseño.

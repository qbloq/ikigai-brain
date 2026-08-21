# Backfill de contratos IO — tareas abiertas sin IO (las de PM) · 2026-08-21

**Pedido:** generar el contrato de trabajo (inputs + outputs + criterios de
aceptación) de las tareas abiertas que no lo tenían, priorizándolas. Casi todas
son las que entraron desde la plataforma PM de Mari (`source_type='other'` +
`source_external_id`), que nacieron por el sync/cruce y no por `create_task.sh`,
así que nunca pasaron por la instanciación de plantilla.

## El universo, medido

Abiertas (`pending`/`in_progress`/`blocked`) al 2026-08-21: **142**. Sin ningún
input ni output: **54** — 53 de PM + 1 de reunión (`871e998f`, tenía arquetipo
A12.4 pero A12.4 no tiene plantilla, así que nació vacía). Las otras 88 ya traen
contrato (meeting-to-tasks / merges).

## Herramienta nueva: `bash/tasks/apply_contract.sh`

No existía forma de poner un contrato sobre una tarea **ya creada**:
`create_task.sh` solo lo hace al nacer; `materialize_io.sh` instancia la
plantilla pero **neutraliza los slots a «pendiente»** — exactamente el daño que
documenta `docs/plantillas-slots-brief.md` (23 de 28 «pendiente» cayeron en
criterios de aceptación, que quedan inverificables). `apply_contract.sh` es el
gemelo de `create_task.sh` sin cabecera: plantilla + slots (literal si falta, con
`{proyecto}` resuelto solo) **o** contrato explícito; se niega si la tarea ya
tiene IO; una txn; deja comentario de rastro con arquetipo y slots.

## Priorización (criterio)

1. **T1 — High y vencidas/activas** (14): el sistema agéntico persigue por
   `due_date`, y una tarea High vencida sin contrato es una persecución sin
   entregable. Todas con due ≤ 2026-08-20.
2. **T2 — Medium vencidas con entregable claro** (24).
3. **T3 — logística de reuniones + migración Notion** (5): contrato de plantilla
   A10.5; valen poco pero cierran el hueco.
4. **T4 — Medium con título vago** (9; las de Juan Camilo sobre «la app», due
   22–29 ago): contrato de plantilla A11.1/A11.2 con confianza baja (0.4–0.7).
   Lo útil aquí es que el **input «Especificación del feature» es obligatorio**:
   el contrato dice «esto no arranca sin alcance», que es lo que falta.

Vía de contrato: **plantilla del arquetipo** (28) cuando encaja y sus slots se
pueden llenar; **a mano** (24) cuando el arquetipo no tiene plantilla (A6.2,
A12.4, A10.4, A7.5) o la plantilla describe otra cosa (p.ej. A8.1 construye el
dashboard; la tarea lo concilia). **11 quedaron sin arquetipo** a propósito —
actividades que el catálogo no tiene (registrar histórico de testeos, base de
estudiantes para LTV, briefing a talento, evaluación de opciones, handoff a
edición, acompañamiento psicológico, documentar proceso comercial/servicio,
concursos de gamificación, entrega de una base). Son la cola del catálogo, no un
error.

## Resultado

Ver `scratchpad/apply.log` de la sesión y `bash/tasks/task_show.sh <id>`. Cada
tarea aplicada lleva un comentario `apply_contract` con arquetipo + slots, y donde
hubo duda otro comentario con el porqué.

## En espera (no se les puso contrato)

| tarea | por qué |
|---|---|
| `bf4122e6` Programa de referidos (Luis David) | gemela de `259eed82` (Lorenzo), mismo título, dos dueños en PM. Contrato puesto en la de Lorenzo; decidir fusión (`cancel_task.sh bf4122e6 --into 259eed82`) o reparto. |
| `8a8c854f` Migrar Notion → plataforma (sin dueño, «platforms») | gemela de `b8c56271` (Marisol). Contrato en la de Marisol; fusionar. |

## Hallazgos laterales (para el cruce PM↔cerebro)

- **Sin dueño en el roster** (PM: «Tati», «expert», «Speaker A»): `9f249dbe`,
  `598d3b2e`, `f70640d8`, `4d1d3792`, `79b11362`, `6259ea37`. El contrato no
  depende del dueño, pero la persecución sí.
- **Contenido de Andrea bajo proyecto David Guerrero** (PM archiva todo bajo DG):
  `bd38a904`, `c57ffb35`. Evaluar mover de proyecto.
- **Posibles solapes con tareas que ya tienen IO**: `f8feea7b`↔`dfeada96`
  (oferta USD 2.000), `598d3b2e`↔`bfc0dc4f` (encuesta de satisfacción),
  `cb95a33b`↔`22251454` (gamificación), `b063d979`↔`2179756c` (dashboard
  embudo). Anotado en comentarios; no se fusionó nada.
- **Pares que se anulan**: `73a9972e` (automatizar aviso de testimonios) vuelve
  obsoleta a `f70640d8` (avisar a mano).
- Cinco tareas son **instrumentos que el Cerebro ya tiene**: el histórico de
  testeos (`f528489f`, `eea6a491`, `9db8fea7` → `bash/testeos/`), el reporte de
  distribución de ventas (`332c414a` → `bash/finance/`), la cohorte en mora
  (`9f249dbe` → `cobranza.sh`). El contrato lo dice en el comentario.

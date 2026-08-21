# WhatsApp como canal — brief para retomar

**Fecha del rastreo**: 2026-08-21 · **Alcance**: reuniones de equipo del
2026-07-01 al 2026-08-19 (20 de 26 mencionan WhatsApp) + inventario de lo que
ya está corriendo.

Este documento existe para que el tema se retome **en su propia sesión** sin
volver a leer seis transcripciones. No propone ejecutar nada todavía: separa lo
que está **confirmado en actas**, lo que **ya tenemos montado**, y lo que es
**afirmación del equipo sin verificar** — que es justo lo que hay que resolver
antes de prometer una solución.

---

## 1. El requerimiento, en dos etapas

### Etapa 1 (julio) — canal de seguimiento, y se acabó la capacidad

Reunión **07-24 `718ebcf8`** (Ikigai), textual:

> «estamos fundidos ya todas las cuentas de WhatsApp disponibles. Y si queremos
> el tema de los grupos, tendríamos que pasar a los closers a **un CRM que les
> permita contestar los mensajes de WhatsApp, y no hay eso en este momento**.»

Ese es **el requerimiento**, dicho por el equipo, y lleva un mes sin moverse.
En la misma reunión, Mari sobre la automatización:

> «Tenemos un reto con WhatsApp que no hemos podido automatizar. Incluso estoy
> que lo hago por Telegram porque es más rápido, no dependo de nada.»

### Etapa 2 (agosto) — WhatsApp pasa a ser la ENTRADA del embudo

Reunión **08-14 `0caa2fcf`**: se decide cortar el funnel —
`anuncio → VSL/BSL → botón de WhatsApp`, sin survey ni calendario.

Reunión **08-19 `b3f06835`**: ya está corriendo.

> «en este momento no estamos generando agendas, sino que la gente está llegando
> directamente al WhatsApp» · «Desde el WhatsApp se agenda la gente» · «hay 9
> leads que llegaron a WhatsApp, de ayer a hoy».

**Esto cambia la naturaleza del problema.** En julio WhatsApp era donde se hacía
seguimiento; hoy es por donde entra el dinero, y sigue sin instrumentar.

---

## 2. Cronología de los problemas (con su reunión)

| Fecha | Reunión | Qué se manifestó |
|---|---|---|
| 07-10 | `2f6646c2` | Se conecta el número de Andrea al API. «no se puede conectar ese mismo porque lo bloquean después» · «ya los muchachos no tienen más WhatsApp para contestar» |
| 07-24 | `718ebcf8` | Cuentas agotadas; falta el CRM para que los closers contesten; Mari evalúa Telegram |
| 08-10 | `dcaec561` | Roberto montó «Conecta» para llamadas. Aviso de cambios de plataforma el **1 de octubre**. Se pide explícitamente **plan de contingencia** |
| 08-12 | `208f209c` | **«ya llevamos 3 bloqueos, bro, este mes»**. Debate de capacidad y reparto desde el embudo |
| 08-14 | `0caa2fcf` | Pivote: el VSL manda directo a WhatsApp |
| 08-19 | `b3f06835` | Los leads ya entran por ahí, sin medición |

---

## 3. La causa raíz — diagnosticada por ellos mismos

Reunión **08-12 `208f209c`**:

> «se usa el WhatsApp normal a la par que se está conectado a una aplicación con
> API, que lo van a tender a bloquear… ya WhatsApp identifica que estás usando
> una API con ellos.»

Es el modo **coexistencia**: la app de WhatsApp Business y la Cloud API sobre el
mismo número. El patrón concreto del bloqueo, misma reunión: el call confirmer
llamando mientras el closer manda mensajes desde ese mismo número.

Roberto lo cierra en **08-10 `dcaec561`**:

> «la única forma en estos momentos para poder hacer llamadas sin bloqueos, o
> sea, todo lo que tenga que ver con WhatsApp, sí o sí tiene que ser a través de
> plantilla y a través de la API, o te van a bloquear.»

**El nudo**: el equipo resuelve un problema de capacidad **multiplicando
números**, y la plataforma castiga exactamente eso. Cada número nuevo arrastra
un CRM nuevo, un embudo duplicado o un script de rotación. Y en 08-12 alguien
describe la salida sin darse cuenta:

> «qué chimba que si fuera todo a través de una plataforma y no tener que hacer
> modificaciones en el embudo ni nada.»

---

## 4. Lo que YA tenemos corriendo (y no entró a ninguna reunión)

Esto es lo más importante del brief: el equipo discute repartir SIM cards
mientras la infraestructura que lo resuelve ya está en producción.

- **WABA viva**: «Feria Local - Ventas», **+57 312 8932486**,
  `phone_number_id 568780566329582`, `WABA 690499003502578`, app Meta
  «Parallelo». Webhook con TLS en `a.parallelo.ai` y router por
  `phone_number_id` + remitente. Detalle: [zeroclaw-referencia.md](zeroclaw-referencia.md).
- **zeroclaw compilado con los DOS canales**: `channel-whatsapp-cloud` **y**
  `whatsapp-web`. Las dos vías posibles ya están disponibles en el mismo binario.
- **[bash/closers/enviar.sh](../bash/closers/enviar.sh)** — enviador único
  (sesión o plantilla Meta), idempotente por `(escenario, ref)`. Lleva **73
  mensajes** enviados en 3 escenarios (`postllamada` 26, `cierre` 23,
  `recordatorio` 23).
- **[bash/onboarding/plantilla_crear.sh](../bash/onboarding/plantilla_crear.sh)** — alta de plantillas nuevas en el WABA.
- **Iki**, el agente, contestando en ese número.
- Doc operativo del canal: [closers-whatsapp.md](closers-whatsapp.md).

---

## 5. Las tres vías, y qué cubre cada una

No compiten; cubren cosas distintas.

### WABA (Cloud API) — todo lo automático y de volumen
Único camino sin bloqueos y único que sobrevive a octubre. Cubre reparto desde
el embudo, recordatorios, distribución entre call confirmers.
**Costo real**: fuera de la ventana de 24 h todo va por plantilla aprobada — es
exactamente lo que Roberto viene diciendo y el equipo recibe como mala noticia.

### WhatsApp Web (zeroclaw) — la conversación personal del closer
Cuando el mensaje debe salir del número propio y sonar humano. No aguanta
volumen y conserva riesgo de bloqueo.
⚠️ **Regla dura: nunca sobre un número que también esté en el API.** Mezclar los
dos es literalmente lo que causó los 3 bloqueos de agosto.

### El agente (Iki / zeroclaw) — lo que cambia la ecuación
Hoy la pregunta es «¿cuántas **personas** caben en un número?» y la respuesta
son 4 dispositivos vinculados. Con un agente sobre WABA la pregunta pasa a ser
«¿cuántas **conversaciones** aguanta un número?», y ahí no hay tope de
dispositivos: el agente recibe, califica, agenda y entrega el contacto al closer
que corresponda. **La rotación de números deja de hacer falta** porque ya no hay
un recurso escaso que repartir.

Es, literalmente, el «CRM que les permita contestar los mensajes de WhatsApp»
pedido el 24 de julio. Y si en octubre los números llegan encriptados, quien
conserva el hilo es quien está dentro del API — o sea, el agente.

---

## 6. ⚠️ Afirmaciones del equipo SIN verificar

Salieron de las actas y **no están confirmadas**. Verificarlas es el primer
paso de la próxima sesión, porque las tres cambian el diseño:

1. **Tope de dispositivos por verificación.** El equipo (08-12) sostiene que la
   verificación sube de 4 → 6 → 10 → 15 dispositivos.
   **Lo dudo**: los dispositivos vinculados son 4 y la verificación de negocio
   no cambia ese límite. Hay tarea abierta para evaluarlo (`8cd96ed0`) —
   resolverla con el dato **antes de pagar nada**.
2. **Cambios del 1 de octubre.** Se afirma que los números llegarán encriptados
   (solo username), y que las llamadas quedarán obligadas a pasar por el API.
   Hay que confirmarlo contra la documentación de Meta: de esto depende el plan
   de contingencia.
3. **«Conecta»** — la plataforma de llamadas que Roberto ya configuró (08-10).
   No sé si se solapa con lo nuestro o lo complementa. **Preguntarle a Roberto
   es el atajo**: es quien tiene el diagnóstico más fino del equipo.

---

## 7. Las tareas abiertas que pertenecen a este tema

11 tareas abiertas tocan WhatsApp. Las del acta del 10-ago (`dcaec561`):

| Tarea | Qué es | En PM |
|---|---|---|
| `ff4496fc` | Plan de contingencia no técnico por los cambios de la API | solo cerebro |
| `dc66c2b8` | Widget de rotación de números en el funnel | solo cerebro |
| `f66aaf1c` | Entregar los números de los closers para la rotación | solo cerebro |
| `42094c7d` | Acceso temporal de Roberto al número y dispositivo | solo cerebro |
| `9396b9fa` | Explicar al equipo la operación con plantillas y llamadas por API | solo cerebro |
| `8cd96ed0` | Evaluar la verificación paga para ampliar dispositivos | `288ea840` |
| `2089d2d6` | Confirmar número/dispositivo de David para conectarlo por Coexistencia a Conecta | `a35cc334` |

Otras relacionadas: `1180ad54` (mensajería con plantillas a los que no
convirtieron), `1e7fe7e2` (reactivar Low Ticket de Andrea por plantillas),
`8d24d272` (automatización que lleva el lead a WhatsApp con palabra clave),
`969f3ef2` (canal de notificaciones con número dedicado).

⚠️ **`dc66c2b8` y `f66aaf1c` son la solución vieja.** Si la vía es el agente
sobre WABA, la rotación de números no hace falta. No cancelarlas todavía —
decidirlo cuando se verifique el punto 6.

**`ff4496fc` es la que más urge**: octubre tiene fecha.

---

## 8. Por dónde empezar la próxima sesión

1. Verificar los 3 puntos abiertos (§6) — sin eso, cualquier diseño es apuesta.
2. Hablar con Roberto: es el que más sabe y el que ya montó infraestructura.
3. Recién ahí decidir entre «rotación de números» (lo que el equipo viene
   armando) y «un número con agente» (lo que la infraestructura ya permite).
4. Instrumentar la entrada por WhatsApp, que desde 08-19 trae leads y **no se
   está midiendo** — hoy no sabemos cuántos entran ni qué pasa con ellos.

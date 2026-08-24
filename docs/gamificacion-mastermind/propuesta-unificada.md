# Sistema de gamificación de Premium Mastermind — propuesta unificada

**Borrador consolidado por el Cerebro · 2026-08-24 · para que Tati y Cisco lo pulan y lo presenten a Lorenzo y Juanca**

Tarea: `22251454` «Estructurar sistema de gamificación con castigos, recompensas y clubes para estudiantes del Mastermind» (Tati · Cisco · Mari).
Fuentes: propuesta de Tati y discusión de la reunión de seguimiento de estudiantes del **29-jul** (`40ef10e0`), reunión de estrategia DG del **29-jul** (`dc27f156`), reunión de alineación Mari–Tati del **15-jul** (`ed6b60c2`) y reunión de servicio del **20-ago** (`2ea7176d`). Nada de lo que sigue es invención del Cerebro: lo que no se dijo en esas reuniones está marcado **[por definir]**.

---

## 1. Para qué existe

La gamificación no es un juego: es la forma de hacer que el estudiante **siga el plan de la estrategia** y, al hacerlo, produzca lo que el negocio necesita:

| Lo que se le pide al estudiante | Lo que produce para Ikigai / David |
|---|---|
| Fondear la cuenta que se le entrega en el programa | Casos de éxito medibles |
| Retirar (primero poco, después más) | Testimonios (meta: **4 al mes**, uno semanal) |
| Enviar el análisis de la estrategia (DAD) | Orden y gestión de riesgo en el grupo |
| Cumplir las reglas del grupo | Menos deserción, más renovaciones |
| Aspirar al grupo de élite | Gancho de venta y de renovación («vamos a tener esto») |

Los cuatro **indicadores de servicio** acordados el 20-ago (índice de resultados por hito: fondeo → primer retiro → recuperación de la inversión → retiro consistente) son exactamente los escalones de los rangos: **la gamificación es la cara visible de esos indicadores para el estudiante.**

## 2. Principios de diseño ya acordados

1. **Gamificación ≠ ruta educativa** (Mari, 29-jul). La ruta educativa dice *qué debe dominar* el estudiante en cada nivel; la gamificación dice *cómo se premia* su participación y sus logros. Se diseñan por separado y luego se unen (tarea `58f86ac8`).
2. **Pequeñas victorias escalonadas** (Mari, 29-jul): la primera meta no es retirar USD 2.000 sino el **primer retiro de USD 100**. Comparar al recién llegado con quien retira 15.000 desmotiva.
3. **Una sola propuesta** de servicio + mentoría para la capa ejecutiva; los beneficios económicos requieren **aprobación de presupuesto** (Lorenzo/Juanca).
4. **Montada sobre la plataforma única** decidida el 20-ago: contenido y cronograma en **Skool con desbloqueo semanal por progreso y mensual por pago de cuota**; seguimiento («oficina») en la **app de Ikigai** con ficha por estudiante. Los rangos y puntos deben vivir en esa ficha, no en un Word.
5. **Se sostiene con reglas de grupo ya publicadas** (Cisco, jul) y el sistema de strikes que se pospuso en julio para revisarse en agosto.

## 3. Rangos

| Rango | Requisito de ascenso (propuesta 29-jul) | Qué demuestra | Beneficios |
|---|---|---|---|
| **Bronce** | Ninguno: es el iniciado que entra al programa | — | Acceso normal al programa |
| **Plata** | Cuenta de fondeo **aprobada** | Siguió el plan hasta pasar la prueba | **[por definir]** |
| **Oro** | **Retiro efectivo** + **análisis de la estrategia (DAD) enviado** | Opera con orden y gestión de riesgo | **[por definir — requiere presupuesto]** |
| **Diamante** | **300 puntos** acumulados + retiro mínimo de **USD 2.000** | Resultado sostenido | Grupo privado de destacados; integración anual con todo pago **[por definir]** |
| *(Nivel superior)* | Propuesta de Cisco: proyección a **gestor / mentor / fondo** (como el mastermind de Londres en que se basó el programa) | Autoridad del programa antes de entrar | **[por definir]** |

Notas de diseño:
- Cisco confirmó que, siguiendo los parámetros de la estrategia, los requisitos son «muy fáciles de alcanzar» una vez la cuenta está fondeada: el sistema premia orden, no suerte.
- El requisito de **Plata** es el primer escalón de la ruta educativa («la primera meta es fondear la cuenta que ya se te da en el programa»).
- Estar **al día en las cuotas** debería ser condición para conservar los beneficios del rango (coherente con la decisión del 20-ago de ligar el desbloqueo de contenido al pago). **[por definir: ¿condición o solo strike?]**

## 4. Puntos y strikes

- Se **suman puntos** por cumplir objetivos (fondeo, retiro, análisis enviado, participación en concursos, dictar sesiones, testimonio) y se **restan por strikes**.
- **Strike = −20 puntos** (único valor ya definido). Los strikes se aplican por incumplir las reglas del grupo que Cisco publicó (opinar sin resultados, stickers y «guachafita», desviar la conversación del análisis).
- **Puntos por evento: [por definir]** — tabla propuesta para llenar en la reunión con Cisco (`cb95a33b`):

| Evento | Puntos | Quién lo registra | Evidencia |
|---|---|---|---|
| Cuenta de fondeo aprobada | [ ] | Tati / Cisco | Captura de la aprobación |
| Retiro efectivo (monto) | [ ] | Tati / Cisco | Comprobante |
| Análisis de la estrategia enviado | [ ] | Cisco | El análisis |
| Participación en concurso bimestral | [ ] | Cisco | Resultado del concurso |
| Dictó sesión en vivo / backtesting | [ ] | Mari | Grabación |
| Grabó testimonio | [ ] | Tati | El video |
| Strike | **−20** | Cisco | Mensaje / regla incumplida |

- Diamante exige 300 puntos: la escala de puntos por evento debe hacer que 300 sea alcanzable en **[por definir] meses** siguiendo el plan.

## 5. Concursos bimestrales (Bridge Market)

Propuesta de Tati, inspirada en la competencia de Bridge Market que «incentivó mucho al grupo» pero le faltaron reglas:

- Cada **2 meses**, los **5 mejores de Oro** y los **5 mejores de Diamante** (por puntos) participan en una **prueba de fondeo** con Bridge Market (si hay alianza).
- Gana el **mayor profit siguiendo los parámetros de la estrategia** (DAX, S&P, oro, Nasdaq — los activos que maneja el programa). Operar fuera de los parámetros descalifica.
- Premios al **top 3**: **cuentas fondeadas**.

El reglamento detallado (reglas, calendario, métrica, premios, condiciones de Bridge Market) es el entregable de la tarea `fa9085db` (Lorenzo): ver *Reglamento del concurso bimestral*.

## 6. Grupo de élite («Black» / Diamante)

- Grupo **privado** de los mejores estudiantes, habilitados para **dar sesiones en vivo** (ya lo hacen Jaime y Wilmar; David hizo una sesión en vivo con Wilmar).
- **Integración anual con todo pago** (lo que gustó de la academia «de la mansión»).
- Efecto buscado: «yo quiero estar ahí — ¿qué tengo que hacer?». Es también el **gancho de la oferta**: la reunión de estrategia del 29-jul propuso presentar en la oferta «nuestros traders bronce participan en estos retos con estos premios; nuestros traders plata…».

## 7. Estructura de los grupos

- Propuesta de Tati: migrar a **Discord** con dos canales — *iniciados* (nuevos, hasta la semana 4 o 12 **[por definir]**) y *general* (antiguos) — para no mezclar contextos ni afanar al nuevo con los resultados del viejo. Cisco: Discord hoy es de la Academy (los básicos).
- **Quedó sin resolver** el 29-jul («primero ordenar la conducta en el grupo actual»).
- El 20-ago la decisión de **Skool + app de Ikigai** cambia la pregunta: el **desbloqueo semanal por progreso en Skool** separa naturalmente al iniciado del antiguo sin dos grupos. **[por decidir: si los grupos de conversación (WhatsApp/Discord) siguen o se van a Skool]**

## 8. Articulación con la ruta educativa (`58f86ac8`)

Hoy todo el material se entrega desde el ingreso y lo único restringido es el 1:1 con el mentor: no hay nada que desbloquear. La ruta educativa debe definir por nivel *qué tengo que saber para empezar → cuál es la primera meta (retiro de USD 100) → nivel de USD 2.000 → escalada vertical y horizontal*. Cada nivel de la ruta se corresponde con un rango, pero se diseña aparte (ver el esqueleto de la ruta educativa en la carpeta de `58f86ac8`).

## 9. Articulación con el cobro y la renovación (20-ago)

- **Desbloqueo por pago**: el contenido del mes se abre al pagar la cuota (palanca principal de cobro). Los rangos deberían exigir estar al día.
- **Inactivos o morosos con más de un año** salen del grupo; oferta de continuidad: **USD 250/mes** (Loro la estructura, Cisco la aplica desde el lunes). Los 62 estudiantes que ya completaron su ciclo (tarea `871e998f`) son la población de esa oferta y de la renovación.
- **Encuestas continuas** (`598d3b2e`) y **psicóloga** (`b6e43cda`) para anticipar los meses negativos: la gamificación cubre la motivación por logro; esas dos cubren la motivación por expectativa.

## 10. Operación: dónde viven los puntos

- **Hoy** no existe ningún registro de fondeos, retiros, análisis ni strikes: la materia prima está en WhatsApp y en la memoria de Cisco.
- **Prototipo del Cerebro** (`gamificacion`, capa local): roster de los **207 estudiantes activos** de Premium Mastermind / Lite sembrado desde los planes de pago (62 ciclo completo · 32 al día · 113 en mora), tabla de **rangos**, catálogo de **tipos de evento** con sus puntos, registro de **eventos** y el **tablero** que calcula rango y puntos por estudiante con las reglas de este documento. Sirve para empezar a registrar mañana, por conversación, sin esperar la app.
- **Destino**: la **ficha por estudiante en la app de Ikigai** (Juanca, decisión 20-ago) — el prototipo declara el esquema (estudiante · evento · puntos · rango) que la ficha debe adoptar.
- **Medición mensual** (Tati, desde fin de agosto, cohortes jul–ago): estudiantes por rango, ascensos del mes, strikes, hitos alcanzados = el «índice de resultados por hito».

## 11. Decisiones abiertas para Lorenzo y Juanca

| # | Decisión | Opciones sobre la mesa | Propone | Decide |
|---|---|---|---|---|
| 1 | Beneficios por rango (plata/oro/diamante) y su **presupuesto** | Económicos (cuentas fondeadas, integración anual) vs de acceso (sesiones, grupo privado) | Tati + Cisco | Lorenzo / Juanca |
| 2 | **Puntos por evento** y escala para llegar a 300 | Tabla §4 | Cisco | Lorenzo |
| 3 | Estar **al día en cuotas** como condición del rango | Condición · strike · nada | Cerebro (condición) | Lorenzo |
| 4 | **Grupos**: WhatsApp / Discord / Skool | §7 | Tati | Lorenzo + Juanca |
| 5 | Semana de paso iniciado → general | 4 · 12 | Tati | Cisco |
| 6 | Alianza con **Bridge Market** para los concursos | Confirmar condiciones | Lorenzo | Bridge Market |
| 7 | **Nivel superior a diamante** (gestor/mentor/fondo) | Sí ahora · después | Cisco | Lorenzo / David |
| 8 | Dónde se registran los eventos hasta que exista la ficha en la app | Tablero del Cerebro · hoja · esperar | Cerebro | Mari |

## 12. Trazabilidad

- Reuniones: `ed6b60c2` (15-jul) · `dc27f156` y `40ef10e0` (29-jul) · `b3f06835` (19-ago) · `2ea7176d` (20-ago).
- Tareas: `22251454` (esta) · `cb95a33b` reunión con Cisco · `fa9085db` concursos · `58f86ac8` ruta educativa · `871e998f` renovaciones · `9f249dbe` cohorte feb–mar · `598d3b2e` encuestas · `b6e43cda` psicóloga · `562fc261`/`f4b81d50` backtesting.
- El documento original de Tati (Word, 29-jul) **no está en Drive**: subirlo a la carpeta de esta tarea es el primer pendiente.

# Iki multi-rol: desacople del rol por archivo, recordado por sesión

**Fecha**: 2026-08-24 · **Estado**: diseño aprobado en conversación, pendiente
review del spec

## Contexto y propósito

Iki es el agente `default` de ZeroClaw (`docs/zeroclaw-referencia.md`): la
primera terminal WhatsApp del Cerebro, viva en producción atendiendo a
Santiago, Pablo y los closers activos sobre el número WABA compartido. Su
identidad son cuatro archivos que zeroclaw inyecta al system prompt
(`~/.zeroclaw/agents/default/workspace/` → `SOUL/IDENTITY/AGENTS/USER.md`); la
continuidad por sesión (`session_id = whatsapp_<numero>`) **es la memoria**
(`brain.db`, scoped por agente), no un historial en disco.

Hoy el **rol está horneado en un solo archivo**: el `AGENTS.md` de Iki mezcla
lo universal (regla del canal, identidad-por-número, recado canónico, la puerta
de datos, reglas duras) con lo específico de closer (saludo matutino,
protocolo post-llamada) y un **menú de puerta comercial** (`calls`, `crm_leads`,
`cobranza`, `closer_dashboard`, …). No hay forma de que Iki atienda a un
**Ejecutivo** (Juan Camilo Correa, Lorenzo Cadavid — el rol que pone la plata)
sin reescribir ese archivo, y reescribirlo arriesga el comportamiento closer que
ya está en producción.

**Pedido de Santiago**: preparar a Iki para atender al rol Ejecutivo y, más
en general, **desacoplar el rol** — que el `AGENTS.md` sea agnóstico y lea el
rol desde otro archivo, recordándolo por sesión (porque las sesiones son WABA:
el hilo in-process se pierde al reiniciar; lo durable es la memoria).

Esto proyecta sobre Iki la arquitectura de roles que el Cerebro ya tiene:
`docs/roles/<rol>.md` + el mapa único `docs/roles/acceso.json` (rol → dominios
/ tablas / UIs), donde **el rol Ejecutivo = acceso total al negocio**
(`docs/superpowers/specs/2026-08-20-control-de-acceso-fuentes-design.md`). Iki
pasa a ser **un consumidor más de ese mapa** — la doctrina "un mapa, varios
consumidores" (`docs/roles/README.md`).

## Qué NO hace esta fase (no-goals)

- **No va a multi-agente** (un agente zeroclaw por rol). Se evaluó y se
  descartó por sobre-ingeniería para pocas personas: un solo Iki flexible.
- **No pone un candado de rol en la puerta de datos** (`viz` `:4317`). El
  fencing del menú queda como **disciplina de prompt**, acotado por que la
  puerta es **solo-lectura** (peor caso: leer una cifra de más, nunca actuar).
  El candado en la puerta es endurecimiento futuro (ver §6).
- **No mueve el resolver número→rol a la DB todavía.** v1 usa un roster
  estructurado y curado a mano en `USER.md`; el resolver DB-autoritativo
  (`team_members→team_roles`) es endurecimiento cuando el roster crezca (§4.3).
- **No parchea el binario de ZeroClaw** (política "línea de no-fork",
  `docs/zeroclaw-referencia.md`). El único cambio de `config.toml` es
  **configuración declarada** (una entrada de `auto_approve`), no un fork —
  se marca explícito para aprobación (§4.4).
- **No toca** el pipeline de señales de seguridad de Iki
  (`2026-08-19-seguridad-agentes-zeroclaw-design.md`): ese lee `brain.db` sin
  importar el rol; agregar roles no lo altera.
- **No construye** aún la fuente `funnel_consolidado` (el dashboard UTM→venta
  quedó parqueado en su propio diseño); el menú Ejecutivo lo agregará cuando
  exista.

## Decisiones tomadas (y por qué)

Cinco bifurcaciones, todas resueltas con Santiago en el brainstorming:

1. **Un solo Iki, multi-rol** (no un agente por rol). Flexible, un despliegue.
2. **Rol desacoplado en archivo local** en el workspace (`roles/<rol>.md`), no
   servido por la puerta. Es un **artefacto propio** — un *playbook
   conversacional*, no el doc de ingeniería `docs/roles/<rol>.md` — así que no
   hay duplicación ni drift con el Cerebro.
3. **Scope Ejecutivo = analista en-rol**: Iki **responde** preguntas de
   negocio leyendo la puerta con el menú del rol; las **acciones**
   (crear/aprobar/cambiar) siguen siendo recado `PARA: Cerebro`.
4. **Carril del rol al runtime = `file_read` de path exacto** (determinista),
   **no `memory_recall`** (que en zeroclaw es búsqueda keyword/FTS, no fetch
   por clave — ver §7). La memoria solo cachea el binding de sesión.
5. **Nivel de determinismo = "determinista-suficiente"**: las dos anclas
   (número→rol, rol→playbook) deterministas; el residual ("respeta el menú")
   como disciplina de prompt acotada por puerta solo-lectura.

## Arquitectura

### 4.1 Estructura de archivos (workspace de Iki)

```
~/.zeroclaw/agents/default/workspace/
  AGENTS.md          KERNEL agnóstico de rol (universal)   [inyectado]
  SOUL.md            alma (sin cambios)                    [inyectado]
  IDENTITY.md        identidad base (sin cambios)          [inyectado]
  USER.md            roster ESTRUCTURADO: número→persona→apodo→ROL [inyectado]
  roles/
    ejecutivo.md     playbook: menú + tono + protocolos + frontera
    closer.md        extraído del AGENTS.md actual (saludo, post-llamada)
    director-comercial.md
    cerebro.md       operador pleno (Santiago) / founder-tech (Pablo)
    _default.md      fallback seguro (recepción, sin datos de negocio)
```

Solo los cuatro archivos raíz se inyectan al prompt. Los `roles/*.md` **no** se
inyectan: Iki los lee con `file_read` cuando resuelve el rol de la sesión.

### 4.2 El kernel (`AGENTS.md`) — solo lo universal

Conserva: regla del canal (solo llega el mensaje final; tools primero, sin
texto para la persona), identidad-por-número, recado canónico, mecánica de la
puerta de datos (genérica, sin el menú comercial), avisos del Cerebro,
aprobaciones de tools, reglas duras (WhatsApp corto, guardar antes de
confirmar, pedidos grandes → recado).

**Gana un protocolo nuevo — resolución de rol, al inicio de cada sesión:**

```
1. Número del remitente (determinista, del sistema; la llave del mensaje
   entrante es whatsapp_<numero>) → rol, leyendo el roster de USER.md
   (tabla exacta, ya en el prompt).
2. file_read roles/<rol>.md  → adoptar menú, tono, protocolos, frontera.
3. memory_store  "ROL: whatsapp_<numero> = <rol>"  (caché de sesión).
   Cada turno siguiente re-resuelve por el número (determinista); la memoria
   es optimización, no la fuente de verdad — si falla/ausente, se re-resuelve.
4. Número desconocido / sin rol en el roster → rol _default (recepción:
   captura recado, NO entrega datos de negocio).
```

### 4.3 Resolución número→rol

- **v1**: el roster de `USER.md` pasa de prosa a **tabla estructurada** con una
  columna `rol` por persona (`ejecutivo`, `closer`, `director-comercial`,
  `cerebro`). Curado a mano, como hoy. Founder/tech (Santiago, Pablo) = rol
  `cerebro` (acceso pleno), **no** `ejecutivo`.
- **Endurecimiento (futuro)**: una fuente de puerta `quien?telefono=<E164>`
  que resuelve contra `team_members→team_roles` (autoritativo, misma fuente que
  `acceso.json`). El número es entrada determinista; la tabla es autoritativa.
  Se adopta cuando el roster crezca más allá de lo curable a mano.

### 4.4 Cambio de configuración (una entrada)

`~/.zeroclaw/config.toml`, `[risk_profiles.default]`:

```toml
auto_approve = ["memory_store", "memory_recall", "web_fetch", "file_read"]
```

- **Por qué**: sin esto, leer `roles/<rol>.md` pediría aprobación humana en
  cada turno — inviable en un chat.
- **Seguridad**: `file_read` queda **encerrado por `workspace_only = true`**
  (ya activo) — Iki solo puede leer dentro de su workspace, no el sistema de
  archivos ni `brain.db` (que vive fuera del workspace). El workspace solo
  contiene sus propios archivos de identidad y los playbooks.
- **Política**: es **configuración**, no un parche al binario — compatible con
  la "línea de no-fork". Aun así **requiere ok explícito de Santiago** porque
  amplía la superficie auto-aprobada de un agente de cara afuera.

### 4.5 El rol Ejecutivo (`roles/ejecutivo.md`)

- **Menú de puerta** — derivado de `docs/roles/acceso.json` (ejecutivo = total
  negocio), enumerado para el modelo: `portfolio · dashboard · ad_campaigns ·
  ad_stats · ad_detail · ad_anuncios · ad_angulos · cashflow · comisiones ·
  cobranza · cohorte_mora · desercion · embudo · embudo_organico ·
  ventas_diarias · testeos · crm_pipeline · crm_leads · crm_opp_detail`
  (+ `funnel_consolidado` cuando exista). **Todas ya expuestas por la puerta**
  — cero fuentes nuevas.
- **Scope**: analista en-rol. Responde lecturas de negocio, **cifras clave
  primero, sin JSON crudo, sin capa de ingeniería** (rutas/scripts/flags
  jamás — `docs/roles` / memoria "no revelar capa de ingeniería"). Acciones →
  recado `PARA: Cerebro` con PROPUESTA. Pedidos de análisis/cómputo pesado →
  recado.
- **Frontera**: el Ejecutivo (CEO/COO) ve **todos los proyectos**; no hay
  restricción de acceso que sostener para este rol (el menú-fencing importa
  para roles restringidos como closer, no para ejecutivo). La confidencialidad
  entre personas sigue vigente (avisos/recados de otro no se filtran).
- **Protocolo (opcional, v2)**: brief de KPIs al saludo matutino (portafolio +
  caja del día). Fuera del alcance de v1; se nombra para no perderlo.

### 4.6 Extracción del rol closer — SIN regresión (risk-first)

Iki está **vivo atendiendo closers**. Mover el saludo matutino y el protocolo
post-llamada del `AGENTS.md` actual a `roles/closer.md` **no puede cambiar el
comportamiento observable**. Requisito de primera clase:

- `roles/closer.md` recibe, **textual**, las secciones actuales: "Saludo
  matutino a closers", "Protocolo post-llamada (closers)", y el menú comercial
  (`closer_agenda`, `closer_dashboard`, `calls`, sus cuotas/desempeño; datos de
  OTRO closer no se comparten).
- El `AGENTS.md` kernel queda sin esas secciones pero con el protocolo de
  resolución que carga `roles/closer.md` para un remitente closer.
- **Verificación antes de activar** (§7): un closer del roster produce
  exactamente el mismo saludo, la misma clasificación post-llamada y los mismos
  formatos de constancia (`SALUDO:`, `RESULTADO:`, `ACUERDO:`) que hoy.

## 5. Dónde vive qué (cross-repo)

- **Runtime de Iki** (`~/.zeroclaw/agents/default/workspace/` + `config.toml`):
  el `AGENTS.md` kernel, `USER.md` roster, `roles/*.md`, la entrada de
  `auto_approve`. No es un repo versionado por el Cerebro — es estado del
  gateway; el spec/plan viven en el Cerebro.
- **Cerebro** (`hermetico`): este spec y su plan; la fuente de verdad de acceso
  (`docs/roles/acceso.json`) de la que deriva el menú; el futuro resolver
  `quien?telefono=` (si se adopta) como script `bash/` + fuente de puerta.
- **Autoría de los playbooks**: se redactan en el Cerebro (revisables) y se
  copian al workspace del gateway, o se editan in situ — decisión menor del
  plan; lo importante es que el playbook es un artefacto conversacional, no el
  doc de ingeniería.

## 6. Determinismo y frontera de acceso (la parte honesta)

- **`memory_recall` NO es determinista**: en zeroclaw es *keyword/FTS search*
  (`crates/zeroclaw-api/src/memory_traits.rs:258`), sobre-pide y rankea. Por
  eso **no** carga el rol — podría traer la tarjeta equivocada, varias o
  ninguna. La memoria solo cachea el binding de sesión, re-resoluble.
- **Dos anclas deterministas**: el número del remitente llega del sistema
  (`on_session_start`/`ingress.rs`, no el modelo adivinando); `file_read` de un
  **path exacto** es un fetch determinista (a diferencia del recall difuso).
- **Residual model-mediated**: que Iki *respete el menú* de su rol. Es
  disciplina de prompt. **Acotado** porque la puerta es solo-lectura: el peor
  caso es una lectura fuera de menú, nunca una acción. Para el rol Ejecutivo el
  residual es **nulo** (acceso total de todos modos); solo pesa en roles
  restringidos, donde ya existía como prosa hoy.
- **Endurecimiento futuro** (fuera de fase): candado de rol en la puerta
  (rechaza fuentes fuera del menú), que solo es realmente determinista si el
  **sistema** inyecta el número/rol en el request — hoy lo pondría el modelo.

## 7. Verificación

1. **No-regresión closer** (bloqueante): en un entorno de prueba del gateway,
   un remitente marcado `closer` en el roster produce el saludo matutino, la
   clasificación post-llamada y los formatos de constancia idénticos a la línea
   base capturada antes del cambio. Usar los evals/benches de zeroclaw si
   aplican; si no, una transcripción manual comparada.
2. **Rol Ejecutivo**: un remitente `ejecutivo` recibe respuesta a una pregunta
   de negocio (p.ej. cobranza vencida, ROAS de una campaña) en lenguaje de
   negocio, cifras primero, sin ingeniería; y una acción se captura como recado.
3. **Fallback**: un número fuera del roster cae en `_default` — recepción, sin
   datos de negocio.
4. **Carga del playbook**: confirmar que `file_read roles/<rol>.md` se
   auto-aprueba (no pide token) y que Iki no puede leer fuera del workspace.
5. **Binding de sesión**: tras reinicio del daemon, la misma sesión re-resuelve
   el rol por el número (la memoria puede estar, pero no es necesaria).

## 8. Fases de rollout

1. Redactar `roles/closer.md` (extracción textual) + `roles/_default.md` +
   `roles/cerebro.md`; refactor de `AGENTS.md` a kernel + protocolo de
   resolución; `USER.md` a roster estructurado con `rol`. **Verificar
   no-regresión closer antes de activar.**
2. Agregar `file_read` a `auto_approve` (con ok de Santiago).
3. Redactar `roles/ejecutivo.md` y marcar a Juan Camilo / Lorenzo con rol
   `ejecutivo` en el roster. Verificar §7.2.
4. (Futuro, fuera de fase) resolver DB-autoritativo `quien?telefono=`;
   `funnel_consolidado` en el menú; candado de rol en la puerta.

## 9. Preguntas abiertas

1. **Autoría/sincronía de playbooks**: ¿se editan in situ en el gateway, o se
   versionan en el Cerebro y se copian? (No bloquea el diseño; lo fija el plan.)
2. **`roles/cerebro.md` para Pablo**: founder-tech con acceso pleno, pero ¿mismo
   playbook que Santiago o uno propio? (Menor; default: mismo `cerebro`.)
3. **Brief de KPIs matutino del Ejecutivo** (§4.5 protocolo v2): ¿lo quiere
   Santiago en esta ronda o después de validar el scope analista?

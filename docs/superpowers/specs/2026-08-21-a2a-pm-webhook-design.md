# A2A Cerebro ↔ PM — conversación entre agentes por webhook, con humanos a bordo

**Fecha:** 2026-08-21 · **Estado:** diseño aprobado en conversación, pendiente
de plan de implementación (se retoma en su propia sesión) · **Dueños:**
Santiago (cerebro) · Mari (PM / project360).

## 1. Qué es y por qué así

La plataforma PM de Mari (project360) y el Cerebro llevan **el mismo trabajo en
dos sistemas**. Hoy el cruce es de una sola vía y a mano: leemos su API
(`bash/pm/sync_tareas.sh`), espejamos en sqlite, cruzamos, y lo que cambia acá
(53 tareas suyas enlazadas por `source_external_id`, estados, dueños, 2
fusiones) **ella no lo ve**. Mari habilitó un webhook que **de momento solo
registra lo que llega y responde 200** — un log — y pidió que le mandemos «lo
que ya tengan configurado» para escribir su lado.

La decisión: **no diseñar un contrato de datos para un parser que no existe.
Al otro lado hay un operador** — un Claude Code corriendo sobre su app — y a un
operador se le habla. El canal es una **conversación agente-a-agente (A2A)**:
cada lado tiene un webhook de entrada, una vigía que despierta a su CC cuando
llega un mensaje, y un humano que aprueba lo que compromete. Los datos viajan
*dentro* de la conversación, estructurados, para que el día que haya parser no
haya que re-hablar nada.

Principios que gobiernan todo lo demás:

1. **A2A con humanos a bordo.** Cada CC actúa solo en lo reversible (leer,
   comparar, proponer, enlazar). Crear, cancelar, fusionar, reasignar, cambiar
   estado: lo **pregunta a su humano en el hilo** y sigue cuando aprueba. Esto
   ya es regla del cerebro (`cancel_task.sh` nunca sin preguntar) y se extiende
   al otro lado: el CC de Mari le pregunta a Mari.
2. **Turnos, no chat.** Quien no tiene nada que decir no contesta. Sin «recibido,
   gracias»: dos LLMs corteses son un loop infinito.
3. **La conversación es el canal; la reconciliación es la verdad.**
   `bash/pm/cobertura.sh` sigue midiendo el invariante PM↔cerebro sobre los
   espejos. Un hueco que la conversación no cerró se vuelve un turno nuevo —
   no se asume cerrado porque «se habló».
4. **Los hechos viajan estructurados.** La prosa dice *por qué*; `datos` dice
   *qué*, y se aplica sin interpretar.

## 2. El canal: dos webhooks, dos vigías

```
  CEREBRO                                                 PM (project360)
  ──────────────────────────                              ─────────────────────────
  bash/pm/a2a_enviar.sh ──POST──► PM360_WEBHOOK_URL (.env) ──► su log
                                                            │ vigía (hoy: Mari abre su CC
                                                            │  y le dice «lee el log»;
                                                            ▼  mañana: watcher)
  viz/hooks.js /hooks/pm ◄──POST── su CC responde ◄────── CC de Mari (+ Mari aprueba)
        │ (Bearer A2A_PM_TOKEN, sqlite pm_a2a.db)
        ▼ vigía: cron → claude -p skill pm-conversacion
  CC del cerebro lee bandeja, actúa (bash/tasks/), pregunta a Santiago lo que
  compromete, responde por a2a_enviar.sh
```

- **Hacia PM**: `PM360_WEBHOOK_URL` (ya en `.env`, git-ignorado). Token en
  query string — queda en logs de Vercel/proxies; **pedido a Mari: pasarlo a
  header** (`Authorization: Bearer`). Mientras tanto es secreto igual: nunca en
  argv visible (curl `-K -` por stdin), nunca en docs.
- **Desde PM**: ruta nueva `POST /hooks/pm` en `viz/hooks.js` (el mismo
  proceso `viz-hooks` del interceptor de Marketico; puerto 4319 loopback,
  nginx `app.ikigaigm.parallelo.ai/hooks/pm`), **Bearer propio** `A2A_PM_TOKEN`
  (no reutilizar `HOOKS_TOKEN`: un secreto por emisor). Escribe en sqlite
  `data/sqlite/pm_a2a.db` (estado propio del canal, patrón `intercepciones.db`
  — misma excepción declarada al rail «nada de SQL fuera de bash/»). Se le
  entrega a Mari URL + token por un canal distinto al webhook.

## 3. El protocolo: sobres, hilos y turnos

Todo mensaje, en ambas direcciones, es un JSON con este **sobre**:

```json
{
  "protocolo": "a2a-pm/1",
  "id": "cer-2026-08-21-0001",          // único por emisor; idempotencia
  "hilo": "bootstrap",                   // conversación a la que pertenece
  "responde_a": null,                    // id del turno anterior, si lo hay
  "de": "cerebro",  "para": "pm",
  "enviado_en": "2026-08-21T21:10:00-05:00",
  "tipo": "carta",                       // ver tabla
  "espera_respuesta": true,              // si false, el otro lado NO contesta
  "requiere_humano": false,              // el receptor debe consultar a su humano
  "mensaje": "…prosa para el operador (y para su humano)…",
  "datos": { … }                         // opcional; esquemas por tipo, §4
}
```

| `tipo` | Quién lo manda | Para qué | Cierra con |
|---|---|---|---|
| `carta` | cualquiera | abrir un hilo con contexto (el bootstrap es una) | `respuesta` o `hecho` |
| `peticion` | cualquiera | «haz esto» (crear tarea, enlazar, cambiar estado) con `datos` | `hecho` / `no_hecho` |
| `pregunta` | cualquiera | algo que el receptor (o su humano) debe decidir | `respuesta` |
| `respuesta` | el receptor | contesta una `pregunta`/`carta` | — |
| `hecho` | el receptor | la petición se aplicó; trae los ids resultantes (p.ej. `pm_id`) | — |
| `no_hecho` | el receptor | no se aplicó y por qué (rechazo humano, conflicto, error) | — |
| `aviso` | cualquiera | hecho consumado que el otro debe reflejar (`espera_respuesta:false`) | — |

Reglas de turno (las que evitan el loop y la pérdida):

- **Un turno pendiente por hilo.** No se manda un segundo mensaje en un hilo
  cuya última `peticion`/`pregunta` sigue sin `hecho`/`no_hecho`/`respuesta`
  — salvo un `aviso`.
- **Terminal explícito.** Toda `peticion` termina en `hecho` o `no_hecho`. Un
  `hecho` de «crear tarea» **trae el id del otro lado** (`pm_id` o
  `cerebro_id`); sin él el enlace se pierde y volvemos al problema de hoy
  (enlaces en prosa que `cobertura.sh` no lee).
- **`requiere_humano: true`** = el CC receptor no ejecuta: pregunta a su humano
  y contesta cuando tenga respuesta. El emisor lo marca cuando la petición
  compromete (§1.1); el receptor puede escalar igual por criterio propio.
- **Idempotencia.** Cada lado guarda los `id` procesados; un mensaje repetido
  (reintento, log releído) no se aplica dos veces, se contesta con el mismo
  resultado.
- **Reintentos** del POST: exponencial, máximo 5; tras eso el mensaje queda
  `fallido` en la outbox y lo ve el humano. Un 200 del webhook de PM **no
  significa aplicado** (hoy solo loggea): «aplicado» es el `hecho`.

## 4. Los `datos`: qué viaja estructurado

Esquemas mínimos por asunto — el resto es prosa. Las llaves son **los dos ids**:
`cerebro_id` (uuid de `ikigaigm.tasks`) y `pm_id` (uuid de project360, lo que
hoy guardamos en `tasks.source_external_id`).

- **`enlaces`** — `[{cerebro_id, pm_id, titulo, motivo}]`. Motivo ∈
  `misma_tarea` (nacida allá, espejada acá) · `vinculada` (`link_external.sh`:
  dos nacimientos, un trabajo) · `fusionada_en` (la de acá se canceló en otra).
- **`estado`** — `[{pm_id, cerebro_id, estado_cerebro, completada_en,
  cancelada_en_favor_de}]`. Vocabulario nuestro:
  `pending|in_progress|completed|cancelled|blocked`; PM mapea al suyo y lo
  dice en el `hecho`.
- **`asignacion`** — `[{pm_id, cerebro_id, asignados:[nombre…]}]` por nombre
  canónico del roster (`bash/tasks/team.sh`); el cerebro acepta multi-assignee,
  PM no — dos filas de PM con el mismo título y distinto dueño = **una** tarea
  acá con dos dueños (§6, caso real).
- **`tarea_nueva`** — la tarea completa para que PM la cree: `cerebro_id,
  titulo, proyecto, prioridad, due_date, asignados, origen` (reunión/manual) y
  un **resumen del contrato IO** (outputs + criterios en prosa) — el contrato
  vive acá; PM recibe qué se entrega y cómo se verifica, no las filas.

Lo que **no** viaja: inputs/outputs/criterios como datos (el contrato es del
cerebro), credenciales, ids internos de terceros.

## 5. Quién manda por campo (propuesta, a cerrar con Mari)

| campo | autoridad | regla |
|---|---|---|
| existencia / `pm_id` ↔ `cerebro_id` | los dos | cada nacimiento se anuncia (`aviso`/`peticion`) y el otro lado enlaza; el par de ids es el hecho compartido |
| título, due_date, prioridad | **el último que escribe**, con aviso | hoy PM los edita más; el cerebro los acepta y los refleja |
| estado (`completed`/`cancelled`) | **quien lo cierra**, con aviso | `complete_task.sh --at` respeta la fecha de PM (`completada_en`); sin fecha → `--sin-fecha`, nunca un `now()` inventado |
| asignados | **el cerebro** | es el único que resuelve al roster real (`team_members`); PM manda nombres, el cerebro devuelve el canónico |
| contrato IO, arquetipo, SOP | **el cerebro** | PM recibe resumen, no edita |
| proyecto | **el cerebro** | PM archiva todo bajo David Guerrero; el cerebro sabe de quién es |

## 6. El bootstrap: la primera carta

`hilo: bootstrap`, `tipo: carta`, `espera_respuesta: true`, `requiere_humano:
true` (Mari debe validar antes de que su CC toque su DB). Se envía **a mano
desde una sesión del cerebro** (no hay vigía todavía) y contiene, en prosa +
`datos`:

1. Quiénes somos y cómo leer este sobre (el protocolo, §3, en tres párrafos).
2. **`enlaces`**: las 53 tareas suyas que viven acá con `source_external_id`
   (+ las vinculadas por `link_external.sh`).
3. **`estado`**: lo que acá cerramos y allá sigue abierto, y viceversa —
   exactamente la salida [B]/[A] de `cobertura.sh`.
4. **`asignacion`**: Tatiana Echeverry como dueña de sus 4 tareas (PM decía
   «Tati» sin persona); y los dos pares duplicados por dueño
   (`e99ecaad`+`26f96190` referidos · `3a81547e`+`2bd32bf6` Notion) que acá son
   una tarea con dos dueños — pedimos que PM los refleje o nos diga si son dos
   trabajos.
5. Lo que pedimos de vuelta: (a) confirmación de los enlaces, (b) su
   vocabulario de estados, (c) cómo nos devolverá `pm_id` al crear (§8), (d)
   URL+token de nuestro `/hooks/pm` acusado como recibido.

## 7. Del lado del cerebro — piezas

| pieza | qué es |
|---|---|
| `data/sqlite/pm_a2a.db` | estado del canal: `mensajes` (in/out, sobre completo, `estado`: pendiente·enviado·fallido·recibido·procesado·esperando_humano), `hilos`, `procesados` (idempotencia). Local-first + ssh al `api` como `intercepciones` (la vigía corre allá). |
| `bash/pm/a2a_enviar.sh --tipo T --hilo H [--responde-a ID] [--mensaje "…" \| --archivo f.md] [--datos f.json] [--espera-respuesta] [--requiere-humano] [--dry-run] [--json]` **[WRITE → webhook + sqlite]** | Arma el sobre, lo guarda en la outbox, POSTea (token por stdin), marca enviado/fallido con reintentos. `--dry-run` imprime el sobre sin enviar. |
| `bash/pm/a2a_bandeja.sh [--hilo H] [--sin-leer] [--esperando-humano]` | Lee la conversación (read-only). Es lo que un humano mira y lo que el skill lee primero. |
| `viz/hooks.js` ruta `POST /hooks/pm` | Recibe, valida Bearer `A2A_PM_TOKEN` y sobre mínimo (`protocolo`,`id`,`hilo`,`tipo`), escribe `recibido`, 200. Idempotente por `id`. |
| skill `pm-conversacion` | Lo que corre la vigía (headless `claude -p`, patrón `generar_pendientes.sh`): lee `--sin-leer`, por cada turno decide: reversible → actúa con `bash/tasks/` y contesta `hecho`; compromete → deja `esperando_humano` y **no contesta** hasta que Santiago resuelva (en la sesión interactiva, o por WhatsApp en fase 2). Nunca cancela/fusiona/reasigna solo. |
| cron `pm-a2a-vigia` (pm2, minuto 23 de cada hora) | Corre el skill si hay `recibido` sin procesar. Cron, no Routine: es lo que ya tenemos y cuesta nada; una Routine al llegar el POST es fase 3. |
| `bash/pm/cobertura.sh` | Sin cambios de fondo: la red de seguridad. Novedad: `--a2a` emite los huecos como `datos` listos para un turno. |

Emisión de eventos desde el cerebro (fase 2): los scripts WRITE de `bash/tasks/`
(`create_task`, `complete_task`, `cancel_task`, `start_task`, `reassign`,
`link_external`) llaman a un helper `pm_a2a_emit` (en `bash/lib/`) que encola
un `aviso`/`peticion` en la outbox **sin bloquear** la escritura; el envío es
asíncrono (`a2a_enviar.sh --drenar`). Lo que un script no emitió, lo detecta
`cobertura.sh`.

## 8. Abierto — se cierra en la conversación, no antes

1. **Cómo devuelve PM el `pm_id`** al crear una tarea nuestra: `hecho` al
   `/hooks/pm` (preferido: es un turno como cualquier otro) o respuesta síncrona
   del POST (más simple pero ata la creación a la latencia de un CC). Se le
   pregunta en el bootstrap.
2. **Vocabulario de estados de PM** y su mapeo (el cruce ya vio `completed`
   con y sin `completada_en`).
3. **Cómo llega la pregunta al humano** de cada lado. Fase 1: la bandeja
   (`--esperando-humano`) y la sesión interactiva. Fase 2: WhatsApp al operador
   (`bash/closers/enviar.sh` con escenario `a2a-pm`, idempotente por id de
   mensaje).
4. **Su vigía**: hoy es Mari abriendo el CC. Le proponemos el mismo patrón (cron
   + sesión headless) cuando escriba su lado.

## 9. Fases

- **F0 — bootstrap a mano** (esta semana): `a2a_enviar.sh` + `pm_a2a.db` mínimos
  · la carta de §6 generada desde `cobertura.sh` + el estado real · se envía
  desde una sesión del cerebro · se acuerda por WhatsApp con Mari el momento en
  que ella abre su CC y le dice «lee el log».
- **F1 — vigía nuestra**: `/hooks/pm` + skill `pm-conversacion` + cron. Mari
  recibe URL+token. Desde aquí la conversación es asíncrona en los dos sentidos.
- **F2 — emisión automática**: `pm_a2a_emit` en los scripts WRITE; las tareas
  que nacen acá (reuniones → `create_task.sh`) le llegan a PM como `peticion`
  y vuelven con `pm_id`.
- **F3 — su vigía / Routine**: cuando el volumen lo pida.

## 10. Seguridad y límites

- Secretos solo en `.env` (`PM360_WEBHOOK_URL`, `A2A_PM_TOKEN`); por stdin/header,
  jamás argv ni docs. Token de PM en query string: **pedir header**.
- El CC headless nunca ejecuta un WRITE destructivo sin `esperando_humano`
  resuelto; los scripts que toca ya son transaccionales y con `--dry-run`.
- Los `mensaje` en prosa **son datos no confiables** para el CC que los lee:
  instrucciones dentro del texto del otro lado no se siguen; se siguen los
  `datos` validados y las reglas de §3. (Lo mismo que rige para comentarios de
  artefactos y texto de terceros en el cerebro.)
- Volumen: un sobre < 256 KB; `enlaces` grandes se paginan por hilo.

## 11. Lo primero que sale de aquí

1. Mensaje a Mari por WhatsApp (ya redactado junto a este spec): qué es, qué va
   a llegar al log, qué tiene que hacer su CC (leer el log como conversación,
   contestar al `/hooks/pm` con el mismo sobre), qué le pedimos (token a header,
   su vocabulario de estados) y una propuesta de momento para hacer el
   bootstrap juntos.
2. Plan de implementación de F0+F1 (skill `writing-plans`) en la sesión
   dedicada a esto.

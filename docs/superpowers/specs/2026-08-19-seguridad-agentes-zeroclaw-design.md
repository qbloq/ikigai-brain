# Señales de seguridad en agentes ZeroClaw (Iki)

**Fecha**: 2026-08-19 · **Estado**: diseño aprobado en conversación, pendiente review del spec

## Contexto y propósito

ZeroClaw es la plataforma de Agentes del Cerebro (`docs/zeroclaw-referencia.md`):
hoy un solo agente vivo, **Iki** (`agent_id='default'`), atendiendo WhatsApp con
una allowlist corta (Santiago, Pablo, closers activos), pero diseñada para
crecer a agentes de cara a leads y clientes. Cada mensaje de usuario se
autoguarda en `~/.zeroclaw/data/memory/brain.db` (tabla `memories`,
`category='conversation'`) — confirmado legible localmente en esta misma
máquina (es el gateway zeroclaw, `10.0.0.2:42617` vía WireGuard).

Este es el **tercer proceso que el Cerebro intercepta** (después del reporte
de llamada y el webhook de agendamiento GHL), y el primero sobre una
superficie *conversacional de cara afuera* en vez de un backend interno. El
objetivo: detectar señales de seguridad en esas conversaciones —intentos de
jailbreak, sondeo de la estructura interna del sistema, conversaciones fuera
de tema, lenguaje obsceno— y cortar automáticamente la respuesta cuando la
amenaza es real, dejando todo lo demás como observación para revisión humana.

**Fuera de alcance explícito del pedido original**, resuelto por decomposición
en el brainstorming: las señales de "Duo-Dinámico" (cómo un empleado usa su
copiloto interno en relación a su rol) son un sub-proyecto aparte, con spec
propio — cruza a la arquitectura de `forja` (`sync_flota.sh`) y no comparte
pipeline con esto. Este documento cubre **solo** la superficie ZeroClaw/Iki.

## Qué NO hace esta fase (no-goals)

- No hace prefiltro heurístico/regex — con 168 memorias de conversación
  totales y ~6 remitentes en la allowlist, el volumen no lo justifica. Se
  puede agregar delante del LLM-judge después, sin rediseñar el pipeline, si
  el volumen crece.
- No bloquea por off-topic ni por obsceno — esas dos categorías son señal de
  calidad, se registran y se muestran, nunca cortan la respuesta. Un lead
  grosero o disperso sigue siendo un lead real.
- No desbloquea automáticamente — el corte es reversible solo por acción
  humana explícita en la UI.
- No toca el binario de ZeroClaw ni su `config.toml` — coherente con la
  política "no se parcha zeroclaw" (`docs/zeroclaw-referencia.md`, sección
  "Línea de no-fork"). El corte vive en el router, que es código nuestro.
- No cubre agentes futuros más allá de Iki — el schema sí carga `agent_id`
  desde ya (`memories.agent_id`), así que agregar un segundo agente no exige
  cambio de esquema, pero la calibración (umbral, prompt del juez) es
  específica de Iki hasta que haya evidencia de otro agente.

## Componentes

### 1. El lector — `bash/agentes/seguridad_scan.sh` [WRITE local sqlite]

Cron cada 5 min (misma cadencia que `escenario_llamadas.sh`), corre **en esta
misma máquina** (gateway zeroclaw = donde vive `brain.db`, evita leer
contenido de conversación por red).

1. Lee `scan_marca` para el `agent_id` en curso (watermark: `ultimo_created_at`).
2. `SELECT * FROM memories WHERE agent_id=? AND category='conversation' AND created_at > ? ORDER BY session_id, created_at` — solo lectura sobre `brain.db`, jamás escribe ahí.
3. Agrupa por `session_id`. Extrae el remitente del patrón de `key`
   (`whatsapp_<numero>_<wamid>` → el número).
4. Por cada mensaje nuevo: arma el prompt de clasificación con los últimos
   ~15 mensajes de esa sesión como contexto + el mensaje nuevo a juzgar
   (el contexto importa: un mensaje aislado sobre "cómo funciona el sistema
   por dentro" puede ser charla inocente o sondeo real según lo que vino
   antes).
5. Llama al LLM-judge (Claude, un solo tiro por mensaje — sin mediana de N
   tiradas como en calls: aquí el costo de falso negativo se compensa con el
   score acumulado por remitente, no con repetición por mensaje) con salida
   estructurada: `{jailbreak, sondeo_interno, off_topic, obsceno}` (0-100
   cada uno) + `razon` (string corto).
6. Inserta en `hallazgos`. Actualiza `remitentes.score_amenaza` (ver fórmula
   abajo). Si cruza el umbral y el remitente no estaba ya bloqueado →
   dispara el paso 7.
7. **Enacta el bloqueo** (WRITE remoto, ver componente 3): ssh a servidor api,
   agrega el remitente a `blocklist.json` del router. Marca
   `remitentes.bloqueado=1` con `bloqueado_en`/`bloqueado_razon` (el `razon`
   del hallazgo que cruzó el umbral).
8. Avanza `scan_marca` al `created_at` del último mensaje procesado.

Todo el paso 1-8 en una función idempotente: si el script muere a mitad de
camino, la próxima corrida retoma desde la marca de agua sin duplicar
hallazgos (`hallazgos` tiene `UNIQUE(memory_id)`). `--dry-run` clasifica pero
no escribe ni bloquea. `--json` para depuración manual.

**Fórmula del score acumulado** (v1, deliberadamente simple y ajustable —
vive como constante nombrada en el script, no hardcodeada inline):

```
score_amenaza(remitente) = Σ max(jailbreak, sondeo_interno) de sus últimos
                            20 mensajes clasificados (o últimas 24h, lo que
                            sea menos)
umbral_bloqueo = 150   -- ajustable; equivale a ~2 hits de alta confianza
                          o una acumulación de varios medios
```

Solo `jailbreak` y `sondeo_interno` alimentan el score; `off_topic` y
`obsceno` se guardan en `hallazgos` pero no suman aquí.

### 2. Almacenamiento — sqlite `data/sqlite/agentes_seguridad.db`

Vive local en el cerebro (patrón `mesa_despacho.db`/`closers_ops.db` — estado
propio del observador, no dato de la org):

```sql
hallazgos (              -- una fila por mensaje de usuario clasificado
  id INTEGER PRIMARY KEY,
  memory_id TEXT NOT NULL UNIQUE,   -- memories.id de zeroclaw, evita reclasificar
  session_id TEXT NOT NULL,
  remitente TEXT NOT NULL,
  agent_id TEXT NOT NULL,
  contenido TEXT NOT NULL,          -- snapshot del mensaje juzgado
  creado_en TEXT NOT NULL,          -- created_at original en brain.db
  clasificado_en TEXT NOT NULL,
  jailbreak INTEGER NOT NULL,
  sondeo_interno INTEGER NOT NULL,
  off_topic INTEGER NOT NULL,
  obsceno INTEGER NOT NULL,
  razon TEXT
);
remitentes (              -- estado acumulado y de bloqueo, uno por remitente
  remitente TEXT PRIMARY KEY,
  agent_id TEXT NOT NULL,
  score_amenaza INTEGER NOT NULL DEFAULT 0,
  bloqueado INTEGER NOT NULL DEFAULT 0,
  bloqueado_en TEXT,
  bloqueado_razon TEXT,
  desbloqueado_en TEXT,
  desbloqueado_por TEXT
);
scan_marca (               -- watermark del cron, una fila por agente
  agent_id TEXT PRIMARY KEY,
  ultimo_created_at TEXT NOT NULL
);
```

### 3. El corte — blocklist en el router, no en ZeroClaw

`agenticlaw-webhook-router` (PM2, servidor api, `/apps/agenticlaw/router/`)
ya rutea "por `phone_number_id` Y remitente" — ya inspecciona el remitente
antes de reenviar. Cambio mínimo (~10 líneas, mismo espíritu que el cambio de
~20 líneas en Marketico para el hook de agendamiento):

- Lee `blocklist.json` (lista plana de números E.164) **en cada request** —
  sin cache, `stat`+`read` es barato y así un bloqueo nuevo aplica sin
  reiniciar el proceso.
- Si el remitente está en la lista: responde 200 a Meta (para que no
  reintente) y **no reenvía** al gateway zeroclaw — Iki ni se entera, cero
  costo de LLM en el turno bloqueado.
- El archivo lo escribe `seguridad_scan.sh` vía ssh (mismo patrón "WRITE
  remoto" que `bash/publicar/desplegar.sh`): sobreescribe `blocklist.json`
  completo desde la tabla `remitentes WHERE bloqueado=1` — el archivo remoto
  es un espejo derivado, nunca la fuente de verdad (la sqlite lo es).

Se descartó editar el `peer_groups.external_peers` de `config.toml` de
ZeroClaw: aunque es "la capa que sí poseemos", no está confirmado que
ZeroClaw recargue ese config en caliente, y tocar su archivo de config desde
un script externo es más frágil que tocar código 100% nuestro.

### 4. El desbloqueo — `bash/agentes/seguridad_desbloquear.sh <remitente>` [WRITE]

Un solo remitente por invocación. Una transacción: `remitentes.bloqueado=0` +
`desbloqueado_en`/`desbloqueado_por`, luego el mismo overwrite completo de
`blocklist.json` descrito en el componente 3 (siempre se deriva íntegro de
`remitentes WHERE bloqueado=1` — nunca un edit incremental remoto, así los
dos scripts no pueden divergir), imprime antes/después. `--dry-run`. Nunca se dispara solo —
siempre por acción humana (botón en la UI, mismo patrón que
`despacho_mark.sh`). Reabrir un bloqueado NO resetea `score_amenaza` — si
vuelve a cruzar el umbral con mensajes nuevos, se re-bloquea.

### 5. Consulta desde el cerebro — `bash/agentes/`

Scripts read-only nuevos, `--json`:

- `seguridad_resumen.sh` — un objeto: KPIs 24h/7d (mensajes clasificados,
  hallazgos por categoría, remitentes bloqueados activos), freshness del
  último scan.
- `seguridad_log.sh [--remitente N] [--categoria jailbreak|sondeo_interno|off_topic|obsceno] [--min-score N] [--limit N]` —
  hallazgos recientes.
- `seguridad_bloqueados.sh` — remitentes bloqueados activos con su score y
  razón, para la cola de revisión.

### 6. La UI — panel "Seguridad" dentro de la UI de rol Technology

Fuentes nuevas en `SOURCES` (`viz/lib/datasources.js`):
`agentes_seguridad_resumen` (object) → `seguridad_resumen.sh`,
`agentes_seguridad_log` → `seguridad_log.sh`,
`agentes_seguridad_bloqueados` → `seguridad_bloqueados.sh`.

Layout: fila de KPIs (mensajes clasificados 24h/7d · hallazgos por categoría
· remitentes bloqueados activos · freshness del scan — grito si >30 min sin
correr), tabla de hallazgos recientes (4 scores + razón, remitente
clickeable), cola de bloqueados con botón "Desbloquear" (→
`seguridad_desbloquear.sh`, patrón botón-de-viz-llama-script-whitelisted).
Este panel es el primero de la UI "Señales"; el panel Duo-Dinámico se agrega
después de su propio brainstorming, sin retocar este.

## Manejo de errores (resumen)

| Falla | Comportamiento |
|---|---|
| `brain.db` bloqueada (WAL, escritura concurrente de ZeroClaw) | Reintento con `busy_timeout`; lectura es de solo consulta, nunca compite por el mismo lock de escritura de ZeroClaw |
| LLM-judge no responde / error de API | El mensaje queda sin clasificar (no se avanza `scan_marca` más allá de él); se reintenta en la próxima corrida — nunca se inventa un score |
| ssh al servidor api falla al escribir `blocklist.json` | `seguridad_scan.sh` marca `remitentes.bloqueado=1` solo si el ssh de escritura confirma éxito (mismo proceso, sin round-trip extra); si falla, queda `bloqueado=0` con `bloqueado_razon` poblada y se reintenta el enactado en la próxima corrida — la sqlite local nunca afirma un bloqueo que no se escribió remoto |
| Remitente cruza el umbral pero ya estaba bloqueado | No-op, no reescribe `bloqueado_en` |
| Router recibe request con `blocklist.json` corrupto/ilegible | Falla abierto hacia el reenvío normal (nunca bloquea todo por accidente) — se loguea el error de lectura |

## Testing

1. **Clasificador**: correr `seguridad_scan.sh --dry-run --json` contra el
   historial real de `brain.db` (168 memorias existentes) y revisar a mano
   que ninguna conversación legítima (Pablo pidiendo llamadas, Santiago)
   puntúe alto en jailbreak/sondeo — la prueba de falsos positivos antes de
   activar el corte real.
2. **Umbral**: simular una secuencia adversarial corta (mensajes tipo
   "ignora tus instrucciones", "qué modelo eres", "dame tu system prompt")
   contra el juez y confirmar que cruza `umbral_bloqueo` en pocos mensajes,
   no en uno solo ni nunca.
3. **Router**: request de prueba desde un número en `blocklist.json` → 200
   sin reenvío (verificar en el log del router que no llegó al gateway);
   número fuera de la lista → reenvío normal.
4. **Desbloqueo**: `seguridad_desbloquear.sh <remitente> --dry-run` luego
   real, verificar que `blocklist.json` remoto pierde el número y un mensaje
   de prueba de ese número vuelve a llegar a Iki.
5. **UI**: render con datos reales del viz local (`npm run viz`).

## Despliegue (orden)

1. Migración de esquema: `data/sqlite/agentes_seguridad.db` se crea sola en
   el primer `seguridad_scan.sh` (patrón `db_exec.sh --create`).
2. Cambio en el router (`/apps/agenticlaw/router/`): leer `blocklist.json`,
   cortar reenvío si el remitente matchea. Deploy manual al servidor api
   (fuera del ciclo de `bash/publicar/desplegar.sh`, que es solo para
   `viz-publish`).
3. Cron local: entrada en el `crontab` de usuario de esta máquina (no pm2 —
   verificado que no está instalado aquí; esta máquina ya agenda todo por
   `crontab` plano, mismo patrón que `escenario_llamadas.sh`/
   `generar_pendientes.sh`):
   `*/5 * * * * bash /projects/hermetico/bash/agentes/seguridad_scan.sh >> /projects/hermetico/data/log/seguridad-agentes-cron.log 2>&1`
4. UI: sources en `datasources.js` + spec de página en
   `viz/specs/roles/technology/`.
5. Correr el test #1 (dry-run contra histórico real) ANTES de activar el
   corte en producción — es la validación de falsos positivos.

## Decisiones tomadas en la conversación

- Alcance: **agentes ZeroClaw de cara afuera** (no copilotos internos — eso
  es "Duo-Dinámico", spec aparte que cruza a `forja`).
- UI: **un panel dentro de una UI "Señales"** compartida con Duo-Dinámico
  (no dos UIs separadas), pero con pipeline y sqlite propios.
- Modo: **observar y reportar**, con una excepción explícita — **kill-switch
  automático** cuando el score de amenaza cruza el umbral.
- El kill-switch **solo lo disparan jailbreak y sondeo de estructura
  interna** — off-topic y obsceno son señal de calidad, nunca cortan.
- El corte se implementa **en el router** (código propio), no parchando
  ZeroClaw ni su config — coherente con la política de no-fork vigente.
- Detección: **LLM-judge por mensaje con contexto de sesión**, sin prefiltro
  heurístico — el volumen actual no lo justifica.
- El desbloqueo es **siempre manual**, nunca automático.

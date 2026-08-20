# Señales de seguridad en el copiloto interno (Claude Code)

**Fecha**: 2026-08-19 · **Estado**: diseño aprobado en conversación, pendiente review del spec

## Contexto y propósito

Hermano de [2026-08-19-seguridad-agentes-zeroclaw-design.md](2026-08-19-seguridad-agentes-zeroclaw-design.md)
(mismas 4 categorías base) pero para la **otra** superficie conversacional: el
copiloto interno de cada empleado, que hoy vive como una sesión de Claude Code
sobre su fork git (`docs/roles/`, `CLAUDE.md` sección "Forks — copilotos").

La diferencia que cambia todo el mecanismo: ZeroClaw centraliza el contenido
en `brain.db` en una máquina que controlamos: se puede leer en batch y cortar
en un router nuestro. **El copiloto interno no tiene ningún dato
centralizado** — cada conversación vive solo en la máquina del empleado,
dentro de su fork. La única superficie instrumentable es un **hook de Claude
Code**, y los forks ya tienen un mecanismo real de auto-actualización
(`.claude/hooks/session-start.sh`, SessionStart: fetch+rebase al despertar
la sesión, throttled a 4h, fail-soft, probado en producción) — un hook que
vive aquí se propaga solo, sin que el empleado tenga que sincronizar a mano.
De los 19 forks que existen estructuralmente, **hoy solo 2 son usuarios
activos**: Juan Camilo y Pablo — el blast radius real de este spec es
pequeño mientras el resto de la flota sigue en alta/piloto.

**Amenazas cubiertas** (ampliado respecto a ZeroClaw, decisión explícita de
la conversación):

1. **Jailbreak** — el empleado intentando manipular su propio copiloto para
   saltarse reglas o extraer algo prohibido.
2. **Sondeo de estructura interna** — igual que en ZeroClaw.
3. **Contenido externo inyectado** — un transcript, una página de Notion, un
   webhook, un doc de Drive que el copiloto *lee* y que intenta secuestrar su
   comportamiento. Aquí el empleado es la víctima/vector, no el atacante —
   precedente directo: la preocupación ya documentada en ZeroClaw de "un Iki
   inyectado podría aprobarse despachos".
4. **Off-topic / obsceno** — igual que ZeroClaw, nunca bloquean.
5. **Desviación de dominio/rol** — uso del copiloto claramente fuera del
   dominio de negocio que le corresponde a su rol (`copilot.json` ya declara
   `role`). Señal de calidad, no bloquea.

## Qué NO hace esta fase (no-goals)

- No manda contenido completo de conversación a ningún lado — solo extractos
  cortos y redactados en el incidente que se reporta, y solo cuando hay
  hallazgo real. La regla "git es telemetría, contenido nunca" para
  telemetría *estructural* sigue intacta; esto es una excepción acotada y
  deliberada, justificada por seguridad, no por medir productividad.
- No pretende ser inevadible. Un empleado con acceso a su propia máquina
  puede editar o borrar el hook — a diferencia de ZeroClaw, esta
  infraestructura no es 100% nuestra. Esto es una limitación aceptada de v1,
  no un bug a resolver aquí (ver "Decisiones" al final).
- No bloquea sincrónicamente en el turno donde ocurre la desviación semántica
  (salvo el tripwire de frases obvias) — hay un turno de rezago porque la
  clasificación fina corre async para no meterle latencia a cada mensaje.
- No construye el chequeo de integridad del hook mismo (detectar si alguien
  lo desactivó, vía diff estructural en forja) — queda anotado como
  extensión futura, no en el alcance de este spec.
- No automatiza la entrega del token de desbloqueo al empleado (WhatsApp,
  Slack, lo que sea) — eso es un paso humano fuera de este sistema.

## Componentes

### 1. Enforcement — `.claude/hooks/seguridad-prompt.sh` (evento `UserPromptSubmit`)

Vive en este repo, se agrega a `.claude/settings.json` (ya usado hoy para
`SessionStart`). Se propaga a los forks en su próximo `pull --rebase`. Corre
ANTES de aceptar cada prompt, y hace solo dos cosas — ambas baratas,
ninguna añade latencia real:

1. **Tripwire síncrono barato**: regex sobre una lista corta y curada de
   frases obvias de jailbreak/extracción ("ignora tus instrucciones
   anteriores", "cuál es tu system prompt", variantes) contra el prompt
   actual. Si matchea: bloqueo inmediato (decisión `block` con razón),
   `score_amenaza` local salta directo al umbral, se dispara el reporte del
   componente 5 sin esperar clasificación fina.
2. **Chequeo de estado**: si `.claude/state/seguridad.json` ya tiene
   `bloqueado=true` (puesto por el hook de clasificación del turno
   anterior, ver abajo) → `block` inmediato, sin más trabajo.

Ninguna clasificación semántica ocurre aquí — por diseño, para no meterle
una llamada a LLM al camino crítico del mensaje del usuario.

### 2. Clasificación — `.claude/hooks/seguridad-clasificar.sh` (evento `Stop`)

Corre DESPUÉS de cada turno completo (la respuesta del copiloto ya se
entregó), así que su latencia no la percibe el usuario en ese turno — y a
diferencia de "drenar en el próximo prompt", cubre también el **último**
mensaje de una sesión (un `Stop` dispara siempre al cerrar el turno, exista
o no un mensaje siguiente).

1. Clasifica el prompt del usuario que acaba de cerrar turno con un
   LLM-judge liviano (Haiku, salida estructurada `{jailbreak, sondeo_interno,
   off_topic, obsceno, desviacion_rol}` 0-100 + `razon`), usando los últimos
   ~15 turnos como contexto de sesión.
2. Actualiza el estado local: agrega a `hallazgos_recientes`, recalcula
   `score_amenaza` = suma de `max(jailbreak, sondeo_interno)` de los últimos
   N mensajes clasificados (umbral inicial a calibrar por separado: el
   modelo/latencia son distintos a ZeroClaw).
3. **Si cruza el umbral**: marca `bloqueado=true` + `bloqueado_en`/
   `bloqueado_razon` en el estado local (efectivo desde el PRÓXIMO
   `UserPromptSubmit`, componente 1) y dispara el reporte del componente 5.

`off_topic`/`obsceno`/`desviacion_rol` se acumulan y se reportan igual (para
la UI), pero nunca alimentan `score_amenaza` ni el bloqueo.

### 3. El escaneo de contenido inyectado — evento `PostToolUse`

Hook separado (`.claude/hooks/seguridad-contenido.sh`), filtrado a tools de
lectura de fuentes externas/no confiables (`WebFetch`, y los `Bash` que
invocan scripts de `bash/notion/`, `bash/google/`, lectura de transcripts).
Escanea el resultado de la tool por patrones de instrucción embebida
("ignora lo anterior", bloques que se dirigen directamente al modelo en
segunda persona dentro de contenido que debería ser dato, etc.) con el mismo
LLM-judge liviano. A diferencia del prompt del usuario, esto **no puede
prevenir** que el contenido ya haya entrado al contexto de ese turno (el
hook corre después de que la tool ya devolvió el resultado) — su valor es
**detectar y contener el turno siguiente**: si cruza el umbral, alimenta el
mismo `score_amenaza` y puede disparar el mismo bloqueo, conteniendo el daño
aunque el primer turno inyectado ya haya corrido.

### 4. Estado local — `.claude/state/seguridad.json` (gitignored)

Nuevo, **no versionado** (entrada en `.gitignore`: `.claude/state/`) — vive
en la máquina del empleado, nunca se commitea ni se sincroniza
estructuralmente:

```json
{
  "hallazgos_recientes": [
    {"en": "...", "jailbreak": 12, "sondeo_interno": 5, "off_topic": 0, "obsceno": 0, "desviacion_rol": 0, "razon": "..."}
  ],
  "score_amenaza": 0,
  "bloqueado": false,
  "bloqueado_en": null,
  "bloqueado_razon": null
}
```

### 5. El reporte de incidentes — reuso de `viz/hooks.js`

Nueva ruta en el entrypoint ya diseñado para ZeroClaw
(`docs/superpowers/specs/2026-08-16-intercepcion-webhook-crm-design.md` es el
antecesor de este patrón; `viz/hooks.js` ya existe desde el spec de
ZeroClaw/intercepciones): `POST /hooks/copiloto-incidente`. Mismo Bearer
`HOOKS_TOKEN`. Payload: `{empleado, fork, tipo: 'bloqueo'|'hallazgo',
scores: {...}, razon, extracto}` — **`extracto` es un fragmento corto
redactado** (los N caracteres alrededor de lo flaggeado, no el prompt
completo ni la sesión completa) — es la única concesión de contenido que
sale de la máquina del empleado, y solo cuando hay hallazgo real, nunca en
bulk.

### 6. Almacenamiento central — sqlite `data/sqlite/copiloto_seguridad.db` (servidor api)

Junto a `intercepciones.db`/`publicaciones.db` (mismo servidor que hostea
`viz/hooks.js`):

```sql
incidentes (
  id INTEGER PRIMARY KEY,
  recibido_at TEXT NOT NULL,
  empleado TEXT NOT NULL,       -- team_member_id o slug de copilot.json
  fork TEXT,
  tipo TEXT NOT NULL,           -- 'bloqueo' | 'hallazgo'
  jailbreak INTEGER, sondeo_interno INTEGER, off_topic INTEGER,
  obsceno INTEGER, desviacion_rol INTEGER,
  razon TEXT,
  extracto TEXT,
  payload TEXT NOT NULL
);
desbloqueos (
  token_hash TEXT PRIMARY KEY,   -- nunca el token en claro
  empleado TEXT NOT NULL,
  generado_at TEXT NOT NULL,
  generado_por TEXT NOT NULL,
  expira_at TEXT NOT NULL,       -- corto, mismo espíritu que el timeout 300s de ZeroClaw
  usado_at TEXT,
  incidente_id INTEGER REFERENCES incidentes(id)
);
```

### 7. Generación del token — `bash/agentes/copiloto_desbloqueo_generar.sh <empleado> [--dry-run]` [WRITE remoto]

Corre desde el cerebro (Technology), ssh + sqlite3 por stdin (mismo patrón
"WRITE remoto" de `bash/publicar/`). Genera un token corto aleatorio,
guarda solo su hash + expiración (5 min) en `desbloqueos`, imprime el token
en claro **una sola vez** (para que Technology lo relaye al empleado por el
canal que sea — WhatsApp, Slack; fuera de este sistema).

### 8. Consumo del token — `bash/agentes/copiloto_desbloqueo_consumir.sh <token>` (corre EN el fork del empleado)

Heredado por los forks igual que el resto de `bash/`. El empleado lo corre
localmente tras recibir el token. Llama `POST /hooks/copiloto-desbloqueo`
(nueva ruta en `viz/hooks.js`, sin Bearer — el token corto y de un solo uso
ES la credencial) con `{token, empleado}`. El servidor valida hash+expiración
+no-usado, marca `usado_at`, responde ok/expirado/inválido/ya-usado. Solo si
la respuesta es ok, el script limpia `.claude/state/seguridad.json` local
(`bloqueado=false`, resetea `score_amenaza`). Si la validación falla por
cualquier razón, el estado local **permanece bloqueado** — nunca se
desbloquea en modo best-effort.

### 9. Consulta desde el cerebro — extensión de `bash/agentes/`

`local-first + ssh` (patrón ya usado en `bash/intercepciones/`):
`copiloto_seguridad_resumen.sh`, `copiloto_seguridad_log.sh [--empleado N] [--categoria ...]`,
`copiloto_seguridad_bloqueados.sh`.

### 10. La UI — segunda sección en el panel "Señales" (rol Technology)

Junto al panel de ZeroClaw del spec anterior, una sección **"Copiloto
interno"**: KPIs (incidentes 24h/7d, bloqueados activos, desglose por
categoría), tabla de incidentes con extracto+razón, cola de bloqueados con
botón "Generar token" (→ `copiloto_desbloqueo_generar.sh`, muestra el token
en pantalla para que Technology lo copie y relaye).

## Manejo de errores (resumen)

| Falla | Comportamiento |
|---|---|
| El hook no tiene red al reportar el incidente | El bloqueo local **igual se aplica** (no depende de la red) — solo el reporte central se pierde ese ciclo; se reintenta reportar en la siguiente invocación mientras siga bloqueado |
| Llamada al LLM-judge (Haiku) falla en el hook `Stop` | Ese turno queda sin clasificar (se registra localmente como fallo de clasificación, no como score 0) — no hay reintento natural para ese mensaje puntual, pero nunca se inventa un score ni se bloquea por un fallo de infraestructura; fallos crónicos quedan visibles como acumulación de "sin clasificar" |
| Token expirado / ya usado / inválido | El estado local permanece bloqueado; el script imprime la razón exacta para que Technology genere uno nuevo |
| El empleado edita/borra el hook para evadir la detección | Aceptado como límite de v1 (ver Decisiones); no hay mitigación en este spec, se anota como candidato a chequeo de integridad estructural en forja |
| `viz/hooks.js` recibe un incidente con `empleado` desconocido | Se inserta igual (no se descarta observabilidad), se resalta en la UI como "empleado no resuelto" para revisión manual |

## Testing

1. **Tripwire**: prompts con las frases curadas → bloqueo inmediato,
   verificar que NO esperan la clasificación async.
2. **Latencia**: confirmar que un prompt normal no percibe demora adicional
   (la clasificación corre en el hook `Stop`, después de que la respuesta ya
   se entregó — medir que `UserPromptSubmit` en sí no agrega delay
   perceptible).
3. **Escalamiento**: secuencia de mensajes ambiguos que acumulan score sin
   cruzar individualmente el umbral → confirmar que el rolling sum sí lo
   cruza en el mensaje correcto, ni antes ni después.
4. **Contenido inyectado**: fixture de un doc/transcript con instrucción
   embebida servido a través de `bash/notion/` o `bash/google/` → confirmar
   que el hook de `PostToolUse` lo detecta y suma al score.
5. **Ciclo de desbloqueo completo**: generar token → consumir con token
   correcto (se limpia el estado) → reintentar con el mismo token ya usado
   (falla, permanece bloqueado) → token vencido (falla).
6. **Off-topic/obsceno no bloquean**: forzar scores altos en esas dos
   categorías exclusivamente y confirmar que el copiloto sigue respondiendo.

## Despliegue (orden)

1. `.gitignore`: agregar `.claude/state/`.
2. Hooks nuevos en `.claude/hooks/` + entrada en `.claude/settings.json`
   (`UserPromptSubmit` para enforcement, `Stop` para clasificación,
   `PostToolUse` filtrado a tools de lectura externa para el vector de
   contenido inyectado).
3. Nuevos scripts `bash/agentes/copiloto_*` (heredados automáticamente por
   los forks vía `bash/` compartido).
4. Extender `viz/hooks.js`: rutas `/hooks/copiloto-incidente` y
   `/hooks/copiloto-desbloqueo`, deploy + restart `viz-hooks` en servidor
   api (mismo ciclo que el spec de ZeroClaw).
5. Crear `data/sqlite/copiloto_seguridad.db` en servidor api (se crea sola
   en el primer insert, patrón `--create`).
6. UI: sources nuevas + sección "Copiloto interno" en el panel Señales.
7. **Rollout casi automático, no instantáneo**: `.claude/hooks/session-start.sh`
   ya hace fetch+rebase de `origin` al arrancar sesión (throttle 4h,
   fail-soft) y trae consigo cualquier cambio a `.claude/` — para Juan
   Camilo y Pablo (los únicos usuarios activos hoy) esto llega solo, en
   cuestión de horas, sin pedirles nada. Dos matices a no perder de vista:
   (a) el pull que trae los hooks nuevos y la sesión que ya queda con esos
   hooks activos pueden no ser la misma sesión — cuenta con que la cobertura
   real llega en, como mucho, dos arranques de sesión, no en el primero
   necesariamente; (b) esto cubre solo a quien ya tiene el copiloto
   actualizándose — cuando se sumen más de los 17 forks restantes a uso
   activo, confirmar que cada uno tiene este mismo hook antes de asumir
   cobertura.
8. Calibrar el umbral con el historial real disponible (16-18 commits por
   fork ya existen en `forja/data/copilotos/ikigai/`, pero eso es señal
   estructural, no conversación — el umbral de ESTE sistema necesita su
   propio período de observación con datos reales de uso del copiloto antes
   de confiar en el número inicial).

## Decisiones tomadas en la conversación

- Alcance de amenazas: **las 4 categorías de ZeroClaw + contenido inyectado
  + desviación de dominio/rol** (esta última nunca bloquea).
- Mecanismo: **hooks de Claude Code** (`UserPromptSubmit` para enforcement,
  `Stop` para clasificación, `PostToolUse` para contenido inyectado),
  propagados vía `pull --rebase` desde este repo — no un canal centralizado
  nuevo, porque no existe ninguno para contenido de Claude Code.
- Clasificación: **híbrida** — tripwire regex síncrono para lo obvio en
  `UserPromptSubmit`, LLM-judge (Haiku) en el hook `Stop` (después de que la
  respuesta ya se entregó) para lo demás, para no meter latencia al camino
  crítico del usuario.
- Kill-switch: **solo jailbreak + sondeo interno**, igual que ZeroClaw.
- Contenido que sale de la máquina: **solo un extracto corto y redactado por
  incidente real**, nunca la conversación completa ni en bulk — excepción
  acotada y deliberada a la regla "estructura sí, contenido no", justificada
  por seguridad y no por medir productividad.
- Límite aceptado: **un empleado puede evadir esto editando su propio hook**
  — no se intenta resolver en este spec; queda anotado como candidato futuro
  (chequeo de integridad estructural desde forja).
- Desbloqueo: **token corto de un solo uso**, generado por Technology desde
  el cerebro, consumido por el empleado con un comando local — nadie externo
  toca el fork del empleado directamente.

<!-- bash/whatsapp_evo_api/CLAUDE.md — manual del dominio. Este directorio NO
     viaja al copiloto (excluido en derivar_canal.sh); su documentación vive
     aquí y no en el CLAUDE.md raíz, byte-idéntico en todos los forks. -->

## WhatsApp domain — Evolution API ([bash/whatsapp_evo_api/](bash/whatsapp_evo_api/))

WhatsApp messaging to one recipient (the closer) via a local Evolution API
instance. Config in `.env`: `EVOLUTION_API_URL`/`EVOLUTION_API_KEY`/
`EVOLUTION_API_INSTANCE` + default recipient `PHONE_NUMBER`; `PROJECT_ID`
scopes the DB read. **Unlike the rest of bash/, senders WRITE to the outside
world** (a real WhatsApp message goes out) — both support `--dry-run`.
**Caveat:** `ikigaigm.whatsapp_messages` is NOT being populated (no Evolution
webhook), so `messages.sh` shows a stale trail; `last_inbound.sh` reads live
from the API and is the source of truth for replies.

| Script | Use it to… |
|--------|-----------|
| `send_message.sh --message TEXT [--to NUMBER] [--dry-run]` **[SEND]** | Send one text message. Recipient defaults to `$PHONE_NUMBER`. Prints the Evolution message id + status. |
| `send_message_template.sh --template NAME --data TEXT [--dry-run]` **[SEND]** | Render `templates/<NAME>/render.py` (repo root) with `--data` (raw output of a data-source script) and send the result via `send_message.sh`. No templates exist yet — create the dir first. |
| `last_inbound.sh [--jid JID] [--since TS]` | Latest message authored by the HUMAN in the conversation, live from `/chat/findMessages`. Excludes only API sends (`fromMe` + `source=web`), so self-tests (phone = instance's own number) still work. `--since` (epoch or ISO) guards against stale replies. Emits one JSON object or `null`. |
| `messages.sh [--phone N] [--limit N] [--date-after D] [--date-before D] [--inbound\|--outbound]` | Conversation trail from `ikigaigm.whatsapp_messages` (filtered by `PROJECT_ID` + jid). Stale until the webhook populates the table. |
| `group_sync.sh <grupo> [--db N] [--completo] [--paginas N] [--dry-run] [--json]` **[WRITE local]** | Baja el historial de UN grupo a una sqlite local (`mensajes` + bitácora `corridas`). Incremental por defecto: para cuando una página entera ya está en la base (ponerse al día = 2-3 páginas, no 324). Idempotente por id de Evolution; **nunca borra**. Migra sola el esquema y rellena `texto_norm`/`autor_norm`. Nunca toca Postgres. |
| `group_history.sh <db> [--buscar T] [--autor N] [--desde D] [--hasta D] [--dia D] [--tipo T] [--solo-texto] [--hora-min N] [--hora-max N] [--contexto N] [--limit N] [--json]` | LEE lo sincronizado (`sqlite_ro`). `--buscar`/`--autor` normalizan la aguja y consultan las columnas sin acentos. `--contexto N` trae N vecinos por coincidencia y marca el hit con `>` — reconstruye el hilo alrededor de un momento. Avisa en stderr la edad del último sync. |

### Historial de grupos — lectura y escritura son scripts distintos

`group_sync.sh` escribe y `group_history.sh` solo lee: consultar no debe poder
alterar la copia. El par nació del cruce que recuperó las 6 ventas perdidas de
Mateo ([docs/only-closers-informe.md](../../docs/only-closers-informe.md) §8) —
el grupo ONLY CLOSERS resultó ser fuente de verdad operativa (fichas de lead,
cierres anunciados, fallas de la app) y bajarlo a mano era un artefacto de
sesión.

**Tres trampas del dominio que los scripts encodan**, todas errores reales:

1. **Los acentos dan falsos negativos silenciosos.** «Vásquez» viaja con acento
   COMBINANTE: `texto LIKE '%Marulanda Vás%'` devuelve **0** y
   `texto_norm LIKE '%marulanda vas%'` devuelve **3**. Ese fallo nos hizo creer
   por un momento que una oportunidad había desaparecido del espejo. Por eso
   existen `texto_norm`/`autor_norm` (minúsculas, sin marcas diacríticas) y
   `--buscar` normaliza también la aguja. **Nunca buscar sobre `texto`.**
2. **Un cero es ambiguo sin la frescura.** «No existe» y «la copia está vieja»
   se ven igual. De ahí la tabla `corridas` y el aviso de edad en cada consulta
   (grita pasadas 24h). Es la duda que tuvimos con Renan Romero.
3. **`numero` es el LID de WhatsApp, NO el teléfono.** Buscar un número ahí no
   encuentra nada; los teléfonos viven en el TEXTO de las fichas de lead, así
   que la vía correcta es `--buscar`. (El mapeo LID→teléfono sí existe, pero en
   `/group/participants`, no en los mensajes.)

⚠️ **Leer historial NO le pega a los servidores de Meta.** `/chat/findMessages`
consulta el store **local** de Evolution (Baileys guarda lo que entra por el
websocket). Verificado 2026-08-13: grupos con años de historia pero sin tráfico
desde el emparejamiento devuelven 0 mensajes, y el mismo grupo aparece con otro
jid en `/group/fetchAllGroups` (metadata live) que en `/chat/findChats` (store).
Paginar acá no cuenta como actividad ante Meta. **Lo que sí arriesga la cuenta
son los ENVÍOS masivos** — la línea de los closers se cayó 3 veces en agosto de
2026 por eso. Los masivos van por WABA, no por acá.

**Techo del histórico:** lo que la instancia haya sincronizado al emparejarse.
Para `ParalleloFinal` (creada 2026-05-01, `syncFullHistory:false`) el grupo ONLY
CLOSERS llega hasta **2026-02-02** — el emparejamiento arrastró meses previos,
así que `syncFullHistory:false` **no** implica «solo desde la creación».
Comprobar con `min(fecha)` antes de concluir que algo «nunca se mencionó».

**Resolución del grupo:** por JID o por fragmento de nombre, y el fragmento se
resuelve contra `/chat/findChats` (el store), **no** contra
`/group/fetchAllGroups`: el mismo grupo puede aparecer con otro jid en el
listado live, y ese jid no tiene mensajes.

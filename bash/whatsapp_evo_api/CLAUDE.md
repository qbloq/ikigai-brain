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

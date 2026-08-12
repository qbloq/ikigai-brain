# ZeroClaw — referencia del cerebro

**Qué es**: runtime de agentes en Rust — un binario, una config TOML, multi-agente,
multi-canal (30+, WhatsApp incluido), multi-proveedor LLM (Anthropic de primera
clase), con gateway HTTP/WS + dashboard, memoria persistente, sandboxing y motor
de SOPs. Licencia MIT/Apache-2.0, repo muy activo.

**Rol en el sistema Cerebro**: es la **plataforma de Agentes** — la interfaz al
cerebro desde las terminales de empleados, stakeholders y clientes. Cada Agente
es una entrada `[agents.<alias>]` con su workspace, su memoria, su risk profile y
sus canales; el cerebro (este repo) queda como la fuente de conocimiento y
gobierno detrás de ellos. **Misión 1: primer Agente corriendo por WhatsApp** (plan
al final).

- Clon local: `/projects/zeroclaw` · versión `v0.8.4` (2026-08-13)
- Docs upstream: `docs/book/src/` (mdBook; ojo — las tablas de campos se generan
  del schema en build; la fuente completa es `crates/zeroclaw-config/src/schema.rs`
  o `zeroclaw config schema`)
- ⚠️ MSRV **1.96.0**; esta máquina tiene Rust 1.93.1 → compilar desde fuente pide
  `rustup update` primero. El binario precompilado no lo necesita.

---

## Arquitectura en una página

```
canal (adapter: decode + dedup + pair-check)        crates/zeroclaw-channels/
  → agent loop (motor de turno ÚNICO p/ todos los transportes)
      run_tool_call_loop()                          crates/zeroclaw-runtime/src/agent/turn/
      1. memory inject (política por TurnOrigin)
      2. provider call (stream; draft updates si el canal lo soporta)
      3. security gate por tool call (risk profile)
      4. ejecución de tools → receipt HMAC → append a history → loop
  → respuesta por el mismo adapter
```

- **Turn** = mensaje de usuario + respuesta + todas sus tool calls/results. El
  trimming retiene turnos atómicos y deja un breadcrumb visible (`HistoryTrimmed`).
- **Session history ≠ memoria**: history es continuidad (SQLite WAL,
  `data/sessions/sessions.db`); memoria durable es solo lo escrito explícito vía
  `memory_store` o autosave — prompt/tools/logs NO son memoria.
- Crates clave: `zeroclaw-runtime` (loop, seguridad, SOP, cron), `zeroclaw-api`
  (traits: `ModelProvider`/`Channel`/`Tool`/`Memory`), `zeroclaw-config` (schema),
  `zeroclaw-providers`, `zeroclaw-channels`, `zeroclaw-gateway`, `zeroclaw-memory`.
- RFC #5574 está partiendo el runtime en microkernel — no acoplar nada nuestro a
  internals del runtime.

## Configuración (V3)

Un TOML en `~/.zeroclaw/config.toml`. Cuatro secciones mínimas, todas con forma
`<type>.<alias>` (alias: minúsculas/dígitos/`_` simple, sin `__` ni guiones):

```toml
schema_version = 3

[providers.models.anthropic.default]
model = "claude-sonnet-4-5"
# api_key vía `zeroclaw config set` (se guarda cifrado) — nunca en el TOML plano

[agents.default]
enabled = true
model_provider = "anthropic.default"
risk_profile = "default"
channels = ["whatsapp.personal"]     # ← EL AGENTE declara sus canales, no al revés

[risk_profiles.default]
level = "supervised"                  # readonly | supervised | full

[channels.whatsapp.personal]
enabled = true
# ... (ver sección WhatsApp)
```

- **El agente es un JOIN**: referencias (`model_provider`, `risk_profile`,
  `runtime_profile`, `channels`, `mcp_bundles`, `cron_jobs`, `delegates`…) +
  componentes en disco (`workspace`, `memory`, `identity`). Multi-agente es de
  primera clase: "a single-agent install is just a map of size one".
- **Enrutamiento canal→agente**: `Config::agent_for_channel` devuelve el primer
  agente habilitado que lista ese `<type>.<alias>`. Cada canal se liga a UN
  agente. Si algún agente declara `channels`, un canal no listado **no arranca**.
- **Identidad del agente**: archivos en su workspace inyectados al system prompt
  en orden `AGENTS.md, SOUL.md, TOOLS.md, IDENTITY.md, USER.md` (+ `MEMORY.md`
  en sesión principal). Aquí es donde un Agente "hereda" el rol/SOP del cerebro.
- **Secretos**: campos `#[secret]` se guardan cifrados (clave en
  `~/.zeroclaw/.secret_key` — perderla = secretos irrecuperables). Env override
  schema-mirror: `ZEROCLAW_<path con __>` (p.ej.
  `ZEROCLAW_providers__models__anthropic__default__api_key`); solo in-memory,
  nunca se persiste. Los legacy `ANTHROPIC_API_KEY` etc. **ya no se leen**.
- **Runtime profiles** (`[runtime_profiles.<alias>]`): tuning operacional —
  `max_tool_iterations`, `max_context_tokens`, `max_cost_per_day_cents`,
  `max_actions_per_hour`, timeouts, `memory_recall_limit`… Quickstart instala
  `unbounded` por defecto — **ajustarlo** para agentes de cara a clientes.
- `[cost]`: límites diario/mensual USD con warning por porcentaje.

## Providers

`[providers.models.<type>.<alias>]` — slots canónicos: `anthropic`, `openai`
(incl. Codex subscription), `ollama`, `bedrock`, `gemini`, `azure`, más ~15
OpenAI-compatibles y multi-región. Campos: `model`, `api_key`, `uri`,
`temperature`, `max_tokens`, `fallback_models`, `fallback`, `wire_api`…

- **Anthropic**: acepta API key de Console **o token de `claude setup-token`
  (Claude Max)** — ambos van en `api_key` del slot `anthropic`; Quickstart los
  ofrece como `api_key` / `setup_token`.
- **Fallback**: `fallback_models` (mismos endpoint/key) vs `fallback` (otros
  aliases con SUS credenciales; depth máx 3, ciclos podados, misconfig = warning
  no fatal). Retry same-provider en `[reliability]` (429 rota keys, 503/timeout
  reintenta; 400/auth no).
- Switch en runtime sin persistir: `/models <type>.<alias>`, `/model <id>`.

## Tools y seguridad (6 capas)

Built-ins: `shell`, `file_read/write/edit`, `glob_search`, `content_search`,
`http_request`, `web_search_tool`, `web_fetch`, `browser`, `memory_recall/store`,
`ask_user`, `escalate_to_human`, `cron_*`, `spawn_subagent`, `delegate`.

**MCP**: zeroclaw es cliente MCP (stdio/http/sse). Patrón de 3 bloques:
`[[mcp.servers]]` define → `[mcp_bundles.x] servers=[...]` agrupa →
`[agents.a] mcp_bundles=["x"]` concede. **Definir NO es conceder** (sin bundle,
cero servidores); deny gana; fail-closed. Tools con namespace `server__tool`.
⚠️ Si `allowed_tools` no está vacía, cualquier tool con `__` se auto-admite —
bloquear las peligrosas explícitamente en `excluded_tools`.

Las capas, de fuera adentro:

1. **Pairing/allowlist de canal** (peer groups) — se aplica en el adapter, antes
   del runtime.
2. **Autonomía** (`risk_profiles.level`): `readonly` / `supervised` (default:
   medium pide aprobación, high bloquea) / `full`. Aprobaciones llegan **por el
   canal de origen**: WhatsApp incrusta un token corto y espera
   `<token> approve|deny|always` (timeout `approval_timeout_secs`, default canal
   WhatsApp 300s → denegar). Ruteo cross-canal: `[risk_profiles.x.approval_route]`.
3. **Workspace boundary**: `workspace_only`, `forbidden_paths`; workspace por
   agente en `~/.zeroclaw/agents/<alias>/workspace/`.
4. **Política de shell**: `allowed_commands` (estricta si no vacía),
   `forbidden_commands`, validación de patrones.
5. **Sandbox OS**: Linux auto = Landlock → Bubblewrap → Firejail → Docker → none
   (Landlock no controla red).
6. **Tool receipts**: HMAC-SHA256 in-band en el historial (`zc-receipt-…`), solo
   ejecuciones exitosas; clave efímera en memoria.

Extras: OTP por acción, `zeroclaw estop`, leak detector, prompt-injection guard.
YOLO = un risk profile `level="full"` sin sandbox, conviviendo con perfiles duros.

## Memoria

`[memory].backend` → `[storage.<backend>.<alias>]`: `sqlite` (default) /
`postgres` / `qdrant` / `markdown` / `lucid` / `none`. Scoping por agente
(UUID por alias en stores compartidos; markdown = archivos por agente). Backend
**bloqueado** una vez el agente escribió; cross-agent solo mismo backend.
Búsqueda `bm25`/`embedding`/`hybrid`; hygiene con archive/purge por días.
Nota: backend `postgres` existe → integrable a futuro con nuestro Postgres.

## SOP engine

SOPs deterministas ejecutados por `SopEngine`: `<workspace>/sops/<name>/SOP.toml`
(identidad + triggers + `admission_policy`) + `SOP.md` (`## Steps` con `tools:`,
`requires_confirmation:`, `policy:`, `next:`, `on_failure:`, contratos
`input:`/`output:`). Triggers vivos: mqtt, filesystem, amqp, cron, channel,
manual. Approval broker en config central (`[sop.approval.groups/policies]`) con
quórum y rutas de solicitud/escalación. Runs durables en `data/sop/runs.db`.

**Resonancia con nuestra ontología**: sus SOPs son *procedimientos ejecutables*
por agente; nuestros SOPs (S1–S12 → arquetipos → tareas) son la ontología del
trabajo humano. El puente natural: un arquetipo nuestro con contrato de IO puede
compilarse a un SOP zeroclaw cuando la actividad se automatice.

## Gateway + dashboard

Un solo proceso: `zeroclaw daemon` = gateway :42617 (REST/WS/SSE/webhooks) +
canales + cron + heartbeat. Auth por **pairing code → bearer token**
(`zeroclaw gateway get-paircode`; `--rotate` revoca todo). Secretos write-only
por HTTP (lecturas devuelven `{populated}`). Dashboard web (config per-field,
personalidad, sesiones, cron, logs SSE) servido del mismo puerto; sin `web/dist`
→ API-only. Webhooks de canal (`/whatsapp/{alias}`, `/webhook/gmail`…) **no**
pasan por pairing — su auth es la firma HMAC del proveedor.

⚠️ `allow_public_bind` NO es un gate — solo silencia el warning; la frontera
real es el bind/mapping de puertos + `require_pairing` (default `true`, pero la
**imagen Docker lo hornea en `false`** — publicar siempre `127.0.0.1:42617:42617`).

## Operación

```sh
# instalar (prebuilt, sin prompts)
curl -fsSL https://raw.githubusercontent.com/zeroclaw-labs/zeroclaw/master/install.sh | sh -s -- --skip-quickstart
# → binario en ~/.cargo/bin/zeroclaw

zeroclaw quickstart            # interactivo (TTY): provider → risk → memory → channels → agent
zeroclaw agent -a <alias> -m "hola"   # -a es OBLIGATORIO, no hay agente default
zeroclaw daemon                # foreground: gateway + canales + scheduler

# always-on (systemd USER-scoped)
zeroclaw service install && zeroclaw service start
sudo loginctl enable-linger $USER     # imprescindible en headless
journalctl --user -u zeroclaw -f

# salud
curl -s localhost:42617/health | jq   # público, por componente
zeroclaw doctor && zeroclaw status
zeroclaw update                       # self-update con backup+rollback
```

- Estado en `~/.zeroclaw/`: `config.toml`, `.secret_key`, `data/` (sessions,
  cron, sop, memory, state/costs.jsonl), `agents/<alias>/workspace/`.
  **Backup**: config + `.secret_key` + `data/` + workspaces.
- **Un solo daemon por install root** (SQLite single-writer).
- Docker: `ghcr.io/zeroclaw-labs/zeroclaw:latest` (distroless, sin shell) /
  `:debian`; volumen único `/zeroclaw-data`; en servidor el patrón recomendado
  por los docs es **Podman quadlet**.
- Los binarios precompilados traen el set "lean standard" de canales — **incluye
  WhatsApp Web, NO incluye WhatsApp Cloud API ni Slack** (esos piden
  `./install.sh --source --preset full`, y un `zeroclaw update` prebuilt
  posterior los quita).

## WhatsApp — los dos backends

Misma familia `[channels.whatsapp.<alias>]`; el selector decide el modo
(`phone_number_id` → Cloud; `session_path`/`pair_phone` → Web; ambos → gana
Cloud + warning). Doc: `docs/book/src/channels/whatsapp.md`. Código:
`crates/zeroclaw-channels/src/whatsapp.rs` (Cloud) / `whatsapp_web.rs` (Web,
puerto Rust de whatsmeow — sin Meta, sin webhook).

| | **Cloud API (Meta)** | **WhatsApp Web** |
|---|---|---|
| Cuenta | WhatsApp Business + app Meta | cuenta normal, vinculada por QR/pair-code |
| Binario | ⚠️ pide build `--preset full` | ✅ viene en el prebuilt |
| Red | webhook → URL pública (túnel `[tunnel]`) | WS saliente, sin IP pública |
| Media saliente | solo texto, location, botones/listas | `[IMAGE:]`/`[DOCUMENT:]`/`[VIDEO:]`/`[VOICE:]`… (paths dentro del workspace; URLs prohibidas) |
| Media entrante | ⚠️ solo texto (imagen/audio/doc se descartan) | imagen/video/audio/sticker; notas de voz → transcripción |
| Typing | no | sí |
| Riesgo | oficial, estable | no-oficial (riesgo de ban teórico como todo cliente Web no oficial) |

**Control de acceso** — el modelo canónico es `[peer_groups.<nombre>]`
(convención `whatsapp_<alias>`): `external_peers = ["+57300…"]` en E.164
(`["*"]` = cualquiera, `[]` = nadie), `ignore` como blocklist, `agents` para
diálogo inter-agente. No existe `allowed_numbers` en el canal (migra solo).

⚠️ **Gotchas que muerden**:

1. **Web + `mode="business"` (default) NO evalúa la allowlist de senders** — el
   gating por número solo corre en `mode="personal"` con
   `dm_policy="allowlist"`. Para nuestro caso: **siempre `mode="personal"`**.
2. `allowed_groups = []` permite TODOS los grupos (lista vacía ≠ nadie, al revés
   que `external_peers`).
3. **No hay chunking para WhatsApp** (Telegram/Discord sí lo tienen): respuesta
   >4096 chars en Cloud = error de Meta. Mitigar con brevedad en el prompt del
   agente y `max_tokens` acotado.
4. **Cloud API + multi-agente**: el webhook despacha al agente *default* del
   gateway (`"default"` o primero alfabético), NO necesariamente al dueño del
   binding. Con un agente no se nota; con varios, el agente de WhatsApp Cloud
   debe llamarse `default`. En Web el orquestador sí enruta al dueño.
5. Cloud sin `app_secret` → el webhook responde 401 a todo (fail-closed).
6. Web: `session_path` en disco persistente — borrarlo = re-vincular QR. Al
   conectar, auto-persiste el número vinculado en el peer group.

### Config de referencia — Web personal (el camino de la Misión 1)

```toml
[channels.whatsapp.personal]
enabled = true
session_path = "~/.zeroclaw/state/whatsapp-web/personal.db"
mode = "personal"
dm_policy = "allowlist"
group_policy = "ignore"          # sin grupos al inicio
self_chat_mode = true

[peer_groups.whatsapp_personal]
channel = "whatsapp.personal"
external_peers = ["+57XXXXXXXXXX"]   # los números autorizados, E.164

[agents.default]
enabled = true
channels = ["whatsapp.personal"]
```

Arranque: `zeroclaw daemon` en foreground → QR en el terminal → escanear desde
WhatsApp > Dispositivos vinculados (con `pair_phone` imprime un pair-code en vez
de QR). `zeroclaw channel doctor` para verificar.

### Config de referencia — Cloud API (cuando se gradúe)

En Meta: app Business + producto WhatsApp → `phone_number_id`, access token
permanente (System User), app secret, verify token propio. En zeroclaw:
`zeroclaw config set channels.whatsapp.default.{enabled,phone_number_id,access_token,verify_token,app_secret}`
+ `[tunnel] tunnel_provider = "cloudflare"` (o reverse proxy propio). Callback
en Meta: `https://<url>/whatsapp/default`, suscribir el campo `messages`.
Requiere binario con `channel-whatsapp-cloud`.

---

## Misión 1 — primer Agente por WhatsApp ✅ COMPLETA (2026-08-12)

**El primer Agente del Cerebro respondió por WhatsApp de ida y vuelta** el
mismo día (webhook→respuesta ~2s). Arquitectura final en producción:

```
WhatsApp (+57 312 8932486 · phone_number_id 568780566329582 · app Parallelo)
  → Meta → https://a.parallelo.ai (nginx) → agenticlaw-webhook-router :8080
  → WireGuard → 10.0.0.2:42617 (gateway zeroclaw, systemd user + linger)
  → verificación HMAC → agente `default` (interno Ikigai, supervised)
  → Claude vía suscripción (setup-token, cifrado) → respuesta por Graph API
```

Higiene pendiente: re-cifrar `access_token`/`verify_token` inline (config set
con TTY), guard de body no-JSON en el router, rotar la key OpenRouter del
config viejo de Coco. Caveat: sin pricing para el modelo, el cost tracking
registra \$0 → `max_cost_per_day_cents` inerte; el freno operativo real es
`max_actions_per_hour`. Lo que sigue: identidad definitiva, herramientas/MCP
hacia los datos del cerebro, ampliar la allowlist.

Las dos vías originales del plan (pueden convivir, ligadas a agentes
distintos): **Vía A (WABA/Cloud API), la ejecutada**; Vía B (Web) queda como
laboratorio/fallback.

### Vía A — WABA (Cloud API de Meta)

**Fase 0 — verificaciones previas** (resuelta casi entera el 2026-08-12):

- ✅ **Credenciales localizadas** en el config del despliegue previo «Coco»
  (`/agentico/data/ids/f90575da-f8c2-4ba9-bbd9-917d095a7b3c/config.toml`,
  zeroclaw schema v2, corrió hasta 2026-06-23; flota "Agentico" de 9 agentes en
  `/agentico/data/ids/`): `phone_number_id` **568780566329582** →
  **+57 312 8932486, "Feria Local - Ventas"** (calidad GREEN), access token
  permanente **verificado vivo** contra Graph API, `verify_token`, allowlist
  `[+573226531629]`. App de Meta: **"Parallelo"** (2060088928108142).
- ❌ **Falta el `app_secret`** (developers.facebook.com → app Parallelo →
  App Settings → Basic) — obligatorio en v0.8.4: sin él el webhook responde
  401 a todo (el schema v2 de Coco no lo pedía).
- Higiene: el config viejo guarda los secretos en texto plano (incl. una key de
  OpenRouter); al migrar, cablearlos vía `zeroclaw config set` (cifrado) y
  considerar rotar lo expuesto.
- ⚠️ **Ventana de 24h de WABA**: el canal Cloud de zeroclaw envía solo mensajes
  freeform (no se encontró soporte de plantillas en el código) → el Agente
  siempre puede *responder* dentro de las 24h posteriores al último mensaje del
  usuario, pero **no puede iniciar** conversación con contactos fríos. Para una
  interfaz inbound-first está bien; outbound frío pediría plantillas (gap).

**Fase 1 — build con Cloud API** (el prebuilt no lo trae):

```sh
rustup update stable            # MSRV 1.96 > 1.93 local
cd /projects/zeroclaw
cargo install --path . --locked --features channel-whatsapp-cloud,whatsapp-web
zeroclaw channel list           # debe listar WhatsApp (cloud) y WhatsApp Web
```

⚠️ Tras esto, **no correr `zeroclaw update`** (el prebuilt revertiría las
features); actualizar recompilando desde el clon.

**Fase 2 — config**: el agente WABA debe llamarse **`default`** (el webhook
Cloud despacha al agente default del gateway, no al dueño del binding):

```toml
[agents.default]
enabled = true
model_provider = "anthropic.default"
risk_profile = "default"
runtime_profile = "acotado"     # max_tool_iterations, max_cost_per_day_cents…
channels = ["whatsapp.default"]

[peer_groups.whatsapp_default]
channel = "whatsapp.default"
external_peers = ["+57XXXXXXXXXX"]   # allowlist inicial, E.164
```

```sh
zeroclaw config set channels.whatsapp.default.enabled true
zeroclaw config set channels.whatsapp.default.phone_number_id <ID>
zeroclaw config set channels.whatsapp.default.access_token    # prompt enmascarado
zeroclaw config set channels.whatsapp.default.verify_token
zeroclaw config set channels.whatsapp.default.app_secret
```

- Identidad del Agente en `~/.zeroclaw/agents/default/workspace/`
  (`IDENTITY.md`/`AGENTS.md`): asistente del equipo Ikigai, tono, límites, y
  **brevedad obligatoria** (sin chunking: >4096 chars = error de Meta).
- Recordar: Cloud **descarta media entrante** (solo texto/botones/listas) — si
  alguien manda un audio o foto, el Agente no lo ve.

**Fase 3 — ingress público**: ya existe, es el **router de agenticlaw**
(descubierto 2026-08-12):

```
Meta → https://a.parallelo.ai (nginx + Certbot, servidor api)
     → agenticlaw-webhook-router (Express, PM2, :8080, /apps/agenticlaw/router/)
     → mappings.json: por phone_number_id Y por remitente
     → WireGuard → 10.0.0.2 (esta máquina)
```

- El número 568780566329582 está **compartido**: los remitentes mapeados van a
  su destino propio y el `default` va a `10.0.0.2:3000/webhook` (hoy caído,
  igual que el zeroclaw de Coco en :43008 — el router reenvía al vacío).
- ⚠️ **El router NO reenvía la firma HMAC**: hace `axios.post` del body
  re-serializado sin `X-Hub-Signature-256`. Con el zeroclaw viejo colaba (no
  verificaba); v0.8.4 respondería 401 a todo. **Parche necesario**: capturar el
  raw body (`express.json({verify})`), reenviar los bytes crudos + el header de
  firma (la firma es sobre el body crudo — re-serializar la invalida), y un
  handler GET para el passthrough del `hub.challenge` si Meta re-verifica.
- Cablear el Agente = agregar en `mappings.json` los números internos →
  `http://10.0.0.2:42617/whatsapp/default` + `pm2 restart
  agenticlaw-webhook-router`. El callback en Meta no cambia (sigue siendo
  `a.parallelo.ai`), así que posiblemente la Fase 4 sea solo verificar que la
  suscripción siga activa.

La alternativa de túnel administrado de zeroclaw (`[tunnel]` cloudflare/ngrok/
tailscale) queda de plan B si algún día se quiere sacar el webhook del router.

**Fase 4 — cablear Meta**: `zeroclaw daemon` corriendo → en la app de Meta,
WhatsApp → Configuration → Webhook: Callback URL =
`https://<url-pública>/whatsapp/default`, Verify Token = el nuestro → Meta hace
el GET de verificación (debe dar 200) → suscribir el campo **`messages`**.

**Fase 5 — prueba y hardening**: mensaje desde un número de la allowlist
(logs: `inbound webhook message`; si sale `ignoring message from unauthorized
number`, falta en el peer group; 401 en Meta = app_secret mal). Después:
`zeroclaw service install` + `sudo loginctl enable-linger` + monitoreo
(`/health`, `zeroclaw doctor`) + probar el flujo de aprobación de tools
(`<token> approve|deny`).

### Vía B — Web personal (laboratorio / fallback)

Binario prebuilt ya instalado la trae. Config de la sección WhatsApp
(`mode="personal"` + allowlist), `zeroclaw daemon` → QR → probar. Decisiones:
qué cuenta se vincula (el QR se escanea desde ese teléfono) y allowlist.

**Política de credenciales Claude** (Santiago, 2026-08-12): la suscripción
(`claude setup-token`) es **exclusivamente para uso interno — solo algunos
empleados**; todo agente de producción o de cara a clientes usa **API key de
Console** (workspace propio para aislar gasto) + techos de costo (`[cost]`,
`max_cost_per_day_cents`). No hay credencial Anthropic en el `.env` del cerebro
— pieza pendiente.

## Puntos de fricción (resumen operativo)

1. `zeroclaw agent` exige `-a <alias>` — no hay default.
2. Sin `loginctl enable-linger`, el servicio muere al cerrar SSH.
3. Imagen Docker: `require_pairing=false` horneado — nunca publicar el puerto
   sin `127.0.0.1:`.
4. `allow_public_bind` no protege nada.
5. Prebuilt ≠ todos los canales; `zeroclaw update` prebuilt revierte un build full.
6. Un daemon por install root.
7. `:latest` es distroless sin shell (usar `:debian` para exec).
8. Perder `.secret_key` = secretos irrecuperables.
9. MSRV 1.96 > Rust local 1.93 — `rustup update` antes de compilar.
10. WhatsApp: business mode sin allowlist de senders; sin chunking; Cloud
    descarta media entrante; webhook Cloud → agente `default`.

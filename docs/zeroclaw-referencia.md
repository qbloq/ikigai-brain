# ZeroClaw — referencia del cerebro

**Qué es**: runtime de agentes en Rust (un binario, config TOML, multi-agente,
30+ canales, multi-LLM, gateway HTTP, memoria, sandboxing). Es la **plataforma
de Agentes** del sistema Cerebro: la interfaz por WhatsApp/terminales para
empleados, stakeholders y clientes; el cerebro (este repo) es la fuente de
conocimiento y gobierno detrás.

- Clon: `/projects/zeroclaw` (upstream muy activo) · corriendo **v0.8.4
  compilado de fuente** con `channel-whatsapp-cloud,whatsapp-web`
  (⚠️ jamás `zeroclaw update`: el prebuilt no trae Cloud API — actualizar
  recompilando del clon; MSRV 1.96+)
- Docs upstream: `docs/book/src/` · schema completo:
  `crates/zeroclaw-config/src/schema.rs` o `zeroclaw config schema`
- Specs nuestros: `docs/superpowers/specs/2026-08-12-*.md` (identidad Iki,
  Mesa Fase B, despacho Fase C)

## El sistema en producción (2026-08-12)

```
WhatsApp +57 312 8932486 («Feria Local - Ventas» · phone_number_id 568780566329582
                          · WABA 690499003502578 · app Meta «Parallelo» 2060088928108142)
  → Meta → https://a.parallelo.ai (nginx+certbot, servidor api)
  → agenticlaw-webhook-router (PM2 :8080, /apps/agenticlaw/router/ — rutea por
    phone_number_id Y remitente; PARCHADO: reenvía bytes crudos + firma
    X-Hub-Signature-256 y passthrough del hub.challenge; backups *.bak-20260812)
  → WireGuard → 10.0.0.2:42617 (gateway zeroclaw, ESTA máquina)
  → verificación HMAC (app_secret) → agente `default` = IKI
  → Claude (suscripción, setup-token cifrado) → respuesta vía Graph API (~2-6s)
```

- **Servicio**: systemd user (`zeroclaw service …`, linger habilitado).
  Salud: `curl -s 10.0.0.2:42617/health` · `zeroclaw doctor` ·
  `journalctl --user -u zeroclaw -f` · traza
  `~/.zeroclaw/data/state/runtime-trace.jsonl`.
- **Config**: `~/.zeroclaw/config.toml` (V3). Secretos cifrados vía
  `zeroclaw config set <path>` (⚠️ exige TTY). `.secret_key` = irrecuperable
  si se pierde. El número WABA es COMPARTIDO: el router manda otros
  remitentes al destino `default` (`10.0.0.2:3000`, hoy muerto).
- **Iki** (agente `default`): identidad en
  `~/.zeroclaw/agents/default/workspace/` (SOUL/IDENTITY/AGENTS/USER.md —
  zeroclaw los inyecta al system prompt). Memoria en el store compartido
  `~/.zeroclaw/data/memory/brain.db` (scoped por agent_id). Risk profile
  `supervised` + `workspace_only`; `memory_store/recall` auto-aprobados;
  runtime acotado (12 iteraciones, 60 acciones/hora). Allowlist:
  `[peer_groups.whatsapp_default] external_peers` (hoy: Santiago).

## Cómo vive una conversación WhatsApp

- **Sesión por remitente**: `session_id = whatsapp_<numero>` (estable). La
  continuidad durable es la MEMORIA, no un historial en disco: cada mensaje
  del usuario se auto-guarda (`category=conversation`, key
  `whatsapp_<numero>_<uuid>`) y el turno siguiente inyecta `[Memory context]`.
  `sessions.db` está vacía para canales — el hilo fino es in-process (un
  restart lo pierde; la memoria lo recupera).
- **El prompt es channel-aware**: el orquestador inyecta una guía por canal —
  para WhatsApp: sé conciso, markers de media/location, paths solo dentro del
  workspace. Lo que el canal NO advierte lo cubre el `AGENTS.md` de Iki:
  **no hay chunking** (>4096 chars = error de Meta) y **el Cloud API descarta
  media entrante** (solo texto/botones/listas llegan al modelo).
- **Aprobaciones de tools** por el mismo chat: token corto +
  `<token> approve|deny` (timeout 300s → deny).
- **Ventana de 24h**: Iki responde libre dentro de la ventana; INICIAR
  conversación (despachos a terceros) exige plantilla Meta aprobada.

## El ciclo del recado (Iki → Mesa → despacho)

```
Iki captura (memoria: «RECADO:» DE/PARA/QUÉ/URGENCIA/CONTEXTO/PROPUESTA)
 → bash/agentes/sync_despachos.sh  [WRITE local]  cosecha → sqlite mesa_despacho
 → Mesa de Despacho (viz /u/mesa-despacho)        cola + estados + entradas
 → humano Aprueba/Rechaza (botón → despacho_mark.sh; solo filas pendientes)
 → bash/agentes/despachar.sh [WRITE→WhatsApp]     DESDE la conversación:
   resuelve `directorio` (nombre→E.164) → plantilla → wamid → estado ejecutado
```

Guardrails: decisiones congeladas (ni sync ni mark reescriben), nunca se
escribe en las DBs del daemon, solo `aprobado` se ejecuta, `--dry-run` en
sync y despacho. Lectura: `despachos.sh` / `recados.sh` / `entradas.sh`
(fuentes viz `iki_despachos`/`iki_recados`/`iki_entradas`).

## Decisiones (con su porqué)

1. **ZeroClaw es la plataforma de Agentes** (2026-08-12) — runtime probado,
   canal WhatsApp nativo, seguridad por capas, y su motor de SOPs resuena con
   nuestra ontología (un arquetipo con contrato IO podría compilarse a SOP).
2. **Suscripción Claude = SOLO uso interno** (empleados selectos). Iki es
   interno → corre con `claude setup-token`. Todo agente customer-facing
   usará API key de Console con techos de costo. (Política en memoria:
   comparte límites 5h/semana con el uso propio; sin facturación por consumo.)
3. **WABA Cloud API sobre el ingress EXISTENTE** — el router de agenticlaw ya
   enrutaba ese número por remitente; se parchó (firma HMAC + verify
   passthrough) en vez de montar túnel nuevo. El callback de Meta no cambió.
4. **El agente WABA se llama `default`** — el webhook Cloud despacha al agente
   default del gateway, no al dueño del binding (caveat verificado en código).
5. **Iki es recepcionista/dispatcher** (no generalista, no «la voz del
   Cerebro»): recibe→estructura→guarda→confirma, cálido y breve. **Habla como
   despachador pleno desde el día 1**; la promesa la hace verdadera el
   sistema (cosecha + Mesa + despacho). Allowlist corta mientras tanto.
6. **Se aprueba SOLO el despacho, nunca la conversación** — Iki responde en
   tiempo real; la Mesa gobierna qué sale de la conversación hacia el mundo.
   Ejecutar NO tiene botón: corre por conversación con el cerebro (patrón
   cruce/merge).
7. **Salida a terceros por plantilla Meta**: `recado_cerebro` (UTILITY) y
   `recado_cerebro_mkt` (MARKETING, gemela — el WABA solo tiene historial
   MARKETING) · ids 1831771134860100 / 2195985700964604 · el token System
   User «Parallelo System User» SÍ administra plantillas vía API.
8. **El directorio sale de la DB con users.phone_number como fuente primaria**
   y `team_members.whatsapp` de fallback (números duplicados en users =
   sospechosos → fallback); espejo re-ejecutable: `sync_directorio.sh`. 40
   entradas
   E.164-normalizados + alias del mapa de apodos. `santi` EXCLUIDO adrede
   (ambiguo: Santiago Ruiz vs Santiago Gaviria) → cae a revisión humana.
   El resolvedor premia la coincidencia más larga.
9. **viz es visor**: los writes de la Mesa van por scripts bash whitelisted
   (`despacho_mark.sh` es el único detrás del botón), ids cortos como handle.

## Deuda y gotchas vigentes

- Re-cifrar `access_token`/`verify_token` (inline en config.toml; el
  `config set` exige TTY → lo corre Santiago). Al hacerlo, mover el token de
  `despachar.sh` a `WABA_TOKEN=` en `.env`.
- Display name del número es **«Feria Local - Ventas»** (los destinatarios lo
  ven); renombrar en Meta si molesta. La plantilla se presenta como Iki/Ikigai.
- Router: guard pendiente para POSTs no-JSON (TypeError inofensivo en logs);
  rotar la key OpenRouter expuesta en el config viejo de Coco
  (`/agentico/data/ids/f90575da-…/config.toml` — de ahí salieron las
  credenciales WABA; flota «Agentico» previa, 9 agentes, era pre-v3).
- Cost tracking sin pricing para `claude-sonnet-5` → `max_cost_per_day_cents`
  inerte; el freno real es `max_actions_per_hour`.
- La cosecha (`sync_despachos.sh`) es manual — candidata a cron/Routine.
- Miembros sin WhatsApp en la DB (Mateo, Francisco O., Roberto M.) no
  resuelven en el directorio → poblar `team_members`.
- WhatsApp **Web** (cuenta normal por QR) está compilado y disponible como
  laboratorio/fallback; si se usa: `mode="personal"` obligatorio (el default
  `business` NO evalúa la allowlist de remitentes).

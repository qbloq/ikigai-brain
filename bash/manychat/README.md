# bash/manychat — ManyChat en la fuente (Instagram DMs)

Sonda **read-only** contra el API de ManyChat (`api.manychat.com/fb/…`, Bearer).
Patrón `bash/vturb/`: el token nunca se imprime ni viaja en argv (va a curl como
header por stdin), solo lecturas. Existe porque el **embudo orgánico** —
conversaciones de setters → leads orgánicos → cierres, ROAS contra los
follow-me ads — no tiene fuente en el Cerebro: `embudo.sh` solo cuenta los leads
del CRM sin pauta (`crm.organicos`). Este dominio es la entrada de ese bloque.

## Tokens — cuál es cuál (verificado 2026-08-21)

Los tokens de ManyChat son **por cuenta conectada**. Llegaron dos, ambos
respondiendo «David Guerrero», pro, America/Bogota — y son **dos cuentas de
Instagram distintas**, las dos activas (flujos creados el 2026-08-20 en ambas,
casi gemelos con 3 min de diferencia). Se distinguieron con `auth_status.sh` y
tres sondas más (`page/getGrowthTools`, `page/getFlows`,
`subscriber/findByName` con leads ganados del CRM):

| token (prefijo) | growth tools | flujos / carpetas | leads ganados del CRM como suscriptores | rol |
|---|---|---|---|---|
| `3175…` (hoy `MANYCHAT_TOKEN_B`) | 32: 16 story reply + **16 comentarios en post/reel** | 51 · «Audios calificación / confirmar agenda / descalificación / descubrimiento», **5 flujos de setter**, «follow me automatización», «INSTAGRAM 2026», lanzamiento abril | **sí** (Andres Mantilla → `andrescamilomm`, Camila Arboleda → `camyarboleda`) | **LA OPERACIÓN** — fuente del embudo orgánico |
| `5001…` (hoy `MANYCHAT_TOKEN_A`) | 17: solo story reply | 40 · «curso youtube», «Follow me auto», lead magnets de YouTube | ninguno | cuenta secundaria (contenido/YouTube) |

Ambas tienen carpeta «Imported from David Guerrero»: una nació importando los
flujos de la otra. El API no expone el `username` de IG en `page/getInfo`, así
que el handle exacto de cada cuenta hay que confirmarlo en la app de ManyChat;
el **rol operativo** ya está claro por los datos.

Sugerencia de nombres en `.env` (el script lee cualquier `MANYCHAT_TOKEN*`):
`MANYCHAT_TOKEN_DG` = la B (operación) · `MANYCHAT_TOKEN_DG_YT` = la A.

| Script | Use it to… |
|---|---|
| `auth_status.sh [--json]` | Qué tokens hay en `.env` y a qué página responde cada uno (nombre, plan, timezone); falla claro si no hay ninguno. |

## Lo que el API NO puede dar (medido 2026-08-21, 79 leads orgánicos de agosto)

- **No lista suscriptores** ni da conteos por tag/flow: `getTags`/`getFlows`/
  `getGrowthTools` devuelven nombres, nunca cantidades. Analytics solo en la UI.
- **Los suscriptores de Instagram no traen email ni teléfono**:
  `findBySystemField` por email **0/8**, por teléfono 0/1.
- **Por nombre (`findByName`) matchea 14/79 (18 %)**, 3 ambiguos, y con falsos
  positivos probables (un «match» suscrito en 2025-09 para un lead de 2026-08).
- Los contactos del CRM traen el campo «¿Cuál es tu Instagram?» solo en 5/79.

Conclusión: ManyChat hoy es **mapa, no medida**. `bash/metrics/organico.sh`
(el bloque orgánico) lo usa solo para `manychat.mapa` (los 22 tags = el
recorrido nuevo seguidor → quiz → pide asesoría → serie YT módulos → lead
magnets → grupo VIP) y mide el embudo orgánico desde el CRM + caja.

**Pedido pendiente (la llave):** que el flujo de ManyChat que crea el contacto
en GHL (los leads de la serie YT llegan con tags `moduloNyt`, así que esa
integración existe) escriba también `ig_username` y el `subscriber_id` de
ManyChat en custom fields del contacto. Con eso el join lead ↔ suscriptor es
exacto y `subscriber/getInfo` da por lead: fecha de suscripción, último
contacto, tags (qué vio), `last_input_text` — el setter → lead que hoy no se ve.

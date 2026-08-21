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

Siguiente pieza: la sonda de conversaciones/etiquetas para el bloque orgánico de
`embudo.sh` (hoy el API no lista suscriptores: se llega por tags/flows/growth
tools y por `findByName`/`findBySystemField` desde el lead del CRM).

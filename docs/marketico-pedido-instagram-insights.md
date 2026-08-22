# Pedido a Marketico — scopes de Instagram en el login de Facebook (seguidores por día)

**Fecha:** 2026-08-21 · **Quién pide:** Cerebro / Ikigai (Santiago) · **Para:** equipo Marketico
**Tamaño:** chico en código, pero toca el app de Meta (scopes + posible App Review).

## Qué pasa hoy

El token de `identities` (provider `facebook*`, el login de Marketico) trae
`email, ads_management, ads_read, business_management, pages_show_list,
pages_read_engagement, whatsapp_*` (`src/index.ts:372`, `metaApiClient.ts:903`).
Con eso el Cerebro ya lee anuncios, creativos y las acciones por campaña de
los follow-me ads (visitas al perfil, conversaciones DM, likes:
`bash/ads/followme.sh`). Lo que **no** puede leer es IG Insights:

```
GET /{ig-user-id}/insights?metric=follower_count&period=day        → (#10) Application does not have permission
GET /{ig-user-id}/insights?metric=follows_and_unfollows&...         → (#10)
```

Meta no reporta «follows» como acción de anuncio, así que **seguidores nuevos
por día** —la métrica natural de los follow-me ads y del embudo orgánico—
solo sale de ahí. Mientras tanto el Cerebro toma una **foto diaria del total**
(`bash/ads/seguidores_snapshot.sh`, `me/accounts{instagram_business_account
{followers_count}}` sí responde con `pages_show_list`) y resta: la serie
empieza el 2026-08-21 y no tiene pasado.

## Qué pedimos

1. Agregar al scope del login de Facebook: **`instagram_basic`** y
   **`instagram_manage_insights`** (y `pages_read_engagement` ya está). En
   `src/index.ts` (scopeArray y `scopes`) y `metaApiClient.ts` (la URL del
   dialog OAuth).
2. Que David (o quien sea admin de las páginas «David Guerrero FX» →
   `@davidguerrero.pro` y «David Guerrero 93» → `@davidguerrero_93`) vuelva a
   hacer login para que el token nuevo traiga los scopes.
3. Si el app de Meta está en modo live y los scopes piden App Review: los
   admins/testers del app no lo necesitan — alcanza con que el usuario que
   hace login sea admin del app o esté como tester.

## Qué habilita (del lado del Cerebro, ya escrito para recibirlo)

- `follower_count` diario hacia atrás (hasta 30 días por llamada, paginable):
  la serie de seguidores nuevos se completa sin esperar fotos.
- `follows_and_unfollows` (follows vs unfollows por día) y `profile_views`,
  `reach`, `accounts_engaged` de la cuenta — el tope del embudo orgánico.
- Cruce con la pauta de marca por día (`followme.sh` ya emite la serie de
  visitas al perfil/DM/inversión): **costo por seguidor** real en vez del
  heurístico de fotos.

## Criterio de aceptación

`bash/ads/followme.sh --project "David Guerrero"` deja de reportar
`seguidores.disponible` solo por fotos y trae `follower_count` por día de las
dos cuentas IG; ningún otro scope existente cambia.

# Pedido a Marketico — persistir la atribución de GHL en el espejo del CRM

**Fecha:** 2026-08-21 · **Quién pide:** Cerebro / Ikigai (Santiago) · **Para:** equipo Marketico
**Repo afectado:** `marketico` · **Tablas:** `ikigaigm.crm_contacts` (+ opcional tabla nueva)
**Tamaño estimado:** chico — el dato ya llega; solo falta guardarlo.

## 1. Qué pasa hoy (verificado 2026-08-21)

El sync de CRM (`src/services/projectCrmService.ts`, `syncPipelineOpportunities`)
ya hace, por cada oportunidad, un **`GET /contacts/{id}`** a GHL
(`ghl.getContact`, línea ~718). Esa respuesta trae la **atribución nativa** del
contacto — `attributionSource` y `lastAttributionSource` — con:

```
sessionSource, url, campaign, campaignId, utmSource, utmMedium, utmCampaign,
utmContent, utmTerm, utmKeyword, utmMatchtype, referrer, fbclid, gclid,
fbc, fbp, userAgent, ip, medium, mediumId
```

En los leads de pauta de David Guerrero la `url` trae además
`campaign_id`, `adset_id`, **`ad_id`**, `placement`, `site_source_name`, y
`utmTerm` **es** el `ad_id` de Meta. Sondeo de 30 contactos recientes, GET
individual: **30/30 con atribución · 22/30 con `utmContent` · 20/30 con
`ad_id`**; los 8 restantes son «Direct traffic» / orgánico, que también es
información. Los 11 `ad_id` distintos que salieron resuelven **11/11** en la
tabla `ads` (misma DB) — o sea el join anuncio → lead → oportunidad → caja es
posible hoy mismo.

Pero al armar el `contactPayload` (líneas ~721-728) se guardan solo
`first_name/last_name/email/phone/tags/custom_fields`: **la atribución se
descarta** en el mismo request que la trajo. Nota: el listado
`GET /contacts/` de GHL NO trae `attributionSource` — solo el GET por id — así
que este sync es exactamente el lugar donde se puede capturar sin llamadas
extra.

Consecuencias visibles:
- No hay caja por **anuncio** (creativo) — solo por campaña vía el custom field
  `utm_campaign`. El dashboard comercial del equipo (UI `anuncios`) muestra ROAS
  del pixel y lo declara como tal.
- `utm_content`, `utm_term`, `placement`, `fbclid` se pierden → no hay
  atribución por creativo/ubicación ni reconciliación con el pixel.
- El custom field **`vtid`** (id de sesión de VTurb, `V1k0OpjddlTmZ1kgvw3z`)
  sí se guarda en `custom_fields`, pero no está en `crm_custom_fields` porque
  `syncCustomFields` no lo trae (o es posterior al último sync de definiciones)
  — vale revisar de paso.

## 2. Qué pedimos (en orden; 2.1 es lo que importa)

### 2.1 Persistir `attributionSource` y `lastAttributionSource` tal cual (jsonb)

Migración (idempotente, mismo estilo de `add_ghl_data_hash_to_crm_tables.sql`):

```sql
ALTER TABLE "{{SCHEMA_NAME}}".crm_contacts
  ADD COLUMN IF NOT EXISTS attribution_source      jsonb,
  ADD COLUMN IF NOT EXISTS last_attribution_source jsonb,
  ADD COLUMN IF NOT EXISTS ghl_source              text,         -- contact.source ("Survey Mastermind - VSL NUEVO OCT 2025")
  ADD COLUMN IF NOT EXISTS ghl_date_added          timestamptz;  -- contact.dateAdded (hoy created_at = fecha de INGESTA, no del lead)
```

Código (`projectCrmService.ts`, `contactPayload`):

```ts
const contactPayload = {
  first_name: contact.firstName || null,
  last_name:  contact.lastName  || null,
  email:      contact.email     || null,
  phone:      contact.phone     || null,
  tags:       contact.tags      || [],
  custom_fields: contact.customFields || {},
  attribution_source:      contact.attributionSource     || null,   // NUEVO
  last_attribution_source: contact.lastAttributionSource || null,   // NUEVO
  ghl_source:     contact.source    || null,                          // NUEVO
  ghl_date_added: contact.dateAdded || null,                          // NUEVO
};
```

Como el hash `ghl_data_hash` se calcula sobre `contactPayload`, al incluir los
campos nuevos **el próximo sync re-escribe solos** los contactos (hash
distinto) — no hace falta backfill aparte para los que vuelvan a pasar por el
sync. Para los históricos que no cambien, ver 2.3.

Guardarlo **crudo** (jsonb) y no columnas sueltas: el objeto de GHL tiene ~20
claves y cambia; las columnas derivadas las extraemos nosotros del lado de
lectura (ver §3).

### 2.2 Columnas derivadas indexables (opcional, cómodo para queries)

Si prefieren columnas, las cuatro que de verdad se consultan:

```sql
ALTER TABLE "{{SCHEMA_NAME}}".crm_contacts
  ADD COLUMN IF NOT EXISTS attr_ad_id       text,   -- utmTerm si es numérico de ≥10 dígitos, si no url?ad_id=
  ADD COLUMN IF NOT EXISTS attr_adset_id    text,   -- url?adset_id=
  ADD COLUMN IF NOT EXISTS attr_campaign_id text,   -- campaignId
  ADD COLUMN IF NOT EXISTS attr_utm_content text;
CREATE INDEX IF NOT EXISTS idx_crm_contacts_attr_ad_id ON "{{SCHEMA_NAME}}".crm_contacts(project_id, attr_ad_id);
```

Regla de precedencia: **`lastAttributionSource` primero** (el último toque es
el que agendó), `attributionSource` como fallback. Si no quieren meter la
regla en el ingestor, con 2.1 alcanza: la derivamos nosotros.

### 2.3 Backfill de los contactos ya ingestados (una vez)

Un script/endpoint que recorra `crm_contacts` del proyecto y haga el
`GET /contacts/{id}` para llenar las columnas nuevas (~2.1k contactos DG, ~500
Andrea; rate limit de GHL 100 req/10 s → unos minutos). Si no hay tiempo, lo
podemos correr nosotros desde el Cerebro con el token de `project_crm_configs`
(`bash/ghl/`) y **escribir solo esas columnas** — pero preferimos que la escritura
en `crm_contacts` siga siendo de un solo dueño (Marketico).

### 2.4 De paso (no bloquea): `syncCustomFields`

Re-sincronizar las definiciones: el campo `vtid` (`V1k0OpjddlTmZ1kgvw3z`)
aparece en `custom_fields` de contactos recientes y no existe en
`crm_custom_fields`. Con eso el eslabón VSL (VTurb) → lead queda también
cerrado.

## 3. Cómo lo vamos a usar nosotros (para que se entienda el porqué)

- `bash/ads/anuncios.sh` → pasa de «ROAS del pixel» a **leads, planes y caja
  real por anuncio** (lead → `crm_opportunities` → `payment_plans`/`installments`),
  con la misma guardia temporal que `embudo.sh` usa por campaña.
- `bash/crm/leads.sh` / `opp_detail.sh` → `origen` deja de depender del custom
  field `utm_campaign` (que lo llena el formulario, y a veces llega literal
  `{{campaign.name}}`) y usa la atribución del navegador, que no depende del form.
- `bash/metrics/embudo.sh` → `atribucion` por campaña con dos fuentes
  (custom field vs attribution) y su delta en `conciliacion`.
- Ubicación (`placement`) y `fbclid` → reconciliación pixel vs CRM por lead
  (hoy el pixel de la cuenta COP tiene magnitudes basura; esto da una vara).

## 4. Criterio de aceptación

1. Tras un sync, un contacto de pauta reciente (p. ej. `npWNDa7f6OVqT4YXxdxO`,
   DG) tiene `last_attribution_source->>'utmContent' = '003.2_AD_5_TO_AD_7_IPHONE - Copy-003_AD_5_POST_ID'`
   y `utmTerm = '120254921120000628'`, y ese id existe en `ads`.
2. Un contacto orgánico trae `sessionSource = 'Direct traffic'` (o similar) y
   `utmContent` nulo — **no** se inventa atribución.
3. `ghl_date_added` ≠ `created_at` para los históricos (hoy `created_at` son
   corridas de exactamente 100 filas: es fecha de ingesta).
4. Ninguna fila de `crm_contacts` se borra ni cambia de `id` (hay FKs desde
   `crm_opportunities` y joins desde el Cerebro).

## 5. Estado — 2026-08-21, mismo día: HECHO por Marketico

Verificado en la DB la tarde del 21: las 8 columnas de 2.1 + 2.2 existen y el
backfill 2.3 corrió **completo** (2.784 contactos; 1.542 con `attr_ad_id`
válido; por mes de ingesta feb→ago 2026 la cobertura de atribución es ≥98%).
Tres observaciones para la siguiente iteración, ninguna bloquea:

- **Regla de derivación implementada** (inferida de los datos): último toque
  antes que primero, y `url.ad_id` antes que `utmTerm` — coherente; la
  documentamos así en `bash/ads/anuncios.sh`.
- **No sanea plantillas rotas**: 2 filas con `attr_ad_id = '{{ad.id}}'` literal
  (UTM sin resolver). Lo correcto es NULL cuando no es `^[0-9]+$`; del lado del
  Cerebro filtramos con esa regex.
- **`ghl_source` mezcla mayúsculas** (`Survey Mastermind - VSL NUEVO OCT 2025`
  y `survey mastermind - vsl nuevo oct 2025` son el mismo formulario). Si se
  agrupa por origen, normalizar con `lower()`.
- 2.4 (`vtid` en `crm_custom_fields`) sigue pendiente — sin urgencia.

Primer consumidor: `bash/ads/anuncios.sh` (UI ejecutivo `anuncios`) muestra
desde hoy leads/planes/contrato/cash/ROAS real por anuncio al lado del pixel.
Agosto DG: 248 leads → 170 con anuncio (69%) → 163 cuyo ad gastó en el mes.

## 6. Referencias

- Evidencia del sondeo y el join con `ads`: sesión del Cerebro 2026-08-21
  (30 contactos recientes DG vía `bash/ghl/contacts.sh --id`).
- Código: `marketico/src/services/projectCrmService.ts` (`syncPipelineOpportunities`,
  `contactPayload`), `marketico/src/services/ghlService.ts` (`getContact`),
  `marketico/src/routes/ghlRoutes.ts` (`/crm/call` ya destructura
  `contact.attributionSource` del webhook — el dato también entra por ahí).
- Ya reportado antes por el mismo canal: bug de retención del normalizador VTurb
  (`bash/vturb/README.md`).

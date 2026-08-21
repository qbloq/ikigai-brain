# GHL domain — el CRM en la fuente

Acceso **de solo lectura** al API de GoHighLevel (v2), directo contra
`services.leadconnectorhq.com`. Existe para una sola cosa: **medir el espejo
contra la fuente**.

Todo lo demás en este repo lee el espejo — `crm_contacts` y
`crm_opportunities`, que un ingestor externo copia desde GHL. `bash/crm/`, la
resolución de closers de `bash/calls/`, y con ellos toda la capa del Director
Comercial, dan ese espejo por bueno. Nadie lo estaba verificando. Esto lo
verifica.

**No es una segunda vía de ingesta.** Ningún script de aquí escribe: ni en GHL
ni en la base. Si el espejo hay que arreglarlo, se arregla en el ingestor.

## Credenciales — leer antes de extender

A diferencia de [`bash/google/`](../google/README.md), donde el backend es
dueño de la identidad y los scripts nunca ven un token, los **Private
Integration Tokens** de GHL viven en la base: `project_crm_configs`, uno por
proyecto, en texto plano pese a que la columna se llame `api_key_encrypted`.
Cualquiera que pueda leer el Postgres de la org puede leerlos. Por eso esta
capa va cercada:

- **Cerca por rol.** La decide `bash/lib/acceso.sh` (`require_acceso ghl`):
  sin `copilot.json` = cerebro = acceso; con `copilot.json`, solo los roles del
  mapa (hoy `ejecutivo`); el resto se niega con `exit 3` y va al espejo
  (`bash/crm/`). Ampliar el mapa es decisión de gobernanza.
- **Solo GET, con UNA excepción declarada.** La conexión a la base es `psql_ro`.
  La excepción es `POST /contacts/search` (`ghl_api_search` en
  [lib/common.sh](lib/common.sh), detrás de `contacts.sh --query`): GHL expone
  la búsqueda de contactos como POST porque los criterios no caben en una query
  string, pero **es un fetch — no crea ni modifica nada**. Autorizada por
  Santiago el 2026-08-14, cuando confirmar si un contacto existía obligaba a
  paginar ~2.000 registros. La regla real de esta capa no es «el verbo GET»
  sino **«nada que escriba en GHL»**; cualquier endpoint que mute queda fuera,
  sea POST, PUT o DELETE.
- **El token nunca pasa por `argv`.** Se le entrega a curl por stdin
  (`--config -`), así no aparece en la lista de procesos.

El estado correcto es mover las credenciales detrás del backend, como Drive.
Mientras tanto, esta cerca es lo que impide que se rieguen.

## Scripts

| Script | Para… |
|--------|-------|
| `auth_status.sh [--json]` | Qué proyectos tienen integración y si responde. Sonda en vivo: autenticación + cuántos contactos y oportunidades reporta GHL por location. |
| `gap.sh [--project N] [--ids] [--json]` | **El informe de cobertura**: GHL contra la base, por proyecto. `--ids` recorre toda la paginación y cuenta cuántas oportunidades faltan de verdad (lento: una página por cada 100). |
| `contacts.sh --project N [--query T] [--limit N] [--id ID] [--missing] [--json]` | Contactos desde la fuente. **`--query` BUSCA** por nombre, email o teléfono (`POST /contacts/search`) — la vía correcta para «¿existe este contacto?»: una llamada en vez de paginar miles. `--missing` = solo los que el espejo no tiene. `--id` busca uno puntual — útil cuando una llamada no resuelve closer y hay que saber si el contacto existe upstream. |
| `opportunities.sh --project N [--limit N] [--status S] [--missing] [--json]` | Oportunidades desde la fuente, con las mismas banderas. `--status open\|won\|lost\|abandoned`. |

`--limit 0` pagina hasta el final. La paginación va por
`meta.startAfterId`/`startAfter`, deduplica la fila del cursor y corta cuando
llega una página corta.

## Lo que encontró al nacer (2026-08-04)

El primer `gap.sh` daba un cuadro alarmante — 6% de los contactos, 32% de las
oportunidades — pero esa comparación es **contra todo GHL**, y exagera. Con el
detalle por pipeline el diagnóstico real es otro:

**1. El espejo está acotado a un pipeline por proyecto**, los que están en
`crm_pipelines`. GHL tiene 12 pipelines para David y 5 para Andrea; ingerimos
NEW CRM TEST y ALQUIMIA CRM. Y está bien apuntado: de los demás, el único que
sigue recibiendo oportunidades es **LOW TICKET** (David), que además se apagó en
julio (53 en mayo, 55 en junio, 5 en julio, 0 en agosto — y cero `won` en sus
750 oportunidades de vida). El resto es histórico muerto. Comparar totales de
CRM completo contra la base no mide nada útil: hay que comparar **dentro del
pipeline espejado**.

**2. El ingestor deriva porque pagina de a 100 y se dispara a mano.** El
histórico de `crm_contacts.created_at` muestra corridas de exactamente 100 filas
(04-ago, 23-jul, 14-jul, 29-jun, 29-may) y otras de menos: cuando pasan más de
~10 días entre corridas, el excedente se cae en silencio. Julio de 2026 —el mes
de más volumen— perdió así **202 de 552** oportunidades. El API pagina sin
problema (`opportunities.sh --project Andrea --limit 0` trae las 495 completas),
o sea que el tope es del ingestor, no de GHL.

**3. `crm_contacts` no es un espejo de contactos**, es un subproducto de ingerir
oportunidades: en la base van ~1:1, en GHL van ~1,6:1. Por eso una llamada cuyo
booking apunta a un contacto sin oportunidad no resuelve closer.

**4. `crm_contacts` no guarda la fecha de creación de GHL** — su `created_at` es
la fecha de ingesta, así que las cohortes por fecha de contacto miden nuestra
ingesta y no el negocio. Para oportunidades sí hay `created_date` real.

## Estado tras el backfill del 2026-08-04

`node scripts/backfill-ghl.js` **[WRITE]** repara el hueco hacia atrás (no
arregla el ingestor). Corrido ese día con la ventana por defecto:

```
                    antes            después
Andrea Torres    73 / 73          100 / 100      (contactos / opps)
David Guerrero 2280 / 2281       2490 / 2491
```

- Pipeline espejado, mayo–agosto: **1086 / 1086** en David, sin faltantes.
- Resolución de closer en llamadas analizadas: **80% → 86%** (195 de 226).
- Lo que sigue sin resolver son llamadas cuyo contacto **ya no existe en GHL**.
- Las oportunidades sin `user_id` (237 solo en julio) son un hueco de asignación
  real en GHL, no un artefacto de ingesta.

## Lo que encontró la auditoría de ventas perdidas (2026-08-14)

Cruzando los reclamos de un closer contra la fuente
(`docs/only-closers-informe.md` §8, doc de operador)
aparecieron dos hallazgos que cambian cómo hay que consultar esta capa.

**5. El ingestor no refresca el `status` de las oportunidades que ya tiene.**
Trae las nuevas, sí; pero una que pasa a `won` después de ingerida se queda
`open` en el espejo para siempre. Tres ventas del mismo closer figuraban `open`
con GHL diciendo `won` —una desde hacía tres semanas—, y una sincronización
manual **no las corrigió**. Antes de esa sync: **288 `won` en el espejo contra
312 en GHL**. Esas ~24 ventas invisibles no son un hueco de paginación como el
punto 2: es que el upsert no mira el estado. Arreglarlo es del ingestor.

**6. Buscar por NOMBRE en este CRM produce falsos negativos.** Tres motivos,
los tres verificados:
- **Acentos combinantes**: «Jonathan Marulanda Vásquez» no matchea
  `ILIKE '%marulanda vás%'` (la `á` es `a`+U+0301, no U+00E1). Casi nos hace
  concluir que una fila había desaparecido del espejo.
- **La misma persona bajo dos nombres**: un contacto tenía dos oportunidades,
  «Ilder Bonifacio» (2025) y «Edilio Suazo» (2026) — mismo `contactId`, mismo
  email, mismo teléfono.
- **El índice de GHL no normaliza teléfonos**: `--query 584146138779` devuelve
  0 para un contacto cuyo `phone` es `+584146138779`.

**El identificador que nunca miente es `contactId`.** Las 7.336 oportunidades de
David lo traen y ninguna lo omite (verificado); el bloque `relations` además
embebe email y teléfono del contacto, así que **buscar oportunidades por
contacto en vez de por nombre** es lo correcto y detecta el caso «la ficha está
con otro nombre». Toda auditoría futura debe cruzar por ahí — y contra
`payment_plans.customer_id`, que guarda justamente el id de contacto de GHL.

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

- **Solo el cerebro.** Si existe `copilot.json` en la raíz, los scripts se
  niegan a correr. Los forks heredan este código pero no las credenciales del
  CRM; un copiloto lee el espejo (`bash/crm/`), no la fuente.
- **Solo GET.** Y la conexión a la base es `psql_ro`.
- **El token nunca pasa por `argv`.** Se le entrega a curl por stdin
  (`--config -`), así no aparece en la lista de procesos.

El estado correcto es mover las credenciales detrás del backend, como Drive.
Mientras tanto, esta cerca es lo que impide que se rieguen.

## Scripts

| Script | Para… |
|--------|-------|
| `auth_status.sh [--json]` | Qué proyectos tienen integración y si responde. Sonda en vivo: autenticación + cuántos contactos y oportunidades reporta GHL por location. |
| `gap.sh [--project N] [--ids] [--json]` | **El informe de cobertura**: GHL contra la base, por proyecto. `--ids` recorre toda la paginación y cuenta cuántas oportunidades faltan de verdad (lento: una página por cada 100). |
| `contacts.sh --project N [--limit N] [--id ID] [--missing] [--json]` | Contactos desde la fuente. `--missing` = solo los que el espejo no tiene. `--id` busca uno puntual — útil cuando una llamada no resuelve closer y hay que saber si el contacto existe upstream. |
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

# Slices de datos por rol — el puente ontología de procesos → ontología de datos

> **Qué es esto.** Los docs de rol mapean *rol → procesos* (la matriz rol×macro
> del [README](README.md), evidencia: 323 tareas etiquetadas). El acceso a
> datos necesita *rol → entidades*. Este doc es esa traducción: cruza la
> matriz con los **12 dominios** del grafo de entidades
> ([docs/graph](../graph/README.md), 98 entidades) y produce el **mapa de
> slices** que alimenta (a) las políticas RLS de la Etapa 2
> ([003_roles_copiloto.sql](../../catalog/migrations/003_roles_copiloto.sql):
> la política `copiloto_acceso` se REEMPLAZA por rol — las permisivas se
> OR-ean, no se recortan añadiendo) y (b) las reglas del proxy de fuentes
> no-Postgres (Notion, Drive, WhatsApp…). La ontología crecerá más allá de la
> DB; el slice se define UNA vez aquí y se impone en ambos rieles.

## 1 · Macro-procesos → dominios de datos

Cada macro-proceso implica dominios. Derivado de qué entidades toca el trabajo
real de cada S (no especulativo — los scripts de cada dominio son la prueba):

| Macro | Dominios núcleo | Lectura |
|---|---|---|
| S1 Narrativa & Oferta | content | crm (objeciones ← call reports) |
| S2 Producción de Creativos | content | ads |
| S3 Optimización de Pauta | ads | okr |
| S4 Contenido Orgánico | content | — |
| S5 Testimonios / Prueba Social | content | crm, meetings |
| S6 Calificación de Leads & Setter | crm, whatsapp | meetings |
| S7 Funnel / Landing / Checkout | projects | ads, finance (checkout) |
| S8 Métricas & Fuente de Verdad | okr | finance, ads, crm |
| S9 Lanzamiento / Masterclass | content | ads, crm |
| S10 Gobernanza de Tareas | tasks (baseline) | — |
| S11 Producto / Plataforma | runtime (⚠ operador) | — |
| S12 Cierre & Retención | crm, meetings (calls) | finance (cobros) |

## 2 · Baseline — lo que TODO copiloto ve

El sustrato de coordinación, sin el cual ningún script funciona:

- **tasks** (10 tablas) — el sistema de tareas completo, el 🧬 núcleo.
- **catalog** (10) — la ontología de procesos (SOPs, arquetipos, io_types).
- **people** (6 de 7) — resolución de nombres/roles (`team_members`, `users`,
  `persons`, `team_roles`, `teams`, `team_member_roles`). **Excluida:**
  `identities` (material de autenticación).
- **projects** (4 de 15) — `projects`, `spaces`, `project_teams`, `settings`.
  **Excluidas: todas las `project_*_configs`** (9 tablas — guardan
  configuración de integraciones: ids, tokens, cuentas. Son material del
  proxy/operador, no de copilotos).
- **meetings** (parcial) — `meetings`, `meeting_reports`,
  `meeting_participants` (coordinación). `meeting_transcripts` y
  `call_meeting_results` solo en los slices que los necesitan (S12).

## 3 · El mapa: rol → dominios

`●` núcleo (lee y su trabajo escribe ahí vía scripts) · `○` lectura · vacío = fuera del slice.
Baseline (§2) implícito en todos.

| Rol | ads | content | crm | finance | meetings+ | okr | whatsapp |
|---|---|---|---|---|---|---|---|
| Copy | ○ | ● | ○ | | | | |
| Estratega | ● | | | | | ○ | |
| Editor | ○ | ● | | | | | |
| Diseño | ○ | ● | | | | | |
| Contenido | ○ | ● | | | | | |
| Ejecutivo | ● | ● | ● | ● | ○ | ● | ○ |
| Operaciones | ○ | ● | ○ | ○ | | | ○ |
| Technology | ○ | ○ | | ○ | | | |
| Setter | | | ● | | ○ | | ● |
| Líder de servicio | | ● | ○ | | ○ | | ● |
| Director Comercial | | | ● | ○ | ● | ● | ○ |
| Project Manager | ○ | ● | ○ | | | ○ | |

`meetings+` = transcripts + call_meeting_results (las llamadas de venta — el
territorio del Director Comercial; Setter/Líder ven reports, no transcripts).

## 4 · Sensibilidad — lo que el slice NUNCA incluye (ningún rol)

| Qué | Por qué |
|---|---|
| `runtime` completo (14 tablas) | Plataforma Parallelo: `llmrouter_api_keys` (¡llaves en la DB!), prompts, workers. Solo operador. |
| `project_*_configs` (9) | Configuración de integraciones — el llavero estructural. Solo operador/proxy. |
| `identities` | Material de autenticación de la app. |
| `payroll_*`, `commission_*`, `economics_ledger`, `revenue_share_*` | Compensación — dentro de finance, tier aparte: solo Ejecutivo (●) y Director Comercial (○ commissions de su equipo). El resto de finance (installments, payment_plans, expenses, products) es el tier general del mapa. |

## 5 · Cómo se aplica

- **Postgres (Etapa 2):** por cada rol se genera la política que reemplaza a
  `copiloto_acceso` en las tablas de su slice — un rol de grupo por rol de
  negocio (`ikigai_rol_copy`, …) entre `copiloto_base` y el empleado, y la
  política ata `USING` a la membresía. Tablas fuera del slice: sin política →
  RLS niega solo (deny by default). Las tablas de §4 pierden además el GRANT.
- **Fuentes no-Postgres (proxy):** el mapa por dominio se traduce a reglas por
  proveedor (Notion→content, Evolution→whatsapp, …): el token del copiloto
  autoriza los proveedores de su slice, con la misma tabla como fuente de
  verdad.
- **Regenerar:** cuando la matriz rol×macro cambie (README §Regenerar), este
  mapa se revisa — es derivado, no fuente.

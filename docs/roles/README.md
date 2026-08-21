# Roles de Ikigai — SOPs, arquetipos y tareas

> Un documento por rol, derivado de la ontología de procesos
> (`cadena de valor → macro (S1…S12) → SOP → arquetipo → tarea`,
> `catalog/sop-archetypes.json`) cruzada con las **tareas reales**
> etiquetadas (`tasks.archetype_id` → asignados → `team_roles`). Lo
> cuantitativo viene de la DB; lo cualitativo (misión, candidatos,
> brechas) del `discovery original`.
> Corte de datos: 2026-07-12 — 329 tareas, 323 etiquetadas (98%), 21 sin asignar.

Cada rol es también la identidad de una **capa de copiloto**
(`copilot.json.role` → `viz/specs/roles/<slug>/`): este doc es el insumo
para craftear qué ve y qué opera cada copiloto.

## Los 12 roles (19 copilotos)

| Rol | Doc | Personas | Tareas | Abiertas | Macro dominante |
|---|---|---|---|---|---|
| Copy | [copy.md](copy.md) | 2 | 83 | 16 | S9 Lanzamiento / Masterclass |
| Estratega | [estratega.md](estratega.md) | 1 | 19 | 11 | S3 Optimización de Pauta |
| Editor | [editor.md](editor.md) | 1 | 37 | 13 | S2 Producción de Creativos (anuncios) |
| Diseño | [diseno.md](diseno.md) | 2 | 19 | 0 | S2 Producción de Creativos (anuncios) |
| Contenido | [contenido.md](contenido.md) | 3 | 35 | 7 | S2 Producción de Creativos (anuncios) |
| Ejecutivo | [ejecutivo.md](ejecutivo.md) | 2 | 77 | 13 | S9 Lanzamiento / Masterclass |
| Operaciones | [operaciones.md](operaciones.md) | 1 | 33 | 3 | S9 Lanzamiento / Masterclass |
| Technology | [technology.md](technology.md) | 3 | 20 | 2 | S7 Funnel / Landing / Checkout |
| Setter | [setter.md](setter.md) | 1 | 0 | 0 | — |
| Líder de servicio | [lider-de-servicio.md](lider-de-servicio.md) | 1 | 6 | 2 | S5 Testimonios / Prueba Social |
| Director Comercial | [director-comercial.md](director-comercial.md) | 1 | 22 | 13 | S8 Métricas & Fuente de Verdad |
| Project Manager | [project-manager.md](project-manager.md) | 1 | 98 | 26 | S2 Producción de Creativos (anuncios) |

## Matriz rol × macro-proceso (tareas etiquetadas)

| Rol | S1 | S2 | S3 | S4 | S5 | S6 | S7 | S8 | S9 | S10 | S11 | S12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Copy | 8 | 21 | 2 | 4 | 2 | 4 | 4 | 1 | 31 | 6 | · | · |
| Estratega | · | 4 | 12 | · | · | · | · | 1 | 1 | 1 | · | · |
| Editor | · | 34 | · | · | 2 | · | 1 | · | · | · | · | · |
| Diseño | · | 18 | · | · | · | · | · | · | · | · | · | 1 |
| Contenido | 1 | 10 | 2 | 10 | · | 4 | 3 | 2 | · | 2 | · | · |
| Ejecutivo | 3 | 2 | 5 | 1 | 2 | 3 | 17 | 6 | 24 | 6 | 5 | 2 |
| Operaciones | · | · | · | · | · | 3 | 9 | · | 21 | · | · | · |
| Technology | 1 | · | · | · | · | 2 | 12 | · | 2 | 2 | · | · |
| Setter | · | · | · | · | · | · | · | · | · | · | · | · |
| Líder de servicio | · | · | · | · | 4 | · | 1 | · | · | · | · | 1 |
| Director Comercial | 1 | · | 1 | · | 1 | 5 | · | 6 | 1 | · | 3 | 4 |
| Project Manager | · | 61 | 4 | 2 | 5 | 3 | 5 | 2 | 4 | 6 | 1 | 3 |

Leyenda: **S1** Narrativa & Oferta · **S2** Producción de Creativos (anuncios) · **S3** Optimización de Pauta · **S4** Contenido Orgánico · **S5** Testimonios / Prueba Social · **S6** Calificación de Leads & Setter Ops · **S7** Funnel / Landing / Checkout · **S8** Métricas & Fuente de Verdad · **S9** Lanzamiento / Masterclass · **S10** Gobernanza de Tareas · **S11** Producto / Plataforma (Paralelo) · **S12** Cierre & Retención (Closers).

## Qué puede cada rol — `acceso.json`

Lo que un copiloto puede **ver** (capas de UI) y **consultar** (fuentes con
credencial de proveedor) lo define **el rol**, no el hecho de ser copiloto
(spec `docs/superpowers/specs/2026-08-20-control-de-acceso-fuentes-design.md`
+ adenda 2026-08-21). El mapa es UN archivo, [`acceso.json`](acceso.json),
con tres consumidores:

| Clave | Quién la lee | Significado |
|---|---|---|
| `uis` | `viz/lib/store.js` | `"*"` = el viz carga las capas de UI de **todos** los roles (con badge de rol por UI). Sin la clave = solo la capa propia. |
| `tablas` | `forja/bash/fleet/crear_alta.sh` (al crear el rol LOGIN de Postgres del copiloto) | `"*"` = miembro de `ikigai_tier_total` (SELECT sobre **todas** las tablas del schema, incluido el tier sensible de `slices.md` §4 — migración `007_tier_total.sql`); lista = `ikigai_tier_<nombre>` por ítem (hoy existe `compensacion`, migración 004); sin la clave = solo `ikigai_copiloto_base` (toda la org menos el tier sensible, 003 §2b). Cambiar el valor de un rol **no** mueve a los copilotos ya dados de alta: la membresía se ajusta con `GRANT/REVOKE ikigai_tier_… TO/FROM ikigai_<empleado>` (lo hace el operador; ver la migración). |
| `dominios` | `bash/lib/acceso.sh` (`require_acceso <dominio>`) | `"*"` = todos los `bash/` cercados por rol (`bash/ghl/`, `bash/vturb/` — credencial de proveedor — y `bash/users/` — cuentas de Marketico); lista = solo esos; sin la clave = negado con `exit 3` y un mensaje que dice a dónde ir (el espejo `bash/crm/` para GHL; el proxy Mkt, pendiente, para VTurb; el cerebro/skill `crear-usuario` para users). |

Hoy: **`technology` = `{uis:*, dominios:*, tablas:*}`** (el rol todo-poderoso —
Parallelo) y **`ejecutivo` = `{dominios:*, tablas:*}`** (mira el embudo completo
con el VSL en vivo y, desde 2026-08-21, **todas las tablas de Postgres** — decisión
de Santiago: «por ahora Ejecutivo y Technology tienen acceso a todas las tablas,
pero solamente esos roles»). Las tres claves tienen que decir lo mismo para un
rol: hasta la 007, `dominios:*` dejaba pasar `bash/vturb` y Postgres negaba
`project_vturb_video_configs` al mismo copiloto.
Regla de reparto con el canal: **`EXCLUIR` (forja) es para lo que no debe
existir en un laptop** (`bash/ops/`, `bash/whatsapp_evo_api/`, `catalog/`,
`apis/`…); todo lo demás viaja y lo decide `acceso.json`.
Sin `copilot.json` = cerebro = todo, sin consultar el mapa. Un `copilot.json`
sin `role` legible, o un mapa ausente, **no hereda nada** (fail-closed en los
tres consumidores). **Editar el mapa es decisión de gobernanza** y se registra
en el spec. La cerca es un riel, no un muro (un fork con `DATABASE_URL` puede
leer el token); el muro es mover las credenciales detrás del backend.

## Hallazgos transversales

- **Media Buyer no existe** — S3 (pauta) no tiene dueño formal; hoy lo absorben Ejecutivo y Estratega. Brecha #1 del discovery, sigue vigente.
- **Setter ≡ Líder de servicio** en los datos: tareas de chat/ManyChat con texto idéntico bajo ambos; Setter tiene 0 tareas etiquetadas a su nombre. Falta desambiguar propiedad.
- **Triplicación por proyecto**: Andrea Torres / David Guerrero / Ikigai llevan copias casi idénticas del mismo proceso — el trabajo distinto real es ~⅓ del conteo bruto.
- **El cuello de botella recurrente** (PM/Contenido/Editor): grabación del talento + entrega del editor. La mayor parte del trabajo del PM es perseguir ese hand-off.
- **Asignaciones anómalas**: el rol `Cliente` acumula 27 tareas (David Guerrero asignado como ejecutor) y `Closer` 1 — ambas señales de higiene de datos, no de roles reales.
- **Roles sin doc aquí**: Closer (política: sin copiloto; su trabajo vive en `bash/calls/` y lo gobierna el Director Comercial), Cliente y Admin (no son roles operativos del equipo).

## Regenerar

Los números salen de esta consulta (read-only) — re-córrela y regenera al ritmo que el etiquetado crezca:

```sql
SELECT tr.name AS rol, mp.code AS macro, s.code AS sop, a.id AS arquetipo,
       count(DISTINCT t.id) AS tareas
FROM ikigaigm.tasks t
JOIN LATERAL unnest(t.assignee) AS asg(mid) ON true
JOIN ikigaigm.team_members tm ON tm.id = asg.mid
LEFT JOIN ikigaigm.team_roles tr ON tr.id = tm.role_id
JOIN ikigaigm.activity_archetypes a ON a.id = t.archetype_id
JOIN ikigaigm.sops s ON s.code = a.sop_code
JOIN ikigaigm.macro_processes mp ON mp.code = s.macro_process_code
GROUP BY 1,2,3,4 ORDER BY 1,2,3, tareas DESC;
```

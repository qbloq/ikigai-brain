# Roles de Ikigai — SOPs, arquetipos y tareas

> Un documento por rol, derivado de la ontología de procesos
> (`cadena de valor → macro (S1…S12) → SOP → arquetipo → tarea`,
> [catalog/sop-archetypes.json](../../catalog/sop-archetypes.json)) cruzada con las **tareas reales**
> etiquetadas (`tasks.archetype_id` → asignados → `team_roles`). Lo
> cuantitativo viene de la DB; lo cualitativo (misión, candidatos,
> brechas) del [discovery original](../role-sops-discovery.md).
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

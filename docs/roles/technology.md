# Rol: Technology

**Quiénes:** Pablo Gaviria (copiloto `pablo-gaviria`) — único Technology en el roster (confirmado contra la DB 2026-08-21; Angélica Ospina y Juan Sebastián Martínez ya no hacen parte del equipo — sus forks siguen en la flota con `role: technology`, sin acceso git, pendientes de baja)
**Capa de rol (viz):** [viz/specs/roles/technology/](../../viz/specs/roles/technology/)
**Nivel de acceso:** **todo-poderoso** — `acceso.json`: `{uis:*, dominios:*}` (decisión 2026-08-21). Su viz carga las capas de UI de **todos** los roles (con badge de rol por UI) y todo `bash/` cercado por rol le responde (`bash/ghl/`, `bash/vturb/`, `bash/users/`…). Es el rol de Parallelo: quien construye y audita el sistema tiene que poder verlo entero.
**Tareas históricas:** 20 asignadas · 19 etiquetadas con arquetipo · 2 abiertas hoy

**Misión.** La fuente de verdad técnica: consolidación de métricas y alineación de fuentes (Paralelo, S8), plataforma VSL (Biturbo↔GHL, S7), tracking de origen de ventas, pagos y comisiones (Stripe), y herramientas de IA/reporting.

## Dónde vive en la cadena de valor

| Macro-proceso | Tareas |
|---|---|
| S7 · Funnel / Landing / Checkout | 12 |
| S10 · Gobernanza de Tareas | 2 |
| S6 · Calificación de Leads & Setter Ops | 2 |
| S9 · Lanzamiento / Masterclass | 2 |
| S1 · Narrativa & Oferta | 1 |

## SOPs → Arquetipos → Tareas (empírico)

### S7 · Funnel / Landing / Checkout

| SOP | Arquetipo | Tareas | Abiertas | Ejemplo real |
|---|---|---|---|---|
| S7.1 Build de landing & páginas | **A7.1** Crear/duplicar landing page | 4 | 0 | DG- Montar página de preparación 5 "mini videos" que irán desde la … |
| S7.1 Build de landing & páginas | **A7.6** Editar/optimizar página del funnel (survey, agenda, velocidad de carga) | 4 | 0 | DG- Llenar página de links de interés |
| S7.3 VSL A/B & plataforma (Biturbo ↔ GHL) | **A7.3** Configurar VSL A/B (Biturbo) | 3 | 0 | DG- Cambiar Página del VSL y probar 3 a 4 promesas para VSL para te… |
| S7.4 Funnel gamificado & lead magnets | **A7.7** Crear/editar lead magnet (guía, video, quiz) | 1 | 0 | DG-Link quiz (lead magnet) |

### S10 · Gobernanza de Tareas

| SOP | Arquetipo | Tareas | Abiertas | Ejemplo real |
|---|---|---|---|---|
| S10.1 Gobernanza de tareas & seguimiento de reuniones | **A10.5** Coordinar/agendar reunión (agenda, asistentes, grabación) | 2 | 1 | DG-Programar una reunión para definir el rol y la estrategia para e… |

### S6 · Calificación de Leads & Setter Ops

| SOP | Arquetipo | Tareas | Abiertas | Ejemplo real |
|---|---|---|---|---|
| S6.1 Automatización ManyChat & tagging (audios CTO) | **A6.1** Implementar/configurar ManyChat | 2 | 1 | DG-Automatizar whatsapp |

### S9 · Lanzamiento / Masterclass

| SOP | Arquetipo | Tareas | Abiertas | Ejemplo real |
|---|---|---|---|---|
| S9.3 Secuencias de mensajería de lanzamiento (email/WhatsApp/Telegram) | **A9.5** Programar/automatizar secuencia de mensajería | 1 | 0 | DG-Montar automatización estrategia de E-mail nutrición para audien… |
| S9.3 Secuencias de mensajería de lanzamiento (email/WhatsApp/Telegram) | **A9.7** Configurar canal/infraestructura de mensajería | 1 | 0 | DG-Comprar simcard para estrategias con API para David |

### S1 · Narrativa & Oferta

| SOP | Arquetipo | Tareas | Abiertas | Ejemplo real |
|---|---|---|---|---|
| S1.1 Construcción de narrativa & oferta | **A1.1** Reformular narrativa / big idea / mecanismo único | 1 | 0 | DG-Crear el brief para el programa de Parejas de Andrea y David. Or… |

## Procesos candidatos del discovery (sin evidencia en tareas etiquetadas aún)

- Desarrollo de features de Paralelo (task-management) — roadmap
- AI Reporting & Knowledge Tools (Ask the Graph / skills) *(S8)*

## Notas y brechas

- Parte del trabajo Dev/Product que hoy cae aquí está en la brecha «Dev/Producto» del discovery: mucho quedó sin dueño en la pila sin asignar.

---
*Generado 2026-07-12 de la ontología (`catalog/sop-archetypes.json`) × las tareas reales (`tasks.archetype_id`, 19/20 etiquetadas). Cualitativo del `discovery original`. Regenerable con la consulta del [README](README.md).*

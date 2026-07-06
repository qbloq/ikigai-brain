# DG · Premium Mastermind — Clasificación a la ontología de procesos

> Piloto Fase B + extensión de catálogo + Fase C. 294 tareas de [tasks.json](tasks.json) → arquetipos de `catalog/sop-archetypes.json`. Datos: [classified.json](classified.json).
> **Loop:** clasificar (LLM) → detectar gaps → extender catálogo → re-clasificar, iterado 3 veces. Se crearon 3 SOPs y 8 arquetipos nuevos; cobertura **71%→98%**.

## Resumen

- **288/294 (98%) mapeadas** · **6 sin arquetipo** (de ellas 2 son títulos vacíos → 4 gaps reales).
- Confianza: **130 altas** (≥0.8) · 78 medias · 80 bajas.
- Cobertura del catálogo: **56/76 arquetipos** ocurren; 20 nunca aparecen en Mastermind.

## Extensiones al catálogo (guiadas por esta data)

| Nuevo | Tipo | Cierra |
|---|---|---|
| **S9.3** Secuencias de mensajería (A9.4–A9.7) | SOP + 4 arquetipos | 50 tareas de email/WhatsApp/Telegram/grupos |
| **S2.3** Diseño gráfico y piezas estáticas (A2.8–A2.9) | SOP + 2 arquetipos | 8 piezas gráficas/presentaciones |
| **S7.4** Funnel gamificado & lead magnets (A7.7–A7.8) | SOP + 2 arquetipos | quiz/lead-magnets |
| **A10.5** Coordinar/agendar reunión | arquetipo (S10.1) | 6 reuniones internas |

## Contratos-plantilla autorizados (Fase C)

`A2.5` Editar anuncios · `A2.4` Grabar · `A2.2` Copy — más los de los SOPs nuevos (S9.3, S2.3, S7.4, A10.5). Todos instanciables por `create_task.sh` (archetype + slots).

## Cobertura por macro-proceso
| Macro | Tareas | % |
|---|--:|--:|
| S2 Producción de Creativos | 134 | 47% |
| S9 Lanzamiento/Masterclass | 58 | 20% |
| S7 Funnel/Landing/Checkout | 24 | 8% |
| S6 Leads & Setter Ops | 12 | 4% |
| S10 Gobernanza de Tareas | 11 | 4% |
| S3 Optimización de Pauta | 9 | 3% |
| S1 Narrativa & Oferta | 9 | 3% |
| S5 Testimonios | 9 | 3% |
| S8 Métricas | 7 | 2% |
| S11 Producto/Plataforma | 6 | 2% |
| S4 Contenido Orgánico | 6 | 2% |
| S12 Cierre & Retención | 3 | 1% |

## Top arquetipos (lo que Mastermind realmente hace)
| Arquetipo | Tareas | Actividad |
|---|--:|---|
| A2.5 | 84 | Editar audio/video de anuncios |
| A9.4 | 21 | Escribir copy/flujo de secuencia de mensajería |
| A9.5 | 15 | Programar/automatizar secuencia de mensajería |
| A2.2 | 15 | Escribir copy de un lote de anuncios |
| A2.4 | 15 | Grabar reels/videos de anuncio con talento |
| A9.6 | 10 | Gestionar ciclo de grupos/comunidades de lanzamiento |
| A6.1 | 8 | Implementar/configurar ManyChat |
| A2.8 | 6 | Diseñar pieza gráfica / estático |
| A7.1 | 6 | Crear/duplicar landing page |
| A9.2 | 6 | Mapear masterclass (correos, mensajes, cronograma) |
| A10.5 | 6 | Coordinar/agendar reunión (agenda, asistentes, grabación) |
| A7.6 | 6 | Editar/optimizar página del funnel (survey, agenda, velocidad de carga) |
| A7.3 | 5 | Configurar VSL A/B (Biturbo) |
| A10.2 | 5 | Seguimiento/chase de entregable |

## Arquetipos nunca usados

20/76: `A1.4`, `A3.5`, `A4.3`, `A4.5`, `A4.6`, `A5.4`, `A6.2`, `A6.6`, `A7.2`, `A7.5`, `A8.6`, `A9.3`, `A10.1`, `A10.3`, `A10.4`, `A11.4`, `A12.1`, `A12.3`, `A12.4`, `A12.7`. Esperable — Mastermind es producción-céntrico (faltan closers/S12, gobernanza/S10, enforcement orgánico).

## Gaps restantes (6)

- (OT)- 
- DG- Enviar contenido orgánico de 'trading' para que David (Gerente de Tráfico) lo utilic
- IGM-Buscar plataforma para comunicación de los setters (varios setters) 
- DG-Durante la captación en el desarrollo de clases clases de Elite en Bolsa, hacer invit
- DG-Crear prueba en CloudFare
- DG-

Son one-offs marginales (2 títulos vacíos, plataforma de setters, prueba Cloudflare, handoff de orgánico, invitación en clases en vivo) — no forman clúster que justifique un SOP nuevo.

## Estado

- ✅ **Fase B** — 294 tareas clasificadas, 98% cobertura.
- ✅ **Extensión de catálogo** — 3 SOPs + 8 arquetipos nuevos, guiados por gaps reales; el catálogo pasó de 65→76 arquetipos.
- ✅ **Fase C** — contratos-plantilla de los arquetipos dominantes (A2.5, A2.4, A2.2) + los nuevos, instanciables end-to-end.
- ⏭️ **Siguiente natural:** escalar a otro proyecto (Academy/Origen del amor) reusando el catálogo ya validado, o computar embeddings para el matcher automático (rule→embedding→LLM).
# DG – Premium Mastermind · Análisis de la planificación

> Fuente: Notion, base maestra **"BD Avances"** (data source `d3944694-…`), filtrada
> por la relación `Proyectos brief` → página *DG- Premium Mastermind*
> (`27ad5db4-6a6c-80f5-90b4-f8223647360f`). Extraído con
> [`bash/notion/project_tasks.sh`](../../../bash/notion/project_tasks.sh).
> Datos crudos: [`tasks.json`](tasks.json) · [`tasks.csv`](tasks.csv).
> Corte: 2026-07-01 · **294 tareas**.

## 1. Qué es el proyecto

Programa **Premium Mastermind** de **David Guerrero** (cliente externo, trading /
mentoría — hay referencias a MetaTrader, VSL, masterclass). Ikigai opera todo el
marketing: contenido orgánico, tráfico pago, embudos (VSL, masterclass, evergreen),
edición de video y páginas. El proyecto es maduro: **87 % de las tareas ya están
en "Done"** — esto es en gran parte un histórico de ejecución, no un backlog por hacer.

## 2. Estado y salud

| Estado | Tareas | % |
|--------|-------:|--:|
| Done | 256 | 87 % |
| On Time (abierta, en plazo) | 31 | 10 % |
| In Progress | 5 | 2 % |
| Archivo | 2 | 1 % |

- **Abiertas hoy: ~36** (On Time + In Progress).
- **Vencidas: 30** — tareas con `Fecha` anterior al 2026-07-01 que no están en
  Done/Archivo. Es el foco operativo real: casi todo lo abierto ya pasó de fecha.
- **Prioridad**: 97 % "Importante", solo 8 "Urgente" → el campo de prioridad casi
  no discrimina; no sirve como señal de triaje.

## 3. Actividades — ¿de qué trata el trabajo?

**Por fase de lanzamiento/evergreen** (campo mejor diligenciado, 79 % con valor):

| Fase | Tareas | % |
|------|-------:|--:|
| 3. Ejecución/operativa | 155 | 52 % |
| (vacío) | 63 | 21 % |
| 2. Concepción/bases | 38 | 13 % |
| Contenido | 14 | 5 % |
| 7. Ventas | 14 | 5 % |
| 4. CPL y ofertas | 6 | 2 % |
| Post-venta | 5 | 2 % |
| 1. Prelanzamiento | 3 | 1 % |

→ El grueso es **ejecución operativa** (producir, editar, publicar), no estrategia.

**Por tipo de embudo (`Nº Lanzamiento`):**

| Embudo | Tareas | % |
|--------|-------:|--:|
| Evergreen | 189 | 64 % |
| Masterclass | 65 | 22 % |
| (vacío) | 36 | 12 % |
| Lanzamiento 2 | 4 | 1 % |

→ El motor del proyecto es el **evergreen**; la **masterclass** es el segundo
frente grande. Lanzamientos puntuales, casi nada.

**Por etapa de funnel** (poco diligenciado — 72 % vacío): de lo etiquetado,
domina **"5. Estrategia orgánica" (70 tareas)** — coherente con un proyecto muy
centrado en contenido orgánico.

Un patrón visible en los títulos: decenas de tareas **"Edición R1…R30"** →
producción de video en serie (rondas de edición) es una línea de trabajo central.

## 4. Roles — quién hace qué

BD Avances guarda **personas**, no roles; se cruzaron con `bash/tasks/team.sh`.
Conteo por **responsable asignado** (una tarea puede tener varios):

| Persona | Rol (team.sh) | Tareas asignadas |
|---------|---------------|-----------------:|
| Marisol Ochoa | **Project Manager** | 93 |
| Jhonatan Rengifo | Copy | 70 |
| Juan Camilo Correa | Ejecutivo | 47 |
| Antonio Mario Espitia | *(externo, edición)* | 40 |
| Tony Vidal | Editor | 37 |
| Roberto Maestre | Operaciones | 30 |
| Santiago Ruiz | Contenido | 29 |
| David Guerrero | **Cliente** | 26 |
| Lorenzo Cadavid | Ejecutivo | 21 |
| Duotono Publicidad | *(externo, diseño)* | 19 |
| Juan Sebastián Martínez | Technology | 15 |
| Luis David Flórez | Director Comercial / Closer | 14 |
| David Castaño | Estratega | 14 |
| Andrés Alzate | Copy | 9 |
| Francisco Otálvaro | Líder de servicio | 5 |

**Lectura de roles:**
- **Marisol Ochoa (PM)** es el centro de gravedad: 93 tareas asignadas y **133 como
  destinataria de entregas** ("A quién entrega") → funciona como el nodo de
  coordinación/QA por el que pasa casi todo.
- **Producción de contenido/video** pesa muchísimo: Jhonatan (copy), Antonio Espitia,
  Tony Vidal (editores), Santiago Ruiz (contenido), Duotono (diseño externo).
- **David Guerrero** aparece con 26 tareas: el cliente participa activamente
  (grabaciones, aprobaciones, accesos).
- **Ventas/tráfico** (closers, estratega) tienen menos volumen de tareas registradas
  aquí → este tablero es sobre todo **marketing/producción**, no el pipeline comercial.
- Ojo dato: los campos `Área`, `Categoría` y `Tipo proceso` están **casi 100 %
  vacíos** — no se pueden usar para segmentar; la señal fiable de "quién" es el
  asignado, y la de "qué" son `Fases` y `Nº Lanzamiento`.

## 5. Tiempos — evolución del proyecto

Tareas por mes (campo `Fecha`):

```
2025-10  ██████████████             27
2025-11  █                           3
2025-12  ████████████               23
2026-01  ████████████████████       41
2026-02  ████████████               25
2026-03  ███████████████████████    47
2026-04  ████████████████████████████████ 64   ← pico
2026-05  █████████                  19
2026-06  ████████████████           33
2026-07  ▏                           1
sin fecha                           11
```

- Arranque **oct 2025**, aceleración fuerte **ene–abr 2026**, **pico en abril (64)**
  — probablemente un ciclo de lanzamiento/masterclass.
- Repunte en **junio (33)** con **30 vencidas** → hay una cola de trabajo reciente
  que se atrasó y sigue abierta.

## 6. Conclusiones y siguientes pasos sugeridos

1. **Foco inmediato = 30 tareas vencidas** (abiertas con fecha pasada). Es el
   backlog real; el resto es histórico Done.
2. **Higiene de datos en Notion**: `Área`, `Categoría`, `Prioridad` y `Tipo proceso`
   no se usan de forma consistente → o se depuran o no sirven para reporting.
   Lo fiable hoy: `Estado`, `Fases`, `Nº Lanzamiento`, `Asignado`, `Fecha`.
3. **Carga sobre la PM (Marisol)**: es cuello de botella de coordinación (133
   entregas dirigidas a ella). Vale la pena revisar si esa centralización escala.
4. **Mapear estas tareas al catálogo de SOPs/archetypes** del repo (S1–S12) para
   convertir el histórico en plantillas reutilizables — especialmente el patrón
   repetitivo "Edición R#" (producción de video en serie) y el evergreen.

---
*Reproducir:* `bash bash/notion/project_tasks.sh <page-id> --format json|csv` ·
agregados en `scratchpad/analyze.py` (ad-hoc).

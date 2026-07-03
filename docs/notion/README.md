# Corpus Notion — BD Avances

Snapshots locales (read-only) de la base maestra de tareas **BD Avances** de
Notion, extraídos con [`bash/notion/project_tasks.sh`](../../bash/notion/project_tasks.sh).
Son **congelados** (para análisis); la UI del viz lee Notion en vivo.

## Contenido

| Ruta | Qué es | Filas |
|------|--------|------:|
| [`_corpus/bd-avances-all.json`](_corpus/bd-avances-all.json) | **Todo** BD Avances, org-wide (todos los clientes). Cada fila trae `proyecto_ids`. | 3300 |
| [`david-guerrero-premium-mastermind/`](david-guerrero-premium-mastermind/) | Proyecto DG Mastermind (+ [ANALISIS.md](david-guerrero-premium-mastermind/ANALISIS.md)) | 294 |
| [`origen-del-amor/`](origen-del-amor/) | Proyecto DG/AT Origen del amor | 75 |
| [`david-guerrero-premium-academy/`](david-guerrero-premium-academy/) | Proyecto DG Academy | 3 |

## Hallazgos de estructura (importantes para el análisis)

- **La relación `Proyectos brief` está poco poblada**: de 3300 filas, solo **372**
  (11 %) apuntan a una página de proyecto — los 3 programas DG. Las otras **2928
  no tienen proyecto** por esa relación.
- **El prefijo del título es el tag de cliente de facto** cuando falta la relación.
  Distribución de las 2928 sin proyecto:

  | Prefijo | Filas | Prefijo | Filas |
  |---|--:|---|--:|
  | (sin prefijo) | 765 | GA | 173 |
  | DG (David Guerrero) | 558 | EL | 91 |
  | MG | 331 | ME | 46 |
  | AT (Andrea Torres) | 262 | IAD | 26 |
  | IGM (Ikigai interno) | 231 | LC | 15 |
  | S | 225 | QCG | 13 |
  | EF | 183 | JCCW | 5 |

  → DG real ≈ **852 tareas** (294 tagged + 558 por prefijo). Hay varios clientes
  más (MG, AT, EF, GA, EL…) recuperables por prefijo.
- Para atribuir org-wide a cliente: **usar `proyecto_ids` y, en su defecto, el
  prefijo del título** (fallback).

## Regenerar

```bash
bash bash/notion/project_tasks.sh <project-page-id|url> --format json --out <dir>/tasks.json
bash bash/notion/project_tasks.sh --all               --format json --out docs/notion/_corpus/bd-avances-all.json
```

Páginas de proyecto conocidas (compartidas con la integración): Mastermind
`27ad5db4-6a6c-80f5-90b4-f8223647360f` · Academy `27ad5db4-6a6c-80a0-8749-cb05a9bbdd7c`
· Origen del amor `2efd5db4-6a6c-801d-90ba-c4df80b4632a`. Las páginas de otros
clientes NO están compartidas, por eso sus filas quedan como "sin proyecto".

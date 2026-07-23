# bash/notion — extracción read-only desde Notion

Trae contenido de Notion a local vía la API HTTP (curl / `python3` stdlib, **sin
deps npm**). **Read-only**: solo GET de páginas/bloques y POST de *query* (que es
una lectura); nunca crea, edita ni borra en Notion. El token vive en `.env` como
`NOTION=ntn_…` (la integración interna, hoy **"Parallelo 2"**).

Salida: JSON/Markdown a stdout, o a `docs/` cuando se destila.

## Scripts

| Script | Para qué |
|--------|----------|
| `fetch_page.sh <id\|url> [--out F] [--blocks\|--raw\|--db\|--search]` | Destila una página a Markdown (props + árbol de bloques recursivo, bases inline como tablas). `--search` lista todo lo accesible (páginas/databases/data_sources). |
| `project_tasks.sh <project-page-id\|url> [--format json\|csv\|md] [--out F]` | Extrae **todas las tareas de BD Avances** cuya relación `Proyectos brief` apunta a esa página de proyecto. |

Motores en [`lib/`](lib/): `common.sh` (token, `notion_api()`, `to_uuid()`),
`notion.py` (render de páginas/bloques/tablas + `search`), `project_tasks.py`.

## Modelo de datos relevante (descubierto)

- El bot solo ve lo **explícitamente compartido** con la integración (menú `•••`
  → Connections). Hoy: las 3 páginas de <proyecto> + la data source **"BD
  Avances"** + **"BD contabilidad T4trade"**.
- El workspace usa el **modelo nuevo de data sources** (API `2025-09-03`): una
  *database* puede tener 1+ *data sources*; las **vistas enlazadas** (linked views,
  como las tablas inline "▶Tareas"/"📋Material lanzamientos" de cada proyecto)
  reportan `data_sources: []` porque su origen es otra base → **no se leen por la
  vista**, hay que consultar la base origen directamente.
- **BD Avances** (`d3944694-6f39-4903-a7b8-5dccf9b4c1d0`) es la base maestra de
  tareas/avances de **todos** los clientes. Cada fila se asocia a un proyecto por
  la relación **`Proyectos brief`** → página del proyecto. Ese es el discriminante
  que usa `project_tasks.sh` (la API de Notion **no** expone el filtro de la vista
  inline, así que se replica por relación).
- Páginas de proyecto <proyecto>: Premium Mastermind
  `27ad5db4-6a6c-80f5-90b4-f8223647360f` · Premium Academy
  `27ad5db4-6a6c-80a0-8749-cb05a9bbdd7c` · Origen del amor
  `2efd5db4-6a6c-801d-90ba-c4df80b4632a`.

## Uso típico

```bash
bash bash/notion/fetch_page.sh --search                          # ¿qué veo?
bash bash/notion/fetch_page.sh <page-url> --out docs/x/page.md    # página → md
bash bash/notion/project_tasks.sh <project-page> --format csv --out docs/x/tasks.csv
```

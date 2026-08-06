# Bindings de artefacto: de la tarea al archivo real (Notion → Drive)

> Nace del sync del 2026-07-26
> ([docs/notion/_sync/2026-07-26/](notion/_sync/2026-07-26/README.md)), donde
> 47 tareas entraron con contrato IO tipado pero **sin un solo artefacto
> enganchado**.
>
> **Estado: etapas 1-3 IMPLEMENTADAS (2026-07-26).** 237 bindings vivos (110
> inputs + 127 outputs), todos con nombre resuelto; 109 tareas con la cadena
> completa crudo→editado. La etapa 4 (verificación automática) sigue pendiente.

## 1. El problema

Una tarea con contrato IO declara *qué* necesita y *qué* produce, pero hoy no
sabe *dónde está*. El input «Material crudo a editar» es un título; no apunta a
nada.

Y el dato existe. Las filas de BD Avances traen dos propiedades de tipo `files`
con URLs **externas y permanentes** de Google Drive:

```
❌Drive Crudo   → https://drive.google.com/drive/folders/1ATiMTNYOHpVV3Yap-CRL3aHesFXt5CSs
✅Drive Editado → https://drive.google.com/drive/folders/1QM-D_eSpXXQ3oJd2DmOgdnr8-x6wJ_lz
```

Las tiramos a la basura en la extracción:

```python
if t == "files":
    return len(v) if v else 0      # bash/notion/lib/project_tasks.py:81
```

Por eso el corpus dice `drive_crudo: 1`. Ese `1` era una carpeta de Drive.

**Y las dos carpetas son literalmente el input y el output que declara `A2.5`**
(«Video/audio en bruto (Drive Crudo)» → «Anuncio(s) editado(s) … (Drive
Editado)»). El contrato ya estaba modelado; solo falta enchufarlo.

### El hallazgo que sube la apuesta

Probando contra el backend con [bash/google/](../bash/google/):

```
$ drive_file.sh 1QM-D_eSpXXQ3oJd2DmOgdnr8-x6wJ_lz
name  R21      mime  application/vnd.google-apps.folder

$ drive_ls.sh --folder 1ATiMTNYOHpVV3Yap-CRL3aHesFXt5CSs     # crudo
  1IabHkOujT6Y92iN6QPLfyKJ0ELVk3DOo  David_Jul_R21.MP4  mp4

$ drive_ls.sh --folder 1QM-D_eSpXXQ3oJd2DmOgdnr8-x6wJ_lz     # editado
  (sin resultados)
```

El crudo está; el editado está vacío. La tarea está `pending` con entrega el
2026-08-01. **Drive ya sabe si el entregable existe** — o sea que un criterio de
aceptación puede verificarse solo, en vez de esperar a que un humano lo marque.
Ese es el premio real, no el enlace.

## 2. Lo que ya existe (no reinventar nada)

| Pieza | Estado |
|---|---|
| Columnas `artifact_reference` (input) / `deliverable_reference` (output), jsonb | ✅ existen |
| `update_task_io.sh --ref-merge '<json>'` — merge superficial en esa jsonb | ✅ existe |
| Artifact type **`drive_file` / «Google Drive File»** | ✅ existe en el catálogo |
| Chip de UI para `drive_file` (📁, label, href) en [viz/lib/artifacts.js](../viz/lib/artifacts.js) | ✅ existe |
| Convención de la jsonb: `{url, file_id, _resolved:{title,url}}` | ✅ ya usada por el binding `google_doc` vivo |
| Lectura de Drive sin credenciales locales ([bash/google/](../bash/google/)) | ✅ existe |

Hay **4 bindings poblados** en toda la DB (3 inputs + 1 output), puestos a mano.
El mecanismo funciona; lo que no existe es el camino automático desde el ingest.

## 3. Diseño — cuatro etapas

```
 (1) CAPTURAR        (2) TRANSPORTAR        (3) RESOLVER        (4) VERIFICAR
 Notion files   →    binding en la fila  →  _resolved cache  →  criterio auto
 pv() devuelve       IO correcta            vía bash/google/    (¿carpeta vacía?)
 URLs, no conteo
```

### (1) Capturar — extractor

En [bash/notion/lib/project_tasks.py](../bash/notion/lib/project_tasks.py), que
`pv()` devuelva la lista real:

```python
if t == "files":
    return [{"name": f.get("name"),
             "url": (f.get("external") or f.get("file") or {}).get("url")}
            for f in (v or [])]
```

⚠️ **Cambio de forma.** `drive_crudo` pasa de `int` a `list`. La truthiness se
conserva (`[]` es falsy, igual que `0`), pero el snapshot ya versionado
[`_corpus/bd-avances-all.json`](notion/_corpus/bd-avances-all.json) y el
[README del corpus](notion/README.md) documentan conteos. Regenerar el snapshot
en el mismo commit.

> Nota: los archivos son `external` (Drive), no `file` (alojados en Notion). Las
> URLs de Notion caducan (~1 h); estas no. Si algún día aparece un `file`
> interno, su URL **no** debe persistirse como binding — solo resolverse al
> vuelo.

### (2) Transportar — script nuevo `bash/ops/bind_io_notion.sh` **[WRITE]**

El binding no puede ocurrir en `ingest_notion.sh` (que no crea IO) ni en
`materialize_io.sh` (que no sabe de Notion). Es un **tercer paso**, después de
ambos:

```
ingest_notion.sh → materialize_io.sh → bind_io_notion.sh
```

Contrato:

```
bind_io_notion.sh <notion-rows.json> [--source notion] [--dry-run] [--yes]
```

- Recorre las filas de Notion que tengan `drive_crudo`/`drive_editado` no vacíos.
- Encuentra la tarea por `source_external_id` (la misma llave del dedup).
- Encuentra la **fila IO destino** por regla de matching (§4).
- Hace merge de `{url, file_id}` en la jsonb, y retipa el `artifact_type` a
  `drive_file` (`update_task_io.sh --artifact drive_file --ref-merge …`).
- **Idempotente**: si la jsonb ya trae ese `file_id`, no toca nada.
- Una transacción, before/after, `--dry-run` por defecto — el mismo patrón de
  policy que el resto de `bash/`.

Reusa `update_task_io.sh` en vez de escribir SQL propio: es el dueño declarado
de esa columna y el único write-path que el viz también usa.

### (3) Resolver — el cache `_resolved`

`artifacts.js` renderiza `_resolved.title` y cae a `file_id` si no está. Sin
resolver, el chip diría `1QM-D_eSpXXQ...`; con resolver dice **`R21`**.

Una pasada con `drive_file.sh <id> --json` por binding nuevo, y merge de:

```json
{"_resolved": {"title": "R21", "url": "https://drive.google.com/drive/folders/1QM-…"}}
```

Se hace **en el momento del bind**, no al render (así lo dice el comentario de
`artifacts.js`). Si el backend falla, el binding se persiste igual sin
`_resolved` — degrada al `file_id`, no rompe.

### (4) Verificar — el criterio que se comprueba solo

`task_acceptance_criteria.verification_method` ya admite `manual` / `attested` /
auto, y los `io_types` declaran un `resolver` (`gdrive`, `storage`, `sql`,
`computed`). La pieza que falta es un criterio tipo:

> «La carpeta de Drive Editado contiene al menos un archivo» → `drive_ls.sh
> --folder <id>` → `count > 0`

Hoy `Edición R21` fallaría ese criterio, correctamente: el editado está vacío.

**Esto es la mitad de un subsistema, no un detalle.** Va como fase 2 — requiere
decidir dónde corre la verificación (¿al abrir la tarea? ¿un cron?) y qué pasa
cuando el backend no responde. No lo metas en el mismo PR.

## 4. La regla de matching (la decisión de diseño de verdad)

`A2.5` tiene 2 inputs y 1 output. ¿Cuál recibe Drive Crudo?

| Opción | Cómo | Veredicto |
|---|---|---|
| **a. Por `io_type`** | crudo → el input con `io_type=video_asset`; editado → el output con `ad_creative` | ✅ **v1**. Semántico, sin datos nuevos, funciona hoy: `A2.5` = `video_asset` + `content_draft` → `ad_creative`, sin ambigüedad |
| b. Por posición | crudo → input[0] | ❌ frágil; el orden de la plantilla no es contrato |
| c. Declarado en la plantilla | `"binding_source": "drive_crudo"` en `archetype_inputs` | ✅ **destino**. Es lo correcto —la plantilla ya declara el contrato, que declare también de dónde se llena— pero exige migración y re-autoría de 58 plantillas |

**Propuesta: (a) ahora, (c) cuando se toque el catálogo de todas formas.** Y que
(a) sea explícito y falle ruidoso: si la regla matchea 0 filas o >1, se salta esa
tarea y la reporta, en vez de adivinar.

## 5. Resultado de la implementación (2026-07-26)

```bash
bash bash/ops/bind_io_notion.sh <notion-rows.json> [--dry-run] [--yes]
```

| | |
|---|---:|
| Pares (carpeta, lado) en el payload | 308 |
| Con tarea en la DB | 308 |
| **Enganchados** | **236** |
| Saltados por la regla (0 o >1 filas IO) | 72 |
| Carpetas resueltas contra Drive | 235/236 |
| **Bindings vivos totales** (incl. el lote previo) | **237** (110 in + 127 out) |
| Tareas con la cadena completa crudo→editado | **109** |

Los 72 saltos son correctos y esperados: son arquetipos sin fila de video
(`A2.2` copy, `A1.2` VSL, `A2.3` hooks, `A5.1`, `A2.7`). La regla falló ruidoso
y los reportó en vez de adivinar, que era el diseño.

**Nota de implementación:** el payload NO viaja como variable `-v` de psql —
unos cientos de bindings revientan `ARG_MAX` en el argv. Va dollar-quoted dentro
del SQL por stdin.

## 6. Riesgos vigentes

1. **La regla de matching vive solo donde hay filas de video.** Cubre `A4.7` y
   `A2.5`; el resto del catálogo no tiene campos de Drive en Notion. 236 de 308
   pares, no el 100 %.
2. **Las URLs se persisten.** Si alguien mueve o borra la carpeta en Drive, el
   binding queda colgado. `_resolved` es cache, no verdad; el `file_id` es la
   llave. Mismo trato que ya reciben los `google_doc`.
3. **Permisos.** Todo pasa por el backend mkt, que tiene la identidad de la org.
   Si una carpeta no está compartida con esa identidad, `drive_file.sh` falla y
   el binding persiste sin `_resolved` (el chip cae al `file_id`). Pasó en 1 de
   236. Degradación prevista, no error.
4. **Re-materializar destruye bindings.** Las filas IO son el soporte del
   binding: borrarlas y recrearlas (como se hizo con las 92 de `A4.7`) borra lo
   enganchado. **El binding va siempre de último**, y si se re-materializa hay
   que volver a correr `bind_io_notion.sh` — que es idempotente, así que basta.

## 7. Deuda que este plan NO resuelve

- El eslabón de **clasificación** sigue siendo un pase LLM a mano
  (ver [sync 2026-07-26 §deuda](notion/_sync/2026-07-26/README.md)).
- **El «pendiente» es sistémico**, no un problema de `A2.5`: 789 filas en 12
  arquetipos (`A9.4` 88, `A2.2` 60, `A2.4` 60, `A9.5` 60…) llevan slots que el
  backfill masivo no puede llenar. Un slot que varía por instancia solo lo llena
  `create_task.sh`; en un backfill set-based, por definición, no hay ese dato.
  **La lección de diseño: si el dato es por-instancia, es un binding, no un
  slot.** `A4.7` se autoró con un único slot (`{proyecto}`) justamente por eso.
- La **etapa 4** (criterios que se verifican solos contra Drive) sigue sin
  hacerse — es la mitad del valor y va aparte.

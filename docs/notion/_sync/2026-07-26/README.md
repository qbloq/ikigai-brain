# Sync Notion → tareas · 2026-07-26 (ventana mayo–julio 2026)

Segunda ingesta desde Notion, después del piloto Mastermind de julio
([CLASIFICACION.md](../../david-guerrero-premium-mastermind/CLASIFICACION.md)).
A diferencia de aquella —que partió de un snapshot congelado— esta corre contra
**BD Avances en vivo** y se acota por recencia.

## El corte y por qué

Contra Notion en vivo había **3.326 filas**, de las cuales 294 ya estaban
ingestadas. De las 3.032 restantes, **429 figuran abiertas** (`On Time` /
`In Progress`) — pero desglosadas por última edición:

| Última edición | Tareas | Lectura |
|---|---:|---|
| Últimos 2 meses | 42 | trabajo vivo |
| 2026, hace >2 meses | 35 | dudosas |
| Sin tocar desde 2025 | 163 | sedimento |
| Sin tocar desde 2024 | 189 | sedimento |

352 de las 429 llevan uno o dos años sin que nadie las toque: siguen en
`On Time` porque ese es el estado por defecto en Notion y nadie las cerró.
No son backlog. **La ventana acordada es mayo–julio 2026** (creada *o* editada
desde `2026-05-01`) → **48 filas**, de las que entraron 47.

> Las 352 abiertas-pero-muertas quedan como **cola de higiene de Notion**: no se
> ingestaron a propósito. Importarlas metería la deuda de Notion en el modelo.

## Qué entró

| Proyecto | Tareas | Ruteo |
|---|---:|---|
| David Guerrero | 27 | 26 «Edición R#» (relación de proyecto poblada = Mastermind) + 1 `DG-` |
| Andrea Torres | 20 | prefijo `AT-` |

Descartada: 1 (`IGM-`, título vacío).

**Ruteo a proyecto:** relación `Proyectos brief` cuando existe; si no, el prefijo
del título (el tag de cliente de facto — ver [../../README.md](../../README.md)).
En esta ventana ningún cliente sin proyecto en la DB (MG, GA, LC, EF…) aparece:
todos viven en la zona de sedimento.

**Nota sobre «Edición R#»:** el título se recicla en cada ronda de lanzamiento
(ya había 49 en la DB, casi todas `completed`). Estas 26 son la ronda siguiente
—creadas el 4 y el 24 de julio, con entregas del 26/jul al 6/ago—. El dedup por
`source_external_id` lo maneja bien; **cualquier dedup por título rompería**.

## Cobertura del contrato IO

44 de 47 quedaron con contrato IO completo. Las 3 sin IO, y por qué:

| Tarea | Arquetipo | Motivo |
|---|---|---|
| AT-Definir y configurar tags en ManyChat/GHL… | `A6.2` | arquetipo exacto, **sin contrato-plantilla** aún |
| AT-Investigar y solucionar la inconsistencia de chats… | `A6.6` | ídem |
| AT-Enviar los contenidos (reels) de Andrea… | — | **gap conocido**: handoff de contenido orgánico → pauta. Ya apareció en el piloto Mastermind y sigue sin arquetipo |

Los dos primeros se cierran autorizando la plantilla de `A6.2`/`A6.6` en
`catalog/sop-archetypes.json` + `sync_catalog.sh`. El tercero es candidato a
arquetipo nuevo si el clúster crece.

## Cómo se reproduce

```bash
bash bash/notion/project_tasks.sh --all --format json --out /tmp/bd-live.json
psql_ro -t -A -c "select source_external_id from ikigaigm.tasks \
  where source_external_id is not null" > /tmp/db-ids.txt

python3 build_window.py /tmp/bd-live.json /tmp/db-ids.txt .

bash bash/ops/ingest_notion.sh lote-dg.json --project "David Guerrero" --yes
bash bash/ops/materialize_io.sh --source notion --label "Premium Mastermind" --yes
bash bash/ops/ingest_notion.sh lote-at.json --project "Andrea Torres" --yes
bash bash/ops/materialize_io.sh --source notion --label "La Ciencia de la Abundancia" --yes
```

**El orden importa.** `materialize_io.sh` se acota por `source_type`, **no por
proyecto**: si se corre una sola vez, le pone el mismo `{proyecto}` a todos los
lotes. Como es idempotente (salta lo que ya tiene IO), la solución es
intercalar ingest→materialize por proyecto. Todo es dry-run por defecto; `--yes`
confirma.

## Alta de persona

`Antonio Mario Espitia España` (Editor, 15 tareas de esta ventana) no existía.
Creado con [crear-usuario](../../../../.claude/skills/crear-usuario/SKILL.md) →
`persons` + `users` vía el API de Marketico (`ae4ce5a0`), y la fila
`team_members` (`4c5da006`) **a mano por SQL** — la skill declara ese paso fuera
de alcance porque no hay script de escritura.

⚠️ Sin confirmar: «Antonio mario Espitia españa» y «Tony Vital» (→ `Tony Vidal`,
`e6fea6f1`) se reparten la misma serie R1–R26 y nunca coinciden en una tarea.
«Tony» es diminutivo de «Antonio». Los apellidos no coinciden, así que se
trataron como dos editores distintos — **verificar con el equipo**; si son la
misma persona, fusionar.

## Lo que siguió el mismo día

1. **Corrección de ontología.** Las «Edición R#» traen `etapa: "5. Estrategia
   orgánica"` (85/85) y se entregan al rol Contenido: son contenido orgánico, no
   creativos de pauta. Se creó **`A4.7` «Editar audio/video de contenido
   orgánico»** bajo S4.1 y se reclasificaron **92 tareas** desde `A2.5`
   (`method=human`); 18 se quedaron en `A2.5` — sus títulos dicen «anuncios»
   explícitamente y su `etapa` es de funnel, no orgánica. El rollup pasó de
   **S2 162 / S4 12** a **S4 104 / S2 70**.
2. **IO re-materializado** con la plantilla de `A4.7` (184 in + 92 out + 368
   criterios), sin un solo «pendiente»: el arquetipo se autoró con un único slot.
3. **Bindings de Drive** (ver [docs/io-bindings-drive.md](../../../io-bindings-drive.md)):
   237 vivos, 109 tareas con la cadena completa crudo→editado.

## Deuda que dejó este sync

1. **No hay script de clasificación.** El mapa título→arquetipo de
   `build_window.py` es un pase LLM escrito a mano, igual que en el piloto. Es
   el eslabón que impide que la sincronización sea un comando.
2. **No hay script de asignación.** El mapeo nombre-de-Notion → `team_members`
   vive en `mapa-asignados.json` y se aplica con un bucle de `reassign.sh`.
3. **No hay script para `team_members`.** Ver §6 de `crear-usuario`.
4. **Nombres sucios en Notion:** `Tony Vital`→`Tony Vidal`, `Sofi`→`Sofia`,
   `David Cast`→`David Castaño`, `Juan Camilo Correa W.`→`Juan Camilo Correa`.
   `luis david florez cardona` resuelve a **dos** filas de `team_members`
   (`81d4bc8e` Closer y `ece00919` Director Comercial); se usó `ece00919`.

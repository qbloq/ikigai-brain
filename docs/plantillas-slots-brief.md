# Plantillas y placeholders — brief para el rabbit-hole

**Estado:** diagnóstico cerrado, diseño abierto. Escrito 2026-08-11 a partir del
daño real que dejó el merge PM↔cerebro, que sirve de sonda: 17 tareas del
cerebro llevan hoy la palabra `«pendiente»` dentro de su contrato de trabajo, y
eso expone un hueco de diseño que estaba latente desde que existen las
plantillas.

**No hay que arreglarlo con prisa.** Las tareas afectadas son la muestra
gratuita: a medida que se revisen una por una (`/revisar-tarea-io`) se van a ir
encontrando los casos, y cada uno es evidencia de campo sobre cómo debería
funcionar la instanciación. Este documento existe para que ese día no haya que
re-descubrir nada.

---

## 1. Qué pasó, en concreto

`bash/tasks/merge_from_cruce.sh` duplica una tarea del cerebro tomando el título
de la plataforma PM y **re-instancia el contrato desde la plantilla del
arquetipo** (`--contrato plantilla`, el default). De 29 pares mezclados los días
10 y 11 de agosto de 2026:

| resultado | pares |
|---|---|
| el contrato original tenía sus slots **llenos** y quedó con `«pendiente»` | **16** |
| ya venía con `«pendiente»` de antes | 1 |
| salió limpio | 12 |

O sea: **el merge degradó 16 contratos que estaban bien**. Ejemplos, con lo que
decía la tarea original (hoy `cancelled`, no borrada — el dato es recuperable):

| tarea nueva | quedó | la original decía |
|---|---|---|
| `dfeada96` | Oferta empaquetada en `«pendiente»` | Oferta empaquetada en **oferta de rango medio cercana a 2.000** |
| `49d0c7f8` | Integración `«pendiente»`↔Parallelo | Integración **endpoints del cerebro** hacia la plataforma… |
| `9eab4247` | Integración `«pendiente»`↔Parallelo | Integración **plataforma de gestión de tareas de la Project Ma…** |
| `8c0919c0` | Tracking de `«pendiente»` implementado | **UTMs implementadas en todos los canales** + registro de origen |

⚠️ **Dónde cae el daño importa más que cuánto.** Las 28 ocurrencias se reparten
así: **23 en criterios de aceptación** (15 tareas), 4 en títulos de output, 1 en
un input. El placeholder se concentra justo en la mitad verificable del
contrato — un criterio como *«Cumple las restricciones y convenciones del
formato «pendiente»»* no es feo, es **inverificable**: no dice contra qué se
valida.

Arquetipos afectados (17 tareas, 12 arquetipos): A7.6 *Editar/optimizar página
del funnel* ×5 · A11.2 *Integrar sistema externo con Parallelo* ×2 · y uno cada
uno A11.3, A12.6, A12.7, A2.2, A2.3, A4.4, A5.3, A1.3, A8.5, A10.2.

## 2. El mecanismo — tres caminos que sustituyen distinto

Hay **tres implementaciones separadas** de la misma idea, y ninguna es la
autoridad:

| camino | qué hace con `{proyecto}` | qué hace con los demás slots |
|---|---|---|
| `bash/tasks/create_task.sh` (JS, `sub()`) | **nada especial** — si no pasás `proyecto` en `slots`, queda literal | deja el `{slot}` **literal** |
| `bash/ops/materialize_io.sh` (SQL, `pg_temp.slotclean`) | lo reemplaza por el nombre del proyecto | los neutraliza a `«pendiente»` |
| `bash/tasks/merge_from_cruce.sh` (SQL, `pg_temp.slotclean` **copiado**) | igual | igual |

La función `slotclean` está **duplicada byte a byte** entre los dos últimos.
Tres caminos, dos comportamientos incompatibles para un slot sin valor: literal
`{formato}` o `«pendiente»`. Ninguno de los tres puede llenar un slot a partir
de un contrato ya instanciado.

## 3. La causa raíz

**Los valores de los slots no existen como dato en ninguna parte.** Se hornean
en el texto en el momento de instanciar y ahí muere la información:

- `ikigaigm.tasks` **no tiene** ninguna columna de slots/params (verificado).
- No hay tabla `task_params` ni equivalente.
- El único registro de que la tarea `dfeada96` tenía `{formato}` = «oferta de
  rango medio cercana a 2.000» es la **cadena de texto** del output de la tarea
  original cancelada.

De ahí se siguen todas las consecuencias:

1. **No se puede re-instanciar sin perder.** Cualquier operación que regenere el
   contrato desde la plantilla (el merge, un futuro re-tag de arquetipo, una
   corrección de plantilla que quiera propagarse) borra los valores, porque no
   tiene de dónde leerlos. Esto es exactamente lo que pasó.
2. **No se puede consultar por dimensión.** «Todas las tareas de canal
   YouTube», «cuántas tareas de talento David» — imposible sin parsear texto.
3. **No se puede validar.** Nada impide instanciar con `{canal}` = cualquier
   cosa, ni detectar que quedó vacío.
4. **El re-tag ya está documentado como roto por esto mismo**: `set_archetype.sh`
   mueve el puntero pero **no reescribe el contrato**, así que una tarea
   re-etiquetada conserva criterios de otra actividad. Es el mismo hueco visto
   desde otro ángulo.

## 4. El socket ya existe, y está vacío

`ikigaigm.archetype_params` fue creada justamente para esto — tiene `key`,
`label`, **`type`**, **`enum_options[]`**, `required`, `position`. Estado real
hoy:

```
 type | count | con_enum | required
------+-------+----------+----------
 text |   120 |        0 |        0
```

**120 params, todos `text`, cero enums, cero required.** El enchufe está puesto
y sin conectar — igual que hace 35 días, cuando se anotó la memoria
`slots-as-org-dimensions`.

Esa memoria tiene la tesis que hay que retomar: los slots son **variables del
proceso y, por transitividad, de la organización** — el *eje dimensional* que
cruza el eje de proceso (macro→SOP→arquetipo). Y la clasificación ya pensada:

- **`ref`** → apuntan a catálogos que ya existen: `proyecto`→projects,
  `talento`/`responsable`/`aprobador`→persons, `herramienta`/`plataforma`→systems.
- **`enum`** → vocabularios controlados (`canal`, `etapa`, `formato`,
  `angulo`…), varios **ya enumerados en campos select de Notion** → baratos de
  cosechar.
- **medidas** (numéricas) → `cantidad`, `n_hooks`, `n_variaciones`: se capturan,
  no se catalogan.

## 5. Anatomía real del catálogo

De 79 arquetipos, **61 tienen contrato plantilla** y **60 usan `{slots}`** en él.

Slots por frecuencia: `{proyecto}` ×55 · `{cantidad}` ×6 · `{canal}` ×6 ·
`{talento}` ×5 · `{tema}` ×4 · `{periodo}` ×4 · `{destino}` ×3 · `{angulo}` ×2 ·
`{formato}` ×2 · `{base}` ×2 · `{entregable}` ×2 · `{etapa}` ×2 · y una cola
larga de uno.

⚠️ **Inconsistencia encontrada:** `{proyecto}` se usa en el contrato de 55
arquetipos pero solo está declarado en el array `slots` de 24 — **31 lo usan sin
declararlo**. Funciona por accidente: los dos caminos SQL lo tratan como caso
especial hardcodeado. Si algún día se valida «todo slot usado debe estar
declarado», esos 31 fallan. Y revela la pregunta de fondo: **¿`{proyecto}` es un
slot o es otra cosa?** Hoy es un híbrido — declarado a veces, hardcodeado
siempre.

## 6. Las preguntas del rabbit-hole

Ordenadas de más barata a más profunda. No hay que responderlas todas.

1. **¿Un solo sustituidor?** Hoy hay tres. Lo mínimo es una función compartida
   (SQL en `catalog/migrations/`, o un script en `bash/lib/`) que los tres
   consuman, con **un** comportamiento definido para el slot sin valor.
2. **¿Literal o neutralizado?** `{formato}` te dice qué falta; `«pendiente»` te
   dice que alguien decidió no llenarlo. La segunda pierde el nombre del slot, y
   ese nombre es la pregunta que hay que hacerle al humano. Sospecha fuerte:
   **el literal es mejor** — `«pendiente»` fue una decisión de cosmética que
   costó información.
3. **¿Se persisten los valores?** Un `task_params` (task_id, key, value,
   value_ref) haría el contrato re-instanciable sin pérdida, y abriría la
   consulta por dimensión. Es la respuesta de fondo a §3.
4. **¿Quién llena los slots?** Hoy nadie los pide: `create_task.sh` los acepta
   pero no los exige, y el pipeline de reuniones no los deriva. ¿Los infiere el
   LLM del texto de la tarea? ¿Los pregunta el skill? ¿Quedan como deuda visible
   en la UI?
5. **¿Cuándo se pobla el eje dimensional?** Promover primero los recurrentes con
   catálogo obvio (`proyecto`→ref, `talento`→ref, `canal`→enum) y dejar la cola
   larga en texto libre — «crecer desde la cola», el mismo criterio con que
   creció el catálogo de arquetipos.
6. **¿Y las plantillas sin inputs?** Hallazgo lateral de estos merges: A-de-SOPs
   (`8ada90bc`) y el arquetipo del PDF de ROAS (`d14c1c0b`) instanciaron con
   **0 inputs**. Sus plantillas declaran outputs y criterios pero ningún input,
   así que la tarea no dice qué necesita para arrancar. Es un defecto de la
   plantilla, no del merge, y afecta a toda instanciación futura del mismo
   arquetipo.

## 7. Reparación pendiente (independiente del rediseño)

Las 16 tareas degradadas **son recuperables sin decidir nada** de lo anterior:
el texto lleno vive en la tarea original `cancelled`. Dos formas:

- **Script de reparación** que copie el contrato de la original a la nueva,
  reutilizando la rama `SQL_COPIA` que `merge_from_cruce.sh` ya tiene. Una txn
  por par, `--dry-run`, auditable. Es la vía limpia si se van a arreglar todas.
- **A mano, a medida que aparezcan**, con `/revisar-tarea-io` — que es el plan
  elegido: cada caso se mira de cerca y alimenta las preguntas de §6.

Y **antes del próximo merge**: cambiar el default de `--contrato`, o mejor,
que el script detecte si la original traía slots llenos y solo entonces prefiera
`copia`. Con el default actual, cada merge nuevo suma otra degradación.

---

**Ver también:** memoria `slots-as-org-dimensions` (la tesis del eje
dimensional) · [docs/activity-archetypes.md](activity-archetypes.md) ·
[docs/role-sops-discovery.md](role-sops-discovery.md) ·
`catalog/sop-archetypes.json` (la fuente) ·
`catalog/migrations/001_process_ontology.sql` (el esquema, incluida
`archetype_params`).

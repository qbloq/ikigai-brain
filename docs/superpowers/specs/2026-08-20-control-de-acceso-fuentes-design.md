# Control de acceso a fuentes por rol (copilotos)

**Fecha**: 2026-08-20 · **Estado**: implementado 2026-08-21 (plan
`docs/superpowers/plans/2026-08-21-control-de-acceso-fuentes.md`) + **adenda
del mismo día** (abajo): el mapa salió a `docs/roles/acceso.json` y cubre
también las UIs del viz; `technology` = todo-poderoso. Preguntas abiertas:
1 resuelta (archivo, no código — ver adenda), 2 resuelta
(`director-comercial` sin `ghl`), 3-4 siguen abiertas

## Contexto y propósito

Hoy la casa tiene dos dominios de `bash/` que operan con **credenciales de
proveedor** leídas de la base (tokens en claro): `bash/ghl/`
(`project_crm_configs`) y `bash/vturb/` (`project_vturb_video_configs`). Ambos
traen el mismo guardián, copiado a mano: si existe `copilot.json` en la raíz,
el script se niega (`exit 3`) — «este dominio es solo del cerebro». La doctrina
detrás: el cerebro corre en una máquina que la org controla; los copilotos
están destinados a 19 laptops de empleados, y una llave maestra regada no se
puede auditar ni revocar por persona. El patrón correcto para copilotos es
`bash/google/`: el backend es dueño de la identidad y cada copiloto le habla
con SU `CEREBRO_TOKEN` (auditado, revocable).

Lo que lo hizo saltar (2026-08-20): la UI **Embudo · El cruce** (`embudo.sh` →
`bash/vturb/analitica.sh`) se llena en el cerebro pero en el copiloto de
Lorenzo (rol `ejecutivo`) muestra el bloque VSL con error declarado. La
cerca binaria trata igual al CEO que al editor de video.

**Decisión de Santiago**: el acceso a fuentes lo define **el rol**, no el
hecho de ser copiloto. El rol **Ejecutivo puede acceder a cualquier fuente de
datos del negocio**, incluidas las que llevan credencial de proveedor.

Dos honestidades que el diseño tiene que cargar, no esconder:

1. **La cerca es un riel, no un muro.** Un fork con `DATABASE_URL` podría
   leer el token con un `SELECT`. El guardián mantiene honesto el camino
   honesto (y evita que se construya algo NUEVO que dependa de la llave en un
   fork); el muro de verdad es mover las credenciales detrás del backend —
   estado final ya declarado en `bash/ghl/README.md`.
2. **La máquina no es el criterio.** Hoy «el copiloto de Lorenzo» corre en la
   máquina de Santiago; mañana en la de Lorenzo. La cerca decide por
   `copilot.json` (rol), no por dónde corre, para que no se olvide de cerrar
   el día de la mudanza.

## Qué NO hace esta fase (no-goals)

- No mueve credenciales al backend ni construye el fallback vía proxy Mkt
  (VTurb) para roles sin acceso. Eso es el paso siguiente, y la salvedad
  medida sigue vigente: el normalizador de retención de Marketico tiene el
  bug documentado en `bash/vturb/README.md` (plays/pitch/CTA bien,
  retenciones mal).
- No toca el control de acceso de **git** (forja `accesos/` + `bin/authz`,
  pre-receive): ese es otro plano (quién puede empujar a qué bare).
- No cifra los tokens en la base (el nombre de la columna miente; es un
  hallazgo conocido, no este spec).
- No decide el mapa completo de roles: solo fija `ejecutivo` = total y deja
  el resto como está (negado), con el socket listo para ampliar.

## Componentes

### 1. `bash/lib/acceso.sh` — la doctrina en UN lugar

Helper pequeño, independiente de `common.sh` (tiene que poder correr en un
fork sin `.env`), con una función:

```
require_acceso <dominio>   # dominio ∈ {ghl, vturb, …}
```

Comportamiento:
- Sin `copilot.json` → cerebro → acceso total, retorna 0 en silencio.
- Con `copilot.json` → lee `role`; consulta el mapa. Si el rol tiene el
  dominio → 0. Si no → mensaje de hoy (qué dominio, por qué, a dónde ir:
  espejo `bash/crm/` para ghl; proxy Mkt pendiente para vturb) y `exit 3`.
- `copilot.json` ilegible o sin `role` → se niega (fail-closed) con mensaje
  claro: un fork sin identidad no hereda permisos.

El mapa vive en el helper como tabla comentada (editar = decisión de
gobernanza, registrada en `gobernanza/`):

```
ejecutivo   : *            # acceso total a fuentes del negocio
# director-comercial : ghl   # candidato; no decidido
```

Regla de lectura: `*` = todos los dominios con credencial; lista = solo esos.

### 2. Las cercas existentes llaman al helper

`bash/ghl/lib/common.sh` y `bash/vturb/lib/common.sh` reemplazan su
`if [[ -f copilot.json ]]` por `require_acceso ghl|vturb`. Mismo mensaje,
misma salida 3, mismo comportamiento para todo rol distinto de `ejecutivo`.
Cualquier dominio futuro con credencial de proveedor **nace** llamando al
helper — la cerca deja de copiarse a mano.

### 3. La doctrina escrita donde viven los roles

- `docs/roles/README.md`: la regla general — «el acceso a fuentes con
  credencial de proveedor lo define el rol; el mapa vive en
  `bash/lib/acceso.sh`; ampliar el mapa es decisión de gobernanza».
- `docs/roles/ejecutivo.md`: «Nivel de acceso a fuentes: **total** — incluye
  dominios con credencial de proveedor (`bash/ghl/`, `bash/vturb/`)».
- `CLAUDE.md` (secciones GHL y VTurb): una línea cada una remitiendo al helper
  en vez de «se niega en forks».

### 4. Propagación

Como todo cambio de `bash/`: commit en el cerebro → `derivar_canal.sh` →
`actualizar_flota.sh` → el hook de SessionStart (o `/actualizarse`) lo trae
al laptop. Nada que desplegar en servidores.

## Manejo de errores (resumen)

- `copilot.json` roto / sin `role` → fail-closed + mensaje (no se inventa
  el rol).
- Rol desconocido (no en el mapa) → negado, mismo camino que hoy.
- El helper nunca toca red ni base: decide con el archivo local. Las
  credenciales siguen saliendo de la base en el dominio, por stdin, nunca argv.

## Testing

- Cerebro (sin `copilot.json`): `bash/vturb/auth_status.sh` y
  `bash/ghl/auth_status.sh` corren como hoy.
- Fork `ejecutivo` (clon de prueba con `copilot.json` `{role:"ejecutivo"}`):
  ambos corren; `bash/metrics/embudo.sh` llena el bloque `vsl` (no `error`).
- Fork de otro rol (p.ej. `editor`): ambos se niegan con exit 3 y el mensaje.
- Fork con `copilot.json` sin `role`: negado con el mensaje de identidad.
- Prueba real: copiloto de Lorenzo tras `/actualizarse` — UI embudo con VSL.

## Preguntas abiertas para la sesión

1. ¿El mapa se queda en código (tabla en `acceso.sh`) o sale a un archivo
   declarativo (`docs/roles/acceso.json`) que el helper lee? Código es más
   simple y viaja por el canal; archivo es más «gobernanza edita sin tocar
   bash». Inclinación: código, con la decisión registrada en `gobernanza/`.
2. ¿`director-comercial` recibe `ghl`? Hoy lee el espejo (`bash/crm/`) y le
   alcanza; la sonda directa es para medir el espejo. Probablemente no.
3. ¿Se registra el uso de credencial desde un fork (telemetría agregada, sin
   contenido — [[privacidad-telemetria-copilotos]])? Va de la mano del spec
   hermano `2026-08-19-seguridad-copiloto-claude-code-design.md`.
4. El paso siguiente real: credenciales detrás del backend + fallback proxy
   Mkt para los roles sin acceso (VTurb ya tiene endpoints de analytics;
   reportar el bug del normalizador antes de apoyarse en sus retenciones).

## Decisiones tomadas en la conversación

- El acceso a fuentes lo define el **rol**, no ser copiloto (Santiago,
  2026-08-20).
- `ejecutivo` = acceso total a fuentes del negocio, incluidas las de
  credencial de proveedor.
- La cerca se decide por `copilot.json`/rol, jamás por la máquina donde corre.
- Un solo helper para todas las cercas; las dos actuales migran a él; las
  futuras nacen con él.
- Se retoma en su propia sesión; este spec es el punto de partida.

## Adenda 2026-08-21 — un solo mapa para fuentes Y UIs; `technology` = todo

**Lo que la disparó.** Santiago: «el rol Technology —o sea nosotros— es el
usuario todo-poderoso; deberíamos poder ver todas las UIs de todos los roles…
la pregunta es si lo podemos hacer elegantemente». Hasta hoy el viz de un fork
cargaba ÚNICAMENTE la capa de su rol
(`viz/lib/store.js`: `roles.filter(r => r.name === COPILOT.role)`), y el mapa
de fuentes vivía como `case` dentro de `bash/lib/acceso.sh`. Dar a technology
las UIs con un `Set` en JS habría dejado **dos mapas de poder en dos
lenguajes**.

**Decisión (Santiago, 2026-08-21).** Un solo archivo declarativo,
**`docs/roles/acceso.json`**, con dos consumidores:

```json
{ "technology": { "uis": "*", "fuentes": "*" },
  "ejecutivo":  { "fuentes": "*" } }
```

- `bash/lib/acceso.sh` lee `fuentes` (el `case` se fue). Mapa ausente o
  ilegible → negado (fail-closed) — salvo el cerebro, que nunca consulta el
  mapa. Sigue sin red ni base, sigue portable a bash 3.2 (parse en python3,
  como `copilot.json`).
- `viz/lib/store.js` lee `uis` al boot: `"*"` → carga **todas** las capas de
  rol; si no, solo la propia. Función pura `rolesVisibles(copilot, acceso,
  roles)` (test `viz/test/acceso.test.js`). **Cambio de comportamiento
  alineado**: un `copilot.json` sin `role` ya no ve todo por accidente — ve
  cero capas de rol (antes, sin filtro = veía todas), la misma regla que el
  helper: *un fork sin identidad no hereda permisos*.
- «Todo-poderoso» incluye **las fuentes**, no solo las UIs: ver la UI Embudo
  del ejecutivo sin `bash/vturb` habría mostrado el bloque VSL en error. Ver
  una UI es ver sus datos.
- Cuando un workspace ve más de una capa de rol (cerebro, technology), el panel
  de UIs muestra un **badge con el rol** de cada UI (`_layer`, que ya existía
  y no se mostraba). Y el store **avisa en consola** si dos capas de rol
  comparten un slug (sombreado silencioso; hoy no hay colisiones — es un
  aviso, no una regla).

**Por qué esto reabre y cierra la pregunta 1.** Se había decidido «código»
porque había UN consumidor; con dos, la balanza se da vuelta. El registro de
la decisión sigue siendo este spec; el archivo es el *estado*, el spec es el
*porqué*.

**Alcance.** Es el viz local del fork (Fase 1, identidad sin auth). El
publicador (`app.ikigaigm…`) tiene su propio `permiso_ui.sh` por rol/usuario
y no se toca. Tampoco cambia `actualizar_flota`/canal: `docs/roles/` ya viaja
a los copilotos, así que el mapa llega solo.

**Verificado.** `bash/lib/test_acceso.sh` 15/15 en bash 5.2 y 3.2.57;
`npm run test:viz` 38/38; forks simulados: technology carga las 4 capas de
rol, ejecutivo solo la suya, editor y «sin role» ninguna, cerebro todo.


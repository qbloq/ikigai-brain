# Control de acceso a fuentes por rol — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que las cercas de los dominios con credencial de proveedor (`bash/ghl/`, `bash/vturb/`) decidan por **rol** del `copilot.json` (ejecutivo = acceso total) y no por «¿soy un fork?», con la doctrina en un solo helper.

**Architecture:** Un helper `bash/lib/acceso.sh` independiente de `common.sh` expone `require_acceso <dominio>`: sin `copilot.json` → cerebro → 0; con `copilot.json` → lee `role` y consulta una tabla comentada en el propio helper; rol con el dominio → 0; si no (o identidad ilegible/sin rol) → mensaje + `exit 3`. Las dos cercas existentes reemplazan su `if [[ -f copilot.json ]]` por la llamada. Docs de roles + CLAUDE.md remiten al helper.

**Tech Stack:** bash 4+, python3 (stdlib, para leer el JSON — ya es dependencia de todo `bash/`), git worktree para simular un fork en las pruebas.

**Spec:** `docs/superpowers/specs/2026-08-20-control-de-acceso-fuentes-design.md`

## Global Constraints

- El helper **nunca toca red ni base**: decide con el archivo local `copilot.json` en la raíz del repo.
- **Fail-closed**: `copilot.json` ilegible o sin `role` → negado con mensaje de identidad; rol desconocido → negado (mismo camino que hoy).
- Mismo código de salida que hoy: `exit 3`.
- La cerca decide por `copilot.json`/rol, **jamás** por la máquina donde corre.
- El mapa vive **en código** (decisión de esta sesión sobre la pregunta abierta 1): editar la tabla = decisión de gobernanza, y el registro es el spec committeado + el comentario de la tabla (el `gobernanza/decisiones.jsonl` de forja es el ledger de revisión de deltas, escrito solo por `review.sh` — no es un registro de políticas).
- `director-comercial` **no** recibe `ghl` (pregunta abierta 2): lee el espejo `bash/crm/`; queda como candidato comentado.
- No-goals intactos: ni credenciales al backend, ni fallback proxy Mkt, ni cifrado, ni telemetría (pregunta 3 va con `2026-08-19-seguridad-copiloto-claude-code-design.md`).
- Todo lo que vive en `bash/` viaja a los copilotos por el canal (`derivar_canal.sh` → `actualizar_flota.sh`); nada que desplegar en servidores.

## Resolución de las preguntas abiertas del spec

| # | Pregunta | Decisión |
|---|---|---|
| 1 | ¿Mapa en código o archivo declarativo? | **Código** (tabla en `acceso.sh`). Más simple, viaja por el canal, una sola fuente. |
| 2 | ¿`director-comercial` recibe `ghl`? | **No.** Le alcanza el espejo; la sonda directa es para medir el espejo. Queda comentado como candidato. |
| 3 | ¿Telemetría del uso de credencial desde un fork? | **Fuera de esta fase** — spec hermano. |
| 4 | Credenciales detrás del backend + proxy Mkt | **Fuera de esta fase** — paso siguiente declarado. |

---

### Task 1: `bash/lib/acceso.sh` — el helper + su test

**Files:**
- Create: `bash/lib/acceso.sh`
- Create: `bash/lib/test_acceso.sh` (test ejecutable, sin framework; arma un árbol temporal `tmp/bash/lib/acceso.sh` + `tmp/copilot.json` para que el helper resuelva la raíz por su propia ubicación, sin overrides de entorno)

**Interfaces:**
- Produces: función `require_acceso <dominio>` (dominio ∈ `ghl`, `vturb`, … — cualquier string; los desconocidos solo pasan con `*`). Retorna 0 o hace `exit 3` con mensaje en stderr. Define `ACCESO_REPO_ROOT` (raíz del repo, resuelta desde `BASH_SOURCE`). Al hacer `source`, no ejecuta nada.

- [x] **Step 1: Escribir el test (falla porque el helper no existe)**

```bash
#!/usr/bin/env bash
# Test de bash/lib/acceso.sh — la cerca por rol, sin red ni base.
# Correr: bash bash/lib/test_acceso.sh   (sale 0 si todo pasa)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$HERE/acceso.sh"
fails=0

# arma un repo de mentira con el helper en la misma posición relativa
# (bash/lib/) para que resuelva su raíz y lea tmp/copilot.json.
mk() {  # mk <copilot.json-content | ""(sin archivo)>
  local d; d="$(mktemp -d)"
  mkdir -p "$d/bash/lib"; cp "$HELPER" "$d/bash/lib/acceso.sh"
  [[ -n "$1" ]] && printf '%s' "$1" >"$d/copilot.json"
  printf '%s' "$d"
}
run() {  # run <dir> <dominio> → echo exit code; stderr en $ERR
  local d="$1" dom="$2"
  ERR="$(bash -c "source '$d/bash/lib/acceso.sh'; require_acceso '$dom'" 2>&1 >/dev/null)"
  echo $?
}
check() {  # check <nombre> <esperado> <obtenido> [<frag que stderr debe contener>]
  if [[ "$2" == "$3" ]] && { [[ -z "${4:-}" ]] || grep -q -- "$4" <<<"$ERR"; }; then
    echo "ok   $1"
  else
    echo "FAIL $1: esperaba exit $2${4:+ + «$4»}, obtuve exit $3; stderr: $ERR"; fails=$((fails+1))
  fi
}

d="$(mk "")";                                        check "cerebro (sin copilot.json) → ghl"    0 "$(run "$d" ghl)"
d="$(mk "")";                                        check "cerebro → vturb"                     0 "$(run "$d" vturb)"
d="$(mk '{"employee":"lorenzo-cadavid","team_member_id":"x","role":"ejecutivo"}')"
                                                     check "ejecutivo → ghl"                     0 "$(run "$d" ghl)"
                                                     check "ejecutivo → vturb"                   0 "$(run "$d" vturb)"
                                                     check "ejecutivo → dominio futuro (*)"      0 "$(run "$d" futuro)"
d="$(mk '{"employee":"tony-vidal","team_member_id":"x","role":"editor"}')"
                                                     check "editor → ghl negado"                 3 "$(run "$d" ghl)"   "bash/crm/"
                                                     check "editor → vturb negado"               3 "$(run "$d" vturb)" "editor"
d="$(mk '{"employee":"luis-david","team_member_id":"x","role":"director-comercial"}')"
                                                     check "director-comercial → ghl negado"     3 "$(run "$d" ghl)"   "director-comercial"
d="$(mk '{"employee":"x","team_member_id":"x"}')";   check "copilot.json sin role → negado"      3 "$(run "$d" ghl)"   "identidad"
d="$(mk 'esto no es json')";                         check "copilot.json roto → negado"          3 "$(run "$d" ghl)"   "identidad"
d="$(mk '{"employee":"x","team_member_id":"x","role":"ejecutivo"}')"
ERR="$(bash -c "source '$d/bash/lib/acceso.sh'" 2>&1)"; check "source no ejecuta nada"           0 "$?"

echo; (( fails == 0 )) && echo "todo ok" || { echo "$fails fallos"; exit 1; }
```

- [x] **Step 2: Correrlo y ver que falla**

Run: `bash bash/lib/test_acceso.sh`
Expected: `cp: cannot stat … acceso.sh` / todos FAIL.

- [x] **Step 3: Escribir el helper**

```bash
#!/usr/bin/env bash
# bash/lib/acceso.sh — quién puede usar los dominios con CREDENCIAL DE PROVEEDOR.
# Source desde el lib del dominio:  source "$(dirname "$0")/../../lib/acceso.sh"
#                                   require_acceso ghl
#
# LA DOCTRINA (spec docs/superpowers/specs/2026-08-20-control-de-acceso-fuentes-design.md)
# Algunos dominios de bash/ operan con tokens de proveedor leídos de la base
# (bash/ghl/ → project_crm_configs, bash/vturb/ → project_vturb_video_configs,
# en claro). El cerebro corre en una máquina que la org controla; los copilotos
# son forks destinados a 19 laptops, y una llave maestra regada no se audita ni
# se revoca por persona. Hasta 2026-08-20 la cerca era binaria («¿hay
# copilot.json? → no»), y trataba igual al CEO que al editor de video.
# Decisión de Santiago (2026-08-20): el acceso a fuentes lo define EL ROL,
# no el hecho de ser copiloto. `ejecutivo` accede a cualquier fuente del
# negocio, incluidas las de credencial de proveedor.
#
# Dos honestidades que este archivo carga:
#   1. Es un riel, no un muro: un fork con DATABASE_URL podría leer el token
#      con un SELECT. El helper mantiene honesto el camino honesto y evita que
#      nazca algo NUEVO que dependa de la llave en un fork. El muro real es
#      mover las credenciales detrás del backend (patrón bash/google/).
#   2. La máquina no es el criterio: se decide por copilot.json (rol), jamás
#      por dónde corre, para que no se olvide cerrar el día de la mudanza.
#
# Independiente de common.sh a propósito: tiene que poder responder en un fork
# sin .env ni Postgres. No toca red ni base: decide con el archivo local.
#
# EL MAPA — editarlo es decisión de gobernanza (registrarla en el spec).
#   rol               : dominios           nota
#   ejecutivo         : *                  acceso total a fuentes del negocio
#   # director-comercial : ghl             candidato; NO decidido — lee el espejo bash/crm/
# Lectura: `*` = todos los dominios con credencial; lista = solo esos
# (separados por espacio). Rol ausente del mapa = negado.
declare -A ACCESO_ROLES=(
  [ejecutivo]='*'
)

ACCESO_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCESO_REPO_ROOT="$(cd "$ACCESO_LIB_DIR/../.." && pwd)"

# acceso_rol : echoes the role of this repo — "cerebro" when there is no
# copilot.json; the `role` value when there is one; "" when the file is
# unreadable or has no role (fail-closed upstream).
acceso_rol() {
  local f="$ACCESO_REPO_ROOT/copilot.json"
  [[ -f "$f" ]] || { echo cerebro; return 0; }
  python3 - "$f" 2>/dev/null <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    r = d.get("role") if isinstance(d, dict) else None
    print(r.strip() if isinstance(r, str) and r.strip() else "")
except Exception:
    print("")
PY
}

# acceso_alternativa <dominio> : a dónde ir cuando el dominio está negado.
acceso_alternativa() {
  case "$1" in
    ghl)   echo "bash/ghl/ lee tokens de project_crm_configs; el espejo del CRM es bash/crm/ (ingestado, sin credencial)." ;;
    vturb) echo "bash/vturb/ lee tokens de project_vturb_video_configs; el fallback vía proxy Mkt (apis/mkt/vturb-video.openapi.json) está pendiente." ;;
    *)     echo "el dominio '$1' opera con credencial de proveedor." ;;
  esac
}

# require_acceso <dominio> : returns 0 when this repo may use the domain;
# otherwise prints why and exits 3 (same code the old binary fence used).
require_acceso() {
  local dom="$1" rol perm d
  rol="$(acceso_rol)"
  [[ "$rol" == "cerebro" ]] && return 0
  if [[ -z "$rol" ]]; then
    echo "$dom: copilot.json sin identidad legible (falta \`role\` o no es JSON) — un fork sin identidad no hereda permisos." >&2
    echo "     (bash/lib/acceso.sh: el acceso a fuentes con credencial lo define el rol; arregla copilot.json o pide el alta de nuevo)" >&2
    exit 3
  fi
  perm="${ACCESO_ROLES[$rol]:-}"
  if [[ "$perm" == "*" ]]; then return 0; fi
  for d in $perm; do [[ "$d" == "$dom" ]] && return 0; done
  echo "$dom: este dominio no está habilitado para el rol '$rol' — solo el cerebro y los roles del mapa en bash/lib/acceso.sh manejan credenciales de proveedor." >&2
  echo "     ($(acceso_alternativa "$dom"))" >&2
  exit 3
}
```

- [x] **Step 4: Correr el test y ver que pasa**

Run: `bash bash/lib/test_acceso.sh`
Expected: todas `ok`, línea final `todo ok`, exit 0.

- [x] **Step 5: Commit**

```bash
git add bash/lib/acceso.sh bash/lib/test_acceso.sh
git commit -m "bash/lib/acceso.sh: la cerca de fuentes con credencial decide por ROL — ejecutivo = total"
```

---

### Task 2: Las dos cercas migran al helper (+ READMEs del dominio)

**Files:**
- Modify: `bash/ghl/lib/common.sh:35-42` (bloque `# --- Fork guard ---`) y el encabezado `brain only:` (línea ~21)
- Modify: `bash/vturb/lib/common.sh:36-43` (bloque `# --- Fork guard ---`) y el encabezado `brain only:` (línea ~19)
- Modify: `bash/ghl/README.md:25-27` («Solo el cerebro.»)
- Modify: `bash/vturb/README.md:24` («solo cerebro»)

**Interfaces:**
- Consumes: `require_acceso <dominio>` de Task 1 (source `"$X_LIB_DIR/../../lib/acceso.sh"`).

- [x] **Step 1: Preparar el fork de prueba (sin tocar el árbol de trabajo)**

```bash
W=/tmp/claude-1000/-projects-hermetico/5056bac7-6cc6-4021-8e0d-83a9e8e19db6/scratchpad/fork-prueba
git worktree add --detach "$W" HEAD
ln -s /projects/hermetico/.env "$W/.env"     # el fork de prueba usa la misma base
printf '{"employee":"prueba","team_member_id":"x","role":"editor"}\n' > "$W/copilot.json"
```

- [x] **Step 2: Verificar la cerca ACTUAL en el fork (línea base: se niega para todo rol)**

Run: `cd $W && bash bash/ghl/auth_status.sh; echo "exit=$?"; bash bash/vturb/auth_status.sh; echo "exit=$?"`
Expected: ambos `exit=3` con el mensaje «solo del cerebro». Y cambiando `role` a `ejecutivo` también `exit=3` (eso es lo que se corrige).

- [x] **Step 3: Reemplazar la cerca de ghl**

En `bash/ghl/lib/common.sh`, el bloque

```bash
# --- Fork guard --------------------------------------------------------------
# identidad.md: a repo carrying copilot.json is an employee's fork. The brain
# holds the org's credentials; copilots do not.
if [[ -f "$REPO_ROOT/copilot.json" ]]; then
  echo "ghl: este dominio es solo del cerebro — un copiloto no maneja credenciales del CRM." >&2
  echo "     (bash/ghl/ lee tokens de project_crm_configs; los forks leen el espejo: bash/crm/)" >&2
  exit 3
fi
```

pasa a

```bash
# --- Cerca por rol -----------------------------------------------------------
# identidad.md: a repo carrying copilot.json is an employee's fork. Whether a
# fork may use THIS domain is decided by its role, in ONE place for every
# credential-bearing domain: bash/lib/acceso.sh (ejecutivo = total; the rest
# is refused with exit 3 and pointed at the mirror, bash/crm/).
# shellcheck disable=SC1091
source "$GHL_LIB_DIR/../../lib/acceso.sh"
require_acceso ghl
```

y en el encabezado, la viñeta `brain only: refuses to run inside a copilot fork (see the guard below), because forks inherit this code but must not inherit CRM credentials;` pasa a `fenced by ROLE: bash/lib/acceso.sh decides which copilot roles may use it (ejecutivo = total; the rest refused) — forks inherit this code, but not the credentials unless their role says so;`.

- [x] **Step 4: Reemplazar la cerca de vturb**

En `bash/vturb/lib/common.sh`, el bloque

```bash
# --- Fork guard --------------------------------------------------------------
# identidad.md: a repo carrying copilot.json is an employee's fork. The brain
# holds the org's credentials; copilots do not.
if [[ -f "$REPO_ROOT/copilot.json" ]]; then
  echo "vturb: este dominio es solo del cerebro — un copiloto no maneja credenciales del proveedor de video." >&2
  echo "       (bash/vturb/ lee tokens de project_vturb_video_configs)" >&2
  exit 3
fi
```

pasa a

```bash
# --- Cerca por rol -----------------------------------------------------------
# identidad.md: a repo carrying copilot.json is an employee's fork. Whether a
# fork may use THIS domain is decided by its role, in ONE place for every
# credential-bearing domain: bash/lib/acceso.sh (ejecutivo = total; the rest
# is refused with exit 3 — the proxy-Mkt fallback for them is still pending).
# shellcheck disable=SC1091
source "$VTURB_LIB_DIR/../../lib/acceso.sh"
require_acceso vturb
```

y en el encabezado la viñeta `brain only: refuses to run inside a copilot fork (guard below);` pasa a `fenced by ROLE: bash/lib/acceso.sh decides which copilot roles may use it (ejecutivo = total; the rest refused);`.

- [x] **Step 5: READMEs**

`bash/ghl/README.md` líneas 25-27 pasan a:

```
- **Cerca por rol.** La decide `bash/lib/acceso.sh` (`require_acceso ghl`):
  sin `copilot.json` = cerebro = acceso; con `copilot.json`, solo los roles del
  mapa (hoy `ejecutivo`); el resto se niega con `exit 3` y va al espejo
  (`bash/crm/`). Ampliar el mapa es decisión de gobernanza.
```

`bash/vturb/README.md` línea 24 pasa a:

```
- **cerca por rol**: `bash/lib/acceso.sh` (`require_acceso vturb`) — cerebro y
  rol `ejecutivo` acceden; los demás roles se niegan con `exit 3` hasta que
  exista el fallback vía proxy Mkt;
```

- [x] **Step 6: Verificar las cuatro celdas (cerebro / ejecutivo / editor / sin rol) — el worktree usa los archivos del HEAD, así que primero se sincronizan los modificados**

```bash
cd /projects/hermetico
for f in bash/lib/acceso.sh bash/ghl/lib/common.sh bash/vturb/lib/common.sh; do mkdir -p "$W/$(dirname $f)"; cp "$f" "$W/$f"; done
# cerebro (este árbol): siguen corriendo
bash bash/ghl/auth_status.sh | head -3; bash bash/vturb/auth_status.sh | head -3
# fork editor → 3
cd "$W"; bash bash/ghl/auth_status.sh; echo "ghl exit=$?"; bash bash/vturb/auth_status.sh; echo "vturb exit=$?"
# fork ejecutivo → corre; embudo llena vsl
printf '{"employee":"prueba","team_member_id":"x","role":"ejecutivo"}\n' > "$W/copilot.json"
bash bash/ghl/auth_status.sh | head -3; bash bash/vturb/auth_status.sh | head -3
bash bash/metrics/embudo.sh --project "David" --json | python3 -c 'import json,sys; v=json.load(sys.stdin)["vsl"]; print("vsl:", "ERROR "+v["error"] if "error" in v else "ok "+v["fuente"])'
# fork sin role → 3 con «identidad»
printf '{"employee":"prueba","team_member_id":"x"}\n' > "$W/copilot.json"
bash bash/vturb/auth_status.sh; echo "exit=$?"
```

Expected: cerebro ok · editor `exit=3` con mensaje de rol · ejecutivo ok y `vsl: ok vturb (live)` · sin rol `exit=3` con «identidad».

- [x] **Step 7: Commit + limpiar el worktree**

```bash
cd /projects/hermetico
git add bash/ghl/lib/common.sh bash/vturb/lib/common.sh bash/ghl/README.md bash/vturb/README.md
git commit -m "ghl+vturb: la cerca de credenciales pasa a bash/lib/acceso.sh — decide el rol, no ser fork"
git worktree remove --force "$W"
```

---

### Task 3: La doctrina donde viven los roles + CLAUDE.md + cierre del spec

**Files:**
- Modify: `docs/roles/README.md` (nueva sección antes de «## Hallazgos transversales»)
- Modify: `docs/roles/ejecutivo.md` (línea bajo «**Capa de rol (viz):**»)
- Modify: `CLAUDE.md:423-426` (GHL: «refuses to run inside a copilot fork»), `CLAUDE.md:456-457` (VTurb: «cerca de solo-cerebro (guard anti-fork)»), `CLAUDE.md:598-602` (testeos: «En un fork el bloque VSL…»)
- Modify: `docs/superpowers/specs/2026-08-20-control-de-acceso-fuentes-design.md` (línea «**Estado**»)

- [x] **Step 1: `docs/roles/README.md` — la regla general**

Insertar antes de `## Hallazgos transversales`:

```markdown
## Acceso a fuentes con credencial de proveedor

El acceso a los dominios de `bash/` que operan con **tokens de proveedor**
(`bash/ghl/`, `bash/vturb/`) lo define **el rol**, no el hecho de ser
copiloto (decisión 2026-08-20, spec
`docs/superpowers/specs/2026-08-20-control-de-acceso-fuentes-design.md`).
El mapa vive en [`bash/lib/acceso.sh`](../../bash/lib/acceso.sh)
(`require_acceso <dominio>`): sin `copilot.json` = cerebro = acceso total;
con `copilot.json`, solo los roles del mapa — hoy **`ejecutivo` = total**;
todo otro rol se niega con `exit 3` y un mensaje que dice a dónde ir (el
espejo `bash/crm/` para GHL; el proxy Mkt, pendiente, para VTurb). Un
`copilot.json` sin `role` legible no hereda permisos. **Ampliar el mapa es
decisión de gobernanza** y se registra en el spec. La cerca es un riel, no un
muro (un fork con `DATABASE_URL` puede leer el token); el muro es mover las
credenciales detrás del backend.
```

- [x] **Step 2: `docs/roles/ejecutivo.md`**

Después de la línea `**Capa de rol (viz):** …` añadir:

```markdown
**Nivel de acceso a fuentes:** **total** — incluye los dominios con credencial de proveedor (`bash/ghl/`, `bash/vturb/`), vía `bash/lib/acceso.sh` (decisión 2026-08-20; es el rol que mira el embudo completo, `embudo.sh`, con el bloque VSL en vivo).
```

- [x] **Step 3: CLAUDE.md — tres retoques**

GHL (`fenced: it **refuses to run inside a copilot fork**, only GETs, and hands the`) →
`fenced: **por rol** (`bash/lib/acceso.sh` — cerebro y `ejecutivo` acceden; el resto se niega, exit 3), only GETs, and hands the`.

VTurb (`claro (`project_vturb_video_configs.api_key_encrypted`), cerca de solo-cerebro (guard anti-fork), token por stdin jamás en argv,`) →
`claro (`project_vturb_video_configs.api_key_encrypted`), **cerca por rol** (`bash/lib/acceso.sh`: cerebro y `ejecutivo`; el resto exit 3), token por stdin jamás en argv,`.

Testeos (`⚠️ **En un fork el bloque VSL del snapshot viene con error declarado** (`bash/vturb` se niega fuera del cerebro): los testeos con métrica `vsl.*` se abren desde el cerebro hasta que el fallback vía el proxy Mkt exista`) →
`⚠️ **En un fork de rol distinto de `ejecutivo` el bloque VSL del snapshot viene con error declarado** (`bash/vturb` se niega por rol, `bash/lib/acceso.sh`): los testeos con métrica `vsl.*` se abren desde el cerebro o desde un copiloto ejecutivo hasta que el fallback vía el proxy Mkt exista`.

- [x] **Step 4: Estado del spec**

`**Estado**: diseño acordado en conversación, pendiente de su propia sesión (no implementado)` →
`**Estado**: implementado 2026-08-21 (plan `docs/superpowers/plans/2026-08-21-control-de-acceso-fuentes.md`); preguntas abiertas 1-2 resueltas ahí (mapa en código; director-comercial sin ghl), 3-4 siguen abiertas`.

- [x] **Step 5: Verificar que nada quedó apuntando a la cerca vieja**

Run: `grep -rn "solo del cerebro\|refuses to run inside a copilot fork\|guard anti-fork\|se niega fuera del cerebro\|Fork guard" CLAUDE.md bash/ docs/roles/ bash/ghl/README.md bash/vturb/README.md`
Expected: sin resultados (salvo comentarios históricos en el spec/plan, que no están en el grep).

- [x] **Step 6: Commit**

```bash
git add docs/roles/README.md docs/roles/ejecutivo.md CLAUDE.md docs/superpowers/specs/2026-08-20-control-de-acceso-fuentes-design.md docs/superpowers/plans/2026-08-21-control-de-acceso-fuentes.md
git commit -m "docs: acceso a fuentes por rol — la doctrina donde viven los roles; spec implementado"
```

---

## Fuera del plan (siguiente paso, no de esta sesión)

- Propagar a la flota: `derivar_canal.sh` → `actualizar_flota.sh` en forja; el copiloto de Lorenzo lo trae con `/actualizarse`. Prueba real: UI embudo con VSL en su máquina.
- Pregunta 3 (telemetría agregada del uso de credencial desde forks) y 4 (credenciales detrás del backend + fallback proxy Mkt, reportar antes el bug del normalizador de retención).

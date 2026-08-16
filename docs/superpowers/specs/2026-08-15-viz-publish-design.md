# Publicación de UIs del viz — diseño

**Fecha:** 2026-08-15 · **Estado:** aprobado en conversación, pendiente de plan
de implementación.

## Qué se construye

La capacidad de **publicar una UI del viz** como página stand-alone en
producción: URL legible (`app.ikigaigm.parallelo.ai/dashboard-closer`) + alias
corto (`/s/Ab3x`), con **datos vivos** (cada visita re-renderiza contra la DB),
**login contra la autenticación existente de Marketico**, y **permisos con
alcance de datos por identidad** (un closer ve solo sus llamadas; el Director
Comercial ve todos los closers vía dropdown — misma UI publicada).

Primer despliegue objetivo: el **Dashboard de Closer**.

## Decisiones tomadas (y por qué)

| Decisión | Elección | Racional |
|---|---|---|
| Datos | **Vivos** (no snapshot) | Filosofía del viz: una UI es un spec que re-renderiza, no markup congelado. La DB (pooler de Supabase) es alcanzable desde el servidor api — verificado. |
| Código en el servidor | **Checkout del cerebro** en `/apps/hermetico` | Un solo código, cero drift: el publicador reusa la torre entera (`lib/`, `pages/`, `blocks/`, tema, assets). Actualizar = `git pull` + restart. |
| Dominio | **`app.ikigaigm.parallelo.ai`** (nuevo site) | Ya resuelve al servidor api (137.184.188.28, wildcard DNS) — solo falta nginx + certbot. Se descartó reusar `a.parallelo.ai`: su catch-all `/` es el `agenticlaw-webhook-router` (puerto 8080) — no está libre. |
| Autenticación | **Login contra Marketico** (no tokens-capability) | Ya existe: `POST /api/auth/login` (email+password, bcrypt contra `users`) devuelve JWT `{id, email, roles[], name}`; roles ya resueltos (principal + secundarios), `name` = `persons.name` (el mismo de la resolución de closer). No se crea ningún sistema de usuarios nuevo. |
| Alcance de datos | **Plantilla de identidad en el despliegue + 3 estados por permiso** | Ver «Permisos» abajo. |
| Flujo de publicación | **Scripts `bash/publicar/` + conversación** (sin botón en el navegador) | Regla vigente: «viz es visor, edición en conversación». |

## Arquitectura

```
tu máquina                          servidor api (137.184.188.28)
──────────                          ────────────────────────────────
viz/server.js  :4317                /apps/hermetico   (git clone + .env propio)
(el taller: shell, editor,            └─ viz/publish.js  :4318   ← pm2 "viz-publish"
 creación de UIs)                     └─ data/sqlite/publicaciones.db
                                    nginx: app.ikigaigm.parallelo.ai → :4318
bash/publicar/*.sh ──ssh──────────▶ (registro sqlite, git pull, pm2 restart)
```

### `viz/publish.js` — el servidor de producción

**Segundo entrypoint** del viz, hermano de `server.js` en el mismo repo.
Importa las mismas librerías (`lib/components.js`, `lib/datasources.js`,
`lib/store.js`, `lib/theme.js`, pages/blocks/patterns) pero monta una
superficie mínima:

| Ruta | Qué hace |
|---|---|
| `GET /<slug>` | Render standalone full-page del despliegue (como `/u/:id` local), con los params de identidad forzados server-side. Sin sesión → página de login. Sin permiso → 404. |
| `GET /s/<code>` | Alias corto → mismo render que el slug (redirect). Conveniencia para compartir; **cero rol de seguridad** (el login gatea igual). |
| `POST /login` | Recibe email+password del form propio, los reenvía server-side a la API de Marketico; si hay token → cookie `httpOnly` + `Secure` + `SameSite=Lax` y redirect al slug. |
| `POST /logout` | Borra la cookie. |
| `GET /c/:component/frag/:name` | Solo los fragments **GET** (SSE) que la UI publicada necesita (filtros, panel detalle), **re-aplicando los params forzados en cada request**. |
| `GET /<asset>` | Assets vendorizados whitelisted (`PUBLIC_FILES` + fonts). |
| `GET /health` | Liveness para pm2/monitoreo. |

**Lo que NO existe en publish.js** (por construcción, no por configuración): el
shell master-detail, el form «Nueva UI», el IO editor, todos los `POST` de
acts, `/api/fuente`. El runner de writes (`lib/actions.js`) **no se monta** —
es imposible ejecutar un script WRITE desde el publicador.

**Verificación del JWT:** local, con el `JWT_SECRET` compartido (vive en
`/apps/marketico/.env`, misma máquina; se copia/referencia en el `.env` del
checkout). Sin llamada de red por visita. Token expirado o inválido → login.

### Registro: `data/sqlite/publicaciones.db` (en el servidor)

Mismo patrón localdb (helpers `sqlite.sh`, db por nombre, WRITE opt-in).

**`despliegues`** — una fila por UI publicada × generación:

| Columna | Notas |
|---|---|
| `id`, `slug` (único por generación vigente), `codigo_corto` (alias) | |
| `spec_json` | **Snapshot congelado al publicar.** Editar la UI en el viz local NO cambia lo publicado. |
| `component`, `source`, `params_fijos` (json) | Denormalizados del spec para consulta. |
| `identidad` (json) | La plantilla, declarada UNA vez: p. ej. `{"closer": "$name"}`. Variables: `$name`, `$email`, `$user_id` — sustituidas desde el JWT del visitante. |
| `generacion` | Re-publicar = generación+1, nunca sobreescribe (misma filosofía que `reporte_guardar.sh`). |
| `creado_at`, `archivado_at` | Despublicar = archivar (soft), nunca borrar. |

**`permisos`** — despliegue × (user **o** rol):

| Columna | Notas |
|---|---|
| `despliegue_id` | FK (al slug lógico, aplica a la generación vigente). |
| `user_id` o `rol` | Exactamente uno. `rol` matchea contra los `roles[]` del JWT. |
| `params_identidad` (json, 3 estados) | **`NULL`** = hereda la plantilla del despliegue · **`{}`** = anula la plantilla (nada se fuerza — el caso Director) · **`{k:v}`** = forzado explícito (excepciones). |
| `creado_at`, `revocado_at` | Revocar es sellar fecha, no borrar. |

**`visitas`** — log liviano: despliegue, user_id, ts. Quién abrió qué.

### Permisos: resolución y precedencia

1. **Matcheo:** permiso por-**user** gana sobre permiso por-**rol**; entre
   varios roles que matcheen, gana el **menos restrictivo** (`{}` sobre
   plantilla). Ningún match → **404** (logueado o no: no se revela qué slugs
   existen).
2. **Precedencia de params al armar el comando bash:**
   `params_fijos` del despliegue → overrides del navegador (solo los
   `overridable` del manifest, como siempre) → **identidad resuelta GANA
   SIEMPRE**. Un closer que edite `?closer=Otro` es pisado server-side antes de
   llegar al shell — también en los fragments SSE.
3. **UI de params bloqueados:** el render recibe la lista de params forzados;
   para esos, el control (dropdown) no se pinta — se pinta un **chip fijo** con
   el valor. El Director (nada forzado) ve el dropdown normal.

**El caso canónico, un solo despliegue `dashboard-closer`:**

| Permiso | `params_identidad` | Efecto |
|---|---|---|
| `rol="Closer"` | `NULL` | Cada closer entra auto-filtrado (`closer=$name`). Un closer nuevo en el equipo cae bajo este permiso sin configuración. |
| `rol="Director Comercial"` | `{}` | Dropdown libre, ve todos. |

**Límite honesto:** la identidad fuerza **params de la fuente** (`--closer`,
`--project`…). No filtra dentro de una fila ni oculta columnas — dos
audiencias que necesiten **estructuras distintas** son dos despliegues, no dos
permisos.

## Flujo de publicación — `bash/publicar/` (conversación, no navegador)

| Script | Uso |
|---|---|
| `publicar_ui.sh <spec-id> --slug <slug> [--identidad k=$var]… [--fijar k=v]… [--dry-run]` **[WRITE remoto]** | Lee el spec del store local, `validateSpec`, ssh → inserta despliegue (o generación+1 si el slug existe). Avisa si el spec usa código aún no pusheado al servidor. |
| `permiso_ui.sh <slug> --rol <Rol> \| --user <email> [--identidad k=v \| --sin-identidad] [--revocar] [--listar] [--visitas]` **[WRITE remoto]** | Alta/revocación/listado de permisos. `--sin-identidad` escribe `{}` explícito. |
| `desplegar.sh [--dry-run]` **[WRITE remoto]** | `git push` + ssh `git pull && pm2 restart viz-publish`. Para cambios de código; el registro no lo toca. |

Todos con `--json` y `-h`, mismo contrato que el resto de `bash/`.

## Infraestructura

- **nginx:** site nuevo `app.ikigaigm.parallelo.ai` → `proxy_pass
  http://localhost:4318`, con `proxy_buffering off` (SSE) y los headers
  estándar. Cert vía `certbot --nginx`. DNS: ya resuelve (wildcard) — cero
  trabajo.
- **pm2:** proceso `viz-publish` (`node viz/publish.js`, cwd
  `/apps/hermetico`, `PORT=4318`, `HOST=127.0.0.1` — solo nginx lo alcanza).
- **Checkout:** `/apps/hermetico` clonado del remoto de trabajo; `.env` propio
  con `DATABASE_URL` (misma DB que marketico ya usa desde esa máquina) +
  `JWT_SECRET` + lo mínimo que las fuentes publicadas requieran. **Nunca** se
  copia el `.env` local entero: solo las llaves necesarias.

## Seguridad (resumen de rails)

- Solo lectura end-to-end: fuentes por `psql_ro`, runner de writes sin montar.
- Cookie `httpOnly` + `Secure` + `SameSite=Lax`; JWT verificado localmente.
- 404 uniforme para slug inexistente y para permiso ausente.
- `HOST=127.0.0.1`: el puerto 4318 no se expone; solo nginx (TLS) llega.
- Los params del navegador pasan por la whitelist `overridable` del manifest
  (ya existente) y la identidad los pisa — inyección de flags imposible por el
  mismo `buildArgs` de siempre.
- Credenciales de login viajan una vez, directo a la API de Marketico
  (server-side); publish.js no las persiste.

## Verificación / pruebas

1. **Local primero:** publish.js corre en la máquina local (puerto 4318) con
   un sqlite de prueba — login real contra la API de Marketico remota, render
   del dashboard-closer, y los tres escenarios de permiso (closer, director,
   sin permiso → 404). Verificar que `?closer=Otro` es pisado en página y en
   fragments SSE.
2. **En el servidor:** deploy, `curl /health`, login real de un closer de
   prueba, verificación TLS + cookie Secure.
3. **Regresión del viz local:** `server.js` no cambia; `npm run viz` sigue
   igual.

## Fuera de alcance (YAGNI declarado)

- **Fragments `/c/` — no se montan en v1.** El piloto re-renderiza por
  `GET /ui/:id`; montar frags genéricos abriría autorización a nivel de fila
  que el modelo v1 no gobierna. Regla operativa: solo se publican UIs
  autosuficientes (sin blocks con frags). Problema, opciones y recomendación
  (capability por fila firmada en el render):
  [docs/viz-publish-fragmentos.md](../../viz-publish-fragmentos.md).
- Auto-deploy por push (webhook) — `desplegar.sh` manual basta hoy.
- Rate-limiting, 2FA, refresh tokens — el login de Marketico es el que es.
- Editar/crear UIs desde producción — jamás: el taller es local.
- Filtrado por-fila o por-columna dentro de una misma UI (documentado como
  límite: son dos despliegues).
- UI de administración de permisos — es conversación + `permiso_ui.sh`.

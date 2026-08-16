// Lógica pura de permisos e identidad del publicador (viz/publish.js).
// El modelo (spec 2026-08-15): el despliegue declara la plantilla de identidad
// UNA vez; cada permiso decide con params_identidad si aplica (NULL hereda),
// se anula ('{}') o se fuerza otra cosa (json explícito).

// Rango de restrictividad de un permiso: '{}' (nada forzado) es el menos
// restrictivo; el explícito fuerza valores propios; NULL hereda la plantilla.
function rango(p) {
  if (p.params_identidad == null) return 2;
  const parsed = JSON.parse(p.params_identidad);
  return Object.keys(parsed).length === 0 ? 0 : 1;
}

// user > rol; entre roles, el menos restrictivo. Determinista.
function elegirPermiso(permisos, payload) {
  if (!payload) return null;
  const roles = new Set(payload.roles || []);
  const porUser = permisos.filter((p) => p.user_id && p.user_id === payload.id);
  if (porUser.length) return porUser.sort((a, b) => rango(a) - rango(b))[0];
  const porRol = permisos.filter((p) => p.rol && roles.has(p.rol));
  if (!porRol.length) return null;
  return porRol.sort((a, b) => rango(a) - rango(b))[0];
}

// → los params FORZADOS para este visitante ({} = nada forzado), o **null =
// DENEGAR**. La distinción importa y es la que sostiene el modelo:
//
//   {}    el permiso dice explícitamente «no fuerces nada» (el Director) — sí ve.
//   null  la plantilla EXIGE una variable que esta sesión no puede llenar — no ve.
//
// Sin ese null la cosa fallaba ABIERTA: una variable vacía se volvía "" , y
// buildArgs descarta los params vacíos, así que el script corría SIN filtro y
// caía en su default (el closer con más llamadas) — la sesión sin identidad
// terminaba viendo los datos de otro. Una identidad que no resuelve es una
// sesión que no tiene derecho a la página, no una sesión sin filtro.
function resolverIdentidad(plantilla, permiso, payload) {
  let base;
  if (permiso.params_identidad == null) base = plantilla || {};
  else base = JSON.parse(permiso.params_identidad);
  const out = {};
  const vars = { $name: payload.name, $email: payload.email, $user_id: payload.id };
  for (const [k, v] of Object.entries(base)) {
    if (typeof v === "string" && Object.prototype.hasOwnProperty.call(vars, v)) {
      const resuelto = vars[v];
      if (resuelto == null || String(resuelto) === "") return null;
      out[k] = String(resuelto);
    } else {
      out[k] = v;
    }
  }
  return out;
}

// Precedencia del spec: fijos → overrides del navegador (whitelist) → forzados.
function mergeParams({ specParams, paramsFijos, overrides, overridable, forzados }) {
  const params = { ...(specParams || {}), ...(paramsFijos || {}) };
  for (const k of overridable || []) {
    const v = (overrides || {})[k];
    if (v != null && v !== "") params[k] = v;
  }
  Object.assign(params, forzados || {});
  return { params, locked: Object.keys(forzados || {}) };
}

module.exports = { elegirPermiso, resolverIdentidad, mergeParams };

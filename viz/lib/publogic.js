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

// → los params FORZADOS para este visitante ({} = nada forzado).
function resolverIdentidad(plantilla, permiso, payload) {
  let base;
  if (permiso.params_identidad == null) base = plantilla || {};
  else base = JSON.parse(permiso.params_identidad);
  const out = {};
  const vars = { $name: payload.name, $email: payload.email, $user_id: payload.id };
  for (const [k, v] of Object.entries(base)) {
    out[k] = typeof v === "string" && v in vars ? String(vars[v] ?? "") : v;
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

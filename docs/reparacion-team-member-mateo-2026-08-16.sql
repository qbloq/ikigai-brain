-- Eliminación del team_member duplicado de Mateo Restrepo (Ikigai Team).
--
-- Diagnóstico (2026-08-16): dos filas en ikigaigm.team_members con idéntico
-- user_id (3dd88377), role_id (Closer 7e83b8bc) y team_id (Ikigai a7c00dde),
-- creadas con 1 segundo de diferencia el 2026-05-06 (doble alta). Es el ÚNICO
-- par duplicado de la tabla.
--
-- Se conserva dd4621c1-04f5-4153-a860-a5f5e1e83f0f porque es la fila canónica:
--   · única con fila en team_member_roles
--   · la que referencian copilot.json e identidad.md del fork de Mateo
--     (data/forks/mateo-restrepo/ y forja/data/copilotos/ikigai/mateo-restrepo/)
--   · la primera creada
--
-- Se elimina 637277b5-fe82-4295-9fee-70dc67fce945: barrido de las 225 columnas
-- uuid/uuid[] del esquema ikigaigm (incluido tasks.assignee, que no tiene FK)
-- con CERO referencias. El único FK con CASCADE (team_member_roles) tampoco
-- tiene filas suyas. No se pierde nada.

BEGIN;

-- antes: deben salir 2 filas
SELECT id, user_id, created_at, updated_at FROM ikigaigm.team_members
WHERE user_id = '3dd88377-2ba0-41d0-8c4c-4548ed95e610'
  AND team_id = 'a7c00dde-2e0b-4a79-938a-d62514e6bdf9';

DELETE FROM ikigaigm.team_members
WHERE id = '637277b5-fe82-4295-9fee-70dc67fce945';

-- después: debe salir solo dd4621c1
SELECT id, user_id, created_at FROM ikigaigm.team_members
WHERE user_id = '3dd88377-2ba0-41d0-8c4c-4548ed95e610'
  AND team_id = 'a7c00dde-2e0b-4a79-938a-d62514e6bdf9';

COMMIT;

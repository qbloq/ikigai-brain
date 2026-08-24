-- Reparación 2026-08-24 — desmapear la cuenta publicitaria «DavidGuerrero_93»
-- (Meta act_766382718179654) del proyecto David Guerrero.
--
-- Por qué: el token del Cerebro recibe 403 de Meta al consultarla, y el aviso
-- salía en el embudo orgánico (followme). La cuenta está en desuso: 48 campañas
-- sin actualizarse desde 2026-03-21, 0 activas, y NUNCA entró un día de
-- insights suyo a la base (toda la pauta viva corre en CONTINGENCIA DAVID
-- GUERRERO, 1653161058598003). Decisión de Santiago 2026-08-24 (opción 1:
-- cuenta muerta). Se borra SOLO la fila de mapeo; ad_accounts y campaigns se
-- conservan (historial). Si Marketico la vuelve a mapear, la decisión de fondo
-- es quitarla del Business o darle permiso al token.
--
-- Ejecución: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f docs/reparacion-desmapeo-davidguerrero93-2026-08-24.sql
-- Estado: EJECUTADO por Santiago el 2026-08-24; verificado después: solo queda CONTINGENCIA (1653161058598003) mapeada a DG y followme ya no reporta errores_meta.
BEGIN;
SELECT 'antes' etapa, m.id, p.name proyecto, m.ad_account_id, a.name
  FROM ikigaigm.project_ad_account_mappings m
  JOIN ikigaigm.projects p ON p.id = m.project_id
  LEFT JOIN ikigaigm.ad_accounts a ON a.id = m.ad_account_id
 WHERE m.ad_account_id = '766382718179654';
DELETE FROM ikigaigm.project_ad_account_mappings
 WHERE id = '0ceec0ad-c45f-44d0-9fa5-d864446b36d7' AND ad_account_id = '766382718179654';
SELECT 'despues' etapa, m.ad_account_id, a.name
  FROM ikigaigm.project_ad_account_mappings m
  LEFT JOIN ikigaigm.ad_accounts a ON a.id = m.ad_account_id
 WHERE m.project_id = '9077f0f0-603e-4af5-8033-444778267d9e';
COMMIT;

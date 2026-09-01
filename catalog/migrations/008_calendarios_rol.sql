-- 008_calendarios_rol.sql — dos calendarios oficiales con rol + el calendario
-- de origen de cada reunión.
--
-- Contexto (spec 2026-08-26-marketico-port-ux-llamadas-design.md §1.1): desde
-- el 22-24 ago el calendario oficial de GHL es el de CONFIRMACIÓN (20 min,
-- call confirmers) y la llamada de venta (60 min) vive en «Aplicación a
-- Premium Mastermind». El sistema asumía UN calendario; `rol` declara cuál es
-- cuál y `meetings.ghl_calendar_id` permite tipar cada reunión
-- (confirmación/venta) sin adivinar. Idempotente.

BEGIN;

ALTER TABLE ikigaigm.crm_calendars
  ADD COLUMN IF NOT EXISTS rol text
  CHECK (rol IN ('entrada','venta'));

COMMENT ON COLUMN ikigaigm.crm_calendars.rol IS
  'entrada = confirmación (call confirmers, 20 min) · venta = llamada de venta con closer (60 min) · NULL = histórico/sin clasificar';

-- El oficial histórico pasa a ser el de entrada.
UPDATE ikigaigm.crm_calendars
SET rol = 'entrada'
WHERE ghl_calendar_id = 'bFFbTpMillO1n35FuDmv' AND rol IS DISTINCT FROM 'entrada';

-- «Aplicación a Premium Mastermind» entra como calendario de venta.
INSERT INTO ikigaigm.crm_calendars (project_id, ghl_calendar_id, ghl_calendar_name, is_active, rol)
SELECT '9077f0f0-603e-4af5-8033-444778267d9e', 'rmiAFkJKOZ2QZ1yEr8dn', 'Aplicación a Premium Mastermind', true, 'venta'
WHERE NOT EXISTS (
  SELECT 1 FROM ikigaigm.crm_calendars WHERE ghl_calendar_id = 'rmiAFkJKOZ2QZ1yEr8dn'
);
UPDATE ikigaigm.crm_calendars
SET rol = 'venta', is_active = true
WHERE ghl_calendar_id = 'rmiAFkJKOZ2QZ1yEr8dn' AND (rol IS DISTINCT FROM 'venta' OR NOT is_active);

ALTER TABLE ikigaigm.meetings
  ADD COLUMN IF NOT EXISTS ghl_calendar_id text;

COMMENT ON COLUMN ikigaigm.meetings.ghl_calendar_id IS
  'Calendario GHL del appointment que originó la reunión (migración 008). Lo escribe el Cerebro (bash/agenda/entrante.sh al crear; bash/agenda/tipar_meetings.sh backfill). El rol se deriva por join a crm_calendars.';

COMMIT;

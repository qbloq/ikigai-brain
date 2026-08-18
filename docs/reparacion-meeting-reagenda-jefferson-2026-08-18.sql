-- Reparación 2026-08-18 — reagenda de GHL que nunca llegó a la DB
--
-- Contexto: la reconciliación de agenda (bash/intercepciones/) detectó
-- horas_difieren en el meeting 38f17149 (Jefferson Lucio - Premium
-- Mastermind): GHL lo reagendó al 2026-08-21 17:00 Bogotá el 13-ago
-- (appointment gM43FtLuXg5VqViojHAm, calendario oficial, confirmed), pero el
-- webhook /crm nunca trajo el cambio y la DB quedó en 2026-08-13 17:00.
-- Se intentó re-disparar el workflow con un PUT por API con las mismas horas
-- (2026-08-18): GHL registró el update pero NO gatilló el workflow — hallazgo
-- documentado. Decisión de Santiago: reparar la DB directo (mover-y-devolver
-- notificaría reagendas falsas al lead).
--
-- ⚠️ Quirk respetado: scheduled_start_time guarda reloj BOGOTÁ etiquetado
-- como UTC — por eso los literales van con +00 y hora 17:00/18:00.
--
-- Nota: el evento de Google Calendar de Marketico sigue apuntando al 13-ago;
-- esa mitad solo la puede corregir Marketico (el Cerebro no escribe en
-- Google). El Meet/space no cambia (mismo link).

BEGIN;

SELECT id, name, status, event_id,
       to_char(scheduled_start_time AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI') AS inicio_bogota,
       to_char(scheduled_end_time   AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI') AS fin_bogota
FROM ikigaigm.meetings
WHERE id = '38f17149-7df9-4c76-ba2d-12a9f08f78d4';

UPDATE ikigaigm.meetings
SET scheduled_start_time = '2026-08-21T17:00:00+00',
    scheduled_end_time   = '2026-08-21T18:00:00+00'
WHERE id = '38f17149-7df9-4c76-ba2d-12a9f08f78d4'
  AND status = 'scheduled'
  AND scheduled_start_time = '2026-08-13T17:00:00+00';

SELECT id, name, status,
       to_char(scheduled_start_time AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI') AS inicio_bogota,
       to_char(scheduled_end_time   AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI') AS fin_bogota
FROM ikigaigm.meetings
WHERE id = '38f17149-7df9-4c76-ba2d-12a9f08f78d4';

COMMIT;

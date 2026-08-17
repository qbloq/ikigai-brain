-- Reparación 2026-08-17 — meeting de calendario NO oficial → cancelled
--
-- Contexto: la reconciliación de agenda (bash/intercepciones/) marcó
-- sobra_en_db el meeting 6ff4e3eb (Alexander Espinoza, 17-ago 13:00 Bogotá,
-- appointment 1b9BjJTlcLauXZ5OZKM9). La cita SÍ existe en GHL, pero en el
-- calendario «Aplicación a Premium Mastermind» (rmiAFkJKOZ2QZ1yEr8dn), que
-- NO es el oficial: decisión de Santiago 2026-08-17 — el único calendario
-- oficial es el configurado en crm_calendars (bFFbTpMillO1n35FuDmv,
-- «Calendario Premium Mastermind»). Los bookings de otros calendarios no
-- pertenecen al sistema.
--
-- Acción: borrado LÓGICO (status='cancelled') — la misma marca que
-- processBooking pone cuando una cita se cancela; nada se borra físicamente
-- (convención del repo: cruzar y ajustar, no borrar). Con esto la fila sale
-- del conjunto 'scheduled' y de la reconciliación.
--
-- Nota: el evento de Google Calendar + espacio Meet creados por Marketico
-- quedan vivos (el Cerebro no tiene write-path a Google); si la cita también
-- se cancela/borra en GHL, el webhook /crm haría esa limpieza del lado de
-- Marketico.

BEGIN;

SELECT id, name, status, event_id,
       to_char(scheduled_start_time AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI') AS inicio_bogota
FROM ikigaigm.meetings
WHERE id = '6ff4e3eb-883c-4e48-842a-29e8b1457e96';

UPDATE ikigaigm.meetings
SET status = 'cancelled'
WHERE id = '6ff4e3eb-883c-4e48-842a-29e8b1457e96'
  AND status = 'scheduled';

SELECT id, name, status FROM ikigaigm.meetings
WHERE id = '6ff4e3eb-883c-4e48-842a-29e8b1457e96';

COMMIT;

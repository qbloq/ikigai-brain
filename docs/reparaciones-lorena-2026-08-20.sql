-- Reparación 2026-08-20 — Lorena Amado (cierre de Mateo, 2026-08-19)
-- Contexto (informe ONLY CLOSERS §8): venta "resucitada" — Mateo marcó la
-- opportunity lost el 13-ago, la lead cerró por WhatsApp el 19-ago con abono
-- de $50, y la app no muestra opportunities perdidas, así que el cierre no
-- pudo registrarse. GHL ya está corregido (won, $50, opp itgTsHVYJ3DGFIotw4fI);
-- el espejo sigue lost por el bug de refresco del ingestor.
--
-- Este script crea el plan con SOLO la cuota 1 (el abono de $50, pagado).
-- Las cuotas 2-3 se agregan cuando Antonio/Mateo confirmen la estructura
-- (Mateo dijo "PA 3 meses" y "la otra semana paga resto"; la ficha decía 700).
-- Patrón de montos irregulares ya existente: plan 444 (Iván Cáceres, 100/317/283).
--
-- Identidades verificadas:
--   contacto GHL  : DvACw5coajzEi6arjpww  (Lorena Amado, +1 864 553 4852)
--   closer        : Mateo Restrepo, users.id 3dd88377-2ba0-41d0-8c4c-4548ed95e610
--   producto      : 17d40000-cf7f-4cba-bd03-817f72fa9dc3 (Premium Academy 3 meses)
--   proyecto      : 9077f0f0-603e-4af5-8033-444778267d9e (David Guerrero)

BEGIN;

WITH p AS (
  INSERT INTO ikigaigm.payment_plans
    (user_id, integration_id, product_id, customer_id, customer_name, original_amount,
     currency, number_of_installments, installment_frequency, start_date, plan_status,
     project_id, product_uuid)
  VALUES
    ('3dd88377-2ba0-41d0-8c4c-4548ed95e610', 'UBREqrQ6n5QEC8lFmyGt', '',
     'DvACw5coajzEi6arjpww', 'Lorena Amado', 700.00,
     'USD', 3, 'Monthly'::ikigaigm.installment_frequency, '2026-08-19',
     'Active'::ikigaigm.payment_plan_status,
     '9077f0f0-603e-4af5-8033-444778267d9e', '17d40000-cf7f-4cba-bd03-817f72fa9dc3')
  RETURNING plan_id, original_amount
), i AS (
  INSERT INTO ikigaigm.installments
    (plan_id, installment_number, due_date, scheduled_amount, paid_amount, payment_date, status)
  SELECT plan_id, 1, DATE '2026-08-19', 50.00, 50.00,
         TIMESTAMPTZ '2026-08-19 16:00:00-05', 'Paid'::ikigaigm.installment_status
  FROM p
  RETURNING installment_id, plan_id, paid_amount
)
INSERT INTO ikigaigm.commission_payouts
  (project_id, installment_id, plan_id, commission_rule_id, commission_type, user_id, role_id,
   rule_value_type, rule_value, installment_paid_amount, plan_total_amount,
   payout_amount, payout_amount_base, currency, base_currency, fx_rate, status)
SELECT '9077f0f0-603e-4af5-8033-444778267d9e', i.installment_id, i.plan_id,
       '14e92aed-dc04-4986-bb5e-81be8a13feb3', 'sale'::ikigaigm.commission_type,
       '3dd88377-2ba0-41d0-8c4c-4548ed95e610', '7e83b8bc-6f0b-4d7e-b63c-f8b6f557a13e',
       'pct_installment'::ikigaigm.commission_value_type, 10.0,
       i.paid_amount, p.original_amount,
       round(i.paid_amount * 0.10, 2), round(i.paid_amount * 0.10, 2),
       'USD', 'USD', 1.0, 'pending'::ikigaigm.payout_status
FROM i JOIN p USING (plan_id)
RETURNING plan_id, installment_id, payout_amount;

-- Verificación en la misma transacción
SELECT pp.plan_id, pp.customer_name, pp.original_amount, pp.plan_status,
       i.installment_number, i.scheduled_amount, i.paid_amount, i.status
FROM ikigaigm.payment_plans pp
JOIN ikigaigm.installments i ON i.plan_id = pp.plan_id
WHERE pp.customer_id = 'DvACw5coajzEi6arjpww';

COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2026-08-20 (segunda parte) — estructura del plan definida por Santiago:
-- el resto del pago ($650) en UNA cuota, programada para el jueves 27-ago
-- (da margen para recordarle a Mateo unos días antes). El plan queda de
-- 2 cuotas — "PA 3 meses" es la duración del programa, no el nº de cuotas
-- (precedente: Kevin Delgado, PA 3 meses en 1 cuota).

BEGIN;

UPDATE ikigaigm.payment_plans
   SET number_of_installments = 2
 WHERE plan_id = 492;

INSERT INTO ikigaigm.installments
  (plan_id, installment_number, due_date, scheduled_amount, paid_amount, status)
VALUES
  (492, 2, DATE '2026-08-27', 650.00, 0, 'Scheduled'::ikigaigm.installment_status);

-- Verificación
SELECT pp.plan_id, pp.number_of_installments, i.installment_number,
       i.scheduled_amount, i.paid_amount, i.due_date::date, i.status
FROM ikigaigm.payment_plans pp
JOIN ikigaigm.installments i ON i.plan_id = pp.plan_id
WHERE pp.plan_id = 492 ORDER BY i.installment_number;

COMMIT;

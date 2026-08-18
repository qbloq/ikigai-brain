-- Alta de las 6 ventas de Mateo Restrepo que nunca entraron al sistema de cobro.
-- Contexto y evidencia: docs/only-closers-informe.md §8.
--
-- Cada una está corroborada por TRES vías independientes:
--   · oportunidad `won` en GHL con el monto exacto
--   · ficha del lead y/o anuncio del cierre en el grupo ONLY CLOSERS
--   · la lista que Mateo reportó de memoria
-- y ninguna tenía payment_plan (verificado por customer_id, no por nombre).
--
-- Mateo confirmó (2026-08-14) que las seis entraron en UN SOLO PAGO (1 cuota),
-- por eso cada plan lleva una única cuota Paid por el total.
--
-- Nota sobre Edilio Suazo: Mateo lo reportó como «Ilder Bonifacio» — es la misma
-- persona (mismo contacto GHL dmy4MxvaQrMzSp2gV5V9), tenía una ficha de 2025 con
-- ese nombre. Monto 699 (valor en GHL y precio de PA 3 meses; Mateo dijo 700).
--
-- Convenciones idénticas a las reparaciones del 2026-08-13 (Edwin/Kevin/Samuel):
--   integración DG UBREqrQ6n5QEC8lFmyGt · proyecto DG 9077f0f0 · closer Mateo
--   3dd88377 · comisión regla 14e92aed 'sale' pct_installment 10% rol 7e83b8bc,
--   status pending (entra a la cola de aprobación, no se paga sola).
-- Los casts de enum son obligatorios en INSERT…SELECT (ver §8 del informe).

BEGIN;

WITH nuevos (customer_id, customer_name, monto, fecha, producto) AS (
  VALUES
    ('dmy4MxvaQrMzSp2gV5V9', 'Edilio Suazo',                   699.00::numeric, DATE '2026-06-22', '17d40000-cf7f-4cba-bd03-817f72fa9dc3'::uuid),
    ('ckpamrhdYsmTJ7FhqoJE', 'Jonathan Marulanda Vásquez',    3500.00::numeric, DATE '2026-07-02', '2c71bfe5-8cc0-409b-9a06-4f30c2843b72'::uuid),
    ('ghnSRxG6L4bLs4C5i6TL', 'Vane de Jesús Ricciulli Rojas',  699.00::numeric, DATE '2026-07-03', '17d40000-cf7f-4cba-bd03-817f72fa9dc3'::uuid),
    ('TKaJiOcWAdzCsKT0kkFC', 'María Paula Niño Rincón',       1000.00::numeric, DATE '2026-07-08', '0e771e70-410d-49d2-a876-1e567d23eaa3'::uuid),
    ('9KaOGkOJs0N5kyIbjYbp', 'Cristian Camilo Herrera Serna', 1000.00::numeric, DATE '2026-07-09', '0e771e70-410d-49d2-a876-1e567d23eaa3'::uuid),
    ('PplvMfjauXV1RPY647pM', 'Iván Darío Giraldo Giraldo',    3500.00::numeric, DATE '2026-07-10', '2c71bfe5-8cc0-409b-9a06-4f30c2843b72'::uuid)
), planes AS (
  INSERT INTO ikigaigm.payment_plans
    (user_id, integration_id, product_id, customer_id, customer_name, original_amount,
     currency, number_of_installments, installment_frequency, start_date, plan_status,
     project_id, product_uuid)
  SELECT '3dd88377-2ba0-41d0-8c4c-4548ed95e610', 'UBREqrQ6n5QEC8lFmyGt', '',
         n.customer_id, n.customer_name, n.monto,
         'USD', 1, 'Monthly'::ikigaigm.installment_frequency, n.fecha,
         'Active'::ikigaigm.payment_plan_status,
         '9077f0f0-603e-4af5-8033-444778267d9e', n.producto
  FROM nuevos n
  RETURNING plan_id, customer_name, original_amount, start_date
), cuotas AS (
  INSERT INTO ikigaigm.installments
    (plan_id, installment_number, due_date, scheduled_amount, paid_amount, payment_date, status)
  SELECT p.plan_id, 1, p.start_date, p.original_amount, p.original_amount,
         (p.start_date + TIME '12:00') AT TIME ZONE 'America/Bogota',
         'Paid'::ikigaigm.installment_status
  FROM planes p
  RETURNING installment_id, plan_id, paid_amount
)
INSERT INTO ikigaigm.commission_payouts
  (project_id, installment_id, plan_id, commission_rule_id, commission_type, user_id, role_id,
   rule_value_type, rule_value, installment_paid_amount, plan_total_amount,
   payout_amount, payout_amount_base, currency, base_currency, fx_rate, status)
SELECT '9077f0f0-603e-4af5-8033-444778267d9e', c.installment_id, c.plan_id,
       '14e92aed-dc04-4986-bb5e-81be8a13feb3', 'sale'::ikigaigm.commission_type,
       '3dd88377-2ba0-41d0-8c4c-4548ed95e610', '7e83b8bc-6f0b-4d7e-b63c-f8b6f557a13e',
       'pct_installment'::ikigaigm.commission_value_type, 10.0,
       c.paid_amount, p.original_amount,
       round(c.paid_amount * 0.10, 2), round(c.paid_amount * 0.10, 2),
       'USD', 'USD', 1.0, 'pending'::ikigaigm.payout_status
FROM cuotas c JOIN planes p USING (plan_id)
RETURNING plan_id, installment_id, payout_amount;

COMMIT;

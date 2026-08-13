-- Reparación de 3 registros de venta detectados en el cruce ONLY CLOSERS ↔ payment_plans
-- (docs/only-closers-informe.md §7). Evidencia: chat del grupo + crm_opportunities (won).
-- Convenciones copiadas de filas creadas por la app (planes 463/477):
--   integration DG = UBREqrQ6n5QEC8lFmyGt · proyecto DG = 9077f0f0-…
--   producto PA = 17d40000-… (Premium Academy 3 meses)
--   comisión: regla 14e92aed-… 'sale' pct_installment 10% rol closer 7e83b8bc-…, status pending

-- ============ CASO 1: Samuel Arango Correa (venta de Carlos González, 700 USD) ============
BEGIN;
WITH p AS (
  INSERT INTO ikigaigm.payment_plans
    (user_id, integration_id, product_id, customer_id, customer_name, original_amount,
     currency, number_of_installments, installment_frequency, start_date, plan_status,
     project_id, product_uuid)
  VALUES
    ('73afe0ee-0e87-4914-967d-7d18293f99f9', 'UBREqrQ6n5QEC8lFmyGt', '',
     'Jknd0KiUviD2oyCVmgY9', 'Samuel Arango Correa', 700.00,
     'USD', 2, 'Monthly', '2026-08-11', 'Active',
     '9077f0f0-603e-4af5-8033-444778267d9e', '17d40000-cf7f-4cba-bd03-817f72fa9dc3')
  RETURNING plan_id
), i AS (
  INSERT INTO ikigaigm.installments
    (plan_id, installment_number, due_date, scheduled_amount, paid_amount, payment_date, status)
  SELECT plan_id, 1, DATE '2026-08-11',  25.00,  25.00, TIMESTAMPTZ '2026-08-11 12:00:00-05', 'Paid'::ikigaigm.installment_status FROM p
  UNION ALL
  SELECT plan_id, 2, DATE '2026-08-12', 675.00, 675.00, TIMESTAMPTZ '2026-08-12 12:00:00-05', 'Paid'::ikigaigm.installment_status FROM p
  RETURNING installment_id, plan_id, paid_amount
)
INSERT INTO ikigaigm.commission_payouts
  (project_id, installment_id, plan_id, commission_rule_id, commission_type, user_id, role_id,
   rule_value_type, rule_value, installment_paid_amount, plan_total_amount,
   payout_amount, payout_amount_base, currency, base_currency, fx_rate, status)
SELECT '9077f0f0-603e-4af5-8033-444778267d9e', installment_id, plan_id,
       '14e92aed-dc04-4986-bb5e-81be8a13feb3', 'sale'::ikigaigm.commission_type,
       '73afe0ee-0e87-4914-967d-7d18293f99f9', '7e83b8bc-6f0b-4d7e-b63c-f8b6f557a13e',
       'pct_installment'::ikigaigm.commission_value_type, 10.0, paid_amount, 700.00,
       round(paid_amount*0.10,2), round(paid_amount*0.10,2), 'USD', 'USD', 1.0, 'pending'::ikigaigm.payout_status
FROM i
RETURNING plan_id, installment_id, payout_amount;
COMMIT;

-- ============ CASO 2: Kevin Felipe Delgado Hurtado (venta de Cristian Buelvas, 699 payfull) ============
BEGIN;
WITH p AS (
  INSERT INTO ikigaigm.payment_plans
    (user_id, integration_id, product_id, customer_id, customer_name, original_amount,
     currency, number_of_installments, installment_frequency, start_date, plan_status,
     project_id, product_uuid)
  VALUES
    ('c103c016-9126-49b1-96d6-6401b09976d0', 'UBREqrQ6n5QEC8lFmyGt', '',
     '8uBhLFdYZ2mkMXdocGAt', 'Kevin Felipe Delgado Hurtado', 699.00,
     'USD', 1, 'Monthly', '2026-07-16', 'Active',
     '9077f0f0-603e-4af5-8033-444778267d9e', '17d40000-cf7f-4cba-bd03-817f72fa9dc3')
  RETURNING plan_id
), i AS (
  INSERT INTO ikigaigm.installments
    (plan_id, installment_number, due_date, scheduled_amount, paid_amount, payment_date, status)
  SELECT plan_id, 1, DATE '2026-07-16', 699.00, 699.00, TIMESTAMPTZ '2026-07-16 11:00:00-05', 'Paid'::ikigaigm.installment_status FROM p
  RETURNING installment_id, plan_id, paid_amount
)
INSERT INTO ikigaigm.commission_payouts
  (project_id, installment_id, plan_id, commission_rule_id, commission_type, user_id, role_id,
   rule_value_type, rule_value, installment_paid_amount, plan_total_amount,
   payout_amount, payout_amount_base, currency, base_currency, fx_rate, status)
SELECT '9077f0f0-603e-4af5-8033-444778267d9e', installment_id, plan_id,
       '14e92aed-dc04-4986-bb5e-81be8a13feb3', 'sale'::ikigaigm.commission_type,
       'c103c016-9126-49b1-96d6-6401b09976d0', '7e83b8bc-6f0b-4d7e-b63c-f8b6f557a13e',
       'pct_installment'::ikigaigm.commission_value_type, 10.0, paid_amount, 699.00,
       round(paid_amount*0.10,2), round(paid_amount*0.10,2), 'USD', 'USD', 1.0, 'pending'::ikigaigm.payout_status
FROM i
RETURNING plan_id, installment_id, payout_amount;
COMMIT;

-- ============ CASO 3: Edwin Antiche (plan 430: PM 5.500 → PA 700; pagos 100 + 600; closer Ayrton) ============
BEGIN;
UPDATE ikigaigm.payment_plans
   SET original_amount = 700.00,
       number_of_installments = 2,
       product_uuid = '17d40000-cf7f-4cba-bd03-817f72fa9dc3'
 WHERE plan_id = 430;

-- la reserva de 100 que GHL registró como won el 10-jul
UPDATE ikigaigm.installments
   SET paid_amount = 100.00, payment_date = TIMESTAMPTZ '2026-07-10 20:22:26+00', status = 'Paid'
 WHERE installment_id = 2106;

-- el resto que completó los «700 usd PA» del 14-jul
UPDATE ikigaigm.installments
   SET scheduled_amount = 600.00, paid_amount = 600.00, due_date = DATE '2026-07-14',
       payment_date = TIMESTAMPTZ '2026-07-14 13:00:00-05', status = 'Paid'
 WHERE installment_id = 2107;

-- cuotas 3-5 del plan PM que ya no existe (todas $0 Scheduled, sin referencias)
DELETE FROM ikigaigm.installments WHERE installment_id IN (2108, 2109, 2110);

INSERT INTO ikigaigm.commission_payouts
  (project_id, installment_id, plan_id, commission_rule_id, commission_type, user_id, role_id,
   rule_value_type, rule_value, installment_paid_amount, plan_total_amount,
   payout_amount, payout_amount_base, currency, base_currency, fx_rate, status)
SELECT '9077f0f0-603e-4af5-8033-444778267d9e', i.installment_id, 430,
       '14e92aed-dc04-4986-bb5e-81be8a13feb3', 'sale'::ikigaigm.commission_type,
       '2ddc4ab9-a663-466b-80bb-c978468c9b26', '7e83b8bc-6f0b-4d7e-b63c-f8b6f557a13e',
       'pct_installment'::ikigaigm.commission_value_type, 10.0, i.paid_amount, 700.00,
       round(i.paid_amount*0.10,2), round(i.paid_amount*0.10,2), 'USD', 'USD', 1.0, 'pending'::ikigaigm.payout_status
FROM ikigaigm.installments i WHERE i.installment_id IN (2106, 2107)
RETURNING plan_id, installment_id, payout_amount;
COMMIT;

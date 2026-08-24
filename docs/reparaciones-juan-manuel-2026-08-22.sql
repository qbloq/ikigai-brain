-- Reparación 2026-08-22 — Juan Manuel Bedoya Amaya: fila del espejo sin dueño
-- Contexto (informe ONLY CLOSERS §8): Antonio pidió ayuda el 21-ago porque el
-- lead «no le sale en la app de reporte de pagos». Es la venta «Juan Manuel»
-- de julio del §4.3 (reportada en el grupo el 17-jul con los datos del cliente,
-- nunca registrada). En GHL la opportunity DlbJDQn7vGLO23u4UmDj está `won`
-- $700 desde el 21-jun-2026, assignedTo yyKZjv1fCTnj15bAGQmX = Cristian
-- Buelvas (users.integrations). En el espejo la fila quedó `open`, sin valor
-- y con user_id NULL — y la app filtra los leads por DUEÑO en el espejo
-- (verificado: las 6 ventas que Mateo registró el 20-ago tienen closer=Mateo
-- en el espejo, incluso una `open`). Sin dueño, Antonio no la ve.
-- Esta reparación alinea la fila del espejo con la fuente; no crea el plan de
-- pagos (eso lo hace Antonio desde la app, camino oficial).
--
-- Ejecutar (una txn, imprime antes/después):
--   bash -c 'source bash/lib/common.sh && psql_rw -v ON_ERROR_STOP=1 -f docs/reparaciones-juan-manuel-2026-08-22.sql'

BEGIN;

SELECT 'antes' AS etapa, id, status, monetary_value, user_id, updated_at
FROM ikigaigm.crm_opportunities WHERE id = 'f7111470-a059-485b-aef4-65a115170a12';

UPDATE ikigaigm.crm_opportunities
   SET user_id        = 'c103c016-9126-49b1-96d6-6401b09976d0',  -- Cristian Buelvas
       status         = 'won',
       monetary_value = 700.00,
       updated_at     = now()
 WHERE id = 'f7111470-a059-485b-aef4-65a115170a12';

SELECT 'despues' AS etapa, id, status, monetary_value, user_id, updated_at
FROM ikigaigm.crm_opportunities WHERE id = 'f7111470-a059-485b-aef4-65a115170a12';

COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2026-08-24 (segunda parte) — el plan de pagos, con los datos que Antonio
-- mandó al grupo el 24-ago 10h y confirmó después:
--   «La venta fue 19/06/2026 · Plan 5.5k reservó con 700 · cuota 1 de 960 →
--    3.840 · segunda cuota 960 → pendiente 2.880 · paga cuota los 19»
-- = Premium Mastermind full $5.500: reserva $700 (19-jun) + 5 cuotas de $960
--   los 19 de cada mes (jul, ago pagadas; sep, oct, nov pendientes).
--   700 + 5×960 = 5.500 ✓ · pagado 2.620 · pendiente 2.880.
-- Comisión: 10 % por cuota pagada (misma regla de todas las reparaciones)
--   → 70 + 96 + 96 = $262 pending a Cristian Buelvas.
-- Identidades: contacto GHL qQM6FQQ0DbDy9FJqhzMB · closer c103c016-9126-49b1-96d6-6401b09976d0
--   · producto PM full 39426991-5e68-4e53-b59c-967c6763bc59 · proyecto DG 9077f0f0-…

BEGIN;

WITH p AS (
  INSERT INTO ikigaigm.payment_plans
    (user_id, integration_id, product_id, customer_id, customer_name, original_amount,
     currency, number_of_installments, installment_frequency, start_date, plan_status,
     project_id, product_uuid)
  VALUES
    ('c103c016-9126-49b1-96d6-6401b09976d0', 'UBREqrQ6n5QEC8lFmyGt', '',
     'qQM6FQQ0DbDy9FJqhzMB', 'Juan Manuel Bedoya Amaya', 5500.00,
     'USD', 6, 'Monthly'::ikigaigm.installment_frequency, '2026-06-19',
     'Active'::ikigaigm.payment_plan_status,
     '9077f0f0-603e-4af5-8033-444778267d9e', '39426991-5e68-4e53-b59c-967c6763bc59')
  RETURNING plan_id, original_amount
), cuotas (n, monto, vence, pagado) AS (
  VALUES
    (1, 700.00::numeric, DATE '2026-06-19', true),
    (2, 960.00::numeric, DATE '2026-07-19', true),
    (3, 960.00::numeric, DATE '2026-08-19', true),
    (4, 960.00::numeric, DATE '2026-09-19', false),
    (5, 960.00::numeric, DATE '2026-10-19', false),
    (6, 960.00::numeric, DATE '2026-11-19', false)
), i AS (
  INSERT INTO ikigaigm.installments
    (plan_id, installment_number, due_date, scheduled_amount, paid_amount, payment_date, status)
  SELECT p.plan_id, c.n, c.vence, c.monto,
         CASE WHEN c.pagado THEN c.monto ELSE 0 END,
         CASE WHEN c.pagado THEN (c.vence + TIME '12:00') AT TIME ZONE 'America/Bogota' END,
         CASE WHEN c.pagado THEN 'Paid' ELSE 'Scheduled' END::ikigaigm.installment_status
  FROM p, cuotas c
  RETURNING installment_id, plan_id, paid_amount, status
)
INSERT INTO ikigaigm.commission_payouts
  (project_id, installment_id, plan_id, commission_rule_id, commission_type, user_id, role_id,
   rule_value_type, rule_value, installment_paid_amount, plan_total_amount,
   payout_amount, payout_amount_base, currency, base_currency, fx_rate, status)
SELECT '9077f0f0-603e-4af5-8033-444778267d9e', i.installment_id, i.plan_id,
       '14e92aed-dc04-4986-bb5e-81be8a13feb3', 'sale'::ikigaigm.commission_type,
       'c103c016-9126-49b1-96d6-6401b09976d0', '7e83b8bc-6f0b-4d7e-b63c-f8b6f557a13e',
       'pct_installment'::ikigaigm.commission_value_type, 10.0,
       i.paid_amount, p.original_amount,
       round(i.paid_amount * 0.10, 2), round(i.paid_amount * 0.10, 2),
       'USD', 'USD', 1.0, 'pending'::ikigaigm.payout_status
FROM i JOIN p USING (plan_id)
WHERE i.status = 'Paid'
RETURNING plan_id, installment_id, payout_amount;

-- Verificación en la misma txn
SELECT pp.plan_id, pp.customer_name, pp.original_amount, pp.number_of_installments,
       i.installment_number, i.scheduled_amount, i.paid_amount, i.due_date::date, i.status
FROM ikigaigm.payment_plans pp JOIN ikigaigm.installments i ON i.plan_id = pp.plan_id
WHERE pp.customer_id = 'qQM6FQQ0DbDy9FJqhzMB' ORDER BY i.installment_number;

COMMIT;

-- Anulación de los 3 planes de pago DUPLICADOS (docs/only-closers-informe.md §8).
--
-- Qué son: en los 3 casos el mismo cliente (mismo customer_id) tiene DOS planes
-- por el mismo monto creados con 45s–8min de diferencia — doble submit del
-- formulario de la app. En cada par, uno recibió los pagos y sus comisiones; el
-- gemelo quedó completamente vacío (cero cuotas pagadas, cero comisiones).
--
--   par                         real (se conserva)   fantasma (se anula)
--   Vero G           2.000 USD  336 (2.000 pagados)  337
--   Nikol Garcia       800 USD  452 (800 pagados)    454
--   Acevedo Morales    699 USD  464 (699 pagados)    465
--
-- Por qué ANULAR y no BORRAR: la línea del repo es «cruzar y ajustar, no
-- borrar» — un DELETE destruye la evidencia de que el doble submit ocurrió, que
-- es justo el dato que hay que vigilar. `Cancelled` deja la fila legible y la
-- saca de todos los reportes: cobranza.sh filtra por
-- `i.status IN ('Scheduled','Partial','Overdue')`.
--
-- Verificado antes de escribir: los 3 fantasmas NO tienen comisiones ni eventos
-- meta_capi asociados, y son exactamente los ÚNICOS 3 planes 'Active' sin una
-- sola cuota pagada en toda la tabla (no hay ventas legítimas recién creadas
-- que puedan confundirse con ellos).

BEGIN;

-- 1. las cuotas fantasma salen de la cola de cobranza
UPDATE ikigaigm.installments
   SET status = 'Cancelled'::ikigaigm.installment_status
 WHERE plan_id IN (337, 454, 465);

-- 2. los planes quedan marcados, no borrados
UPDATE ikigaigm.payment_plans
   SET plan_status = 'Cancelled'::ikigaigm.payment_plan_status
 WHERE plan_id IN (337, 454, 465);

-- 3. verificación dentro de la misma txn (si algo no cuadra, ROLLBACK a mano)
SELECT pp.plan_id, pp.customer_name, pp.plan_status,
       count(i.installment_id) cuotas,
       count(*) FILTER (WHERE i.status = 'Cancelled') canceladas
  FROM ikigaigm.payment_plans pp
  LEFT JOIN ikigaigm.installments i USING (plan_id)
 WHERE pp.plan_id IN (337, 454, 465)
 GROUP BY 1, 2, 3
 ORDER BY 1;

COMMIT;

-- 004_slice_compensacion.sql — Etapa 2, primer tier real: compensación para
-- Ejecutivos. APLICADA 2026-07-22 sobre la instancia de la org.
--
-- Contexto: la 003 §2b revocó el tier sensible COMPLETO a todo copiloto.
-- docs/roles/slices.md distingue: compensación (payroll/commission/economics/
-- revenue_share) es «tier aparte: solo Ejecutivo (●) y Director Comercial
-- (○ commissions de su equipo)». El dashboard financiero (bash/metrics/
-- dashboard.sh) la necesita — el primer copiloto Ejecutivo real la reclamó.
--
-- Mecánica del slice (el patrón de la Etapa 2): un rol-tier NOLOGIN agrupa
-- los GRANTs + una política RLS FOR SELECT; los roles LOGIN de los empleados
-- cuyo rol la merece se hacen miembros. Nada se des-revoca del base.
-- Pendiente: el ○ del Director Comercial (solo commissions de su equipo)
-- exige política con predicado — cuando se necesite, no antes.
--
-- Idempotente. Ejecuta el operador (rol admin).

BEGIN;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='ikigai_tier_compensacion') THEN
    CREATE ROLE ikigai_tier_compensacion NOLOGIN;
  END IF;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'commission_payouts','commission_rules','economics_ledger',
    'payroll_actuals','payroll_rules',
    'revenue_share_distributions','revenue_share_payouts','revenue_share_rules'
  ] LOOP
    EXECUTE format('GRANT SELECT ON ikigaigm.%I TO ikigai_tier_compensacion', t);
    EXECUTE format('DROP POLICY IF EXISTS tier_compensacion ON ikigaigm.%I', t);
    IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
               WHERE n.nspname='ikigaigm' AND c.relname=t AND c.relrowsecurity) THEN
      EXECUTE format('CREATE POLICY tier_compensacion ON ikigaigm.%I FOR SELECT TO ikigai_tier_compensacion USING (true)', t);
    END IF;
  END LOOP;
END $$;

-- Membresía: los copilotos de rol ejecutivo (al crear uno nuevo, añadirlo).
GRANT ikigai_tier_compensacion TO ikigai_lorenzo_cadavid, ikigai_juan_camilo_correa;

COMMIT;

-- Verificación ejecutada al aplicar (como ikigai_lorenzo_cadavid):
--   SELECT count(*) FROM ikigaigm.commission_payouts;   → 255 ✓
--   SELECT ... FROM ikigaigm.llmrouter_api_keys;        → permission denied ✓
--   bash/metrics/dashboard.sh --project "David Guerrero" --json → KPIs completos ✓

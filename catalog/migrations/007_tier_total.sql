-- 007_tier_total.sql — tier TOTAL de lectura para los roles de copiloto
-- Ejecutivo y Technology. APLICADA 2026-08-21 sobre la instancia de la org.
--
-- Decisión de Santiago (2026-08-21): «por ahora los roles Ejecutivo y
-- Technology tienen acceso a TODAS las tablas, pero solamente esos roles».
-- Hasta hoy la 003 §2b revocaba el tier sensible a TODO copiloto y la 004
-- devolvía solo compensación a los ejecutivos; en la práctica eso dejaba a
-- acceso.json (`dominios:*` → bash/ghl, bash/vturb) en contradicción con
-- Postgres: la cerca decía «sí» y `project_*_configs` respondía «permission
-- denied» en el laptop de Lorenzo. Este tier cierra la contradicción del lado
-- de la DB: incluye el runtime LLM (llmrouter_api_keys), el llavero
-- project_*_configs, compensación e identities — declarado, no implícito.
--
-- Mecánica (la del patrón Etapa 2, igual que la 004): un rol-tier NOLOGIN
-- agrupa los GRANTs SELECT + una política RLS FOR SELECT; los roles LOGIN de
-- los empleados cuyo rol lo merece se hacen miembros. Solo LECTURA: las
-- escrituras siguen siendo las del copiloto_base (tasks/IO/meeting_reports).
-- Nada se des-revoca del base — el resto de roles sigue sin el tier sensible.
--
-- La membresía YA NO se decide a mano: docs/roles/acceso.json (`tablas:"*"`)
-- es el mapa, y forja/bash/fleet/crear_alta.sh lo lee al dar de alta.
-- Aquí se listan los copilotos vivos de esos roles al momento de aplicar.
--
-- Idempotente. Ejecuta el operador (rol admin), envuelto en BEGIN/COMMIT.

BEGIN;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='ikigai_tier_total') THEN
    CREATE ROLE ikigai_tier_total NOLOGIN;
  END IF;
END $$;

GRANT USAGE ON SCHEMA ikigaigm TO ikigai_tier_total;
GRANT SELECT ON ALL TABLES IN SCHEMA ikigaigm TO ikigai_tier_total;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA ikigaigm TO ikigai_tier_total;
-- Tablas futuras del schema (creadas por el rol que corre esto) también.
ALTER DEFAULT PRIVILEGES IN SCHEMA ikigaigm
  GRANT SELECT ON TABLES TO ikigai_tier_total;

-- Política RLS FOR SELECT en TODA tabla con RLS del schema (las 89/101 que lo
-- tienen; sin política, RLS niega solo — el GRANT no basta).
DO $$
DECLARE t record;
BEGIN
  FOR t IN
    SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='ikigaigm' AND c.relkind='r' AND c.relrowsecurity
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS tier_total ON ikigaigm.%I', t.relname);
    EXECUTE format('CREATE POLICY tier_total ON ikigaigm.%I FOR SELECT TO ikigai_tier_total USING (true)', t.relname);
  END LOOP;
END $$;

-- Membresía al aplicar: ejecutivo (Lorenzo, Juan Camilo) + technology (Pablo).
-- Altas nuevas: crear_alta.sh lee acceso.json. Baja: REVOKE ikigai_tier_total FROM ikigai_<empleado>;
GRANT ikigai_tier_total TO ikigai_lorenzo_cadavid, ikigai_juan_camilo_correa, ikigai_pablo_gaviria;

COMMIT;

-- Verificación ejecutada al aplicar (como ikigai_lorenzo_cadavid):
--   SELECT count(*) FROM ikigaigm.project_vturb_video_configs;  → filas ✓
--   SELECT count(*) FROM ikigaigm.llmrouter_api_keys;           → filas ✓
--   has_table_privilege('ikigai_luis_david','ikigaigm.project_crm_configs','SELECT') → f ✓

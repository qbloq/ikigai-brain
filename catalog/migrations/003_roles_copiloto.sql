-- 003_roles_copiloto.sql — acceso por rol para copilotos, Etapa 1 (mínimo
-- privilegio). APLICADA 2026-07-22 sobre la instancia del org.
--
-- Problema: el .env de un copiloto llevaba el rol admin del cluster
-- (createrole/createdb/BYPASSRLS, escritura en schemas de otras orgs).
-- Este DDL crea el paquete de privilegios que un copiloto SÍ necesita.
--
-- Estructura (dos niveles):
--   ikigai_copiloto_base   NOLOGIN — el paquete de GRANTs + políticas RLS
--   ikigai_<empleado>      LOGIN   — miembro del base; uno por copiloto real.
--                                    current_user es la identidad que las
--                                    políticas de Etapa 2 usarán para el slice.
--
-- RLS: 89/97 tablas del schema ya tenían RLS habilitado (políticas existentes:
-- authenticated/service_role — la app). El copiloto necesita su propia
-- política; la de Etapa 1 es permisiva (USING true = ve toda la org, como el
-- DSN admin que reemplaza). ESE using ES el socket del slice de Etapa 2.
-- OJO: las políticas permisivas se OR-ean → Etapa 2 REEMPLAZA copiloto_acceso
-- con la versión recortada por rol, no añade otra encima.
--
-- Lecciones operativas (vividas al aplicar):
--   · psql NO interpola :'var' en -c — contraseñas SIEMPRE por stdin/heredoc.
--   · El pooler (Supavisor) tiene circuit breaker por IP ante fallos de auth
--     repetidos, y cachea credenciales un momento tras un ALTER PASSWORD:
--     probar la conexión UNA vez y esperar ante fallo, no reintentar en loop.
--   · Usuario vía pooler: ikigai_<empleado>.<project-ref>.
--
-- Idempotente. Ejecuta el operador (rol admin), envuelto en BEGIN/COMMIT.

BEGIN;

-- ── 1 · El paquete de privilegios del cerebro ──────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='ikigai_copiloto_base') THEN
    CREATE ROLE ikigai_copiloto_base NOLOGIN;
  END IF;
END $$;

-- Alcance: SOLO el schema de la org (ningún otro schema otorga USAGE a
-- PUBLIC, así que el rol no los alcanza por construcción).
GRANT USAGE ON SCHEMA ikigaigm TO ikigai_copiloto_base;
GRANT SELECT ON ALL TABLES IN SCHEMA ikigaigm TO ikigai_copiloto_base;

-- Escritura: exactamente la superficie de los scripts psql_rw de cara al
-- copiloto (create_task, add_comment, reassign, set_archetype, cancel_task,
-- update_task_io, materialize_io, upsert_report). Lo que NO está: DELETE de
-- tasks (wipe_tasks es de operador; cancel_task marca status) y todo DDL
-- (sync_catalog es de operador).
GRANT INSERT ON ikigaigm.tasks, ikigaigm.task_inputs, ikigaigm.task_outputs,
                ikigaigm.task_acceptance_criteria, ikigaigm.task_comments,
                ikigaigm.meeting_reports TO ikigai_copiloto_base;
GRANT UPDATE ON ikigaigm.tasks, ikigaigm.task_inputs, ikigaigm.task_outputs,
                ikigaigm.task_acceptance_criteria, ikigaigm.meeting_reports
  TO ikigai_copiloto_base;
GRANT DELETE ON ikigaigm.task_inputs, ikigaigm.task_outputs,
                ikigaigm.task_acceptance_criteria TO ikigai_copiloto_base;

-- sync_catalog.sh (operador) DROPea y recrea el catálogo: sin esto, cada sync
-- borraría el SELECT del copiloto sobre las tablas nuevas.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA ikigaigm
  GRANT SELECT ON TABLES TO ikigai_copiloto_base;

-- ── 2 · Política RLS del copiloto (una por tabla con RLS) ──────────────────
DO $$
DECLARE t record;
BEGIN
  FOR t IN
    SELECT c.relname
    FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
    WHERE ns.nspname='ikigaigm' AND c.relkind='r' AND c.relrowsecurity
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS copiloto_acceso ON ikigaigm.%I', t.relname);
    EXECUTE format(
      'CREATE POLICY copiloto_acceso ON ikigaigm.%I FOR ALL TO ikigai_copiloto_base USING (true) WITH CHECK (true)',
      t.relname);
  END LOOP;
END $$;

-- ── 2b · Tier sensible: FUERA de todo copiloto (aplicado 2026-07-22) ────────
-- El GRANT SELECT ON ALL TABLES del §1 alcanzaba el tier que docs/roles/
-- slices.md excluye de TODO slice. Se revoca por lista explícita (cinturón:
-- REVOKE; tirantes: fuera la política RLS). Idempotente. OJO: el ALTER
-- DEFAULT PRIVILEGES del §1 re-abriría una tabla sensible NUEVA — al crear
-- una, añadirla aquí y re-aplicar.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    -- runtime agéntico / LLM (14, dominio del grafo)
    'llm_calls','llmrouter_api_keys','prompt_sections','prompt_budgets',
    'runners','runner_runs','workers','worker_runs','skills','output_channels',
    'graph_conversations','graph_messages','sql_conversations','sql_messages',
    -- llavero estructural de integraciones (7)
    'project_crm_configs','project_google_configs','project_meta_configs',
    'project_notion_configs','project_panda_video_configs',
    'project_vturb_video_configs','project_whatsapp_configs',
    -- compensación (8)
    'payroll_actuals','payroll_rules','commission_payouts','commission_rules',
    'economics_ledger','revenue_share_distributions','revenue_share_payouts',
    'revenue_share_rules',
    -- material de autenticación (2)
    'identities','user_evolution_instances'
  ] LOOP
    EXECUTE format('REVOKE ALL ON ikigaigm.%I FROM ikigai_copiloto_base', t);
    EXECUTE format('DROP POLICY IF EXISTS copiloto_acceso ON ikigaigm.%I', t);
  END LOOP;
END $$;

COMMIT;

-- ── 3 · Alta de UN copiloto (plantilla; la contraseña por stdin, jamás -c) ──
--   CREATE ROLE ikigai_<empleado> LOGIN PASSWORD :'pwd'
--     NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS
--     CONNECTION LIMIT 5
--     IN ROLE ikigai_copiloto_base;
--
--   DSN del copiloto (pooler): usuario ikigai_<empleado>.<project-ref>,
--   su contraseña, y el host del pooler — armados como URL postgresql://
--   (no se escribe aquí la forma completa: dispararía el escáner de secretos)
--
-- Baja: REVOKE ikigai_copiloto_base FROM ikigai_<empleado>;
--       ALTER ROLE ikigai_<empleado> NOLOGIN;
--
-- Aplicado 2026-07-22: ikigai_luis_david (primer copiloto real).
--
-- ── Verificación E2E ejecutada al aplicar ──────────────────────────────────
--   8 scripts de lectura byte-idénticos vs admin · INSERT de copiloto OK ·
--   DENEGADOS: DELETE tasks / CREATE TABLE / viasegura.* / auth.*

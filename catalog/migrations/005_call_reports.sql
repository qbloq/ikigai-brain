-- Migration 005 — Reportes de llamada generados por el Cerebro (producción)
-- Schema: ikigaigm.  Applied: 2026-08-13.
--
-- WHY: hasta hoy el reporte de análisis de una llamada lo generaba gemini en el
-- API y vivía en `meeting_reports`; el pipeline del Cerebro (3 tiradas de
-- contexto limpio + mediana por ítem, ver docs/bant-prompt-informe.md) vivía en
-- una sqlite local declarada «prototipo». Decisión de Santiago 2026-08-13: las
-- operaciones de la plataforma se van portando al Cerebro y **de aquí en
-- adelante producción es lo que se genera aquí**. Un reporte que solo existe en
-- una sqlite del portátil no es producción — tiene que estar donde producción
-- lee, que es Postgres.
--
-- EL REEMPLAZO (decisión de Santiago, 2026-08-13): el reporte del Cerebro
-- REEMPLAZA al de gemini — también en `meeting_reports`, que es de donde lee la
-- plataforma. Un reporte que la plataforma no muestra no reemplazó a nada.
-- Pero `meeting_reports` tiene UNIQUE (meeting_id): escribir encima BORRA el de
-- gemini, y el de gemini es la celda de CONTROL de las cohortes 1-5 (el AUC
-- 0.804 vs 0.655 que justificó este cambio se mide contra él). Perderlo hace
-- irrepetible el experimento que motivó el reemplazo.
-- Por eso el orden es: **congelar primero, reemplazar después**.
--   · call_reports_gemini — snapshot íntegro de lo que gemini escribió, tomado
--     ANTES del primer sobrescrito. Es la celda de control, congelada.
--   · meeting_reports     — pasa a ser el ESCAPARATE: lo que la plataforma
--     muestra. Nuestro pipeline lo upsertea.
--   · call_reports        — la fuente de verdad del Cerebro, versionada y con
--     procedencia. `meeting_reports` guarda un jsonb y nada más; nuestro
--     reporte NO es un jsonb suelto: es un agregado con variante de prompt,
--     modelo, N tiradas, medianas, RANGOS, ítems en baja confianza, votos de
--     arquetipo y cuál tirada dio la narrativa. Esa procedencia es lo que
--     permite leerlo con honestidad — un puntaje sin su rango no dice si es
--     señal o ruido — y va en columnas, no enterrada en el blob.
--     Regenerar nunca sobreescribe: `generacion+1`.
--
-- QUÉ AGREGA:
--   · call_reports          — el agregado (una fila por meeting × generación)
--   · call_report_tiradas   — las N tiradas crudas (el agregado es derivable,
--                             las tiradas no; sin ellas no hay auditoría del
--                             ruido ni recálculo de la mediana)
--   · call_reports_gemini   — la celda de control congelada
--   · call_report_vigente   — la VISTA que resuelve «cuál reporte manda»:
--                             cerebro (última generación) si existe, si no lo
--                             que haya en meeting_reports. Cada fila declara su
--                             `fuente`.
--
-- CÓMO SE CONSUME (regla que hay que sostener):
--   · Los scripts OPERATIVOS del dominio calls (calls.sh, call_show.sh,
--     call_stats.sh, call_objections.sh, lead_profile.sh, closer_dashboard.sh)
--     leen la VISTA — ven el reporte del Cerebro apenas existe, y saben de qué
--     fuente viene.
--   · Los scripts del EXPERIMENTO (bant_diff, comparativo_bant,
--     importar_produccion, validacion_plata, rasgo_plata, conversion_real,
--     lead_score_model) leen `call_reports_gemini`, NUNCA `meeting_reports`:
--     desde hoy esa tabla contiene reportes NUESTROS, así que seguir leyéndola
--     como «producción» convierte el control en el tratamiento y pudre todos
--     los AUC en silencio.
--
-- Idempotente: se puede correr varias veces. El snapshot solo inserta lo que
-- falte (ON CONFLICT DO NOTHING) — nunca re-captura encima de sí mismo, que es
-- justo lo que lo destruiría después del primer reemplazo.

BEGIN;

CREATE TABLE IF NOT EXISTS ikigaigm.call_reports (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id        uuid NOT NULL REFERENCES ikigaigm.meetings(id),
  generacion        integer NOT NULL DEFAULT 1,

  -- procedencia del pipeline
  prompt_variante   text NOT NULL,            -- p. ej. 'mejorado2'
  modelo            text NOT NULL,            -- modelo que corrió las tiradas
  n_tiradas         integer NOT NULL CHECK (n_tiradas >= 2),

  -- puntajes: mediana por ítem entre tiradas
  bant_budget       numeric NOT NULL,
  bant_authority    numeric NOT NULL,
  bant_need         numeric NOT NULL,
  bant_timeline     numeric NOT NULL,

  -- dispersión entre tiradas: sin esto un puntaje no se puede leer
  rango_budget      numeric NOT NULL,
  rango_authority   numeric NOT NULL,
  rango_need        numeric NOT NULL,
  rango_timeline    numeric NOT NULL,
  baja_confianza    text[]  NOT NULL DEFAULT '{}',  -- ítems con rango > umbral
  umbral_confianza  numeric NOT NULL DEFAULT 10,

  -- arquetipo por voto de mayoría
  arquetipo         text,
  arquetipo_votos   jsonb   NOT NULL DEFAULT '{}'::jsonb,
  arquetipo_unanime boolean NOT NULL DEFAULT false,

  tirada_narrativa  integer,                  -- cuál tirada aportó el texto
  report            jsonb   NOT NULL,         -- el canon de 6 secciones + _generacion
  generado_at       timestamptz NOT NULL DEFAULT now(),
  created_at        timestamptz NOT NULL DEFAULT now(),

  UNIQUE (meeting_id, generacion)
);

CREATE INDEX IF NOT EXISTS call_reports_meeting_idx
  ON ikigaigm.call_reports (meeting_id, generacion DESC);

CREATE TABLE IF NOT EXISTS ikigaigm.call_report_tiradas (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  call_report_id uuid NOT NULL REFERENCES ikigaigm.call_reports(id) ON DELETE CASCADE,
  n              integer NOT NULL,
  report         jsonb   NOT NULL,
  UNIQUE (call_report_id, n)
);

-- La celda de control, congelada ANTES del primer reemplazo. Sin esta tabla el
-- experimento BANT (docs/bant-prompt-informe.md) deja de ser reproducible en el
-- instante en que upsertamos el primer reporte propio en meeting_reports.
CREATE TABLE IF NOT EXISTS ikigaigm.call_reports_gemini (
  meeting_id  uuid PRIMARY KEY REFERENCES ikigaigm.meetings(id),
  report      jsonb NOT NULL,
  created_at  timestamptz,          -- el de meeting_reports (cuándo lo generó gemini)
  capturado_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO ikigaigm.call_reports_gemini (meeting_id, report, created_at)
SELECT mr.meeting_id, mr.report, mr.created_at
FROM ikigaigm.meeting_reports mr
JOIN ikigaigm.meetings m ON m.id = mr.meeting_id
WHERE m.meeting_type = 'call'
ON CONFLICT (meeting_id) DO NOTHING;

-- Cuál reporte manda por llamada. `fuente` viaja en la fila: ningún consumidor
-- debería tener que adivinar si está leyendo al Cerebro o al escaparate.
CREATE OR REPLACE VIEW ikigaigm.call_report_vigente AS
SELECT DISTINCT ON (u.meeting_id)
       u.meeting_id, u.report, u.fuente, u.generacion, u.generado_at,
       u.prompt_variante, u.modelo, u.baja_confianza
FROM (
  SELECT cr.meeting_id, cr.report, 'cerebro'::text AS fuente, cr.generacion,
         cr.generado_at, cr.prompt_variante, cr.modelo, cr.baja_confianza
  FROM ikigaigm.call_reports cr
  UNION ALL
  SELECT mr.meeting_id, mr.report, 'meeting_reports'::text, 0,
         mr.created_at, NULL, NULL, '{}'::text[]
  FROM ikigaigm.meeting_reports mr
  JOIN ikigaigm.meetings m ON m.id = mr.meeting_id
  WHERE m.meeting_type = 'call'
) u
ORDER BY u.meeting_id, (u.fuente = 'cerebro') DESC, u.generacion DESC;

COMMIT;

#!/usr/bin/env node
// backfill-ghl.js — **[WRITE]** rellena en la base las oportunidades y los
// contactos que existen en GHL y el ingestor nunca trajo.
//
// Contexto: `crm_opportunities` / `crm_contacts` son un espejo de GHL que
// mantiene un ingestor externo. Ese ingestor pagina de a 100 por corrida y se
// dispara a mano, así que cada vez que pasan más de ~10 días entre corridas el
// excedente se pierde en silencio. Esto repara el hueco hacia atrás; NO
// reemplaza al ingestor ni lo arregla.
//
// Uso:
//   node scripts/backfill-ghl.js [opciones]
//
//   --months N        ventana: los últimos N meses calendario, contando el
//                     actual (default 4 → mayo, junio, julio y agosto si hoy
//                     es agosto). Alternativa exacta: --from YYYY-MM-DD
//   --from FECHA      corte explícito; gana sobre --months
//   --project N       solo ese proyecto (fragmento del nombre)
//   --pipelines P     'configured' (default) = solo los pipelines que ya
//                     espejamos (crm_pipelines). 'all' = todos los de GHL,
//                     creando las filas de pipeline que falten (is_active=false
//                     para no alterar lo que hoy muestran los tableros)
//   --contacts C      'linked' (default) = solo los contactos que referencian
//                     las oportunidades insertadas. 'all' = además, todo
//                     contacto creado dentro de la ventana (recorre el listado
//                     completo de contactos: lento)
//   --dry-run         hace todo el trabajo y al final ROLLBACK — no escribe
//   --json            resumen machine-readable
//
// Política: una sola transacción; imprime conteos antes y después; los INSERT
// llevan ON CONFLICT DO NOTHING, así que correrlo dos veces no duplica. Nunca
// hace UPDATE ni DELETE: solo agrega lo que falta.

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const REPO_ROOT = path.resolve(__dirname, "..");

// --- Fork guard --------------------------------------------------------------
// Igual que bash/ghl/: las credenciales del CRM son del cerebro, no de un fork.
if (fs.existsSync(path.join(REPO_ROOT, "copilot.json"))) {
  console.error("backfill-ghl: este script es solo del cerebro — un copiloto no maneja credenciales del CRM.");
  process.exit(3);
}

// --- env ---------------------------------------------------------------------
function loadEnv(key) {
  if (process.env[key]) return process.env[key];
  const envPath = path.join(REPO_ROOT, ".env");
  if (fs.existsSync(envPath)) {
    const re = new RegExp(`^\\s*${key}\\s*=\\s*(.*)\\s*$`);
    for (const line of fs.readFileSync(envPath, "utf8").split("\n")) {
      const m = line.match(re);
      if (m) return m[1].replace(/^["']|["']$/g, "");
    }
  }
  return null;
}
const DATABASE_URL = loadEnv("DATABASE_URL");
const SCHEMA = loadEnv("DB_SCHEMA");
const TZ = loadEnv("BRAIN_TZ") || "America/Bogota";
if (!DATABASE_URL || !SCHEMA) {
  console.error("Falta DATABASE_URL o DB_SCHEMA en .env");
  process.exit(1);
}

const RO = ["-c default_transaction_read_only=on", `-c search_path=${SCHEMA},public`, `-c timezone=${TZ}`].join(" ");
const RW = [`-c search_path=${SCHEMA},public`, `-c timezone=${TZ}`].join(" ");

function psql(sql, { write = false } = {}) {
  return execFileSync("psql", [DATABASE_URL, "-v", "ON_ERROR_STOP=1", "--pset", "pager=off", "-tAc", sql], {
    encoding: "utf8",
    maxBuffer: 512 * 1024 * 1024,
    env: { ...process.env, PGOPTIONS: write ? RW : RO },
  });
}
function psqlScript(sql) {
  // WRITE path: the whole transaction arrives on stdin as one script.
  return execFileSync("psql", [DATABASE_URL, "-v", "ON_ERROR_STOP=1", "--pset", "pager=off", "-f", "-"], {
    input: sql,
    encoding: "utf8",
    maxBuffer: 512 * 1024 * 1024,
    env: { ...process.env, PGOPTIONS: RW },
  });
}
function queryJson(sql) {
  const out = psql(sql).trim();
  return out ? JSON.parse(out) : null;
}

// --- SQL literals ------------------------------------------------------------
const lit = (v) => (v === null || v === undefined || v === "" ? "NULL" : `'${String(v).replace(/'/g, "''")}'`);
const num = (v) => (v === null || v === undefined || v === "" || Number.isNaN(Number(v)) ? "NULL" : Number(v));
const textArray = (a) =>
  !Array.isArray(a) || a.length === 0 ? "NULL" : `ARRAY[${a.map((x) => lit(String(x))).join(",")}]::text[]`;
const jsonb = (o) => (o && Object.keys(o).length ? `${lit(JSON.stringify(o))}::jsonb` : "NULL");

// --- CLI ---------------------------------------------------------------------
const args = process.argv.slice(2);
const opt = { months: 4, from: null, project: null, pipelines: "configured", contacts: "linked", dryRun: false, json: false };
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === "--months") opt.months = parseInt(args[++i], 10);
  else if (a === "--from") opt.from = args[++i];
  else if (a === "--project") opt.project = args[++i];
  else if (a === "--pipelines") opt.pipelines = args[++i];
  else if (a === "--contacts") opt.contacts = args[++i];
  else if (a === "--dry-run") opt.dryRun = true;
  else if (a === "--json") opt.json = true;
  else if (a === "-h" || a === "--help") {
    console.log(fs.readFileSync(__filename, "utf8").split("\n").filter((l) => l.startsWith("//")).map((l) => l.slice(3)).join("\n"));
    process.exit(0);
  } else {
    console.error(`Unknown arg: ${a}`);
    process.exit(2);
  }
}
if (!["configured", "all"].includes(opt.pipelines)) { console.error("--pipelines: configured | all"); process.exit(2); }
if (!["linked", "all"].includes(opt.contacts)) { console.error("--contacts: linked | all"); process.exit(2); }

// Ventana: primer día del mes, N-1 meses hacia atrás desde el mes actual.
function cutoffDate() {
  if (opt.from) return opt.from;
  const now = new Date();
  const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - (opt.months - 1), 1));
  return d.toISOString().slice(0, 10);
}
const CUTOFF = cutoffDate();

// --- GHL ---------------------------------------------------------------------
const GHL_BASE = process.env.GHL_BASE || "https://services.leadconnectorhq.com";
const GHL_VERSION = "2021-07-28";

async function ghl(token, pathQ) {
  const res = await fetch(GHL_BASE + pathQ, {
    headers: { Authorization: `Bearer ${token}`, Version: GHL_VERSION, Accept: "application/json" },
  });
  if (!res.ok) throw new Error(`GHL HTTP ${res.status} — ${pathQ.split("?")[0]}: ${(await res.text()).slice(0, 200)}`);
  return res.json();
}

// Walks GHL's cursor pagination. `stop` can end the walk early (the listings
// come newest-first, so once we are past the cutoff there is nothing left to
// gain by pulling the rest of the history).
async function ghlAll(token, endpoint, key, locParam, locationId, stop) {
  const items = [];
  const seen = new Set();
  let after = null, afterId = null;
  for (;;) {
    const qs = new URLSearchParams({ [locParam]: locationId, limit: "100" });
    if (afterId) { qs.set("startAfterId", afterId); if (after) qs.set("startAfter", String(after)); }
    const page = await ghl(token, `${endpoint}?${qs}`);
    const batch = page[key] || [];
    for (const it of batch) {
      if (it.id && !seen.has(it.id)) { seen.add(it.id); items.push(it); }
    }
    const meta = page.meta || {};
    if (batch.length < 100 || !meta.startAfterId || meta.startAfterId === afterId) break;
    if (stop && batch.length && stop(batch[batch.length - 1])) break;
    afterId = meta.startAfterId;
    after = meta.startAfter;
  }
  return items;
}

// --- main --------------------------------------------------------------------
(async () => {
  const configs = queryJson(`
    SELECT coalesce(json_agg(row_to_json(q)), '[]'::json) FROM (
      SELECT c.project_id, p.name AS project, c.location_id, c.api_key_encrypted AS token
      FROM project_crm_configs c JOIN projects p ON p.id = c.project_id
      WHERE c.provider='ghl' AND c.api_key_encrypted IS NOT NULL
        ${opt.project ? `AND p.name ILIKE ${lit("%" + opt.project + "%")}` : ""}
      ORDER BY p.name) q;`);

  if (!configs.length) { console.error("Ningún proyecto con integración GHL coincide."); process.exit(1); }

  // assigned_to (id de usuario en GHL) -> users.id, aprendido de lo que el
  // ingestor ya resolvió. Lo que no esté en ese mapa queda con user_id NULL:
  // preferimos un hueco explícito a una atribución inventada.
  const userMap = new Map(
    (queryJson(`
      SELECT coalesce(json_agg(row_to_json(q)), '[]'::json) FROM (
        SELECT DISTINCT assigned_to, user_id::text FROM crm_opportunities
        WHERE assigned_to IS NOT NULL AND user_id IS NOT NULL) q;`) || []
    ).map((r) => [r.assigned_to, r.user_id])
  );

  const stmts = [];
  const summary = [];

  for (const cfg of configs) {
    const before = queryJson(`
      SELECT json_build_object(
        'contactos', (SELECT count(*) FROM crm_contacts WHERE project_id=${lit(cfg.project_id)}),
        'opps',      (SELECT count(*) FROM crm_opportunities WHERE project_id=${lit(cfg.project_id)}));`);

    const pipes = queryJson(`
      SELECT coalesce(json_agg(row_to_json(q)), '[]'::json) FROM (
        SELECT id::text, ghl_pipeline_id FROM crm_pipelines WHERE project_id=${lit(cfg.project_id)}) q;`);
    const pipeByGhl = new Map(pipes.map((p) => [p.ghl_pipeline_id, p.id]));

    process.stderr.write(`· ${cfg.project}: consultando GHL…\n`);
    const opps = await ghlAll(cfg.token, "/opportunities/search", "opportunities", "location_id", cfg.location_id);
    const inWindow = opps.filter((o) => (o.createdAt || "") >= CUTOFF);

    // Pipelines nuevos (solo con --pipelines all)
    let newPipes = [];
    if (opt.pipelines === "all") {
      const wanted = [...new Set(inWindow.map((o) => o.pipelineId).filter(Boolean))].filter((g) => !pipeByGhl.has(g));
      if (wanted.length) {
        const all = (await ghl(cfg.token, `/opportunities/pipelines?locationId=${cfg.location_id}`)).pipelines || [];
        newPipes = all.filter((p) => wanted.includes(p.id));
        for (const p of newPipes) {
          stmts.push(
            `INSERT INTO crm_pipelines (project_id, ghl_pipeline_id, ghl_pipeline_name, stages, is_active)
             VALUES (${lit(cfg.project_id)}, ${lit(p.id)}, ${lit(p.name || p.id)}, ${jsonb(p.stages || [])}, false)
             ON CONFLICT (project_id, ghl_pipeline_id) DO NOTHING;`
          );
        }
      }
    }
    const pipelineOk = (g) => pipeByGhl.has(g) || newPipes.some((p) => p.id === g);
    const scoped = inWindow.filter((o) => o.pipelineId && pipelineOk(o.pipelineId));
    const skippedPipeline = inWindow.length - scoped.length;

    const haveOpps = new Set(
      psql(`SELECT ghl_opportunity_id FROM crm_opportunities WHERE project_id=${lit(cfg.project_id)};`)
        .split("\n").map((s) => s.trim()).filter(Boolean)
    );
    const missingOpps = scoped.filter((o) => !haveOpps.has(o.id));

    // Contactos: los que referencian las opps que vamos a insertar, más —con
    // --contacts all— todo contacto creado dentro de la ventana.
    const haveContacts = new Set(
      psql(`SELECT ghl_contact_id FROM crm_contacts WHERE project_id=${lit(cfg.project_id)};`)
        .split("\n").map((s) => s.trim()).filter(Boolean)
    );
    const wantContacts = new Map();
    if (opt.contacts === "all") {
      process.stderr.write(`  … recorriendo contactos (ventana desde ${CUTOFF})\n`);
      const all = await ghlAll(cfg.token, "/contacts/", "contacts", "locationId", cfg.location_id);
      for (const c of all) {
        const added = (c.dateAdded || "").slice(0, 10);
        if (added >= CUTOFF && !haveContacts.has(c.id)) wantContacts.set(c.id, c);
      }
    }
    const linkedIds = [...new Set(missingOpps.map((o) => o.contactId).filter(Boolean))].filter(
      (id) => !haveContacts.has(id) && !wantContacts.has(id)
    );
    if (linkedIds.length) process.stderr.write(`  … trayendo ${linkedIds.length} contactos referenciados\n`);
    for (const id of linkedIds) {
      try {
        const c = (await ghl(cfg.token, `/contacts/${id}`)).contact;
        if (c) wantContacts.set(c.id, c);
      } catch { /* contacto borrado en GHL: la opp entra con contact_id NULL */ }
    }

    for (const c of wantContacts.values()) {
      stmts.push(
        `INSERT INTO crm_contacts (project_id, ghl_contact_id, first_name, last_name, email, phone, tags, custom_fields, user_id)
         VALUES (${lit(cfg.project_id)}, ${lit(c.id)}, ${lit(c.firstName)}, ${lit(c.lastName)}, ${lit(c.email)},
                 ${lit(c.phone)}, ${textArray(c.tags)}, ${jsonb(c.customFields)},
                 ${lit(userMap.get(c.assignedTo) || null)}::uuid)
         ON CONFLICT (project_id, ghl_contact_id) DO NOTHING;`
      );
    }

    for (const o of missingOpps) {
      const pipeSub = `(SELECT id FROM crm_pipelines WHERE project_id=${lit(cfg.project_id)} AND ghl_pipeline_id=${lit(o.pipelineId)})`;
      const contactSub = o.contactId
        ? `(SELECT id FROM crm_contacts WHERE project_id=${lit(cfg.project_id)} AND ghl_contact_id=${lit(o.contactId)})`
        : "NULL";
      stmts.push(
        `INSERT INTO crm_opportunities (project_id, pipeline_id, contact_id, ghl_opportunity_id, name, ghl_stage_id,
                                        status, monetary_value, assigned_to, user_id, created_date, last_status_change_at)
         VALUES (${lit(cfg.project_id)}, ${pipeSub}, ${contactSub}, ${lit(o.id)}, ${lit(o.name || "(sin nombre)")},
                 ${lit(o.pipelineStageId)}, ${lit(o.status || "open")}, ${num(o.monetaryValue)}, ${lit(o.assignedTo)},
                 ${lit(userMap.get(o.assignedTo) || null)}::uuid, ${lit(o.createdAt)}::timestamptz,
                 ${lit(o.lastStatusChangeAt)}::timestamptz)
         ON CONFLICT (project_id, ghl_opportunity_id) DO NOTHING;`
      );
    }

    summary.push({
      proyecto: cfg.project,
      ventana_desde: CUTOFF,
      opps_en_ventana: inWindow.length,
      opps_fuera_de_pipeline: skippedPipeline,
      opps_a_insertar: missingOpps.length,
      contactos_a_insertar: wantContacts.size,
      pipelines_nuevos: newPipes.length,
      antes: before,
    });
  }

  const total = summary.reduce((a, s) => a + s.opps_a_insertar + s.contactos_a_insertar, 0);
  if (!total && !stmts.length) {
    console.log(`Nada que rellenar desde ${CUTOFF}: el espejo ya tiene todo lo que GHL reporta en esa ventana.`);
    process.exit(0);
  }

  const proj = summary.map((s) => lit(s.proyecto)).join(",");
  const countsSql = `
    SELECT p.name AS proyecto,
           (SELECT count(*) FROM crm_contacts      WHERE project_id=p.id) AS contactos,
           (SELECT count(*) FROM crm_opportunities WHERE project_id=p.id) AS opps
    FROM projects p WHERE p.name IN (${proj}) ORDER BY 1;`;

  const script = [
    "BEGIN;",
    `\\echo '--- ANTES ---'`,
    countsSql,
    // Los INSERT van con la salida silenciada: son cientos y su estado línea a
    // línea no dice nada; lo que importa es el antes/después.
    "\\o /dev/null",
    ...stmts,
    "\\o",
    `\\echo '--- DESPUÉS ---'`,
    countsSql,
    opt.dryRun ? "ROLLBACK;" : "COMMIT;",
  ].join("\n");

  if (opt.json) {
    console.log(JSON.stringify({ cutoff: CUTOFF, dry_run: opt.dryRun, resumen: summary }, null, 2));
  } else {
    console.log(`\nVentana: desde ${CUTOFF}${opt.dryRun ? "   [DRY RUN — se hace ROLLBACK]" : ""}`);
    for (const s of summary) {
      console.log(`\n  ${s.proyecto}`);
      console.log(`    oportunidades en la ventana (GHL) : ${s.opps_en_ventana}`);
      if (s.opps_fuera_de_pipeline)
        console.log(`    fuera de los pipelines espejados  : ${s.opps_fuera_de_pipeline}  (--pipelines all para incluirlas)`);
      if (s.pipelines_nuevos) console.log(`    pipelines nuevos a crear          : ${s.pipelines_nuevos}`);
      console.log(`    oportunidades a insertar          : ${s.opps_a_insertar}`);
      console.log(`    contactos a insertar              : ${s.contactos_a_insertar}`);
    }
  }

  process.stderr.write(`\nEjecutando ${stmts.length} sentencias en una transacción…\n`);
  console.log(psqlScript(script));
})().catch((e) => {
  console.error(`backfill-ghl: ${e.message}`);
  process.exit(1);
});

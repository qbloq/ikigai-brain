// meetico client — the viz's bridge to the task backend for artifact BINDING.
//
// Binding (associating an I/O with a concrete artifact instance — *which* Google
// Doc) needs the resolver engine + Google/Notion credentials, which live in
// meetico, not in our read-only bash layer. So the IO editor's "Vincular" action
// proxies to meetico's I/O Review API instead of writing the jsonb ourselves.
//
//   POST /tasks/io-review/bind-preview          resolve a locator, no persist
//   POST /tasks/io-review/{kind}/{id}/bind      persist artifact_type_id + reference
//
// meetico runs over HTTPS with a self-signed cert (rejectUnauthorized:false) and
// authenticates with a service JWT. Both come from .env (the node process doesn't
// inherit them — the bash data layer loads .env itself, so we parse it here too).

const https = require("node:https");
const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const { URL } = require("node:url");
const { REPO_ROOT } = require("./datasources");

// Minimal .env reader (KEY=VALUE, ignores comments/blank/quotes). Cached.
let ENV = null;
function dotenv() {
  if (ENV) return ENV;
  ENV = {};
  try {
    for (const line of fs.readFileSync(path.join(REPO_ROOT, ".env"), "utf8").split("\n")) {
      const m = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/.exec(line);
      if (!m || line.trim().startsWith("#")) continue;
      let v = m[2].trim();
      if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
      ENV[m[1]] = v;
    }
  } catch {
    /* no .env → ENV stays {} */
  }
  return ENV;
}

function cfg() {
  const env = { ...dotenv(), ...process.env };
  return {
    base: env.MEETICO_BASE || "https://127.0.0.1:5000",
    token: env.MEETICO_JWT_TOKEN || "",
  };
}

// POST a JSON body to a meetico /tasks path; resolve to parsed JSON.
// Rejects (with the server's error message when present) on non-2xx.
function postJson(pathname, body) {
  const { base, token } = cfg();
  const url = new URL(base.replace(/\/$/, "") + pathname);
  const payload = Buffer.from(JSON.stringify(body));
  const mod = url.protocol === "http:" ? http : https;
  const opts = {
    method: "POST",
    hostname: url.hostname,
    port: url.port,
    path: url.pathname + url.search,
    headers: {
      "Content-Type": "application/json",
      "Content-Length": payload.length,
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    rejectUnauthorized: false, // meetico uses a self-signed localhost cert
    timeout: 20000,
  };
  return new Promise((resolve, reject) => {
    const req = mod.request(opts, (res) => {
      let data = "";
      res.on("data", (c) => (data += c));
      res.on("end", () => {
        let json = null;
        try {
          json = data ? JSON.parse(data) : null;
        } catch {
          /* non-JSON body */
        }
        if (res.statusCode >= 200 && res.statusCode < 300) return resolve(json ?? {});
        const msg = (json && (json.error || json.message)) || `meetico HTTP ${res.statusCode}`;
        reject(new Error(msg));
      });
    });
    req.on("error", (e) => reject(new Error(`meetico no accesible: ${e.message}`)));
    req.on("timeout", () => req.destroy(new Error("meetico timeout")));
    req.end(payload);
  });
}

// Persist a binding on one input/output. kind = "inputs"|"outputs".
// body: { artifact_type_id, url? , reference?, project_id? }. Returns the IORow.
function bind(kind, id, body) {
  return postJson(`/tasks/io-review/${kind}/${encodeURIComponent(id)}/bind`, body);
}

// Resolve a proposed binding without persisting → { reference, resolved }.
function bindPreview(body) {
  return postJson(`/tasks/io-review/bind-preview`, body);
}

module.exports = { bind, bindPreview };

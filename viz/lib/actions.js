// actions — the kernel's enforced write path for component acts.
//
// A block/page whose acts shell out to a bash script must declare it in
// manifest.writes; makeRunner() hands the act a run(script, args) bound to
// that whitelist and THROWS on anything undeclared (a misdeclared write is a
// programming error — it must fail loud, never silent). This is a governance
// rail, not a sandbox: the fork is the sandbox and engineering review is the
// security boundary — what gets approved when a component is elevated is
// exactly its manifest.writes list (docs/deltas-architecture.md).

const path = require("node:path");
const { execFileSync } = require("node:child_process");
const { REPO_ROOT } = require("./datasources");

// Parse the LAST JSON line of a script's output. Convention of the bash write
// scripts: they print progress, then one JSON result line; fail() prints its
// {ok:false,…} JSON to stdout and exits non-zero.
function parseLast(s) {
  const line = String(s || "").trim().split("\n").filter(Boolean).pop();
  if (!line) return null;
  try {
    return JSON.parse(line);
  } catch {
    return null;
  }
}

// run(script, args) → the script's parsed JSON result ({ok, …} or {ok:false,
// error}). `script` is the repo-relative path exactly as declared in writes.
function makeRunner(manifest) {
  const allowed = new Set((manifest && manifest.writes) || []);
  return function run(script, args) {
    if (!allowed.has(script)) {
      throw new Error(`Script no declarado en manifest.writes: ${script}`);
    }
    try {
      const out = execFileSync("bash", [path.join(REPO_ROOT, script), ...args, "--json"], {
        encoding: "utf8",
        cwd: REPO_ROOT,
      });
      return parseLast(out) || { ok: true };
    } catch (e) {
      return parseLast(e.stdout) || { ok: false, error: (e.stderr && String(e.stderr)) || e.message };
    }
  };
}

module.exports = { makeRunner };

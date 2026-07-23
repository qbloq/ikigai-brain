// Minimal Server-Sent Events helpers speaking the Datastar 1.0 wire protocol.
//
// Datastar drives the DOM from the backend: an action like @get('/ui/123')
// opens an SSE stream and the server replies with `datastar-patch-elements`
// events. Each event carries an `elements` HTML payload that Datastar merges
// into the live DOM, by default matching on the element's id (mode "outer").

function startSSE(res) {
  res.writeHead(200, {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
  });
}

// Patch one (multi-line ok) HTML element into the DOM. mode: outer (default) |
// inner | append | prepend | replace. selector overrides id-based matching.
function patchElements(res, html, { mode = "outer", selector } = {}) {
  let s = "event: datastar-patch-elements\n";
  if (mode && mode !== "outer") s += `data: mode ${mode}\n`;
  if (selector) s += `data: selector ${selector}\n`;
  for (const line of String(html).split("\n")) s += `data: elements ${line}\n`;
  s += "\n";
  res.write(s);
}

module.exports = { startSSE, patchElements };

#!/usr/bin/env python3
"""Notion read-only engine: fetch a page (or database) and render to Markdown.

Stdlib only (urllib). Token from $NOTION_TOKEN (or $NOTION). Read-only: GET for
pages/blocks, POST only to /databases/<id>/query (a read). Never mutates Notion.

Usage:
  notion.py page   <id-or-url>   > page.md        # page: props + blocks (recursive)
  notion.py blocks <id-or-url>                    # raw block tree as JSON
  notion.py db     <id-or-url>                    # query a database -> rows as markdown table
  notion.py raw-page <id-or-url>                  # page object JSON
"""
import json
import os
import re
import sys
import time
import urllib.request
import urllib.error

TOKEN = os.environ.get("NOTION_TOKEN") or os.environ.get("NOTION")
VERSION = os.environ.get("NOTION_VERSION", "2022-06-28")
API = "https://api.notion.com/v1"

if not TOKEN:
    sys.exit("NOTION token not set (NOTION_TOKEN or NOTION)")


def to_uuid(raw):
    m = re.findall(r"[0-9a-fA-F]{32}", raw)
    if m:
        h = m[-1].lower()
    else:
        m = re.findall(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", raw)
        if not m:
            sys.exit(f"no Notion id found in {raw!r}")
        return m[-1].lower()
    return f"{h[0:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"


def api(method, path, body=None):
    url = API + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    req.add_header("Notion-Version", VERSION)
    req.add_header("Content-Type", "application/json")
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 4:
                time.sleep(float(e.headers.get("Retry-After", "1")))
                continue
            sys.stderr.write(e.read().decode(errors="replace") + "\n")
            raise


def paginate(method, path, body=None):
    """Yield all results across cursor pages."""
    cursor = None
    while True:
        if method == "GET":
            sep = "&" if "?" in path else "?"
            p = path + (f"{sep}start_cursor={cursor}" if cursor else "")
            d = api("GET", p)
        else:
            b = dict(body or {})
            if cursor:
                b["start_cursor"] = cursor
            d = api("POST", path, b)
        yield from d.get("results", [])
        if not d.get("has_more"):
            break
        cursor = d.get("next_cursor")


# ---- rich text --------------------------------------------------------------
def rich(rts):
    out = []
    for rt in rts or []:
        t = rt.get("plain_text", "")
        a = rt.get("annotations", {})
        if a.get("code"):
            t = f"`{t}`"
        if a.get("bold"):
            t = f"**{t}**"
        if a.get("italic"):
            t = f"*{t}*"
        if a.get("strikethrough"):
            t = f"~~{t}~~"
        href = rt.get("href")
        if href:
            t = f"[{t}]({href})"
        out.append(t)
    return "".join(out)


# ---- property values (for db rows / page props) -----------------------------
def prop_value(p):
    t = p.get("type")
    v = p.get(t)
    if t in ("title", "rich_text"):
        return rich(v)
    if t == "select":
        return v["name"] if v else ""
    if t == "status":
        return v["name"] if v else ""
    if t == "multi_select":
        return ", ".join(o["name"] for o in v)
    if t == "date":
        if not v:
            return ""
        return v["start"] + (f" → {v['end']}" if v.get("end") else "")
    if t == "people":
        return ", ".join(o.get("name", o.get("id", "?")) for o in v)
    if t == "number":
        return "" if v is None else str(v)
    if t == "checkbox":
        return "✓" if v else "✗"
    if t == "url":
        return v or ""
    if t == "email":
        return v or ""
    if t == "phone_number":
        return v or ""
    if t == "formula":
        return str(v.get(v["type"], "")) if v else ""
    if t == "relation":
        return f"{len(v)} rel" + ("+" if p.get("has_more") else "")
    if t == "rollup":
        rt = v.get("type")
        if rt == "array":
            return "; ".join(prop_value({"type": x["type"], x["type"]: x[x["type"]]}) for x in v["array"])
        return str(v.get(rt, ""))
    if t == "people":
        return ", ".join(o.get("name", "?") for o in v)
    if t == "created_time":
        return v
    if t == "last_edited_time":
        return v
    return json.dumps(v, ensure_ascii=False) if v else ""


# ---- block rendering --------------------------------------------------------
def fetch_children(block_id):
    return list(paginate("GET", f"/blocks/{block_id}/children?page_size=100"))


def render_blocks(blocks, depth=0):
    lines = []
    numbered = 0
    for b in blocks:
        t = b["type"]
        data = b.get(t, {})
        txt = rich(data.get("rich_text")) if isinstance(data, dict) else ""
        ind = "  " * depth
        if t.startswith("heading_"):
            level = int(t[-1])
            lines.append("")
            lines.append("#" * (level + 1) + " " + txt)
            lines.append("")
        elif t == "paragraph":
            lines.append(ind + txt if txt else "")
        elif t == "bulleted_list_item":
            lines.append(ind + "- " + txt)
        elif t == "numbered_list_item":
            numbered += 1
            lines.append(ind + f"{numbered}. " + txt)
        elif t == "to_do":
            chk = "x" if data.get("checked") else " "
            lines.append(ind + f"- [{chk}] " + txt)
        elif t == "toggle":
            lines.append(ind + "- " + txt + " ⏷")
        elif t == "quote":
            lines.append(ind + "> " + txt)
        elif t == "callout":
            icon = (data.get("icon") or {}).get("emoji", "💡")
            lines.append(ind + f"> {icon} " + txt)
        elif t == "code":
            lang = data.get("language", "")
            lines.append(f"```{lang}")
            lines.append(txt)
            lines.append("```")
        elif t == "divider":
            lines.append("---")
        elif t == "child_page":
            lines.append(ind + f"- 📄 **{data.get('title','')}** _(subpágina `{b['id']}`)_")
        elif t == "child_database":
            title = data.get("title", "(sin título)")
            lines.append("")
            lines.append(f"### 🗃️ Base de datos: {title}")
            lines.append(f"_(child_database `{b['id']}`)_")
            lines.append("")
            try:
                lines.extend(render_db_table(b["id"]))
            except Exception as e:
                lines.append(f"_(no se pudo leer la base: {e})_")
            lines.append("")
        elif t in ("image", "file", "pdf", "video"):
            f = data.get(data.get("type", ""), {})
            url = f.get("url", "") if isinstance(f, dict) else ""
            cap = rich(data.get("caption"))
            lines.append(ind + f"- 📎 [{t}]({url}) {cap}".rstrip())
        elif t == "table":
            # children are table_row blocks
            pass
        elif t == "table_row":
            cells = ["".join(rich(c)) for c in data.get("cells", [])]
            lines.append(ind + "| " + " | ".join(cells) + " |")
        elif t == "bookmark" or t == "embed" or t == "link_preview":
            lines.append(ind + f"- 🔗 {data.get('url','')}")
        elif t == "equation":
            lines.append(ind + f"$$ {data.get('expression','')} $$")
        elif t == "column_list" or t == "column":
            pass  # transparent; children rendered below
        else:
            if txt:
                lines.append(ind + txt)
            else:
                lines.append(ind + f"_[{t}]_")

        # recurse
        if b.get("has_children") and t not in ("child_database", "child_page"):
            child = fetch_children(b["id"])
            if t == "table":
                lines.extend(render_blocks(child, depth))
            else:
                lines.extend(render_blocks(child, depth + 1))
    return lines


DS_VERSION = "2025-09-03"  # data-source model (multi-source databases / linked views)


def api_ds(method, path, body=None):
    """Same as api() but pins the data-source API version."""
    global VERSION
    prev, VERSION = VERSION, DS_VERSION
    try:
        return api(method, path, body)
    finally:
        VERSION = prev


def _query_datasource(ds_id):
    """Paginate a data source query under the DS API version."""
    global VERSION
    prev, VERSION = VERSION, DS_VERSION
    try:
        return list(paginate("POST", f"/data_sources/{ds_id}/query", {"page_size": 100}))
    finally:
        VERSION = prev


def render_db_table(db_id):
    """Query a (child) database and render its rows as a markdown table.

    Handles both models: the newer data-source model (2025-09-03) where a
    database fans out to one or more data sources, and the classic single
    /databases/{id}/query. Linked-view databases whose source is not shared
    with the integration report an empty data_sources list -> not readable.
    """
    dbnew = api_ds("GET", f"/databases/{db_id}")
    sources = dbnew.get("data_sources", [])
    rows, schema = [], {}
    if sources:
        for s in sources:
            ds = api_ds("GET", f"/data_sources/{s['id']}")
            schema = ds.get("properties", schema)
            rows.extend(_query_datasource(s["id"]))
    else:
        # classic model (or unshared linked view -> likely 400/empty)
        db = api("GET", f"/databases/{db_id}")
        schema = db.get("properties", {})
        rows = list(paginate("POST", f"/databases/{db_id}/query", {"page_size": 100}))
    names = list(schema.keys())
    names.sort(key=lambda n: (schema[n]["type"] != "title", n.lower()))
    out = []
    out.append("| " + " | ".join(names) + " |")
    out.append("|" + "|".join(["---"] * len(names)) + "|")
    for pg in rows:
        props = pg.get("properties", {})
        cells = []
        for n in names:
            val = prop_value(props[n]) if n in props else ""
            val = val.replace("\n", " ").replace("|", "\\|")
            cells.append(val)
        out.append("| " + " | ".join(cells) + " |")
    out.append("")
    out.append(f"_{len(rows)} filas._")
    return out


def page_title(page):
    for p in page.get("properties", {}).values():
        if p.get("type") == "title":
            return rich(p["title"])
    return "(sin título)"


def render_page(raw):
    pid = to_uuid(raw)
    page = api("GET", f"/pages/{pid}")
    title = page_title(page)
    md = [f"# {title}", ""]
    md.append(f"> Notion page `{pid}` · última edición {page.get('last_edited_time','?')} · creada {page.get('created_time','?')}")
    md.append(f"> URL: {page.get('url','')}")
    md.append("")
    # page-level properties (skip the title)
    props = page.get("properties", {})
    proplines = []
    for name, p in props.items():
        if p.get("type") == "title":
            continue
        val = prop_value(p)
        if val:
            proplines.append(f"- **{name}**: {val}")
    if proplines:
        md.append("## Propiedades de la página")
        md.extend(proplines)
        md.append("")
    md.append("## Contenido")
    blocks = fetch_children(pid)
    md.extend(render_blocks(blocks))
    return "\n".join(md) + "\n"


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    cmd, arg = sys.argv[1], sys.argv[2]
    if cmd == "page":
        sys.stdout.write(render_page(arg))
    elif cmd == "raw-page":
        print(json.dumps(api("GET", f"/pages/{to_uuid(arg)}"), ensure_ascii=False, indent=2))
    elif cmd == "blocks":
        print(json.dumps(fetch_children(to_uuid(arg)), ensure_ascii=False, indent=2))
    elif cmd == "db":
        print("\n".join(render_db_table(to_uuid(arg))))
    elif cmd == "search":
        q = arg if arg != "-" else ""
        body = {"page_size": 100}
        if q:
            body["query"] = q
        d = api_ds("POST", "/search", body)
        for r in d.get("results", []):
            obj = r["object"]
            if obj in ("database", "data_source"):
                title = "".join(t.get("plain_text", "") for t in r.get("title", []))
                print(f"{obj:11} {r['id']}  {title!r}  ds={len(r.get('data_sources', []))}")
            else:
                title = ""
                for p in r.get("properties", {}).values():
                    if p.get("type") == "title":
                        title = "".join(t.get("plain_text", "") for t in p["title"])
                print(f"{obj:11} {r['id']}  {title!r}")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Extract all BD Avances tasks for a given "Proyecto brief" page.

BD Avances (data source d3944694-…) is the org's master task/advances database,
shared with the integration. Each row's "Proyectos brief" relation links it to a
project page (e.g. DG- Premium Mastermind). We filter by that relation.

Usage:
  project_tasks.py <project-page-id-or-url> [--format json|csv|md]

Read-only (POST to /data_sources/<id>/query is a read). Token: $NOTION / $NOTION_TOKEN.
"""
import csv
import io
import json
import os
import re
import sys
import urllib.request
import urllib.error

TOKEN = os.environ.get("NOTION_TOKEN") or os.environ.get("NOTION")
VERSION = "2025-09-03"
API = "https://api.notion.com/v1"
BD_AVANCES = "d3944694-6f39-4903-a7b8-5dccf9b4c1d0"  # master task DB (data source)
REL_PROP = "Proyectos brief"  # relation on each task -> project page

if not TOKEN:
    sys.exit("NOTION token not set")


def to_uuid(raw):
    m = re.findall(r"[0-9a-fA-F]{32}", raw)
    if m:
        h = m[-1].lower()
        return f"{h[0:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"
    m = re.findall(r"[0-9a-fA-F-]{36}", raw)
    if m:
        return m[-1].lower()
    sys.exit(f"no id in {raw!r}")


def api(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    req.add_header("Notion-Version", VERSION)
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())


def pv(p):
    """Render a property value to a plain python value for analysis."""
    t = p.get("type")
    v = p.get(t)
    if t in ("title", "rich_text"):
        return "".join(x.get("plain_text", "") for x in v)
    if t in ("select", "status"):
        return v["name"] if v else None
    if t == "multi_select":
        return [o["name"] for o in v]
    if t == "date":
        return v.get("start") if v else None
    if t == "people":
        return [o.get("name") or o.get("id") for o in v]
    if t == "relation":
        return [r["id"] for r in v]
    if t == "checkbox":
        return bool(v)
    if t == "number":
        return v
    if t == "formula":
        return v.get(v["type"]) if v else None
    if t == "url":
        return v
    if t in ("created_time", "last_edited_time"):
        return v
    if t in ("created_by", "last_edited_by"):
        return (v or {}).get("name") if isinstance(v, dict) else None
    if t == "files":
        return len(v) if v else 0
    return None


# Fields we keep for analysis (Notion prop name -> output key). '' is the
# unnamed people prop = the assignee ("Asignado").
FIELDS = {
    "Tarea": "tarea",
    "Estado": "estado",
    "Área": "area",
    "Etapa": "etapa",
    "Fases lanzamientos y evergreen": "fases",
    "Nº Lanzamiento": "lanzamiento",
    "Prioridad": "prioridad",
    "Categoría": "categoria",
    "Tipo proceso": "tipo_proceso",
    "Proceso de análisis de datos": "proceso_datos",
    "": "asignado",
    "A quién entrega": "entrega_a",
    "Texto": "texto",
    "❌Drive Crudo": "drive_crudo",
    "✅Drive Editado": "drive_editado",
    "Aprobación interna": "aprob_interna",
    "Aprobación cliente": "aprob_cliente",
    "Fecha": "fecha",
    "Fecha creación": "creado",
    "Tiempo de Última Edición": "editado",
    "Avance Tarea": "avance",
    "% Cumplimiento persona": "cumplimiento",
    "Órdenes de trabajo": "ot",
    REL_PROP: "proyecto_ids",  # relation -> project brief page id(s)
}


def fetch_tasks(page_id):
    """page_id=None -> dump the ENTIRE data source (org-wide, all clients)."""
    out = []
    cursor = None
    while True:
        body = {"page_size": 100}
        if page_id:
            body["filter"] = {"property": REL_PROP, "relation": {"contains": page_id}}
        if cursor:
            body["start_cursor"] = cursor
        d = api("POST", f"/data_sources/{BD_AVANCES}/query", body)
        for pg in d["results"]:
            props = pg["properties"]
            row = {"id": pg["id"], "url": pg.get("url", "")}
            for nname, key in FIELDS.items():
                row[key] = pv(props[nname]) if nname in props else None
            out.append(row)
        if not d.get("has_more"):
            break
        cursor = d["next_cursor"]
    return out


def main():
    argv = sys.argv[1:]
    fmt, page, want_all = "json", None, False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--format":
            fmt = argv[i + 1]
            i += 2
        elif a == "--all":
            want_all = True
            i += 1
        elif a == "--json":
            fmt = "json"
            i += 1
        elif not a.startswith("--"):
            page = to_uuid(a)
            i += 1
        else:
            i += 1
    if not want_all and not page:
        sys.exit(__doc__)
    tasks = fetch_tasks(None if want_all else page)
    if fmt == "json":
        print(json.dumps(tasks, ensure_ascii=False, indent=2))
    elif fmt == "csv":
        keys = ["id", "url"] + list(FIELDS.values())
        w = csv.DictWriter(sys.stdout, fieldnames=keys, extrasaction="ignore")
        w.writeheader()
        for t in tasks:
            row = {k: (", ".join(v) if isinstance(v, list) else v) for k, v in t.items()}
            w.writerow(row)
    elif fmt == "md":
        print(f"# {len(tasks)} tareas\n")
        for t in tasks:
            print(f"- **{t['tarea']}** — {t.get('estado')} · {t.get('area')} · {t.get('fecha')}")
    else:
        sys.exit("unknown format")


if __name__ == "__main__":
    main()

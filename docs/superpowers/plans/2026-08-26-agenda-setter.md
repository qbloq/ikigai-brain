# Agenda del Setter — plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un dashboard para los setters con la agenda del día/semana tomada de GHL, cada cita enriquecida con Meet, closer, banda pre-llamada (entrantes) y estado por capas (pasadas).

**Architecture:** Un dominio nuevo `bash/setters/` con UN script read-only (`agenda.sh`) que orquesta GHL (citas + contactos en vivo) y Postgres (una sola consulta) y delega el ensamblado a un módulo Python puro (`lib/agenda_lib.py`, testeable sin red). El viz lo consume como fuente `agenda_setter` (emits object) y lo pinta en una página autosuficiente `agenda-setter` (sin `/c/`, publicable en v1). Spec en la capa de rol nueva `viz/specs/roles/setter/`.

**Tech Stack:** bash (3.2-compatible), python3 stdlib, psql (`psql_ro`), curl (helpers `bash/ghl/lib/common.sh`), Node stdlib + Datastar 1.0 (viz), `node:test`.

**Spec:** `docs/superpowers/specs/2026-08-26-agenda-setter-design.md`

## Global Constraints

- Read-only en todo: solo GET a GHL, `psql_ro` en Postgres. Nada escribe (spec §1).
- **GHL manda**: la agenda es la lista de citas de GHL; la base solo enriquece. GHL caído ≠ agenda vacía (spec §2.5).
- Reloj: `startTime` de GHL trae offset → hora de pared Bogotá; `meetings.scheduled_start_time` se lee LITERAL (`AT TIME ZONE 'UTC'`), nunca se convierte (spec §2.1.7).
- El token de GHL jamás en argv ni exportado al entorno (política `bash/ghl/lib/common.sh`); las lecturas paralelas se hacen en subshells `( … ) &` en tandas, no con `export -f`/xargs.
- bash 3.2: sin `wait -n`, sin arrays asociativos, sin `mapfile`.
- viz: nada de SQL, nada de hex; solo clases del DS y tokens `var(--…)`; Datastar 1.0 sintaxis con dos puntos (`data-on:click`); toda página nueva exporta `{id, render(ui), manifest}` con `manifest.consumes = "object"` y `overridable` exacto (viz/CLAUDE.md).
- `anunciada` es siempre `null` en v1 y se declara en `sin_instrumentar` (spec §2.3).
- Bandas A/B/C exactamente como spec §2.2; sin score 0-100.
- Commits pequeños, en español, con el prefijo del dominio (`setters:`, `viz(agenda-setter):`, `docs:`).

---

### Task 1: Módulo puro de ensamblado (`agenda_lib.py`) con sus tests

**Files:**
- Create: `bash/setters/lib/agenda_lib.py`
- Create: `bash/setters/lib/test_agenda_lib.py`
- Create: `bash/setters/test.sh`

**Interfaces:**
- Produces (Python, importable y ejecutable):
  - `banda(presupuesto: str|None, disposicion: str|None) -> "A"|"B"|"C"`
  - `ventana(fecha: date, vista: str) -> (date, date)` (semana = lunes→domingo)
  - `hora_bogota(iso: str) -> (fecha "YYYY-MM-DD", hora "HH:MM")` — normaliza el ISO con offset de GHL a pared Bogotá (UTC−5)
  - `estado(cita: dict) -> str` (spec §2.3)
  - `armar(ctx: dict) -> dict` — el objeto de salida completo (spec §2.4)
  - CLI: `python3 agenda_lib.py --dir DIR --proyecto N --fecha D --vista V --ahora "YYYY-MM-DDTHH:MM"` lee `DIR/calendarios.json`, `DIR/eventos.json`, `DIR/contactos/<id>.json`, `DIR/db.json`, `DIR/fuente.json` y escribe el objeto en stdout.

- [ ] **Step 1: Escribir los tests que fallan**

`bash/setters/lib/test_agenda_lib.py`:

```python
import json, unittest
from datetime import date
import agenda_lib as L


class Banda(unittest.TestCase):
    def test_a_presupuesto_alto_y_listo(self):
        self.assertEqual(L.banda("$1.500", "Estoy listo para tomar acción e invertir"), "A")
        self.assertEqual(L.banda("más de $4.000", "Listo para tomar acción"), "A")
    def test_b_500_aunque_listo(self):
        self.assertEqual(L.banda("$500", "listo para tomar acción e invertir"), "B")
    def test_b_alto_pero_no_listo(self):
        self.assertEqual(L.banda("$2.000", "Estoy interesado en saber más"), "B")
        self.assertEqual(L.banda("$2.000", "En búsqueda, no estoy listo"), "B")
    def test_b_valor_desconocido_cuenta_como_respondido(self):
        self.assertEqual(L.banda("un millón", "listo para tomar acción"), "B")
    def test_b_solo_una_respondida(self):
        self.assertEqual(L.banda("$1.500", None), "B")
        self.assertEqual(L.banda("", "listo para tomar acción"), "B")
    def test_c_sin_responder(self):
        self.assertEqual(L.banda(None, None), "C")
        self.assertEqual(L.banda("", "  "), "C")


class Ventana(unittest.TestCase):
    def test_dia(self):
        self.assertEqual(L.ventana(date(2026, 8, 26), "dia"), (date(2026, 8, 26), date(2026, 8, 26)))
    def test_semana_lunes_a_domingo(self):
        # 2026-08-26 es miércoles
        self.assertEqual(L.ventana(date(2026, 8, 26), "semana"), (date(2026, 8, 24), date(2026, 8, 30)))
        self.assertEqual(L.ventana(date(2026, 8, 30), "semana"), (date(2026, 8, 24), date(2026, 8, 30)))


class HoraBogota(unittest.TestCase):
    def test_offset_bogota(self):
        self.assertEqual(L.hora_bogota("2026-08-25T09:20:00-05:00"), ("2026-08-25", "09:20"))
    def test_utc_se_convierte(self):
        self.assertEqual(L.hora_bogota("2026-08-25T14:20:00Z"), ("2026-08-25", "09:20"))
        self.assertEqual(L.hora_bogota("2026-08-26T02:30:00.000Z"), ("2026-08-25", "21:30"))


def cita(**kw):
    base = {"estado_ghl": "confirmed", "pasada": True, "venta": None, "reporte": None,
            "ocurrio": {"transcript": False, "grabacion": False}}
    base.update(kw); return base


class Estado(unittest.TestCase):
    def test_orden(self):
        self.assertEqual(L.estado(cita(estado_ghl="cancelled", venta={"x": 1})), "cancelada")
        self.assertEqual(L.estado(cita(pasada=False, venta={"x": 1})), "proxima")
        self.assertEqual(L.estado(cita(venta={"x": 1}, reporte={"y": 1})), "venta")
        self.assertEqual(L.estado(cita(reporte={"y": 1})), "analizada")
        self.assertEqual(L.estado(cita(ocurrio={"transcript": True, "grabacion": False})), "ocurrio_sin_analisis")
        self.assertEqual(L.estado(cita(ocurrio={"transcript": False, "grabacion": True})), "ocurrio_sin_analisis")
        self.assertEqual(L.estado(cita()), "sin_rastro")


CTX = {
    "proyecto": "David Guerrero", "fecha": "2026-08-26", "vista": "dia", "ahora": "2026-08-26T10:00",
    "fuente": {"ghl": "ok", "detalle": None, "db": "ok"},
    "calendarios": [{"id": "CAL1", "nombre": "Calendario Premium Mastermind", "setters": ["SET1", "SET2"]}],
    "eventos": [
        {"id": "AP1", "appointmentStatus": "confirmed", "title": "Ana Pérez - Premium Mastermind",
         "startTime": "2026-08-26T09:20:00-05:00", "endTime": "2026-08-26T09:40:00-05:00",
         "contactId": "C1", "assignedUserId": "CLO1", "calendarId": "CAL1", "createdBy": {"source": "booking_widget"}},
        {"id": "AP2", "appointmentStatus": "confirmed", "title": "Luis Gil - Premium Mastermind",
         "startTime": "2026-08-26T15:00:00-05:00", "endTime": "2026-08-26T15:20:00-05:00",
         "contactId": "C2", "assignedUserId": "SET1", "calendarId": "CAL1", "createdBy": {"source": "booking_widget"}},
        {"id": "AP3", "appointmentStatus": "cancelled", "title": "Eva Ruiz - Premium Mastermind",
         "startTime": "2026-08-26T08:00:00-05:00", "endTime": "2026-08-26T08:20:00-05:00",
         "contactId": "C3", "assignedUserId": "CLO1", "calendarId": "CAL1", "createdBy": {"source": "booking_widget"}},
        {"id": "AP_FUERA", "appointmentStatus": "confirmed", "title": "Fuera - PM",
         "startTime": "2026-08-27T09:00:00-05:00", "endTime": "2026-08-27T09:20:00-05:00",
         "contactId": "C9", "assignedUserId": "CLO1", "calendarId": "CAL1", "createdBy": {}},
    ],
    "contactos": {
        "C1": {"id": "C1", "firstName": "Ana", "lastName": "Pérez", "email": "ana@x.co", "phone": "+57 300",
               "source": "Survey Mastermind", "tags": ["form mastermind"],
               "attributionSource": {"sessionSource": "Social media", "campaign": "Fly_test", "utmSource": "fb"},
               "customFields": [{"id": "F_PRES", "value": "$1.500"}, {"id": "F_DISP", "value": "Estoy listo para tomar acción e invertir"},
                                {"id": "F_OTRO", "value": "Colombia"}]},
        "C2": None,
        "C3": {"id": "C3", "firstName": "Eva", "lastName": "Ruiz", "customFields": []},
    },
    "db": {
        "catalogo": [{"ghl_field_id": "F_PRES", "name": "¿Tienes al menos $1.500 USD para invertir?", "position": 1},
                     {"ghl_field_id": "F_DISP", "name": "¿En qué situación te encuentras actualmente?", "position": 2},
                     {"ghl_field_id": "F_OTRO", "name": "País", "position": 3}],
        "usuarios": [{"ghl_user_id": "CLO1", "user_id": "u-1", "nombre": "Carlos González"},
                     {"ghl_user_id": "SET1", "user_id": "u-2", "nombre": "Cristian Buelvas"},
                     {"ghl_user_id": "SET2", "user_id": "u-3", "nombre": "Anthony Velásquez"}],
        "meetings": [{"appointment_id": "AP3", "id8": "aaaaaaaa", "meet_url": "https://meet.google.com/aaa", "status": "ended",
                      "grabacion": True, "transcript": True, "reporte_fuente": "cerebro", "baja_confianza": ["budget"],
                      "bant": {"budget": {"score": 60}, "authority": {"score": 80}, "need": {"score": 70}, "timeline": {"score": 50}},
                      "arquetipo": "Emocional"}],
        "planes": [], "opps": [{"ghl_contact_id": "C1", "etapa": "LLAMADA CONFIRMADA", "dueno": "Carlos González"}],
        "historial": [{"ghl_contact_id": "C1", "llamadas_previas": 1, "ultima": "2026-07-01", "bant_previo": 55}],
        "espejo": [{"ghl_contact_id": "C2", "first_name": "Luis", "last_name": "Gil", "email": "luis@x.co", "phone": None,
                    "custom_fields": [{"id": "F_PRES", "value": "$500"}], "tags": []}],
        "solo_en_sistema": [{"id8": "bbbbbbbb", "fecha": "2026-08-26", "hora": "11:00", "lead": "Javier Gutierrez", "closer": "Carlos González"}],
    },
}


class Armar(unittest.TestCase):
    def setUp(self):
        self.out = L.armar(json.loads(json.dumps(CTX)))
        self.por_id = {c["appointment_id"]: c for c in self.out["citas"]}

    def test_ventana_filtra_y_ordena(self):
        self.assertEqual([c["appointment_id"] for c in self.out["citas"]], ["AP3", "AP1", "AP2"])
        self.assertEqual(self.out["ventana"], {"vista": "dia", "fecha": "2026-08-26", "desde": "2026-08-26", "hasta": "2026-08-26", "ahora": "2026-08-26T10:00"})

    def test_lead_en_vivo_banda_y_survey(self):
        c = self.por_id["AP1"]
        self.assertEqual(c["lead"]["nombre"], "Ana Pérez"); self.assertEqual(c["lead"]["fuente"], "ghl")
        self.assertEqual(c["lead"]["campana"], "Fly_test"); self.assertEqual(c["lead"]["sesion"], "Social media")
        self.assertEqual(c["banda"], {"letra": "A", "presupuesto": "$1.500", "disposicion": "Estoy listo para tomar acción e invertir"})
        self.assertEqual([s["campo"] for s in c["survey"]], ["¿Tienes al menos $1.500 USD para invertir?", "¿En qué situación te encuentras actualmente?", "País"])
        self.assertEqual(c["closer"]["nombre"], "Carlos González"); self.assertFalse(c["sin_closer"])
        self.assertEqual(c["etapa_crm"], "LLAMADA CONFIRMADA"); self.assertFalse(c["etapa_no_confirmada"])
        self.assertEqual(c["historial"], {"llamadas_previas": 1, "ultima": "2026-07-01", "bant_previo": 55})
        self.assertIsNone(c["meeting"]); self.assertTrue(c["sin_meet"])
        self.assertFalse(c["pasada"]); self.assertEqual(c["estado"], "proxima"); self.assertIsNone(c["anunciada"])

    def test_lead_desde_espejo_y_setter_asignado(self):
        c = self.por_id["AP2"]
        self.assertEqual(c["lead"]["fuente"], "espejo"); self.assertEqual(c["lead"]["nombre"], "Luis Gil")
        self.assertEqual(c["banda"]["letra"], "B")
        self.assertEqual(c["closer"]["nombre"], "Cristian Buelvas"); self.assertTrue(c["sin_closer"])
        self.assertIsNone(c["etapa_crm"]); self.assertTrue(c["etapa_no_confirmada"])

    def test_pasada_cancelada_con_reporte(self):
        c = self.por_id["AP3"]
        self.assertTrue(c["pasada"]); self.assertEqual(c["estado"], "cancelada")
        self.assertEqual(c["meeting"]["meet_url"], "https://meet.google.com/aaa"); self.assertFalse(c["sin_meet"])
        self.assertEqual(c["reporte"]["bant"], {"budget": 60, "authority": 80, "need": 70, "timeline": 50, "total": 65})
        self.assertEqual(c["reporte"]["baja_confianza"], ["budget"]); self.assertEqual(c["reporte"]["arquetipo"], "Emocional")
        self.assertEqual(c["ocurrio"], {"transcript": True, "grabacion": True})
        self.assertIsNone(c["banda"])  # pasadas no llevan banda

    def test_kpis_y_alertas(self):
        k = self.out["kpis"]
        self.assertEqual((k["citas"], k["confirmadas"], k["canceladas"]), (3, 2, 1))
        self.assertEqual((k["banda_a"], k["sin_closer"], k["sin_meet"]), (1, 1, 2))
        self.assertEqual((k["pasadas"], k["ocurrieron"], k["analizadas"], k["ventas"], k["sin_rastro"]), (1, 0, 0, 0, 0))
        self.assertEqual(self.out["solo_en_sistema"][0]["lead"], "Javier Gutierrez")
        self.assertEqual(self.out["fuente"]["contactos_en_vivo"], 2); self.assertEqual(self.out["fuente"]["contactos_espejo"], 1)
        self.assertEqual(len(self.out["sin_instrumentar"]), 2)
        self.assertEqual(self.out["calendarios"][0]["setters"], ["Cristian Buelvas", "Anthony Velásquez"])

    def test_sin_contacto_ni_espejo_usa_titulo(self):
        ctx = json.loads(json.dumps(CTX)); ctx["contactos"]["C3"] = None
        c = {x["appointment_id"]: x for x in L.armar(ctx)["citas"]}["AP3"]
        self.assertEqual(c["lead"]["nombre"], "Eva Ruiz"); self.assertEqual(c["lead"]["fuente"], "titulo")

    def test_venta_y_estado_venta(self):
        ctx = json.loads(json.dumps(CTX)); ctx["ahora"] = "2026-08-26T23:00"
        ctx["db"]["planes"] = [{"customer_id": "C1", "plan_id8": "pppppppp", "monto": 1000, "cuotas": 3, "creado": "2026-08-26"}]
        c = {x["appointment_id"]: x for x in L.armar(ctx)["citas"]}["AP1"]
        self.assertEqual(c["estado"], "venta"); self.assertEqual(c["venta"]["plan_id8"], "pppppppp")

    def test_ghl_error_deja_citas_vacias(self):
        ctx = json.loads(json.dumps(CTX)); ctx["fuente"] = {"ghl": "error", "detalle": "HTTP 500", "db": "ok"}; ctx["eventos"] = []
        out = L.armar(ctx)
        self.assertEqual(out["citas"], []); self.assertEqual(out["fuente"]["ghl"], "error"); self.assertEqual(out["kpis"]["citas"], 0)


if __name__ == "__main__":
    unittest.main()
```

`bash/setters/test.sh`:

```bash
#!/usr/bin/env bash
# Tests del dominio setters — puros (sin red, sin base).
# Correr: bash bash/setters/test.sh   (sale 0 si todo pasa)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/lib" && python3 -m unittest -v test_agenda_lib
```

- [ ] **Step 2: Correr y ver que falla**

Run: `bash bash/setters/test.sh`
Expected: `ModuleNotFoundError: No module named 'agenda_lib'`

- [ ] **Step 3: Implementar `agenda_lib.py`**

```python
#!/usr/bin/env python3
"""agenda_lib — el ensamblado PURO de la agenda del setter (spec
docs/superpowers/specs/2026-08-26-agenda-setter-design.md).

Sin red ni base: recibe lo que agenda.sh ya trajo (citas de GHL, contactos en
vivo, una consulta a Postgres) y emite el objeto de la fuente `agenda_setter`.
Todo lo que se puede probar sin credenciales vive aquí.
"""
import argparse, json, os, re, sys
from datetime import date, datetime, timedelta, timezone

BOGOTA = timezone(timedelta(hours=-5))
SIN_INSTRUMENTAR = [
    "anunciada: el desenlace que el closer anuncia en ONLY CLOSERS no se persiste aún (detector de anuncios, sub-proyecto 2)",
    "asistió/no asistió: GHL lo soporta (showed/noshow) y nadie lo marca; el setter puede empezar hoy",
]
RE_PRESUPUESTO = re.compile(r"al menos \$?\s*1[.,]?500", re.I)
RE_DISPOSICION = re.compile(r"situaci[oó]n te encuentras actualmente", re.I)


# --- reglas puras -----------------------------------------------------------
def banda(presupuesto, disposicion):
    """A/B/C de docs/lead-score.md §5. Un presupuesto no reconocido cuenta
    como respondido (B): nunca se descarta un lead por un rótulo nuevo."""
    p = (presupuesto or "").strip()
    d = (disposicion or "").strip()
    if not p and not d:
        return "C"
    digitos = re.sub(r"\D", "", p)
    alto = bool(digitos) and int(digitos) >= 1500
    low = d.lower()
    listo = "listo para" in low and "no estoy listo" not in low
    return "A" if (alto and listo) else "B"


def ventana(fecha, vista):
    if vista == "semana":
        desde = fecha - timedelta(days=fecha.weekday())
        return desde, desde + timedelta(days=6)
    return fecha, fecha


def hora_bogota(iso):
    """ISO con offset (GHL) → ('YYYY-MM-DD', 'HH:MM') en pared Bogotá."""
    s = iso.replace("Z", "+00:00")
    s = re.sub(r"\.\d+(?=[+-]\d\d:\d\d$)", "", s)
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=BOGOTA)
    dt = dt.astimezone(BOGOTA)
    return dt.strftime("%Y-%m-%d"), dt.strftime("%H:%M")


def estado(cita):
    if cita.get("estado_ghl") == "cancelled":
        return "cancelada"
    if not cita.get("pasada"):
        return "proxima"
    if cita.get("venta"):
        return "venta"
    if cita.get("reporte"):
        return "analizada"
    oc = cita.get("ocurrio") or {}
    if oc.get("transcript") or oc.get("grabacion"):
        return "ocurrio_sin_analisis"
    return "sin_rastro"


# --- ensamblado ---------------------------------------------------------------
def _nombre_titulo(titulo):
    return re.sub(r"\s*[-|–]\s*.*$", "", titulo or "").strip() or None


def _lead(ev, contacto, espejo, catalogo):
    """(lead, survey, banda) desde el contacto en vivo, el espejo o el título."""
    nombres = {c["ghl_field_id"]: c for c in catalogo}
    orden = {c["ghl_field_id"]: (c.get("position") if c.get("position") is not None else 9999) for c in catalogo}
    if contacto:
        attr = contacto.get("attributionSource") or {}
        nombre = " ".join(x for x in [contacto.get("firstName"), contacto.get("lastName")] if x).strip()
        lead = {"nombre": nombre or _nombre_titulo(ev.get("title")), "email": contacto.get("email"),
                "telefono": contacto.get("phone"), "formulario": contacto.get("source"),
                "sesion": attr.get("sessionSource"), "campana": attr.get("campaign"),
                "tags": contacto.get("tags") or [], "fuente": "ghl"}
        campos = contacto.get("customFields") or []
    elif espejo:
        nombre = " ".join(x for x in [espejo.get("first_name"), espejo.get("last_name")] if x).strip()
        lead = {"nombre": nombre or _nombre_titulo(ev.get("title")), "email": espejo.get("email"),
                "telefono": espejo.get("phone"), "formulario": None, "sesion": None, "campana": None,
                "tags": espejo.get("tags") or [], "fuente": "espejo"}
        campos = espejo.get("custom_fields") or []
    else:
        lead = {"nombre": _nombre_titulo(ev.get("title")), "email": None, "telefono": None, "formulario": None,
                "sesion": None, "campana": None, "tags": [], "fuente": "titulo"}
        campos = []
    survey, pres, disp = [], None, None
    for f in sorted(campos, key=lambda f: orden.get(f.get("id"), 9999)):
        v = f.get("value")
        if v in (None, "", []):
            continue
        v = v if isinstance(v, str) else json.dumps(v, ensure_ascii=False)
        nom = (nombres.get(f.get("id")) or {}).get("name") or f.get("id")
        survey.append({"campo": nom, "valor": v})
        if RE_PRESUPUESTO.search(nom):
            pres = v
        elif RE_DISPOSICION.search(nom):
            disp = v
    return lead, survey, {"letra": banda(pres, disp), "presupuesto": pres, "disposicion": disp}


def _reporte(m):
    if not m or not m.get("reporte_fuente"):
        return None
    bant = {}
    for k in ("budget", "authority", "need", "timeline"):
        raw = ((m.get("bant") or {}).get(k) or {}).get("score")
        try:
            bant[k] = int(round(float(re.sub(r"[^0-9.]", "", str(raw)))))
        except (TypeError, ValueError):
            bant[k] = None
    vals = [v for v in bant.values() if v is not None]
    bant["total"] = int(round(sum(vals) / len(vals))) if vals else None
    bc = m.get("baja_confianza")
    if isinstance(bc, str):
        bc = [x for x in re.split(r"[,{}\s\"]+", bc) if x]
    return {"fuente": m["reporte_fuente"], "bant": bant, "baja_confianza": bc or [],
            "arquetipo": m.get("arquetipo"), "meeting_id8": m.get("id8")}


def armar(ctx):
    fecha = date.fromisoformat(ctx["fecha"])
    desde, hasta = ventana(fecha, ctx["vista"])
    ahora = ctx["ahora"]
    db = ctx.get("db") or {}
    usuarios = {u["ghl_user_id"]: u for u in db.get("usuarios") or []}
    meetings = {m["appointment_id"]: m for m in db.get("meetings") or [] if m.get("appointment_id")}
    opps = {o["ghl_contact_id"]: o for o in db.get("opps") or []}
    hist = {h["ghl_contact_id"]: h for h in db.get("historial") or []}
    espejo = {e["ghl_contact_id"]: e for e in db.get("espejo") or []}
    planes = {}
    for p in db.get("planes") or []:
        planes.setdefault(p["customer_id"], []).append(p)
    catalogo = db.get("catalogo") or []
    setters = set()
    calendarios = []
    for cal in ctx.get("calendarios") or []:
        ids = cal.get("setters") or []
        setters.update(ids)
        calendarios.append({"id": cal["id"], "nombre": cal.get("nombre"),
                            "setters": [usuarios.get(i, {}).get("nombre") or i for i in ids]})
    contactos = ctx.get("contactos") or {}
    en_vivo = sum(1 for v in contactos.values() if v)
    espejo_usados = 0

    citas = []
    for ev in ctx.get("eventos") or []:
        f, h = hora_bogota(ev["startTime"])
        if not (desde.isoformat() <= f <= hasta.isoformat()):
            continue
        fin = hora_bogota(ev["endTime"])[1] if ev.get("endTime") else None
        cid = ev.get("contactId")
        cont = contactos.get(cid)
        esp = None if cont else espejo.get(cid)
        if esp:
            espejo_usados += 1
        lead, survey, bnd = _lead(ev, cont, esp, catalogo)
        pasada = f"{f}T{h}" < ahora
        u = usuarios.get(ev.get("assignedUserId"))
        closer = {"nombre": u["nombre"], "user_id": u["user_id"], "ghl_user_id": ev.get("assignedUserId")} if u \
            else {"nombre": None, "user_id": None, "ghl_user_id": ev.get("assignedUserId")}
        sin_closer = (u is None) or (ev.get("assignedUserId") in setters)
        m = meetings.get(ev["id"])
        meeting = {"id8": m["id8"], "meet_url": m.get("meet_url"), "status": m.get("status")} if m else None
        etapa = (opps.get(cid) or {}).get("etapa")
        venta = None
        for p in planes.get(cid, []):
            if p.get("creado") and p["creado"] >= f:
                venta = {"plan_id8": p["plan_id8"], "monto": p.get("monto"), "cuotas": p.get("cuotas"), "creado": p["creado"]}
                break
        cita = {
            "appointment_id": ev["id"], "fecha": f, "hora": h, "fin": fin,
            "estado_ghl": ev.get("appointmentStatus"), "titulo": ev.get("title"),
            "creada_por": (ev.get("createdBy") or {}).get("source"),
            "pasada": pasada, "estado": None,
            "lead": lead, "closer": closer, "sin_closer": sin_closer,
            "meeting": meeting, "sin_meet": meeting is None,
            "etapa_crm": etapa, "etapa_no_confirmada": (etapa or "").strip().lower() != "llamada confirmada",
            "banda": None if pasada else bnd, "survey": survey,
            "historial": hist.get(cid) and {k: hist[cid].get(k) for k in ("llamadas_previas", "ultima", "bant_previo")}
                         or {"llamadas_previas": 0, "ultima": None, "bant_previo": None},
            "ocurrio": {"transcript": bool(m and m.get("transcript")), "grabacion": bool(m and m.get("grabacion"))},
            "reporte": _reporte(m), "venta": venta, "anunciada": None,
        }
        cita["estado"] = estado(cita)
        citas.append(cita)
    citas.sort(key=lambda c: (c["fecha"], c["hora"]))

    vivas = [c for c in citas if c["estado_ghl"] != "cancelled"]
    prox = [c for c in vivas if not c["pasada"]]
    pas = [c for c in vivas if c["pasada"]]
    kpis = {
        "citas": len(citas), "confirmadas": sum(1 for c in citas if c["estado_ghl"] == "confirmed"),
        "canceladas": sum(1 for c in citas if c["estado_ghl"] == "cancelled"),
        "banda_a": sum(1 for c in prox if (c["banda"] or {}).get("letra") == "A"),
        "sin_closer": sum(1 for c in vivas if c["sin_closer"]), "sin_meet": sum(1 for c in vivas if c["sin_meet"]),
        "pasadas": len(pas), "ocurrieron": sum(1 for c in pas if c["ocurrio"]["transcript"] or c["ocurrio"]["grabacion"]),
        "analizadas": sum(1 for c in pas if c["reporte"]), "ventas": sum(1 for c in pas if c["venta"]),
        "sin_rastro": sum(1 for c in pas if c["estado"] == "sin_rastro"),
    }
    fuente = dict(ctx.get("fuente") or {})
    fuente.update({"contactos_en_vivo": en_vivo, "contactos_espejo": espejo_usados})
    return {
        "proyecto": ctx.get("proyecto"), "calendarios": calendarios,
        "ventana": {"vista": ctx["vista"], "fecha": ctx["fecha"], "desde": desde.isoformat(), "hasta": hasta.isoformat(), "ahora": ahora},
        "fuente": fuente, "kpis": kpis, "citas": citas,
        "solo_en_sistema": db.get("solo_en_sistema") or [],
        "sin_instrumentar": list(SIN_INSTRUMENTAR),
    }


# --- CLI (lo llama agenda.sh) -----------------------------------------------
def _leer(path, default):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True); ap.add_argument("--proyecto", required=True)
    ap.add_argument("--fecha", required=True); ap.add_argument("--vista", required=True); ap.add_argument("--ahora", required=True)
    a = ap.parse_args(argv)
    d = a.dir
    contactos = {}
    cdir = os.path.join(d, "contactos")
    if os.path.isdir(cdir):
        for fn in os.listdir(cdir):
            if fn.endswith(".json"):
                raw = _leer(os.path.join(cdir, fn), None)
                contactos[fn[:-5]] = (raw.get("contact") or raw) if isinstance(raw, dict) else None
    ctx = {"proyecto": a.proyecto, "fecha": a.fecha, "vista": a.vista, "ahora": a.ahora,
           "fuente": _leer(os.path.join(d, "fuente.json"), {"ghl": "error", "detalle": "sin fuente.json", "db": "error"}),
           "calendarios": _leer(os.path.join(d, "calendarios.json"), []),
           "eventos": _leer(os.path.join(d, "eventos.json"), []),
           "contactos": contactos, "db": _leer(os.path.join(d, "db.json"), {})}
    json.dump(armar(ctx), sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Correr los tests y ver que pasan**

Run: `bash bash/setters/test.sh`
Expected: `OK` con 20 tests (todas las clases). Si falla `test_kpis_y_alertas` en `sin_meet`: AP1 y AP2 no tienen meeting (2), AP3 sí — revisar que `vivas` excluye canceladas.

- [ ] **Step 5: Commit**

```bash
git add bash/setters/lib/agenda_lib.py bash/setters/lib/test_agenda_lib.py bash/setters/test.sh
git commit -m "setters: agenda_lib — bandas A/B/C, ventana, estado por capas y ensamblado puro con tests"
```

---

### Task 2: El orquestador `bash/setters/agenda.sh`

**Files:**
- Create: `bash/setters/agenda.sh`

**Interfaces:**
- Consumes: `bash/ghl/lib/common.sh` (`ghl_resolve_project`, `ghl_load_creds`, `ghl_api`, `ghl_qs`, `psql_ro`, `require_acceso ghl`), `bash/setters/lib/agenda_lib.py` CLI (Task 1).
- Produces: `agenda.sh [--project N] [--fecha YYYY-MM-DD] [--vista dia|semana] [--json]` → objeto JSON en stdout (spec §2.4). Siempre JSON (`--json` aceptado por compatibilidad con `buildArgs`).

- [ ] **Step 1: Escribir el script**

```bash
#!/usr/bin/env bash
# agenda.sh — LA AGENDA DEL SETTER como un solo objeto JSON: las citas del
# calendario oficial de GHL (día o semana) enriquecidas con lo que el Cerebro
# sabe de cada lead. Spec: docs/superpowers/specs/2026-08-26-agenda-setter-design.md
#
#   GHL MANDA. La lista de citas es la de GHL; Postgres solo enriquece (Meet,
#   transcript/grabación, reporte BANT, plan de pago, etapa del tablero,
#   historial). Si GHL falla, fuente.ghl='error' y citas=[] — jamás se rellena
#   la agenda desde la base (una llamada que GHL no tiene no existe para el
#   webhook, y por tanto tampoco tendrá grabación ni análisis).
#
#   Por cita: contacto EN VIVO (GET /contacts/{id}) — el lead recién agendado
#   existe en GHL antes que en el espejo; si el GET falla, cae al espejo y la
#   fila lo declara (lead.fuente). Banda pre-llamada A/B/C (lead-score.md §5)
#   solo para las que vienen; estado por capas para las que pasaron.
#   `anunciada` (lo que el closer dijo en ONLY CLOSERS) es null en v1.
#
# ⚠️ Horas: startTime de GHL trae offset → pared Bogotá (UTC−5);
#    meetings.scheduled_start_time se lee LITERAL (quirk Bogotá-como-UTC).
# ⚠️ Solo GET a GHL y psql_ro. Cerca por rol vía bash/ghl/lib (dominio ghl).
# ⚠️ bash 3.2: las lecturas de contacto van en tandas de 4 subshells + wait.
#
# Uso: agenda.sh [--project N] [--fecha YYYY-MM-DD] [--vista dia|semana] [--json]
#   --project  fragmento del nombre (default: David Guerrero)
#   --fecha    día de referencia, Bogotá (default hoy)
#   --vista    dia (default) · semana = lunes–domingo que contiene --fecha
# Siempre emite JSON (un objeto). Read-only. Alimenta la fuente viz `agenda_setter`.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../ghl/lib/common.sh"
export GHL_API_VERSION=2021-04-15   # calendars/* viven en esta versión

PROJECT="David Guerrero"; FECHA=""; VISTA="dia"
usage() { sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="${2:?}"; shift 2 ;;
    --fecha)   FECHA="${2:?}"; shift 2 ;;
    --vista)   VISTA="${2:?}"; shift 2 ;;
    --json)    shift ;;
    -h|--help) usage ;;
    *) echo "flag desconocido: $1" >&2; usage 1 ;;
  esac
done
[[ -z "$FECHA" ]] && FECHA="$(TZ=America/Bogota date +%F)"
[[ "$FECHA" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "--fecha debe ser YYYY-MM-DD" >&2; exit 2; }
[[ "$VISTA" == "dia" || "$VISTA" == "semana" ]] || { echo "--vista debe ser dia|semana" >&2; exit 2; }
AHORA="$(TZ=America/Bogota date +%FT%H:%M)"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/contactos"
GHL_ESTADO=ok; GHL_DETALLE=""; DB_ESTADO=ok

# --- proyecto + credenciales (una vez) --------------------------------------
IFS=$'\t' read -r PID PNAME < <(ghl_resolve_project "$PROJECT")
ghl_load_creds "$PID"
PID_ESC="${PID//\'/\'\'}"

# --- ventana Bogotá → epoch millis (GHL filtra grueso; el python re-filtra) --
read -r DESDE HASTA DESDE_MS HASTA_MS < <(python3 - "$FECHA" "$VISTA" <<'PY'
import sys
from datetime import date, datetime, timedelta, timezone
sys.path.insert(0, __import__("os").path.join(__import__("os").environ["HERE"], "lib"))
import agenda_lib as L
f = date.fromisoformat(sys.argv[1]); d, h = L.ventana(f, sys.argv[2])
tz = timezone(timedelta(hours=-5))
ms = lambda x: int(datetime(x.year, x.month, x.day, tzinfo=tz).timestamp() * 1000)
print(d.isoformat(), h.isoformat(), ms(d), ms(h + timedelta(days=1)))
PY
)

# --- calendarios activos + sus miembros (= los setters) -----------------------
CALS="$(psql_ro -t -A -F$'\t' -c "SELECT ghl_calendar_id, coalesce(nullif(custom_name,''), ghl_calendar_name, '')
  FROM crm_calendars WHERE project_id='$PID_ESC' AND is_active ORDER BY created_at;")" || { DB_ESTADO=error; CALS=""; }
[[ -z "$CALS" ]] && { GHL_ESTADO=error; GHL_DETALLE="el proyecto no tiene calendario activo en crm_calendars"; }

echo '[]' >"$TMP/calendarios.json"; echo '[]' >"$TMP/eventos.json"
while IFS=$'\t' read -r cal_id cal_nombre; do
  [[ -z "$cal_id" ]] && continue
  miembros="[]"
  if out="$(ghl_api "/calendars/$cal_id" 2>"$TMP/err")"; then
    miembros="$(python3 -c 'import json,sys; d=json.load(sys.stdin); c=d.get("calendar") or d
print(json.dumps([m.get("userId") for m in (c.get("teamMembers") or []) if m.get("userId")]))' <<<"$out")"
  fi
  python3 - "$TMP/calendarios.json" "$cal_id" "$cal_nombre" "$miembros" <<'PY'
import json, sys
p, cid, nom, mem = sys.argv[1:5]
arr = json.load(open(p)); arr.append({"id": cid, "nombre": nom, "setters": json.loads(mem)})
json.dump(arr, open(p, "w"), ensure_ascii=False)
PY
  if out="$(ghl_api "/calendars/events$(ghl_qs locationId "$GHL_LOCATION" calendarId "$cal_id" startTime "$DESDE_MS" endTime "$HASTA_MS")" 2>"$TMP/err")"; then
    python3 - "$TMP/eventos.json" <<<"$out" <<'PY' 2>/dev/null || true
PY
    python3 -c '
import json, sys
p = sys.argv[1]; nuevo = json.load(open(sys.argv[2])).get("events") or []
arr = json.load(open(p)); vistos = {e.get("id") for e in arr}
arr += [e for e in nuevo if e.get("id") not in vistos]
json.dump(arr, open(p, "w"), ensure_ascii=False)' "$TMP/eventos.json" <(printf '%s' "$out")
  else
    GHL_ESTADO=error; GHL_DETALLE="$(head -c 300 "$TMP/err" | tr '\n' ' ')"
  fi
done <<<"$CALS"

# --- contactos en vivo, en tandas de 4 (bash 3.2: sin wait -n) ---------------
IDS="$(python3 -c '
import json, sys
print("\n".join(sorted({e.get("contactId") for e in json.load(open(sys.argv[1])) if e.get("contactId")})))' "$TMP/eventos.json")"
n=0
for cid in $IDS; do
  ( ghl_api "/contacts/$cid" >"$TMP/contactos/$cid.json" 2>/dev/null || rm -f "$TMP/contactos/$cid.json" ) &
  n=$((n+1)); (( n % 4 == 0 )) && wait
done
wait

# --- Postgres: UNA consulta con todos los ids -----------------------------------
AP_SQL="$(python3 -c '
import json, sys
ids = [e["id"] for e in json.load(open(sys.argv[1])) if e.get("id")]
print(",".join("\x27%s\x27" % i.replace("\x27","\x27\x27") for i in ids) or "\x27__ninguna__\x27")' "$TMP/eventos.json")"
CT_SQL="$(printf '%s\n' $IDS | sed "s/'/''/g; s/.*/'&'/" | paste -sd, -)"; [[ -z "$CT_SQL" ]] && CT_SQL="'__ninguno__'"
LOC_ESC="${GHL_LOCATION//\'/\'\'}"

DB_JSON="$(psql_ro -t -A -c "
WITH ap AS (SELECT unnest(ARRAY[$AP_SQL]) AS id),
     ct AS (SELECT unnest(ARRAY[$CT_SQL]) AS id),
     closer_de AS (
       SELECT c.ghl_contact_id,
              trim(regexp_replace(coalesce(p.name,'')||' '||coalesce(p.lastname,''),'\s+',' ','g')) AS dueno,
              (SELECT st->>'name' FROM jsonb_array_elements(pl.stages::jsonb) st WHERE st->>'id' = o.ghl_stage_id) AS etapa,
              row_number() OVER (PARTITION BY c.ghl_contact_id ORDER BY (o.project_id='$PID_ESC') DESC NULLS LAST, o.created_date DESC) AS rn
       FROM crm_contacts c JOIN crm_opportunities o ON o.contact_id=c.id
       LEFT JOIN crm_pipelines pl ON pl.id=o.pipeline_id
       LEFT JOIN users u ON u.id=o.user_id LEFT JOIN persons p ON p.person_id=u.person_id
       WHERE c.ghl_contact_id IN (SELECT id FROM ct))
SELECT json_build_object(
 'catalogo', (SELECT coalesce(json_agg(json_build_object('ghl_field_id',ghl_field_id,'name',name,'position',position) ORDER BY position NULLS LAST),'[]')
              FROM crm_custom_fields WHERE project_id='$PID_ESC'),
 'usuarios', (SELECT coalesce(json_agg(json_build_object('ghl_user_id', u.integrations->>'$LOC_ESC', 'user_id', u.id,
                 'nombre', trim(regexp_replace(coalesce(p.name,'')||' '||coalesce(p.lastname,''),'\s+',' ','g')))),'[]')
              FROM users u LEFT JOIN persons p ON p.person_id=u.person_id WHERE u.integrations ? '$LOC_ESC'),
 'meetings', (SELECT coalesce(json_agg(row_to_json(x)),'[]') FROM (
    SELECT coalesce(m.event_id, m.event->'booking'->>'appointment_id') AS appointment_id,
           left(m.id::text,8) AS id8, m.meet_url, m.status,
           (m.recording_url IS NOT NULL OR m.drive_file_id IS NOT NULL) AS grabacion,
           (coalesce(length(t.transcript),0) >= 2000) AS transcript,
           v.fuente AS reporte_fuente, to_json(v.baja_confianza) AS baja_confianza,
           v.report->'leadProfile'->'bantAnalysis' AS bant,
           v.report->'leadProfile'->'intelligentSegmentation'->'archetype'->>'name' AS arquetipo
    FROM meetings m
    LEFT JOIN meeting_transcripts t ON t.meeting_id=m.id
    LEFT JOIN call_report_vigente v ON v.meeting_id=m.id
    WHERE m.meeting_type='call'
      AND (m.event_id IN (SELECT id FROM ap) OR m.event->'booking'->>'appointment_id' IN (SELECT id FROM ap))) x),
 'planes', (SELECT coalesce(json_agg(row_to_json(x)),'[]') FROM (
    SELECT pp.customer_id, left(pp.plan_id::text,8) AS plan_id8, pp.original_amount AS monto,
           pp.number_of_installments AS cuotas, to_char(pp.created_at AT TIME ZONE 'America/Bogota','YYYY-MM-DD') AS creado
    FROM payment_plans pp WHERE pp.customer_id IN (SELECT id FROM ct) AND pp.plan_status='Active'
    ORDER BY pp.created_at DESC) x),
 'opps', (SELECT coalesce(json_agg(json_build_object('ghl_contact_id',ghl_contact_id,'etapa',etapa,'dueno',dueno)),'[]') FROM closer_de WHERE rn=1),
 'historial', (SELECT coalesce(json_agg(row_to_json(x)),'[]') FROM (
    SELECT m.event->'booking'->>'contact_id' AS ghl_contact_id, count(*) AS llamadas_previas,
           to_char(max(m.scheduled_start_time AT TIME ZONE 'UTC'),'YYYY-MM-DD') AS ultima,
           (SELECT round(avg(nullif(regexp_replace(coalesce(v2.report->'leadProfile'->'bantAnalysis'->k->>'score',''),'[^0-9]','','g'),'')::numeric))
              FROM meetings m2 JOIN call_report_vigente v2 ON v2.meeting_id=m2.id,
                   unnest(ARRAY['budget','authority','need','timeline']) k
             WHERE m2.event->'booking'->>'contact_id' = m.event->'booking'->>'contact_id'
               AND (m2.scheduled_start_time AT TIME ZONE 'UTC')::date < '$DESDE'
             GROUP BY m2.id ORDER BY m2.scheduled_start_time DESC LIMIT 1) AS bant_previo
    FROM meetings m
    WHERE m.meeting_type='call' AND m.event->'booking'->>'contact_id' IN (SELECT id FROM ct)
      AND (m.scheduled_start_time AT TIME ZONE 'UTC')::date < '$DESDE' AND m.status <> 'cancelled'
    GROUP BY 1) x),
 'espejo', (SELECT coalesce(json_agg(row_to_json(x)),'[]') FROM (
    SELECT ghl_contact_id, first_name, last_name, email, phone, custom_fields, tags
    FROM crm_contacts WHERE ghl_contact_id IN (SELECT id FROM ct)) x),
 'solo_en_sistema', (SELECT coalesce(json_agg(row_to_json(x) ORDER BY x.fecha, x.hora),'[]') FROM (
    SELECT left(m.id::text,8) AS id8,
           to_char(m.scheduled_start_time AT TIME ZONE 'UTC','YYYY-MM-DD') AS fecha,
           to_char(m.scheduled_start_time AT TIME ZONE 'UTC','HH24:MI') AS hora,
           regexp_replace(m.name, ' *[-|–] *.*$', '') AS lead,
           (SELECT trim(regexp_replace(coalesce(p.name,'')||' '||coalesce(p.lastname,''),'\s+',' ','g'))
              FROM crm_contacts c JOIN crm_opportunities o ON o.contact_id=c.id
              LEFT JOIN users u ON u.id=o.user_id LEFT JOIN persons p ON p.person_id=u.person_id
             WHERE c.ghl_contact_id = m.event->'booking'->>'contact_id'
             ORDER BY (o.project_id=m.project_id) DESC NULLS LAST, o.created_date DESC LIMIT 1) AS closer
    FROM meetings m
    WHERE m.meeting_type='call' AND m.project_id='$PID_ESC' AND m.status <> 'cancelled'
      AND (m.scheduled_start_time AT TIME ZONE 'UTC')::date BETWEEN '$DESDE' AND '$HASTA'
      AND coalesce(m.event_id, m.event->'booking'->>'appointment_id') NOT IN (SELECT id FROM ap)) x)
);")" || { DB_ESTADO=error; DB_JSON="{}"; }
printf '%s' "$DB_JSON" >"$TMP/db.json"

python3 -c 'import json,sys; json.dump({"ghl": sys.argv[1], "detalle": sys.argv[2] or None, "db": sys.argv[3]}, open(sys.argv[4],"w"))' \
  "$GHL_ESTADO" "$GHL_DETALLE" "$DB_ESTADO" "$TMP/fuente.json"

HERE="$HERE" python3 "$HERE/lib/agenda_lib.py" --dir "$TMP" --proyecto "$PNAME" --fecha "$FECHA" --vista "$VISTA" --ahora "$AHORA"
```

Notas de implementación que el script debe respetar:
- El bloque de ventana usa `HERE` como variable de entorno del heredoc Python: exportar antes (`export HERE`) o pasar la ruta como argumento; elegir **pasar `"$HERE/lib"` como tercer argumento** y hacer `sys.path.insert(0, sys.argv[3])` — más simple que exportar.
- Eliminar el heredoc vacío `python3 - "$TMP/eventos.json" <<<"$out" <<'PY' … PY` (residuo): el merge de eventos es el `python3 -c` que le sigue, que recibe `$out` por process substitution.
- `set -e` + `||`: cada llamada a `ghl_api`/`psql_ro` que puede fallar va dentro de `if out=$(…); then … else … fi` o con `|| { …; }` — nunca desnuda.

- [ ] **Step 2: Correr contra hoy y contra la semana; cuadrar con la sonda**

```bash
chmod +x bash/setters/agenda.sh
bash/setters/agenda.sh --json | python3 -c '
import json,sys; d=json.load(sys.stdin)
print(d["fuente"], d["kpis"]); print([ (c["hora"], c["lead"]["nombre"], c["banda"], c["closer"]["nombre"], c["sin_meet"], c["estado"]) for c in d["citas"]])
print("solo_en_sistema", d["solo_en_sistema"])'
bash/setters/agenda.sh --vista semana --fecha 2026-08-19 --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["ventana"], d["kpis"]["citas"])'
bash/ghl/appointments.sh --project David --desde -7 --hasta -1 --json | python3 -c '
import json,sys; from datetime import datetime; e=json.load(sys.stdin)
print(sum(1 for x in e if "2026-08-17" <= x["startTime"][:10] <= "2026-08-23"))'
```
Expected: `fuente.ghl == "ok"`, `fuente.db == "ok"`; el conteo de la semana 17–23 cuadra con la sonda filtrada por fecha; cada cita con `meeting` trae `meet_url`; las que están en `solo_en_sistema` coinciden con el drift `sobra_en_db` de `bash/intercepciones/drift.sh` para las mismas fechas.

- [ ] **Step 3: Simular fallos**

```bash
GHL_BASE=https://127.0.0.1:9 bash/setters/agenda.sh --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["fuente"], len(d["citas"]))'
```
Expected: `{'ghl': 'error', 'detalle': '…', 'db': 'ok', …} 0` y exit 0.

```bash
DATABASE_URL=postgres://invalida bash/setters/agenda.sh --json 2>/dev/null | head -c 200
```
Expected: sin base no hay credenciales de GHL (viven en Postgres) → el script sale con error claro por stderr y exit ≠ 0 — **ese caso no puede producir agenda** y se documenta así en el README (Task 3). Con base viva y GHL vivo pero la consulta grande fallando (p.ej. tabla renombrada) → `fuente.db == "error"` y las citas salen sin enriquecer.

- [ ] **Step 4: Commit**

```bash
git add bash/setters/agenda.sh
git commit -m "setters: agenda.sh — la agenda del setter desde GHL (citas + contactos en vivo) enriquecida con una consulta a Postgres"
```

---

### Task 3: README del dominio + sección en CLAUDE.md

**Files:**
- Create: `bash/setters/README.md`
- Modify: `CLAUDE.md` (después de la sección «Onboarding domain», antes de «ManyChat domain»)

- [ ] **Step 1: README**

```markdown
# bash/setters — la agenda del setter

El primer dominio del rol **Setter** (Antonio = Cristian Buelvas, Anthony
Velásquez): quienes califican, confirman y sostienen la agenda de llamadas del
equipo de closers, y desde el 2026-08-25 los únicos (junto con la IA) que
tocan el CRM. Spec: `docs/superpowers/specs/2026-08-26-agenda-setter-design.md`.

## Scripts

| Script | Para qué |
|--------|----------|
| `agenda.sh [--project N] [--fecha D] [--vista dia\|semana] [--json]` | La agenda del día o de la semana (lunes–domingo) como UN objeto: citas del calendario oficial de GHL, cada una con lead (contacto **en vivo**), closer asignado, link de Meet, etapa del tablero, **banda pre-llamada A/B/C** (entrantes) y **estado por capas** ocurrió · analizada (BANT) · venta (pasadas). Alertas: `sin_closer`, `sin_meet`, `solo_en_sistema` (drift). Read-only. Fuente viz `agenda_setter`. |
| `test.sh` | Tests puros de `lib/agenda_lib.py` (bandas, ventana, estado, ensamblado). |

## Reglas

- **GHL manda.** La agenda es la lista de citas de GHL. Postgres enriquece;
  nunca completa. Si GHL falla: `fuente.ghl = "error"` y `citas = []`.
- **Sin Postgres no hay agenda**: las credenciales de GHL viven en la base
  (`project_crm_configs`), así que la base caída es exit ≠ 0 con mensaje, no
  un objeto a medias. La base viva pero la consulta de enriquecimiento rota →
  `fuente.db = "error"` y las citas salen peladas.
- Contacto en vivo con fallback al espejo, declarado por fila (`lead.fuente`
  = `ghl` · `espejo` · `titulo`).
- `anunciada` es `null` hasta que exista el detector de anuncios del grupo
  ONLY CLOSERS (rutina de registro, pieza 1).
- Solo GET a GHL, `psql_ro` en Postgres, cerca por rol de `bash/ghl/`.
```

- [ ] **Step 2: Sección en CLAUDE.md** (insertar antes de `## ManyChat domain`)

```markdown
## Setters domain — la agenda del setter ([bash/setters/](bash/setters/))

El primer dominio del rol **Setter** (Antonio = Cristian Buelvas, Anthony
Velásquez — los únicos, con la IA, que tocan el CRM desde el 2026-08-25).
`agenda.sh [--project N] [--fecha D] [--vista dia|semana]` emite UN objeto: las
citas del **calendario oficial de GHL** (GHL manda; Postgres solo enriquece) con
el lead leído **en vivo** (el recién agendado existe en GHL antes que en el
espejo), closer asignado (`assignedUserId` → `users.integrations`; si es un
setter → `sin_closer`), link de Meet vía meeting (`event_id` = cita; sin meeting
→ `sin_meet`: no pasó por el webhook), etapa del tablero, **banda pre-llamada
A/B/C** (`docs/lead-score.md` §5, solo entrantes; el score 0-100 sigue sin
validar) y, para las pasadas, el **estado por capas**: `cancelada` · `venta`
(plan Active desde la cita) · `analizada` (reporte vigente + BANT) ·
`ocurrio_sin_analisis` (transcript/grabación) · `sin_rastro`. `anunciada`
(lo que el closer dijo en ONLY CLOSERS) es `null` en v1 — lo llena el detector
de anuncios de `docs/rutina-registro-only-closers-brief.md`. Alertas:
`solo_en_sistema` (drift `sobra_en_db`). GHL caído ≠ agenda vacía. Read-only.
Fuente viz `agenda_setter` → page `agenda-setter` (spec de rol
`viz/specs/roles/setter/agenda-setter.json`, publicada por usuario a los
setters y al DC). Spec: `docs/superpowers/specs/2026-08-26-agenda-setter-design.md`.
```

- [ ] **Step 3: Commit**

```bash
git add bash/setters/README.md CLAUDE.md
git commit -m "docs: dominio setters — README y sección en CLAUDE.md"
```

---

### Task 4: Fuente viz + página `agenda-setter` + spec de rol, con test de render

**Files:**
- Modify: `viz/lib/datasources.js` (añadir entrada en `SOURCES`, junto a `closer_dashboard`)
- Create: `viz/pages/agenda-setter.js`
- Create: `viz/specs/roles/setter/agenda-setter.json`
- Create: `viz/test/agenda-setter.test.js`

**Interfaces:**
- Consumes: fuente `agenda_setter` → `fetchSource("agenda_setter", {project, fecha, vista}).rows[0]` = objeto spec §2.4.
- Produces: página `agenda-setter` (`manifest: {consumes: "object", overridable: ["fecha", "vista", "project"]}`); `render(ui)` devuelve `<section id="pane">…`. Exporta además `renderObjeto(ui, d)` (render puro sobre un objeto ya cargado) para el test.

- [ ] **Step 1: Test de render que falla**

`viz/test/agenda-setter.test.js`:

```js
const { test } = require("node:test");
const assert = require("node:assert");
const page = require("../pages/agenda-setter");

const D = {
  proyecto: "David Guerrero",
  calendarios: [{ id: "CAL1", nombre: "Calendario Premium Mastermind", setters: ["Cristian Buelvas", "Anthony Velásquez"] }],
  ventana: { vista: "dia", fecha: "2026-08-26", desde: "2026-08-26", hasta: "2026-08-26", ahora: "2026-08-26T10:00" },
  fuente: { ghl: "ok", detalle: null, db: "ok", contactos_en_vivo: 2, contactos_espejo: 1 },
  kpis: { citas: 3, confirmadas: 2, canceladas: 1, banda_a: 1, sin_closer: 1, sin_meet: 2, pasadas: 1, ocurrieron: 1, analizadas: 1, ventas: 0, sin_rastro: 0 },
  citas: [
    { appointment_id: "AP3", fecha: "2026-08-26", hora: "08:00", fin: "08:20", estado_ghl: "cancelled", titulo: "Eva Ruiz - PM", creada_por: "booking_widget",
      pasada: true, estado: "cancelada", lead: { nombre: "Eva Ruiz", email: null, telefono: null, formulario: null, sesion: null, campana: null, tags: [], fuente: "titulo" },
      closer: { nombre: "Carlos González", user_id: "u-1", ghl_user_id: "CLO1" }, sin_closer: false,
      meeting: { id8: "aaaaaaaa", meet_url: "https://meet.google.com/aaa", status: "ended" }, sin_meet: false,
      etapa_crm: null, etapa_no_confirmada: true, banda: null, survey: [], historial: { llamadas_previas: 0, ultima: null, bant_previo: null },
      ocurrio: { transcript: true, grabacion: true }, reporte: { fuente: "cerebro", bant: { budget: 60, authority: 80, need: 70, timeline: 50, total: 65 }, baja_confianza: ["budget"], arquetipo: "Emocional", meeting_id8: "aaaaaaaa" },
      venta: null, anunciada: null },
    { appointment_id: "AP1", fecha: "2026-08-26", hora: "09:20", fin: "09:40", estado_ghl: "confirmed", titulo: "Ana Pérez - PM", creada_por: "booking_widget",
      pasada: false, estado: "proxima", lead: { nombre: "Ana Pérez", email: "ana@x.co", telefono: "+57 300", formulario: "Survey Mastermind", sesion: "Social media", campana: "Fly_test", tags: ["form mastermind"], fuente: "ghl" },
      closer: { nombre: "Carlos González", user_id: "u-1", ghl_user_id: "CLO1" }, sin_closer: false, meeting: null, sin_meet: true,
      etapa_crm: "LLAMADA CONFIRMADA", etapa_no_confirmada: false, banda: { letra: "A", presupuesto: "$1.500", disposicion: "Estoy listo para tomar acción e invertir" },
      survey: [{ campo: "¿Tienes al menos $1.500 USD para invertir?", valor: "$1.500" }, { campo: "País", valor: "Colombia <b>x</b>" }],
      historial: { llamadas_previas: 1, ultima: "2026-07-01", bant_previo: 55 }, ocurrio: { transcript: false, grabacion: false }, reporte: null, venta: null, anunciada: null },
    { appointment_id: "AP2", fecha: "2026-08-26", hora: "15:00", fin: "15:20", estado_ghl: "confirmed", titulo: "Luis Gil - PM", creada_por: "booking_widget",
      pasada: false, estado: "proxima", lead: { nombre: "Luis Gil", email: "luis@x.co", telefono: null, formulario: null, sesion: null, campana: null, tags: [], fuente: "espejo" },
      closer: { nombre: "Cristian Buelvas", user_id: "u-2", ghl_user_id: "SET1" }, sin_closer: true, meeting: null, sin_meet: true,
      etapa_crm: null, etapa_no_confirmada: true, banda: { letra: "B", presupuesto: "$500", disposicion: null }, survey: [],
      historial: { llamadas_previas: 0, ultima: null, bant_previo: null }, ocurrio: { transcript: false, grabacion: false }, reporte: null, venta: null, anunciada: null },
  ],
  solo_en_sistema: [{ id8: "bbbbbbbb", fecha: "2026-08-26", hora: "11:00", lead: "Javier Gutierrez", closer: "Carlos González" }],
  sin_instrumentar: ["anunciada: pendiente", "asistió/no asistió: GHL lo soporta"],
};
const UI = { id: "agenda-setter", source: "agenda_setter", params: { project: "David Guerrero", vista: "dia" } };

test("manifest", () => {
  assert.strictEqual(page.id, "agenda-setter");
  assert.deepStrictEqual(page.manifest, { consumes: "object", overridable: ["fecha", "vista", "project"] });
});

test("secciones, kpis y filas", () => {
  const h = page.renderObjeto(UI, D);
  assert.ok(h.startsWith('<section id="pane"'));
  assert.ok(h.includes("Por venir") && h.includes("Ya pasaron"));
  assert.ok(h.includes("Ana Pérez") && h.includes("Luis Gil") && h.includes("Eva Ruiz"));
  assert.ok(h.includes("https://meet.google.com/aaa"));
  assert.ok(h.includes("sin closer") && h.includes("sin Meet"));
  assert.ok(h.includes("Javier Gutierrez"));                      // solo en el sistema
  assert.ok(h.includes("Cristian Buelvas, Anthony Velásquez"));  // setters del calendario
  assert.ok(!h.includes("<b>x</b>") && h.includes("&lt;b&gt;x&lt;/b&gt;")); // escape del survey
  assert.ok(!/#[0-9a-f]{6}\b/i.test(h.replace(/#pane|#as-/g, "")), "sin hex en el markup");
});

test("banda solo en las por venir; BANT solo en las pasadas", () => {
  const h = page.renderObjeto(UI, D);
  const porVenir = h.slice(h.indexOf("Por venir"), h.indexOf("Ya pasaron"));
  const pasaron = h.slice(h.indexOf("Ya pasaron"));
  assert.ok(porVenir.includes(">A<") && porVenir.includes(">B<"));
  assert.ok(pasaron.includes("65") && pasaron.includes("Emocional") && pasaron.includes("⚠"));
  assert.ok(pasaron.includes("Cancelada"));
});

test("aviso cuando GHL falla y agenda vacía", () => {
  const h = page.renderObjeto(UI, { ...D, fuente: { ghl: "error", detalle: "HTTP 500", db: "ok" }, citas: [], kpis: { ...D.kpis, citas: 0 } });
  assert.ok(h.includes("GHL no respondió") && h.includes("HTTP 500"));
  assert.ok(!h.includes("Ana Pérez"));
});

test("vista semana agrupa por día", () => {
  const d = { ...D, ventana: { ...D.ventana, vista: "semana", desde: "2026-08-24", hasta: "2026-08-30" } };
  const h = page.renderObjeto(UI, d);
  assert.ok(h.includes("miércoles 26") || h.includes("mié 26"));
});
```

- [ ] **Step 2: Correr y ver que falla**

Run: `node --test viz/test/agenda-setter.test.js`
Expected: `Cannot find module '../pages/agenda-setter'`

- [ ] **Step 3: Entrada en `SOURCES`** (en `viz/lib/datasources.js`, justo después de la entrada `closer_dashboard`)

```js
  // La agenda del setter — GHL manda, Postgres enriquece. Vista operativa:
  // sin caché (cada render vuelve a GHL; ~30 GETs en semana, en paralelo).
  agenda_setter: {
    label: "Agenda del setter",
    script: "bash/setters/agenda.sh",
    emits: "object",
    args: { project: "--project", fecha: "--fecha", vista: "--vista" },
  },
```

- [ ] **Step 4: La página**

`viz/pages/agenda-setter.js`:

```js
// agenda-setter page — la agenda del setter (día / semana) desde el único
// objeto que emite bash/setters/agenda.sh. GHL manda: lo que se lista son las
// citas del calendario oficial; la base solo enriquece (Meet, BANT, plan).
//
// Dos secciones deliberadas, cortadas por la hora actual:
//   Por venir   cronológica, con la BANDA pre-llamada (A/B/C) — la capa de
//               operación de docs/lead-score.md §5, que el setter SÍ ve.
//   Ya pasaron  la más reciente primero, con el ESTADO POR CAPAS (ocurrió ·
//               analizada + BANT · venta) y «anunciada» en gris: promesa
//               visible, no medible aún (detector de anuncios, v2).
// Autosuficiente: sin /c/ (el publicador v1 no lo monta) — el detalle del lead
// viaja en el HTML y se despliega con una señal por fila.
const { fetchSource } = require("../lib/datasources");
const { escape, selectCtl } = require("../lib/kit");
const { cards } = require("../blocks/kpi-cards");

const ES_GHL = { confirmed: "Confirmada", new: "Nueva", cancelled: "Cancelada", showed: "Asistió", noshow: "No asistió", invalid: "Inválida" };
const ES_ESTADO = {
  proxima: ["Por venir", "brand"], cancelada: ["Cancelada", "muted"], venta: ["Venta", "pos"],
  analizada: ["Analizada", "pos"], ocurrio_sin_analisis: ["Ocurrió, sin análisis", "cau"], sin_rastro: ["Sin rastro", "neg"],
};
const DIAS = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"];
const TONE = { pos: "var(--pos-text)", neg: "var(--neg-text)", cau: "var(--cau-text)", brand: "var(--text-brand)", muted: "var(--text-3)" };
const BANDA_TONE = { A: "pos", B: "brand", C: "cau" };

const badge = (txt, tone = "brand", title = "") =>
  `<span class="badge" style="color:${TONE[tone]}"${title ? ` title="${escape(title)}"` : ""}>${escape(txt)}</span>`;

function diaLabel(iso) {
  const [y, m, d] = iso.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  return `${DIAS[(dt.getUTCDay() + 6) % 7]} ${d}`;
}
function sumarDias(iso, n) {
  const [y, m, d] = iso.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

function section(title, hint) {
  return `<div class="flex items-baseline gap-3 mt-8 mb-3 flex-wrap">
    <h2 class="text-sm font-bold uppercase tracking-wider" style="color:var(--text-2);letter-spacing:var(--tr-micro)">${escape(title)}</h2>
    ${hint ? `<span class="text-xs" style="color:var(--text-3)">${escape(hint)}</span>` : ""}
  </div>`;
}

function bantCell(r) {
  if (!r) return `<span style="color:var(--text-3)">—</span>`;
  const t = r.bant.total;
  const tone = t == null ? "muted" : t >= 81 ? "pos" : t >= 61 ? "brand" : "neg";
  const bc = (r.baja_confianza || []).length ? ` <span title="baja confianza: ${escape(r.baja_confianza.join(", "))}">⚠</span>` : "";
  return `<span class="tabular-nums font-semibold" style="color:${TONE[tone]}">${t == null ? "—" : t}</span>${bc}
    ${r.arquetipo ? `<span class="text-xs ml-1" style="color:var(--text-3)">${escape(r.arquetipo)}</span>` : ""}`;
}

function detalle(c, sig) {
  const kv = (k, v) => `<div class="flex gap-2 text-sm"><span style="color:var(--text-3);min-width:9rem">${escape(k)}</span><span>${v}</span></div>`;
  const l = c.lead;
  const survey = c.survey.length
    ? c.survey.map((s) => kv(s.campo, escape(s.valor))).join("")
    : `<p class="text-sm italic" style="color:var(--text-3)">Sin respuestas del survey.</p>`;
  const rep = c.reporte
    ? ["budget", "authority", "need", "timeline"].map((k) => kv(k, `<span class="tabular-nums">${c.reporte.bant[k] == null ? "—" : escape(String(c.reporte.bant[k]))}</span>${(c.reporte.baja_confianza || []).includes(k) ? " ⚠" : ""}`)).join("")
      + kv("arquetipo", escape(c.reporte.arquetipo || "—"))
      + kv("reporte", `<a class="link" href="/u/reporte-llamada?meeting=${escape(c.reporte.meeting_id8)}">ver reporte (${escape(c.reporte.fuente)})</a>`)
    : `<p class="text-sm italic" style="color:var(--text-3)">Sin reporte.</p>`;
  const venta = c.venta ? kv("plan", `${escape(c.venta.plan_id8)} · $${escape(String(c.venta.monto ?? "—"))} · ${escape(String(c.venta.cuotas ?? "—"))} cuotas · ${escape(c.venta.creado)}`) : "";
  const hist = c.historial.llamadas_previas
    ? kv("llamadas previas", `${c.historial.llamadas_previas} · última ${escape(c.historial.ultima || "—")}${c.historial.bant_previo != null ? ` · BANT ${escape(String(c.historial.bant_previo))}` : ""}`)
    : kv("llamadas previas", "ninguna");
  return `<tr data-show="$${sig}=='${escape(c.appointment_id)}'" style="display:none"><td colspan="9" style="background:var(--surface-2)">
    <div class="grid gap-6 p-3" style="grid-template-columns:repeat(auto-fit,minmax(18rem,1fr))">
      <div>${kv("correo", escape(l.email || "—"))}${kv("teléfono", escape(l.telefono || "—"))}${kv("formulario", escape(l.formulario || "—"))}
           ${kv("origen", escape([l.sesion, l.campana].filter(Boolean).join(" · ") || "—"))}${kv("tags", escape((l.tags || []).join(", ") || "—"))}
           ${kv("datos del lead", escape({ ghl: "en vivo (GHL)", espejo: "espejo (la base)", titulo: "solo el título de la cita" }[l.fuente] || l.fuente))}
           ${hist}${kv("cita GHL", escape(c.appointment_id))}${c.meeting ? kv("llamada", escape(c.meeting.id8)) : ""}</div>
      <div><p class="text-xs font-bold uppercase mb-1" style="color:var(--text-2)">Survey</p>${survey}</div>
      <div><p class="text-xs font-bold uppercase mb-1" style="color:var(--text-2)">Reporte de la llamada</p>${rep}${venta}</div>
    </div></td></tr>`;
}

function fila(c, sig) {
  const cancel = c.estado_ghl === "cancelled";
  const dim = cancel ? ` style="color:var(--text-3)"` : "";
  const closer = c.closer.nombre ? escape(c.closer.nombre) : "—";
  const closerCell = c.sin_closer ? `${closer} ${badge("sin closer", "cau", "la cita está asignada a un setter o a nadie")}` : closer;
  const meet = c.meeting && c.meeting.meet_url
    ? `<a class="link" href="${escape(c.meeting.meet_url)}" target="_blank" rel="noopener">Meet</a>`
    : c.sin_meet ? badge("sin Meet", "neg", "no pasó por el webhook: no habrá grabación ni análisis") : "—";
  const etapa = c.etapa_crm ? `${escape(c.etapa_crm)}${c.etapa_no_confirmada ? " " + badge("≠ confirmada", "cau") : ""}` : `<span style="color:var(--text-3)">— (espejo)</span>`;
  const [estTxt, estTone] = ES_ESTADO[c.estado] || [c.estado, "muted"];
  const ocurrio = c.pasada ? [c.ocurrio.transcript ? "transcript" : null, c.ocurrio.grabacion ? "grabación" : null].filter(Boolean).join(" · ") || "—" : "";
  const bandaCell = !c.pasada && c.banda ? badge(c.banda.letra, BANDA_TONE[c.banda.letra], `${c.banda.presupuesto || "sin presupuesto"} · ${c.banda.disposicion || "sin disposición"}`) : "";
  const anunciada = c.pasada ? `<span style="color:var(--text-3)" title="pendiente de conectar al grupo ONLY CLOSERS">—</span>` : "";
  const ultimas = c.pasada
    ? `<td>${escape(ocurrio)}</td><td>${bantCell(c.reporte)}</td><td>${c.venta ? badge("venta", "pos") : "—"}</td><td>${anunciada}</td>`
    : `<td>${bandaCell}</td><td colspan="3"></td>`;
  return `<tr${dim} class="cursor-pointer" data-on:click="$${sig} = $${sig}=='${escape(c.appointment_id)}' ? '' : '${escape(c.appointment_id)}'">
    <td class="tabular-nums whitespace-nowrap">${escape(c.hora)}</td>
    <td class="font-medium">${escape(c.lead.nombre || "—")}</td>
    <td>${closerCell}</td>
    <td>${meet}</td>
    <td>${badge(ES_GHL[c.estado_ghl] || c.estado_ghl || "—", cancel ? "muted" : "brand")} ${badge(estTxt, estTone)}</td>
    <td class="text-xs">${etapa}</td>
    ${ultimas}
  </tr>${detalle(c, sig)}`;
}

function tabla(citas, sig, pasadas, vacio) {
  if (!citas.length) return `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)">${escape(vacio)}</p>`;
  const th = pasadas
    ? ["Hora", "Lead", "Closer", "Meet", "Estado", "Etapa CRM", "Ocurrió", "BANT", "Venta", "Anunciada"]
    : ["Hora", "Lead", "Closer", "Meet", "Estado", "Etapa CRM", "Banda", "", "", ""];
  return `<div class="table-wrap"><div class="table-scroll"><table class="tbl">
    <thead><tr>${th.map((h) => `<th>${escape(h)}</th>`).join("")}</tr></thead>
    <tbody>${citas.map((c) => fila(c, sig)).join("")}</tbody></table></div></div>`;
}

function bloqueDia(citas, ahora, sig, conTitulo) {
  const prox = citas.filter((c) => !c.pasada);
  const pas = citas.filter((c) => c.pasada).slice().reverse();
  const head = conTitulo ? section(`${diaLabel(citas[0].fecha)}`, `${citas.length} citas`) : "";
  return `${head}
    ${section("Por venir", prox.length ? `${prox.length} citas` : "")}
    ${tabla(prox, sig, false, "Nada por venir.")}
    ${section("Ya pasaron", pas.length ? `${pas.length} citas · la más reciente primero` : "")}
    ${tabla(pas, sig, true, "Ninguna todavía.")}`;
}

function renderObjeto(ui, d) {
  const p = Object.assign({}, ui.params || {});
  const v = d.ventana;
  const sig = "asSel";
  const semana = v.vista === "semana";
  const paso = semana ? 7 : 1;
  const base = `/u/${escape(ui.id)}?vista=${escape(v.vista)}&fecha=`;
  const nav = `<div class="flex flex-wrap items-center gap-3" data-signals="{asVista:'${escape(v.vista)}',asFecha:'${escape(v.fecha)}',loadingas:false}">
    <a class="btn" href="${base}${sumarDias(v.fecha, -paso)}">←</a>
    <input type="date" data-bind="asFecha" data-on:change="@get('/ui/${escape(ui.id)}?vista='+$asVista+'&fecha='+$asFecha)" data-indicator:loadingas class="input w-auto" />
    <a class="btn" href="${base}${sumarDias(v.fecha, paso)}">→</a>
    ${selectCtl("asVista", v.vista, [["dia", "Día"], ["semana", "Semana"]], `@get('/ui/${escape(ui.id)}?vista='+$asVista+'&fecha='+$asFecha)`, "loadingas")}
    <span class="text-sm" style="color:var(--text-3)">${escape(d.proyecto || "")} · ${semana ? `${escape(diaLabel(v.desde))} → ${escape(diaLabel(v.hasta))}` : escape(diaLabel(v.fecha))} · ahora ${escape(v.ahora.slice(11))}</span>
  </div>`;

  const avisos = [];
  if (d.fuente.ghl !== "ok") avisos.push(`<div class="alert alert-neg">GHL no respondió — la agenda no se puede listar desde la base (GHL manda). ${escape(d.fuente.detalle || "")}</div>`);
  if (d.fuente.db === "error") avisos.push(`<div class="alert alert-cau">La base no respondió: las citas salen sin Meet, BANT ni plan.</div>`);
  const cals = (d.calendarios || []).map((c) => `${escape(c.nombre || c.id)} — setters: ${escape((c.setters || []).join(", ") || "—")}`).join(" · ");
  const meta = `<p class="text-xs mt-2" style="color:var(--text-3)">${cals} · contactos en vivo ${d.fuente.contactos_en_vivo ?? 0} / espejo ${d.fuente.contactos_espejo ?? 0}</p>`;

  const k = d.kpis;
  const kpisProx = cards([
    { key: "citas", label: "Citas", fmt: "int", tone: "brand", title: "citas en GHL en la ventana, todos los estados" },
    { key: "confirmadas", label: "Confirmadas", fmt: "int", tone: "pos" },
    { key: "banda_a", label: "Banda A", fmt: "int", tone: "pos", title: "declara ≥ $1.500 y está listo para tomar acción — se confirma primero" },
    { key: "sin_closer", label: "Sin closer", fmt: "int", tone: k.sin_closer ? "cau" : "muted", title: "asignadas a un setter o a nadie" },
    { key: "sin_meet", label: "Sin Meet", fmt: "int", tone: k.sin_meet ? "neg" : "muted", title: "no pasaron por el webhook: no habrá grabación ni análisis" },
    { key: "canceladas", label: "Canceladas", fmt: "int", tone: "muted" },
  ], k);
  const kpisPas = cards([
    { key: "pasadas", label: "Ya pasaron", fmt: "int", tone: "brand" },
    { key: "ocurrieron", label: "Ocurrieron", fmt: "int", tone: "pos", title: "transcript usable o grabación" },
    { key: "analizadas", label: "Analizadas", fmt: "int", tone: "pos", title: "con reporte BANT vigente" },
    { key: "ventas", label: "Ventas", fmt: "int", tone: "pos", title: "plan de pago activo creado desde la cita" },
    { key: "sin_rastro", label: "Sin rastro", fmt: "int", tone: k.sin_rastro ? "neg" : "muted", title: "ni grabación, ni transcript, ni plan — ¿qué pasó?" },
    { label: "Anunciadas", fmt: "int", value: null, muted: true, title: "pendiente de conectar al grupo ONLY CLOSERS" },
  ], k);

  let cuerpo;
  if (!d.citas.length) {
    cuerpo = `<p class="text-sm italic px-1 py-4" style="color:var(--text-3)">Sin citas en la ventana.</p>`;
  } else if (!semana) {
    cuerpo = bloqueDia(d.citas, v.ahora, sig, false);
  } else {
    const porDia = new Map();
    for (const c of d.citas) (porDia.get(c.fecha) || porDia.set(c.fecha, []).get(c.fecha)).push(c);
    cuerpo = [...porDia.keys()].sort().map((f) => bloqueDia(porDia.get(f), v.ahora, sig, true)).join("");
  }

  const solo = d.solo_en_sistema.length
    ? `<div class="table-wrap"><div class="table-scroll"><table class="tbl"><thead><tr><th>Fecha</th><th>Hora</th><th>Lead</th><th>Closer</th><th>Llamada</th></tr></thead><tbody>
        ${d.solo_en_sistema.map((s) => `<tr><td>${escape(s.fecha)}</td><td class="tabular-nums">${escape(s.hora)}</td><td>${escape(s.lead || "—")}</td><td>${escape(s.closer || "—")}</td><td class="text-xs">${escape(s.id8)}</td></tr>`).join("")}
      </tbody></table></div></div>`
    : `<p class="text-sm italic px-1 py-2" style="color:var(--text-3)">Ninguna — el sistema y GHL coinciden.</p>`;

  return `<section id="pane" class="flex-1 relative overflow-auto p-6" data-signals="{${sig}:''}">
    <style>#as-loading{opacity:0;transition:opacity .2s ease}#as-loading.on{opacity:1}</style>
    <div id="as-loading" data-class:on="$loadingas" class="pointer-events-none absolute inset-0 z-10 flex items-start justify-center pt-16 bg-white/50">
      <div class="w-7 h-7 rounded-full border-2 border-slate-300 border-t-indigo-600 animate-spin"></div>
    </div>
    <div class="max-w-6xl mx-auto">
      ${nav}${meta}
      ${avisos.join("")}
      <div class="mt-6">${kpisProx}</div>
      ${kpisPas}
      ${cuerpo}
      ${section("En el sistema, no en GHL", "llamadas agendadas en la base que el calendario oficial no tiene — para corregir la agenda")}
      ${solo}
      <ul class="text-xs mt-8 list-disc pl-5" style="color:var(--text-3)">${d.sin_instrumentar.map((s) => `<li>${escape(s)}</li>`).join("")}</ul>
    </div>
  </section>`;
}

function render(ui) {
  const p = Object.assign({}, ui.params || {});
  const params = { project: p.project, fecha: p.fecha, vista: p.vista };
  let d, err;
  try {
    d = fetchSource(ui.source || "agenda_setter", params).rows[0];
  } catch (e) {
    err = e.message;
  }
  if (err || !d) {
    return `<section id="pane" class="flex-1 p-6 overflow-auto"><div class="alert alert-neg">No se pudo cargar la agenda: ${escape(err || "sin datos")}</div></section>`;
  }
  return renderObjeto(ui, d);
}

module.exports = {
  id: "agenda-setter",
  manifest: { consumes: "object", overridable: ["fecha", "vista", "project"] },
  render,
  renderObjeto,
};
```

Verificaciones al escribir: (1) las clases `.badge`, `.alert`, `.alert-neg`, `.alert-cau`, `.link`, `.btn`, `.input`, `.select`, `.table-wrap`, `.table-scroll`, `.tbl` existen en `viz/public/tokens.css` — `grep -c "\.alert-neg\|\.badge\|\.link" viz/public/tokens.css`; si `.alert-neg`/`.alert-cau`/`.link` no existen, usar `class="alert"` con `style="color:var(--neg-text)"` y `<a class="underline">`. (2) La URL del reporte: el spec publicado del reporte del closer se llama `reporte-llamada` (`viz/specs/roles/closer/reporte-llamada.json`); confirmar el `id` con `grep '"id"' viz/specs/roles/closer/reporte-llamada.json`. (3) `data-show` con `style="display:none"` inicial sigue el patrón de `pages/plan-reactivacion.js:58`.

- [ ] **Step 5: Spec de rol**

`viz/specs/roles/setter/agenda-setter.json`:

```json
{
  "id": "agenda-setter",
  "name": "Agenda del setter",
  "component": "agenda-setter",
  "source": "agenda_setter",
  "params": { "project": "David Guerrero", "vista": "dia" },
  "scope": "role",
  "role": "setter",
  "created_at": "2026-08-26T00:00:00.000Z"
}
```

- [ ] **Step 6: Correr los tests**

Run: `node --test viz/test/agenda-setter.test.js`
Expected: 5 pass. Si falla «sin hex»: buscar el hex en el markup y cambiarlo por token.

- [ ] **Step 7: Commit**

```bash
git add viz/lib/datasources.js viz/pages/agenda-setter.js viz/specs/roles/setter/agenda-setter.json viz/test/agenda-setter.test.js
git commit -m "viz(agenda-setter): fuente agenda_setter + página día/semana con bandas y estado por capas + spec de rol setter"
```

---

### Task 5: Smoke en el viz local, publicación y permisos, higiene de rol

**Files:**
- Modify: `docs/roles/setter.md` (cabecera «Quiénes» y «Capa de rol»)

- [ ] **Step 1: Reiniciar el viz y verificar el render en vivo**

```bash
npm run viz:restart
curl -s "http://localhost:4317/u/agenda-setter" | grep -o "Por venir\|Ya pasaron\|GHL no respondió\|Sin citas" | sort -u
curl -s "http://localhost:4317/u/agenda-setter?vista=semana&fecha=2026-08-19" | grep -o "lunes 17\|martes 18\|miércoles 19\|jueves 20\|viernes 21" | sort -u
```
Expected: la primera muestra `Por venir` y `Ya pasaron` (o `Sin citas` si hoy no hay); la segunda lista los días con citas de esa semana. Abrir en el navegador en modo claro y oscuro (botón ◐), desplegar un lead y comprobar survey + Meet.

- [ ] **Step 2: Publicar (dry-run, luego real) y dar permisos**

```bash
bash/publicar/publicar_ui.sh agenda-setter --slug agenda-setter --dry-run
bash/publicar/publicar_ui.sh agenda-setter --slug agenda-setter --json
for e in buelvascristian38@gmail.com antonivelasquez2014@gmail.com luisda262003@gmail.com; do
  bash/publicar/permiso_ui.sh agenda-setter --user "$e" --sin-identidad
done
bash/publicar/permiso_ui.sh agenda-setter --listar
```
Expected: despliegue generación 1 en `https://app.ikigaigm.parallelo.ai/agenda-setter`; tres permisos por usuario con `params_identidad = '{}'`. Si `permiso_ui.sh` avisa que el correo no tiene usuario en la app: Cristian necesita cuenta (Anthony la tiene desde el 03-ago) — crearla con `/crear-usuario` **solo si Santiago lo confirma**; dejar el permiso pendiente y decirlo en el reporte final. Antes de publicar el código nuevo hay que desplegarlo: `bash/publicar/desplegar.sh` (push + pull en el servidor + restart), ya que el publicador corre el código del repo.

- [ ] **Step 3: Higiene documental del rol**

En `docs/roles/setter.md` reemplazar las tres primeras líneas de datos por:

```markdown
**Quiénes:** Antonio = Cristian Buelvas (setter estructural desde feb-2026) y Anthony Velásquez (desde el 03-ago-2026). Ambos figuran aún como *Closer* en `team_members`/`team_roles` — higiene pendiente. Mateo Restrepo (el «setter» de este doc en julio) es closer.
**Capa de rol (viz):** `viz/specs/roles/setter/` — `agenda-setter` (2026-08-26; publicada por usuario en la app).
**Tareas históricas:** 0 asignadas · 0 etiquetadas con arquetipo · 0 abiertas hoy
```

y añadir al final de «Notas y brechas»:

```markdown
- **2026-08-26 — Agenda del setter** (`bash/setters/agenda.sh` + UI `agenda-setter`): GHL manda, banda A/B/C para las entrantes, estado por capas para las pasadas. «Anunciada por el closer» queda pendiente del detector de anuncios de ONLY CLOSERS. Spec: `docs/superpowers/specs/2026-08-26-agenda-setter-design.md`.
```

- [ ] **Step 4: Commit y desplegar**

```bash
git add docs/roles/setter.md
git commit -m "docs(roles): setter — quiénes son de verdad y su primera UI (agenda-setter)"
bash/publicar/desplegar.sh --dry-run && bash/publicar/desplegar.sh
```
Expected: push a `origin` + pull en `/apps/hermetico` + `pm2 restart viz-publish` sin errores; `curl -s -o /dev/null -w '%{http_code}' https://app.ikigaigm.parallelo.ai/health` → 200.

---

## Self-review

- **Spec coverage**: §1 alcance → Tasks 2-5; §2.1 algoritmo (calendarios+miembros, citas, contacto en vivo en tandas, catálogo, consulta única, solo_en_sistema, reloj) → Task 2; §2.2 bandas → Task 1; §2.3 estado y banderas → Task 1 (`estado`, `sin_closer`, `sin_meet`, `etapa_no_confirmada`); §2.4 contrato → Task 1 `armar` (mismas claves); §2.5 errores → Task 2 (`GHL_ESTADO`/`DB_ESTADO`) + README (sin base = exit ≠ 0, declarado); §3 página (cabecera, KPIs con «Anunciadas» muted, día/semana, fila, detalle, alertas, tema) → Task 4; §4 registro/publicación/higiene → Tasks 4-5; §5 verificación → Task 1 Step 4, Task 2 Steps 2-3, Task 4 Step 6, Task 5 Step 1.
- **Placeholders**: ninguno; el residuo del heredoc vacío en Task 2 está señalado para borrarse.
- **Consistencia de nombres**: `agenda_setter` (fuente) / `agenda-setter` (página, spec, slug); claves del objeto idénticas entre `armar`, el test Python, el fixture JS y la página (`estado_ghl`, `sin_closer`, `sin_meet`, `etapa_no_confirmada`, `banda.letra`, `reporte.bant.total`, `solo_en_sistema`, `sin_instrumentar`).

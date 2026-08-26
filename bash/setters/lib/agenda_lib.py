#!/usr/bin/env python3
"""agenda_lib — el ensamblado PURO de la agenda del setter (spec
docs/superpowers/specs/2026-08-26-agenda-setter-design.md).

Sin red ni base: recibe lo que agenda.sh ya trajo (citas de GHL, contactos en
vivo, una consulta a Postgres) y emite el objeto de la fuente `agenda_setter`.
Todo lo que se puede probar sin credenciales vive aquí (test_agenda_lib.py).
"""
import argparse, json, os, re, sys
from datetime import date, datetime, timedelta, timezone

BOGOTA = timezone(timedelta(hours=-5))
SIN_INSTRUMENTAR = [
    "anunciada: el desenlace que el closer anuncia en ONLY CLOSERS no se persiste aún (detector de anuncios, sub-proyecto 2)",
    "asistió/no asistió: GHL lo soporta (showed/noshow) y nadie lo marca; el setter puede empezar hoy",
]
# Dos preguntas de presupuesto conviven en el CRM: la VALIDADA contra plata en
# docs/lead-score.md («¿Tienes al menos $1.500 USD…?», valores «Tengo $500…»)
# y la del survey vigente («…describe tu situación financiera actual», valores
# en rangos «entre 500 y 1000», «más de 5000»). Si un lead trae las dos, manda
# la validada; el corte ≥1500 sobre la nueva NO está validado aún.
RE_PRES_VALIDADA = re.compile(r"al menos \$?\s*1[.,]?500", re.I)
RE_PRES_VIGENTE = re.compile(r"situaci[oó]n financiera actual", re.I)
RE_DISPOSICION = re.compile(r"situaci[oó]n te encuentras actualmente", re.I)


# --- reglas puras -----------------------------------------------------------
def monto_declarado(texto):
    """USD que el lead DECLARA tener, leído del texto de la respuesta.
    «entre A y B» → A (la cota que seguro tiene) · «más de N» → N ·
    «menos de N» / «no cuento con dinero» → 0 · «$1.500» → 1500 ·
    sin número → None (respondido pero irreconocible)."""
    t = (texto or "").lower().replace(".", "").replace(",", "")
    if not t.strip():
        return None
    if "no cuento" in t or "no tengo" in t:
        return 0
    nums = [int(n) for n in re.findall(r"\d+", t)]
    if not nums:
        return None
    if "menos de" in t:
        return 0
    return nums[0]


def banda(presupuesto, disposicion):
    """A/B/C de docs/lead-score.md §5. Un presupuesto no reconocido cuenta
    como respondido (B): nunca se descarta un lead por un rótulo nuevo."""
    p = (presupuesto or "").strip()
    d = (disposicion or "").strip()
    if not p and not d:
        return "C"
    monto = monto_declarado(p)
    alto = monto is not None and monto >= 1500
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
    if isinstance(campos, str):
        try:
            campos = json.loads(campos)
        except ValueError:
            campos = []
    survey, pres_val, pres_vig, disp = [], None, None, None
    for f in sorted(campos, key=lambda f: orden.get(f.get("id"), 9999)):
        v = f.get("value")
        if v in (None, "", []):
            continue
        v = v if isinstance(v, str) else json.dumps(v, ensure_ascii=False)
        nom = (nombres.get(f.get("id")) or {}).get("name") or f.get("id")
        survey.append({"campo": nom, "valor": v})
        if RE_PRES_VALIDADA.search(nom):
            pres_val = v
        elif RE_PRES_VIGENTE.search(nom):
            pres_vig = v
        elif RE_DISPOSICION.search(nom):
            disp = v
    pres = pres_val or pres_vig
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
    usuarios = {u["ghl_user_id"]: u for u in db.get("usuarios") or [] if u.get("ghl_user_id")}
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
        hc = hist.get(cid)
        cita = {
            "appointment_id": ev["id"], "fecha": f, "hora": h, "fin": fin,
            "estado_ghl": ev.get("appointmentStatus"), "titulo": ev.get("title"),
            "creada_por": (ev.get("createdBy") or {}).get("source"),
            "pasada": pasada, "estado": None,
            "lead": lead, "closer": closer, "sin_closer": sin_closer,
            "meeting": meeting, "sin_meet": meeting is None,
            "etapa_crm": etapa, "etapa_no_confirmada": (etapa or "").strip().lower() != "llamada confirmada",
            "banda": None if pasada else bnd, "survey": survey,
            "historial": ({k: hc.get(k) for k in ("llamadas_previas", "ultima", "bant_previo")} if hc
                          else {"llamadas_previas": 0, "ultima": None, "bant_previo": None}),
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

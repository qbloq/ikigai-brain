#!/usr/bin/env python3
"""disponibilidad_lib — el ensamblado PURO de la matriz semanal de
disponibilidad de closers (closers × días, calendario de venta).

Sin red ni base: recibe lo que disponibilidad.sh ya trajo (miembros del
calendario resueltos a nombre, free-slots de GHL por closer, appointments de
la semana) y emite el objeto de la fuente `disponibilidad_closers`.

La verdad es GHL: `libres` son los huecos que su endpoint free-slots calcula
(configuración de disponibilidad del closer menos sus citas) — aquí no se
inventa horario laboral. Días pasados: GHL no da huecos hacia atrás, la celda
sale `pasado` con sus citas y `libres: []` (declarado, no inventado).
"""
import argparse, json, sys
from datetime import date, timedelta

from agenda_lib import hora_bogota


def dias_semana(fecha):
    """Los 7 días (lunes–domingo) de la semana de `fecha`, como ISO strings."""
    lunes = fecha - timedelta(days=fecha.weekday())
    return [(lunes + timedelta(days=i)).isoformat() for i in range(7)]


def _estado(dia, hoy, libres, citas):
    if dia < hoy:
        return "pasado"
    if libres:
        return "normal"
    return "lleno" if citas else "sin_horario"


def _lead(titulo):
    import re
    return re.sub(r"\s*[-|–]\s*.*$", "", titulo or "").strip() or None


def armar(ctx):
    fecha = date.fromisoformat(ctx["fecha"])
    dias = dias_semana(fecha)
    hoy = ctx["ahora"][:10]
    miembros = {c["ghl_user_id"] for c in ctx.get("closers") or []}

    # citas por (closer, día); las de un asignado que no es miembro (un setter,
    # o nadie resoluble) no se botan: van a `sin_closer`, declaradas.
    por_celda, sin_closer = {}, []
    for ev in ctx.get("eventos") or []:
        if ev.get("appointmentStatus") == "cancelled":
            continue
        f, h = hora_bogota(ev["startTime"])
        if f not in dias:
            continue
        fin = hora_bogota(ev["endTime"])[1] if ev.get("endTime") else None
        cita = {"appointment_id": ev.get("id"), "hora": h, "fin": fin,
                "lead": _lead(ev.get("title")), "estado_ghl": ev.get("appointmentStatus")}
        uid = ev.get("assignedUserId")
        if uid in miembros:
            por_celda.setdefault((uid, f), []).append(cita)
        else:
            sin_closer.append({**cita, "fecha": f, "assigned_user_id": uid})

    closers = []
    for c in sorted(ctx.get("closers") or [], key=lambda c: c.get("nombre") or ""):
        uid = c["ghl_user_id"]
        slots_de = ctx.get("slots", {}).get(uid) or {}
        fila_dias, tl, tc = {}, 0, 0
        for d in dias:
            citas = sorted(por_celda.get((uid, d), []), key=lambda x: x["hora"])
            libres = [] if d < hoy else sorted(hora_bogota(s)[1] for s in slots_de.get(d) or [])
            fila_dias[d] = {"libres": libres, "citas": citas,
                            "estado": _estado(d, hoy, libres, citas)}
            tl += len(libres); tc += len(citas)
        closers.append({**c, "dias": fila_dias, "total_libres": tl, "total_citas": tc})

    return {
        "proyecto": ctx.get("proyecto"),
        "calendario": ctx.get("calendario"),
        "semana": {"fecha": ctx["fecha"], "desde": dias[0], "hasta": dias[-1],
                   "dias": dias, "ahora": ctx["ahora"]},
        "fuente": ctx.get("fuente") or {},
        "closers": closers,
        "sin_closer": sorted(sin_closer, key=lambda x: (x["fecha"], x["hora"])),
    }


# --- CLI (lo llama disponibilidad.sh) ----------------------------------------
def _leer(path, default):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True); ap.add_argument("--proyecto", required=True)
    ap.add_argument("--fecha", required=True); ap.add_argument("--ahora", required=True)
    a = ap.parse_args(argv)
    d = a.dir
    ctx = {"proyecto": a.proyecto, "fecha": a.fecha, "ahora": a.ahora,
           "fuente": _leer(f"{d}/fuente.json", {"ghl": "error", "detalle": "sin fuente.json", "db": "error"}),
           "calendario": _leer(f"{d}/calendario.json", None),
           "closers": _leer(f"{d}/closers.json", []),
           "slots": _leer(f"{d}/slots.json", {}),
           "eventos": _leer(f"{d}/eventos.json", [])}
    json.dump(armar(ctx), sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()

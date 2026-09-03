import unittest
from datetime import date
import disponibilidad_lib as D


def ctx(**kw):
    """Contexto mínimo: semana del lunes 2026-08-31, «ahora» miércoles 02 10:00."""
    base = {
        "proyecto": "David Guerrero",
        "fecha": "2026-09-02",
        "ahora": "2026-09-02T10:00",
        "fuente": {"ghl": "ok", "db": "ok"},
        "calendario": {"id": "CAL1", "nombre": "Aplicación a Premium Mastermind"},
        "closers": [
            {"ghl_user_id": "U1", "nombre": "Carlos González", "user_id": "uu1"},
            {"ghl_user_id": "U2", "nombre": "Ayrton Vega", "user_id": "uu2"},
        ],
        "slots": {},
        "eventos": [],
    }
    base.update(kw)
    return base


class DiasSemana(unittest.TestCase):
    def test_lunes_a_domingo(self):
        # 2026-09-02 es miércoles → semana 08-31 .. 09-06
        self.assertEqual(D.dias_semana(date(2026, 9, 2))[0], "2026-08-31")
        self.assertEqual(D.dias_semana(date(2026, 9, 2))[-1], "2026-09-06")
        self.assertEqual(len(D.dias_semana(date(2026, 9, 2))), 7)


class Armar(unittest.TestCase):
    def test_forma_general(self):
        r = D.armar(ctx())
        self.assertEqual(r["proyecto"], "David Guerrero")
        self.assertEqual(r["semana"]["desde"], "2026-08-31")
        self.assertEqual(r["semana"]["hasta"], "2026-09-06")
        self.assertEqual(len(r["semana"]["dias"]), 7)
        self.assertEqual([c["nombre"] for c in r["closers"]],
                         ["Ayrton Vega", "Carlos González"])  # orden alfabético
        for c in r["closers"]:
            self.assertEqual(sorted(c["dias"].keys()), r["semana"]["dias"])

    def test_celda_normal_slots_en_hora_bogota(self):
        r = D.armar(ctx(slots={"U1": {"2026-09-03": [
            "2026-09-03T08:00:00-05:00", "2026-09-03T14:30:00-05:00"]}}))
        carlos = next(c for c in r["closers"] if c["ghl_user_id"] == "U1")
        celda = carlos["dias"]["2026-09-03"]
        self.assertEqual(celda["libres"], ["08:00", "14:30"])
        self.assertEqual(celda["estado"], "normal")

    def test_cita_cae_en_la_celda_de_su_closer(self):
        r = D.armar(ctx(eventos=[{
            "id": "AP1", "assignedUserId": "U2", "appointmentStatus": "confirmed",
            "startTime": "2026-09-03T09:00:00-05:00", "endTime": "2026-09-03T09:30:00-05:00",
            "title": "Juan Pérez - Aplicación",
        }]))
        ayrton = next(c for c in r["closers"] if c["ghl_user_id"] == "U2")
        citas = ayrton["dias"]["2026-09-03"]["citas"]
        self.assertEqual(len(citas), 1)
        self.assertEqual(citas[0]["hora"], "09:00")
        self.assertEqual(citas[0]["lead"], "Juan Pérez")
        self.assertEqual(citas[0]["appointment_id"], "AP1")

    def test_cancelada_no_ocupa(self):
        r = D.armar(ctx(eventos=[{
            "id": "AP2", "assignedUserId": "U1", "appointmentStatus": "cancelled",
            "startTime": "2026-09-03T09:00:00-05:00", "title": "X",
        }]))
        carlos = next(c for c in r["closers"] if c["ghl_user_id"] == "U1")
        self.assertEqual(carlos["dias"]["2026-09-03"]["citas"], [])

    def test_estado_sin_horario_vs_lleno(self):
        r = D.armar(ctx(eventos=[{
            "id": "AP3", "assignedUserId": "U1", "appointmentStatus": "confirmed",
            "startTime": "2026-09-04T09:00:00-05:00", "title": "Y",
        }]))
        carlos = next(c for c in r["closers"] if c["ghl_user_id"] == "U1")
        ayrton = next(c for c in r["closers"] if c["ghl_user_id"] == "U2")
        # día futuro, 0 libres + citas → lleno; 0 libres + 0 citas → sin_horario
        self.assertEqual(carlos["dias"]["2026-09-04"]["estado"], "lleno")
        self.assertEqual(ayrton["dias"]["2026-09-04"]["estado"], "sin_horario")

    def test_dia_pasado(self):
        # el lunes 08-31 ya pasó («ahora» = miércoles): estado pasado, sin libres,
        # pero las citas que hubo sí se muestran.
        r = D.armar(ctx(eventos=[{
            "id": "AP4", "assignedUserId": "U1", "appointmentStatus": "showed",
            "startTime": "2026-08-31T11:00:00-05:00", "title": "Z",
        }]))
        carlos = next(c for c in r["closers"] if c["ghl_user_id"] == "U1")
        celda = carlos["dias"]["2026-08-31"]
        self.assertEqual(celda["estado"], "pasado")
        self.assertEqual(celda["libres"], [])
        self.assertEqual(len(celda["citas"]), 1)

    def test_cita_sin_closer_resoluble_va_aparte(self):
        r = D.armar(ctx(eventos=[{
            "id": "AP5", "assignedUserId": "SETTER9", "appointmentStatus": "confirmed",
            "startTime": "2026-09-03T10:00:00-05:00", "title": "Lead Sin Closer",
        }]))
        self.assertEqual(len(r["sin_closer"]), 1)
        self.assertEqual(r["sin_closer"][0]["appointment_id"], "AP5")
        for c in r["closers"]:
            self.assertEqual(c["dias"]["2026-09-03"]["citas"], [])

    def test_totales_por_closer(self):
        r = D.armar(ctx(
            slots={"U1": {"2026-09-03": ["2026-09-03T08:00:00-05:00"],
                          "2026-09-04": ["2026-09-04T08:00:00-05:00", "2026-09-04T09:00:00-05:00"]}},
            eventos=[{"id": "AP6", "assignedUserId": "U1", "appointmentStatus": "confirmed",
                      "startTime": "2026-09-03T09:00:00-05:00", "title": "T"}]))
        carlos = next(c for c in r["closers"] if c["ghl_user_id"] == "U1")
        self.assertEqual(carlos["total_libres"], 3)
        self.assertEqual(carlos["total_citas"], 1)


if __name__ == "__main__":
    unittest.main()

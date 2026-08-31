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


class MontoDeclarado(unittest.TestCase):
    def test_rangos_del_survey_vigente(self):
        self.assertEqual(L.monto_declarado("Actualmente tengo entre 500 y 1000 usd para invertir en mi formación como trader"), 500)
        self.assertEqual(L.monto_declarado("Actualmente tengo entre 2000 y 5000 usd para invertir en lograr la rentabilidad"), 2000)
        self.assertEqual(L.monto_declarado("Actualmente tengo más de 5000 usd para invertir en lograr la rentabilidad."), 5000)
        self.assertEqual(L.monto_declarado("Actualmente no cuento con dinero para invertir en mi información como Trader."), 0)
    def test_valores_de_la_pregunta_validada(self):
        self.assertEqual(L.monto_declarado("Tengo $1.500 USD para Invertir"), 1500)
        self.assertEqual(L.monto_declarado("Tengo $500 USD para Invertir"), 500)
        self.assertEqual(L.monto_declarado("Tengo más de $4.000 USD para Invertir"), 4000)
        self.assertEqual(L.monto_declarado('["Menos de $1500 USD"]'), 0)
    def test_sin_numero(self):
        self.assertIsNone(L.monto_declarado("un millón")); self.assertIsNone(L.monto_declarado(""))

    def test_banda_con_rangos(self):
        listo = "Estoy listo para tomar acción e invertir en alguien que me ayude"
        self.assertEqual(L.banda("Actualmente tengo entre 2000 y 5000 usd para invertir", listo), "A")
        self.assertEqual(L.banda("Actualmente tengo entre 1000 y 2000 para invertir", listo), "B")  # cota inferior, conservador
        self.assertEqual(L.banda("Actualmente tengo entre 500 y 1000 usd para invertir", listo), "B")


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
    "proyecto": "David Guerrero", "fecha": "2026-08-26", "vista": "dia", "ahora": "2026-08-26T09:00",
    "fuente": {"ghl": "ok", "detalle": None, "db": "ok"},
    "calendarios": [{"id": "CAL1", "nombre": "Calendario Premium Mastermind", "tipo": "funnel", "miembros": ["SET1", "SET2"]},
                    {"id": "CAL2", "nombre": "Aplicación a Premium Mastermind", "tipo": "closers", "miembros": ["CLO1"]}],
    "eventos": [
        {"id": "AP1", "appointmentStatus": "confirmed", "title": "Ana Pérez - Premium Mastermind",
         "startTime": "2026-08-26T09:20:00-05:00", "endTime": "2026-08-26T09:40:00-05:00",
         "contactId": "C1", "assignedUserId": "SET1", "calendarId": "CAL1", "createdBy": {"source": "booking_widget"}},
        {"id": "AP2", "appointmentStatus": "confirmed", "title": "Luis Gil - Premium Mastermind",
         "startTime": "2026-08-26T15:00:00-05:00", "endTime": "2026-08-26T15:20:00-05:00",
         "contactId": "C2", "assignedUserId": "SET1", "calendarId": "CAL1", "createdBy": {"source": "booking_widget"}},
        {"id": "AP3", "appointmentStatus": "cancelled", "title": "Eva Ruiz - Premium Mastermind",
         "startTime": "2026-08-26T08:00:00-05:00", "endTime": "2026-08-26T08:20:00-05:00",
         "contactId": "C3", "assignedUserId": "CLO1", "calendarId": "CAL2", "createdBy": {"source": "booking_widget"}},
        {"id": "AP_FUERA", "appointmentStatus": "confirmed", "title": "Fuera - PM",
         "startTime": "2026-08-27T09:00:00-05:00", "endTime": "2026-08-27T09:20:00-05:00",
         "contactId": "C9", "assignedUserId": "CLO1", "calendarId": "CAL2", "createdBy": {}},
        {"id": "AP4", "appointmentStatus": "confirmed", "title": "Ana Pérez - Premium Mastermind",
         "startTime": "2026-08-26T16:00:00-05:00", "endTime": "2026-08-26T16:20:00-05:00",
         "contactId": "C1", "assignedUserId": "CLO1", "calendarId": "CAL2", "createdBy": {"source": "calendar_page"}},
        {"id": "AP5", "appointmentStatus": "confirmed", "title": "Zoe Mal - Premium Mastermind",
         "startTime": "2026-08-26T17:00:00-05:00", "endTime": "2026-08-26T17:20:00-05:00",
         "contactId": "C5", "assignedUserId": "SET2", "calendarId": "CAL2", "createdBy": {"source": "calendar_page"}},
    ],
    "eventos_cruce": [
        {"id": "APX", "appointmentStatus": "confirmed", "title": "Luis Gil - Premium Mastermind",
         "startTime": "2026-08-28T10:00:00-05:00", "endTime": "2026-08-28T10:20:00-05:00",
         "contactId": "C2", "assignedUserId": "CLO1", "calendarId": "CAL2", "createdBy": {}},
        {"id": "APY", "appointmentStatus": "cancelled", "title": "Eva Ruiz - Premium Mastermind",
         "startTime": "2026-08-27T10:00:00-05:00", "endTime": "2026-08-27T10:20:00-05:00",
         "contactId": "C3", "assignedUserId": "CLO1", "calendarId": "CAL2", "createdBy": {}},
    ],
    "contactos": {
        "C1": {"id": "C1", "firstName": "Ana", "lastName": "Pérez", "email": "ana@x.co", "phone": "+57 300",
               "source": "Survey Mastermind", "tags": ["form mastermind"],
               "attributionSource": {"sessionSource": "Social media", "campaign": "Fly_test", "utmSource": "fb"},
               "customFields": [{"id": "F_PRES", "value": "$1.500"}, {"id": "F_DISP", "value": "Estoy listo para tomar acción e invertir"},
                                {"id": "F_OTRO", "value": "Colombia"}]},
        "C2": None,
        "C3": {"id": "C3", "firstName": "Eva", "lastName": "Ruiz", "customFields": []},
        "C5": None,
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
        self.assertEqual([c["appointment_id"] for c in self.out["citas"]], ["AP3", "AP1", "AP2", "AP4", "AP5"])
        self.assertEqual({c["appointment_id"]: c["calendario"] for c in self.out["citas"]},
                         {"AP3": "closers", "AP1": "funnel", "AP2": "funnel", "AP4": "closers", "AP5": "closers"})
        self.assertEqual(self.out["ventana"], {"vista": "dia", "fecha": "2026-08-26", "desde": "2026-08-26", "hasta": "2026-08-26", "ahora": "2026-08-26T09:00"})

    def test_lead_en_vivo_banda_y_survey(self):
        c = self.por_id["AP1"]
        self.assertEqual(c["lead"]["nombre"], "Ana Pérez"); self.assertEqual(c["lead"]["fuente"], "ghl")
        self.assertEqual(c["lead"]["campana"], "Fly_test"); self.assertEqual(c["lead"]["sesion"], "Social media")
        self.assertEqual(c["banda"], {"letra": "A", "presupuesto": "$1.500", "disposicion": "Estoy listo para tomar acción e invertir"})
        self.assertEqual([s["campo"] for s in c["survey"]], ["¿Tienes al menos $1.500 USD para invertir?", "¿En qué situación te encuentras actualmente?", "País"])
        self.assertEqual(c["asignado"]["nombre"], "Cristian Buelvas"); self.assertFalse(c["sin_closer"]); self.assertFalse(c["sin_asignar"])
        self.assertEqual(c["cita_closer"], {"fecha": "2026-08-26", "hora": "16:00", "closer": "Carlos González"})
        self.assertEqual(c["etapa_crm"], "LLAMADA CONFIRMADA"); self.assertFalse(c["etapa_no_confirmada"])
        self.assertEqual(c["historial"], {"llamadas_previas": 1, "ultima": "2026-07-01", "bant_previo": 55})
        self.assertIsNone(c["meeting"]); self.assertTrue(c["sin_meet"])
        self.assertFalse(c["pasada"]); self.assertEqual(c["estado"], "proxima"); self.assertIsNone(c["anunciada"])

    def test_lead_desde_espejo_y_cruce_fuera_de_ventana(self):
        c = self.por_id["AP2"]
        self.assertEqual(c["lead"]["fuente"], "espejo"); self.assertEqual(c["lead"]["nombre"], "Luis Gil")
        self.assertEqual(c["banda"]["letra"], "B")
        self.assertFalse(c["sin_closer"])  # funnel: asignado a setter es lo normal
        self.assertEqual(c["cita_closer"], {"fecha": "2026-08-28", "hora": "10:00", "closer": "Carlos González"})
        self.assertIsNone(c["etapa_crm"]); self.assertTrue(c["etapa_no_confirmada"])

    def test_closers_sin_closer_y_cancelada_no_cruza(self):
        c = self.por_id["AP5"]  # cita de closers asignada a un setter
        self.assertEqual(c["calendario"], "closers"); self.assertTrue(c["sin_closer"]); self.assertFalse(c["sin_asignar"])
        self.assertIsNone(c["cita_closer"])  # el cruce es solo del funnel
        # la cita cancelada APY no cuenta como «agendó con closer» para C3
        self.assertIsNone(self.por_id["AP3"]["cita_closer"])

    def test_pasada_cancelada_con_reporte(self):
        c = self.por_id["AP3"]
        self.assertTrue(c["pasada"]); self.assertEqual(c["estado"], "cancelada")
        self.assertEqual(c["meeting"]["meet_url"], "https://meet.google.com/aaa"); self.assertFalse(c["sin_meet"])
        self.assertEqual(c["reporte"]["bant"], {"budget": 60, "authority": 80, "need": 70, "timeline": 50, "total": 65})
        self.assertEqual(c["reporte"]["baja_confianza"], ["budget"]); self.assertEqual(c["reporte"]["arquetipo"], "Emocional")
        self.assertEqual(c["ocurrio"], {"transcript": True, "grabacion": True})
        self.assertIsNone(c["banda"])  # pasadas no llevan banda

    def test_kpis_y_alertas(self):
        kf, kc = self.out["kpis"]["funnel"], self.out["kpis"]["closers"]
        self.assertEqual((kf["citas"], kf["confirmadas"], kf["canceladas"]), (2, 2, 0))
        self.assertEqual((kf["banda_a"], kf["sin_asignar"], kf["sin_closer"], kf["agendo_closer"], kf["leads"]), (1, 0, 0, 2, 2))
        self.assertEqual((kc["citas"], kc["canceladas"], kc["sin_closer"], kc["pasadas"]), (3, 1, 1, 0))
        self.assertEqual(self.out["solo_en_sistema"][0]["lead"], "Javier Gutierrez")
        self.assertEqual(self.out["fuente"]["contactos_en_vivo"], 2); self.assertEqual(self.out["fuente"]["contactos_espejo"], 1)
        self.assertEqual(len(self.out["sin_instrumentar"]), 2)
        self.assertEqual(self.out["calendarios"][0]["miembros"], ["Cristian Buelvas", "Anthony Velásquez"])
        self.assertEqual(self.out["calendarios"][1]["tipo"], "closers")

    def test_prefiere_la_pregunta_validada_sobre_la_vigente(self):
        ctx = json.loads(json.dumps(CTX))
        ctx["db"]["catalogo"].append({"ghl_field_id": "F_VIG", "name": "…describe tu situación financiera actual:", "position": 0})
        ctx["contactos"]["C1"]["customFields"].append({"id": "F_VIG", "value": "Actualmente tengo entre 500 y 1000 usd"})
        c = {x["appointment_id"]: x for x in L.armar(ctx)["citas"]}["AP1"]
        self.assertEqual(c["banda"]["letra"], "A"); self.assertEqual(c["banda"]["presupuesto"], "$1.500")
        del ctx["contactos"]["C1"]["customFields"][0]  # sin la validada → manda la vigente
        c = {x["appointment_id"]: x for x in L.armar(ctx)["citas"]}["AP1"]
        self.assertEqual(c["banda"]["letra"], "B"); self.assertEqual(c["banda"]["presupuesto"], "Actualmente tengo entre 500 y 1000 usd")

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
        self.assertEqual(out["citas"], []); self.assertEqual(out["fuente"]["ghl"], "error")
        self.assertEqual(out["kpis"]["funnel"]["citas"], 0); self.assertEqual(out["kpis"]["closers"]["citas"], 0)


if __name__ == "__main__":
    unittest.main()

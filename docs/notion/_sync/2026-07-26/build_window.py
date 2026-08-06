#!/usr/bin/env python3
"""
Sync Notion -> tareas · ventana mayo-julio 2026 (corte acordado 2026-07-26).

Toma el pull en vivo de BD Avances + los source_external_id ya ingestados y
produce los lotes por proyecto que come `bash/ops/ingest_notion.sh`.

  python3 build_window.py <bd-live.json> <db-ids.txt> <outdir>

Criterio de la ventana: tarea ABIERTA (On Time / In Progress) en Notion, cuyo
id NO está en la DB, creada O editada desde 2026-05-01. Lo anterior es
sedimento (352 filas abiertas sin tocar desde 2024-2025) y se deja fuera a
propósito — ver README.md.
"""
import json, re, sys, os

live_path, ids_path, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
CORTE = '2026-05-01'

live = json.load(open(live_path))
db = {l.strip() for l in open(ids_path) if l.strip()}

ed = lambda r: (r.get('editado') or '')[:10]
cr = lambda r: (r.get('creado') or '')[:10]

ventana = [r for r in live
           if r.get('estado') in ('On Time', 'In Progress')
           and r['id'] not in db
           and (ed(r) >= CORTE or cr(r) >= CORTE)]

# --- clasificación a arquetipo (pase LLM; evidencia = título + contexto del lote) ---
# clave = fragmento único del título;  valor = (archetype_id, confianza)
CLS = {
    "Iniciar campaña de generación de audiencias":            ("A3.3",  0.70),
    "Contactar 1:1":                                          ("A6.7",  0.60),
    "Crear copy para envío de mensajes con encuesta":          ("A9.4",  0.80),
    "Crear encuesta y regalo de encuesta":                     ("A7.7",  0.65),
    "Descargar base de datos de compradores":                  ("A8.5",  0.55),
    "Hacer estudio de mercado":                                ("A6.7",  0.70),
    "Coordinar con Lorenzo sobre los ajustes pendientes":      ("A10.2", 0.65),
    "Generar investigación del avatar":                        ("A6.7",  0.90),
    "Enviar los contenidos (reels)":                           (None,    0.0),  # gap conocido
    "Obtener acceso al WhatsApp de Andrea":                    ("A9.7",  0.70),
    "Encuesta con los leads":                                  ("A6.7",  0.80),
    "Alinear la estrategia con Lucho":                         ("A12.2", 0.75),
    "Alinear la estrategia de contenido orgánico":             ("A4.4",  0.70),
    "Escribir el nuevo VSL":                                   ("A1.2",  0.85),
    "Revisar respuestas del formulario de registro":           ("A6.7",  0.70),
    "Capacitar a los setters":                                 ("A6.4",  0.90),
    "Definir y configurar tags en ManyChat":                   ("A6.2",  0.95),
    "Implementar ManyChat para la comunicación de setters":    ("A6.1",  0.90),
    "Investigar y solucionar urgentemente la inconsistencia":  ("A6.6",  0.90),
    "Adquirir o recuperar un número de WhatsApp":              ("A9.7",  0.75),
    "Crea video para el primer video del funnel":              ("A7.8",  0.60),
}


def clasificar(t):
    if re.match(r'\s*edici[oó]n\s+r\d', t or '', re.I):
        return ("A2.5", 0.90)          # editar audio/video de anuncios (lote de lanzamiento)
    for frag, val in CLS.items():
        if frag.lower() in (t or '').lower():
            return val
    return (None, 0.0)


def proyecto(r):
    """Relación de proyecto poblada = Mastermind; si no, el prefijo del título."""
    t = (r.get('tarea') or '').strip().upper()
    if r.get('proyecto_ids'):
        return 'David Guerrero'
    if t.startswith('AT'):
        return 'Andrea Torres'
    if t.startswith('DG'):
        return 'David Guerrero'
    return None


FILE = {'David Guerrero': 'lote-dg.json', 'Andrea Torres': 'lote-at.json'}
lotes, descartes = {}, []
for r in ventana:
    t = (r.get('tarea') or '').strip()
    if len(re.sub(r'[^0-9A-Za-zÁÉÍÓÚÑáéíóúñ]', '', t)) < 3:
        descartes.append((t, 'título vacío/basura')); continue
    p = proyecto(r)
    if not p:
        descartes.append((t, 'sin proyecto resoluble')); continue
    arq, conf = clasificar(t)
    lotes.setdefault(p, []).append({
        "id": r['id'], "url": r.get('url') or '', "tarea": t,
        "estado": r.get('estado'), "fecha": r.get('fecha'),
        "prioridad": r.get('prioridad'),
        "archetype_id": arq, "confidence": conf,
        "_asignado": r.get('asignado') or [],
    })

os.makedirs(outdir, exist_ok=True)
print(f"ventana ({CORTE}+, abiertas, no ingestadas): {len(ventana)}")
for p, rows in sorted(lotes.items()):
    json.dump(rows, open(os.path.join(outdir, FILE[p]), 'w'), ensure_ascii=False, indent=1)
    sin = sum(1 for r in rows if not r['archetype_id'])
    print(f"  {p:16} {len(rows):3} -> {FILE[p]}  (sin arquetipo: {sin})")
print("descartadas:", descartes or "ninguna")

# --- mapa nombre-en-Notion -> team_members (id-prefix; los ambiguos exigen prefijo) ---
MAPA = {
    "Marisol Ochoa": "ea2e5c2b",                # Project Manager
    "Tony Vital": "e6fea6f1",                   # -> Tony Vidal (typo en Notion)
    "Antonio mario Espitia españa": "4c5da006",  # alta 2026-07-26 (Editor, Ikigai)
    "Lorenzo Cadavid": "4a5fb68e",
    "luis david florez cardona": "ece00919",    # Director Comercial (no la fila Closer 81d4bc8e)
    "Sofi": "5b38842b",                         # -> Sofia
    "Roberto Maestre": "98086347",
    "Juan Camilo Correa W.": "aaac2f92",
    "David Cast": "62b13787",                   # -> David Castaño
    "Jhonatan Rengifo": "c632680c",
}
json.dump(MAPA, open(os.path.join(outdir, 'mapa-asignados.json'), 'w'), ensure_ascii=False, indent=1)
vistos = {a.strip() for rows in lotes.values() for r in rows for a in r['_asignado']}
print("sin mapear:", sorted(v for v in vistos if not MAPA.get(v)))

#!/usr/bin/env python3
"""Guardar un reporte de llamada regenerado en la db local `reportes_llamada`.

Valida ANTES de escribir. Esa es su razón de existir: un reporte que no parsea,
o al que le falta la mitad del esquema, entra igual de silencioso que uno bueno
y después contamina toda comparación. Aquí falla y no escribe.

El write real lo hace bash/localdb/db_exec.sh — este helper solo arma el INSERT
con el escapado correcto. No abre sqlite por su cuenta.
"""
import argparse, json, pathlib, subprocess, sys
from datetime import datetime

RAIZ = {"reportTitle", "generalInformation", "generalMetrics", "performanceInsights",
        "objectionsAndInsights", "leadProfile", "aiAgentConclusion"}
BANT = ("budget", "authority", "need", "timeline")
REPO = pathlib.Path(__file__).resolve().parents[3]


def sql_str(s):
    """Literal SQL de sqlite: comilla simple duplicada. Nada más se escapa."""
    return "'" + str(s).replace("'", "''") + "'"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--meeting", required=True, help="uuid COMPLETO del meeting en Postgres")
    ap.add_argument("--corrida", required=True, help="etiqueta única de la corrida")
    ap.add_argument("--modelo", required=True, help="qué modelo escribió el reporte")
    # Una variante = un archivo de prompt. Nunca una edición al vuelo: un prompt
    # tocado a mano no se puede volver a correr ni atribuir, y las corridas ya
    # guardadas bajo ese nombre dejan de ser interpretables.
    #   produccion → prompt-produccion.md    mejorado  → prompt-mejorado.md
    #   mejorado2  → prompt-mejorado-2.md (eje propio para `need`)
    ap.add_argument("--variante", required=True,
                    choices=["produccion", "mejorado", "mejorado2"])
    ap.add_argument("--json", required=True, help="ruta al JSON generado")
    ap.add_argument("--prompt-sha", default="31e2210", help="commit del prompt en google-meet-express")
    ap.add_argument("--nota", default="")
    ap.add_argument("--db", default="reportes_llamada")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    crudo = pathlib.Path(a.json).read_text().strip()
    # Producción despoja cercas de markdown antes de guardar; hacemos lo mismo,
    # pero avisando: si el modelo las puso, no siguió la instrucción del prompt.
    if crudo.startswith("```"):
        print("AVISO: el JSON venía con cercas de markdown; el prompt las prohíbe.", file=sys.stderr)
        crudo = crudo.split("```", 2)[1]
        if crudo.startswith("json"):
            crudo = crudo[4:]
        crudo = crudo.strip()

    try:
        rep = json.loads(crudo)
    except json.JSONDecodeError as e:
        sys.exit(f"ERROR: el JSON no parsea ({e}). No se escribió nada.")

    faltan = RAIZ - set(rep)
    if faltan:
        sys.exit(f"ERROR: faltan claves de raíz del esquema: {sorted(faltan)}. No se escribió nada.")

    bant = (rep.get("leadProfile") or {}).get("bantAnalysis") or {}
    sin = [k for k in BANT if not isinstance((bant.get(k) or {}).get("score"), (int, float))]
    if sin:
        sys.exit(f"ERROR: ítems BANT sin score numérico: {sin}. No se escribió nada.")

    # Se re-serializa compacto: el JSON entra a sqlite normalizado, así dos
    # corridas no difieren por espacios en blanco.
    payload = json.dumps(rep, ensure_ascii=False, separators=(",", ":"))
    sql = (
        "INSERT OR REPLACE INTO reportes "
        "(meeting_id, corrida, generado_por, prompt_variante, prompt_sha, generado_at, report, nota) VALUES ("
        + ", ".join([
            sql_str(a.meeting), sql_str(a.corrida), sql_str(a.modelo), sql_str(a.variante),
            sql_str(a.prompt_sha), sql_str(datetime.now().isoformat(timespec="seconds")),
            sql_str(payload), sql_str(a.nota)]) + ");"
    )

    cmd = [str(REPO / "bash/localdb/db_exec.sh"), a.db, "-"]
    if a.dry_run:
        cmd.append("--dry-run")
    r = subprocess.run(cmd, input=sql, text=True, capture_output=True)
    sys.stdout.write(r.stdout)
    sys.stderr.write(r.stderr)
    if r.returncode:
        sys.exit(r.returncode)

    p = {k: bant[k]["score"] for k in BANT}
    arq = ((rep["leadProfile"].get("intelligentSegmentation") or {}).get("archetype") or {}).get("name")
    print(f"guardado: {a.corrida} | {a.variante} | {a.modelo}")
    print(f"  BANT  budget={p['budget']} authority={p['authority']} need={p['need']} timeline={p['timeline']}"
          f"  prom={sum(p.values())/4:.1f}")
    print(f"  arquetipo: {arq!r}")


if __name__ == "__main__":
    main()

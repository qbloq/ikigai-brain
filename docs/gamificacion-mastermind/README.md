# Gamificación de Premium Mastermind — índice de trazabilidad

Proceso: el sistema de rangos, puntos, strikes, beneficios y concursos para los
estudiantes de Premium Mastermind (David Guerrero) — S12 retención, **sin
arquetipo en el catálogo** (cola declarada el 4-ago y el 21-ago). No confundir
con el *funnel gamificado* (quiz lead-magnet de Andrea, S7.4, apagado el 4-jun).

Línea: 15-jul `ed6b60c2` (rol de Tati, strikes pospuestos) → 29-jul `dc27f156`
(gamificación como gancho de oferta) + `40ef10e0` (propuesta de Tati, aportes de
Cisco y Mari) → 19-ago `b3f06835` (impago cohorte feb–mar) → 20-ago `2ea7176d`
(plataforma única Skool + app, desbloqueo por pago, salida de morosos >1 año).

Cada entregable del Cerebro (2026-08-24) vive como **IO de una tarea existente**
con su artefacto físico enlazado en el binding del IO (`reference`):

| Tarea | IO | Artefacto | Dónde |
|---|---|---|---|
| `22251454` Estructurar sistema de gamificación (Tati · Cisco · Mari) | E1 Documento de Tati (29-jul) | drive_file — **pendiente de subir** | carpeta `1. David Guerrero/Hermetico/22251454 · Sistema de gamificación Mastermind` |
| | E2 Acta + transcript 29-jul | storage_file | meeting `40ef10e0` |
| | E3 Decisiones 20-ago | meeting_report | meeting `2ea7176d` (tarea `386e9036`) |
| | E4 Reglas y strikes de Cisco | documentation — **pendiente** | WhatsApp del grupo |
| | **S1 Propuesta unificada** (3 criterios; el último = aprobación de Lorenzo/Juanca, atestada) | google_doc | [Doc](https://docs.google.com/document/d/1EEE1Fs_NQGtG1Xpfz6gOubN-ASBfjYduiSRE4o498Pc/edit) · fuente [propuesta-unificada.md](propuesta-unificada.md) |
| | **S2 Tablero de rangos y puntos (prototipo)** (3 criterios) | web_url → db local `gamificacion` | viz `bases-locales?db=gamificacion&table=tablero` |
| `cb95a33b` Reunión con Cisco (Lorenzo) | E1 Objetivo/temas | google_doc | [Doc](https://docs.google.com/document/d/1JlMoyvprOBXaTgv0uZqOVBXHTN97lQeinhL_Ue0lkZY/edit) · fuente [reunion-cisco-objetivo.md](reunion-cisco-objetivo.md) |
| | S1 Reunión realizada | computed — **no realizada** (vencía 7-ago) | carpeta `cb95a33b · Reunión Cisco — diseño de la gamificación` |
| `fa9085db` Concursos Bridge Market (Lorenzo) | E1 Propuesta unificada | google_doc | el Doc de `22251454` S1 |
| | S1 Diseño de concursos | google_doc | [Doc](https://docs.google.com/document/d/1u5fQly1REJQ3H8-UqIW9DVQCdX2UbQBVdqBEVJYBjoo/edit) · fuente [reglamento-concurso-bridge-market.md](reglamento-concurso-bridge-market.md) |
| `58f86ac8` Ruta educativa por niveles (Mari · Cisco) | E1 Propuesta unificada · E2 Acta 29-jul | google_doc · storage_file | — |
| | S1 Ruta educativa | google_doc (esqueleto, Cisco llena) | [Doc](https://docs.google.com/document/d/1onksoiXSaisWvldhY6MDOtWfOW1UcsaMBJKj0do2K9Y/edit) · fuente [ruta-educativa-esqueleto.md](ruta-educativa-esqueleto.md) |
| `871e998f` Renovación de quienes completaron pagos (Cisco) | E1 Lista con el plan pagado al 100 % | sql_query (viva, 62 hoy) | `run_io_query.sh 85ffab92` |

## El prototipo del tablero (db local `gamificacion`)

- `estudiantes` (207): planes activos de Premium Mastermind / Lite, sembrados
  desde `payment_plans` + `installments` (`estado_pago` = ciclo_completo 62 ·
  al_dia 32 · en_mora 113). Re-sembrar = volver a exportar e importar con
  `--replace`.
- `rangos` (bronce → diamante + nivel superior) con requisito, `puntos_min`,
  `retiro_min_usd`, beneficios (todos «por definir»).
- `tipos_evento` con puntos: solo `strike = −20` está definido; el resto NULL
  hasta la reunión con Cisco.
- `eventos`: fecha · estudiante · tipo · monto · puntos · nota · fuente ·
  registrado_por. Se llenan por conversación con el Cerebro
  (`bash/localdb/db_exec.sh gamificacion`).
- Vistas `tablero` (rango calculado: diamante = ≥300 pts y retiro ≥2.000; oro =
  retiro + análisis; plata = cuenta fondeada) y `resumen` (rango × estado de pago).
- Destino declarado: la ficha por estudiante en la app de Ikigai (20-ago).

## Pendientes que no puede cerrar el Cerebro

1. Subir el Word de Tati a la carpeta de `22251454` (E1).
2. Recoger las reglas/strikes de Cisco (E4).
3. Realizar la reunión con Cisco (`cb95a33b`) y llenar los «por definir».
4. Presentación a Lorenzo/Juanca con presupuesto (criterio S1.3 de `22251454`).
5. Catálogo: arquetipos para «gamificación/retención» (S12) y «ruta educativa» (S11).
6. Re-fechar las cuatro tareas (todas vencidas salvo `fa9085db`, 26-ago).

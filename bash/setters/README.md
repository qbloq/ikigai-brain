# bash/setters — la agenda del setter

El primer dominio del rol **Setter** (Antonio = Cristian Buelvas, Anthony
Velásquez): quienes califican, confirman y sostienen la agenda de llamadas del
equipo de closers, y desde el 2026-08-25 los únicos (junto con la IA) que
tocan el CRM. Spec: `docs/superpowers/specs/2026-08-26-agenda-setter-design.md`.

## Scripts

| Script | Para qué |
|--------|----------|
| `agenda.sh [--project N] [--fecha D] [--vista dia\|semana] [--json]` | La agenda del día o de la semana (lunes–domingo) como UN objeto: citas del calendario oficial de GHL, cada una con lead (contacto **en vivo**), closer asignado, link de Meet, etapa del tablero, **banda pre-llamada A/B/C** (entrantes) y **estado por capas** ocurrió · analizada (BANT) · venta (pasadas). Alertas: `sin_closer`, `sin_meet`, `solo_en_sistema` (drift). Read-only. Fuente viz `agenda_setter`. |
| `test.sh` | Tests puros de `lib/agenda_lib.py` (bandas, montos, ventana, estado, ensamblado). |

## Reglas

- **GHL manda.** La agenda es la lista de citas de GHL. Postgres enriquece;
  nunca completa. Si GHL falla: `fuente.ghl = "error"` y `citas = []`.
- **Sin Postgres no hay agenda**: las credenciales de GHL viven en la base
  (`project_crm_configs`), así que la base caída es exit ≠ 0 con mensaje, no
  un objeto a medias. La base viva pero la consulta de enriquecimiento rota →
  `fuente.db = "error"` y las citas salen peladas (lead + banda + closer sin
  resolver a nombre).
- Contacto en vivo con fallback al espejo, declarado por fila (`lead.fuente`
  = `ghl` · `espejo` · `titulo`).
- **Dos preguntas de presupuesto conviven** en el CRM: la validada contra
  plata (`docs/lead-score.md`, «¿Tienes al menos $1.500 USD…?») y la del
  survey vigente («…describe tu situación financiera actual», en rangos:
  «entre 500 y 1000», «más de 5000»). La banda lee la validada si existe y si
  no la vigente, tomando la **cota inferior** del rango (conservador: «entre
  1000 y 2000» → B). El corte ≥1500 sobre la pregunta nueva no está validado
  contra plata todavía — es la misma regla aplicada al instrumento nuevo.
- `sin_closer` = la cita está asignada a un miembro del calendario (los
  setters, leídos en vivo de `GET /calendars/{id}`) o a nadie.
- `anunciada` es `null` hasta que exista el detector de anuncios del grupo
  ONLY CLOSERS (rutina de registro, pieza 1).
- Solo GET a GHL, `psql_ro` en Postgres, cerca por rol de `bash/ghl/`.

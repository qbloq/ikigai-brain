# bash/setters — la agenda del setter

El primer dominio del rol **Setter** (Antonio = Cristian Buelvas, Anthony
Velásquez): quienes califican, confirman y sostienen la agenda de llamadas del
equipo de closers, y desde el 2026-08-25 los únicos (junto con la IA) que
tocan el CRM. Spec: `docs/superpowers/specs/2026-08-26-agenda-setter-design.md`.

## Scripts

| Script | Para qué |
|--------|----------|
| `agenda.sh [--project N] [--fecha D] [--vista dia\|semana] [--calendar-closers ID] [--json]` | La agenda del día o de la semana (lunes–domingo) como UN objeto, con los **dos calendarios oficiales**: el del **funnel** (el widget agenda ahí; la toma un setter) y el de **closers** («Aplicación…», la agenda que cuadra el setter — descubierto en vivo o fijado por flag). Cada cita con `calendario`, lead (contacto **en vivo**), asignado, link de Meet, **banda A/B/C** (entrantes), **estado por capas** (pasadas) y el cruce `cita_closer` (funnel→«ya agendó con closer», mirando 7 días adelante). Alertas: `sin_closer` (solo closers), `sin_asignar` (funnel), `sin_meet`, `solo_en_sistema` (drift). Read-only. Fuente viz `agenda_setter`. |
| `disponibilidad.sh [--project N] [--fecha D] [--calendar ID] [--json]` | La **matriz semanal de disponibilidad de closers** (closers × días, lunes–domingo) como UN objeto. La verdad es GHL: los `libres` de cada celda son los huecos que su endpoint free-slots calcula por closer sobre el calendario de **venta** (la disponibilidad que cada uno configuró menos sus citas) — no se inventa horario laboral. Estados de celda: `normal` · `lleno` (0 libres con citas) · `sin_horario` (0 y 0 en día futuro: el closer no configuró su disponibilidad) · `pasado` (GHL no da huecos hacia atrás; solo las citas que hubo). Citas asignadas a un no-miembro → `sin_closer`, declaradas. Read-only. Fuente viz `disponibilidad_closers`. |
| `test.sh` | Tests puros de `lib/agenda_lib.py` + `lib/disponibilidad_lib.py` (bandas, montos, ventana, estado, ensamblado, matriz). |

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
- **Semántica por carril**: en el calendario del funnel el asignado ES el
  setter que toma la llamada (round-robin entre los miembros) — la alerta ahí
  es `sin_asignar`. `sin_closer` existe solo en el carril de closers: la cita
  quedó en manos de un setter (miembro del funnel) o de nadie cuando debía
  tener un closer dueño. Los miembros de cada calendario se leen en vivo
  (`GET /calendars/{id}`).
- `anunciada` es `null` hasta que exista el detector de anuncios del grupo
  ONLY CLOSERS (rutina de registro, pieza 1).
- Solo GET a GHL, `psql_ro` en Postgres, cerca por rol de `bash/ghl/`.

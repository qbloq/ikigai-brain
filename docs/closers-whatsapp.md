# Closers por WhatsApp — el sistema de mensajes estandarizados

**Qué es (2026-08-12):** los 5 escenarios de acompañamiento diario a los
closers por WhatsApp, corriendo sobre el número WABA del Cerebro (+57 312
8932486). La mitad **programada** (escenarios 1, 2 y 5 + la apertura del 3) son
scripts deterministas en [bash/closers/](../bash/closers/) disparados por cron;
la mitad **conversacional** (el 3 completo y el 4) la lleva Iki con el
«Protocolo post-llamada» de su AGENTS.md. Estreno: 2026-08-13 con todos los
closers.

## Los 5 escenarios

| # | Cuándo | Qué llega | Quién lo corre |
|---|--------|-----------|----------------|
| 1 | 07:00 COT (cron) | Saludo + agenda del día (hora · lead por llamada) | `escenario_manana.sh` — plantilla Meta (fuera de ventana) |
| 2 | 45 min antes de cada llamada (tick cron 5 min) | Lead + link de Google Meet | `escenario_llamadas.sh` — sesión, fallback plantilla |
| 3 | Al terminar cada llamada (mismo tick) | «¿Cómo terminó? Venta / Seguimiento / No Califica / No Show» → la respuesta la conversa **Iki**: clasifica, guarda `RESULTADO:`, y si no fue venta lo deja en cola para Marketico | apertura: script · conversación: Iki |
| 4 | Tras una Venta (dentro del 3) | Iki pide el acuerdo de pago EN TEXTO, guarda `ACUERDO:` y responde confirmando el Plan de Pagos reformulado | Iki |
| 5 | 20:00 COT (cron) | Total de ventas del día + cuotas DEL CLOSER que vencen mañana con recaudo posible | `escenario_cierre.sh` — sesión, fallback plantilla |

## Las piezas

- **`agenda.sh`** (read-only): las llamadas agendadas de un día resueltas por
  closer — misma traza CRM de `bash/calls/` (booking contact → crm_contacts →
  crm_opportunities → users → persons). Llamadas sin traza salen con closer
  vacío y los escenarios las reportan a stderr (la cola S8.2 también existe a
  futuro).
- **`enviar.sh`** [WRITE→WhatsApp]: el enviador único. Sesión (texto libre,
  requiere ventana 24h) o plantilla Meta; resuelve nombres contra el
  `directorio` de `mesa_despacho.db`; **idempotente** por `(escenario, ref)` en
  la sqlite local `closers_ops.db` (tabla `envios`) — re-correr un escenario
  jamás duplica. Si una sesión rebota por ventana cerrada (error 131047) cae
  solo a `--fallback-plantilla` con el cuerpo colapsado a una línea (las
  variables de plantilla no aceptan saltos: regla Meta).
- **`closers_ops.db`**: `envios` (el log/candado) y `resultados` (la cola
  local de resultados de llamada rumbo a Marketico — `registrado_api=0` es lo
  pendiente de subir).
- **La ventana de 24h como diseño**: el saludo de las 07:00 va por plantilla;
  la respuesta del closer («OK») abre la sesión que los demás escenarios del
  día usan gratis. Por eso el saludo pide responder OK.
- **Resultados del día**: el protocolo de Iki guarda en su memoria
  (`brain.db`) filas `RESULTado: <fecha> | <closer> | <lead> | <resultado> |
  <detalle>` (formato exacto en su AGENTS.md); `escenario_cierre.sh` las lee
  **solo-lectura** y las une con la cola `resultados`. Nunca se escribe en las
  DBs del daemon.

## Plantillas Meta (WABA 690499003502578)

Propias (UTILITY, es_CO, creadas 2026-08-12, PENDING): `agenda_dia`
(2045660289396167) · `recordatorio_llamada` (1629321558813163) ·
`resultado_llamada` (1770044007337937) · `cierre_dia` (1036508266037698).
Regla aprendida: **las variables no pueden abrir ni cerrar el cuerpo**.

Mientras aprueban, el puente es **`weekly_report`** (APROBADA, heredada de la
flota coach): «Listo {{1}}! Aquí está tu reporte de esta semana. {{2}}» — su
`{{2}}` libre carga cualquier cuerpo colapsado a una línea. Cuando `agenda_dia`
apruebe: `escenario_manana.sh --plantilla agenda_dia` (y actualizar el default).

## Cron (hora local del server = COT)

```
# 0 7 * * *    escenario_manana.sh     # DESACTIVADO 2026-08-13 — ver nota
*/5 4-21 * * * escenario_llamadas.sh   # recordatorios 45min + post-llamada (hay llamadas 04-05h: leads en España)
0 20 * * *     escenario_cierre.sh     # cierre del día
```

Log: `data/log/closers-cron.log`.

**El saludo matutino es de Iki mientras Meta no apruebe** (decisión
2026-08-13): las plantillas propias siguen PENDING, así que el día arranca al
revés — el closer escribe «Hola», Iki (regla «Saludo matutino» de su
AGENTS.md) consulta `closer_agenda` por la puerta `/api` y responde con la
agenda completa (hora — lead — link de Meet) + qué esperar del día. Ese primer
mensaje del closer abre la ventana de 24h y el resto de escenarios (tick,
cierre) viajan como sesión — cero dependencia de plantillas. Constancia
`SALUDO: <fecha> | <closer>` en su memoria evita el saludo doble. Cuando
`agenda_dia` apruebe: reactivar la línea del cron con
`--plantilla agenda_dia`.

**Aprendizaje del estreno**: un mensaje de sesión fuera de ventana es
ACEPTADO por Meta (devuelve wamid) y falla después por webhook — el fallback
por error inmediato (131047) no lo cubre. Los recordatorios de las 06:20 del
2026-08-13 salieron «enviados» sin ventana abierta y probablemente no
llegaron. Mientras el saludo dependa del «Hola» del closer, los recordatorios
previos a ese Hola corren el mismo riesgo — se mitigan solos apenas el closer
escribe.

## Pendientes conocidos

- ~~Router~~ **Resuelto 2026-08-13**: los closers activos están en el
  mappings del agenticlaw-router (backup `mappings.json.bak-20260813`); el
  router lee el archivo POR REQUEST (`readMappings()` en cada handler), así
  que no necesitó restart. El camino de vuelta closer→Iki está completo.
- **Roster auditado contra el grupo de WhatsApp (2026-08-13)**: 6 closers
  activos — Lucho (DC), Ayrton, Mateo, Carlos, **Cristian Buelvas** y
  **Anthony Velásquez** (los dos últimos entraron en esta auditoría). Regla:
  **cuenta el número que usan en el grupo** — Anthony usa +573014076387 (no
  su personal +573052795025 de la DB), resuelto con el mecanismo `OVERRIDES`
  de `sync_directorio.sh` (par del de BAJAS: la DB no puede expresar ni bajas
  ni números de trabajo distintos). Mateo figura como *Setter* en la DB y
  está DUPLICADO en `team_members` (higiene pendiente); Cristian quedó sin
  cotejar contra el grupo (su LID oculta el número) — se valida solo cuando
  escriba.
- ~~Mateo Restrepo sin número~~ **Resuelto 2026-08-12**: Santiago lo cargó en
  la DB (+573117347664); directorio re-sincronizado, allowlist y roster al día.
- **Daniel Cardona DE BAJA (2026-08-13)**: fuera de allowlist, roster y
  directorio (la DB no tiene flag de activo → la lista de bajas vive en
  `sync_directorio.sh`). ⚠️ Sigue siendo dueño de **27 cuotas pendientes por
  \$23.499** en `payment_plans` — el cierre del día lo intentará y quedará
  `fallido` visible cada vez que le venza una: eso es el recordatorio de que
  su cartera necesita **reasignación** (decisión de negocio pendiente).
- **Marketico API**: el endpoint para registrar el resultado de una llamada
  existe según Santiago pero el contrato no está en `apis/mkt/` — la cola
  `resultados.registrado_api=0` está lista para cablearse en cuanto llegue.
- **Notas de voz**: el canal WhatsApp de zeroclaw descarta audio (candidato
  en el registro de no-fork) — el acuerdo de pago se pide en texto.

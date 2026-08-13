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
0 7 * * *      escenario_manana.sh     # saludo + agenda
*/5 4-21 * * * escenario_llamadas.sh   # recordatorios 45min + post-llamada (hay llamadas 04-05h: leads en España)
0 20 * * *     escenario_cierre.sh     # cierre del día
```

Log: `data/log/closers-cron.log`.

## Pendientes conocidos

- **Router**: los números de los closers deben estar en el mappings del
  agenticlaw-router (api.parallelo.ai, `/apps/agenticlaw/router/mappings.json`)
  para que sus RESPUESTAS lleguen a Iki — sin eso los escenarios salen pero el
  camino de vuelta cae al destino muerto. (El write remoto lo bloqueó el
  clasificador de permisos; comando listo en la conversación del 2026-08-12.)
- **Mateo Restrepo sin número** (ni en users ni en team_members): hoy queda
  fuera de los envíos — sus fallas salen como `fallido` en `envios`, visibles.
- **Marketico API**: el endpoint para registrar el resultado de una llamada
  existe según Santiago pero el contrato no está en `apis/mkt/` — la cola
  `resultados.registrado_api=0` está lista para cablearse en cuanto llegue.
- **Notas de voz**: el canal WhatsApp de zeroclaw descarta audio (candidato
  en el registro de no-fork) — el acuerdo de pago se pide en texto.

# Definición de etapas y etiquetas del embudo orgánico (Instagram DM → CRM)

**Tarea:** 3f8f9914 — David Guerrero · **Responsable de implementar:** Santiago Ruiz · **Elaborado:** 2026-08-22 por el Cerebro · **Estado:** propuesta para aprobación del equipo de setters.

## 1. Para qué

Hoy el embudo orgánico se ve por los extremos —cuántos leads entran sin pauta y cuántos compran— pero **no se ve el medio**: qué pasó en la conversación por DM. Medido julio–agosto: de cada 100 leads orgánicos, solo entre 15 y 35 llevan alguna etiqueta de calificación en el CRM, y solo 6 de cada 100 llegan con su usuario de Instagram. Sin etiqueta no se sabe si a un lead no lo trabajaron o lo trabajaron sin marcarlo; sin usuario de Instagram no se puede cruzar la conversación con la venta.

Este documento define **las etapas**, **una etiqueta por etapa** con el criterio de cuándo aplicarla, **cómo se mide** y **cómo se prueba** que el sistema opera.

## 2. Las etapas del recorrido orgánico

| # | Etapa | Qué significa | Dónde ocurre |
|---|---|---|---|
| 1 | **Entró** | Nuevo seguidor o persona que reaccionó a contenido (story, reel, comentario) y quedó como suscriptor | ManyChat (automático) |
| 2 | **Consumió contenido** | Vio la serie de YouTube, un lead magnet, el quiz, la clase | ManyChat (automático — etiquetas existentes) |
| 3 | **Conversación con setter** | Un setter le escribió o respondió por DM | ManyChat (manual, setter) |
| 4 | **Calificado / No calificado** | El setter decidió si califica para una llamada | ManyChat (manual, setter) → CRM |
| 5 | **Agendó** | Se agendó llamada con closer | Calendario / CRM |
| 6 | **Conectó / No conectó** | Asistió o no a la llamada | CRM (closer) |
| 7 | **Venta** | Firmó plan de pago | CRM / caja |

Las etapas 1–2 ya están instrumentadas en ManyChat (22 etiquetas de contenido) y viajan al CRM (`modulo3yt`, `leadmagnet1`, `quiz`…). Las etapas 5–7 ya existen en el CRM con etiquetas que los closers aplican. **El hueco son las etapas 3 y 4** — la conversación del setter — y ese es el objeto de este sistema.

## 3. La lista cerrada de etiquetas

Regla de oro: **la etiqueta se llama igual en ManyChat y en el CRM**. El puente ManyChat → GHL ya escribe etiquetas en el contacto; con el mismo nombre no hace falta traducir nada y el Cerebro cuenta directo.

### 3.1 Etiquetas que se crean en ManyChat (nuevas — el setter las aplica a mano)

| Etiqueta | Cuándo aplicarla | Quién |
|---|---|---|
| `contactado dm` | El setter le escribió al lead por DM (primer mensaje humano, no automático). Se aplica al enviar, aunque no responda. | Setter |
| `respondio dm` | El lead contestó al setter al menos una vez. | Setter |
| `calificado cc` | El setter determinó que cumple el perfil (capital, disposición, tiempo) y se le ofrece llamada. **Misma etiqueta que ya usa el CRM.** | Setter |
| `no calificado` | No cumple el perfil por ahora (capital insuficiente, no es su momento). Puede volver a nutrición. **Misma que el CRM.** | Setter |
| `descalificado cc` | No es cliente potencial (curioso, spam, competencia, menor de edad). No se vuelve a trabajar. **Misma que el CRM.** | Setter |
| `agendo dm` | El lead agendó la llamada desde la conversación de DM (el link de calendario salió del setter). | Setter |

### 3.2 Etiquetas que ya existen y se conservan

- **ManyChat (contenido, automáticas):** `nuevo seguidor`, `nuevo seguidor completa quiz`, `nuevo seguidor pide asesoria trading`, `lead ve curso de youtube modulo 1…7`, `lead ve curso completo de youtube`, `Lead magnet …`, `lead accede al grupo del lanzamiento`, `ingresa al grupo VIP de telegram`, etc. No se tocan.
- **CRM (closers):** `llamada agendada pm`, `agenda premium academy`, `llamada confirmada`, `llamada por confirmar`, `no se conectó`, `no contesta`, `venta`. No se tocan.

### 3.3 Lo que NO se hace

- No se crean etiquetas por closer, por producto ni por objeción: eso vive en otros campos.
- No se reemplazan las etiquetas de contenido existentes por «versiones limpias»: romperían el histórico.
- Una etiqueta de etapa **no se quita** cuando el lead avanza: el recorrido se lee por acumulación (quien tiene `venta` tiene también `calificado cc`).

## 4. La llave: el usuario de Instagram

Para cruzar la conversación de DM con la venta hace falta que el lead llegue **identificado** al CRM. Hoy el campo existe («¿Cuál es tu usuario de Instagram?») pero lo llena el survey, no el agendamiento, y solo lo trae el 6 % de los leads orgánicos.

Dos cambios, uno por cada lado del puente:

1. **En ManyChat:** el flujo que crea o actualiza el contacto en GHL escribe también el `ig_username` y el `subscriber_id` de ManyChat en el contacto (campos personalizados). Con eso el cruce es exacto, sin adivinar por nombre.
2. **En el agendamiento:** el formulario del calendario pide el usuario de Instagram (campo obligatorio para leads orgánicos) y lo guarda en el mismo campo del CRM.

Meta: que el usuario de Instagram pase del 6 % al ≥ 80 % de los leads orgánicos nuevos. Se mide semana a semana en el reporte (columna «con IG»).

## 5. Cómo se mide

- **Fuente de verdad: el CRM**, no ManyChat. El API de ManyChat no lista suscriptores ni cuenta por etiqueta; lo que sí hace el sistema es llevar la etiqueta al contacto de GHL, y ahí el Cerebro la cuenta.
- **Reporte semanal por etapa** (en el Cerebro, reproducible para cualquier período): leads orgánicos que entraron cada semana y cuántos llevan `contactado dm` · `respondio dm` · calificado / no calificado · agendó · no conectó · venta, más la **cobertura** (% con alguna etiqueta de calificación) y el % con usuario de Instagram.
- **La cobertura manda sobre los conteos**: una semana con 20 % de cobertura no dice que el canal convierte mal, dice que no se etiquetó. Por eso va al lado de cada fila.

Línea base (julio–agosto 2026, leads orgánicos por semana de entrada): cobertura de calificación entre **15 % y 35 %**; usuario de Instagram entre **0 % y 13 %**; `contactado dm` / `respondio dm`: **0 %** (no existen todavía).

## 6. La semana de prueba

1. Santiago Ruiz crea las seis etiquetas de §3.1 en ManyChat (cuenta operativa) y confirma que el puente las escribe en el contacto del CRM (prueba con un lead real: etiqueta en ManyChat → aparece en GHL).
2. Durante una semana, los setters aplican `contactado dm` / `respondio dm` / calificación / `agendo dm` a **toda** conversación nueva.
3. Al cierre de la semana, el Cerebro saca el reporte y se revisa una muestra de conversaciones nuevas: **≥ 90 % con etapa asignada** es el criterio de aceptación.
4. Los setters confirman que el etiquetado cabe en su operación diaria (atestación). Si no cabe, se ajusta la lista — se quitan etiquetas, no se agregan.

## 7. Responsables

| Qué | Quién |
|---|---|
| Crear etiquetas en ManyChat y ajustar el flujo (usuario de IG + subscriber_id al CRM) | Santiago Ruiz |
| Campo de Instagram en el formulario de agendamiento | Santiago Ruiz con quien administre el calendario |
| Aplicar etiquetas en cada conversación | Setters |
| Reporte semanal, cobertura y línea base | Cerebro (automático) |
| Aprobar la lista y el criterio | Equipo de setters + Lorenzo |

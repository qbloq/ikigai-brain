# Lead score — uso interno

**Entregable de la tarea `767605d8`** · arquetipo A6.8 · corte 2026-08-05.

La tarea pide *«definir el uso interno del lead score (0 a 100) para priorizar
leads sin entregarlo crudo a los closers»*. Este documento responde qué es el
score, contra qué está validado, a quién se le muestra y a quién no.

---

## 1. El hallazgo que reordena la pregunta

**El score que teníamos no puede priorizar leads.** Existe solo *después* de la
llamada.

El BANT que el analizador escribe en `leadProfile.bantAnalysis` se calcula a
partir del **transcript**. Es un score post-mortem: excelente para decidir a
quién perseguir en el seguimiento, inútil para decidir a quién llamar o quién
lo llama. Y `7fd54080` —«asignar los leads con calificación de 8 o más al closer
con mejor tasa de cierre»— necesita justamente lo contrario: un número que
exista **antes** de asignar.

Pero ese número también existe, y nadie lo estaba usando: **la encuesta de
calificación que el lead responde al agendar**, guardada en los
`custom_fields` de GHL. 1.621 contactos la tienen respondida.

Así que no hay un score. **Hay dos, y sirven para cosas distintas.**

| | Score PRE-llamada | Score POST-llamada |
|---|---|---|
| fuente | encuesta de agendamiento (GHL) | BANT del transcript |
| existe desde | que el lead agenda | que la llamada se analiza |
| cobertura | 1.621 contactos | 164 llamadas |
| sirve para | **asignar y confirmar** | **priorizar el seguimiento** |

---

## 2. Score POST-llamada (BANT) — validado

Promedio de los cuatro scores BANT (`need`, `budget`, `timeline`, `authority`),
cada uno 0-100 tal como los escribe el analizador. Sin re-escalar.

| tramo | llamadas | convirtió |
|---|---|---|
| **81-100** | 95 | **38.9 %** |
| 61-80 | 62 | 3.2 % |
| 41-60 | 7 | 0 % |

Doce veces la conversión entre el tramo alto y el siguiente. **Los tramos
discriminan**, que es lo que el criterio de aceptación exige.

El corte útil está en **80**, no en la mitad: entre 61 y 80 la conversión ya es
prácticamente cero. No es una escala lineal de calidad, es un umbral.

Reproducible: `bash/calls/lead_profile.sh --by tramo`

## 3. Score PRE-llamada (encuesta) — discrimina, falta ajustarlo

Dos preguntas de la encuesta predicen por sí solas. Medido sobre las
oportunidades del pipeline espejado:

**Presupuesto declarado** — *«¿Tienes al menos $1.500 USD para invertir…?»*

| respuesta | leads | cierre |
|---|---|---|
| $2.000 | 15 | 26.7 % |
| $1.500 | 132 | 16.7 % |
| más de $4.000 | 23 | 13.0 % |
| $500 | 405 | 12.3 % |

**Disposición declarada** — *«¿En qué situación te encuentras actualmente…?»*

| respuesta | leads | cierre |
|---|---|---|
| «listo para tomar acción e invertir» | 1.189 | 9.4 % |
| «interesado en saber más» | 370 | 5.7 % |
| «en búsqueda, no estoy listo» | 60 | 3.3 % |

Casi 3× entre el techo y el piso de la segunda. **Basta para ordenar una cola**;
no basta todavía para un número 0-100 defendible — los tramos altos de
presupuesto tienen 12-23 leads, y con esas muestras la diferencia entre 16.7 %
y 26.7 % no es señal, es ruido.

⚠️ **«Sin responder» no es una categoría comparable.** En presupuesto rinde
7.7 % (el piso) y en disposición 12.3 % (el techo). Son poblaciones distintas —
formularios y épocas distintas—, no un mismo grupo comportándose de dos formas.
Nunca se pondera; se manda a su propio balde.

---

## 4. Qué población se excluye, y por qué

Criterio de aceptación explícito. Se excluyen:

- **66 de 230 reportes de llamada** con los cuatro scores BANT en **cero
  literal**. No son leads malos: son llamadas sin transcript utilizable.
  Contarlos como ceros hunde cualquier promedio y fabrica un tramo bajo que no
  existe. Se recuperan con `--incluir-sin-analizar`, nunca por defecto.
- **Los leads sin oportunidad en el pipeline espejado.** El espejo cubre un
  pipeline por proyecto y está completo de mayo en adelante; antes de mayo hay
  hueco.
- **Los `callStatus` sin data** (51 reportes): transcripción vacía, error
  técnico, no-show. Entran al denominador de operación pero no al de calidad.

El universo queda definido así: **toda oportunidad del pipeline espejado tiene
banda pre-llamada** (incluida «sin datos», que es una banda, no una ausencia), y
**toda llamada analizada con BANT distinto de cero tiene banda post-llamada**.
Ningún lead queda sin clasificar.

---

## 5. Uso interno — la propuesta

### Qué se hace con cada score

**Pre-llamada**, en tres bandas, al momento de agendar:

| banda | regla | qué dispara |
|---|---|---|
| **A** | declara ≥ $1.500 **y** «listo para tomar acción» | confirmación prioritaria; se asigna primero |
| **B** | cualquier otra combinación respondida | flujo normal |
| **C** | encuesta sin responder | confirmar antes de ocupar agenda de closer |

**Post-llamada**, dos acciones:

- BANT ≥ 81 que no cerró → **cola de seguimiento activo**. Es el 38.9 %: ahí
  está el dinero que se está dejando sobre la mesa.
- BANT ≤ 60 → no se persigue con llamada; entra a la secuencia de low ticket.

### Qué ve el closer — y qué no

El corazón de la tarea es *«sin entregarlo crudo»*. La razón no es
desconfianza: **un número visible se convierte en profecía**. Un closer que ve
«32» entra a la llamada convencido de que no cierra, y no cierra. Además el
score mide lo que el lead *declaró*, no lo que vale — y el trabajo del closer es
precisamente mover eso.

Por eso:

| | el closer ve | el closer NO ve |
|---|---|---|
| antes de la llamada | el orden de su cola y las respuestas textuales de la encuesta | la banda, el número, el ranking |
| después de la llamada | su propio score de desempeño y el coaching | el BANT del lead |

El score vive en la **capa de operación** —quién confirma, quién asigna, quién
arma la cola de seguimiento— y no en la capa de conversación.

Las respuestas textuales sí se le muestran completas: saber que el lead escribió
*«tengo $500»* es contexto que le sirve. Saber que eso lo pone en banda B solo lo
condiciona.

---

## 6. Lo que falta y es decisión humana

1. **Firmar la política de visibilidad** de la sección 5. Es de Luis David y
   David Castaño, los dos asignados.
2. **Ajustar el score pre-llamada a 0-100.** Hoy son tres bandas sostenidas por
   dos preguntas. Para un número hace falta más volumen en los tramos altos.
3. **Decidir si `7fd54080` se reescribe.** Pide asignar «los de calificación 8 o
   más» al mejor closer. Ese 8 no existe en ninguna escala nuestra; lo más
   cercano es la banda A. La regla es implementable, el umbral que cita no.
4. **Trabajar la cola de seguimiento.** Ya está medida: de las **95 llamadas con
   BANT ≥ 81, 57 quedaron en «seguimiento»** y nunca cerraron. Son leads que el
   analizador calificó como los mejores del embudo —el tramo que convierte
   38.9 %— y que se enfriaron. Se reparten en **Ayrton Vega (21)** y **Carlos
   González (19)**, con 9 más sin closer resuelto, y van desde noviembre de 2025
   hasta hoy. Esta es la aplicación inmediata del score, y no necesita que se
   firme nada: la lista existe.

---

## Reproducir

```bash
bash/calls/lead_profile.sh --by tramo      # validación del score post-llamada
bash/calls/lead_profile.sh --by base       # los subgrupos de lead
bash/crm/opp_detail.sh <opp-id>            # la encuesta que respondió un lead
```

---
name: actualizarse
description: Actualizar este copiloto desde su servidor — git pull + re-esconder la ingeniería + contar qué llegó. Use cuando el humano pida actualizar(se), traer lo último, "actualízate", "ponte al día", o después de que Parallelo anuncie una actualización.
---

# Actualizarse

Traer lo último del servidor a esta copia, dejar la carpeta presentable y
contarle al humano qué cambió — en su idioma, sin jerga.

**Tono:** el de siempre con tu humano: cálido, breve, cero tecnicismos.
No narres los comandos; narra lo que significan.

## Pasos

### 1 · Recordar dónde estabas

```bash
antes=$(git rev-parse HEAD)
```

### 2 · Traer lo último

```bash
git pull
```

`pull.rebase=true` ya está configurado: tus cosas personales quedan
encima de lo nuevo, solas. Si el pull falla o reporta conflicto, **no
improvises**: muestra el error tal cual y pide que se lo envíen a
Santiago (Parallelo). No sigas al paso 3.

### 3 · Dejar la carpeta presentable

Solo si existe `copilot.json` en la raíz (eres un copiloto; el cerebro
no esconde nada — si no existe, salta al paso 4).

La ingeniería del copiloto no tiene que estorbar la vista de la carpeta.
Nada se borra — solo deja de verse en el explorador; tú la sigues usando
igual. `identidad.md` queda visible a propósito (es el ancla de la
carpeta).

- **macOS**:
  ```bash
  chflags hidden bash viz docs bin lib data CLAUDE.md cerebro.json copilot.json package.json tema.json .gitignore 2>/dev/null || true
  ```
- **Windows** (PowerShell):
  ```powershell
  foreach ($x in 'bash','viz','docs','bin','lib','data','CLAUDE.md','cerebro.json','copilot.json','package.json','tema.json') { if (Test-Path $x) { attrib +h $x } }
  ```
- **Linux**: `printf '%s\n' bash viz docs bin lib data CLAUDE.md cerebro.json copilot.json package.json tema.json > .hidden`

Repetirlo siempre es correcto: una actualización puede volver visible un
archivo que ya estaba escondido (así funciona el sistema de archivos) —
este paso lo re-esconde cada vez, sin drama.

### 4 · Contar qué llegó

```bash
git log --oneline "$antes"..HEAD -- . | head -20
git diff --stat "$antes"..HEAD | tail -5
```

Si no llegó nada: «ya estabas al día». Si llegó algo: resume en 2-3
frases QUÉ puede hacer ahora tu humano que antes no — mira qué dominios
de `bash/` o páginas de `viz/` aparecieron y tradúcelo a su trabajo
(«ahora puedo ver tus datos de finanzas», no «llegó bash/finance»). Si
cambió `CLAUDE.md` o `identidad.md`, avisa que en la próxima sesión
(`/exit` y volver a entrar) estarás aún más al día — sin obligarlo.

## Qué NO hacer

- No tocar nada fuera de esta carpeta.
- No resolver conflictos de git inventando: error → Santiago (Parallelo).
- No mostrar SHAs, rutas ni jerga en el mensaje final salvo que tu
  humano sea técnico y los pida.

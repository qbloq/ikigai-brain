# bash/video — cosas con ffmpeg

Piezas **locales y sin estado** para trabajar video: ni `.env`, ni Postgres,
ni Drive — entra un archivo, sale un archivo. Mismo espíritu que
[bash/audio/](../audio/): la composición con Drive y la DB vive en los dominios
que las usan (p.ej. `bash/calls/procesar_video.sh`), no aquí.

Reglas que comparten todos los scripts:

- `ffmpeg -nostdin` siempre: sin él ffmpeg se come el stdin heredado de un
  loop `while read` y mutila la lista de un lote (ya pasó en bash/audio).
- Nunca pisan un destino existente sin `--force`.
- `--json` para salida máquina, `-h` para uso.

| Script | Use it to… |
|--------|-----------|
| `frame.sh <video> --at T [--out F] [--force] [--json]` | Un fotograma en un instante dado. `T` = segundos (`90`, `12.5`) o reloj (`01:30`, `00:01:30.250`). Seek **preciso** (`-ss` antes de `-i`: decodifica desde el keyframe previo y descarta hasta el instante), no el keyframe más cercano. Default `<video>-<T>.jpg`; la extensión de `--out` decide el formato (jpg/png/webp). Pedir más allá del final es error (ffmpeg calla; aquí no). `--json` = `{frame, at, width, height, bytes}`. |

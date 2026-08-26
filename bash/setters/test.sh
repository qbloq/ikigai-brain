#!/usr/bin/env bash
# Tests del dominio setters — puros (sin red, sin base).
# Correr: bash bash/setters/test.sh   (sale 0 si todo pasa)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/lib" && python3 -m unittest -v test_agenda_lib

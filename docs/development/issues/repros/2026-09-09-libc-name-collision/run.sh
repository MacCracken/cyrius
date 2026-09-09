#!/bin/sh
# Usage: ./run.sh            -> reproduces the failure
#        ./run.sh localize   -> applies the objcopy workaround
set -e
LIB="${CYRIUS_LIB:-$HOME/.cyrius/lib}"
{ printf 'object;\n'
  for m in syscalls string fmt alloc io vec str assert tagged fnptr; do
      echo "include \"$LIB/$m.cyr\""
  done
  cat app.cyr
} > full.cyr
CYRIUS_ALLOW_ABSOLUTE_INCLUDES=1 cycc < full.cyr > app.o
[ "$1" = "localize" ] && objcopy -L memchr app.o
cc -c main.c $(pkg-config --cflags libsystemd) -o main.o
cc app.o main.o $(pkg-config --libs libsystemd) -o repro
timeout 10 ./repro || echo "(timed out or failed)"

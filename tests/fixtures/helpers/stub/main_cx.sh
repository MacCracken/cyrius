#!/bin/sh
# Stand-in cx compiler (the checkout's src/main_cx.cyr in the xb golden): the "bytecode" is
# the exit code plus one; BADCX fails the compile.
src=$(cat)
case "$src" in *BADCX*|*BADBAD*) echo "error: cx stub refuses" >&2; exit 2 ;; esac
code=$(printf '%s\n' "$src" | sed -n 's/^EXIT //p' | head -1)
[ -n "$code" ] || code=0
echo "CYX $((code + 1))"

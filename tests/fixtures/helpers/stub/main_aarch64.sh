#!/bin/sh
# Stand-in aarch64 compiler (the checkout's src/main_aarch64.cyr in the xb golden): the binary
# exits with the code plus two; BADA64 fails the compile.
src=$(cat)
case "$src" in *BADA64*|*BADBAD*) echo "error: a64 stub refuses" >&2; exit 3 ;; esac
code=$(printf '%s\n' "$src" | sed -n 's/^EXIT //p' | head -1)
[ -n "$code" ] || code=0
printf '#!/bin/sh\nexit %s\n' "$((code + 2))"

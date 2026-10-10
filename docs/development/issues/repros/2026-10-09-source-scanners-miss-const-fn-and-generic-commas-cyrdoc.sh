#!/bin/sh
# issues/2026-10-09-source-scanners-miss-const-fn-and-generic-commas.md, item 4 — cyrdoc copies a signature
# into a 256-byte buffer with no bound. This writes one documented 80-parameter fn line (~820 bytes) and runs
# cyrdoc on it: the signature it prints comes back out of that buffer whole (~806 bytes), i.e. ~550 bytes were
# written past the allocation. Usage: sh <this> [path/to/cyrdoc]   (default: build/cyrdoc)
set -eu
CYRDOC=${1:-build/cyrdoc}
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
{
    printf '# doc\nfn many('
    i=1; while [ $i -le 80 ]; do printf 'p%d: i64, ' $i; i=$((i + 1)); done
    printf 'z): i64 { return z; }\n'
} > "$D/many.cyr"
rc=0
"$CYRDOC" "$D/many.cyr" > "$D/out.md" || rc=$?
sig=$(grep '^### ' "$D/out.md" | head -1)
echo "cyrdoc rc=$rc; printed signature: ${#sig} bytes (sigbuf is alloc(256))"

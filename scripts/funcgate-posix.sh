#!/bin/sh
# funcgate-posix.sh — REAL consumer-flow functional gate (macOS / Linux).
#
# The self-host gate (cycc==cycc byte-identical) and a single-file `cyrius build`
# BOTH pass while the toolchain can't list a directory — neither walks one. That
# blind spot let arm64-macOS `lib sync` rot, green, for 10+ releases until a
# consumer (yantra) hit it. This gate runs the flow a real user runs and fails
# LOUD at the first broken step:
#
#   init -> lib sync (dir-walk) -> add a path dep + pull deps -> build a fib that
#   ALLOCATES (vec-grown sequence) -> run/assert -> hash + reproducible-build.
#
# Usage: funcgate-posix.sh <cyrius-bin> <scratch-dir> <CYRIUS_HOME>
# Exits 0 only if the WHOLE flow works; a distinct non-zero code per failing step
# (11 lib-sync, 12 deps, 13 build, 14 run/alloc, 15 non-reproducible). See
# docs/development/issues/2026-06-04-shipped-broken-functionality-found-by-consumers.md.
set -e

CY="${1:?usage: funcgate-posix.sh <cyrius-bin> <scratch> <CYRIUS_HOME>}"
WORK="${2:?scratch dir}"
export CYRIUS_HOME="${3:?CYRIUS_HOME}"

_hash() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }
_sign() { command -v codesign >/dev/null 2>&1 && codesign -s - -f "$1" >/dev/null 2>&1 || true; }

rm -rf "$WORK" && mkdir -p "$WORK" && cd "$WORK"

echo "funcgate: init"
"$CY" init proj >/dev/null 2>&1 || { echo "FUNCGATE FAIL(10): cyrius init"; exit 10; }
cd proj

echo "funcgate: lib sync (walks the snapshot lib dir — the getdirentries path)"
"$CY" lib sync >/dev/null 2>&1 && [ -s lib/fs.cyr ] \
  || { echo "FUNCGATE FAIL(11): lib sync did not vendor lib/fs.cyr — dir-walk broken"; exit 11; }

echo "funcgate: pull deps (resolve the manifest's [deps] stdlib modules)"
"$CY" deps >/dev/null 2>&1 || { echo "FUNCGATE FAIL(12): cyrius deps failed"; exit 12; }
[ -s lib/vec.cyr ] || { echo "FUNCGATE FAIL(12): deps/sync left no lib/vec.cyr"; exit 12; }

echo "funcgate: build a fib that allocates (vec-grown sequence — real heap use)"
cat > src/main.cyr <<'CYR'
include "lib/alloc.cyr"
include "lib/vec.cyr"
fn main(): i64 {
    alloc_init();
    var seq = vec_new();
    vec_push(seq, 0);
    vec_push(seq, 1);
    var i = 2;
    while (i <= 30) {
        vec_push(seq, vec_get(seq, i - 1) + vec_get(seq, i - 2));   # vec grows -> alloc
        i = i + 1;
    }
    if (vec_get(seq, 30) == 832040) { return 42; }   # fib(30)
    return 1;
}
CYR
"$CY" build src/main.cyr build/fib >/dev/null 2>&1 && [ -e build/fib ] \
  || { echo "FUNCGATE FAIL(13): cyrius build produced no binary"; exit 13; }
_sign build/fib

echo "funcgate: run (assert fib(30)=832040 -> exit 42; exercises the allocator)"
r=0; ./build/fib || r=$?
[ "$r" -eq 42 ] || { echo "FUNCGATE FAIL(14): fib exited $r (expected 42) — allocation/codegen broken"; exit 14; }

echo "funcgate: hash + reproducible-build"
H1=$(_hash build/fib)
"$CY" build src/main.cyr build/fib2 >/dev/null 2>&1
_sign build/fib2
H2=$(_hash build/fib2)
[ "$H1" = "$H2" ] || { echo "FUNCGATE FAIL(15): non-reproducible build ($H1 != $H2)"; exit 15; }

echo "FUNCGATE_OK hash=$H1"

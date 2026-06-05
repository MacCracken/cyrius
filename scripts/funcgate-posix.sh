#!/bin/sh
# funcgate-posix.sh — REAL consumer-flow functional gate (macOS / Linux).
#
# The self-host gate (cycc==cycc byte-identical) and a single-file `cyrius build`
# BOTH pass while the toolchain can't list a directory — neither walks one. That
# blind spot let arm64-macOS `lib sync` rot, green, for 10+ releases until a
# consumer (yantra) hit it. This gate runs the flow a real user runs and fails
# LOUD at the first broken step:
#
#   init -> lib sync (dir-walk) -> pull deps -> build a fib that ALLOCATES
#   (vec-grown sequence) -> run/assert -> hash + reproducible-build -> build a
#   SECOND program that exercises the hashmap (hash_u64 + str/fmt) -> run/assert.
#
# Two distinct allocating programs (vec path + hashmap/str path) so a codegen or
# stdlib regression localizes to a toolchain area by exit code rather than a
# single pass/fail. This is also wired into the always-green Linux jobs (Test
# ubuntu / AGNOS) as a baseline — a red there is a real toolchain regression, not
# a platform gap.
#
# Usage: funcgate-posix.sh <cyrius-bin> <scratch-dir> <CYRIUS_HOME>
# Exits 0 only if the WHOLE flow works; a distinct non-zero code per failing step:
#   10 init    11 lib-sync(dir-walk)   12 deps   13 fib-build   14 fib-run/alloc
#   15 non-reproducible   16 map-build   17 map-run(hashmap/str). See
# docs/development/issues/2026-06-04-shipped-broken-functionality-found-by-consumers.md.
set -e

CY="${1:?usage: funcgate-posix.sh <cyrius-bin> <scratch> <CYRIUS_HOME>}"
WORK="${2:?scratch dir}"
export CYRIUS_HOME="${3:?CYRIUS_HOME}"

_hash() {
  if   command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum     >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v openssl    >/dev/null 2>&1; then openssl dgst -sha256 "$1" | awk '{print $NF}'
  else cksum "$1" | awk '{print "cksum:"$1"-"$2}'; fi   # cksum is POSIX — always present
}
_sign() { command -v codesign >/dev/null 2>&1 && codesign -s - -f "$1" >/dev/null 2>&1 || true; }

rm -rf "$WORK" && mkdir -p "$WORK" && cd "$WORK"

# Tell `cyrius init` which toolchain version to stamp into cyrius.cyml. A real
# consumer install conveys this via ~/.cyrius/current; with a throwaway
# CYRIUS_HOME the init script's detection can miss it (it checks
# ~/.cyrius/current and a symlink-sensitive $CYRIUS/VERSION). This is the
# DOCUMENTED override and is purely cosmetic — without it the gate would
# falsely RED at init instead of reaching the steps that actually exercise the
# toolchain (lib sync / build / run). The real platform truth is below.
export CYRIUS_VER="${CYRIUS_VER:-$(cat "$CYRIUS_HOME/current" 2>/dev/null)}"

echo "funcgate: init (CYRIUS_VER=$CYRIUS_VER)"
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
# Hash the UNSIGNED compiler output now: codesign is non-deterministic, so a
# signed binary can't be compared for reproducibility (the .44 lesson).
H1=$(_hash build/fib)
_sign build/fib

echo "funcgate: run (assert fib(30)=832040 -> exit 42; exercises the allocator)"
r=0; ./build/fib || r=$?
[ "$r" -eq 42 ] || { echo "FUNCGATE FAIL(14): fib exited $r (expected 42) — allocation/codegen broken"; exit 14; }

echo "funcgate: reproducible-build (rebuild SAME source + SAME output name)"
# Must reuse the SAME output name: Mach-O embeds the output basename as the
# code-signature identifier, so building fib vs fib2 always differs by those
# bytes even when the compiler output is otherwise identical. Rebuild build/fib
# (overwriting the signed copy with a fresh unsigned one) and compare unsigned.
"$CY" build src/main.cyr build/fib >/dev/null 2>&1
H2=$(_hash build/fib)
[ "$H1" = "$H2" ] || { echo "FUNCGATE FAIL(15): non-reproducible build ($H1 != $H2)"; exit 15; }

echo "funcgate: build a SECOND program — u64 hashmap + str/fmt (hash + more alloc)"
cat > src/mapprog.cyr <<'CYR'
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/syscalls.cyr"
include "lib/vec.cyr"
include "lib/str.cyr"
include "lib/fnptr.cyr"
include "lib/hashmap.cyr"
fn main(): i64 {
    alloc_init();
    var m = map_u64_new();
    var i = 1;
    while (i <= 50) { map_u64_set(m, i, i * i); i = i + 1; }   # hash + grow/rehash
    var sum = 0;
    var k = 1;
    while (k <= 50) { sum = sum + map_u64_get(m, k); k = k + 1; }   # probe/lookup
    if (sum == 42925 && map_count(m) == 50) { return 43; }   # sum of squares 1..50
    return 1;
}
CYR
"$CY" build src/mapprog.cyr build/mapprog >/dev/null 2>&1 && [ -e build/mapprog ] \
  || { echo "FUNCGATE FAIL(16): hashmap program failed to build"; exit 16; }
_sign build/mapprog

echo "funcgate: run hashmap program (assert sum-of-squares -> exit 43)"
r=0; ./build/mapprog || r=$?
[ "$r" -eq 43 ] || { echo "FUNCGATE FAIL(17): mapprog exited $r (expected 43) — hashmap/str codegen broken"; exit 17; }

echo "FUNCGATE_OK hash=$H1 (fib+hashmap flows verified)"

#!/usr/bin/env bash
# Repro: a source that includes a stdlib module its project does not list in `[deps] stdlib` (here
# `include "lib/sakshi.cyr"` with sakshi unlisted) builds and runs: the include resolves from the pinned toolchain's
# lib/, nothing is vendored into the project's lib/, cyrius.lock has no row for it, and `cyrius deps --locked` passes.
# No step says so (`cyrius build -v` lists only the declared leaves). The lock's contract — lib/ and cyrius.lock are
# exactly what the build compiles — silently does not cover that module; a toolchain upgrade changes it unseen. In
# rasayan, sakshi resolved this way through M0 part 3a, and sandhi with its TLS stack still does for the [lib.ai]
# probes (port-parity.md §3, probes 7 and 10).
# Exits 1 while the defect is present: build OK, the module absent from lib/ and the lock, --locked green, and no
# diagnostic naming it.
#
#   bash docs/development/issues/repros/2026-11-16-unlisted-stdlib-include-resolves-from-the-toolchain.sh; echo $?
set -u
root=$(cd "$(dirname "$0")/../../../.." && pwd)
w=$root/build/upstream-repros/unlisted-stdlib
rm -rf "$w"
mkdir -p "$w/src"
cat > "$w/cyrius.cyml" <<'TOML'
[package]
name = "unlisted"
version = "0.0.1"
language = "cyrius"
cyrius = "6.7.18"

[build]
entry = "src/main.cyr"
output = "build/unlisted"

[deps]
stdlib = ["string", "fmt", "alloc", "syscalls", "io"]
TOML
cat > "$w/src/main.cyr" <<'CYR'
include "lib/sakshi.cyr"

fn main(): i64 {
    alloc_init();
    var lv = sakshi_get_level();
    print("sakshi level ", 13);
    fmt_int(lv);
    println("");
    return 0;
}

var r = main();
sys_exit_group(r);
CYR
cd "$w" || exit 2
cyrius deps > deps.log 2>&1 || { cat deps.log; exit 2; }
out=$(cyrius build -v src/main.cyr build/unlisted 2>&1)
brc=$?
[ "$brc" -eq 0 ] || { printf '%s\n' "$out"; echo "repro: the build failed"; exit 0; }
./build/unlisted
vendored=0
[ -f lib/sakshi.cyr ] && vendored=1
locked=$(grep -c 'lib/sakshi.cyr' cyrius.lock)
cyrius deps --locked > locked.log 2>&1
lrc=$?
said=$(printf '%s\n' "$out" | grep -c -i 'sakshi')
echo "lib/sakshi.cyr vendored: $vendored; lock rows: $locked; deps --locked rc: $lrc; build lines naming sakshi: $said"
if [ "$vendored" -eq 0 ] && [ "$locked" -eq 0 ] && [ "$lrc" -eq 0 ] && [ "$said" -eq 0 ]; then
    echo "repro: DEFECT PRESENT (an unlisted stdlib include compiled from the toolchain, unvendored and unlocked, silently)"
    exit 1
fi
echo "repro: fixed (refused, vendored, locked or at least named)"
exit 0

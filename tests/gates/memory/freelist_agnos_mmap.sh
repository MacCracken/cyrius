#!/bin/sh
# tests/gates/memory/freelist_agnos_mmap.sh — v6.3.31 freelist agnos mmap-ABI gate.
#
# `lib/freelist.cyr`'s two mmap sites must dispatch by target: agnos `mmap#27` is
# SINGLE-ARG (length in arg1/rdi; kernel ignores addr/prot/flags/fd/off), while
# Linux/BSD mmap is 6-arg (length in arg2/rsi, addr=0 in arg1/rdi). The pre-fix
# freelist used the 6-arg form on agnos → length landed as arg1=0 → mmap returned 0
# → first store derefs NULL → SIGSEGV on every agnos `fl_alloc` consumer (libro's
# audit chain, sigil's crypto; found via mirshi-fanout running descent).
#
# Asserts: (1) the DEFAULT (Linux) freelist runs correct — a small (arena) + large
# (direct) alloc round-trip exits 42; (2) an agnos-target build compiles clean (the
# `#ifdef` doesn't break the agnos build); (3) source integrity — the `_fl_mmap`
# dispatcher carries the agnos single-arg branch and BOTH mmap sites route through
# it (no raw 6-arg `syscall(SYS_MMAP, 0, …)` remains). (The single-arg emit on real
# agnos is consumer-verified end-to-end — descent runs; a disasm arg-count check is
# unreliable here because `syscall()` routes through a shared arity helper.)
set -u
cd "$(dirname "$0")/../../.." || exit 2
TMP="${TMPDIR:-/tmp}/flagnos.$$"
mkdir -p "$TMP" || exit 2
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/fl.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/mmap.cyr"
include "lib/freelist.cyr"
fn main(): i64 {
    var p = fl_alloc(32);          # small → arena mmap
    store64(p, 12345);
    var big = fl_alloc(200000);    # large → direct mmap
    store64(big, 67890);
    if (load64(p) != 12345) { return 1; }
    if (load64(big) != 67890) { return 2; }
    return 42;
}
EOF

# (1) default Linux path runs correct (small arena + large direct alloc round-trip).
cat "$TMP/fl.cyr" | build/cycc > "$TMP/fl_lin" 2>/dev/null || { echo "FAIL: Linux freelist build"; exit 1; }
chmod +x "$TMP/fl_lin"; "$TMP/fl_lin" >/dev/null 2>&1; el=$?
[ "$el" = "42" ] || { echo "FAIL: Linux fl_alloc round-trip exit=$el (expect 42)"; exit 1; }

# (2) agnos-target build compiles clean.
CYRIUS_TARGET_AGNOS=1 sh -c "cat \"$TMP/fl.cyr\" | build/cycc > \"$TMP/fl_ag\"" 2>/dev/null || { echo "FAIL: agnos freelist build"; exit 1; }
[ -s "$TMP/fl_ag" ] || { echo "FAIL: agnos freelist build produced no output"; exit 1; }

# (3) source integrity: the dispatcher + both sites route through it.
F=lib/freelist.cyr
grep -q "fn _fl_mmap(" "$F" || { echo "FAIL: _fl_mmap dispatcher missing from $F"; exit 1; }
# the agnos single-arg branch must be present inside _fl_mmap
awk '/fn _fl_mmap\(/{f=1} f&&/#ifdef CYRIUS_TARGET_AGNOS/{a=1} f&&/syscall\(SYS_MMAP, length\)/{s=1} /^}/{if(f)exit} END{exit !(a&&s)}' "$F" \
  || { echo "FAIL: _fl_mmap lacks the '#ifdef CYRIUS_TARGET_AGNOS → syscall(SYS_MMAP, length)' single-arg branch"; exit 1; }
# ALL raw mmap syscalls must live in _fl_mmap's two branches (agnos 1-arg + else 6-arg)
# = exactly 2 `syscall(SYS_MMAP` occurrences; a 3rd means an alloc site still calls
# mmap directly instead of routing through _fl_mmap.
nraw=$(grep -c "syscall(SYS_MMAP" "$F")
if [ "$nraw" != "2" ]; then
    echo "FAIL: expected exactly 2 raw mmap syscalls (the _fl_mmap agnos+else branches), found $nraw — an alloc site isn't routed through _fl_mmap"; exit 1
fi
# both alloc sites must call the dispatcher.
grep -q "_fl_mmap(FL_ARENA_SIZE)" "$F" || { echo "FAIL: _fl_arena_alloc doesn't route through _fl_mmap"; exit 1; }
grep -q "_fl_mmap(total)" "$F" || { echo "FAIL: fl_alloc large path doesn't route through _fl_mmap"; exit 1; }

echo "OK: freelist Linux round-trip=42; agnos build clean; _fl_mmap dispatches the agnos single-arg mmap ABI"
exit 0

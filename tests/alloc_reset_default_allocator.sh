#!/bin/sh
# Gate: alloc_reset() must not invalidate the process-wide default Allocator.
#
# THE BUG (filed by hisab 2026-08-05, fixed v6.5.7). `default_alloc()` built the
# 40-byte Allocator vtable with `allocator_new`, i.e. via `alloc(40)` — INSIDE the global
# bump arena — and memoized its address in `_default_allocator`. `alloc_reset()` zeroes
# the reused span of the first chunk and rewinds the bump pointer back over it, but never
# cleared the memo. So the memo survived as a pointer into scrubbed, re-issuable arena
# space, and the next allocation through the default allocator loaded a function pointer
# of 0 out of the wiped vtable and called it:
#
#     alloc_init(); vec_new(); alloc_reset(); vec_new();   ->  SIGSEGV (exit 139)
#
# Both calls used exactly as documented. No unsafe construct, no FFI, no manual store64
# on the consumer side. The v6.4.1 zero-on-reset scrub is NOT the bug — without it the
# rewind still re-issues those 40 bytes and the vtable gets overwritten by unrelated
# data, which is a nondeterministic jump instead of a deterministic null one. The scrub
# is what made this findable.
#
# THE FIX: the vtable now lives in file-scope static storage, so no arena operation can
# reach it. The lazy-init CAS went with it — the published address is a compile-time
# constant, so racing threads store the identical value into the identical buffer and a
# plain store is race-safe.
#
# ⚠ AXIS 3 IS THE ONE THAT MATTERS AND THE REASON THIS GATE EXISTS.
# The storage MUST be declared `var _default_allocator_storage: i64[5];` — TYPED.
# A bare top-level `var x[N]` is N*8 bytes under cycc but N bytes under **cybs**, so the
# natural-looking `[5]` reserves 40 B in the compiler and 8 B in the bootstrap compiler.
# gen1 then writes the vtable over whatever follows it — and that variant STILL PASSES
# `gen2 == gen3`, because the corruption is confined to gen1. It is a GREEN seed-derive
# over a silently broken intermediate. Measured directly, below.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 2
CC="$ROOT/build/cycc"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

PRE='include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"'

runprobe() {
    printf '%s\n%s\n' "$PRE" "$1" > "$D/p.cyr"
    "$CC" < "$D/p.cyr" > "$D/p.bin" 2>/dev/null
    chmod +x "$D/p.bin" 2>/dev/null
    timeout 30 "$D/p.bin" >/dev/null 2>&1
    echo $?
}

# ── AXIS 1: the filed repro. 139 = SIGSEGV (the bug), 42 = fixed.
echo "axis 1 — vec_new() after alloc_reset() (139 = SIGSEGV, 42 = fixed):"
check "reset-then-allocate" 42 "$(runprobe 'fn main(): i64 {
    alloc_init();
    var v1 = vec_new();
    vec_push(v1, 1);
    alloc_reset();
    var v2 = vec_new();
    vec_push(v2, 2);
    if (vec_get(v2, 0) != 2) { return 7; }
    return 42;
}
var r = main();
sys_exit_group(r);')"

# ── AXIS 2: it must survive REPEATED resets — the motivating shape is a harness
# resetting a per-frame arena between cases, not resetting once.
echo "axis 2 — 50 reset/allocate cycles stay sound:"
check "repeated resets" 42 "$(runprobe 'fn main(): i64 {
    alloc_init();
    var i = 0;
    while (i < 50) {
        var v = vec_new();
        vec_push(v, i);
        if (vec_get(v, 0) != i) { return 8; }
        alloc_reset();
        i = i + 1;
    }
    return 42;
}
var r = main();
sys_exit_group(r);')"

# ── AXIS 3: THE BOOTSTRAP-DIVERGENCE AXIS. Assemble cybs straight from the seed and
# measure the reservation on BOTH compilers. A declaration that reserves 40 B under cycc
# and 8 B under cybs is the failure this gate exists to catch, and neither the cycc
# fixpoint nor `gen2 == gen3` can see it.
echo "axis 3 — the storage declaration reserves 5 slots on BOTH cycc and cybs:"
if [ ! -x bootstrap/asm ]; then
    echo "  FAIL: bootstrap/asm missing — cannot assemble cybs"; fails=$((fails + 1))
else
    bootstrap/asm < bootstrap/cybs.cyr > "$D/cybs" 2>/dev/null
    chmod +x "$D/cybs" 2>/dev/null
    # Write all 5 slots, then confirm the global declared immediately after is intact.
    cat > "$D/clob.cyr" <<'EOF'
var probe: i64[5];
var sentinel = 12345;
var r = 0;
fn main(): i64 {
    var s = &probe;
    store64(s, 1); store64(s + 8, 2); store64(s + 16, 3);
    store64(s + 24, 4); store64(s + 32, 5);
    if (sentinel != 12345) { return 9; }
    return 42;
}
r = main();
syscall(60, r);
EOF
    "$D/cybs" < "$D/clob.cyr" > "$D/cb.bin" 2>/dev/null; chmod +x "$D/cb.bin" 2>/dev/null
    timeout 30 "$D/cb.bin" >/dev/null 2>&1
    check "cybs: sentinel intact (9 = clobbered)" 42 "$?"
    "$CC" < "$D/clob.cyr" > "$D/cc.bin" 2>/dev/null; chmod +x "$D/cc.bin" 2>/dev/null
    timeout 30 "$D/cc.bin" >/dev/null 2>&1
    check "cycc: sentinel intact" 42 "$?"
    # And prove the gate can SEE the bad form: the bare `[5]` must clobber under cybs.
    sed 's/^var probe: i64\[5\];$/var probe[5];/' "$D/clob.cyr" > "$D/bare.cyr"
    "$D/cybs" < "$D/bare.cyr" > "$D/bb.bin" 2>/dev/null; chmod +x "$D/bb.bin" 2>/dev/null
    timeout 30 "$D/bb.bin" >/dev/null 2>&1
    check "bare [5] DOES clobber under cybs (proves this axis works)" 9 "$?"
fi

# ── AXIS 4: structural. The declaration must stay typed, and the vtable must not go
# back into the arena. A future "simplification" to allocator_new re-opens the bug.
echo "axis 4 — structural: typed storage, vtable not arena-allocated:"
n_typed=$(grep -c '^var _default_allocator_storage: i64\[5\];' lib/alloc.cyr)
check "typed i64[5] declaration present" 1 "$n_typed"
body=$(awk '/^fn default_alloc\(/,/^}/' lib/alloc.cyr)
# Code lines only — the body's comment NAMES bump_allocator/allocator_new to explain
# which four slots are being written, and that prose must not trip the check.
n_arena=$(printf '%s\n' "$body" | grep -vE '^[[:space:]]*#' | grep -c 'allocator_new(\|bump_allocator(' || true)
check "default_alloc does not build into the arena" 0 "$n_arena"
n_static=$(printf '%s\n' "$body" | grep -c '_default_allocator_storage')
check "default_alloc fills the static storage" 1 "$n_static"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: alloc-reset-default-allocator — vtable is reset-proof on cycc AND cybs"
    exit 0
fi
echo "FAIL: alloc-reset-default-allocator — $fails assertion(s) failed"
exit 1

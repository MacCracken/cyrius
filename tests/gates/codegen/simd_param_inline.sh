#!/bin/sh
# simd_param_inline.sh — v6.5.52. Value-form SIMD wrappers are INLINED, correctly.
#
# WHY. A value-form SIMD chain emitted a `call` per link, and every xmm is caller-saved under
# SysV, so each intermediate was provably spilled and reloaded — no register allocator can fix
# that while the chain crosses call boundaries. Inlining is therefore a PREREQUISITE for SIMD
# register residency, not a nicety. Measured on a 2M-iteration chain: 24 ms -> 16 ms.
#
# ⛔ FOUR SEPARATE DEFECTS HAD TO LAND TOGETHER, and each one alone still looked "nearly
# working" — which is why the axes below test VALUES, not just exit codes:
#   1. `SFINL` packed param names from slots 0/1, which assumes ONE slot per param. A wide
#      param puts (n-1) ANON fillers BEFORE its named slot, so slot 0 held the anon marker
#      `0 - 1`; through `& 0xFFFFFFFF` that becomes 0xFFFFFFFF, which is POSITIVE as an i64, so
#      FINDLOCAL's `if (sn >= 0)` guard handed it to STREQ as a name offset -> SIGSEGV in cycc.
#   2. Param slots were a fixed 8 bytes; f32v4/f64v2 are 16 and f64v4 is 32, so arg 0 overran
#      arg 1. ONE SIMD param worked, TWO corrupted — hence axis 1 uses TWO with DISTINCT values.
#   3. `SLTYPE` was never re-applied to the replayed param, so it stopped being SIMD-typed
#      inside the body ("value-form SIMD arg type mismatch" on a mixed SIMD+int signature).
#   4. `PCMPE` does not materialise a value-form SIMD operand at all. The normal call path
#      routes them in TWO PASSES for a stated reason — the arg "MUST be a local", loaded to XMM
#      only AFTER the int args, "so int-arg eval (which may clobber XMM during PCMPE) doesn't
#      trample SIMD state". Without that the replay stored whatever XMM0 last held: measured as
#      three consecutive `movupd %xmm0, ...` with NO load between them, so both params took a
#      previous local's value and f32v4_dot returned 36.0 where 8.0 was correct.
#
# ⚠ AXIS 3 AND 4 GUARD THE SCOPING, and both were real failures during development. The
# wrappers are all `var r: <vec>; <op>(&r,&a,&b,n); return r;`, so inlining them puts a `var r`
# into the caller — which collided with a caller's own `r` ("duplicate variable"), and left the
# name registered so a SECOND use of the same wrapper collided with the FIRST. Fixed by making
# the replay a nested SCOPE (the dup check is `GLDEP == GSDEP`) and clearing the names on
# teardown. ⚠ GFLC is deliberately NOT restored: the inlined body's emitted code still addresses
# those frame slots at runtime, and reusing them made simd_ints SIGSEGV while compiling clean.
#
# ⚠ THE AXES SPLIT INTO TWO ROLES AND ONLY ONE OF THEM MOVES ON A BINARY SWAP.
# Measured 2026-09-04 against a pre-v6.5.52 build/cycc: **axis 4 goes RED (5 callq), axes 1-3
# stay GREEN**. That is correct, not a weak gate — without inlining the wrappers are ordinary
# calls that behave perfectly, so a value test cannot see the difference. Axis 4 proves the
# inlining HAPPENS; axes 1-3 prove the inlined path is CORRECT, and each of them was a real
# red during development (arg0 taking arg1's value, `duplicate variable` on a caller's own `r`,
# and again on the second use of the same wrapper). To mutate axes 1-3 you must break the
# replay itself — e.g. revert `_inl_simd_arg` to `PCMPE` + store, or the SFINL named-slot
# packing — not swap the compiler.
#
# ⚠ NO `set -e`: exit codes are DATA.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
CC="$ROOT/build/cycc"
FAIL=0

# ── axis 1: two SIMD params keep DISTINCT values (defects 1, 2, 4) ────────────────
cat > "$D/a.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
fn pick_a(a: f32v4, b: f32v4): i64 { return f32v4_lane0(a); }
fn pick_b(a: f32v4, b: f32v4): i64 { return f32v4_lane0(b); }
fn main(): i64 {
    var a: f32v4 = f32v4_make(0x40000000,0x40000000,0x40000000,0x40000000);
    var b: f32v4 = f32v4_splat(0x3F800000);
    if (pick_a(a, b) != 0x40000000) { return 1; }
    if (pick_b(a, b) != 0x3F800000) { return 2; }
    if (f32v4_dot(a, b) != 0x41000000) { return 3; }
    return 0;
}
var r = main();
syscall(60, r);
EOF
"$CC" < "$D/a.cyr" > "$D/a.bin" 2>/dev/null; chmod +x "$D/a.bin" 2>/dev/null
"$D/a.bin"; rc=$?
if [ "$rc" != 0 ]; then
    echo "FAIL: axis 1: two SIMD params did not keep distinct values (rc=$rc; 1=arg0 wrong, 2=arg1 wrong, 3=dot wrong)"
    FAIL=1
else echo "  ok: two SIMD params keep distinct values, and f32v4_dot is correct"; fi

# ── axis 2: a callee `var` may SHADOW a caller local of the same name ─────────────
cat > "$D/b.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
fn main(): i64 {
    var a: f32v4 = f32v4_make(0x40000000,0x40000000,0x40000000,0x40000000);
    var b: f32v4 = f32v4_splat(0x3F800000);
    var r: f32v4 = f32v4_add(a, b);
    if (f32v4_lane0(r) != 0x40400000) { return 1; }
    return 0;
}
var r2 = main();
syscall(60, r2);
EOF
"$CC" < "$D/b.cyr" > "$D/b.bin" 2>"$D/b.err"; chmod +x "$D/b.bin" 2>/dev/null
"$D/b.bin"; rc=$?
if [ "$rc" != 0 ]; then
    echo "FAIL: axis 2: a caller local named 'r' collided with the inlined body's own 'r' (rc=$rc)"
    grep -m1 "duplicate variable" "$D/b.err" | sed 's/^/        /'
    FAIL=1
else echo "  ok: an inlined body's local shadows a same-named caller local"; fi

# ── axis 3: the SAME wrapper used TWICE (teardown clears the name) ────────────────
cat > "$D/c.cyr" <<'EOF'
include "lib/simd.cyr"
include "lib/syscalls.cyr"
fn main(): i64 {
    var a: f32v4 = f32v4_make(0x40000000,0x40000000,0x40000000,0x40000000);
    var b: f32v4 = f32v4_splat(0x3F800000);
    var x: f32v4 = f32v4_add(a, b);
    var y: f32v4 = f32v4_add(x, b);
    if (f32v4_lane0(y) != 0x40800000) { return 1; }
    return 0;
}
var r = main();
syscall(60, r);
EOF
"$CC" < "$D/c.cyr" > "$D/c.bin" 2>"$D/c.err"; chmod +x "$D/c.bin" 2>/dev/null
"$D/c.bin"; rc=$?
if [ "$rc" != 0 ]; then
    echo "FAIL: axis 3: using the same SIMD wrapper twice failed (rc=$rc) — the replay teardown"
    echo "        is leaving the body's local names registered"
    FAIL=1
else echo "  ok: the same wrapper inlines twice in one fn"; fi

# ── axis 4: the calls REALLY GO AWAY (this is the point of the arc) ───────────────
cat > "$D/d.cyr" <<'EOF'
include "lib/simd.cyr"
fn chain(a: f32v4, b: f32v4): i64 {
    var t1: f32v4 = f32v4_add(a, b);
    var t2: f32v4 = f32v4_mul(t1, b);
    return f32v4_lane0(t2);
}
fn main(): i64 { return 0; }
var r = main();
EOF
CYRIUS_SYMS="$D/d.syms" "$CC" < "$D/d.cyr" > "$D/d.bin" 2>/dev/null
ADDR=$(grep -w chain "$D/d.syms" | awk '{print $1}')
if [ -z "$ADDR" ]; then
    echo "FAIL: axis 4: could not locate 'chain' in the symbol dump"; FAIL=1
else
    START=$(printf '0x%s' "$ADDR")
    STOP=$(printf '0x%x' $(( 0x$ADDR + 0x200 )))
    N=$(llvm-objdump -d --start-address=$START --stop-address=$STOP --no-show-raw-insn "$D/d.bin" 2>/dev/null | grep -c callq)
    # 5 before the arc (one per wrapper + the kernels). Anything at or above that means the
    # wrappers stopped being inlined.
    if [ "$N" -ge 5 ]; then
        echo "FAIL: axis 4: $N callq in a 2-link value chain (was 5 before inlining) — the"
        echo "        wrappers are no longer inlined, so intermediates cross call boundaries again"
        FAIL=1
    else echo "  ok: a 2-link value chain emits $N callq (was 5 before the arc)"; fi
fi

if [ "$FAIL" != 0 ]; then echo "FAIL: simd_param_inline"; exit 1; fi
echo "PASS simd_param_inline (SIMD wrappers inline; params keep distinct values; scoping holds)"

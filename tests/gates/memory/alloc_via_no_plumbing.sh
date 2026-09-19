#!/bin/sh
# Gate: the allocator dispatch helpers stay free of call plumbing (v6.5.10).
#
# THE FILED DEFECT (agnosai, 2026-08-07, measured on live 6.5.9). `alloc_via` cost
# **15.1 ns** while `arena_alloc`'s bump — align, load, add, compare, store — is about
# eight instructions. The gap was a five-call chain, three levels of which were pure
# plumbing:
#
#   allocator_alloc_fn(a)   a CALL, to perform one load64(a)
#   allocator_state(a)      a CALL, to perform one load64(a + 32)
#   fncall2                 the vtable indirection, landing on…
#   _arena_alloc            a trampoline whose entire body is `return arena_alloc(state, size)`
#   arena_alloc             the actual work
#
# Cyrius does not inline, so every one of those is a real frame.
#
# ⭐ WHY IT MATTERS MORE THAN 5 ns SOUNDS. The `_a` convention multiplies it by the size
# of the object graph, and building whole response trees on an arena is the entire point
# of the `_a` families. agnosai counted 112 allocations on one route — 32 % of the
# request — using a counting allocator wrapped around the arena's own vtable, and that
# was AFTER a hoisting pass. `bayan_json_v_obj_new_a` alone is three `alloc_via` calls,
# and every key/value pair is two more. The more faithfully a consumer threads its
# allocator, the more it paid.
#
# TWO FIXES, and the measured split (this box, 200k iterations of 10 allocations):
#   6.5.9 baseline .................. 15-16 ns/alloc
#   + inlined accessor loads ........ 12 ns      <- the large half
#   + real fn instead of trampoline .. 11 ns
#
# ⚠ THE STRUCTURAL AXIS IS NOT DECORATION. The perf axis alone cannot say WHY a number
# regressed, and a bound loose enough not to flake on a loaded box is loose enough to
# hide one of the two fixes being reverted. Assert the shape as well as the speed.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC="$ROOT/build/cycc"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

echo "axis 1 — the dispatch helpers read the vtable directly, not through calls:"
# Each accessor is a CALL doing one load64. On this path that is ~2.5 ns each.
for spec in "alloc_via:load64(a), load64(a + 32)" "free_via:load64(a + 16), load64(a + 32)" "reset_via:load64(a + 24), load64(a + 32)"; do
    fn=${spec%%:*}; want=${spec#*:}
    body=$(awk "/^fn $fn\(/,/^}/" lib/alloc.cyr)
    check "$fn inlines its two loads" 1 "$(printf '%s\n' "$body" | grep -cF "$want" || true)"
    check "$fn calls no accessor fn" 0 \
        "$(printf '%s\n' "$body" | grep -cE 'allocator_(alloc_fn|realloc_fn|free_fn|reset_fn|state)\(' || true)"
done
body=$(awk '/^fn realloc_via\(/,/^}/' lib/alloc.cyr)
check "realloc_via inlines its two loads" 1 \
    "$(printf '%s\n' "$body" | grep -cF 'load64(a + 8), load64(a + 32)' || true)"

echo "axis 2 — the accessors still EXIST (public API, only the hot path stopped calling them):"
for f in allocator_alloc_fn allocator_realloc_fn allocator_free_fn allocator_reset_fn allocator_state; do
    check "$f still defined" 1 "$(grep -c "^fn $f(" lib/alloc.cyr || true)"
done

echo "axis 3 — the arena vtable registers the REAL fns, not pass-through trampolines:"
# `_arena_alloc(state, size)` was `return arena_alloc(state, size)` — an identical
# signature, so the trampoline was a frame for nothing. Same for `_arena_reset`.
check "arena_allocator* register &arena_alloc / &arena_reset" 2 \
    "$(grep -c 'allocator_new(&arena_alloc, &_arena_realloc, &_alloc_free_noop, &arena_reset' lib/alloc.cyr || true)"
check "the pass-through trampolines are gone" 0 \
    "$(grep -cE '^fn _arena_(alloc|reset)\(' lib/alloc.cyr || true)"
# ⚠ NOT every trampoline can go: `_bump_alloc(state, size)` calls `alloc(size)` and
# `_bump_reset(state)` calls `alloc_reset()` — DIFFERENT arity, so they genuinely adapt
# rather than pass through. Removing those would corrupt the call. Assert they stay.
check "_bump_alloc stays (adapts arity, not a pass-through)" 1 "$(grep -c '^fn _bump_alloc(' lib/alloc.cyr || true)"
check "_bump_reset stays (adapts arity)" 1 "$(grep -c '^fn _bump_reset(' lib/alloc.cyr || true)"
check "_arena_realloc stays (real body, not a pass-through)" 1 "$(grep -c '^fn _arena_realloc(' lib/alloc.cyr || true)"

echo "axis 4 — runtime: correctness first, then the tripwire:"
# ⛔ 6.6.6 — THE TRIPWIRE WAS AN ABSOLUTE `NS -lt 14`, AND IT WENT BLIND ON THE BOX IT WAS SET
# ON. Measured 2026-09-19 against a scratch lib with the WHOLE v6.5.10 fix reverted (accessor
# calls back in alloc_via/reset_via, pass-through trampolines back in the vtable): 13 ns, GREEN,
# 3 of 3 runs. The fixed path now reads 9 ns here, not the 11 it was calibrated on, so the
# 15-16 ns revert it was meant to catch had slid under its own constant. It also went RED
# the other way under load (the 6.5.19 test_runner_bounded note: leaked children flipped it).
# Same defect as sync_mutex_contended.tcyr's `per < 250` (CHANGELOG [6.6.6]): a constant
# calibrated on one run of one box is not a property of the code.
#
# THE RULE NOW. The probe rebuilds BOTH shapes next to the library's alloc_via and times all
# three in the same run, interleaved, 7 rounds, keeping each one's minimum:
#   VIA — the library's alloc_via on arena_allocator's own vtable
#   FIX — the v6.5.10 shape, rebuilt: loads inlined, &arena_alloc registered directly
#   PL  — the v6.5.9 shape, rebuilt: allocator_alloc_fn()/allocator_state() CALLS and a
#         pass-through trampoline in the vtable
# and requires 2*VIA < FIX + PL — the library performs like the fixed shape, not the
# plumbed one, on whatever this host's call cost is. FIX and PL own their vtables, so a
# regression in the library moves VIA alone. PL must measure at least 10% dearer than FIX
# first (PL*10 > FIX*11): if the instrument cannot tell the two shapes apart, the verdict
# would be a coin flip, so that is reported as an instrument failure. It was `PL > FIX` —
# zero margin: a PL a few ps above FIX passed it and left 2*VIA < FIX+PL deciding on noise.
# Measured PL/FIX here: 1.35-1.39 across every row of the ledger below, i.e. a 35-39% gap
# against the 10% it must clear.
#
# MUTATION LEDGER (2026-09-19, scratch lib, this box, 3 runs each; ps/alloc VIA/FIX/PL):
#   real lib .................. 10130 / 10013-10060 / 13947-13959 ... tripwire GREEN
#   whole v6.5.10 fix reverted  14440-14505 / 10406-10429 / 14311-14368  RED (the old
#                               absolute `-lt 14` read 13 ns here: GREEN)
#   accessor CALLS only ....... 12769-12850 / 10325-10447 / 14221-14353  RED (0.4 ns margin —
#                               a bonus, not a promise; axis 1 pins it structurally)
#   trampolines only .......... 11592-11687 / 10250-10377 / 14021-14239  GREEN — one frame is
#                               under half the plumbing; axis 3 pins it structurally (RED)
cat > "$D/p.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/syscalls.cyr"
include "lib/vec.cyr"
include "lib/chrono.cyr"
# The two reference shapes. Names are the probe's own so neither collides with lib/.
fn _pl_tramp(state, size): i64 { return arena_alloc(state, size); }
fn _pl_alloc_via(a, size): i64 { return fncall2(allocator_alloc_fn(a), allocator_state(a), size); }
fn _fx_alloc_via(a, size): i64 { return fncall2(load64(a), load64(a + 32), size); }
# ps per allocation (each 10-alloc batch carries one reset_via, identical in all three).
fn _t_via(ar, n): i64 {
    var t0 = clock_now_ns();
    var i = 0;
    while (i < n) {
        alloc_via(ar,24); alloc_via(ar,24); alloc_via(ar,24); alloc_via(ar,24); alloc_via(ar,24);
        alloc_via(ar,24); alloc_via(ar,24); alloc_via(ar,24); alloc_via(ar,24); alloc_via(ar,24);
        reset_via(ar);
        i = i + 1;
    }
    return (clock_now_ns() - t0) * 100 / n;
}
fn _t_fx(ar, fx, n): i64 {
    var t0 = clock_now_ns();
    var i = 0;
    while (i < n) {
        _fx_alloc_via(fx,24); _fx_alloc_via(fx,24); _fx_alloc_via(fx,24); _fx_alloc_via(fx,24); _fx_alloc_via(fx,24);
        _fx_alloc_via(fx,24); _fx_alloc_via(fx,24); _fx_alloc_via(fx,24); _fx_alloc_via(fx,24); _fx_alloc_via(fx,24);
        reset_via(ar);
        i = i + 1;
    }
    return (clock_now_ns() - t0) * 100 / n;
}
fn _t_pl(ar, pl, n): i64 {
    var t0 = clock_now_ns();
    var i = 0;
    while (i < n) {
        _pl_alloc_via(pl,24); _pl_alloc_via(pl,24); _pl_alloc_via(pl,24); _pl_alloc_via(pl,24); _pl_alloc_via(pl,24);
        _pl_alloc_via(pl,24); _pl_alloc_via(pl,24); _pl_alloc_via(pl,24); _pl_alloc_via(pl,24); _pl_alloc_via(pl,24);
        reset_via(ar);
        i = i + 1;
    }
    return (clock_now_ns() - t0) * 100 / n;
}
fn main(): i64 {
    alloc_init();
    var ar = arena_allocator(1048576);
    # Correctness: the vtable still dispatches to the arena, and reset still resets.
    var p1 = alloc_via(ar, 24);
    var p2 = alloc_via(ar, 24);
    if (p1 == 0) { return 2; }
    if (p2 == 0) { return 3; }
    if (p2 <= p1) { return 4; }                 # bumped forward
    store8(p1, 77);
    if (load8(p1) != 77) { return 5; }
    reset_via(ar);
    if (alloc_via(ar, 24) != p1) { return 6; }  # reset rewound to the same address
    # The reference vtables share the arena's STATE and reset fn; only the alloc slot differs.
    var st = load64(ar + 32);
    var fx = allocator_new(&arena_alloc, 0, 0, load64(ar + 24), st);
    var pl = allocator_new(&_pl_tramp, 0, 0, load64(ar + 24), st);
    if (_pl_alloc_via(pl, 24) == 0) { return 7; }
    if (_fx_alloc_via(fx, 24) == 0) { return 8; }
    reset_via(ar);
    var via = 0;
    var fxm = 0;
    var plm = 0;
    var r = 0;
    while (r < 7) {
        var v = _t_via(ar, 50000);
        var f = _t_fx(ar, fx, 50000);
        var q = _t_pl(ar, pl, 50000);
        if (r == 0 || v < via) { via = v; }
        if (r == 0 || f < fxm) { fxm = f; }
        if (r == 0 || q < plm) { plm = q; }
        r = r + 1;
    }
    print_num(via); syscall(1, 1, " ", 1); print_num(fxm); syscall(1, 1, " ", 1); print_num(plm);
    syscall(1, 1, "\n", 1);
    return 0;
}
var r = main();
sys_exit_group(r);
EOF
"$CC" < "$D/p.cyr" > "$D/p.bin" 2>/dev/null
if [ ! -s "$D/p.bin" ]; then
    check "the probe compiled to a non-empty binary" 1 0
else
    chmod +x "$D/p.bin"
    rc=0
    timeout 120 "$D/p.bin" > "$D/p.out" 2>&1 || rc=$?
    check "dispatch still correct (2=null,3=null,4=no-bump,5=unwritable,6=no-reset,7/8=reference vtable)" 0 "$rc"
    set -- $(tail -1 "$D/p.out" 2>/dev/null)
    VIA=${1:-}; FIX=${2:-}; PL=${3:-}
    echo "  measured (ps/alloc, min of 7): library ${VIA:-?} · fixed shape ${FIX:-?} · 6.5.9 plumbing ${PL:-?}"
    case "$VIA$FIX$PL" in
        ''|*[!0-9]*) check "the probe printed three numbers" 1 0 ;;
        *)
            check "the instrument separates the shapes (plumbing >=10% dearer than the fixed shape: PL*10 > FIX*11)" 1 \
                "$([ $((PL * 10)) -gt $((FIX * 11)) ] && echo 1 || echo 0)"
            check "alloc_via performs like the fixed shape, not the plumbing (2*VIA < FIX + PL)" 1 \
                "$([ $((2 * VIA)) -lt $((FIX + PL)) ] && echo 1 || echo 0)"
            ;;
    esac
fi

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: alloc-via-no-plumbing — vtable read inline, no pass-through trampoline, costs like the fixed shape"
    exit 0
fi
echo "FAIL: alloc-via-no-plumbing — $fails assertion(s) failed"
exit 1

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
cat > "$D/p.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/syscalls.cyr"
include "lib/vec.cyr"
include "lib/chrono.cyr"
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
    var n = 200000;
    var t0 = clock_now_ns();
    var i = 0;
    while (i < n) { reset_via(ar); i = i + 1; }
    var ctl = clock_now_ns() - t0;
    t0 = clock_now_ns();
    i = 0;
    while (i < n) {
        alloc_via(ar,24); alloc_via(ar,24); alloc_via(ar,24); alloc_via(ar,24); alloc_via(ar,24);
        alloc_via(ar,24); alloc_via(ar,24); alloc_via(ar,24); alloc_via(ar,24); alloc_via(ar,24);
        reset_via(ar);
        i = i + 1;
    }
    var tot = clock_now_ns() - t0;
    println_int((tot - ctl) / (n * 10));
    return 0;
}
var r = main();
sys_exit_group(r);
EOF
"$CC" < "$D/p.cyr" > "$D/p.bin" 2>/dev/null
chmod +x "$D/p.bin" 2>/dev/null
rc=0
timeout 120 "$D/p.bin" > "$D/p.out" 2>&1 || rc=$?
check "dispatch still correct (2=null,3=null,4=no-bump,5=unwritable,6=no-reset)" 0 "$rc"
NS=$(tail -1 "$D/p.out" 2>/dev/null)
echo "  measured: ${NS:-?} ns per alloc_via (6.5.9 was 15-16, now ~11)"
# Loose on purpose: 14 sits above the ~11 this change produces and below the 15-16 it
# replaced, so it catches a full revert without flaking on a loaded or slower box. It is
# a tripwire, not a benchmark — `benches/` tracks the numbers.
if [ -n "${NS:-}" ]; then
    check "alloc_via stays under 14 ns (was 15-16 before the fix)" 1 "$([ "$NS" -lt 14 ] && echo 1 || echo 0)"
else
    check "measurement produced a number" 1 0
fi

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: alloc-via-no-plumbing — vtable read inline, no pass-through trampoline, ~11ns"
    exit 0
fi
echo "FAIL: alloc-via-no-plumbing — $fails assertion(s) failed"
exit 1

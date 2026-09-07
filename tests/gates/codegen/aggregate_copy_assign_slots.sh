#!/bin/sh
# aggregate_copy_assign_slots.sh — v6.6.1. `X = Y;` between two locals must copy the number of
# slots the variables ACTUALLY OCCUPY, not the number their TYPE implies.
#
# ⛔ WHY THIS EXISTS. v6.5.57 added `_try_aggregate_copy_assign` so that `c = a;` between two
# inline structs copies every word instead of just the first. Its guard was `GLTYPE(dst) < 0`,
# i.e. "the type is an aggregate". But TWO different layouts share that marker:
#
#     var b: P = a;          -> INLINE: ceil(STRUCTSZ/8) slots, anonymous fillers (name -1)
#                               below the named slot.
#     var a = str_from(x);   -> POINTER: exactly ONE slot holding an address. The declaration
#                               path infers the callee's declared return sid so `a.field` works,
#                               and that stamps the SAME negative GLTYPE.
#
# So `a = b;` between two `Str` POINTERS copied STRUCTSZ(Str)/8 slots and wrote over whatever
# locals sat below them. Silent: it compiles clean, corrupts a neighbour, and the damage surfaces
# somewhere else entirely. In the wild it overwrote the `len` PARAMETER of yukti's
# `parse_uevent` mid-loop, so `for (var i = 0; i <= len; i = i + 1)` stopped terminating and
# walked off a 256-byte buffer into the process stack — the trace showed it "parsing" the
# environment (`CLAUDECODE=1`, argv[0]) before it SIGSEGV'd. **Live in every release from
# v6.5.57 to v6.6.0**, and it took a version bisect over tracked `build/cycc` binaries to find,
# because the symptom appears nowhere near the assignment.
#
# ⭐ AXIS 2 IS THE ANTI-VACUOUS ONE. The fix narrows a real feature, so the inline copy that
# v6.5.57 shipped must still copy every word. A guard that simply disabled the path would pass
# axis 1 and silently undo the fix it was guarding.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL aggregate_copy_assign_slots: no build/cycc"; exit 1; }

run() {           # run <label> <expected-exit>; source on stdin
  cat > "$T/p.cyr"
  "$CC" < "$T/p.cyr" > "$T/p" 2>"$T/p.err" || {
    echo "FAIL aggregate_copy_assign_slots: $1 did not compile"
    grep -E '^error' "$T/p.err" | head -3 | sed 's/^/    /'; exit 1; }
  chmod +x "$T/p"; "$T/p"; got=$?
  [ "$got" -eq "$2" ] || { echo "FAIL aggregate_copy_assign_slots: $1 gave $got, expected $2"; exit 1; }
}

# ── axis 1 — the miscompile: a POINTER-mode local must copy ONE slot ────────────────────────
# `guard` is a parameter; the corrupting copy reached it. Returning it proves the neighbouring
# slots were untouched.
run "Str-pointer assignment does not scribble on neighbours" 42 <<'EOF'
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"
include "lib/str.cyr"
include "lib/syscalls.cyr"
fn probe(guard): i64 {
    var a = str_from("AAA");
    var b = str_from("BBB");
    a = b;
    return guard;
}
fn main(): i64 { alloc_init(); if (probe(118) != 118) { return 1; } return 42; }
var e = main();
syscall(60, e);
EOF

# ── axis 2 — ANTI-VACUOUS: the v6.5.57 feature must survive the guard ───────────────────────
run "inline struct + vector assignment still copies EVERY word" 42 <<'EOF'
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"
include "lib/simd.cyr"
include "lib/syscalls.cyr"
struct P2 { x; y; }
fn main(): i64 {
    alloc_init();
    var a: P2;
    a.x = 11; a.y = 22;
    var c: P2;
    c = a;
    if (c.x != 11) { return 1; }
    if (c.y != 22) { return 2; }
    var b: P2 = a;
    if (b.y != 22) { return 3; }
    var v1: f32v4 = f32v4_make(0x3F800000, 0x40000000, 0x40400000, 0x40800000);
    var v2: f32v4;
    v2 = v1;
    if (f32v4_lane3(&v2) != 0x40800000) { return 4; }
    return 42;
}
var e = main();
syscall(60, e);
EOF

# ── axis 3 — the field-standing shape: a struct POINTER's fields still work after assignment ─
# The pointer local keeps its inferred sid so `.field` resolves; the assignment must retarget
# the pointer, not memcpy through it.
run "struct-pointer assignment retargets the pointer" 42 <<'EOF'
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"
include "lib/str.cyr"
include "lib/syscalls.cyr"
fn probe(guard): i64 {
    var s1 = str_from("hello");
    var s2 = str_from("worldwide");
    var n1 = str_len(s1);
    s1 = s2;
    if (str_len(s1) != 9) { return 0 - 1; }
    if (n1 != 5) { return 0 - 2; }
    return guard;
}
fn main(): i64 { alloc_init(); if (probe(7) != 7) { return 1; } return 42; }
var e = main();
syscall(60, e);
EOF

echo 'PASS aggregate_copy_assign_slots: a pointer-mode local copies ONE slot (the v6.5.57 neighbour-clobber) · inline struct AND vector assignment still copy every word · struct-pointer assignment retargets rather than memcpys'
exit 0

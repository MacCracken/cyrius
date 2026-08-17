#!/bin/sh
# v6.5.24 — `assigning non-pointer to typed pointer` must test the RIGHT SIGN.
#
# The local-variable arm of this warning gated on `lt > 0`, but in the local SLTYPE scheme
# a positive type is a narrow WIDTH (1/2/4) or a FLOAT TAG (F64_TYID 0x40000001 /
# F32_TYID 0x40000002); the pointer-like case is stored NEGATIVE as `0 - sid`
# (src/frontend/parse_decl.cyr:2490). The test was therefore inverted, with a failure mode
# in BOTH directions at once — it fired on every width- or float-annotated local, and
# never on a real typed-pointer local, so the check was unreachable for its own purpose.
# The GLOBAL arm of the same warning (`vt < 0`, src/frontend/parse.cyr:~1550) had always
# used the correct convention, so the two arms silently disagreed.
#
# ⛔ WHY A GATE. This is a WARNING, so no .tcyr can catch it: warnings don't change exit
# codes, and the false positives were visible only as noise in consumer builds. That is
# how it survived — and it was not harmless. The f64/f32 half BLOCKED a consumer feature:
# `acc = f32_op(acc, ...)` is the canonical ranga/ganita loop body, so shipping the f32
# math tier while this warned would have put a bogus warning in every consumer's f32 loop.
#
# ⭐ AXIS 4 IS THE ANTI-VACUOUS ONE. Axes 1-3 all assert an ABSENCE, so deleting the
# warning outright would make them all pass. Axis 4 requires the warning to still fire on
# a genuine typed pointer, which is also the case that never worked before this fix.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
cd "$ROOT"
T=$(mktemp --suffix=.cyr); E=$(mktemp); O=$(mktemp)
trap 'rm -f "$T" "$E" "$O"' EXIT

# Compile $T and put stderr in $E. NEVER merge stderr into the binary stream.
build() { "$CC" < "$T" > "$O" 2>"$E" || true; }
warns() { grep -c "assigning non-pointer to typed pointer" "$E" || true; }

fail=0

# --- axis 1: narrow-width annotated local must not warn on ordinary reassignment ---
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 {
    var w: i32 = 5;
    w = 6;
    return w;
}
var ec = main();
syscall(60, ec);
EOF
build
n=$(warns)
if [ "$n" -ne 0 ]; then echo "  FAIL axis 1: 'var w: i32; w = 6;' emitted $n typed-pointer warning(s)"; fail=1
else echo "  ok axis 1: narrow-width local (i32) does not warn"; fi

# --- axis 2: f64-annotated local must not warn (the half that gated the ganita f32 tier) ---
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 {
    var acc: f64 = f64_from(1);
    acc = f64_add(acc, f64_from(2));
    return f64_to(acc);
}
var ec = main();
syscall(60, ec);
EOF
build
n=$(warns)
if [ "$n" -ne 0 ]; then echo "  FAIL axis 2: 'var acc: f64; acc = f64_add(..)' emitted $n typed-pointer warning(s)"; fail=1
else echo "  ok axis 2: f64 accumulator does not warn"; fi

# --- axis 3: f32-annotated local must not warn (same tag class, distinct TYID) ---
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 {
    var s: f32 = f32_from(f64_from(1));
    s = f32_from(f64_from(2));
    return 0;
}
var ec = main();
syscall(60, ec);
EOF
build
n=$(warns)
if [ "$n" -ne 0 ]; then echo "  FAIL axis 3: 'var s: f32; s = ..' emitted $n typed-pointer warning(s)"; fail=1
else echo "  ok axis 3: f32 local does not warn"; fi

# --- axis 4 (ANTI-VACUOUS): a real typed pointer assigned a non-pointer MUST warn ---
# Before this fix this case produced NO warning at all — the check could not reach it.
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
struct Pt { x: i64; y: i64; }
fn main(): i64 {
    var p: Pt = 0;
    p = 7;
    return 0;
}
var ec = main();
syscall(60, ec);
EOF
build
n=$(warns)
if [ "$n" -lt 1 ]; then echo "  FAIL axis 4 (anti-vacuous): struct-typed local assigned a non-pointer did NOT warn — the check is unreachable again, or was deleted"; fail=1
else echo "  ok axis 4: struct-typed local assigned a non-pointer warns (check is reachable)"; fi

[ "$fail" -eq 0 ] || { echo "FAIL: typed-pointer-warn-sign"; exit 1; }
echo "PASS: typed-pointer-warn-sign — warns on typed pointers only, not on width/float-annotated locals"

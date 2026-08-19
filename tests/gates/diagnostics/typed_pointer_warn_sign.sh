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

# --- axis 5 (v6.5.28): the assignment path must consult the callee's DECLARED return type ---
# v6.5.27's sign fix made this check reach real typed-pointer locals for the FIRST time, and
# exposed the gap behind it: the DECLARATION path resolves the callee's return sid
# (parse_decl.cyr: peek `IDENT (`, FINDFN, GFRS) but the ASSIGNMENT path did not. So
# `var t: Str = mk();` was accepted while `t = mk();` — the same call, the same binding —
# warned. Two paths disagreeing about one expression. Filed from abaco.
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
struct Str { p: i64; n: i64; }
fn mk(): Str { var s: Str = 0; return s; }
fn main(): i64 {
    var t: Str = mk();
    t = mk();
    return 0;
}
var ec = main();
syscall(60, ec);
EOF
build
n=$(warns)
if [ "$n" -ne 0 ]; then echo "  FAIL axis 5: 't = mk()' warned $n time(s) — the assignment path still ignores the callee's declared return type"; fail=1
else echo "  ok axis 5: assigning a call whose declared return is a struct does not warn"; fi

# --- axis 6 (ANTI-VACUOUS for axis 5): a genuine non-pointer assignment MUST still warn ---
# Axis 5 asserts an absence; without this, suppressing the warning entirely would pass it.
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
struct Str { p: i64; n: i64; }
fn main(): i64 {
    var p: Str = 0;
    p = 7;
    return 0;
}
var ec = main();
syscall(60, ec);
EOF
build
n=$(warns)
if [ "$n" -lt 1 ]; then echo "  FAIL axis 6 (anti-vacuous): 'p = 7' on a struct-typed local did NOT warn — the check was suppressed, not fixed"; fail=1
else echo "  ok axis 6: a genuine non-pointer assignment still warns"; fi

# --- axis 7 (v6.5.29): `&x` IS a pointer — the one expression that cannot be a non-pointer ---
# The address-of branch of parse_expr never called SPSC, so `var p: *i64 = &nodes;` — the
# canonical idiom — warned. Found by MEASURING the warning's blast radius across programs/
# after the .28 fix, not by a filing: 9 warnings, of which these were the only ones with no
# defensible reading (the rest assign an `i64`-DECLARED value to a pointer, where the warning
# is type-accurate whatever one thinks of the ergonomics).
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
var nodes[80];
fn main(): i64 {
    var p: *i64 = &nodes;
    var q: *i64 = &nodes + 16;
    var loc = 7;
    var r: *i64 = &loc;
    store64(p, 1);
    return 0;
}
var ec = main();
syscall(60, ec);
EOF
build
n=$(warns)
if [ "$n" -ne 0 ]; then echo "  FAIL axis 7: '&x' assigned to a *i64 warned $n time(s) — address-of still reports no pointer scale"; fail=1
else echo "  ok axis 7: &global, &global+n and &local are all recognised as pointers"; fi

# --- axis 8 (ANTI-VACUOUS for axis 7): scale 1, not 8 — the arithmetic must not re-scale ---
# EPTR_SCALE multiplies the addend by the scale, so any value above 1 silently re-scales every
# existing `&x + n` site. This asserts the ARITHMETIC, not the warning: bytes, not slots.
# ⚠ Must exercise the ADDRESS-OF expression itself, not a `*i64`-declared local: a local
# declared `*i64` carries its own DECLARED scale of 8, so `p + 3` is slot arithmetic by
# design and says nothing about what `&buf` reports. (First draft of this axis made exactly
# that conflation and failed against correct code.)
cat > "$T" <<'EOF'
include "lib/syscalls.cyr"
var buf[64];
fn main(): i64 {
    store8(&buf + 3, 42);
    var v = load8(&buf + 3);
    return v;
}
var ec = main();
syscall(60, ec);
EOF
build
chmod +x "$O" 2>/dev/null || true
# ⚠ `set -e` is on: a bare `"$O"; rc=$?` ABORTS the gate the moment the fixture exits 42 —
# which is the PASSING case here. The `|| rc=$?` form is the only one that survives it.
rc=0
"$O" >/dev/null 2>&1 || rc=$?
if [ "$rc" -ne 42 ]; then echo "  FAIL axis 8 (anti-vacuous): '&buf + 3' addressed byte $rc, not byte 3 — the pointer scale is re-scaling byte arithmetic"; fail=1
else echo "  ok axis 8: &x + n stays BYTE arithmetic (scale 1)"; fi

[ "$fail" -eq 0 ] || { echo "FAIL: typed-pointer-warn-sign"; exit 1; }
echo "PASS: typed-pointer-warn-sign — warns on typed pointers only, not on width/float-annotated locals"

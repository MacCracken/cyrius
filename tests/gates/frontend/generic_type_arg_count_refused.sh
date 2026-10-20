#!/bin/sh
# tests/gates/frontend/generic_type_arg_count_refused.sh — 6.7.16
#
# A TYPE-ARGUMENT LIST LONGER THAN ITS GENERIC DECLARES IS REFUSED, ONCE, AT THE FIRST EXTRA ARGUMENT. With
# `struct Box<T>`, `var b: Box<i64, i64>;` compiled (the filed repro exited 3), and so did `g<i32, Pt>(5)` on
# `fn g<T>` (exit 4): every type-argument reader took two arguments whatever the generic declared — a
# one-parameter generic's second into c1, which it dropped — and a third argument was left to the enclosing
# statement ("expected '=', got ','"). Each reader now reads the arguments its generic declares, refuses the
# first one past them — "'Box' takes 1 type argument, 2 given" (the user's D5, 2026-10-19) — and steps the
# rest of the list, so the line reads as if the extra arguments were deleted and nothing cascades. A
# lookahead or typer that reads the list ahead of its parse says nothing (the parse reports it); a body
# parsed per instance reports it once; `--syntax-only` (cyrius lint) says nothing, as 6.7.15's D6 refusal.
# 6.3.33 - 6.7.15, every target. Filed: docs/development/issues/2026-10-18-excess-type-arguments-to-generic-
# struct-accepted.md
#
#   R   the filed repros, verbatim: ta.cyr (a local) refused at 2:34, ta2.cyr (a parameter) at 3:25 — one line each
#   P   every struct position, one line each at the extra argument: `sizeof(Box<i64, i64>)`, a global, a
#       `: Box<i64, i64>` return, a `*Box<i64, i64>` local, `Box<i64, Pt>` (a local and its sizeof: two lines),
#       three arguments ("3 given"), a two-parameter struct given three, a nested list (`Box<Box<i64, i64>>`,
#       `Pair<Box<i64, i64>, i64>`), an extra argument that is itself generic (`Box<i64, Box<i64>>`, its `>>`;
#       `Box<i64, P<P<i64>>>`, its `>>>`), a struct literal head, a generic struct's field (three instances),
#       a late `*Later<i64, i64>` field, a Vec element, a trait member's parameter and a `*fn( .. )` parameter
#   F   every fn-call position: `g<i32, Pt>(5)` on `fn g<T>`, a method `p.m<i32, Pt>(5)` ('P.m'), the
#       struct-valued receives (retptr and register pair), a global's initializer, `g2<i32, i16, i8>` on
#       `fn g2<A, B>` ("2 type arguments, 3 given")
#   B   a generic body with two instances reports once
#   X   --syntax-only says nothing (rc 0)
#   E   `Box<i64,>` keeps its refusal of an empty argument ("a type argument is a type name, got '>'")
#   C   controls, unchanged: `Box<i64>`, `Pair<i32, Pt>`, `Box<Box<i64>>`, `Box<Box<Pt>>`, `g<i32>(5)` and
#       `sizeof(Pair<i64, Pt>)` build and exit 38 on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine)
#   A   R1 and F1 refused with the same line by the aarch64, cx and PE compilers
#
# MUTATION (2026-10-20): CYCC = the lane's previous compiler (f201704a2, before the fix) -> RED 26: every R, P,
# F and B row and A [pe] (each builds, or P6 / P7 / F6 report the enclosing statement's errors instead); X, E,
# C and A [a64] / [cx] green (those two cross compilers are built from the tree's src).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=generic_type_arg_count_refused
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
WP="$D/wine"
WHM="$D/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$D"' EXIT
ulimit -c 0 2>/dev/null
unset CYRIUS_COVERAGE CYRIUS_COVERAGE_FILE CYRIUS_BOUNDS
fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

# one <name> <expected text> <what> [compiler-cmd]: refused (rc != 0) with EXACTLY one error line, which carries
# <expected text>.
one() {
    rc=0
    if [ $# -ge 4 ]; then sh -c "$4" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$?
    else "$CC" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$?; fi
    n=$(grep -c '^error' "$D/$1.err")
    if [ "$rc" -eq 0 ]; then bad "$3: BUILT (rc 0)"
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines, want 1: $(grep '^error' "$D/$1.err" | tr '\n' '|')"
    elif ! grep -qF -- "$2" "$D/$1.err"; then bad "$3: refused, but not with \"$2\": $(grep '^error' "$D/$1.err")"
    else ok "$3: $2"; fi
}
# lines <name> <count> <expected text> <what>: refused with <count> error lines, each carrying <expected text>.
lines() {
    rc=0
    "$CC" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err" || rc=$?
    n=$(grep -c '^error' "$D/$1.err")
    k=$(grep '^error' "$D/$1.err" | grep -cF -- "$3")
    if [ "$rc" -eq 0 ]; then bad "$4: BUILT (rc 0)"
    elif [ "$n" -ne "$2" ] || [ "$k" -ne "$2" ]; then bad "$4: $n error lines ($k with \"$3\"), want $2: $(grep '^error' "$D/$1.err" | tr '\n' '|')"
    else ok "$4: $2 x \"$3\""; fi
}

# ── R: the filed repros, verbatim ────────────────────────────────────────────────────────────────────────────
cat > "$D/ta.cyr" <<'EOF'
struct Box<T> { v: T; n; }
fn main(): i64 { var b: Box<i64, i64>; b.n = 3; return b.n; }
syscall(60, main());
EOF
cat > "$D/ta2.cyr" <<'EOF'
struct R2 { a; b; }
struct Box<T> { v: T; n; }
fn g(x: R2, y: Box<i64, i64>): i64 { return x.a + y.n; }
fn main(): i64 { var r: R2; r.a = 1; r.b = 2; var b: Box<i64>; b.n = 3; return g(r, b); }
syscall(60, main());
EOF
one ta "2:34: 'Box' takes 1 type argument, 2 given" "R1: ta.cyr (a local)"
one ta2 "3:25: 'Box' takes 1 type argument, 2 given" "R2: ta2.cyr (a parameter)"

# ── P: every struct position ─────────────────────────────────────────────────────────────────────────────────
BX='struct Box<T> { v: T; n; }'
printf '%s\nfn main(): i64 { return sizeof(Box<i64, i64>); }\n' "$BX" > "$D/p1.cyr"
one p1 "2:41: 'Box' takes 1 type argument, 2 given" "P1: sizeof(Box<i64, i64>)"
printf '%s\nvar G: Box<i64, i64> = 0;\nfn main(): i64 { return 4; }\n' "$BX" > "$D/p2.cyr"
one p2 "2:17: 'Box' takes 1 type argument, 2 given" "P2: a global"
printf '%s\nfn mk(): Box<i64, i64> { var b: Box<i64>; b.n = 6; return b; }\nfn main(): i64 { var b: Box<i64> = mk(); return b.n; }\n' "$BX" > "$D/p3.cyr"
one p3 "2:19: 'Box' takes 1 type argument, 2 given" "P3: a : Box<i64, i64> return"
printf '%s\nfn main(): i64 { var b: Box<i64>; b.n = 7; var p: *Box<i64, i64> = &b; return p.n; }\n' "$BX" > "$D/p4.cyr"
one p4 "2:61: 'Box' takes 1 type argument, 2 given" "P4: a *Box<i64, i64> local"
printf 'struct Pt { x; y; }\n%s\nfn main(): i64 { var b: Box<i64, Pt>; b.n = 8; return b.n + sizeof(Box<i64, Pt>); }\n' "$BX" > "$D/p5.cyr"
lines p5 2 "'Box' takes 1 type argument, 2 given" "P5: Box<i64, Pt>, a local and its sizeof"
printf '%s\nfn main(): i64 { var b: Box<i64, i64, i64>; b.n = 3; return b.n; }\n' "$BX" > "$D/p6.cyr"
one p6 "2:34: 'Box' takes 1 type argument, 3 given" "P6: three arguments"
printf 'struct Pair<A, B> { a: A; b: B; }\nfn main(): i64 { var p: Pair<i64, i64, i32>; p.b = 3; return p.b; }\n' > "$D/p7.cyr"
one p7 "2:40: 'Pair' takes 2 type arguments, 3 given" "P7: a two-parameter struct given three"
printf 'struct Pair<A, B> { a: A; b: B; }\n%s\nfn main(): i64 { var b: Box<Box<i64, i64>>; var c: Pair<Box<i64, i64>, i64>; b.n = 3; c.b = 2; return b.n + c.b; }\n' "$BX" > "$D/p8.cyr"
lines p8 2 "'Box' takes 1 type argument, 2 given" "P8: nested lists (Box<Box<..>>, Pair<Box<..>, i64>)"
printf 'struct P<T> { v: T; }\n%s\nfn main(): i64 { var d: Box<i64, Box<i64>>; var e: Box<i64, P<P<i64>>>; d.n = 4; e.n = 5; return d.n + e.n; }\n' "$BX" > "$D/p9.cyr"
lines p9 2 "'Box' takes 1 type argument, 2 given" "P9: a generic extra argument (its >> / >>> close kept)"
printf '%s\nfn main(): i64 { var b = Box<i64, i64> { 1, 5 }; return b.n; }\n' "$BX" > "$D/p10.cyr"
one p10 "2:35: 'Box' takes 1 type argument, 2 given" "P10: a struct literal head"
printf '%s\nstruct W<T> { b: Box<T, i64>; m; }\nfn main(): i64 { var a: W<i32>; var c: W<i64>; var d: W<i16>; a.m = 1; c.m = 2; return a.m + c.m; }\n' "$BX" > "$D/p11.cyr"
one p11 "2:25: 'Box' takes 1 type argument, 2 given" "P11: a generic struct's field, three instances"
printf 'struct A { p: *Later<i64, i64>; n; }\nstruct Later<T> { v: T; n; }\nfn main(): i64 { var a: A; a.n = 3; return a.n; }\n' > "$D/p12.cyr"
one p12 "1:27: 'Later' takes 1 type argument, 2 given" "P12: a late *Later<i64, i64> field"
printf 'include "lib/vec.cyr"\n%s\nfn main(): i64 { var w: Vec<Box<i64, i64>> = 0; return 5; }\n' "$BX" > "$D/p13.cyr"
one p13 "3:38: 'Box' takes 1 type argument, 2 given" "P13: a Vec element"
printf '%s\ntrait T1 { fn a(self, b: Box<i64, i64>): i64; }\nfn main(): i64 { return 5; }\n' "$BX" > "$D/p14.cyr"
one p14 "2:35: 'Box' takes 1 type argument, 2 given" "P14: a trait member's parameter"
printf '%s\nfn f(cb: *fn(Box<i64, i64>): i64): i64 { return 5; }\nfn main(): i64 { return f(0); }\n' "$BX" > "$D/p15.cyr"
one p15 "2:23: 'Box' takes 1 type argument, 2 given" "P15: a *fn( .. ) parameter"

# ── F: every fn-call position ────────────────────────────────────────────────────────────────────────────────
cat > "$D/f1.cyr" <<'EOF'
struct Pt { x; y; }
fn g<T>(a: T): i64 { return sizeof(T); }
fn main(): i64 { return g<i32, Pt>(5); }
syscall(60, main());
EOF
one f1 "3:32: 'g' takes 1 type argument, 2 given" "F1: g<i32, Pt>(5) on fn g<T>"
cat > "$D/f2.cyr" <<'EOF'
struct Pt { x; y; }
struct P { a; }
impl P { fn m<T>(self, v: T): i64 { return sizeof(T); } }
fn main(): i64 { var p: P; p.a = 1; return p.m<i32, Pt>(5); }
EOF
one f2 "4:53: 'P.m' takes 1 type argument, 2 given" "F2: a method p.m<i32, Pt>(5)"
cat > "$D/f3.cyr" <<'EOF'
struct Pt { x; y; z; }
fn mk<T>(x: T): Pt { var p: Pt; p.x = sizeof(T); p.y = 2; p.z = 3; return p; }
fn main(): i64 { var q: Pt = mk<i32, Pt>(5); return q.x; }
EOF
one f3 "3:38: 'mk' takes 1 type argument, 2 given" "F3: a retptr struct receive"
sed 's/struct Pt { x; y; z; }/struct Pt { x; y; }/; s/ p.z = 3;//' "$D/f3.cyr" > "$D/f4.cyr"
one f4 "3:38: 'mk' takes 1 type argument, 2 given" "F4: a register-pair struct receive"
printf 'struct Pt { x; y; }\nfn g<T>(a: T): i64 { return sizeof(T); }\nvar G = g<i32, Pt>(5);\nfn main(): i64 { return G; }\n' > "$D/f5.cyr"
one f5 "3:16: 'g' takes 1 type argument, 2 given" "F5: a global's initializer"
printf 'fn g2<A, B>(a: A, b: B): i64 { return sizeof(B); }\nfn main(): i64 { return g2<i32, i16, i8>(1, 2); }\n' > "$D/f6.cyr"
one f6 "2:38: 'g2' takes 2 type arguments, 3 given" "F6: g2<i32, i16, i8> on fn g2<A, B>"

# ── B: a generic body, two instances ─────────────────────────────────────────────────────────────────────────
printf '%s\nfn g<T>(x: T): i64 { var b: Box<T, i64>; b.n = 2; return b.n; }\nfn main(): i64 { return g(1) + g<i32>(2); }\n' "$BX" > "$D/b1.cyr"
one b1 "2:36: 'Box' takes 1 type argument, 2 given" "B1: a generic body with two instances"

# ── X: --syntax-only ─────────────────────────────────────────────────────────────────────────────────────────
rc=0; "$CC" --syntax-only < "$D/ta.cyr" > /dev/null 2> "$D/x.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^error' "$D/x.err"; then ok "X: --syntax-only says nothing"
else bad "X: --syntax-only rc $rc: $(grep '^error' "$D/x.err" | head -1)"; fi

# ── E: an empty argument keeps its refusal ───────────────────────────────────────────────────────────────────
printf '%s\nfn main(): i64 { var b: Box<i64,>; b.n = 3; return b.n; }\n' "$BX" > "$D/e1.cyr"
one e1 "2:33: a type argument is a type name, got '>'" "E1: Box<i64,>"

# ── C: controls, every leg ───────────────────────────────────────────────────────────────────────────────────
cat > "$D/c.cyr" <<'EOF'
struct Pt { x; y; }
struct Box<T> { v: T; n; }
struct Pair<A, B> { a: A; b: B; }
fn g<T>(x: T): i64 { return sizeof(T); }
fn main(): i64 {
    var b: Box<i64>; b.n = 1;
    var p: Pair<i32, Pt>; p.a = 2;
    var bb: Box<Box<i64>>; bb.n = 3;
    var bp: Box<Box<Pt>>; bp.n = 4;
    return b.n + p.a + bb.n + bp.n + g<i32>(5) + sizeof(Pair<i64, Pt>);
}
syscall(60, main());
EOF
A64=""; CXCC=""; WINE=0
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null && [ -s "$D/cc_a64" ]; then
        chmod +x "$D/cc_a64"; A64="$D/cc_a64"
    else bad "aarch64: src/main_aarch64.cyr did not build"; fi
else echo "  SKIP: aarch64 legs (qemu-aarch64 not installed)"; skips=$((skips + 1)); fi
if "$CC" < src/main_cx.cyr > "$D/cc_cx" 2> /dev/null && [ -s "$D/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$D/cxvm" 2> /dev/null && [ -s "$D/cxvm" ]; then
    chmod +x "$D/cc_cx" "$D/cxvm"; CXCC="$D/cc_cx"
else bad "cx: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
if command -v wine > /dev/null 2>&1; then WINE=1
else echo "  SKIP: PE legs (wine not installed)"; skips=$((skips + 1)); fi
crun() {   # <leg>: build c.cyr for <leg> and run it; RC = its exit (-1 = no build)
    RC=-1
    case "$1" in
        x86) "$CC" < "$D/c.cyr" > "$D/c_$1" 2> /dev/null || return 0 ;;
        a64) "$A64" < "$D/c.cyr" > "$D/c_$1" 2> /dev/null || return 0 ;;
        cx)  "$CXCC" < "$D/c.cyr" > "$D/c_$1" 2> /dev/null || return 0 ;;
        pe)  CYRIUS_TARGET_WIN=1 "$CC" < "$D/c.cyr" > "$D/c_$1.exe" 2> /dev/null || return 0 ;;
    esac
    RC=0
    case "$1" in
        x86) chmod +x "$D/c_$1"; timeout 60 "$D/c_$1" > /dev/null 2>&1 || RC=$? ;;
        a64) chmod +x "$D/c_$1"; timeout 300 qemu-aarch64 "$D/c_$1" > /dev/null 2>&1 || RC=$? ;;
        cx)  timeout 300 "$D/cxvm" < "$D/c_$1" > /dev/null 2>&1 || RC=$? ;;
        pe)  (cd "$D" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine "$D/c_$1.exe" > /dev/null 2>&1) || RC=$? ;;
    esac
}
LEGS="x86"
[ -n "$A64" ] && LEGS="$LEGS a64"
[ -n "$CXCC" ] && LEGS="$LEGS cx"
[ "$WINE" = 1 ] && LEGS="$LEGS pe"
for L in $LEGS; do
    crun "$L"
    if [ "$RC" -eq 38 ]; then ok "C [$L]: the controls exit 38"; else bad "C [$L]: exit $RC, want 38"; fi
done

# ── A: the refusal from every cross compiler ─────────────────────────────────────────────────────────────────
if [ -n "$A64" ]; then
    one ta "2:34: 'Box' takes 1 type argument, 2 given" "A [a64]: R1" "$A64"
    one f1 "3:32: 'g' takes 1 type argument, 2 given" "A [a64]: F1" "$A64"
fi
if [ -n "$CXCC" ]; then
    one ta "2:34: 'Box' takes 1 type argument, 2 given" "A [cx]: R1" "$CXCC"
    one f1 "3:32: 'g' takes 1 type argument, 2 given" "A [cx]: F1" "$CXCC"
fi
one ta "2:34: 'Box' takes 1 type argument, 2 given" "A [pe]: R1" "CYRIUS_TARGET_WIN=1 $CC"
one f1 "3:32: 'g' takes 1 type argument, 2 given" "A [pe]: F1" "CYRIUS_TARGET_WIN=1 $CC"

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
echo "PASS: $G — a type-argument list longer than its generic declares is refused once, at the first extra argument (the user's D5): the filed repros (R), every struct position (P) and fn-call position (F), a generic body once (B), silent under --syntax-only (X), an empty argument as before (E), the controls on x86_64 / aarch64 / cx / PE (C) and the refusal from every cross compiler (A)"
exit 0

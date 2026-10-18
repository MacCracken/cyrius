#!/bin/sh
# tests/gates/frontend/generic_nested_shift_close.sh — 6.7.15
#
# A NESTED TYPE ARGUMENT CLOSED BY `>>` / `>>>` AND FOLLOWED BY `,`. The lexer folds the closes of a nested
# argument into one `>>` (or `>>>`) token, which closes the inner list AND the one around it; the reader
# owes the enclosing list that close (`_ta_pending_gt`). `_parse_one_type_arg` tested for a second argument
# (`,`) BEFORE paying it, so the `,` of the ENCLOSING list was read as the inner list's: `g2<P<P<R>>, i16>`
# read `i16` as P's second argument and bound g2's B to i64 (the filed repro exited 8, 2 is right; no
# diagnostic), `Two<P<P<R>>, i16>` was 24 bytes, not 18, and `fn f(a: Box<Box<Pt>>, b: i64)` was refused
# "unknown type 'b' as a type argument". Two halves, both needed: (1) every type-argument list reads `, arg`
# only while no close is owed (`_ta_comma`: the nested arm and the nine list readers); (2) minting the
# inner instance re-parses its struct, whose own reads reset the owed close — `_instantiate_generic_struct`
# puts it back, so the fix does not depend on whether the instance already existed. 6.3.33 - 6.7.14, every
# target. Filed: docs/development/issues/2026-10-16-nested-type-arg-shift-close-then-comma-drops-next-arg.md
#
#   A  the filed repro, verbatim: exit 2 (8 before); its `>>>` form (`P<P<P<R>>>`): 2 (8 before)
#   S  `sizeof(Two<P<P<R>>, i16>)` at top level: 18 (24 before); in a fn after a local of it: 18 (24); the
#      layout (`t.b = 65539` keeps 3 in an i16; `t.a.v.v.w` its own field): 109 (9 before)
#   V  `g2<P<Vec<i64>>, i16>`: 2 (8 before)
#   D  a doubly nested parameter that is not the last: `a: Box<Box<Pt>>, b`, `a: *Box<P<R>>, b` and
#      `w: Vec<Box<Box<Pt>>>, b` compile and return b (refused before: "unknown type 'b'")
#   O  the instance found, not minted: `P<R>` declared first, then the repro's call twice: 4 (16 before)
#   M  a generic method `o.m<P<P<R>>, i16>(0)`: 2 (8 before); the struct-valued receive
#      `var t: Two<P<P<R>>, i16> = mk<P<P<R>>, i16>(3)`: 21 (refused before: "unknown type 'B'")
#   C  controls, unchanged: the closes spaced (`P<P<R> >, i16`) 2, the nested argument last 216
#   T  tests/tcyr/lang/generic_nested_shift_close.tcyr: "N passed, 0 failed (N total)", N derived from the file
#      (one row per `assert_eq(`); the release gate's cross-OS leg runs it on ecb / ach / cass / pi
#   Every row on x86_64, x86_64 CYRIUS_IR=3, aarch64 (qemu), cx (cxvm) and PE (wine).
#
# MUTATION LEDGER (2026-10-18; a scratch copy of the tree with the one change, this gate run with
# CYCC=<the mutant built from it>):
#   M1  half 1 removed (`_ta_comma` reads a `,`     -> RED A, S, V, D, O and M on every leg (the before
#       whether or not a close is owed)               values); T: the file does not build on any leg; C green
#   M2  half 2 removed (`_instantiate_generic_struct` -> RED S1 (24), S3 (9), D1 / D2 (refused), M1 (8) and M2
#       no longer puts `_ta_pending_gt` back)          (refused: "fn return struct-id differs") on every leg;
#                                                     T: the file does not build; A, S2, V, D3, O and C green
#                                                     (an earlier read found the inner instance already
#                                                     minted — the explicit call's lookahead mints it first)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=generic_nested_shift_close
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix under $D (never ~/.wine), torn down with its server dir on exit — the
# defer_every_return_path.sh helper.
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

TC=tests/tcyr/lang/generic_nested_shift_close.tcyr
[ -f "$TC" ] || { echo "FAIL: $G: $TC is missing"; exit 1; }
# One row per `assert_eq(` call (the file defines none). The floor keeps a gutted file from passing.
N=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TC")
FLOOR=16
if [ "$N" -lt "$FLOOR" ]; then echo "FAIL: $G: only $N rows in $TC (floor $FLOOR) — rows were lost"; exit 1; fi

# The legs this box can run: aarch64 under qemu, cx under the tree's own cxvm, PE under wine.
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

# run_leg <leg> <src> <out-binary>: compile <src> for <leg>, run it; sets RC (exit, -1 = no build)
# and LAST (the last line of its output, CR stripped).
run_leg() {
    RC=-1; LAST=''
    case "$1" in
        x86)   "$CC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        x86:*) env "${1#x86:}" "$CC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        a64)   "$A64" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        cx)    "$CXCC" < "$2" > "$3" 2> "$3.err" || return 0 ;;
        pe)    CYRIUS_TARGET_WIN=1 "$CC" < "$2" > "$3.exe" 2> "$3.err" || return 0 ;;
    esac
    RC=0
    case "$1" in
        x86|x86:*) chmod +x "$3"; timeout 60 "$3" > "$3.out" 2>&1 || RC=$? ;;
        a64)  chmod +x "$3"; timeout 300 qemu-aarch64 "$3" > "$3.out" 2>&1 || RC=$? ;;
        cx)   timeout 300 "$D/cxvm" < "$3" > "$3.out" 2>&1 || RC=$? ;;
        pe)   (cd "$D" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine "$3.exe" > "$3.out" 2> /dev/null) || RC=$? ;;
    esac
    LAST=$(tail -1 "$3.out" | tr -d '\r')
}
OTHER=""
[ -n "$A64" ] && OTHER="$OTHER a64"
[ -n "$CXCC" ] && OTHER="$OTHER cx"
[ "$WINE" = 1 ] && OTHER="$OTHER pe"

# The filed repro, verbatim, and its `>>>` form.
cat > "$D/a1.cyr" <<'EOF'
struct P<T> { v: T; }
struct R<T> { v: T; w; }
fn g2<A, B>(a: *A, b: *B): i64 { return sizeof(A) * 100 + sizeof(B); }
var x = g2<P<P<R>>, i16>(0, 0);
syscall(60, x - 1600);
EOF
sed 's/g2<P<P<R>>, i16>/g2<P<P<P<R>>>, i16>/' "$D/a1.cyr" > "$D/a2.cyr"
cat > "$D/s1.cyr" <<'EOF'
struct P<T> { v: T; }
struct R<T> { v: T; w; }
struct Two<A, B> { a: A; b: B; }
syscall(60, sizeof(Two<P<P<R>>, i16>));
EOF
cat > "$D/s2.cyr" <<'EOF'
struct P<T> { v: T; }
struct R<T> { v: T; w; }
struct Two<A, B> { a: A; b: B; }
fn f(): i64 { var t: Two<P<P<R>>, i16>; return sizeof(Two<P<P<R>>, i16>); }
syscall(60, f());
EOF
cat > "$D/s3.cyr" <<'EOF'
struct P<T> { v: T; }
struct R<T> { v: T; w; }
struct Two<A, B> { a: A; b: B; }
fn f(): i64 { var t: Two<P<P<R>>, i16>; t.b = 65539; t.a.v.v.w = 9; var r = t.a.v.v.w; if (t.b == 3) { r = r + 100; } return r; }
syscall(60, f());
EOF
cat > "$D/v.cyr" <<'EOF'
include "lib/vec.cyr"
struct P<T> { v: T; }
fn g2<A, B>(a: *A, b: *B): i64 { return sizeof(A) * 100 + sizeof(B); }
var x = g2<P<Vec<i64>>, i16>(0, 0);
syscall(60, x - 800);
EOF
cat > "$D/d1.cyr" <<'EOF'
struct Pt { x; y; }
struct Box<T> { v: T; }
fn f(a: Box<Box<Pt>>, b: i64): i64 { return a.v.v.y + b; }
fn m(): i64 { var x: Box<Box<Pt>>; x.v.v.y = 40; return f(x, 5); }
syscall(60, m());
EOF
cat > "$D/d2.cyr" <<'EOF'
struct P<T> { v: T; }
struct R<T> { v: T; w; }
struct Box<T> { v: T; }
fn f(a: *Box<P<R>>, b: i64): i64 { return b; }
syscall(60, f(0, 5));
EOF
cat > "$D/d3.cyr" <<'EOF'
struct Pt { x; }
struct Box<T> { v: T; }
fn f(w: Vec<Box<Box<Pt>>>, b: i64): i64 { return b; }
syscall(60, f(0, 5));
EOF
cat > "$D/o.cyr" <<'EOF'
struct P<T> { v: T; }
struct R<T> { v: T; w; }
fn g2<A, B>(a: *A, b: *B): i64 { return sizeof(A) * 100 + sizeof(B); }
var y = sizeof(P<R>);
var x = g2<P<P<R>>, i16>(0, 0);
var z = g2<P<P<R>>, i16>(0, 0);
syscall(60, x + z - 3200);
EOF
cat > "$D/m1.cyr" <<'EOF'
struct P<T> { v: T; }
struct R<T> { v: T; w; }
struct O { a; }
impl O { fn m<A, B>(self, x): i64 { return sizeof(A) * 100 + sizeof(B); } }
fn main(): i64 { var o = O { 1 }; return o.m<P<P<R>>, i16>(0) - 1600; }
syscall(60, main());
EOF
cat > "$D/m2.cyr" <<'EOF'
struct P<T> { v: T; }
struct R<T> { v: T; w; }
struct Two<A, B> { a: A; b: B; }
fn mk<A, B>(x): Two<A, B> { var t: Two<A, B>; t.b = x; return t; }
fn main(): i64 { var t: Two<P<P<R>>, i16> = mk<P<P<R>>, i16>(3); return sizeof(Two<P<P<R>>, i16>) + t.b; }
syscall(60, main());
EOF
sed 's/g2<P<P<R>>, i16>/g2<P<P<R> >, i16>/' "$D/a1.cyr" > "$D/c1.cyr"
cat > "$D/c2.cyr" <<'EOF'
struct P<T> { v: T; }
struct R<T> { v: T; w; }
fn g2<A, B>(a: *A, b: *B): i64 { return sizeof(A) * 100 + sizeof(B); }
var x = g2<i16, P<P<R>>>(0, 0);
syscall(60, x);
EOF

# xrow <id> <src> <want> <what>: the exit on every leg
xrow() {
    for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
        n=$(printf '%s_%s' "$1" "$leg" | tr -c 'a-zA-Z0-9' '_')
        run_leg "$leg" "$2" "$D/x_$n"
        if [ "$RC" -eq -1 ]; then bad "$1 $leg: did not build: $(grep -m1 'error' "$D/x_$n.err")"
        elif [ "$RC" -eq "$3" ]; then ok "$1 $leg: exit $3"
        else bad "$1 $leg: exit $RC, want $3 ($4)"; fi
    done
}
echo "A. the filed repro, verbatim: g2<P<P<R>>, i16> binds B to i16"
xrow A1 "$D/a1.cyr" 2 "8: i16 was read as P's second argument, B bound to i64"
xrow A2 "$D/a2.cyr" 2 "8: the \`>>>\` form"
echo "S. Two<P<P<R>>, i16> is 18 bytes, its b an i16"
xrow S1 "$D/s1.cyr" 18 "24: at top level, B bound to i64"
xrow S2 "$D/s2.cyr" 18 "24: in a fn"
xrow S3 "$D/s3.cyr" 109 "9: b was an i64"
echo "V. a Vec's \`>>\`: g2<P<Vec<i64>>, i16>"
xrow V "$D/v.cyr" 2 "8: B bound to i64"
echo "D. a doubly nested parameter that is not the last"
xrow D1 "$D/d1.cyr" 45 "refused: 'b' read as a type argument"
xrow D2 "$D/d2.cyr" 5 "refused: 'b' read as a type argument"
xrow D3 "$D/d3.cyr" 5 "refused: 'b' read as a type argument"
echo "O. the inner instance found, not minted: P<R> first, the call twice"
xrow O "$D/o.cyr" 4 "16: B bound to i64 twice"
echo "M. a generic method's list and the struct-valued receive's"
xrow M1 "$D/m1.cyr" 2 "8: B bound to i64"
xrow M2 "$D/m2.cyr" 21 "refused: mk's B unbound"
echo "C. controls, unchanged"
xrow C1 "$D/c1.cyr" 2 "the closes spaced apart"
xrow C2 "$D/c2.cyr" 216 "the nested argument last"

echo "T. $TC ($N rows)"
for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TC" "$D/t_$n"
    if [ "$RC" -eq -1 ]; then bad "T $leg: the values file did not build: $(grep -m1 'error' "$D/t_$n.err")"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N passed, 0 failed ($N total)" ]; then ok "T $leg: $LAST"
    else bad "T $leg: exit $RC, '$LAST' (want '$N passed, 0 failed ($N total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a nested type argument closed by \`>>\` / \`>>>\` and followed by \`,\` leaves the \`,\` to the enclosing list: the filed repro and its \`>>>\` form (A), Two's size and layout (S), a Vec (V), the parameters (D), the found instance (O), a method and a receive (M), the controls (C) and $N rows (T) on x86_64 / IR / aarch64 / cx / PE"

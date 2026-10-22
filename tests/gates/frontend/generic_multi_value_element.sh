#!/bin/sh
# tests/gates/frontend/generic_multi_value_element.sh — 6.7.16
#
# A GENERIC'S MULTI-VALUE ELEMENT TYPED BY ITS TYPE PARAMETER IS THE INSTANCE'S BINDING, as a single `: T` return is
# (`_gtype_tp_ret`). `fn mm2<V>(x: V): (V, i64)` recorded its V element as i64 at every instance — the element was read
# where V is unbound — so at V = f64 `var a, b = mm2<f64>(h);` bound `a` as an integer word holding the double's bits:
# `f64_to(a * 2.0) + b` warned "integer arithmetic with an f64 right operand" and exited 7 (10 is right), on x86_64,
# CYRIUS_IR=3, aarch64, cx and PE alike; `var t: (f64, i64) = mm2<f64>(h);` was refused "it returns 2 values, (i64,
# i64)". `_mret_elem` now reads a type-parameter element under the instance's binding (f64 -9, a struct; a narrower
# integer stays an i64 slot), and the destructure's callee lookahead (`_dt_call_fn`) resolves a generic method's
# inferred `p.mm(h)` to the instance its arguments bind (`_mcall_gen`, quiet), as the explicit `p.mm<f64>(h)` and the
# free spellings already reached theirs.
# Filed: docs/development/issues/2026-10-18-generic-multi-value-type-parameter-element-binds-i64.md
#
#   V1 the filed repro, verbatim: exit 10 and no warning (7 and the warning before) on x86_64, CYRIUS_IR=3, aarch64
#      (qemu), cx (cxvm) and PE (wine)
#   T  tests/tcyr/crossos/multi_return.tcyr (its mv_* rows: the free, inferred, method, capture, assignment, wrap, for
#      step, closure, arity-3, two-parameter, forwarder and i32 / i64 spellings) on x86_64 (plain, IR=1, IR=3, DCE=1),
#      aarch64, cx and PE
#   V2 the instance's signature is the one the checks read (x86_64 and each cross compiler): V2a `var t: (i64, i64) =
#      mm2<f64>(h);` refused, "it returns 2 values, (f64, i64)" (it compiled, the double's bits as an integer); V2b
#      `mm2<Pt>(p)` into `(i64, i64)` refused naming `(Pt, i64)`, as V2c, the non-generic `(Pt, i64)` fn, is
#   V3 a tuple LOCAL in a generic was refused at its type ("a tuple type in a generic fn is refused"), and its `return
#      t;` is judged no further — exactly the type's own errors, nothing from an instance whose `(V, i64)` is now
#      `(f64, i64)` (V3a-V3d; each had a second error, "cannot return tuple 't' (i64, i64) from 'mt$f64'"), nor from
#      the base's own `(f64, i64)` (V3e: that cascade predates 6.7.16)
#   V4 a top-level destructure after the first statement (and a multi-value assignment, a tuple capture) binds the
#      f64 element on every leg
#   (6.7.16, the user's D90: a struct value over 8 B is no `return ( .. )` element, mret_struct_element_refused.sh —
#   V2b's and V5f's instance body `return (x, 7)` at a struct V is that refusal too, a second line; the (Pt, i64) /
#   (Box<Pt>, i64) controls `mm3` / `mb` return a field, a word, so their rows keep one line.)
#   V5 the multi-value refusals name the fn and its values as the source spells them: an instance `mt<f64>`,
#      `P.gm<f64>`, `mt2<i64, f64>` (V5a / V5c / V5d: the refusal an instance can now meet printed `mt$f64`), a method
#      `Q.pair` (V5b: `Q_pair`), a struct instance element `(Box<Pt>, i64)` (V5e / V5f: `(Box$Pt, i64)`); V5K the same
#      body at i64 compiles
#   V6 (6.7.16, the user's D98, 2026-10-20; issues/2026-10-20-zone-destructure-leaves-f64-element-untyped.md) the
#      declaration zone types a destructure's f64 element and an untyped global from an f64 call, as a fn and the line
#      after the first statement do: V6 the filed repro verbatim (10, no warning; 7 and "integer arithmetic with an f64
#      right operand" before), V6b its after-the-first-statement twin (10, unchanged), V6c `var Y = mkf(1.5);` /
#      `mkf(1.5) * 2.0` in the zone read by a later global and a fn body compiled before the replay, V6d the same after
#      the first statement (untyped there too before), V6e a generic's `(V, i64)`, a generic method's, an f64 method,
#      and an f64 comparison that stays an integer, V6k a `kernel;` build (its replay runs after the program: the types
#      are read at the end of pass 1); the tcyr's MZ rows (T) on every leg
#
# MUTATION LEDGER (2026-10-20; each mutant a scratch copy of the tree with the one change, its 2-stage cycc, this gate
# run from the copy with CYCC= that cycc, so the aarch64 / cx / PE compilers are built from the mutant too):
#   M1 the tree before (f7470fcf1)                       -> RED 30: V1 x5 (7, warned), T x7 (the mv_* rows: the tcyr did
#                                                           not build — its captures refused), V2a / V2b x4 (each
#                                                           compiled), V3e x4 + its cascade line, V4 x5
#   M2 `_mret_elem` without the type-parameter read      -> RED 25: V1 x5, T x7, V2a / V2b x4, V4 x5
#   M3 `_dt_call_fn` without its `_mcall_gen` arm        -> RED 12: T x7 (mv_mi / mv_capm / mv_masg: the inferred
#                                                           p.mm(h) typed from the base), V4 x5 (GP.mm(4.5))
#   M4 `_ret_tuple_var` judging a generic's tuple local  -> RED 25: V3a-V3e x4 + each cascade line ("cannot return
#                                                           tuple 't' (i64, i64) from 'mt$f64'")
#   M5 `_ret_tup_err` naming the fn table's entry        -> RED 16: V5a-V5d x4 (`mt$f64`, `Q_pair`, `P_gm$f64`,
#                                                           `mt2$i64$f64`)
#   M6 `_mret_spell` naming a struct by its table entry   -> RED 8: V5e / V5f x4 (`(Box$Pt, i64)`)
# D98 (2026-10-21; each mutant a scratch copy of the tree with the one change, its compiler built from it, the gate run
# from the copy):
#   M7 the tree before (1cfdeb9d1)                       -> RED 28: T x7 (the MZ rows), V6 / V6c / V6d / V6e x5, V6k
#   M8 `_gzf_pass` reading nothing                       -> RED 23: T x7, V6 / V6c / V6e x5, V6k
#   M9 `_gzf_late` keeping the line untyped              -> RED 5: V6d x5
#   M10 `_gzf_lead` answering 1 (a comparison typed f64) -> RED 12: T x7 (MZN), V6e x5 (N)
#   M11 `_gzf_elem` answering 0                          -> RED 18: T x7, V6 / V6e x5, V6k
#   M12 `_gzf_dt_reg` noting nothing                     -> RED 18: the same
#   M13 `_gzf_bind` answering 0 (no generic binding)     -> RED 12: T x7, V6e x5
#   M14 `_gzf_mret` answering 0 (no method's f64)        -> RED 12: T x7, V6e x5
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
case $CC in /*) ;; *) CC="$ROOT/$CC" ;; esac
G=generic_multi_value_element
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix under $D (never ~/.wine), torn down with its server dir on exit.
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

fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

TC=tests/tcyr/crossos/multi_return.tcyr
[ -f "$TC" ] || { echo "FAIL: $G: $TC is missing"; exit 1; }
N=$(grep -cE '^[[:space:]]*assert(_[a-z]+)?\(' "$TC")
FLOOR=82   # 6.7.16: + the mv_* rows, + the MZ rows (D98)
if [ "$N" -lt "$FLOOR" ]; then echo "FAIL: $G: only $N rows in $TC (floor $FLOOR) — rows were lost"; exit 1; fi
MV=$(grep -c 'assert_eq(mv_' "$TC")
[ "$MV" -ge 17 ] || bad "only $MV mv_* rows in $TC (floor 17)"

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

# run_leg <leg> <src> <out-binary>: compile <src> for <leg>, run it; sets RC (exit, -1 = no build) and LAST (the last
# line of its output, CR stripped).
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

# xr <id> <src> <want> <what>: the exit on every leg, with no warning
xr() {
    for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
        n=$(printf '%s_%s' "$1" "$leg" | tr -c 'a-zA-Z0-9' '_')
        run_leg "$leg" "$2" "$D/x_$n"
        if [ "$RC" -eq -1 ]; then bad "$1 $leg: $4 did not build: $(grep -m1 'error' "$D/x_$n.err")"
        elif grep -q '^warning' "$D/x_$n.err"; then bad "$1 $leg: $4 warned: $(grep -m1 '^warning' "$D/x_$n.err")"
        elif [ "$RC" -eq "$3" ]; then ok "$1 $leg: $4 exits $3"
        else bad "$1 $leg: $4 exits $RC, want $3"; fi
    done
}
# rf <id> <src> <nerr> <fragment> <what>: refused on x86_64 and by each cross compiler with exactly <nerr> `^error`
# lines, the last holding <fragment> (empty: none checked), and no binary
rf() {
    for leg in x86 $OTHER; do
        n=$(printf '%s_%s' "$1" "$leg" | tr -c 'a-zA-Z0-9' '_')
        o="$D/r_$n"
        crc=0
        case "$leg" in
            x86) "$CC" < "$2" > "$o" 2> "$o.err" || crc=$? ;;
            a64) "$A64" < "$2" > "$o" 2> "$o.err" || crc=$? ;;
            cx)  "$CXCC" < "$2" > "$o" 2> "$o.err" || crc=$? ;;
            pe)  CYRIUS_TARGET_WIN=1 "$CC" < "$2" > "$o" 2> "$o.err" || crc=$? ;;
        esac
        ne=$(grep -c '^error' "$o.err")
        if [ "$crc" -eq 0 ]; then bad "$1 $leg: $5 BUILT (rc 0)"
        elif [ "$ne" -ne "$3" ]; then bad "$1 $leg: $5: $ne error lines, want $3: $(grep '^error' "$o.err" | tr '\n' ' ')"
        elif [ -n "$4" ] && ! grep '^error' "$o.err" | tail -1 | grep -qF "$4"; then bad "$1 $leg: $5: not as expected: $(grep '^error' "$o.err" | tail -1)"
        elif [ -s "$o" ]; then bad "$1 $leg: $5: refused, but a binary was written"
        else ok "$1 $leg: $5: refused ($3 error line(s))"; fi
    done
}

echo "V1. the filed repro, verbatim: var a, b = mm2<f64>(h); binds a as f64 (exit 10, no warning; 7 and the warning before)"
cat > "$D/v1.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn mm2<V>(x: V): (V, i64) { return (x, 7); }
fn main(): i64 {
    var h: f64 = 1.5;
    var a, b = mm2<f64>(h);
    return f64_to(a * 2.0) + b;
}
syscall(60, main());
EOF
xr V1 "$D/v1.cyr" 10 "the filed repro"

echo "T. $TC ($N rows, $MV of them mv_*)"
for leg in x86 x86:CYRIUS_IR=1 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1 $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TC" "$D/t_$n"
    if [ "$RC" -eq -1 ]; then bad "T $leg: the values file did not build: $(grep -m1 'error' "$D/t_$n.err")"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N passed, 0 failed ($N total)" ]; then ok "T $leg: $LAST"
    else bad "T $leg: exit $RC, '$LAST' (want '$N passed, 0 failed ($N total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
done

echo "V2. the checks read the instance's signature"
H='include "lib/syscalls.cyr"
struct Pt { x; y; }
fn mm2<V>(x: V): (V, i64) { return (x, 7); }
fn mm3(p: Pt): (Pt, i64) { return (p.x, 7); }'
printf '%s\nfn main(): i64 { var h: f64 = 1.5; var t: (i64, i64) = mm2<f64>(h); return t.1; }\nsyscall(60, main());\n' "$H" > "$D/v2a.cyr"
rf V2a "$D/v2a.cyr" 1 "cannot capture 'mm2' into tuple (i64, i64) - it returns 2 values, (f64, i64)" "var t: (i64, i64) = mm2<f64>(h); (it compiled: the double's bits as t.0)"
printf '%s\nfn main(): i64 { var p: Pt = Pt { 3, 4 }; var t: (i64, i64) = mm2<Pt>(p); return t.1; }\nsyscall(60, main());\n' "$H" > "$D/v2b.cyr"
rf V2b "$D/v2b.cyr" 2 "cannot capture 'mm2' into tuple (i64, i64) - it returns 2 values, (Pt, i64)" "var t: (i64, i64) = mm2<Pt>(p); (it compiled: the struct's first word) — and the instance's return (x, 7), D90's line"
printf '%s\nfn main(): i64 { var p: Pt = Pt { 3, 4 }; var t: (i64, i64) = mm3(p); return t.1; }\nsyscall(60, main());\n' "$H" > "$D/v2c.cyr"
rf V2c "$D/v2c.cyr" 1 "cannot capture 'mm3' into tuple (i64, i64) - it returns 2 values, (Pt, i64)" "the non-generic (Pt, i64) control (unchanged)"

echo "V3. a generic's tuple local is refused at its type, once: no second error from its return"
vrow() {   # <id> <generic> <call> <nerr> <what>
    printf 'include "lib/syscalls.cyr"\n%s\nfn main(): i64 { var a, b = %s; return b; }\nsyscall(60, main());\n' "$2" "$3" > "$D/$1.cyr"
    rf "$1" "$D/$1.cyr" "$4" "" "$5"
    if grep -q 'cannot return tuple' "$D/r_$1_x86.err" 2> /dev/null; then bad "$1: the return's cascade printed: $(grep 'cannot return tuple' "$D/r_$1_x86.err")"; fi
}
vrow V3a 'fn mt<V>(x: V): (V, i64) { var t: (i64, i64) = (1, 7); return t; }' 'mt<f64>(1.5)' 1 "var t: (i64, i64) returned from mt<f64>: the type's one error"
vrow V3b 'fn mt<V>(x: V): (V, i64) { var t: (V, i64) = (x, 7); return t; }' 'mt<f64>(1.5)' 2 "var t: (V, i64) returned from mt<f64>: the type's two errors"
vrow V3c 'fn mt<V>(x: V): (V, i64) { var t = (x, 7); return t; }' 'mt<f64>(1.5)' 2 "an untyped var t = (x, 7) returned from mt<f64>: the literal's two errors"
vrow V3d 'fn mt<V>(x: V, t: (i64, i64)): (V, i64) { return t; }' 'mt<f64>(1.5, (1, 2))' 1 "a t: (i64, i64) parameter returned from mt<f64>"
vrow V3e 'fn mt<V>(x: V): (f64, i64) { var t: (i64, i64) = (1, 7); return t; }' 'mt<i64>(1)' 1 "the base's own (f64, i64) (a cascade before 6.7.16 too)"

echo "V5. the refusals name the fn and the element types as the source spells them"
H5='include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
struct P { k; }
var G: (i64, i64) = (1, 2);
var GF: (f64, i64) = (1.5, 2);
fn mt<V>(x: V): (V, i64) { return G; }
fn mt2<A, B>(a: A, b: B): (B, A) { return G; }
fn mm2<V>(x: V): (V, i64) { return (x, 7); }
fn mb(b: Box<Pt>): (Box<Pt>, i64) { return (b.n, 1); }
impl P {
    fn gm<V>(self, x: V): (V, i64) { return G; }
}'
nrow() {   # <id> <main body> <fragment> <what> [<declarations>] [<error lines>, default 1]
    printf '%s\n%s\nfn main(): i64 { %s return 0; }\nsyscall(60, main());\n' "$H5" "${5:-}" "$2" > "$D/$1.cyr"
    rf "$1" "$D/$1.cyr" "${6:-1}" "$3" "$4"
}
nrow V5a 'var a, b = mt<f64>(1.5);' "cannot return tuple 'G' (i64, i64) from 'mt<f64>' - it returns (f64, i64)" "return G; from the f64 instance (named 'mt\$f64')"
nrow V5b 'var q: Q = Q { 1 }; var a, b = q.pair(1);' "cannot return tuple 'GF' (f64, i64) from 'Q.pair' - it returns (i64, i64)" "a method's (named 'Q_pair')" 'struct Q { k; }
impl Q {
    fn pair(self, a): (i64, i64) { return GF; }
}'
nrow V5c 'var p: P = P { 1 }; var a, b = p.gm(2.5);' "cannot return tuple 'G' (i64, i64) from 'P.gm<f64>' - it returns (f64, i64)" "a generic method's f64 instance (named 'P_gm\$f64')"
nrow V5d 'var a, b = mt2<i64, f64>(1, 1.5);' "cannot return tuple 'G' (i64, i64) from 'mt2<i64, f64>' - it returns (f64, i64)" "two type parameters (named 'mt2\$i64\$f64')"
nrow V5e 'var b: Box<Pt>; var t: (i64, i64) = mb(b);' "cannot capture 'mb' into tuple (i64, i64) - it returns 2 values, (Box<Pt>, i64)" "a (Box<Pt>, i64) fn's values (spelled '(Box\$Pt, i64)')"
nrow V5f 'var b: Box<Pt>; var t: (i64, i64) = mm2<Box<Pt>>(b);' "cannot capture 'mm2' into tuple (i64, i64) - it returns 2 values, (Box<Pt>, i64)" "mm2<Box<Pt>>'s values — and the instance's return (x, 7), D90's line" '' 2
printf '%s\nfn main(): i64 { var a, b = mt<i64>(1); var c, d = mt(5); return b * 10 + d; }\nsyscall(60, main());\n' "$H5" > "$D/v5k.cyr"
xr V5K "$D/v5k.cyr" 22 "the same return G; at i64 (the base) compiles"

echo "V4. top level after the first statement: the f64 element binds"
cat > "$D/v4.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct P { k; }
fn mm2<V>(x: V): (V, i64) { return (x, 7); }
impl P {
    fn mm<V>(self, x: V): (V, i64) { return (x, self.k); }
}
var GP: P = P { 7 };
var GT: (f64, i64) = mm2<f64>(3.5);
var r = 0;
if (f64_to(GT.0 * 2.0) + GT.1 != 14) { r = r | 1; }
var TA, TB = mm2(1.5);
if (f64_to(TA * 2.0) + TB != 10) { r = r | 2; }
var TC, TD = GP.mm(4.5);
if (f64_to(TC * 2.0) + TD != 16) { r = r | 4; }
var TE: f64 = 0.0;
var TF = 0;
TE, TF = mm2(0.5);
if (f64_to(TE * 2.0) + TF != 8) { r = r | 8; }
GT = GP.mm(2.5);
if (f64_to(GT.0 * 2.0) + GT.1 != 12) { r = r | 16; }
syscall(SYS_EXIT, r);
EOF
xr V4 "$D/v4.cyr" 0 "a zone capture, a destructure, a method destructure, a multi-value assignment and a capture at top level"

echo "V6. (6.7.16, D98) the declaration zone types a destructure's f64 element and an f64 call's global, as a fn does"
cat > "$D/v6.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn mm3(x: f64): (f64, i64) { return (x, 7); }
var ZA, ZB = mm3(1.5);
var r = f64_to(ZA * 2.0) + ZB;
syscall(60, r);
EOF
xr V6 "$D/v6.cyr" 10 "the filed repro, verbatim: ZA an f64 in the zone (7 and a warning before)"
cat > "$D/v6b.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn mm3(x: f64): (f64, i64) { return (x, 7); }
var q = 1;
q = 2;
var ZA, ZB = mm3(1.5);
var r = f64_to(ZA * 2.0) + ZB;
syscall(60, r);
EOF
xr V6b "$D/v6b.cyr" 10 "the same line after the first statement (unchanged)"
cat > "$D/v6c.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn mkf(x: f64): f64 { return x; }
var Y = mkf(1.5);
var W = mkf(1.5) * 2.0;
fn rd(): i64 { return f64_to(Y * 2.0) * 10 + f64_to(W); }
var r = f64_to(Y * 2.0) * 100 + rd();
syscall(60, r % 256);
EOF
xr V6c "$D/v6c.cyr" 77 "var Y = mkf(1.5); / mkf(1.5) * 2.0 in the zone, read by a later global and a fn body: f64s (333; 0 before)"
cat > "$D/v6d.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn mkf(x: f64): f64 { return x; }
var q = 1;
q = 2;
var Y = mkf(1.5);
var W = mkf(1.5) * 2.0;
var r = f64_to(Y * 2.0) * 10 + f64_to(W);
syscall(60, r);
EOF
xr V6d "$D/v6d.cyr" 33 "the same after the first statement: f64s, as in a fn (0 and a warning before)"
cat > "$D/v6e.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn mkf(x: f64): f64 { return x; }
fn mm2<V>(x: V): (V, i64) { return (x, 7); }
struct P { k; }
impl P {
    fn mm<V>(self, x: V): (V, i64) { return (x, self.k); }
    fn mf(self, x: f64): f64 { return x; }
}
var GP = P { 7 };
var A, B = mm2<f64>(1.5);
var C, D = GP.mm(1.5);
var E = GP.mf(1.5);
var N = mkf(1.5) > 1.0;
var r = (f64_to(A * 2.0) + B) * 10 + f64_to(C * 2.0) + D + f64_to(E * 2.0) + N * 3;
syscall(60, r);
EOF
xr V6e "$D/v6e.cyr" 116 "zone generic, method and f64-method shapes (an f64 comparison stays an integer: N * 3)"
printf 'kernel;\n' > "$D/v6k.cyr"
cat "$D/v6.cyr" >> "$D/v6k.cyr"
krc=0
CYRIUS_ELF64_KERNEL=1 "$CC" < "$D/v6k.cyr" > "$D/v6k" 2> "$D/v6k.err" || krc=$?
nf=$(grep -c 'integer arithmetic with an f64' "$D/v6k.err" || true)
nk=$(grep -c '^warning.*in a kernel build the initializer' "$D/v6k.err" || true)
if [ "$krc" -eq 0 ] && [ "$nf" -eq 0 ] && [ "$nk" -eq 2 ]; then ok "V6k x86 kernel: the zone typed before the late replay (no f64-mix warning; its 2 late-initializer warnings)"
else bad "V6k x86 kernel: rc $krc, $nf f64-mix warning(s), $nk late-initializer warning(s): $(grep -m1 '^warning' "$D/v6k.err")"; fi

echo "  $fails failed, $skips skipped"
if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
echo "PASS: $G — a generic's (V, i64) element is the instance's binding: the filed repro (V1), the tcyr's mv_* spellings (T) on x86_64 / IR / DCE / aarch64 / cx / PE, the checks reading the instance's signature (V2), a generic's tuple local refused once (V3), top level (V4), the refusals' spelling (V5), the declaration zone's f64 element and f64 call global (V6, D98)"

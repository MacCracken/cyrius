#!/bin/sh
# tests/gates/frontend/generic_f64_result.sh — 6.7.9
#
# A GENERIC CALL WHOSE T = f64 IS INFERRED, OR NAMES T ONLY IN ITS RETURN, IS AN f64. A call's f64
# result is typed f64 only by `_call_ret_marks`, from a return recorded -9. Three things kept a
# generic's from it: an f64 ARGUMENT inferred i64 (`_infer_conc_at_cursor`), so `gid(h)` ran the i64
# base (`dbl(h)` added the double's bits) and the call arm typed the result from that base; an
# instance's `: T` at T = f64 was recorded as the base's i64 (`_gtype_tp_ret`, -8) and its value
# handed back in rax; and the explicit arm (`_explicit_generic_call`) never typed its result. So
# `gid(h) * 2.0` and `gg<f64>(&h) * 2.0` multiplied bit patterns as integers, and `gid<f64>(h) * 2.0`
# was right only when the instance was inlined. Now a whole f64 argument binds T = f64 and calls the
# f64 instance (`_gen_infer_tp`'s `_gi_sc`), that instance's `: T` is an f64 return, the inferred
# call is typed from the instance it reaches (`_gcall_ret_f64`), the explicit one by
# `_call_ret_marks`, and a generic METHOD binds an f64 V the same way (`_mcall_gen`, and
# `_var_rhs_msid` for `var w = p.id(h);`). The user's decision 1(e). 6.6.20 - 6.7.8 measured, every
# target. Filed: docs/development/issues/2026-10-10-generic-call-f64-result-untyped.md
#
#   R1 the filed repro, verbatim, exits 0 (7 before: rows 1, 2, 4) on x86_64, x86_64 CYRIUS_IR=3,
#      aarch64 (qemu), cx (cxvm) and PE (wine)
#   W  x86_64, compile only: R1 draws no warning (3 before); and a generic's f64 result mixes like an
#      f64 value — `gid(h) * 2` is a kind 1 as `h * 2` is, `2 * gid(h)` a kind 2, `p.id(h) * 2.0`
#      clean (was a kind 2); the rule's edges keep their kind 2: `gid(h * 2.0) * 2.0` (not the whole
#      argument: T = i64) and `gid(f) * 2.0` with `f: f32` (f32 is not a type argument: T = i64)
#   B  x86_64, compile only: a bound is met at the type the call binds - `gb(h)` and `p.bm(h)` with only
#      `impl Show for i64` are refused, each note naming `impl Show for f64`, as `gb<f64>(h)` always was
#      (before: they compiled and ran the i64 impl on the double's bits); `gb(7)` is not refused
#   T  tests/tcyr/crossos/generic_f64_result.tcyr on x86_64 (default, CYRIUS_IR=1, CYRIUS_IR=3,
#      CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm) and PE (wine): "N passed, 0 failed (N total)", N derived
#      from the file (one row per `assert_eq(` call); the release gate's cross-OS leg runs it on ecb / ach
#      / cass / pi
#
# MUTATION LEDGER (2026-10-11; a scratch copy of the tree with the one change, this gate run from that
# copy with CYCC=<the mutant built from it>):
#   M0  the fix reverted (the tree before it)      -> RED R1 (exit 7) on every leg; W 5 rows (R1's 3
#                                                    warnings; `gid(h) * 2`, `2 * gid(h)` silent;
#                                                    `p.id(h) * 2.0` a kind 2); B 4 rows (the file
#                                                    compiled); T 28 of 44 on every leg
#   M1  `_gtype_tp_ret` keeps -8 at T = f64       -> RED R1 (exit 1) on every leg; W 3 rows; T 13 rows
#                                                    on every leg (the instance's value is left in rax)
#   M2  `_gen_infer_tp` without its `_gi_sc` mark  -> RED R1 (exit 6) on every leg; W 4 rows; B 2 rows; T
#                                                    18 rows on every leg (an inferred call runs the base)
#   M3  an f64 local / parameter infers i64       -> RED R1 (exit 6) on every leg; W 5 rows; B 4 rows; T
#                                                    20 rows on every leg
#   M4  `_call_scale_fix` without `_gcall_ret_f64` -> RED T 4 rows on every leg (the inferred calls that
#                                                    are not inlined: a named argument, three
#                                                    parameters, the self-call, `GfP_id(&p, h)`); R1, W
#                                                    and B green (an inlined replay leaves its f64 behind)
#   M5  `_explicit_generic_call`'s `_call_ret_ps`  -> RED R1 (exit 1) on every leg; W R1; T 3 rows
#   M6  the method arm without `_mcall_gen`        -> RED W 2 rows; T the 4 method rows on every leg
#   M7  `_var_rhs_msid` without `_mcall_gen`       -> RED T `var w = p.id(h);` on every leg
#   M8  `_ic_call_rs` reverted to GFRS             -> RED T `gf_gid(gf_gid(h))` on every leg
#   M9  no float-literal inference (`_ic_flit`)    -> RED T `gf_gid(1.5)` and `p.id(1.5)` on every leg
#   M10 no f64-global inference                    -> RED T `gf_gid(GF_G)` on every leg
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=generic_f64_result
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

fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

TC=tests/tcyr/crossos/generic_f64_result.tcyr
R1=docs/development/issues/repros/2026-10-10-generic-call-f64-result-untyped.cyr
for f in "$TC" "$R1"; do [ -f "$f" ] || { echo "FAIL: $G: $f is missing"; exit 1; }; done
# One row per `assert_eq(` call (the file defines none). The floor keeps a gutted file from passing.
N=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TC")
FLOOR=44
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

echo "R1. the filed repro, verbatim: gg<f64>(&h), gid(h) and gid2(h, 1), each * 2.0, are 3.0 (exit 0; 7 = rows 1, 2, 4)"
for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
    n=$(printf 'R1_%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$R1" "$D/r_$n"
    if [ "$RC" -eq -1 ]; then bad "R1 $leg: did not build: $(grep -m1 'error' "$D/r_$n.err")"
    elif [ "$RC" -eq 0 ]; then ok "R1 $leg: exit 0"
    else bad "R1 $leg: exit $RC, want 0"; fi
done

echo "W. x86_64 warnings: a generic's f64 result mixes like an f64 value"
"$CC" < "$R1" > "$D/w_r1" 2> "$D/w_r1.err" || true
nw=$(grep -c 'warning' "$D/w_r1.err" || true)
if [ "$nw" -eq 0 ]; then ok "W R1: no warning"
else bad "W R1: $nw warning(s), want none: $(grep -m1 'warning' "$D/w_r1.err")"; fi
cat > "$D/wmix.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct P { v; }
impl P { fn id<V>(self, w: V): V { return w; } }
fn gid<T>(x: T): T { return x; }
fn main(): i64 {
    var h: f64 = 1.5;
    var f: f32 = 1.5;
    var p = P { 1 };
    var a = gid(h) * 2;
    var b = gid(h * 2.0) * 2.0;
    var c = gid(f) * 2.0;
    var d = p.id(h) * 2.0;
    var e = 2 * gid(h);
    var g = h * 2;
    return 0;
}
var rc = main();
syscall(60, rc);
EOF
"$CC" < "$D/wmix.cyr" > "$D/wmix" 2> "$D/wmix.err" || true
K1='f64 arithmetic with a non-f64 right operand'
K2='integer arithmetic with an f64 right operand'
# wrow <line> <want: kind text or "none"> <what>
wrow() {
    got=$(grep "^warning:<source>:$1:" "$D/wmix.err" | sed 's/^warning:<source>:[0-9]*:[0-9]*: //' || true)
    if [ "$2" = none ]; then
        if [ -z "$got" ]; then ok "W $3: no warning"; else bad "W $3: '$got', want none"; fi
    elif [ "$got" = "$2" ]; then ok "W $3: '$2'"
    else bad "W $3: '$got', want '$2'"; fi
}
wrow 9 "$K1" "gid(h) * 2 (line 9) — an f64 times an integer"
wrow 10 "$K2" "gid(h * 2.0) * 2.0 (line 10) — not the whole argument: T = i64"
wrow 11 "$K2" "gid(f) * 2.0, f: f32 (line 11) — f32 is not a type argument: T = i64"
wrow 12 none "p.id(h) * 2.0 (line 12)"
wrow 13 "$K2" "2 * gid(h) (line 13)"
wrow 14 "$K1" "h * 2, the f64 control (line 14)"
nw=$(grep -c '^warning' "$D/wmix.err" || true)
if [ "$nw" -eq 5 ]; then ok "W the mix file: 5 warnings in all"
else bad "W the mix file: $nw warnings, want 5: $(tr '\n' ' ' < "$D/wmix.err")"; fi

echo "B. x86_64: a bound is checked at the type the call binds (f64), as the explicit spelling's is"
cat > "$D/bnd.cyr" <<'EOF'
include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
impl Show for i64 { fn show(self): i64 { return self + 1; } }
fn gb<T: Show>(x: T): i64 { return x.show(); }
struct P { v; }
impl P { fn bm<V: Show>(self, w: V): i64 { return w.show(); } }
fn main(): i64 {
    var h: f64 = 1.5;
    var p = P { 1 };
    var a = gb(h);
    var b = p.bm(h);
    return gb(7);
}
var rc = main();
syscall(60, rc);
EOF
brc=0; "$CC" < "$D/bnd.cyr" > "$D/bnd" 2> "$D/bnd.err" || brc=$?
if [ "$brc" -ne 0 ]; then ok "B the file is refused (exit $brc)"; else bad "B the file compiled (exit 0): an f64 argument met the i64 impl"; fi
for ln in 10 11; do
    if grep -q "^error:<source>:$ln:.*does not implement trait 'Show'" "$D/bnd.err"; then ok "B line $ln: refused by the bound"
    else bad "B line $ln: no bound refusal: $(tr '\n' ' ' < "$D/bnd.err")"; fi
done
nf=$(grep -c 'needs `impl Show for f64`' "$D/bnd.err" || true)
if [ "$nf" -eq 2 ]; then ok "B each of the 2 notes names impl Show for f64"
else bad "B $nf of 2 notes name impl Show for f64: $(grep 'note: the bound' "$D/bnd.err" | tr '\n' ' ')"; fi
if grep -q "^error:<source>:12:" "$D/bnd.err"; then bad "B line 12: gb(7) (T = i64, its impl exists) was refused"
else ok "B line 12: gb(7) is not refused (the i64 impl)"; fi
# The explicit spelling, the rule the inferred one now follows (a refusal is reported once per
# generic and type, so it is a file of its own).
sed 's/    var a = gb(h);/    var a = gb<f64>(h);/; /p.bm(h)/d' "$D/bnd.cyr" > "$D/bnd2.cyr"
"$CC" < "$D/bnd2.cyr" > "$D/bnd2" 2> "$D/bnd2.err" || true
if grep -q 'needs `impl Show for f64`' "$D/bnd2.err"; then ok "B control: gb<f64>(h) is refused the same way"
else bad "B control: gb<f64>(h) not refused for f64: $(tr '\n' ' ' < "$D/bnd2.err")"; fi

echo "T. $TC ($N rows)"
for leg in x86 x86:CYRIUS_IR=1 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1 $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TC" "$D/t_$n"
    if [ "$RC" -eq -1 ]; then bad "T $leg: the values file did not build: $(grep -m1 'error' "$D/t_$n.err")"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N passed, 0 failed ($N total)" ]; then ok "T $leg: $LAST"
    else bad "T $leg: exit $RC, '$LAST' (want '$N passed, 0 failed ($N total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a generic call whose T = f64 is inferred or names T only in its return is an f64: the filed repro (R1) on x86_64 / IR / aarch64 / cx / PE, the warnings (W) and the bound (B) on x86_64, and $N rows (T) on x86_64 / IR / DCE / aarch64 / cx / PE"

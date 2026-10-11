#!/bin/sh
# tests/gates/frontend/call_result_type.sh — 6.7.9
#
# A CALL'S RESULT IS TYPED BY ITS CALLEE, NEVER BY ITS LAST ARGUMENT. A call's arguments are parsed as
# expressions inside the call's factor, and the last one leaves its expression type behind; PARSE_FNCALL
# resets it (v6.4.56 D3) and `_call_ret_marks` types a `: f64` return f64. The METHOD arm of
# `_field_load_on` (parse_decl.cyr) ran neither half, so `p.m(1.5) * 2` with `m: i64` multiplied bit
# patterns as doubles (0), `p.m(p) * 10` dispatched the struct's operator fn (undefined `P_mul`, or a
# silent wrong value when one exists), and `p.area() + 1.0` with `area: f64` added integers — and a free
# struct-returning call's field (`mkq(1.5).a`, `_struct_call_emit`) skipped the reset too. The method
# arm now runs `_mcall_ret` (the reset, then `_call_ret_marks`) and `_struct_call_emit` the reset (the
# user's decision 1(d)). 6.7.0 - 6.7.8, every target. Filed:
# docs/development/issues/2026-10-09-method-call-result-keeps-last-arg-f64-type.md
#
#   R1 the filed repro, verbatim, exits 0 (1 before the fix: r = 0) on x86_64, x86_64 CYRIUS_IR=3,
#      aarch64 (qemu), cx (cxvm) and PE (wine)
#   R2 the f64-return repro, verbatim, exits 42 (1 before) on the same legs
#   R3 the struct-last-argument repro, verbatim, exits 20 (before: "undefined function 'P_mul'", no
#      binary) on the same legs
#   W  x86_64, compile only: R1-R3 draw no warning (before: kind 1 on R1, kind 2 on R2); and a method's
#      result mixes like a free call's — `2 * p.m(1.5)` is clean (was a kind 2), `p.area() * 3` is a kind
#      1 exactly as `fa(&p) * 3` is (was clean: untyped), `p.m(1.5) * 2.0` a kind 2 (was clean: the leaked
#      f64 made it a float multiply of 21's bits)
#   T  tests/tcyr/crossos/call_result_type.tcyr on x86_64 (default, CYRIUS_IR=1, CYRIUS_IR=3,
#      CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm) and PE (wine): "N passed, 0 failed (N total)", N derived
#      from the file (one row per `assert_eq(` call); the release gate's cross-OS leg runs it on ecb / ach
#      / cass / pi
#
# MUTATION LEDGER (2026-10-11; a scratch copy of the tree with the one change, this gate run from that
# copy with CYCC=<the mutant built from it>):
#   M0 the fix reverted (the 6.7.9 bite-7 compiler) -> RED R1 (exit 1), R2 (exit 1), R3 (no build) on
#                                                every leg; W 7 of 8 rows (all but the free control); T
#                                                does not build on any leg (`p.mo(p)`: undefined CrP_mul)
#                                                — without that row, 25 of 31 rows red on x86_64
#   M1 `_mcall_ret` without its SESTYPE(S, 0)  -> RED R1 (exit 1), R3 (no build) on every leg; W 4 rows
#                                                (R1, R3, `2 * p.m(1.5)`, `p.m(1.5) * 2.0`); T does not
#                                                build (as M0)
#   M2 `_mcall_ret` calling `_call_ret_ps`      -> RED R2 (exit 1) on every leg; W 3 rows (R2, `p.area()
#      instead of `_call_ret_marks`               * 3`, the count); T the 9 f64-method rows on every leg
#                                                (aarch64 / cx too: their EMOVQ_A_X0 is a no-op, but the
#                                                result is untyped)
#   M3 `_struct_call_emit` without the reset   -> RED T the 4 free-call field rows (`cr_mk*(1.5).f`) on
#                                                every leg; R1-R3 and W green (no free struct call there)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=call_result_type
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

TC=tests/tcyr/crossos/call_result_type.tcyr
RP=docs/development/issues/repros/2026-10-09-method-call-result-keeps-last-arg-f64-type
R1="$RP.cyr"
R2="$RP-f64-return.cyr"
R3="$RP-struct-arg.cyr"
for f in "$TC" "$R1" "$R2" "$R3"; do [ -f "$f" ] || { echo "FAIL: $G: $f is missing"; exit 1; }; done
# One row per `assert_eq(` call (the file defines none). The floor keeps a gutted file from passing.
N=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TC")
FLOOR=32
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

# repro_row <tag> <src> <want-exit> <what>
repro_row() {
    echo "$1. $4"
    for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
        n=$(printf '%s_%s' "$1" "$leg" | tr -c 'a-zA-Z0-9' '_')
        run_leg "$leg" "$2" "$D/r_$n"
        if [ "$RC" -eq -1 ]; then bad "$1 $leg: did not build: $(grep -m1 'error' "$D/r_$n.err")"
        elif [ "$RC" -eq "$3" ]; then ok "$1 $leg: exit $3"
        else bad "$1 $leg: exit $RC, want $3"; fi
    done
}
repro_row R1 "$R1" 0 "the filed repro, verbatim: p.m(1.5) * 2 and m2(&p, 1.5) * 2 are 42 (exit 0; 1 = r was 0)"
repro_row R2 "$R2" 42 "the f64-return repro, verbatim: p.area() + 1.0 is an f64 add (exit 42; 1 = an integer add)"
repro_row R3 "$R3" 20 "the struct-last-argument repro, verbatim: p.m(p) * 10 is 20 (was: undefined function 'P_mul')"

echo "W. x86_64 warnings: a method's result mixes like a free call's"
for r in R1 R2 R3; do
    eval "src=\$$r"
    "$CC" < "$src" > "$D/w_$r" 2> "$D/w_$r.err"
    nw=$(grep -c 'warning' "$D/w_$r.err" || true)
    if [ "$nw" -eq 0 ]; then ok "W $r: no warning"
    else bad "W $r: $nw warning(s), want none: $(grep -m1 'warning' "$D/w_$r.err")"; fi
done
cat > "$D/wmix.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct P { v; }
impl P { fn m(self, d: f64): i64 { return 21; } fn area(self): f64 { return 2.5; } }
fn fa(p): f64 { return 2.5; }
fn main(): i64 {
    var p = P { 1 };
    var a = 2 * p.m(1.5);
    var b = p.area() * 3;
    var c = fa(&p) * 3;
    var d = p.m(1.5) * 2.0;
    return 0;
}
var rc = main();
syscall(60, rc);
EOF
"$CC" < "$D/wmix.cyr" > "$D/wmix" 2> "$D/wmix.err"
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
wrow 7 none "2 * p.m(1.5) (line 7)"
wrow 8 "$K1" "p.area() * 3 (line 8)"
wrow 9 "$K1" "fa(&p) * 3, the free control (line 9)"
wrow 10 "$K2" "p.m(1.5) * 2.0 (line 10)"
nw=$(grep -c '^warning' "$D/wmix.err" || true)
if [ "$nw" -eq 3 ]; then ok "W the mix file: 3 warnings in all"
else bad "W the mix file: $nw warnings, want 3: $(tr '\n' ' ' < "$D/wmix.err")"; fi

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
echo "PASS: $G — a call's result is typed by its callee, never by its last argument: the three filed repros (R1-R3) on x86_64 / IR / aarch64 / cx / PE, the warnings (W) on x86_64, and $N rows (T) on x86_64 / IR / DCE / aarch64 / cx / PE"

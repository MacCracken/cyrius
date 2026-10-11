#!/bin/sh
# tests/gates/frontend/unary_constant_fold.sh — 6.7.9
#
# UNARY `-` / `~` ON A CONSTANT OPERAND BINDS TIGHTER THAN A LITERAL OPERATOR AFTER IT. The run-time
# constant fold (`_cfo` / `_cfv` / `_cfp`, parse_expr.cyr) folds `K op L` when its left operand was a
# constant factor (a literal, an enum constant or a `const`, 0 - 0xFFFF) and L an integer literal,
# rewinding the code to the constant. Unary `-` (on anything but a literal) and unary `~` parsed their
# operand as a factor, which armed the fold with the OPERAND's value, and returned still armed: `-K + 10`
# folded `5 + 10` = 15 and `~5 * 2` folded `5 * 2` = 10, and the rewind dropped the 0 unary minus had
# pushed (`1 + -K * 2` was 10; a loop leaked a stack word a turn). 6.6.10 - 6.7.8, every target.
# `_neg_int` / `_bnot_int` now disarm it (the user's decision 1(c)). Filed:
# docs/development/issues/2026-10-10-unary-minus-and-not-folded-over-by-literal-operator.md
#
#   R  the filed repro, verbatim, exits 0 (7 before the fix: seven wrong values) on x86_64, aarch64
#      (qemu), cx (cxvm) and PE (wine)
#   T  tests/tcyr/crossos/unary_constant_fold.tcyr on x86_64 (default, CYRIUS_IR=1, CYRIUS_IR=3,
#      CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm) and PE (wine): "N passed, 0 failed (N total)", N derived
#      from the file (one row per `assert_eq(` call); the release gate's cross-OS leg runs it on ecb /
#      ach / cass / pi
#
# MUTATION LEDGER (2026-10-11; a scratch copy of the tree with the one change, this gate run from that
# copy with CYCC=<the mutant built from it>):
#   M0 both disarms removed (the fix reverted) -> RED R (exit 7) on every leg; T 57 of 77 rows on x86 /
#                                                IR=1 / DCE=1 / aarch64 / PE, 55 under IR=3, and cx stops
#                                                at "cxvm: data stack overflow" (the leaked pushes)
#   M1 `_neg_int` without `_cfo = 0`           -> RED R (exit 3) on every leg; T 34 rows (33 under IR=3;
#                                                cx: the data stack overflow)
#   M2 `_bnot_int` without `_cfo = 0`          -> RED R (exit 4) on every leg; T 21 rows (cx: "guest
#                                                address out of range" — the folded index)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=unary_constant_fold
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

TC=tests/tcyr/crossos/unary_constant_fold.tcyr
REPRO=docs/development/issues/repros/2026-10-10-unary-minus-and-not-folded-over-by-literal-operator.cyr
[ -f "$TC" ] || { echo "FAIL: $G: $TC is missing"; exit 1; }
[ -f "$REPRO" ] || { echo "FAIL: $G: $REPRO is missing"; exit 1; }
# One row per `assert_eq(` call (not the definition — the file has none). The floor keeps a gutted
# file from passing.
N=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TC")
FLOOR=77
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

echo "R. the filed repro, verbatim (exit 0; 7 = seven shapes folded over the unary operator)"
for leg in x86 x86:CYRIUS_IR=3 $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$REPRO" "$D/r_$n"
    if [ "$RC" -eq -1 ]; then bad "R $leg: did not build: $(grep '^error' "$D/r_$n.err" | head -1)"
    elif [ "$RC" -eq 0 ]; then ok "R $leg: exit 0"
    else bad "R $leg: exit $RC, want 0"; fi
done

echo "T. $TC ($N rows)"
for leg in x86 x86:CYRIUS_IR=1 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1 $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    run_leg "$leg" "$TC" "$D/t_$n"
    if [ "$RC" -eq -1 ]; then bad "T $leg: the values file did not build: $(grep '^error' "$D/t_$n.err" | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$N passed, 0 failed ($N total)" ]; then ok "T $leg: $LAST"
    else bad "T $leg: exit $RC, '$LAST' (want '$N passed, 0 failed ($N total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — unary - / ~ on a constant binds tighter than the literal operator after it: the filed repro (R) and $N rows (T) on x86_64 / IR / DCE / aarch64 / cx / PE"

#!/bin/sh
# tests/gates/codegen/global_struct_store_width.sh — 6.7.7
#
# A WHOLE-STRUCT STORE INTO A GLOBAL WRITES EXACTLY THE STRUCT'S BYTES. Struct globals are packed,
# so a 3 / 5 / 6 / 7-byte global has a neighbour right after it; a struct of 8 bytes or fewer is
# stored from one register through EVSTORE_W, which stored exactly only 1 / 2 / 4 bytes and took
# the 8-byte store for every other width. `G = l;` (the filed repro), `G = mk();` and every other
# form of such a value overwrote the next 5 / 3 / 2 / 1 bytes of globals, silently, on every
# backend. EVSTORE_W now stores those widths as 4 + 2 + 1 pieces (x86 `_ESTORE_ODD_RCX`, aarch64
# `_ESTORE_ODD_X1`, cx `_CX_STORE_ODD`). Filed:
# docs/development/issues/2026-10-09-global-odd-size-struct-store-overwrites-next-global.md
#
# The runtime half is tests/tcyr/crossos/global_struct_store_width.tcyr — every struct size 1..16
# and every store form (its header carries the analysis: which store path each form takes, and why
# the declaration replay's `_gv_store` is not it). The release gate's cross-OS leg runs it on ecb /
# ach / cass / pi; this gate runs it on the legs this box has, compilers built from this tree:
#   R  the filed repro, verbatim, exits 77 (0 before the fix: the i8 after G was overwritten) on
#      x86_64, aarch64 (qemu), cx (cxvm) and PE (wine)
#   T  the values file on x86_64 (default, CYRIUS_IR=1, CYRIUS_IR=3, CYRIUS_DCE=1), aarch64 (qemu),
#      cx (cxvm) and PE (wine): "N passed, 0 failed (N total)", N derived from the file (one row per
#      `gs_row(` call or top-level `assert_eq(`; on cx without the `#ifndef CYRIUS_TARGET_CX` blocks)
#
# MUTATION LEDGER (2026-10-09; a scratch copy of the tree with the one change, this gate run from
# that copy with CYCC=<the mutant built from it>):
#   the merged 6.7.7 compiler   -> RED R (exit 0) and T on every leg (88 of 304 rows; cx 88 of 284)
#   M1 x86 EVSTORE_W without its odd arm      -> RED R x86, R PE, T x86 / IR=1 / IR=3 / DCE=1 / PE
#   M2 aarch64 EVSTORE_W without its odd arm  -> RED R aarch64, T aarch64
#   M3 cx EVSTORE_W without its odd arm       -> RED R cx, T cx
#   M4 x86 ror by 8*off, not 8*(off-rot)       -> RED T x86 / IR=1 / IR=3 / DCE=1 / PE (22 rows: byte 6
#                                                of the 7-byte shapes); R green (a 3-byte struct)
#   M6 aarch64 later pieces from w0, not w16   -> RED T aarch64 (G's byte 2 wrong); R green (the
#                                                repro reads only the neighbour, which is intact)
#   M7 cx later pieces stored at r1 + 0        -> RED T cx (G's tail bytes wrong); R green, as M6
#   GREEN, recorded (see the tcyr header): M5 x86 without the closing `rol`, M8 `_gv_store` back to
#   exact 1 / 2 / 4.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=global_struct_store_width
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

TC=tests/tcyr/crossos/global_struct_store_width.tcyr
REPRO=docs/development/issues/repros/2026-10-09-global-odd-size-struct-store-overwrites-next-global.cyr
[ -f "$TC" ] || { echo "FAIL: $G: $TC is missing"; exit 1; }
[ -f "$REPRO" ] || { echo "FAIL: $G: $REPRO is missing"; exit 1; }
# One row per `gs_row(` call (not its definition) or top-level `assert_eq(`; NCX leaves out the
# rows inside `#ifndef CYRIUS_TARGET_CX` blocks. The floor keeps a gutted file from passing.
N=$(awk '/^fn gs_row/{next} /gs_row\(|^assert_eq\(/{n++} END{print n+0}' "$TC")
NCX=$(awk '/^[[:space:]]*#ifndef CYRIUS_TARGET_CX/{s=1; next} /^[[:space:]]*#endif/{s=0; next} /^fn gs_row/{next} !s && /gs_row\(|^assert_eq\(/{n++} END{print n+0}' "$TC")
FLOOR=300
if [ "$N" -lt "$FLOOR" ]; then echo "FAIL: $G: only $N rows in $TC (floor $FLOOR) — rows were lost"; exit 1; fi

# The legs this box can run: aarch64 under qemu, cx under the tree's own cxvm, PE under wine.
A64=""; CXCC=""; CXRUN=""; WINE=0
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

echo "R. the filed repro, verbatim (exit 77; 0 = the i8 after G overwritten)"
for leg in x86 $OTHER; do
    run_leg "$leg" "$REPRO" "$D/r_$leg"
    if [ "$RC" -eq -1 ]; then bad "R $leg: did not build: $(grep '^error' "$D/r_$leg.err" | head -1)"
    elif [ "$RC" -eq 77 ]; then ok "R $leg: exit 77"
    else bad "R $leg: exit $RC, want 77"; fi
done

echo "T. $TC ($N rows; $NCX on cx)"
for leg in x86 x86:CYRIUS_IR=1 x86:CYRIUS_IR=3 x86:CYRIUS_DCE=1 $OTHER; do
    n=$(printf '%s' "$leg" | tr -c 'a-zA-Z0-9' '_')
    want=$N; [ "$leg" = cx ] && want=$NCX
    run_leg "$leg" "$TC" "$D/t_$n"
    if [ "$RC" -eq -1 ]; then bad "T $leg: the values file did not build: $(grep '^error' "$D/t_$n.err" | head -1)"
    elif [ "$RC" -eq 0 ] && [ "$LAST" = "$want passed, 0 failed ($want total)" ]; then ok "T $leg: $LAST"
    else bad "T $leg: exit $RC, '$LAST' (want '$want passed, 0 failed ($want total)') $(grep -m3 'FAIL' "$D/t_$n.out" | tr '\n' ' ')"; fi
done

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a whole-struct store into a global writes exactly its bytes: the filed repro (R) and every size 1..16 x every store form (T) on x86_64 / IR / DCE / aarch64 / cx / PE"

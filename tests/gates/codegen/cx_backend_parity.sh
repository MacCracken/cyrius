#!/bin/sh
# cx_backend_parity.sh — 6.7.6 (Break 1, lane F). Values the cx bytecode backend got wrong while
# every native backend got them right, each run NATIVELY (x86, the oracle) and on cxvm.
#
# THE DEFECTS (measured on cycc 6.7.5 with this tree's cycc_cx + cxvm):
#   A  `~x` was `x` on cx. ENOTR emitted `xor r0, r0, r31` on the word of a comment that r31 held
#      all-ones; nothing ever set it and cxvm zeroes its registers. `var x = 6; return ~x + 10;`
#      exited 16 on cx, 3 on x86 / aarch64 / PE; bitclr / bitset complement their mask, so they
#      kept the bits they were asked to clear (bitclr(0xFF, 4, 4) = 0xF0, want 0x0F).
#
# ROWS
#   T  tests/tcyr/codegen/cx_backend_parity.tcyr: native x86 and cxvm must each print
#      "<N> passed, 0 failed (<N> total)" and exit 0, N = the assertions counted in the source
#      (floor below). The same file on aarch64 (qemu-aarch64) and PE (wine, a private prefix torn
#      down on exit) is the other ABIs' oracle; either leg is a named SKIP when its tool is absent.
#   A1 the filed repro, inline: native and cxvm both exit 3.
#
# COMPILERS. CC=${CYCC:-build/cycc} builds the native legs and the cx compiler from THIS tree's
# src/main_cx.cyr, and cxvm from programs/cxvm.cyr. A cx-backend mutation is therefore picked up
# by running the gate from a mutated COPY of the tree, with the real build/cycc.
#
# MUTATION LEDGER (6.7.6, each in a scratch copy of the tree, the gate run from that copy with the
# real build/cycc; the real tree is green):
#   ENOTR back to `CX_EMIT(S, 34, 0, 0, 31)`        -> T cx RED (0 passed, 8 failed) + A1 RED (cx 16)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: cx_backend_parity — no compiler at $CC (exit 77: a SKIP, not a PASS)"; exit 77; }
command -v timeout >/dev/null 2>&1 || { echo "SKIP: cx_backend_parity — no timeout(1) (exit 77)"; exit 77; }
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp"; exit 1; }
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

"$CC" < src/main_cx.cyr > "$D/cc" 2> "$D/cc.err"; [ -s "$D/cc" ] || { echo "FAIL: cannot build the cx compiler from src/main_cx.cyr"; exit 1; }
"$CC" < programs/cxvm.cyr > "$D/vm" 2> "$D/vm.err"; [ -s "$D/vm" ] || { echo "FAIL: cannot build cxvm from programs/cxvm.cyr"; exit 1; }
chmod +x "$D/cc" "$D/vm"

pass=0; fail=0
ok()  { printf '  ok: %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL: %s\n' "$1"; fail=$((fail+1)); }

# cx_file FILE [secs] -> CXRC, CXERR (stderr's first line), CXOUT (stdout's last line)
cx_file() {
    CXRC=255; CXERR=''; CXOUT=''
    "$D/cc" < "$1" > "$D/c.cyx" 2> "$D/c.cerr" || { CXERR="cx compile failed: $(grep -v '^note' "$D/c.cerr" | head -1)"; CXRC=-1; return; }
    CXRC=0; ( ulimit -c 0; timeout "${2:-60}" "$D/vm" < "$D/c.cyx" ) > "$D/c.out" 2> "$D/c.verr" || CXRC=$?
    CXERR=$(head -1 "$D/c.verr"); CXOUT=$(tail -1 "$D/c.out")
}
nat_file() {
    NATRC=-1; NATOUT=''
    "$CC" < "$1" > "$D/n.bin" 2> "$D/n.err" || return
    chmod +x "$D/n.bin"; NATRC=0
    { ( ulimit -c 0; timeout 60 "$D/n.bin" ) > "$D/n.out" 2>&1 || NATRC=$?; } 2> /dev/null
    NATOUT=$(tail -1 "$D/n.out")
}
# both LABEL SRC WANT: cx and native must both exit WANT
both() {
    printf '%s' "$2" > "$D/s.cyr"
    nat_file "$D/s.cyr"; cx_file "$D/s.cyr"
    if [ "$NATRC" != "$3" ]; then bad "$1: native exits $NATRC, want $3 (the expectation itself is wrong)"; return; fi
    if [ "$CXRC" = "$3" ]; then ok "$1 (cx $CXRC = native)"; else bad "$1: cx exits $CXRC (want $3, native $NATRC)${CXERR:+ — $CXERR}"; fi
}

echo "T. tests/tcyr/codegen/cx_backend_parity.tcyr, native and on cxvm"
TC=tests/tcyr/codegen/cx_backend_parity.tcyr
N=$(grep -c '^[[:space:]]*assert_[a-z]*(' "$TC")
FLOOR=8
if [ "$N" -lt "$FLOOR" ]; then bad "T: only $N assertions in $TC (floor $FLOOR) — rows were lost"
else
    nat_file "$TC"
    if [ "$NATRC" = 0 ] && [ "$NATOUT" = "$N passed, 0 failed ($N total)" ]; then ok "T native: $NATOUT"
    else bad "T native: exit $NATRC, '$NATOUT' (want '$N passed, 0 failed ($N total)')"; fi
    cx_file "$TC" 120
    if [ "$CXRC" = 0 ] && [ "$CXOUT" = "$N passed, 0 failed ($N total)" ]; then ok "T cx: $CXOUT"
    else bad "T cx: exit $CXRC, '$CXOUT' (want '$N passed, 0 failed ($N total)')${CXERR:+ — $CXERR} $(grep -m3 'FAIL' "$D/c.out" | tr '\n' ' ')"; fi
    if command -v qemu-aarch64 > /dev/null 2>&1; then
        "$CC" < src/main_aarch64.cyr > "$D/cc_a64" 2> /dev/null; chmod +x "$D/cc_a64" 2> /dev/null
        if [ -s "$D/cc_a64" ] && "$D/cc_a64" < "$TC" > "$D/t.a" 2> "$D/t.aerr" && [ -s "$D/t.a" ]; then
            chmod +x "$D/t.a"; got=0; (cd "$D" && ulimit -c 0; timeout 300 qemu-aarch64 ./t.a > "$D/t.aout" 2>&1) || got=$?
            last=$(tail -1 "$D/t.aout")
            if [ "$got" = 0 ] && [ "$last" = "$N passed, 0 failed ($N total)" ]; then ok "T aarch64 (qemu): $last"
            else bad "T aarch64 (qemu): exit $got, '$last' $(grep -m3 'FAIL' "$D/t.aout" | tr '\n' ' ')"; fi
        else bad "T aarch64: could not build src/main_aarch64.cyr or the tcyr: $(grep '^error' "$D/t.aerr" 2> /dev/null | head -1)"; fi
    else echo "  SKIP: T aarch64 — qemu-aarch64 not installed"; fi
    if command -v wine > /dev/null 2>&1; then
        if CYRIUS_TARGET_WIN=1 "$CC" < "$TC" > "$D/t.exe" 2> "$D/t.werr" && [ -s "$D/t.exe" ]; then
            got=0
            (cd "$D" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine ./t.exe > "$D/t.wout" 2> /dev/null) || got=$?
            last=$(tail -1 "$D/t.wout" | tr -d '\r')
            if [ "$got" = 0 ] && [ "$last" = "$N passed, 0 failed ($N total)" ]; then ok "T PE (wine): $last"
            else bad "T PE (wine): exit $got, '$last' $(grep -m3 'FAIL' "$D/t.wout" | tr '\n' ' ')"; fi
        else bad "T PE: the tcyr did not compile: $(grep '^error' "$D/t.werr" | head -1)"; fi
    else echo "  SKIP: T PE — wine not installed"; fi
fi

echo "A. ~x"
both "A1 var x = 6; return ~x + 10; (the filed repro; cx gave 16)" 'fn main() { var x = 6; return ~x + 10; }
var r = main();
syscall(60, r);
' 3

echo
echo "cx_backend_parity: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
echo "PASS cx_backend_parity: ~x is the complement on cx (bitset / bitclr with it), as on every native backend"

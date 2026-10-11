#!/bin/sh
# tests/gates/frontend/slice_signed_read.sh — 6.7.8 (C2-6c)
#
# A SIGNED SLICE ELEMENT IS READ SIGN-EXTENDED (the user's decision, 2026-10-10). `s[i]` on an
# [i8] / [i16] / [i32] (or slice<i8> ..) slice local called lib/slice.cyr's `_slice_idx_get_1/2/4`,
# whose load8 / load16 / load32 zero-extend: a stored -3 in an [i8] read 253 and `s[0] < 0` was false
# (6.7.7 and every release since v5.8.15), while the same bytes in an `i8[N]` array, through a `*i8`
# or in an i8 field read -3. The read now takes the element's checked address from the store's call
# (`_slice_idx_addr(&s, i, sizeof(T))`, the same "slice bounds violation" / 134 check) and loads it at
# the negative width (`_esub_load`, src/frontend/parse_expr.cyr `_slice_sub_sread`), and `s[i] OP= v`
# (C2-6a) loads the element the same way. Unsigned, i64, float, bool, pointer and u128 elements keep
# their getter byte for byte (the differential: nothing else that compiled changes).
#
#   R  the decision's shape by exit code: `s[0] = -3; return s[0] < 0;` on [i8] / [i16] / [i32] (was
#      0), `return s[0] + 2 < 0;` on [i8] (the C2-1b left-operand shape; was 0); the controls: [u8]
#      0xFD reads 253 and [u16] 0xFFFD < 0 is false
#   T  a signed read out of range on every leg (x86 plain / CYRIUS_IR=3, aarch64 qemu, cx, PE wine):
#      past the end of an [i8], a negative index into an [i16], past the end of an [i32] in an
#      expression — exit 134, "slice bounds violation" (the read's check moved to `_slice_idx_addr`)
#   W  tests/tcyr/crossos/slice_signed_read.tcyr (every signed width and its extremes, the unsigned
#      controls, the slice read == the typed array == the `*T` == the field holding the same
#      bytes, a negative element in every expression position, OP= as the typed array's, generic /
#      closure / heap places) compiles with no warning; --syntax-only silent; then on x86 (plain,
#      CYRIUS_IR=1, CYRIUS_IR=3, CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm) and PE (wine), its full
#      assertion count
#
# MUTATION LEDGER (scratch trees, each its 2-stage mutant cycc, the gates run from that tree as
# CYCC=<mutant>; 2026-10-10):
#   MS1  `_slice_sub_read` without its signed arm (every read through the getter) -> RED R1-R4,
#        Wa Wb Wf Wg Wc Wd We (the 6.7.7 values) and slice_position_refused.sh E1; T green
#   MS2  the store / OP= path drops an integer's sign (`_arr_sub_addr`'s slice arm) -> RED Wa Wb Wf
#        Wg Wc Wd We (the O rows) and slice_position_refused.sh E1 (OP= and the read disagree)
#   MS2b `_slice_sub_addr` drops it (C2-6a's line restored: read and OP= both zero-extend) -> RED
#        R1-R4, Wa-We; slice_position_refused.sh E green (the two agree — E pins only agreement)
#   MS3  `_slice_sub_sread` loads by `_arr_sub_load` (no `_esub_load` resets) -> RED R4 and Wa-We
#        (exit 132: `s[0] + 2` with a constant index, the C2-1b crash back on the signed path) and
#        slice_read_left_operand.sh A1-A7 (139 / cxvm "guest address out of range" / PE 84)
#   MS4  `_slice_idx_addr` without its two checks (lib/slice.cyr) -> RED T1a-T3e (15: every leg)
#   MS5  `_arr_sub_load` without its signed-width IR record (C2-4a's M25, shared) -> RED Wb (IR=3)
#   the C2-6a compiler (before this bite) -> RED R1-R4, Wa Wb Wf Wg We; R5 R6 T W0 W0s green; Wc Wd
#        pass (those legs' compilers are built from this tree's src)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=slice_signed_read
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix under $T (never ~/.wine), torn down with its server dir on exit — the
# defer_every_return_path.sh helper. CHANGELOG [6.6.16] [6.6.17]
WP="$T/wine"
WHM="$T/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
cd "$ROOT"
fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
wine_run() {   # <dir> <exe> <stderr file>: run under the private prefix; sets got
    got=0
    (cd "$1" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
        WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$2" > "$1/$2.out" 2> "$3") || got=$?
}
HAVE_WINE=0
if command -v wine > /dev/null 2>&1; then HAVE_WINE=1
else echo "  SKIP Te / We: the PE legs — wine not installed"; skips=$((skips + 1)); fi
HAVE_QEMU=0
if command -v qemu-aarch64 > /dev/null 2>&1; then HAVE_QEMU=1
else echo "  SKIP Tc / Wc: the aarch64 legs — qemu-aarch64 not installed"; skips=$((skips + 1)); fi

# ── R: the decision's shape, by exit code ──────────────────────────────────────────────────────
# exits <name> <want> <what> <element type> <body>: s is a 4-element slice of <type> over b
exits() {
    printf '%b' "include \"lib/slice.cyr\"\nfn f(): i64 {\n    var b: i64[2];\n    var s: [$4] = 0;\n    slice_set(&s, &b, 4);\n$5}\nvar rc = f();\nsyscall(60, rc);\n" > "$T/$1.cyr"
    rc=0; timeout 60 "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; timeout 10 "$T/$1.bin" > /dev/null 2>&1 || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
exits r1 1 "R1: [i8] s[0] = -3; return s[0] < 0; (was 0: the element read 253)" i8 \
    '    s[0] = 0 - 3;\n    return s[0] < 0;\n'
exits r2 1 "R2: [i16] s[1] = -3; return s[1] < 0; (was 0)" i16 \
    '    s[1] = 0 - 3;\n    return s[1] < 0;\n'
exits r3 1 "R3: [i32] s[2] = -3; return s[2] < 0; (was 0)" i32 \
    '    s[2] = 0 - 3;\n    return s[2] < 0;\n'
exits r4 1 "R4: [i8] s[0] = -3; return s[0] + 2 < 0; (a constant index on the left of +: was 0)" i8 \
    '    s[0] = 0 - 3;\n    return s[0] + 2 < 0;\n'
exits r5 253 "R5: control: [u8] store8 0xFD; return s[0]; (zero-extended, as before)" u8 \
    '    store8(&b, 0xFD);\n    return s[0];\n'
exits r6 0 "R6: control: [u16] 0xFFFD; return s[0] < 0; (false, as before)" u16 \
    '    store16(&b, 0xFFFD);\n    return s[0] < 0;\n'

# ── T: a signed read out of range, on every leg ─────────────────────────────────────────────────
"$CC" < src/main_cx.cyr > "$T/cc_cx" 2> "$T/cc_cx.err" && [ -s "$T/cc_cx" ] \
    && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/cxvm.err" && [ -s "$T/cxvm" ] && chmod +x "$T/cc_cx" "$T/cxvm" \
    || rm -f "$T/cc_cx" "$T/cxvm"
if [ "$HAVE_QEMU" -eq 1 ]; then
    "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> "$T/cc_a64.err" && [ -s "$T/cc_a64" ] && chmod +x "$T/cc_a64" || rm -f "$T/cc_a64"
fi
trap_ok() {   # <label> <exit> <stderr file>
    if [ "$2" -eq 134 ] && tr -d '\r' < "$3" | grep -qx 'slice bounds violation'; then ok "$1: exit 134, \"slice bounds violation\""
    else bad "$1: exit $2, stderr: $(tr -d '\r' < "$3" | head -2 | tr '\n' '|')"; fi
}
trap_legs() {   # <name> <what> <element type> <statement>: s is a 4-element slice of <type>
    n=$1
    printf '%b' "include \"lib/slice.cyr\"\nfn f(): i64 {\n    var b: i64[2];\n    var s: [$3] = 0;\n    slice_set(&s, &b, 4);\n$4    return 3;\n}\nsyscall(60, f());\n" > "$T/$n.cyr"
    for mode in plain IR3; do
        env_=""; lbl="${n}a: x86"
        [ "$mode" = IR3 ] && { env_="CYRIUS_IR=3"; lbl="${n}b: x86, CYRIUS_IR=3"; }
        rc=0; env $env_ "$CC" < "$T/$n.cyr" > "$T/${n}_$mode" 2> "$T/${n}_$mode.cerr" || rc=$?
        if [ "$rc" -ne 0 ]; then bad "$lbl $2: rc $rc: $(grep '^error' "$T/${n}_$mode.cerr" | head -1)"; continue; fi
        chmod +x "$T/${n}_$mode"; got=0; timeout 10 "$T/${n}_$mode" > /dev/null 2> "$T/${n}_$mode.err" || got=$?
        trap_ok "$lbl $2" "$got" "$T/${n}_$mode.err"
    done
    if [ "$HAVE_QEMU" -eq 1 ]; then
        if [ ! -x "$T/cc_a64" ]; then bad "${n}c: src/main_aarch64.cyr did not build"
        elif "$T/cc_a64" < "$T/$n.cyr" > "$T/$n.a64" 2> "$T/$n.a64.cerr" && [ -s "$T/$n.a64" ]; then
            chmod +x "$T/$n.a64"; got=0; (cd "$T" && timeout 60 qemu-aarch64 "./$n.a64" > /dev/null 2> "$T/$n.a64.err") || got=$?
            trap_ok "${n}c: aarch64 (qemu) $2" "$got" "$T/$n.a64.err"
        else bad "${n}c: aarch64: did not compile: $(grep '^error' "$T/$n.a64.cerr" | head -1)"; fi
    fi
    if [ ! -x "$T/cc_cx" ]; then bad "${n}d: src/main_cx.cyr or programs/cxvm.cyr did not build"
    elif "$T/cc_cx" < "$T/$n.cyr" > "$T/$n.cyx" 2> "$T/$n.cyx.cerr" && [ -s "$T/$n.cyx" ]; then
        got=0; timeout 60 "$T/cxvm" < "$T/$n.cyx" > /dev/null 2> "$T/$n.cyx.err" || got=$?
        trap_ok "${n}d: cx (cxvm) $2" "$got" "$T/$n.cyx.err"
    else bad "${n}d: cx: did not compile: $(grep '^error' "$T/$n.cyx.cerr" | head -1)"; fi
    if [ "$HAVE_WINE" -eq 1 ]; then
        if CYRIUS_TARGET_WIN=1 "$CC" < "$T/$n.cyr" > "$T/$n.exe" 2> "$T/$n.exe.cerr" && [ -s "$T/$n.exe" ]; then
            wine_run "$T" "$n.exe" "$T/$n.exe.err"
            trap_ok "${n}e: PE (wine) $2" "$got" "$T/$n.exe.err"
        else bad "${n}e: PE: did not compile: $(grep '^error' "$T/$n.exe.cerr" | head -1)"; fi
    fi
}
trap_legs T1 "return s[4]; on a 4-element [i8]" i8 '    return s[4];\n'
trap_legs T2 "var v = s[0 - 1]; on an [i16]" i16 '    var v = s[0 - 1];\n    return v;\n'
trap_legs T3 "s[4] + 1 in an expression, an [i32]" i32 '    var i = 4;\n    return s[i] + 1;\n'

# ── W: the value file on every leg ──────────────────────────────────────────────────────────────
TC="$ROOT/tests/tcyr/crossos/slice_signed_read.tcyr"
[ -f "$TC" ] || { echo "FAIL: $G: $TC missing"; exit 1; }
cp "$TC" "$T/w.cyr"
rc=0; "$CC" < "$T/w.cyr" > "$T/w0.bin" 2> "$T/w0.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^warning' "$T/w0.err"; then ok "W0: the value file compiles with no warning"
else bad "W0: rc $rc: $(grep '^error\|^warning' "$T/w0.err" | head -2 | tr '\n' '|')"; fi
rc=0; "$CC" --syntax-only < "$T/w.cyr" > /dev/null 2> "$T/w0s.err" || rc=$?
if [ "$rc" -eq 0 ] && ! grep -q '^error\|^warning' "$T/w0s.err"; then ok "W0s: --syntax-only (cyrius lint) reports nothing"
else bad "W0s: rc $rc: $(grep '^error\|^warning' "$T/w0s.err" | head -2 | tr '\n' '|')"; fi
WANT=$(grep -oE 'assert_eq\(' "$TC" | wc -l)
if [ "$WANT" -lt 90 ]; then bad "W: only $WANT assertions derived from $(basename "$TC") (floor 90)"; fi
w_ok() {   # <label> <exit> <output file>
    if [ "$2" -eq 0 ] && tr -d '\r' < "$3" | grep -q "^$WANT passed, 0 failed"; then ok "$1: $WANT passed"
    else bad "$1: exit $2 $(tr -d '\r' < "$3" | grep -m2 'FAIL\|violation\|passed' | tr '\n' '|')"; fi
}
for mode in plain IR3 IR1 DCE1; do
    case $mode in
        plain) env_=""; lbl="Wa: x86" ;;
        IR3) env_="CYRIUS_IR=3"; lbl="Wb: x86, CYRIUS_IR=3" ;;
        IR1) env_="CYRIUS_IR=1"; lbl="Wf: x86, CYRIUS_IR=1" ;;
        DCE1) env_="CYRIUS_DCE=1"; lbl="Wg: x86, CYRIUS_DCE=1" ;;
    esac
    rc=0; env $env_ "$CC" < "$T/w.cyr" > "$T/w_$mode" 2> "$T/w_$mode.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "$lbl: rc $rc: $(grep '^error' "$T/w_$mode.err" | head -1)"; continue; fi
    chmod +x "$T/w_$mode"; got=0; timeout 60 "$T/w_$mode" > "$T/w_$mode.out" 2>&1 || got=$?
    w_ok "$lbl" "$got" "$T/w_$mode.out"
done
if [ "$HAVE_QEMU" -eq 1 ]; then
    if [ ! -x "$T/cc_a64" ]; then bad "Wc: src/main_aarch64.cyr did not build"
    elif "$T/cc_a64" < "$T/w.cyr" > "$T/w.a64" 2> "$T/w.a64.err" && [ -s "$T/w.a64" ]; then
        chmod +x "$T/w.a64"; got=0; (cd "$T" && timeout 120 qemu-aarch64 ./w.a64 > "$T/w.a64.out" 2>&1) || got=$?
        w_ok "Wc: aarch64 (qemu)" "$got" "$T/w.a64.out"
    else bad "Wc: aarch64: did not compile: $(grep '^error' "$T/w.a64.err" | head -1)"; fi
fi
if [ ! -x "$T/cc_cx" ]; then bad "Wd: src/main_cx.cyr or programs/cxvm.cyr did not build"
elif "$T/cc_cx" < "$T/w.cyr" > "$T/w.cyx" 2> "$T/w.cyx.err" && [ -s "$T/w.cyx" ]; then
    got=0; timeout 120 "$T/cxvm" < "$T/w.cyx" > "$T/w.cyx.out" 2>&1 || got=$?
    w_ok "Wd: cx (cxvm)" "$got" "$T/w.cyx.out"
else bad "Wd: cx: did not compile: $(grep '^error' "$T/w.cyx.err" | head -1)"; fi
if [ "$HAVE_WINE" -eq 1 ]; then
    if CYRIUS_TARGET_WIN=1 "$CC" < "$T/w.cyr" > "$T/w.exe" 2> "$T/w.exe.err" && [ -s "$T/w.exe" ]; then
        wine_run "$T" w.exe "$T/w.exe.serr"
        cat "$T/w.exe.serr" >> "$T/w.exe.out"
        w_ok "We: PE (wine)" "$got" "$T/w.exe.out"
    else bad "We: PE: did not compile: $(grep '^error' "$T/w.exe.err" | head -1)"; fi
fi

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — an [i8] / [i16] / [i32] slice element reads sign-extended, the unsigned controls zero-extended (R); a signed read out of range traps on every leg (T); the value file on x86 / IR / DCE / aarch64 / cx / PE (W)"

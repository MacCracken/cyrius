#!/bin/sh
# tests/gates/frontend/slice_read_left_operand.sh — 6.7.8 (C2-1b)
#
# A SLICE SUBSCRIPT IS A WHOLE VALUE. The slice read `s[i]` (`_slice_sub_read`,
# src/frontend/parse_expr.cyr) parsed its index, called `_slice_idx_get_W(&s, i)` and returned with
# the INDEX's state still describing the factor (6.7.5 - 6.7.7, every target): a constant index left
# the constant folder armed, so `s[0] + 10` folded `0 + 10` and rewound the code to the index's load
# — the call vanished and its fixup patched the return's jump into a jump to the helper (exit 134
# "slice bounds violation", or SIGSEGV); a `*T` index left its pointer step (`s[ix()] + 1` added 4);
# a struct-typed index its type (`s[n] + 10` dispatched `Idx_add`); and the syscall builtin read the
# index as a literal syscall number (`syscall(s[0], 7)` warned "syscall 0 ... not routed" on PE).
# The read now ends with `_arr_sub_read`'s resets: step 0, estype 0, `_cfo` 0.
#
#   R  the filed repro, by exit code: `return s[0] + 10;` 15 (was 134), `var y = s[0] + 10;` 15 and
#      `return s[1] * 2;` 12 (were SIGSEGV); the three right-before-the-fix forms as controls
#   P  `syscall(s[0], 7)` with s[0] = 60 for PE: no "syscall 0" warning at the call; exits 7 (wine)
#   A  tests/tcyr/crossos/slice_read_left_operand.tcyr with its full assertion count (every operator
#      class, every element width, the index shapes, every position) on x86 (plain, CYRIUS_IR=1,
#      CYRIUS_IR=3, CYRIUS_DCE=1), aarch64 (qemu), cx (cxvm) and PE (wine)
#
# MUTATION LEDGER (scratch trees, each rebuilt with the one change, run as CYCC=<mutant>; 2026-10-10):
#   M0 the 6.7.7 read (none of the three resets)  -> RED R1 R2 R3 P1 and A1-A7: x86 134 (IR=1, IR=3 too),
#                                                    DCE=1 "corrupted 2 live function bodies", aarch64
#                                                    139, cx "got 10, expected 15" (R1), PE exit 5
#   M1 `_slice_sub_read` without `_cfo = 0`       -> RED R1 R2 R3 (134 / 139 / 139), P1 (warns "syscall
#                                                    0"), A1-A7 (as M0)
#   M2 `_slice_sub_read` without `SPSC(S, 0)`     -> RED A1-A7 (tcyr I9: s[ix()] + 1 is 16)
#   M3 `_slice_sub_read` without `SESTYPE(S, 0)`  -> RED A1-A7 (tcyr I10: s[n] + 10 is 99, Idx_add)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=slice_read_left_operand
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
wine_run() {   # <dir> <exe>: run under the private prefix; sets got
    got=0
    (cd "$1" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
        WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$2" > "$1/$2.out" 2>/dev/null) || got=$?
}
HAVE_WINE=0
if command -v wine > /dev/null 2>&1; then HAVE_WINE=1
else echo "  SKIP P2 / A7: PE run legs — wine not installed"; skips=$((skips + 1)); fi

# ── R: the filed repro ─────────────────────────────────────────────────────────────────────────
HD='include "lib/slice.cyr"\nfn main(): i64 {\n    var b: i64[4];\n    b[0] = 5; b[1] = 6;\n    var s: [i64] = 0;\n    slice_set(&s, &b, 4);\n'
TL='}\nvar rc = main();\nsyscall(60, rc);\n'
exits() {   # <name> <want> <what> <body>
    printf '%b' "$HD$4$TL" > "$T/$1.cyr"
    rc=0; timeout 60 "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; timeout 10 "$T/$1.bin" > /dev/null 2>&1 || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}
exits r1 15 "R1: return s[0] + 10; (was 134, slice bounds violation)" '    return s[0] + 10;\n'
exits r2 15 "R2: var y = s[0] + 10; (was SIGSEGV)" '    var y = s[0] + 10;\n    return y;\n'
exits r3 12 "R3: return s[1] * 2; (was SIGSEGV)" '    return s[1] * 2;\n'
exits r4 15 "R4: control: return 10 + s[0];" '    return 10 + s[0];\n'
exits r5 15 "R5: control: return (s[0]) + 10;" '    return (s[0]) + 10;\n'
exits r6 15 "R6: control: var x = s[0]; return x + 10;" '    var x = s[0];\n    return x + 10;\n'

# ── P: the syscall builtin's literal-number reader (PE) ────────────────────────────────────────
printf '%b' 'include "lib/slice.cyr"\nfn main(): i64 {\n    var b: i64[4];\n    b[0] = 60; b[1] = 6;\n    var s: [i64] = 0;\n    slice_set(&s, &b, 4);\n    syscall(s[0], 7);\n    return 3;\n}\nvar rc = main();\nsyscall(60, rc);\n' > "$T/p1.cyr"
rc=0; CYRIUS_TARGET_WIN=1 timeout 60 "$CC" < "$T/p1.cyr" > "$T/p1.exe" 2> "$T/p1.err" || rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$T/p1.exe" ]; then bad "P1: the PE probe did not build (rc $rc): $(grep '^error' "$T/p1.err" | head -1)"
else
    if grep '^warning:<source>:7:' "$T/p1.err" | grep -q 'syscall 0 '; then
        bad "P1: syscall(s[0], 7) was read as the literal syscall 0: $(grep '^warning:<source>:7:' "$T/p1.err" | head -1)"
    else ok "P1: syscall(s[0], 7) on PE: no literal-number warning at the call"; fi
    if [ "$HAVE_WINE" -eq 1 ]; then
        wine_run "$T" p1.exe
        if [ "$got" -eq 7 ]; then ok "P2: ... exits 7 under wine"; else bad "P2: exit $got under wine, want 7"; fi
    fi
fi

# ── A: the values file on every leg ────────────────────────────────────────────────────────────
TC="$ROOT/tests/tcyr/crossos/slice_read_left_operand.tcyr"
[ -f "$TC" ] || { echo "FAIL: $G: $TC missing"; exit 1; }
WANT=$(grep -cE '^ *assert_eq\(' "$TC" || true)
if [ "$WANT" -lt 114 ]; then bad "A0: only $WANT assertions derived from $(basename "$TC") (floor 114)"; fi
tcyr_ok() {   # <label> <output file> <exit>
    if [ "$3" -eq 0 ] && grep -q "^$WANT passed, 0 failed" "$2"; then ok "$1: $WANT passed"
    else bad "$1: exit $3, $(grep -E 'passed|FAIL|error|violation' "$2" | tr -d '\r' | head -3 | tr '\n' '|')"; fi
}
for mode in plain IR1 IR3 DCE; do
    case $mode in
        plain) env_=""; lbl="A1: x86" ;;
        IR1) env_="CYRIUS_IR=1"; lbl="A2: x86, CYRIUS_IR=1" ;;
        IR3) env_="CYRIUS_IR=3"; lbl="A3: x86, CYRIUS_IR=3" ;;
        DCE) env_="CYRIUS_DCE=1"; lbl="A4: x86, CYRIUS_DCE=1" ;;
    esac
    rc=0; env $env_ "$CC" < "$TC" > "$T/a_$mode" 2> "$T/a_$mode.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "$lbl: rc $rc: $(grep '^error' "$T/a_$mode.err" | head -1)"; continue; fi
    chmod +x "$T/a_$mode"; got=0; timeout 60 "$T/a_$mode" > "$T/a_$mode.out" 2>&1 || got=$?
    tcyr_ok "$lbl" "$T/a_$mode.out" "$got"
done
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> "$T/cc_a64.err" && [ -s "$T/cc_a64" ]; then
        chmod +x "$T/cc_a64"
        if "$T/cc_a64" < "$TC" > "$T/a.a64" 2> "$T/a.a64.err" && [ -s "$T/a.a64" ]; then
            chmod +x "$T/a.a64"; got=0; (cd "$T" && timeout 120 qemu-aarch64 ./a.a64 > "$T/a.a64.out" 2>&1) || got=$?
            tcyr_ok "A5: aarch64 (qemu)" "$T/a.a64.out" "$got"
        else bad "A5: aarch64: the tcyr did not compile: $(grep '^error' "$T/a.a64.err" | head -1)"; fi
    else bad "A5: src/main_aarch64.cyr did not build"; fi
else echo "  SKIP A5: aarch64 leg — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
if "$CC" < src/main_cx.cyr > "$T/cc_cx" 2> "$T/cc_cx.err" && [ -s "$T/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/cxvm.err" && [ -s "$T/cxvm" ]; then
    chmod +x "$T/cc_cx" "$T/cxvm"
    if "$T/cc_cx" < "$TC" > "$T/a.cyx" 2> "$T/a.cyx.err" && [ -s "$T/a.cyx" ]; then
        got=0; timeout 120 "$T/cxvm" < "$T/a.cyx" > "$T/a.cyx.out" 2>&1 || got=$?
        tcyr_ok "A6: cx (cxvm)" "$T/a.cyx.out" "$got"
    else bad "A6: cx: the tcyr did not compile: $(grep '^error' "$T/a.cyx.err" | head -1)"; fi
else bad "A6: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
if [ "$HAVE_WINE" -eq 1 ]; then
    if CYRIUS_TARGET_WIN=1 "$CC" < "$TC" > "$T/a.exe" 2> "$T/a.exe.err" && [ -s "$T/a.exe" ]; then
        wine_run "$T" a.exe
        tcyr_ok "A7: PE (wine)" "$T/a.exe.out" "$got"
    else bad "A7: PE: the tcyr did not compile: $(grep '^error' "$T/a.exe.err" | head -1)"; fi
fi

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a slice read is a whole value as a left operand: the filed repro (R), the syscall-number reader (P), every operator / width / index shape / position on x86 / IR / DCE / aarch64 / cx / PE (A)"

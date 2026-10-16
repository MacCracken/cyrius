#!/bin/sh
# tests/gates/frontend/closure_capture_narrow_scalar.sh — 6.7.13 (Break 2, repair 3; the receives lane)
#
# A CLOSURE'S CAPTURE OF A NARROW SCALAR LOCAL (`i8` / `i16` / `i32`, `u8` / `u16` / `u32`) READS ITS VALUE
# (docs/development/issues/archived/2026-10-14-closure-capture-of-narrow-local-reads-unextended-word.md). A narrow local's
# frame slot holds its value only in its low 1 / 2 / 4 bytes; the closure's env copy (`_cl_emit_cap_word`,
# src/frontend/parse_expr.cyr) took the slot's whole raw word, and the closure reads the env word whole
# (`_cl_cap_load`, ELOAD64). So a captured `i8` holding -3 read 253 (65533 / 4294967293 at 16 / 32 bits) on every
# target, and on aarch64 / cx a positive value read the stale upper bytes a previous call left in the slot. Measured
# on the filed repro (expected `-3 -3 -3 7 7`), 6.6.0 through the 6.7.13 lane before this fix:
#   x86_64 (plain and CYRIUS_IR=3), PE (wine): 253 65533 4294967293 7 7
#   aarch64 (qemu): <garbage> 65533 4294967293 -249 -65529      cx (cxvm): 253 65533 4294967293 -249 -65529
# THE FIX (`_cl_cap_narrow`): a one-word capture of a narrow local is copied at its width, sign-extended for a signed
# one (`EFLLOAD_W`, as the local-read arm loads it), so the env word holds the value; a nested closure's re-copy
# reads that word. A narrow PARAMETER was always right (the controls).
#
# ROWS: R1-R5 the filed repro verbatim (its stdout) on x86_64 / CYRIUS_IR=3 / aarch64 (qemu — emulation, not
# hardware) / cx (cxvm) / PE (wine, a private prefix); T1-T5 tests/tcyr/crossos/closure_capture_narrow_scalar.tcyr on
# the same legs, each requiring exactly "N passed, 0 failed (N total)", N derived from the file (one per
# `assert_eq(`, floor 31); A0 (CYRIUS_ASYNC=1, x86) a non-suspending `async fn` capturing an `i8` local reads -3 (it
# read 253 too); A1 (CYRIUS_ASYNC=1) a narrow local in a suspending `async fn` stays refused by name. The release gate
# runs the .tcyr on ecb / ach / cass / pi.
#
# MUTATION LEDGER (2026-10-16; a scratch copy of src/ with the one edit, its cycc built from it, this gate run as
# CYCC=<mutant> — so the cross legs, built from the tree's src/, stay green except the x86-built PE leg):
#   the fix reverted (the lane's previous tip, fd3d5e61)  -> RED 7: R1 R2 R5, T1 T2 T5 (14 failed each), A0 (exit 1)
#   M-NC1 `_cl_cap_narrow` ignores the sign (`lw = lt`)    -> RED 7: R1 R2 R5, T1 T2 T5 (10 failed each), A0
#   M-NC2 `_cl_cap_narrow` sign-extends every width        -> RED 3: T1 T2 T5 (8 failed each: the u8 / u16 / u32 rows
#       over the signed range)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=closure_capture_narrow_scalar
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed"; exit 1; }
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
cd "$ROOT"
ulimit -c 0 2>/dev/null
fails=0
skips=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }

TC=tests/tcyr/crossos/closure_capture_narrow_scalar.tcyr
[ -f "$TC" ] || { echo "FAIL: $G: $TC is missing"; exit 1; }
TN=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TC")
FLOOR=31
if [ "$TN" -lt "$FLOOR" ]; then bad "T: only $TN rows in $TC (floor $FLOOR) — rows were lost"; fi

# The filed repro, verbatim.
cat > "$T/repro.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/fnptr.cyr"
fn neg8(): i64 { var b: i8 = 0 - 3; var k = |z| b + z; return callptr(k, 0); }
fn neg16(): i64 { var b: i16 = 0 - 3; var k = |z| b + z; return callptr(k, 0); }
fn neg32(): i64 { var b: i32 = 0 - 3; var k = |z| b + z; return callptr(k, 0); }
fn dirty(): i64 { var a = 0 - 1; var b = 0 - 1; var c = 0 - 1; var d = 0 - 1; var e = 0 - 1; return a + b + c + d + e; }
fn pos8(): i64 { var b: i8 = 5; var k = |z| b + z; return callptr(k, 2); }
fn pos16u(): i64 { var b: u16 = 5; var k = |z| b + z; return callptr(k, 2); }
fn main(): i64 {
    alloc_init();
    fmt_int(neg8()); syscall(1, 1, " ", 1);
    fmt_int(neg16()); syscall(1, 1, " ", 1);
    fmt_int(neg32()); syscall(1, 1, " ", 1);
    var x = dirty();
    fmt_int(pos8()); syscall(1, 1, " ", 1);
    x = dirty();
    fmt_int(pos16u()); syscall(1, 1, "\n", 1);
    return 0;
}
syscall(60, main());
# expected: -3 -3 -3 7 7
EOF
WANT='-3 -3 -3 7 7'

# <name> <compiler> <runner or ""> [ENV=V]: the repro's stdout must be WANT.
repro() {
    n=r_$(printf '%s' "$1" | tr -c 'a-zA-Z0-9' '_')
    rc=0
    if [ -n "${4:-}" ]; then env "$4" "$2" < "$T/repro.cyr" > "$T/$n" 2> "$T/$n.err" || rc=$?
    else "$2" < "$T/repro.cyr" > "$T/$n" 2> "$T/$n.err" || rc=$?; fi
    if [ "$rc" -ne 0 ] || [ ! -s "$T/$n" ]; then bad "$1: the repro did not build (rc $rc): $(grep '^error' "$T/$n.err" | head -1)"; return; fi
    chmod +x "$T/$n"
    got=""
    if [ -n "$3" ]; then got=$(timeout 120 $3 "$T/$n" 2>/dev/null | tr -d '\r')
    else got=$(timeout 30 "$T/$n" 2>/dev/null | tr -d '\r'); fi
    if [ "$got" = "$WANT" ]; then ok "$1: the filed repro prints '$got'"; else bad "$1: the filed repro printed '$got', want '$WANT'"; fi
}
# <name> <compiler> <runner or ""> [ENV=V]: the values file, exactly "TN passed, 0 failed (TN total)".
tcyr() {
    n=t_$(printf '%s' "$1" | tr -c 'a-zA-Z0-9' '_')
    rc=0
    if [ -n "${4:-}" ]; then env "$4" "$2" < "$TC" > "$T/$n" 2> "$T/$n.err" || rc=$?
    else "$2" < "$TC" > "$T/$n" 2> "$T/$n.err" || rc=$?; fi
    if [ "$rc" -ne 0 ] || [ ! -s "$T/$n" ]; then bad "$1: the values file did not build (rc $rc): $(grep '^error' "$T/$n.err" | head -1)"; return; fi
    chmod +x "$T/$n"
    got=0
    if [ -n "$3" ]; then timeout 120 $3 "$T/$n" > "$T/$n.out" 2>&1 || got=$?
    else timeout 60 "$T/$n" > "$T/$n.out" 2>&1 || got=$?; fi
    if [ "$got" -eq 0 ] && tr -d '\r' < "$T/$n.out" | grep -qx "$TN passed, 0 failed ($TN total)"; then ok "$1: $TN passed, 0 failed"
    else bad "$1: exit $got, want '$TN passed, 0 failed ($TN total)': $(tr -d '\r' < "$T/$n.out" | grep -E 'FAIL|failed' | head -3 | tr '\n' '|')"; fi
}

repro "R1: x86_64" "$CC" ""
repro "R2: CYRIUS_IR=3" "$CC" "" CYRIUS_IR=3
tcyr "T1: x86_64" "$CC" ""
tcyr "T2: CYRIUS_IR=3" "$CC" "" CYRIUS_IR=3

if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> "$T/cc_a64.err" && [ -s "$T/cc_a64" ]; then
        chmod +x "$T/cc_a64"
        repro "R3: aarch64 (qemu)" "$T/cc_a64" qemu-aarch64
        tcyr "T3: aarch64 (qemu)" "$T/cc_a64" qemu-aarch64
    else bad "R3 / T3: src/main_aarch64.cyr did not build"; fi
else echo "  SKIP: aarch64 legs R3 / T3 (qemu-aarch64 not installed)"; skips=$((skips + 1)); fi

if "$CC" < src/main_cx.cyr > "$T/cc_cx" 2> "$T/cc_cx.err" && [ -s "$T/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/cxvm.err" && [ -s "$T/cxvm" ]; then
    chmod +x "$T/cc_cx" "$T/cxvm"
    printf '#!/bin/sh\nexec "%s" < "$1"\n' "$T/cxvm" > "$T/cxrun"; chmod +x "$T/cxrun"
    repro "R4: cx (cxvm)" "$T/cc_cx" "$T/cxrun"
    tcyr "T4: cx (cxvm)" "$T/cc_cx" "$T/cxrun"
else bad "R4 / T4: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi

if command -v wine > /dev/null 2>&1; then
    printf '#!/bin/sh\ncp "$1" "$1.exe" || exit 1\ncd "%s" && WINEPREFIX="%s" HOME="%s" XDG_CACHE_HOME="%s/.cache" WINEDEBUG=-all WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d" exec wine "$1.exe"\n' \
        "$T" "$WP" "$WHM" "$WHM" > "$T/winrun"; chmod +x "$T/winrun"
    repro "R5: PE (wine)" "$CC" "$T/winrun" CYRIUS_TARGET_WIN=1
    tcyr "T5: PE (wine)" "$CC" "$T/winrun" CYRIUS_TARGET_WIN=1
else echo "  SKIP: PE legs R5 / T5 (wine not installed)"; skips=$((skips + 1)); fi

# A0 / A1 — CYRIUS_ASYNC=1 on the host.
ASH='include "lib/alloc.cyr"\ninclude "lib/string.cyr"\ninclude "lib/fmt.cyr"\ninclude "lib/vec.cyr"\ninclude "lib/syscalls.cyr"\ninclude "lib/async.cyr"\ninclude "lib/fnptr.cyr"\n'
printf '%b' "${ASH}async fn ac(): i64 { var b: i8 = 0 - 3; var k = |z| b + z; if (callptr(k, 0) == 0 - 3) { return 42; } return 1; }\nfn main(): i64 { alloc_init(); var f = ac(); return future_force(f); }\nsyscall(60, main());\n" > "$T/a0.cyr"
rc=0; CYRIUS_ASYNC=1 "$CC" < "$T/a0.cyr" > "$T/a0" 2> "$T/a0.err" || rc=$?
if [ "$rc" -ne 0 ]; then bad "A0: a non-suspending async fn's captured i8 did not build (rc $rc): $(grep '^error' "$T/a0.err" | head -1)"
else
    chmod +x "$T/a0"; got=0; timeout 10 "$T/a0" > /dev/null 2>&1 || got=$?
    if [ "$got" -eq 42 ]; then ok "A0: a non-suspending async fn's captured i8 reads -3 (exit 42)"; else bad "A0: a non-suspending async fn's captured i8: exit $got, want 42 (1: not -3)"; fi
fi
printf '%b' "${ASH}fn nopark(): i64 { return 0; }\nasync fn ac(): i64 { var b: i8 = 0 - 3; var k = |z| b + z; var w = await nopark(); return callptr(k, 0) + w; }\nfn main(): i64 { alloc_init(); var f = ac(); return future_force(f); }\nsyscall(60, main() & 255);\n" > "$T/a1.cyr"
rc=0; CYRIUS_ASYNC=1 "$CC" < "$T/a1.cyr" > "$T/a1" 2> "$T/a1.err" || rc=$?
if [ "$rc" -eq 0 ]; then bad "A1: a narrow local in a suspending async fn BUILT (rc 0)"
elif grep -qF 'a sub-word local in an `async fn` is not supported yet' "$T/a1.err"; then ok "A1: a narrow local in a suspending async fn stays refused by name"
else bad "A1: refused, but not by name: $(grep '^error' "$T/a1.err" | head -1)"; fi

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a captured narrow local (i8 .. u32) reads its value: the filed repro and $TN rows on x86_64 / IR=3 / aarch64 / cx / PE; async rows A0 / A1"

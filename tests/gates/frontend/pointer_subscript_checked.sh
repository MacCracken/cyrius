#!/bin/sh
# tests/gates/frontend/pointer_subscript_checked.sh — 6.7.8 (C2)
#
# What a subscript `x[i]` is, and the shapes it refuses by name. 6.7.8's C2 lane grows this gate
# bite by bite; its first group (C2-2a) is the slice bit.
#
# ST — A STALE SLICE WIDTH IS NO SLICE (C2-2a). A slice local's element width lives in the per-slot
# slice-width table, which most registrations never clear — a fn parameter, a closure parameter —
# so a slot inherited the width of whatever slice last sat there, in ANY earlier fn. An untyped
# parameter then compiled AS A SLICE (6.7.7 and before): `fn b(x, y) { return y[0]; }` read through
# `&y` as a slice header (exit 7 for a buffer holding 7), `y.len` read the frame word above `y`,
# `y.len = 5` wrote it, and the valid `y += 1` was refused as "compound assignment to slice 'y'".
# A slice is now marked by bit 62 of the slot's depth word (SLSLICE, util.cyr), which clears itself
# at the next registration's SLDEP; every slice reader asks `_slice_lw` (parse_types.cyr), which
# trusts the width only behind the bit.
#   ST1  `y[0]` on an untyped parameter after a slice local in an earlier fn: refused (today's
#        "cannot subscript 'y'"), one error line; ST1b the same on a third parameter's slot
#   ST2  `y.len` / `y.len = 5` / `y.ptr = 5`: the non-struct text, one error line
#   ST3  a closure parameter: `|x, p| p[0]` and `|x, p| p.len`: refused, one error line
#   ST4  real slices still read, `.len`, `.ptr`, `.len =`, `.ptr =`: after parameters, in a
#        closure's own body, in a fn after a closure was made (the snapshot restore), after a closed
#        block, in a generic instance, a `slice<T>` spelling, and a 256-byte struct element (its
#        width passes 255) — on x86 (plain, CYRIUS_IR=3), aarch64 (qemu), cx (cxvm) and PE (wine)
#   ST5  `y += 1` on an untyped parameter compiles and runs (7; it was refused as a slice)
#   ST6  a real slice keeps its slice refusals: `s += 1`, `s, x = f2();`, `(s, 1)` — anti-vacuous
#        for the three readers whose answer no ST1-ST3 row reaches
#
# MUTATION LEDGER (scratch trees, each rebuilt with the one change, run as CYCC=<mutant>; 2026-10-10):
#   M1  `_slice_lw` ignores bit 62 (returns the width)  -> RED ST1 ST1b ST2 ST2b ST2c ST3 ST3b ST5
#   M1b SLSLICE never sets bit 62                       -> RED ST4a-e (`cannot subscript 's'`), ST6
#                                                          ST6b ST6c (read as a u128)
#   M1c `_slice_lw` masks the width to a byte (& 0xFF)  -> RED ST4a-e (`s.len` on [Big]: no slice)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
G=pointer_subscript_checked
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

# refused <name> <fragment> <what> <body>: compile fails with exactly one error line holding the fragment
refused() {
    printf '%b' "$4" > "$T/$1.cyr"
    rc=0; timeout 60 "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    n=$(grep -c '^error' "$T/$1.err" || true)
    if [ "$rc" -eq 0 ]; then bad "$3: compiled (rc 0) — want the refusal \"$2\""
    elif [ "$n" -ne 1 ]; then bad "$3: $n error lines, want exactly 1: $(grep '^error' "$T/$1.err" | head -3 | tr '\n' '|')"
    elif grep '^error' "$T/$1.err" | grep -qF "$2"; then ok "$3"
    else bad "$3: wrong refusal: $(grep '^error' "$T/$1.err" | head -1)"; fi
}
# exits <name> <want> <what> <body>: compiles and exits <want>
exits() {
    printf '%b' "$4" > "$T/$1.cyr"
    rc=0; timeout 60 "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"; got=0; timeout 10 "$T/$1.bin" > /dev/null 2>&1 || got=$?
    if [ "$got" -eq "$2" ]; then ok "$3: exit $got"; else bad "$3: exit $got, want $2"; fi
}

# ── ST: a stale slice width is no slice ───────────────────────────────────────────────────────
# `a`'s slice sits in slots 0 (the nameless high half) and 1 (the canonical slot) — `y`'s slot in b.
SA='include "lib/slice.cyr"\nfn a() { var s: [i64] = 0; return 0; }\n'
BUF='var buf[16];\nstore64(&buf, 7);\n'
refused st1 "cannot subscript 'y'" "ST1: y[0] on an untyped parameter after a slice local (was a slice read, exit 7)" \
    "${SA}fn b(x, y) { return y[0]; }\n${BUF}var r = b(1, &buf);\nsyscall(60, r);\n"
refused st1b "cannot subscript 'z'" "ST1b: z[1] on a third parameter's slot (a slice after a parameter)" \
    'include "lib/slice.cyr"\nfn a(p) { var s: [u8] = 0; return p; }\nfn b(x, y, z) { return z[1]; }\nvar buf[16];\nvar r = b(1, 2, &buf);\nsyscall(60, r);\n'
refused st2 "no struct type in scope for 'y'" "ST2: y.len on an untyped parameter (read the frame above y)" \
    "${SA}fn b(x, y) { return y.len; }\n${BUF}var r = b(1, &buf);\nsyscall(60, r);\n"
refused st2b "no struct type in scope for 'y'" "ST2b: y.len = 5 on an untyped parameter (wrote the frame)" \
    "${SA}fn b(x, y) { y.len = 5; return 0; }\n${BUF}var r = b(1, &buf);\nsyscall(60, r);\n"
refused st2c "no struct type in scope for 'y'" "ST2c: y.ptr = 5 on an untyped parameter" \
    "${SA}fn b(x, y) { y.ptr = 5; return 0; }\n${BUF}var r = b(1, &buf);\nsyscall(60, r);\n"
refused st3 "cannot subscript 'p'" "ST3: |x, p| p[0] — a closure parameter" \
    "${SA}fn b() { var k = |x, p| p[0]; ${BUF}return callptr(k, 1, &buf); }\nsyscall(60, b());\n"
refused st3b "no struct type in scope for 'p'" "ST3b: |x, p| p.len — a closure parameter" \
    "${SA}fn b() { var k = |x, p| p.len; ${BUF}return callptr(k, 1, &buf); }\nsyscall(60, b());\n"
exits st5 7 "ST5: y += 1 on an untyped parameter after a slice local (was refused as a slice)" \
    "${SA}fn b(x, y) { y += 1; return y; }\nvar r = b(1, 6);\nsyscall(60, r);\n"

# ST6: a REAL slice keeps the refusals of the readers no ST1-ST3 row reaches
SL='include "lib/slice.cyr"\nfn f2(): i64 { return (3, 4); }\nfn b(): i64 {\n    var w: i64[2];\n    var s: [i64] = 0;\n    slice_set(&s, &w, 2);\n    var x = 0;\n'
refused st6 "compound assignment to slice 's'" "ST6: s += 1 on a slice (_asg_wide_refused)" \
    "${SL}    s += 1;\n    return x;\n}\nsyscall(60, b());\n"
refused st6b "cannot re-assign slice 's'" "ST6b: s, x = f2(); (_masg_kind)" \
    "${SL}    s, x = f2();\n    return x;\n}\nsyscall(60, b());\n"
refused st6c "not a slice" "ST6c: var t = (s, 1); (_tup_wide_name)" \
    "${SL}    var t = (s, 1);\n    return x;\n}\nsyscall(60, b());\n"

# ST4: real slices on every registration path, on every leg (exit 0; else the failing check's number)
cat > "$T/st4.cyr" <<'EOF'
include "lib/slice.cyr"
# 256 B: a slice of Big has element width 256 (a byte mask on the width would read 0, no slice)
struct Big { f0; f1; f2; f3; f4; f5; f6; f7; f8; f9; f10; f11; f12; f13; f14; f15; f16; f17; f18; f19; f20; f21; f22; f23; f24; f25; f26; f27; f28; f29; f30; f31; }
fn after_params(a, b, c): i64 {
    var buf: i64[4];
    buf[0] = a;
    buf[1] = b;
    buf[2] = c;
    var s: [i64] = 0;
    slice_set(&s, &buf, 3);
    return s[0] + s[1] + s[2] + s.len;
}
fn closure_own(n): i64 {
    var k = |m| { var b: i64[2]; b[0] = m; b[1] = m + 1; var s: [i64] = 0; slice_set(&s, &b, 2); return s[1] + s.len; };
    return callptr(k, n);
}
fn after_closure(): i64 {
    var b: u8[4];
    b[0] = 10;
    b[1] = 20;
    b[2] = 30;
    var s: [u8] = 0;
    slice_set(&s, &b, 3);
    var k = |x, y| x + y;
    var t = callptr(k, 1, 2);
    return s[2] + s.len + t;
}
fn after_block(n): i64 {
    if (n > 0) { var t = n; n = t + 1; }
    var b: u16[2];
    b[0] = 400;
    b[1] = 500;
    var s: [u16] = 0;
    slice_set(&s, &b, 2);
    return s[1] + n;
}
fn gsum<T>(x: T): i64 {
    var b: i64[2];
    b[0] = 7;
    b[1] = 8;
    var s: [i64] = 0;
    slice_set(&s, &b, 2);
    return s[1] + s.len + x;
}
fn fields(): i64 {
    var b: i64[3];
    b[0] = 4;
    var s: [i64] = 0;
    slice_set(&s, &b, 3);
    s.len = 1;
    if (s.ptr != &b) { return 100; }
    s.ptr = &b;
    return s.len + s[0];
}
fn big(): i64 {
    var bg: Big;
    bg.f0 = 3;
    var s: [Big] = 0;
    slice_set(&s, &bg, 1);
    if (s.ptr != &bg) { return 100; }
    return s.len;
}
fn spelled(): i64 {
    var b: i32[2];
    b[0] = 6;
    b[1] = 9;
    var s: slice<i32> = 0;
    slice_set(&s, &b, 2);
    return s[1] + s.len;
}
fn main(): i64 {
    if (after_params(1, 2, 3) != 9) { return 1; }
    if (closure_own(5) != 8) { return 2; }
    if (after_closure() != 36) { return 3; }
    if (after_block(1) != 502) { return 4; }
    if (gsum<i64>(1) != 11) { return 6; }
    if (fields() != 5) { return 7; }
    if (big() != 1) { return 8; }
    if (spelled() != 11) { return 9; }
    return 0;
}
var rc = main();
syscall(60, rc);
EOF
st4_ok() {   # <label> <exit>
    if [ "$2" -eq 0 ]; then ok "$1: every real-slice check"; else bad "$1: exit $2 (the failing check's number)"; fi
}
for mode in plain IR3; do
    case $mode in
        plain) env_=""; lbl="ST4a: x86" ;;
        IR3) env_="CYRIUS_IR=3"; lbl="ST4b: x86, CYRIUS_IR=3" ;;
    esac
    rc=0; env $env_ "$CC" < "$T/st4.cyr" > "$T/st4_$mode" 2> "$T/st4_$mode.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "$lbl: rc $rc: $(grep '^error' "$T/st4_$mode.err" | head -1)"; continue; fi
    chmod +x "$T/st4_$mode"; got=0; timeout 30 "$T/st4_$mode" > /dev/null 2>&1 || got=$?
    st4_ok "$lbl" "$got"
done
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> "$T/cc_a64.err" && [ -s "$T/cc_a64" ]; then
        chmod +x "$T/cc_a64"
        if "$T/cc_a64" < "$T/st4.cyr" > "$T/st4.a64" 2> "$T/st4.a64.err" && [ -s "$T/st4.a64" ]; then
            chmod +x "$T/st4.a64"; got=0; (cd "$T" && timeout 60 qemu-aarch64 ./st4.a64 > /dev/null 2>&1) || got=$?
            st4_ok "ST4c: aarch64 (qemu)" "$got"
        else bad "ST4c: aarch64: did not compile: $(grep '^error' "$T/st4.a64.err" | head -1)"; fi
    else bad "ST4c: src/main_aarch64.cyr did not build"; fi
else echo "  SKIP ST4c: aarch64 leg — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
if "$CC" < src/main_cx.cyr > "$T/cc_cx" 2> "$T/cc_cx.err" && [ -s "$T/cc_cx" ] \
   && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/cxvm.err" && [ -s "$T/cxvm" ]; then
    chmod +x "$T/cc_cx" "$T/cxvm"
    if "$T/cc_cx" < "$T/st4.cyr" > "$T/st4.cyx" 2> "$T/st4.cyx.err" && [ -s "$T/st4.cyx" ]; then
        got=0; timeout 60 "$T/cxvm" < "$T/st4.cyx" > /dev/null 2>&1 || got=$?
        st4_ok "ST4d: cx (cxvm)" "$got"
    else bad "ST4d: cx: did not compile: $(grep '^error' "$T/st4.cyx.err" | head -1)"; fi
else bad "ST4d: src/main_cx.cyr or programs/cxvm.cyr did not build"; fi
if command -v wine > /dev/null 2>&1; then
    if CYRIUS_TARGET_WIN=1 "$CC" < "$T/st4.cyr" > "$T/st4.exe" 2> "$T/st4.exe.err" && [ -s "$T/st4.exe" ]; then
        got=0
        (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine ./st4.exe > /dev/null 2>&1) || got=$?
        st4_ok "ST4e: PE (wine)" "$got"
    else bad "ST4e: PE: did not compile: $(grep '^error' "$T/st4.exe.err" | head -1)"; fi
else echo "  SKIP ST4e: PE leg — wine not installed"; skips=$((skips + 1)); fi

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a stale slice width is no slice: untyped / closure parameters refused by name (ST1-ST3), y += 1 compiles (ST5), real slices on every registration path and leg (ST4) keep their refusals (ST6)"

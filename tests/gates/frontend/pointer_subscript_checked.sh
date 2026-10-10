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
#
# P / S0 — THE STEP WORD CARRIES THE ELEMENT KIND (C2-3a). A typed pointer's step (sizeof(T)) is
# all GPSC carried, and `*u8` / `*i8`, `*u32` / `*f32`, `*f64` / `*bool` / `*i64` share steps, so
# C2's `p[i]` and `*p` at the element's width had nothing to load by. The step is now stored and
# carried as one word, `ps | ed << 40` (the element descriptor, parse_decl.cyr `_ek_*`): the slot
# mark (locals, `p: *T` parameters, captures), a field's `_fld_ps`, a return's `_fn_rps`, a global's
# `_gv_ped` beside GVTYPE; an f64 / f32 / bool array records its kind in the descriptor. Nothing
# reads the kind yet — the corpus differential is byte-identical on every target — so these rows
# pin that it changes NOTHING: the readers that use the word as a number take its step.
#   P1  a difference of two pointers of one step and different kinds (`*u32 - *i32`, `*f64 -
#       *i64`, `*u8 - *i8`) is their element count, no new error             (in the PV program)
#   P2  an if-expression over two such pointers keeps the step; P2c different steps keep none
#   P3  `n + p` on a `*u8` / `*i8` (parameter, local, global, field, return) compiles to the bytes
#       of the untyped program — no `n * step` imul
#   P4  `p += 2` on a local, a global and a field, every kind                 (in the PV program)
#   P5  the PV program — typed declarations from another kind's pointer included — has no warning
#   PV  every kind (i8 .. u64, f32, f64, bool, a struct) on every source (local, parameter, global,
#       field, return, capture, if-expression, a generic instance's parameter and return): `p + 1`,
#       `2 + p`, `p - 1`, `(p + 3) - p`, `(p + 1) + 1`, `var q: *T = p + 2`, measured byte-exactly,
#       on x86 (plain, CYRIUS_IR=3), aarch64 (qemu), cx (cxvm) and PE (wine)
#   P6  `*u8` / `*i8` (and step-4, step-8 sets) redeclared globals fold; P6c a different step stays
#       refused
#   S0  `f64[2]` / `f32[4]`, `bool[2]` / `f64[2]`, `f32[2]` / `bool[1]` still fold; S0c / S0d an
#       integer element of the same size stays a different shape
#
# MUTATION LEDGER (C2-3a, scratch trees, 2-stage mutant cycc, the gate as CYCC=<mutant>; 2026-10-10):
#   M5  `_ptr_diff` compares the words                   -> RED P5 PVa-e (P1: "pointer difference
#                                                           of pointers with different element sizes")
#   M6  the if-expression merges the words               -> RED PVa-e (P2: +1 where +4 / +8 / +2)
#   M23 EPTR_SCALE multiplies by the word                -> RED PVa-e: every kind on every source
#                                                           (341 of 513 checks; the struct's kind is 0
#                                                           and passes) — each setter carries its kind;
#                                                           typed_pointer_step.tcyr exits 37 too
#   M24 `_gsgn_shape` keeps the kinds                    -> RED S0a S0b S0e
#   MP3 `_ptr_add` tests the word (`rs > 1`)             -> RED P3 (the imul path)
#   MIP `_int_plus_ptr` multiplies by the word           -> RED PVa-e (`2 + p`)
#   M23 + the factor's step-8 local arm writing the plain step (`_lt_spsc` reverted): 321 fail —
#       the i64 / u64 / f64 / bool LOCAL checks pass again (5 each): that arm is where their kind is set
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
# legs <name> <row> <what>: $T/<name>.cyr built and run on every leg — x86 (plain, CYRIUS_IR=3),
# aarch64 (qemu), cx (cxvm), PE (wine); exit 0 passes, else the exit (ST4: the failing check's
# number; an assert program: its failure count) and the program's first FAIL line. The cross
# compilers are built once, from this tree, by the compiler under test.
XCC=0
xcc() {
    [ "$XCC" -eq 0 ] || return 0
    XCC=1
    if command -v qemu-aarch64 > /dev/null 2>&1; then
        "$CC" < src/main_aarch64.cyr > "$T/cc_a64" 2> "$T/cc_a64.err" && [ -s "$T/cc_a64" ] && chmod +x "$T/cc_a64" || rm -f "$T/cc_a64"
    fi
    if "$CC" < src/main_cx.cyr > "$T/cc_cx" 2> "$T/cc_cx.err" && [ -s "$T/cc_cx" ] \
       && "$CC" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/cxvm.err" && [ -s "$T/cxvm" ]; then
        chmod +x "$T/cc_cx" "$T/cxvm"
    else rm -f "$T/cc_cx" "$T/cxvm"; fi
}
leg_ok() {   # <label> <exit> <what> <output file>
    if [ "$2" -eq 0 ]; then ok "$1: $3"
    else bad "$1: exit $2 $(grep -m1 'FAIL' "$4" 2> /dev/null || echo '(the failing check'"'"'s number)')"; fi
}
legs() {
    n=$1; r=$2; w=$3
    xcc
    for mode in plain IR3; do
        case $mode in
            plain) env_=""; lbl="${r}a: x86" ;;
            IR3) env_="CYRIUS_IR=3"; lbl="${r}b: x86, CYRIUS_IR=3" ;;
        esac
        rc=0; env $env_ "$CC" < "$T/$n.cyr" > "$T/${n}_$mode" 2> "$T/${n}_$mode.err" || rc=$?
        if [ "$rc" -ne 0 ]; then bad "$lbl: rc $rc: $(grep '^error' "$T/${n}_$mode.err" | head -1)"; continue; fi
        chmod +x "$T/${n}_$mode"; got=0; timeout 30 "$T/${n}_$mode" > "$T/${n}_$mode.out" 2>&1 || got=$?
        leg_ok "$lbl" "$got" "$w" "$T/${n}_$mode.out"
    done
    if ! command -v qemu-aarch64 > /dev/null 2>&1; then
        echo "  SKIP ${r}c: aarch64 leg — qemu-aarch64 not installed"; skips=$((skips + 1))
    elif [ ! -x "$T/cc_a64" ]; then bad "${r}c: src/main_aarch64.cyr did not build"
    elif "$T/cc_a64" < "$T/$n.cyr" > "$T/$n.a64" 2> "$T/$n.a64.err" && [ -s "$T/$n.a64" ]; then
        chmod +x "$T/$n.a64"; got=0; (cd "$T" && timeout 60 qemu-aarch64 "./$n.a64" > "$T/$n.a64.out" 2>&1) || got=$?
        leg_ok "${r}c: aarch64 (qemu)" "$got" "$w" "$T/$n.a64.out"
    else bad "${r}c: aarch64: did not compile: $(grep '^error' "$T/$n.a64.err" | head -1)"; fi
    if [ ! -x "$T/cc_cx" ]; then bad "${r}d: src/main_cx.cyr or programs/cxvm.cyr did not build"
    elif "$T/cc_cx" < "$T/$n.cyr" > "$T/$n.cyx" 2> "$T/$n.cyx.err" && [ -s "$T/$n.cyx" ]; then
        got=0; timeout 60 "$T/cxvm" < "$T/$n.cyx" > "$T/$n.cyx.out" 2>&1 || got=$?
        leg_ok "${r}d: cx (cxvm)" "$got" "$w" "$T/$n.cyx.out"
    else bad "${r}d: cx: did not compile: $(grep '^error' "$T/$n.cyx.err" | head -1)"; fi
    if ! command -v wine > /dev/null 2>&1; then
        echo "  SKIP ${r}e: PE leg — wine not installed"; skips=$((skips + 1))
    elif CYRIUS_TARGET_WIN=1 "$CC" < "$T/$n.cyr" > "$T/$n.exe" 2> "$T/$n.exe.err" && [ -s "$T/$n.exe" ]; then
        got=0
        (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$n.exe" > "$T/$n.exe.out" 2>&1) || got=$?
        leg_ok "${r}e: PE (wine)" "$got" "$w" "$T/$n.exe.out"
    else bad "${r}e: PE: did not compile: $(grep '^error' "$T/$n.exe.err" | head -1)"; fi
}
legs st4 ST4 "every real-slice check"

# ── P / S0: the step word carries the element kind (C2-3a) ────────────────────────────────────
# P1-P5 + the source x kind arithmetic: one assert program, generated — every element kind (i8 u8
# i16 u16 i32 u32 i64 u64 f32 f64 bool, and a 24-byte struct) on every pointer source (a local, a
# parameter, a global, a field, a `*T` return, a capture, an if-expression, a generic instance's
# parameter and return), each `p + 1`, `2 + p`, `p - 1`, `(p + 3) - p`, `(p + 1) + 1`, a typed
# `var q: *T = p + 2` and `p += 2` measured byte-exactly against `&pv_buf`. Address arithmetic only
# (nothing is dereferenced), so a leaked kind is a wrong number, never a fault.
pv_src() {   # <pointer expr> <label> <sizeof(T)>
    cat <<EOF
    a = $1 + 1;
    assert_eq(a - B, $3, "$2: p + 1");
    a = 2 + $1;
    assert_eq(a - B, 2 * $3, "$2: 2 + p");
    a = $1 - 1;
    assert_eq(a - B, 0 - $3, "$2: p - 1");
    a = ($1 + 3) - $1;
    assert_eq(a, 3, "$2: (p + 3) - p");
    a = ($1 + 1) + 1;
    assert_eq(a - B, 2 * $3, "$2: (p + 1) + 1");
EOF
}
pv_kind() {   # <T> <sizeof(T)>
    k=$1; s=$2
    cat <<EOF
struct PVH_$k { p: *$k; }
var PVG_$k: *$k = 0;
fn pvr_$k(): *$k { return &pv_buf; }
fn pvp_$k(p: *$k, c): i64 {
    var B = &pv_buf;
    var a = 0;
$(pv_src p "$k parameter" "$s")
$(pv_src "(if (c) { p } else { p })" "$k if-expression" "$s")
$(pv_src "pvr_$k()" "$k return" "$s")
    return 0;
}
fn pvl_$k(): i64 {
    var B = &pv_buf;
    var a = 0;
    var p: *$k = &pv_buf;
$(pv_src p "$k local" "$s")
    var q: *$k = p + 2;
    a = q;
    assert_eq(a - B, 2 * $s, "$k local: var q: *$k = p + 2");
    PVG_$k = &pv_buf;
$(pv_src "PVG_$k" "$k global" "$s")
    var h: PVH_$k;
    h.p = &pv_buf;
$(pv_src h.p "$k field" "$s")
    var k1 = || { var B1 = &pv_buf; var a1 = p + 1; return a1 - B1; };
    assert_eq(callptr(k1), $s, "$k capture: p + 1");
    var k2 = || { var B2 = &pv_buf; var a2 = 2 + p; return a2 - B2; };
    assert_eq(callptr(k2), 2 * $s, "$k capture: 2 + p");
    var k3 = || { return (p + 3) - p; };
    assert_eq(callptr(k3), 3, "$k capture: (p + 3) - p");
    p += 2;
    a = p;
    assert_eq(a - B, 2 * $s, "$k local: p += 2");
    PVG_$k += 2;
    a = PVG_$k;
    assert_eq(a - B, 2 * $s, "$k global: p += 2");
    h.p += 2;
    a = h.p;
    assert_eq(a - B, 2 * $s, "$k field: p += 2");
    return 0;
}
EOF
}
PVK="i8:1 u8:1 i16:2 u16:2 i32:4 u32:4 i64:8 u64:8 f32:4 f64:8 bool:8 Pt:24"
{
    printf 'include "lib/assert.cyr"\nstruct Pt { x; y; z; }\nvar pv_buf: i64[32];\n'
    for ks in $PVK; do pv_kind "${ks%%:*}" "${ks#*:}"; done
    cat <<EOF
fn pvg<T>(p: *T, s): i64 {
    var B = &pv_buf;
    var a = 0;
$(pv_src p "generic parameter" s)
    return 0;
}
fn pvgr<T>(): *T { return &pv_buf; }
fn pvgc<T>(s): i64 {
    var B = &pv_buf;
    var a = 0;
$(pv_src "pvgr<T>()" "generic return" s)
    return 0;
}
# P1 a difference of two pointers of one step and different kinds is their element count (no new
# error); P2 an if-expression over two such pointers keeps the step (P2c: different steps keep
# none, as before); P5 a typed declaration from one of another kind takes no warning.
fn pvmix(c, gf: *f64): i64 {
    var B = &pv_buf;
    var a = 0;
    var p32: *i32 = &pv_buf;
    var pu: *u32 = &pv_buf;
    pu = pu + 3;
    assert_eq(pu - p32, 3, "P1 *u32 - *i32 (locals)");
    PVG_i64 = &pv_buf;
    assert_eq((gf + 2) - PVG_i64, 2, "P1 *f64 parameter - *i64 global");
    var h: PVH_u8;
    h.p = &pv_buf;
    assert_eq((h.p + 5) - pvr_i8(), 5, "P1 *u8 field - *i8 return");
    a = (if (c) { p32 } else { pu }) + 1;
    assert_eq(a - B, 4, "P2 (if (c) { *i32 } else { *u32 }) + 1");
    a = (if (c) { gf } else { PVG_i64 }) + 1;
    assert_eq(a - B, 8, "P2 (if (c) { *f64 } else { *i64 }) + 1");
    a = (if (c) { pvr_u16() } else { pvr_i16() }) + 1;
    assert_eq(a - B, 2, "P2 (if (c) { *u16 call } else { *i16 call }) + 1");
    var p16: *i16 = &pv_buf;
    a = (if (c) { p32 } else { p16 }) + 1;
    assert_eq(a - B, 1, "P2c (if (c) { *i32 } else { *i16 }) + 1: no step");
    var qx: *u32 = p32 + 1;
    a = qx;
    assert_eq(a - B, 4, "P5 var q: *u32 = (*i32) + 1");
    var qf: *f32 = pu - 3;
    a = qf;
    assert_eq(a - B, 0, "P5 var q: *f32 = (*u32) - 3");
    return 0;
}
alloc_init();
EOF
    for ks in $PVK; do k=${ks%%:*}; printf 'pvp_%s(&pv_buf, 1);\npvl_%s();\n' "$k" "$k"; done
    for ks in i8:1 i16:2 i32:4 i64:8 f64:8 Pt:24; do
        printf 'pvg<%s>(&pv_buf, %s);\npvgc<%s>(%s);\n' "${ks%%:*}" "${ks#*:}" "${ks%%:*}" "${ks#*:}"
    done
    printf 'pvmix(1, &pv_buf);\nsyscall(60, assert_summary());\n'
} > "$T/pv.cyr"
# P5: no declaration of the program warns (`assigning non-pointer to typed pointer` and the like)
rc=0; "$CC" < "$T/pv.cyr" > "$T/pv.chk" 2> "$T/pv.chk.err" || rc=$?
nw=$(grep -c '^warning\|^error' "$T/pv.chk.err" || true)
if [ "$rc" -eq 0 ] && [ "$nw" -eq 0 ]; then ok "P5: the step-word program compiles with no warning ($(grep -c 'assert_eq' "$T/pv.cyr") checks)"
else bad "P5: rc $rc, $nw diagnostic line(s): $(grep '^warning\|^error' "$T/pv.chk.err" | head -2 | tr '\n' '|')"; fi
legs pv PV "every source x kind step, P1 P2 P4 P5"

# P3: `n + p` on a 1-byte pointee is a plain add on every source — byte-identical to the same
# program with untyped pointers (a kind read as part of the step took 6.6.17's `n * step` imul path).
p3_gen() {   # <pointer annotation> <return annotation>
    printf 'var b: i64[2];\nvar G%s = 0;\nstruct H { p%s; }\nfn r()%s { return &b; }\nfn f(n, p%s): i64 { var q%s = &b; var h: H; h.p = &b; G = &b; return (n + p) + (n + q) + (n + G) + (n + h.p) + (n + r()); }\nsyscall(60, f(3, &b) - 5 * &b);\n' "$1" "$1" "$2" "$1" "$1"
}
p3_gen "" ": i64" > "$T/p3u.cyr"
p3_gen ": *u8" ": *u8" > "$T/p3t.cyr"
p3_gen ": *i8" ": *i8" > "$T/p3s.cyr"
rc=0
"$CC" < "$T/p3u.cyr" > "$T/p3u.bin" 2> /dev/null || rc=1
"$CC" < "$T/p3t.cyr" > "$T/p3t.bin" 2> /dev/null || rc=1
"$CC" < "$T/p3s.cyr" > "$T/p3s.bin" 2> /dev/null || rc=1
if [ "$rc" -ne 0 ]; then bad "P3: a variant did not compile"
elif cmp -s "$T/p3u.bin" "$T/p3t.bin" && cmp -s "$T/p3u.bin" "$T/p3s.bin"; then
    chmod +x "$T/p3t.bin"; got=0; timeout 10 "$T/p3t.bin" > /dev/null 2>&1 || got=$?
    if [ "$got" -eq 15 ]; then ok "P3: n + p on *u8 / *i8 (parameter, local, global, field, return) == untyped, bytes and value (15)"
    else bad "P3: exit $got, want 15"; fi
else bad "P3: n + p on a *u8 / *i8 differs from the untyped program (the kind took the imul path)"; fi

# P6: a `*T` global redeclared with another kind of the same step folds into one global (the kind
# is no shape: `_gv_ped` beside GVTYPE); a different step stays refused (P6c, anti-vacuous).
exits p6 3 "P6: var G: *u8 / var G: *i8 fold (G + 3 steps 1)" \
    'var buf: i64[2];\nvar G: *u8 = 0;\nvar G: *i8 = 0;\nfn f(): i64 { G = &buf; var a = G + 3; return a - &buf; }\nsyscall(60, f());\n'
exits p6b 12 "P6b: *u32 / *f32 / *i32 fold (step 4)" \
    'var buf: i64[2];\nvar G: *u32 = 0;\nvar G: *f32 = 0;\nvar G: *i32 = 0;\nfn f(): i64 { G = &buf; var a = G + 3; return a - &buf; }\nsyscall(60, f());\n'
exits p6d 24 "P6d: *f64 / *bool / *u64 fold (step 8)" \
    'var buf: i64[2];\nvar G: *f64 = 0;\nvar G: *bool = 0;\nvar G: *u64 = 0;\nfn f(): i64 { G = &buf; var a = G + 3; return a - &buf; }\nsyscall(60, f());\n'
refused p6c "global 'G' redeclared with a different type or size" "P6c: *u8 then *u16 stays refused" \
    'var buf: i64[2];\nvar G: *u8 = 0;\nvar G: *u16 = 0;\nsyscall(60, 0);\n'

# S0: an f64 / f32 / bool array records its kind in the descriptor, which the redeclaration fold
# reads through `_ek_legacy` — `f64[2]` / `f32[4]` / `bool[2]` (16 B each) fold as in 6.7.6; an
# integer element of the same size stays a different shape (S0c, S0d: anti-vacuous).
exits s0a 7 "S0a: f64[2] then f32[4] fold" 'var A: f64[2];\nvar A: f32[4];\nsyscall(60, 7);\n'
exits s0b 7 "S0b: bool[2] then f64[2] fold" 'var A: bool[2];\nvar A: f64[2];\nsyscall(60, 7);\n'
exits s0e 7 "S0e: f32[2] then bool[1] fold (8 B)" 'var A: f32[2];\nvar A: bool[1];\nsyscall(60, 7);\n'
refused s0c "global 'A' redeclared with a different type or size" "S0c: f64[2] then i64[2] stays refused" \
    'var A: f64[2];\nvar A: i64[2];\nsyscall(60, 7);\n'
refused s0d "global 'A' redeclared with a different type or size" "S0d: f32[4] then u32[4] stays refused" \
    'var A: f32[4];\nvar A: u32[4];\nsyscall(60, 7);\n'

if [ "$fails" -ne 0 ]; then echo "FAIL: $G — $fails row(s) red"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: $G — $skips leg(s) could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: $G — a stale slice width is no slice (ST1-ST6); the step word carries the element kind with no change to any step, difference, merge, warning or fold (P1-P6, PV legs, S0)"

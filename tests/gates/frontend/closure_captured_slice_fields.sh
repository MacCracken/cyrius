#!/bin/sh
# Gate: inside a closure, `s.len` / `s.ptr` of a captured slice read the captured copy (6.7.11).
#
# THE DEFECT (measured 6.6.0 - 6.7.10, every target):
#
#     var s: [u8] = 0;
#     slice_of(&s, &buf, 7);
#     var c = |x| s.len + x;          # error: undefined variable 's'   (expected: fncall1(c, 1) is 8)
#
# A closure captures by value, and 6.7.9 made a captured slice arrive in its env in field order
# (`slice_len(&s)` inside the closure read it — coroutine_midbody_suspend.sh axis 11). The dot
# syntax did not: PARSE_FIELD_LOAD's slice arm is a fn-LOCAL's (`_slice_lw`) and its capture arm
# (`_CL_CAP_FIELD_IDX`) takes a struct capture only, so `s.len` fell through to "undefined
# variable 's'" (+ "no struct type in scope for 's'"), naming a name that IS defined and captured.
#
# THE FIX (src/frontend/parse_decl.cyr `_cl_cslice_field`), the user's decision (a), 2026-10-13:
# `.ptr` / `.len` of a captured slice read the captured copy, one load from the env words (`.ptr`
# at +0, `.len` at +8). Any other field is "slice has only .ptr and .len fields", as on a local. A
# STORE (`s.len = v`, `s.ptr = p`, `s.len += 1`) into the captured copy is refused by name
# (`_cl_cslice_store_err`): the decision covers the reads, and a closure cannot assign a captured
# scalar either.
#
# ROWS: id|mode|want|source (printf %b; the prelude below is prepended). mode v: compiles, exits
# `want`. mode e: REFUSED, stderr carries `want` (a fixed string) exactly once and no "undefined
# variable". S / E rows were refused before the fix ("undefined variable 's'"); K rows are CONTROLS
# that held before and after. The filed repro (verbatim, exit 8) and the async row A1 (a closure
# built in a coroutine before and after its await reads the captured slice's fields: 122) run as
# their own files (A1 on the host: a mid-body `await` is x86-only so far).
#
# LEGS: host x86_64; cx via the tree's own main_cx + cxvm; aarch64 under qemu-aarch64 —
# EMULATION, not hardware. The fix is in the shared frontend, so every fork takes it.
#
# MUTATION LEDGER (6.7.11 — each mutant is a scratch copy of the tree whose src/ carries the
# change, built by build/cycc into the scratch tree's build/cycc, with this gate run from the
# scratch tree, so the cx and aarch64 legs are built from the mutated src too):
#   n0 the pre-fix src (both arms out)                -> RED S1-S6, E1-E4, the repro on every leg; A1 (46)
#   n1 the read arm dropped (`_cl_cslice_field`)       -> RED S1-S6, E1, the repro on every leg; A1 (28)
#   n2 `.len` read at +0 (the EADDRA_IMM dropped)      -> RED S2-S6 and the repro (the pointer's low
#                                                         byte) on every leg; A1 (19)
#   n3 the store refusal dropped                       -> RED E2-E4 ("undefined variable 's'") on every leg (18)
#   real tree                                          -> GREEN (49: 15 rows and the repro per leg, A1)
# (a count is FAIL lines: an E row that both misses its message and says "undefined variable" is two.)
#
# HALF 2 (6.7.12, the user's decision D29 (a), 2026-10-15): an untyped `var q = p;` of a struct VALUE
# is a typed copy, as `var q: P = p;` is. Through 6.7.11 q took p's FIRST WORD, so `q.y` was "no
# struct type in scope for 'q'" in a fn and "undefined variable 'q'" in a closure that captured q (the
# filed repro 2, verbatim below: exit 45), and `take(q)` passed the word as the struct's address.
# THE FIX (src/frontend/parse_decl.cyr `_uci_ps`, called by PARSE_VAR with no annotation): a name or
# a wrap `(name)` up to the `;` naming an inline struct local, a by-value struct parameter or a
# closure's captured copy of one gives the declaration the source's `0 - sid`, and it goes on as the
# annotated form. Q rows were refused before; QK rows are controls that held before and after (a
# `*T` source and an untyped impl `self` stay plain words, an untyped global keeps the word). The
# runtime rows are tests/tcyr/crossos/untyped_struct_name_copy.tcyr, run here on every leg (its row
# count derived, floor 25) and on ecb / ach / cass / pi by the release gate. The PE leg (wine, a
# private prefix) runs the repro 2, the Q / QK rows and the .tcyr.
# MUTATION LEDGER (6.7.12, measured the same way):
#   m1 PARSE_VAR's `_uci_ps` call dropped (D29 out)  -> RED Q1-Q9, repro 2 and the .tcyr on every leg (44)
#   m2 `_uci_cap` answers 0 (no captured source)      -> RED Q5, Q9 and the .tcyr on every leg (12)
#   m3 `_uci_cap`'s `*T` check dropped                 -> RED QK5 and the .tcyr on every leg (8)
#   real tree                                          -> GREEN (117: host 34, cx 33, aarch64 33, PE 17)
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: closure_captured_slice_fields: cannot cd to $ROOT"; exit 1; }
CC="${CYCC:-$ROOT/build/cycc}"
[ -x "$CC" ] || { echo "FAIL: closure_captured_slice_fields: $CC missing"; exit 1; }
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: closure_captured_slice_fields: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
ulimit -c 0 2>/dev/null || true
NFAIL=0
NROWS=0
bad() { echo "  FAIL: $1"; NFAIL=$((NFAIL + 1)); }

# build <compiler> <src> <out>: a failed compile or an empty output is a FAIL, never a silent
# pass (cycc on empty input still emits a runnable binary).
build() {
    if ! "$1" < "$2" > "$3" 2> "$3.err"; then return 1; fi
    [ -s "$3" ] || return 1
    return 0
}

cat > "$WORK/prelude" <<'PRE'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
include "lib/slice.cyr"
struct P { x; y; }
struct S8 { a: i32; b: i32; }
var g_buf[16];
PRE

cat > "$WORK/rows" <<'ROWS'
S1|v|11|fn main(): i64 { alloc_init(); var s: [u8] = 0; slice_of(&s, &g_buf, 7); var c = |x| (s.ptr == &g_buf) * 10 + x; return fncall1(c, 1); }\nsyscall(60, main());\n
S2|v|178|fn main(): i64 { alloc_init(); var a = 1; var p = P { 2, 3 }; var s: [u8] = 0; slice_of(&s, &g_buf, 7); var b = 4; var c = |x| a + s.len * 10 + (s.ptr == &g_buf) * 100 + p.y + b + x; return fncall1(c, 0); }\nsyscall(60, main());\n
S3|v|7|fn main(): i64 { alloc_init(); var s: [i64] = 0; slice_set(&s, &g_buf, 2); var c = || s.len + 5; return fncall0(c); }\nsyscall(60, main());\n
S4|v|89|fn main(): i64 { alloc_init(); var s: [u8] = 0; slice_of(&s, &g_buf, 7); var c = |x| s.len + x; slice_of(&s, &g_buf, 9); return fncall1(c, 1) * 10 + s.len; }\nsyscall(60, main());\n
S5|v|7|fn main(): i64 { alloc_init(); var s: [u8] = 0; slice_of(&s, &g_buf, 7); var c = || { var d = || s.len; return fncall0(d); }; return fncall0(c); }\nsyscall(60, main());\n
S6|v|5|fn main(): i64 { alloc_init(); var s: [u8] = 0; slice_of(&s, &g_buf, 7); var c = |x| { if (s.len > x) { return s.len - x; } return 0; }; return fncall1(c, 2); }\nsyscall(60, main());\n
E1|e|slice has only .ptr and .len fields|fn main(): i64 { alloc_init(); var s: [u8] = 0; slice_of(&s, &g_buf, 7); var c = |x| s.foo + x; return fncall1(c, 1); }\nsyscall(60, main());\n
E2|e|a closure cannot assign a field of the captured slice 's'|fn main(): i64 { alloc_init(); var s: [u8] = 0; slice_of(&s, &g_buf, 7); var c = |x| { s.len = x; return 0; }; return fncall1(c, 1); }\nsyscall(60, main());\n
E3|e|a closure cannot assign a field of the captured slice 's'|fn main(): i64 { alloc_init(); var s: [u8] = 0; slice_of(&s, &g_buf, 7); var c = |x| { s.ptr = 0; return x; }; return fncall1(c, 1); }\nsyscall(60, main());\n
E4|e|a closure cannot assign a field of the captured slice 's'|fn main(): i64 { alloc_init(); var s: [u8] = 0; slice_of(&s, &g_buf, 7); var c = |x| { s.len += x; return 0; }; return fncall1(c, 1); }\nsyscall(60, main());\n
K1|v|45|fn main(): i64 { alloc_init(); var p: P = P { 3, 4 }; var q: P = p; var c = |k| q.y + k; return fncall1(c, 1) + q.y * 10; }\nsyscall(60, main());\n
K2|v|6|fn main(): i64 { alloc_init(); var c = |x| { var t: [u8] = 0; slice_of(&t, &g_buf, 5); return t.len + x; }; return fncall1(c, 1); }\nsyscall(60, main());\n
K3|v|8|fn main(): i64 { alloc_init(); var s: [u8] = 0; slice_of(&s, &g_buf, 7); var c = |x| slice_len(&s) + x; return fncall1(c, 1); }\nsyscall(60, main());\n
K4|e|a closure cannot subscript a captured slice|fn main(): i64 { alloc_init(); var s: [u8] = 0; slice_of(&s, &g_buf, 7); var c = |x| s[0] + x; return fncall1(c, 1); }\nsyscall(60, main());\n
K5|v|73|fn main(): i64 { alloc_init(); var s: [u8] = 0; slice_of(&s, &g_buf, 7); s.len = 3; return s.len * 10 + (s.ptr == &g_buf) * 43; }\nsyscall(60, main());\n
Q1|v|4|fn main(): i64 { var p: P = P { 3, 4 }; var q = p; return q.y; }\nsyscall(60, main());\n
Q2|v|49|fn main(): i64 { var p: P = P { 3, 4 }; var q = p; q.y = 9; return p.y * 10 + q.y; }\nsyscall(60, main());\n
Q3|v|49|fn main(): i64 { var p: S8 = S8 { 3, 4 }; var q = p; q.b = 9; return p.b * 10 + q.b; }\nsyscall(60, main());\n
Q4|v|53|fn f(p: P): i64 { var q = p; q.y = 9; return p.y * 10 + q.y; }\nfn main(): i64 { var p: P = P { 3, 4 }; return f(p) + p.y; }\nsyscall(60, main());\n
Q5|v|5|fn main(): i64 { alloc_init(); var p: P = P { 3, 4 }; var c = |k| { var q = p; var d = |j| q.y + j; return fncall1(d, k); }; return fncall1(c, 1); }\nsyscall(60, main());\n
Q6|v|34|fn main(): i64 { var p: P = P { 3, 4 }; var q = (p); q.x = 1; return p.x * 10 + q.y; }\nsyscall(60, main());\n
Q7|v|4|fn tk(a: P): i64 { return a.y; }\nfn main(): i64 { var p: P = P { 3, 4 }; var q = p; return tk(q); }\nsyscall(60, main());\n
Q8|v|49|fn f(p: S8): i64 { var q = p; q.b = 9; return p.b * 10 + q.b; }\nfn main(): i64 { var p: S8 = S8 { 3, 4 }; return f(p); }\nsyscall(60, main());\n
Q9|v|49|fn f(p: P): i64 { var c = |k| { var q = p; q.y = 9; return p.y * 10 + q.y + k; }; return fncall1(c, 0); }\nfn main(): i64 { alloc_init(); var p: P = P { 3, 4 }; return f(p); }\nsyscall(60, main());\n
QK1|v|3|var G: P = P { 3, 4 };\nvar H = G;\nsyscall(60, H);\n
QK2|v|3|var G: P = P { 3, 4 };\nalloc_init();\nvar H = G;\nsyscall(60, H);\n
QK3|v|14|fn main(): i64 { var p: P = P { 3, 4 }; var pp: *P = &p; var q = pp; return (q == &p) * 10 + load64(q + 8); }\nsyscall(60, main());\n
QK4|v|4|impl P { fn sy(self): i64 { var q = self; return load64(q + 8); } }\nfn main(): i64 { var p: P = P { 3, 4 }; return p.sy(); }\nsyscall(60, main());\n
QK5|v|14|fn f(pp: *P): i64 { var c = |k| { var q = pp; return (q == pp) * 10 + load64(q + 8) + k; }; return fncall1(c, 0); }\nfn main(): i64 { alloc_init(); var p: P = P { 3, 4 }; return f(&p); }\nsyscall(60, main());\n
QK6|v|3|fn main(): i64 { var p: P = P { 3, 4 }; var q = p; return q; }\nsyscall(60, main());\n
ROWS
NTAB=$(grep -c '|' "$WORK/rows")

# The filed repro 1, verbatim.
cat > "$WORK/repro.cyr" <<'RP'
# 1 — a captured slice's field
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
include "lib/slice.cyr"
fn main(): i64 {
    alloc_init();
    var buf[16];
    var s: [u8] = 0;
    slice_of(&s, &buf, 7);
    var c = |x| s.len + x;
    return fncall1(c, 1);
}
syscall(60, main());
# error:<source>:10:23: undefined variable 's'      expected: exit 8
RP

# The filed repro 2 (half 2, D29), verbatim: exit 45.
cat > "$WORK/repro2.cyr" <<'RP2'
# 2 — an untyped struct copy's field
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
struct P { x; y; }
fn main(): i64 {
    alloc_init();
    var p: P = P { 3, 4 };
    var q = p;
    var c = |k| q.y + k;
    return fncall1(c, 1) + q.y * 10;
}
syscall(60, main());
# error:<source>:9:21: undefined variable 'q'      expected: exit 45
RP2
TC="$ROOT/tests/tcyr/crossos/untyped_struct_name_copy.tcyr"
[ -f "$TC" ] || { echo "FAIL: closure_captured_slice_fields: $TC is missing"; exit 1; }
# One row per `assert_eq(` call; the floor keeps a gutted file from passing.
NTC=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TC")
if [ "$NTC" -lt 25 ]; then echo "FAIL: closure_captured_slice_fields: only $NTC rows in $TC (floor 25)"; exit 1; fi

# A1: a closure built in a coroutine, after and before its await, reads the captured slice's
# fields (the axis-11 shape of coroutine_midbody_suspend.sh with the dot syntax): 71 + 51.
cat > "$WORK/a1.cyr" <<'A1'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"
include "lib/async.cyr"
include "lib/fnptr.cyr"
include "lib/slice.cyr"
var g_buf[16];
fn nopark(): i64 { return 0; }
fn trash(n) { var pad[512]; store64(&pad, 123456789); if (n > 0) { trash(n - 1); } return load64(&pad); }
fn run2(F): i64 { future_force(F); trash(40); return future_force(F); }
async fn after(n): i64 { var v: [u8] = 0; slice_set(&v, &g_buf, n); var s1 = await nopark(); var c = || v.len * 10 + (v.ptr == &g_buf); return fncall0(c); }
async fn before(n): i64 { var v: [u8] = 0; slice_set(&v, &g_buf, n); var c = || v.len * 10 + (v.ptr == &g_buf); var s1 = await nopark(); return fncall0(c); }
fn main(): i64 { alloc_init(); return run2(after(7)) + run2(before(5)); }
var e = main();
syscall(60, e);
A1

# run_bin <leg> <id> <runner> <bin> <want>
run_bin() {
    chmod +x "$4"
    set +e
    if [ -n "$3" ]; then $3 "$4" > /dev/null 2>&1
    else "$4" > /dev/null 2>&1; fi
    r=$?
    set -e
    [ "$r" = "$5" ] || bad "$1 row $2: exited $r, want $5"
    return 0
}

# run_row <leg> <compiler> <runner> <id> <mode> <want> <src> — runner is "" for native
run_row() {
    { cat "$WORK/prelude"; printf '%b' "$7"; } > "$WORK/t.cyr"
    if [ "$5" = e ]; then
        if build "$2" "$WORK/t.cyr" "$WORK/t.bin"; then
            bad "$1 row $4: compiled, want refused"; return 0
        fi
        n=$(grep -cF "$6" "$WORK/t.bin.err" || true)
        [ "$n" = 1 ] || bad "$1 row $4: '$6' $n time(s), want once: $(grep error "$WORK/t.bin.err" | head -2 | head -c 300)"
        if grep -q 'undefined variable' "$WORK/t.bin.err"; then bad "$1 row $4: says 'undefined variable'"; fi
        return 0
    fi
    if ! build "$2" "$WORK/t.cyr" "$WORK/t.bin"; then
        bad "$1 row $4: compile failed: $(grep error "$WORK/t.bin.err" | head -1 | head -c 300)"; return 0
    fi
    run_bin "$1" "$4" "$3" "$WORK/t.bin" "$6"
}

# run_tc <leg> <compiler> <runner>: the crossos .tcyr, "N passed, 0 failed (N total)" with N derived.
run_tc() {
    NROWS=$((NROWS + 1))
    if ! build "$2" "$TC" "$WORK/tc.bin"; then
        bad "$1 untyped_struct_name_copy.tcyr: compile failed: $(grep error "$WORK/tc.bin.err" | head -1 | head -c 300)"; return 0
    fi
    chmod +x "$WORK/tc.bin"
    set +e
    if [ -n "$3" ]; then $3 "$WORK/tc.bin" > "$WORK/tc.out" 2>&1
    else "$WORK/tc.bin" > "$WORK/tc.out" 2>&1; fi
    r=$?
    set -e
    last=$(tail -1 "$WORK/tc.out" | tr -d '\r')
    [ "$r" = 0 ] && [ "$last" = "$NTC passed, 0 failed ($NTC total)" ] \
        || bad "$1 untyped_struct_name_copy.tcyr: exit $r, '$last' (want $NTC passed)"
    return 0
}

# run_leg <leg> <compiler> <runner>
run_leg() {
    while IFS='|' read -r id mode want src; do
        NROWS=$((NROWS + 1))
        run_row "$1" "$2" "$3" "$id" "$mode" "$want" "$src"
    done < "$WORK/rows"
    NROWS=$((NROWS + 1))
    if build "$2" "$WORK/repro.cyr" "$WORK/rp.bin"; then run_bin "$1" repro "$3" "$WORK/rp.bin" 8
    else bad "$1 repro: compile failed: $(grep error "$WORK/rp.bin.err" | head -1 | head -c 300)"; fi
    NROWS=$((NROWS + 1))
    if build "$2" "$WORK/repro2.cyr" "$WORK/rp2.bin"; then run_bin "$1" repro2 "$3" "$WORK/rp2.bin" 45
    else bad "$1 repro2: compile failed: $(grep error "$WORK/rp2.bin.err" | head -1 | head -c 300)"; fi
    run_tc "$1" "$2" "$3"
    # A1 on the host only: a mid-body `await` is x86-only so far (aarch64 and cx refuse it by name).
    [ "$1" = host ] || return 0
    NROWS=$((NROWS + 1))
    if CYRIUS_ASYNC=1 build "$2" "$WORK/a1.cyr" "$WORK/a1.bin"; then run_bin "$1" A1 "$3" "$WORK/a1.bin" 122
    else bad "$1 row A1: compile failed: $(grep error "$WORK/a1.bin.err" | head -1 | head -c 300)"; fi
}

echo "host x86_64:"
run_leg host "$CC" ""

# ---- cx leg: the tree's own cx compiler + cxvm ----
echo "cx (cxvm):"
if build "$CC" "$ROOT/src/main_cx.cyr" "$WORK/cycc_cx" && build "$CC" "$ROOT/programs/cxvm.cyr" "$WORK/cxvm"; then
    chmod +x "$WORK/cycc_cx" "$WORK/cxvm"
    cxr() { timeout 60 "$WORK/cxvm" < "$1"; }
    run_leg cx "$WORK/cycc_cx" cxr
else
    bad "cx leg: could not build src/main_cx.cyr / programs/cxvm.cyr"
fi

# ---- aarch64 leg (qemu-aarch64, NOT hardware) ----
if command -v qemu-aarch64 > /dev/null 2>&1; then
    echo "aarch64 (qemu-aarch64 — emulation, not hardware):"
    if build "$CC" "$ROOT/src/main_aarch64.cyr" "$WORK/cycc_a64"; then
        chmod +x "$WORK/cycc_a64"
        a64r() { timeout 60 qemu-aarch64 "$1"; }
        run_leg aarch64 "$WORK/cycc_a64" a64r
    else
        bad "aarch64 leg: could not build src/main_aarch64.cyr"
    fi
else
    echo "  SKIP: qemu-aarch64 not installed (the pi hardware leg still covers the target)"
    GATE_SKIPS=$((${GATE_SKIPS:-0} + 1))
fi

# ---- PE leg (wine, a private prefix — never ~/.wine): the D29 rows, repro 2 and the .tcyr ----
WP="$WORK/wine"
_wine_down() {
    [ -d "$WP" ] || return 0
    WINEPREFIX="$WP" wineserver -k > /dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w > /dev/null 2>&1 || true
}
trap '_wine_down; rm -rf "$WORK"' EXIT
if command -v wine > /dev/null 2>&1; then
    echo "PE (wine):"
    pecc() { CYRIUS_TARGET_WIN=1 "$CC"; }
    per() {
        cp "$1" "$1.exe"
        (cd "$WORK" && WINEPREFIX="$WP" HOME="$WORK/whome" XDG_CACHE_HOME="$WORK/whome/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 300 wine "$1.exe")
    }
    pe_build() { CYRIUS_TARGET_WIN=1 build "$CC" "$1" "$2"; }
    grep '^Q' "$WORK/rows" > "$WORK/qrows"
    while IFS='|' read -r id mode want src; do
        NROWS=$((NROWS + 1))
        { cat "$WORK/prelude"; printf '%b' "$src"; } > "$WORK/t.cyr"
        if pe_build "$WORK/t.cyr" "$WORK/t.bin"; then run_bin pe "$id" per "$WORK/t.bin" "$want"
        else bad "pe row $id: compile failed: $(grep error "$WORK/t.bin.err" | head -1 | head -c 300)"; fi
    done < "$WORK/qrows"
    NROWS=$((NROWS + 1))
    if pe_build "$WORK/repro2.cyr" "$WORK/rp2.bin"; then run_bin pe repro2 per "$WORK/rp2.bin" 45
    else bad "pe repro2: compile failed: $(grep error "$WORK/rp2.bin.err" | head -1 | head -c 300)"; fi
    NROWS=$((NROWS + 1))
    if pe_build "$TC" "$WORK/tc.bin"; then
        set +e; per "$WORK/tc.bin" > "$WORK/tc.out" 2> /dev/null; r=$?; set -e
        last=$(tail -1 "$WORK/tc.out" | tr -d '\r')
        [ "$r" = 0 ] && [ "$last" = "$NTC passed, 0 failed ($NTC total)" ] \
            || bad "pe untyped_struct_name_copy.tcyr: exit $r, '$last' (want $NTC passed)"
    else bad "pe untyped_struct_name_copy.tcyr: compile failed: $(grep error "$WORK/tc.bin.err" | head -1 | head -c 300)"; fi
else
    echo "  SKIP: PE leg (wine not installed; cass covers PE at the release gate)"
    GATE_SKIPS=$((${GATE_SKIPS:-0} + 1))
fi

# Derived floor: the row table (30 rows), the two repros and the .tcyr on host + cx, A1 on the host,
# even with qemu and wine absent.
if [ "$NTAB" -lt 30 ]; then bad "the row table holds $NTAB rows (floor 30) — it did not load"; fi
if [ "$NROWS" -lt $(((NTAB + 3) * 2 + 1)) ]; then bad "only $NROWS rows ran (floor $(((NTAB + 3) * 2 + 1)))"; fi
if [ "$NFAIL" -ne 0 ]; then
    echo "FAIL: closure_captured_slice_fields ($NFAIL of $NROWS rows)"
    exit 1
fi
if [ "${GATE_SKIPS:-0}" -gt 0 ]; then echo "SKIP: closure_captured_slice_fields — $GATE_SKIPS leg(s) above could not run; every one that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: closure_captured_slice_fields ($NROWS rows)"

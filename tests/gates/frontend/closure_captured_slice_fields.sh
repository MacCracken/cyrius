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

# run_leg <leg> <compiler> <runner>
run_leg() {
    while IFS='|' read -r id mode want src; do
        NROWS=$((NROWS + 1))
        run_row "$1" "$2" "$3" "$id" "$mode" "$want" "$src"
    done < "$WORK/rows"
    NROWS=$((NROWS + 1))
    if build "$2" "$WORK/repro.cyr" "$WORK/rp.bin"; then run_bin "$1" repro "$3" "$WORK/rp.bin" 8
    else bad "$1 repro: compile failed: $(grep error "$WORK/rp.bin.err" | head -1 | head -c 300)"; fi
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

# Derived floor: the row table (15 rows) and the repro on host + cx, A1 on the host, even with
# qemu absent.
if [ "$NTAB" -lt 15 ]; then bad "the row table holds $NTAB rows (floor 15) — it did not load"; fi
if [ "$NROWS" -lt $(((NTAB + 1) * 2 + 1)) ]; then bad "only $NROWS rows ran (floor $(((NTAB + 1) * 2 + 1)))"; fi
if [ "$NFAIL" -ne 0 ]; then
    echo "FAIL: closure_captured_slice_fields ($NFAIL of $NROWS rows)"
    exit 1
fi
if [ "${GATE_SKIPS:-0}" -gt 0 ]; then echo "SKIP: closure_captured_slice_fields — $GATE_SKIPS leg(s) above could not run; every one that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: closure_captured_slice_fields ($NROWS rows)"

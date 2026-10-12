#!/bin/sh
# Gate: a field name inside a closure body is not a capture of the enclosing local of that name (6.7.9).
#
# THE DEFECT (measured 6.6.0 - 6.7.8, x86_64 and aarch64):
#
#     fn lit(): i64 { var y = 5; var cl = |n| { var p = Pt { x: n, y: 2 }; return p.x + 2; }; ... }
#     fn acc(): i64 { var y = 5; var cl = |n| { var p = Pt { n, 2 }; return p.y + 5; }; ... }
#
# Neither closure reads `y`, yet both were refused: "a capturing closure needs include
# "lib/alloc.cyr" for its heap env". The capture pre-scan (`_cl_prescan_ident`) took every
# identifier naming an enclosing local for a read; it skipped call names, `loop` and a named
# argument's label (6.7.7), not a field name after `.` nor a struct literal's field label. With
# lib/alloc.cyr included the value was right, but each such closure carried a heap env holding a
# copy of `y` it never read.
#
# THE FIX (src/frontend/parse_expr.cyr): two more exemptions. `_cl_is_field_name`: the name
# follows a `.` that is not the second dot of a range's `..` (`for i in 0..y` reads `y` — the
# lexer makes `..` two DOT tokens). `_cl_is_lit_label`: `IDENT :` right after a `{` or `,` whose
# innermost open bracket is a `{` that follows a struct name or a generic struct's `>`.
#
# ROWS: id|mode|want|source (printf %b; `include "lib/fnptr.cyr"` and `struct Pt { x; y; }` are
# prepended). mode n: no lib/alloc.cyr — the source compiles and exits `want`. mode a: with
# lib/alloc.cyr — it exits `want`. mode r: no lib/alloc.cyr — the source is REFUSED with exactly
# `want` "a capturing closure needs" errors (a real capture is still a capture).
# Rows R, L, D, E, C, G, N, F were refused before the fix (R twice); the K rows are CONTROLS that
# held before and after: K1-K4 a value after a label and a bare `y` beside `p.y` still capture
# (and capture by value: `y = 50` after construction is not seen), K5-K6 a range's `0..y` still
# captures `y` and does not read the global `y` (21, not 63).
#
# LEGS: host x86_64; cx via the tree's own main_cx + cxvm; aarch64 under qemu-aarch64 —
# EMULATION, not hardware. The fix is in the shared frontend, so every fork takes it.
#
# MUTATION LEDGER (6.7.9 — each mutant is a scratch copy of the tree whose src/ carries the
# change, built by build/cycc into the scratch tree's build/cycc, with this gate run from the
# scratch tree, so the cx and aarch64 legs are built from the mutated src too):
#   m0 the pre-fix src (this bite reverted)   -> RED R L D E C G N F on every leg, and the repro file
#                                                (25 of 46)
#   m1 `_cl_is_field_name` always 0            -> RED as m0 (25): every non-K row also reads a `.field`
#                                                named like an enclosing local
#   m2 `_cl_is_lit_label` always 0             -> RED R L G N on every leg, and the repro file (13)
#   m3 the `..` guard dropped                  -> RED K5 (compiles) and K6 (63) on every leg (6)
#   m4 the generic `>` literal head dropped    -> RED G on every leg (3)
#   real tree                                  -> GREEN (46: 15 rows per leg, and the repro file)
# A `{` that is no struct literal's never holds `IDENT :` after a `{` or `,` in valid source (a
# `case` value follows `case`; there is no ternary), so the struct-name test has no killing row.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: closure_field_names_not_captured: cannot cd to $ROOT"; exit 1; }
CC="${CYCC:-$ROOT/build/cycc}"
[ -x "$CC" ] || { echo "FAIL: closure_field_names_not_captured: $CC missing"; exit 1; }
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: closure_field_names_not_captured: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
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

cat > "$WORK/rows" <<'ROWS'
R|n|16|fn lit(): i64 { var y = 5; var cl = |n| { var p = Pt { x: n, y: 2 }; return p.x + 2; }; return fncall1(cl, 7); }\nfn acc(): i64 { var y = 5; var cl = |n| { var p = Pt { n, 2 }; return p.y + 5; }; return fncall1(cl, 7); }\nsyscall(60, lit() + acc());\n
L|n|9|fn f(): i64 { var y = 5; var x = 4; var cl = |n| { var p = Pt { x: n, y: 2 }; return p.x + 2; }; return fncall1(cl, 7); }\nsyscall(60, f());\n
D|n|7|fn f(): i64 { var y = 5; var cl = |n| { var p = Pt { n, 2 }; return p.y + 5; }; return fncall1(cl, 7); }\nsyscall(60, f());\n
E|n|9|var gp = Pt { 1, 2 };\nfn f(): i64 { var y = 5; var cl = |n| n + gp.y; return fncall1(cl, 7); }\nsyscall(60, f());\n
C|n|5|struct Ln { a: Pt; b; }\nfn f(): i64 { var a = 9; var y = 9; var b = 9; var cl = |n| { var l = Ln { n, 2, 3 }; return l.a.y + l.b; }; return fncall1(cl, 7); }\nsyscall(60, f());\n
G|n|9|struct Box<T> { v: T; w; }\nfn f(): i64 { var w = 5; var v = 6; var cl = |n| { var b = Box<i64> { v: n, w: 2 }; return b.v + b.w; }; return fncall1(cl, 7); }\nsyscall(60, f());\n
N|n|8|fn f(): i64 { var y = 5; var cl = |n| { var g = |m| { var p = Pt { x: m, y: 1 }; return p.x + p.y; }; return fncall1(g, n); }; return fncall1(cl, 7); }\nsyscall(60, f());\n
F|n|21|fn f(): i64 { var y = 5; var cl = |n| { var s = 0; var p = Pt { 1, 3 }; for i in 0..p.y { s = s + n; } return s; }; return fncall1(cl, 7); }\nsyscall(60, f());\n
K1|r|1|fn f(): i64 { var y = 5; var cl = |n| { var p = Pt { x: n, y: y }; return p.x + p.y; }; return fncall1(cl, 7); }\nsyscall(60, f());\n
K2|a|12|fn f(): i64 { alloc_init(); var y = 5; var cl = |n| { var p = Pt { x: n, y: y }; return p.x + p.y; }; y = 50; return fncall1(cl, 7); }\nsyscall(60, f());\n
K3|r|1|fn f(): i64 { var y = 5; var cl = |n| { var p = Pt { n, 2 }; return p.y + y; }; return fncall1(cl, 7); }\nsyscall(60, f());\n
K4|a|7|fn f(): i64 { alloc_init(); var y = 5; var cl = |n| { var p = Pt { n, 2 }; return p.y + y; }; y = 50; return fncall1(cl, 7); }\nsyscall(60, f());\n
K5|r|1|var y = 9;\nfn f(): i64 { var y = 3; var cl = |n| { var s = 0; for i in 0..y { s = s + n; } return s; }; return fncall1(cl, 7); }\nsyscall(60, f());\n
K6|a|21|var y = 9;\nfn f(): i64 { alloc_init(); var y = 3; var cl = |n| { var s = 0; for i in 0..y { s = s + n; } return s; }; return fncall1(cl, 7); }\nsyscall(60, f());\n
K7|a|19|fn f(): i64 { alloc_init(); var y = 5; var p = Pt { 4, 6 }; var cl = |n| n + p.x + p.y + y - 3; return fncall1(cl, 7); }\nsyscall(60, f());\n
ROWS
NTAB=$(grep -c '|' "$WORK/rows")

# run_row <leg> <compiler> <runner> <id> <mode> <want> <src> — runner is "" for native
run_row() {
    {
        printf 'include "lib/fnptr.cyr"\n'
        if [ "$5" = a ]; then printf 'include "lib/alloc.cyr"\n'; fi
        printf 'struct Pt { x; y; }\n'
        printf '%b' "$7"
    } > "$WORK/t.cyr"
    if [ "$5" = r ]; then
        if build "$2" "$WORK/t.cyr" "$WORK/t.bin"; then
            bad "$1 row $4: compiled, want refused (a real capture must still be one)"; return 0
        fi
        n=$(grep -c 'a capturing closure needs include "lib/alloc.cyr"' "$WORK/t.bin.err" || true)
        [ "$n" = "$6" ] || bad "$1 row $4: $n capture refusal(s), want $6: $(head -c 300 "$WORK/t.bin.err")"
        return 0
    fi
    if ! build "$2" "$WORK/t.cyr" "$WORK/t.bin"; then
        bad "$1 row $4: compile failed: $(grep error "$WORK/t.bin.err" | head -1 | head -c 300)"; return 0
    fi
    chmod +x "$WORK/t.bin"
    set +e
    if [ -n "$3" ]; then $3 "$WORK/t.bin" > /dev/null 2>&1
    else "$WORK/t.bin" > /dev/null 2>&1; fi
    r=$?
    set -e
    [ "$r" = "$6" ] || bad "$1 row $4: exited $r, want $6"
    return 0
}

# run_leg <leg> <compiler> <runner>
run_leg() {
    while IFS='|' read -r id mode want src; do
        NROWS=$((NROWS + 1))
        run_row "$1" "$2" "$3" "$id" "$mode" "$want" "$src"
    done < "$WORK/rows"
}

echo "host x86_64:"
run_leg host "$CC" ""

# The filed repro, verbatim (row R carries its code lines; this compiles the file itself).
RP="$ROOT/docs/development/issues/repros/2026-10-09-closure-prescan-reads-field-names-as-captures.cyr"
NROWS=$((NROWS + 1))
if [ ! -f "$RP" ]; then bad "host repro: $RP is missing"
elif ! build "$CC" "$RP" "$WORK/rp.bin"; then bad "host repro: compile failed: $(grep error "$WORK/rp.bin.err" | head -1 | head -c 300)"
else
    chmod +x "$WORK/rp.bin"
    set +e; "$WORK/rp.bin" > /dev/null 2>&1; r=$?; set -e
    [ "$r" = 16 ] || bad "host repro: exited $r, want 16"
fi

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

# Derived floor: the row table (15 rows) on host + cx, even with qemu absent.
if [ "$NTAB" -lt 15 ]; then bad "the row table holds $NTAB rows (floor 15) — it did not load"; fi
if [ "$NROWS" -lt $((NTAB * 2)) ]; then bad "only $NROWS rows ran (floor $((NTAB * 2)))"; fi
if [ "$NFAIL" -ne 0 ]; then
    echo "FAIL: closure_field_names_not_captured ($NFAIL of $NROWS rows)"
    exit 1
fi
if [ "${GATE_SKIPS:-0}" -gt 0 ]; then echo "SKIP: closure_field_names_not_captured — $GATE_SKIPS leg(s) above could not run; every one that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: closure_field_names_not_captured ($NROWS rows)"

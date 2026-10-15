#!/bin/sh
# Gate: a name a closure body declares is not a capture of the enclosing local of that name (6.7.11).
#
# THE DEFECT (measured 6.6.0 - 6.7.10, x86_64 and aarch64):
#
#     fn fi(): i64 { var i = 3; var cl = |n| { var s = 0; for i in 0..4 { s = s + i + n; } return s; }; .. }
#     fn fc(): i64 { var k = 5; var cl = |n| { const k = 3; return k + n; }; .. }
#     fn fm(): i64 { var b = 5; var cl = |n| { var a, b = two(); return a + b + n; }; .. }
#
# None of the three closures reads the enclosing local, yet each was refused: "a capturing closure
# needs include "lib/alloc.cyr" for its heap env". The capture pre-scan (`_cl_prescan_body`)
# shadowed only the name right after `var`; a `for … in` variable, a local const's name and the
# second / third name of a destructure were taken for reads. With lib/alloc.cyr the values were
# right, but each closure carried a heap env holding a copy of a local it never read.
#
# THE FIX (src/frontend/parse_expr.cyr): each name is shadowed from where the PARSER binds it.
# `const` names one as `var` does. `_cl_prescan_forin`: the start bound or the collection is read in
# the enclosing scope (PARSE_FOR parses it before it registers the variable), then the variable is
# shadowed for a range's end bound (which reads it) and the body, and dropped after the loop.
# `_cl_prescan_mvar`: a destructure's right-hand side is read first (PARSE_VAR binds the names
# after it), then its second and third names are shadowed.
#
# ROWS: id|mode|want|source (printf %b; the prelude below is prepended). mode n: no lib/alloc.cyr —
# the source compiles and exits `want`. mode a: with lib/alloc.cyr — it exits `want`. mode r: no
# lib/alloc.cyr — the source is REFUSED with exactly `want` "a capturing closure needs" errors (a
# real capture is still a capture). I / IC / C / M rows were refused before the fix; the K rows
# are CONTROLS that held before and after: KI1-KI2 a read after the loop, KI3-KI4 a range's start
# bound, KC1-KC2 the collection, KK1-KK4 an enclosing name after a nested block's const and beside
# one, KM1-KM4 a destructure's right-hand side and a read after a nested block's destructure. The
# `a` controls carry a GLOBAL of the same name, so a dropped capture reads it (a wrong value, not
# only a refusal): the 6.6.17 class this pre-scan can fall into.
#
# LEGS: host x86_64; cx via the tree's own main_cx + cxvm; aarch64 under qemu-aarch64 —
# EMULATION, not hardware. The fix is in the shared frontend, so every fork takes it. The filed
# repro file runs on every leg.
#
# MUTATION LEDGER (6.7.11 — each mutant is a scratch copy of the tree whose src/ carries the
# change, built by build/cycc into the scratch tree's build/cycc, with this gate run from the
# scratch tree, so the cx and aarch64 legs are built from the mutated src too):
#   m0 the pre-fix src                              -> RED I1-I3 IC1 C1 C2 M1 M2 and the repro, every leg (27)
#   m1 the `const` arm dropped (`t == 168`)          -> RED C1 C2 and the repro, every leg (9)
#   m2 the destructure arm dropped (`_cl_at_mvar` 0) -> RED M1 M2 and the repro, every leg (9)
#   m3 the for-in arm dropped (`_cl_at_forin` 0)     -> RED I1-I3 IC1 and the repro, every leg (15)
#   m4 the for-in variable shadowed from its name    -> RED KI3 KC1 (refused 'undefined variable'),
#                                                       KI4 (6) and KC2 (64): the GLOBAL read, every leg (12)
#   m5 a destructure's names shadowed at the names   -> RED KM1 (refused 'undefined variable'), KM2 (88:
#                                                       the global `b`), every leg (6)
#   real tree                                        -> GREEN (69: 22 rows and the repro per leg)
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: closure_declared_names_not_captured: cannot cd to $ROOT"; exit 1; }
CC="${CYCC:-$ROOT/build/cycc}"
[ -x "$CC" ] || { echo "FAIL: closure_declared_names_not_captured: $CC missing"; exit 1; }
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: closure_declared_names_not_captured: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
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

# The prelude: a two- and a three-value fn, and a `vec_len` / `vec_get` pair the collection
# `for x in c` calls by name (element i of collection v is v + i — no heap, so a mode-n row
# needs no lib/alloc.cyr).
cat > "$WORK/prelude" <<'PRE'
fn two(): (i64, i64) { return (3, 4); }
fn tw(x): (i64, i64) { return (x, x + 1); }
fn three(): (i64, i64, i64) { return (1, 2, 3); }
fn vec_len(v): i64 { return 3; }
fn vec_get(v, i): i64 { return v + i; }
PRE

cat > "$WORK/rows" <<'ROWS'
I1|n|10|fn f(): i64 { var i = 3; var cl = |n| { var s = 0; for i in 0..4 { s = s + i + n; } return s; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
I2|n|1|fn f(): i64 { var i = 3; var cl = |n| { var s = 0; for i in 0..i { s = s + 1; } return s + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
I3|n|5|fn f(): i64 { var i = 3; var j = 4; var cl = |n| { var s = 0; for i in 0..2 { for j in 0..2 { s = s + i + j; } } return s + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
IC1|n|34|fn f(): i64 { var x = 5; var cl = |n| { var s = 0; for x in 10 { s = s + x; } return s + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
C1|n|4|fn f(): i64 { var k = 5; var cl = |n| { const k = 3; return k + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
C2|n|9|fn f(): i64 { var k = 5; var cl = |n| { var s = 0; if (n > 0) { const k = 4; s = k * 2; } return s + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
M1|n|8|fn f(): i64 { var b = 5; var cl = |n| { var a, b = two(); return a + b + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
M2|n|7|fn f(): i64 { var c = 9; var b = 9; var cl = |n| { var a, b, c = three(); return a + b + c + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KI1|r|1|fn f(): i64 { var i = 3; var cl = |n| { var s = 0; for i in 0..4 { s = s + i; } return s + i + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KI2|a|10|var i = 40;\nfn f(): i64 { alloc_init(); var i = 3; var cl = |n| { var s = 0; for i in 0..4 { s = s + i; } return s + i + n; }; i = 50; return fncall1(cl, 1); }\nsyscall(60, f());\n
KI3|r|1|fn f(): i64 { var i = 3; var cl = |n| { var s = 0; for i in i..5 { s = s + 1; } return s + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KI4|a|3|var i = 0;\nfn f(): i64 { alloc_init(); var i = 3; var cl = |n| { var s = 0; for i in i..5 { s = s + 1; } return s + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KC1|r|1|fn f(): i64 { var x = 10; var cl = |n| { var s = 0; for x in x { s = s + x; } return s + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KC2|a|34|var x = 20;\nfn f(): i64 { alloc_init(); var x = 10; var cl = |n| { var s = 0; for x in x { s = s + x; } return s + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KK1|r|1|fn f(): i64 { var k = 5; var cl = |n| { var s = 0; if (n > 0) { const k = 3; s = k; } return s + k + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KK2|a|9|var k = 70;\nfn f(): i64 { alloc_init(); var k = 5; var cl = |n| { var s = 0; if (n > 0) { const k = 3; s = k; } return s + k + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KK3|r|1|fn f(): i64 { var k = 5; var cl = |n| { const c = 3; return c + k + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KK4|a|9|fn f(): i64 { alloc_init(); var k = 5; var cl = |n| { const c = 3; return c + k + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KM1|r|1|fn f(): i64 { var b = 5; var cl = |n| { var a, b = tw(b + n); return a * 10 + b; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KM2|a|67|var b = 100;\nfn f(): i64 { alloc_init(); var b = 5; var cl = |n| { var a, b = tw(b + n); return a * 10 + b; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KM3|r|1|fn f(): i64 { var b = 5; var cl = |n| { var s = 0; if (n > 0) { var a, b = two(); s = a + b; } return s + b + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
KM4|a|13|var b = 100;\nfn f(): i64 { alloc_init(); var b = 5; var cl = |n| { var s = 0; if (n > 0) { var a, b = two(); s = a + b; } return s + b + n; }; return fncall1(cl, 1); }\nsyscall(60, f());\n
ROWS
NTAB=$(grep -c '|' "$WORK/rows")

# run_row <leg> <compiler> <runner> <id> <mode> <want> <src> — runner is "" for native
run_row() {
    {
        printf 'include "lib/fnptr.cyr"\n'
        if [ "$5" = a ]; then printf 'include "lib/alloc.cyr"\n'; fi
        cat "$WORK/prelude"
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

# The filed repro, verbatim (rows I1 / C1 / M1 carry its three closures; this compiles the file).
RP="$ROOT/docs/development/issues/repros/2026-10-11-closure-prescan-reads-declared-names-as-captures.cyr"
run_repro() {
    NROWS=$((NROWS + 1))
    if [ ! -f "$RP" ]; then bad "$1 repro: $RP is missing"; return 0; fi
    if ! build "$2" "$RP" "$WORK/rp.bin"; then
        bad "$1 repro: compile failed: $(grep error "$WORK/rp.bin.err" | head -1 | head -c 300)"; return 0
    fi
    chmod +x "$WORK/rp.bin"
    set +e
    if [ -n "$3" ]; then $3 "$WORK/rp.bin" > /dev/null 2>&1
    else "$WORK/rp.bin" > /dev/null 2>&1; fi
    r=$?
    set -e
    [ "$r" = 22 ] || bad "$1 repro: exited $r, want 22"
    return 0
}

# run_leg <leg> <compiler> <runner>
run_leg() {
    while IFS='|' read -r id mode want src; do
        NROWS=$((NROWS + 1))
        run_row "$1" "$2" "$3" "$id" "$mode" "$want" "$src"
    done < "$WORK/rows"
    run_repro "$1" "$2" "$3"
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

# Derived floor: the row table (22 rows) and the repro on host + cx, even with qemu absent.
if [ "$NTAB" -lt 22 ]; then bad "the row table holds $NTAB rows (floor 22) — it did not load"; fi
if [ "$NROWS" -lt $(((NTAB + 1) * 2)) ]; then bad "only $NROWS rows ran (floor $(((NTAB + 1) * 2)))"; fi
if [ "$NFAIL" -ne 0 ]; then
    echo "FAIL: closure_declared_names_not_captured ($NFAIL of $NROWS rows)"
    exit 1
fi
if [ "${GATE_SKIPS:-0}" -gt 0 ]; then echo "SKIP: closure_declared_names_not_captured — $GATE_SKIPS leg(s) above could not run; every one that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: closure_declared_names_not_captured ($NROWS rows)"

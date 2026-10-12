#!/bin/sh
# Gate: a closure at TOP LEVEL captures nothing from the last fn compiled before it (6.7.9).
#
# THE DEFECT (measured 6.6.0 - 6.7.8, x86_64 and aarch64, no diagnostic):
#
#     fn w(qa): i64 { return qa; }
#     alloc_init();
#     var qa = 5;
#     var cl = |n| n + qa;
#     syscall(60, fncall1(cl, 7));          rc 139 (want 12)
#
# A closure literal snapshots the enclosing fn's local table, and its capture pre-scan takes a
# free name found there for a capture. A fn's end does not clear that table: at top level GFLC
# and the slot names still held the LAST fn compiled, so the global `qa` was "captured" from
# w's parameter slot — a slot of a frame that does not exist at top level. The env copy read
# it: SIGSEGV on x86_64 and aarch64, a wrong value on cx (7 here). A parameter, a second
# parameter, a local, a struct local and a `for` header's name of that fn all did it; so did a
# closure in a declaration-zone initializer (compiled after every fn) and in a top-level block,
# and a struct literal's field label `y:` / a `p.y` below a `fn w(y)` (row L).
#
# THE FIX (src/frontend/parse_expr.cyr `_cl_ctx_enter`): outside a fn the capture lookup is
# empty. Whether the closure sits in a fn is read from its own `_fnst_save` block
# (`_fnst_was_infn`, src/frontend/parse.cyr), taken before the closure enters its own fn. The
# table is still saved and put back around the closure as before, so nothing else at top level
# reads a different table. A closure NESTED in a top-level closure is inside a fn (the outer
# closure's), so it still captures the outer closure's names (row N).
#
# ROWS: id|want-rc|source (printf %b). Rows A-I, L and N were red before the fix (139 on x86_64
# and aarch64; a wrong value on cx, L aside); the K rows are CONTROLS that were right before and after —
# they pin that the fix drops no real capture (K3: a closure in a fn captures its parameter)
# and that a top-level name with no fn above it was never the problem.
#
# LEGS: host x86_64; cx via the tree's own main_cx + cxvm; aarch64 under qemu-aarch64 —
# EMULATION, not hardware. The fix is in the shared frontend, so every fork takes it.
#
# MUTATION LEDGER (6.7.9 — each mutant is a scratch copy of the tree whose src/ carries the
# change, built by build/cycc into the scratch tree's build/cycc, with this gate run from the
# scratch tree, so the cx and aarch64 legs are built from the mutated src too):
#   m1 `_cl_ctx_enter` ignores `st` (always the snapshot: the 6.7.8 code)  -> RED A-I, N on every
#      leg (139 on host and aarch64; 7 / 14 / 103 / 126 / 8 on cx) and L on host and aarch64 —
#      32 of 45 (cx copies L's needless capture harmlessly, and nothing reads it)
#   m2 the test inverted (the snapshot only at top level)                  -> RED as m1, and K3, N
#      refused `undefined variable` on every leg (35 of 45)
#   real tree                                                               -> GREEN (45 rows)
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: toplevel_closure_stale_locals: cannot cd to $ROOT"; exit 1; }
CC="${CYCC:-$ROOT/build/cycc}"
[ -x "$CC" ] || { echo "FAIL: toplevel_closure_stale_locals: $CC missing"; exit 1; }
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: toplevel_closure_stale_locals: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
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

# Every source starts with these two includes (prepended below).
cat > "$WORK/rows" <<'ROWS'
A|12|fn w(qa): i64 { return qa; }\nalloc_init();\nvar qa = 5;\nvar cl = |n| n + qa;\nsyscall(60, fncall1(cl, 7));\n
B|12|fn w(x, qa): i64 { return qa + x; }\nalloc_init();\nvar qa = 5;\nvar cl = |n| n + qa;\nsyscall(60, fncall1(cl, 7));\n
C|12|fn w(x): i64 { var qa = 1; return qa + x; }\nalloc_init();\nvar qa = 5;\nvar cl = |n| n + qa;\nsyscall(60, fncall1(cl, 7));\n
D|12|fn w(qa): i64 { return qa; }\nalloc_init();\nvar qa = 5;\nvar cl = |n| n + qa;\nvar zz = 3;\nsyscall(60, fncall1(cl, 7));\n
E|12|var qa = 5;\nvar cl = |n| n + qa;\nfn w(qa): i64 { return qa; }\nalloc_init();\nsyscall(60, fncall1(cl, 7));\n
F|19|fn w(x): i64 { var t = 2; var qa = x + t; return qa; }\nalloc_init();\nvar qa = 5;\nvar cl = |n| { var t = n * 2; return t + qa; };\nsyscall(60, fncall1(cl, 7));\n
G|12|fn w(qa): i64 { return qa; }\nalloc_init();\nvar qa = 5;\nvar r = 0;\nif (qa > 1) { var cl = |n| n + qa; r = fncall1(cl, 7); }\nsyscall(60, r);\n
H|12|struct Pt { x; y; }\nfn w(a): i64 { var qa: Pt = Pt { a, 2 }; return qa.x + qa.y; }\nalloc_init();\nvar qa = 5;\nvar cl = |n| n + qa;\nsyscall(60, fncall1(cl, 7));\n
I|33|fn w(k): i64 { return k; }\nalloc_init();\nvar s = 0;\nfor (var k = 0; k < 3; k = k + 1) { var cl = |n| n + k; s = s + fncall1(cl, 10); }\nsyscall(60, s);\n
L|16|struct Pt { x; y; }\nfn w(y): i64 { return y; }\nalloc_init();\nvar cl = |n| { var p = Pt { x: n, y: 2 }; return p.x + 2; };\nvar c2 = |n| { var p = Pt { n, 2 }; return p.y + 5; };\nsyscall(60, fncall1(cl, 7) + fncall1(c2, 7));\n
N|13|fn w(n, qa): i64 { var m = n; return qa + m; }\nalloc_init();\nvar qa = 5;\nvar cl = |n| { var g = |m| m + n; return fncall1(g, 1) + qa; };\nsyscall(60, fncall1(cl, 7));\n
K1|12|fn w(zz): i64 { return zz; }\nalloc_init();\nvar qa = 5;\nvar cl = |n| n + qa;\nsyscall(60, fncall1(cl, 7));\n
K2|12|fn w(qa): i64 { return qa; }\nvar qa = 5;\nfn mk(): i64 { return |n| n + qa; }\nalloc_init();\nsyscall(60, fncall1(mk(), 7));\n
K3|12|fn w(zz): i64 { return zz; }\nvar qa = 5;\nfn mk(b): i64 { return |n| n + b; }\nalloc_init();\nsyscall(60, fncall1(mk(qa), 7));\n
K4|33|alloc_init();\nvar s = 0;\nfor (var k = 0; k < 3; k = k + 1) { var cl = |n| n + k; s = s + fncall1(cl, 10); }\nsyscall(60, s);\n
ROWS
NTAB=$(grep -c '|' "$WORK/rows")

# run_row <leg> <compiler> <runner> <id> <want> <src> — runner is "" for native
run_row() {
    { printf 'include "lib/fnptr.cyr"\ninclude "lib/alloc.cyr"\n'; printf '%b' "$6"; } > "$WORK/t.cyr"
    if ! build "$2" "$WORK/t.cyr" "$WORK/t.bin"; then
        bad "$1 row $4: compile failed: $(head -c 300 "$WORK/t.bin.err")"; return 0
    fi
    chmod +x "$WORK/t.bin"
    set +e
    if [ -n "$3" ]; then $3 "$WORK/t.bin" > /dev/null 2>&1
    else "$WORK/t.bin" > /dev/null 2>&1; fi
    r=$?
    set -e
    [ "$r" = "$5" ] || bad "$1 row $4: exited $r, want $5"
    return 0
}

# run_leg <leg> <compiler> <runner>
run_leg() {
    while IFS='|' read -r id want src; do
        NROWS=$((NROWS + 1))
        run_row "$1" "$2" "$3" "$id" "$want" "$src"
    done < "$WORK/rows"
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

# Derived floor: the row table (15 rows) on host + cx, even with qemu absent.
if [ "$NTAB" -lt 15 ]; then bad "the row table holds $NTAB rows (floor 15) — it did not load"; fi
if [ "$NROWS" -lt $((NTAB * 2)) ]; then bad "only $NROWS rows ran (floor $((NTAB * 2)))"; fi
if [ "$NFAIL" -ne 0 ]; then
    echo "FAIL: toplevel_closure_stale_locals ($NFAIL of $NROWS rows)"
    exit 1
fi
if [ "${GATE_SKIPS:-0}" -gt 0 ]; then echo "SKIP: toplevel_closure_stale_locals — $GATE_SKIPS leg(s) above could not run; every one that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: toplevel_closure_stale_locals ($NROWS rows)"

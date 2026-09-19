#!/bin/sh
# A REAL .tcyr compiles for the cx target and RUNS on cxvm.
#
# WHY (v6.6.6): until this release the cx driver predefined no CYRIUS_TARGET_*
# macro at all. Every per-target `#ifdef` arm in the stdlib (lib/alloc.cyr,
# lib/syscalls.cyr, …) therefore matched nothing on cx, so those modules
# compiled to NOTHING and the filed repro
#
#     include "lib/assert.cyr"; assert_eq(1,1,"x"); var r = assert_summary();
#
# failed with `undefined function(s) called (cx backend): alloc, vec_get,
# alloc_reset, sys_exit`. No .tcyr had ever run on cx, so the whole target's
# test coverage was hand-written syscall-only programs — the five existing cx
# gates prove codegen shapes, not that the STDLIB works there. That is the
# "compiles on five targets is not runs on five targets" shape.
#
# Rows:
#   1  the filed repro verbatim — compiles for cx and exits 0 on cxvm.
#   2  tests/tcyr/platform/cx_stdlib_harness.tcyr compiles to a real CYX and
#      runs on cxvm with every assertion passing.
#   3  the same .tcyr passes NATIVELY (build/cycc) — so a cx-only green cannot
#      come from a file that is vacuous everywhere.
#   4  the assertion COUNT the run reports is checked against the count derived
#      from the source by grep — a different way of arriving at the same
#      number, so a harness that silently stopped asserting cannot pass.
#
# MUTATION LEDGER (v6.6.6, scratch trees only, never the repo):
#   real tree                                                        -> GREEN
#     4 rows, 13 assertions on cx and natively, 2.6 s
#   drop `PP_PREDEFINE(S, "CYRIUS_TARGET_CX")` from src/main_cx.cyr  -> RED
#     "FAIL: the filed repro does not compile for cx" + the four undefined fns
#   keep the predefine, remove the CYRIUS_TARGET_CX arm from
#     lib/alloc.cyr                                                  -> RED
#     same failure (alloc/alloc_reset undefined)
#   keep both, revert lib/assert.cyr's `include "lib/vec.cyr"`       -> RED
#     "undefined function(s) called (cx backend): vec_get"
#   keep all, delete two assertions from the .tcyr                   -> RED
#     "FAIL: only 11 assertions in ...cx_stdlib_harness.tcyr (floor 13)"
#     (the first cut of row 4 compared only run-count vs grep-count, which
#      AGREE when assertions are deleted — that mutant passed until the floor
#      was added. Recorded because it is the mutant that nearly shipped green.)
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC="$ROOT/build/cycc"
TCYR=tests/tcyr/platform/cx_stdlib_harness.tcyr
[ -x "$CC" ] || { echo "SKIP: build/cycc missing"; exit 0; }
[ -f src/main_cx.cyr ] || { echo "SKIP: src/main_cx.cyr missing"; exit 0; }
[ -f programs/cxvm.cyr ] || { echo "SKIP: programs/cxvm.cyr missing"; exit 0; }
[ -f "$TCYR" ] || { echo "FAIL: $TCYR missing — the cx row has nothing to run"; exit 1; }

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: cx_tcyr_runs: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT

build() {   # $1 = source, $2 = out binary
    if ! cat "$1" | "$CC" > "$2" 2> "$T/b.err"; then
        echo "FAIL: building $1 with build/cycc failed"
        head -3 "$T/b.err" || true
        exit 1
    fi
    sz=$(wc -c < "$2" | tr -d ' ')
    if [ "$sz" -lt 1024 ]; then
        echo "FAIL: $1 produced a $sz-byte binary (empty/truncated)"
        exit 1
    fi
    chmod +x "$2"
}
build src/main_cx.cyr "$T/cycc_cx"
build programs/cxvm.cyr "$T/cxvm"

# ── row 1: the filed repro, verbatim ─────────────────────────────────────
printf 'include "lib/assert.cyr";\nassert_eq(1,1,"x");\nvar r = assert_summary();\n' > "$T/repro.cyr"
if ! "$T/cycc_cx" < "$T/repro.cyr" > "$T/repro.cyx" 2> "$T/repro.err"; then
    echo "FAIL: the filed repro does not compile for cx"
    head -6 "$T/repro.err" || true
    exit 1
fi
rc=0
"$T/cxvm" < "$T/repro.cyx" > "$T/repro.out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
    echo "FAIL: the filed repro compiled for cx but exited $rc on cxvm"
    head -5 "$T/repro.out" || true
    exit 1
fi
echo "  repro: include lib/assert.cyr compiles for cx and exits 0 on cxvm"

# ── row 2: a real .tcyr on cxvm ──────────────────────────────────────────
if ! "$T/cycc_cx" < "$TCYR" > "$T/h.cyx" 2> "$T/h.err"; then
    echo "FAIL: $TCYR does not compile for cx"
    head -6 "$T/h.err" || true
    exit 1
fi
magic=$(od -An -N3 -tx1 "$T/h.cyx" | tr -d ' \n')
if [ "$magic" != "435958" ]; then
    echo "FAIL: cx output is not a CYX file (magic $magic)"
    exit 1
fi
rc=0
"$T/cxvm" < "$T/h.cyx" > "$T/h.out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
    echo "FAIL: $TCYR exited $rc on cxvm"
    head -8 "$T/h.out" || true
    exit 1
fi
cx_pass=$(awk '/passed,/ {print $1}' < "$T/h.out" | tail -1)
cx_fail=$(awk -F'passed, ' '/passed,/ {print $2}' < "$T/h.out" | awk '{print $1}' | tail -1)
if [ "$cx_fail" != "0" ] || [ -z "$cx_pass" ]; then
    echo "FAIL: cxvm run did not report a clean summary"
    head -8 "$T/h.out" || true
    exit 1
fi
echo "  cxvm: $TCYR -> $cx_pass assertions passed, 0 failed"

# ── row 3: the same file passes natively ─────────────────────────────────
build "$TCYR" "$T/h_native"
rc=0
"$T/h_native" > "$T/n.out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
    echo "FAIL: $TCYR exited $rc natively (x86-linux) — a cx-only green would be meaningless"
    head -8 "$T/n.out" || true
    exit 1
fi
nat_pass=$(awk '/passed,/ {print $1}' < "$T/n.out" | tail -1)
if [ "$nat_pass" != "$cx_pass" ]; then
    echo "FAIL: cxvm ran $cx_pass assertions, native ran $nat_pass — the two targets disagree"
    exit 1
fi
echo "  native: same file, same $nat_pass assertions"

# ── row 4: the count, derived from the SOURCE a different way ────────────
# Every assertion in the harness is one `assert*(` call at the start of a line.
want=$(grep -c '^assert' "$TCYR" || true)
# Floor = the count this file carried when the gate landed. Raise it when the
# harness grows; never lower it. Without a floor, DELETING assertions keeps the
# grep count and the run count in agreement and the gate stays green.
if [ "$want" -lt 13 ]; then
    echo "FAIL: only $want assertions in $TCYR (floor 13) — the harness was gutted"
    exit 1
fi
if [ "$cx_pass" != "$want" ]; then
    echo "FAIL: cxvm ran $cx_pass assertions, the source has $want"
    exit 1
fi

echo "PASS: cx compiles and runs a real .tcyr ($want assertions) on cxvm"
exit 0

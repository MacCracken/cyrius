#!/bin/sh
# tests/gates/memory/harness_alloc_refused.sh — 6.6.10 (bite 12)
#
# THE TEST HARNESS NEVER STORES THROUGH A REFUSED ALLOCATION.
#
# THE DEFECT. `test_scratch` (lib/assert.cyr, 6.6.6) did `var buf = alloc(bl + 32);
# memcpy(buf, base, bl); store8(buf + bl, 46);` with no zero check. With ALLOC_MAX = 0 that is
# rc 139 on x86 and qemu-aarch64, a page fault writing 0x0 under wine — and on cx NO crash at
# all: cxvm wrote guest offset 0 and test_scratch RETURNED 0, so a test got a "name" that was
# address 0. The same shape sat in `bench_new` (lib/bench.cyr, store64 through `b`) and in
# lib/regression.cyr: the deadline's tree-walk buffers (`_regression_tree_init` allocated three
# and tested one, and nothing checked any), `_regression_termed`, the envp merge of
# `regression_exec_in_dir3_env`, and `regression_pipe_to_bin_capture`'s source buffer.
#
# THE FIX. test_scratch PANICS by name (a test has no fixture name to fall back to); bench_new
# returns 0; the regression verbs return -1 BEFORE any fork — the walk buffers are allocated by
# `_regression_fork` ahead of the child, so a refusal is that verb's ordinary fork failure.
#
# WHY A GATE AND NOT A crossos .tcyr: the pass condition of the test_scratch row is EXIT 1 with
# the panic text, which the crossos leg cannot express, and the class has a target that does
# not crash (cx), so each target must be run — the template gate
# (io_alloc_refused_per_call.sh) is x86-only.
#
# ROWS
#   1  test_scratch with ALLOC_MAX = 0: exit 1 + `panic: test_scratch: alloc refused the
#      fixture name`, and nothing after it runs — on x86, qemu-aarch64, wine (PE) and cxvm
#   2  POSITIVE CONTROL on the same four: test_scratch serves "<base>.<pid>", bench_new
#      returns 0 when refused and a benchmark when served
#   3  (x86 Linux) the regression verbs: a refused walk-buffer allocation fails
#      regression_exec_in_dir3 with -1 and NO child runs; a refused envp merge does the same
#      for regression_exec_in_dir3_env; regression_pipe_to_bin_capture returns -1; a refused
#      `_regression_termed` does not fault regression_terminate_children, which still ends
#      the child; each served twin runs
# Each cross target is built FRESH from src/ with $CC (a stale build/cycc_aarch64 is exactly
# what the check-driver half of this bite stops trusting). wine / qemu-aarch64 missing = a
# named SKIP of that target only.
#
# MUTATION LEDGER (6.6.10, each check removed ALONE; measured)
#   * test_scratch's `buf == 0` panic   -> row 1: x86 139, aarch64 139 (qemu SIGSEGV), PE 5 (wine
#                                           page fault writing 0x0), cx 7 = it CARRIED ON past a
#                                           silent write to guest offset 0 — the reason cx is a row
#   * bench_new's `b == 0`              -> row 2: x86 139, aarch64 139, PE 5. cx stays green: its
#                                           write through 0 is silent and bench_new then returns
#                                           0 anyway (the cxvm no-bounds-check backlog item)
#   * `_regression_fork`'s tree init    -> row 3: "a child ran although the walk buffers were refused"
#   * the envp merge's `merged == 0`    -> row 3: rc 139
#   * `_regression_termed == 0` return  -> row 3: rc 139
#   * the src_buf check                 -> row 3: "pipe_to_bin_capture ... returns -1 (got 0)"
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=harness_alloc_refused
[ -x "$CC" ] || { echo "FAIL: $NAME — no compiler at $CC"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME — mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAILS=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }
ulimit -c 0 2>/dev/null || :
PANIC='panic: test_scratch: alloc refused the fixture name'

cat > "$W/p1.cyr" <<'CYR'
include "lib/alloc.cyr"
include "lib/assert.cyr"
alloc_init();
ALLOC_MAX = 0;
var p = test_scratch("hx");
syscall(1, 1, "NOT REACHED\n", 12);
syscall(60, 7);
CYR
cat > "$W/p2.cyr" <<'CYR'
include "lib/alloc.cyr"
include "lib/assert.cyr"
include "lib/bench.cyr"
alloc_init();
var rc = 0;
var n = test_scratch("hx");
if (n == 0) { rc = 2; }
if (rc == 0) {
    if (load8(n) != 104 || load8(n + 1) != 120 || load8(n + 2) != 46) { rc = 2; }
    if (load8(n + 3) < 48 || load8(n + 3) > 57) { rc = 2; }
}
var saved = ALLOC_MAX;
ALLOC_MAX = 0;
var b = bench_new("refused");
ALLOC_MAX = saved;
if (b != 0) { rc = 3; }
var b2 = bench_new("served");
if (b2 == 0) { rc = 4; }
if (rc == 0) { syscall(1, 1, "ok\n", 3); }
syscall(60, rc);
CYR

# ── the four targets: name, how to build, how to run ─────────────────────────────────────
"$CC" < src/main_aarch64.cyr > "$W/cca" 2>/dev/null && chmod +x "$W/cca" || _fail "the aarch64 cross compiler did not build from src/main_aarch64.cyr"
"$CC" < src/main_cx.cyr > "$W/cccx" 2>/dev/null && chmod +x "$W/cccx" || _fail "the cx compiler did not build from src/main_cx.cyr"
"$CC" < programs/cxvm.cyr > "$W/vm" 2>/dev/null && chmod +x "$W/vm" || _fail "cxvm did not build from programs/cxvm.cyr"
HAVE_QEMU=1; command -v qemu-aarch64 >/dev/null 2>&1 || HAVE_QEMU=0
HAVE_WINE=1; command -v wine >/dev/null 2>&1 || HAVE_WINE=0
NT=0
build_run() {  # $1 target, $2 probe → sets RRC, $W/<probe>.<t>.out / .err ; returns 1 on SKIP
    t=$1; p=$2; o="$W/$p.$t"
    RRC=0
    case "$t" in
        x86)     "$CC" < "$W/$p.cyr" > "$o.bin" 2>/dev/null || { _fail "$t: $p did not compile"; return 1; }
                 chmod +x "$o.bin"; ( cd "$W" && timeout 60 "$o.bin" ) > "$o.out" 2> "$o.err" || RRC=$? ;;
        aarch64) [ "$HAVE_QEMU" = 1 ] || { echo "  SKIP: $t $p — qemu-aarch64 not installed (pi covers the hardware)"; return 1; }
                 "$W/cca" < "$W/$p.cyr" > "$o.bin" 2>/dev/null || { _fail "$t: $p did not compile"; return 1; }
                 chmod +x "$o.bin"; ( cd "$W" && timeout 60 qemu-aarch64 "$o.bin" ) > "$o.out" 2> "$o.err" || RRC=$? ;;
        pe)      [ "$HAVE_WINE" = 1 ] || { echo "  SKIP: $t $p — wine not installed (cass covers the hardware)"; return 1; }
                 CYRIUS_TARGET_WIN=1 "$CC" < "$W/$p.cyr" > "$o.exe" 2>/dev/null || { _fail "$t: $p did not compile"; return 1; }
                 ( cd "$W" && WINEDEBUG=-all timeout 120 wine "$o.exe" ) > "$o.out" 2> "$o.err" || RRC=$? ;;
        cx)      "$W/cccx" < "$W/$p.cyr" > "$o.cyx" 2>/dev/null || { _fail "$t: $p did not compile"; return 1; }
                 ( cd "$W" && timeout 60 "$W/vm" < "$o.cyx" ) > "$o.out" 2> "$o.err" || RRC=$? ;;
    esac
    tr -d '\r' < "$o.out" > "$o.o"; mv "$o.o" "$o.out"
    tr -d '\r' < "$o.err" > "$o.e"; mv "$o.e" "$o.err"
    return 0
}

echo "row 1: test_scratch under a refused allocation panics by name, on every target"
for t in x86 aarch64 pe cx; do
    build_run "$t" p1 || continue
    NT=$((NT + 1))
    [ "$RRC" = 1 ] || _fail "row 1 $t: exit $RRC, expected 1$( [ "$RRC" = 0 ] && echo ' — a silent write through address 0')"
    grep -qxF "$PANIC" "$W/p1.$t.err" || _fail "row 1 $t: no '$PANIC' on stderr (got: $(head -c 120 "$W/p1.$t.err"))"
    grep -q 'NOT REACHED' "$W/p1.$t.out" && _fail "row 1 $t: the program carried on past the panic"
done

echo "row 2: positive control — the name is served, bench_new refuses to 0 and serves"
for t in x86 aarch64 pe cx; do
    build_run "$t" p2 || continue
    [ "$RRC" = 0 ] && grep -qx ok "$W/p2.$t.out" \
        || _fail "row 2 $t: exit $RRC (2 = no/bad scratch name, 3 = bench_new did not return 0 when refused, 4 = not served)"
done
[ "$NT" -ge 2 ] || _fail "only $NT target(s) ran row 1 (floor 2: x86 and cx never skip)"

echo "row 3: the regression verbs fail with -1 before any fork (x86_64 Linux)"
case "$(uname -s)-$(uname -m)" in
Linux-x86_64)
cat > "$W/p3.cyr" <<'CYR'
include "lib/assert.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
include "lib/syscalls.cyr"
include "lib/vec.cyr"
include "lib/str.cyr"
include "lib/tagged.cyr"
include "lib/chrono.cyr"
include "lib/net.cyr"
include "lib/regression.cyr"
var _saved = 0;
fn refuse(): i64 { _saved = ALLOC_MAX; ALLOC_MAX = 0; return 0; }
fn serve(): i64 { ALLOC_MAX = _saved; return 0; }
fn main(): i64 {
    alloc_init();
    var envp[8];
    store64(&envp, 0);
    refuse();
    var r1 = regression_exec_in_dir3(".", "/bin/sh", "-c", "echo x > m1", 0, 0, &envp);
    serve();
    assert_eq(r1, 0 - 1, "exec_in_dir3 with the walk buffers refused returns -1");
    assert_eq(file_exists("m1"), 0, "a child ran although the walk buffers were refused");
    var r2 = regression_exec_in_dir3(".", "/bin/sh", "-c", "echo x > m2", 0, 0, &envp);
    assert_eq(r2, 0, "served: exec_in_dir3 runs");
    assert_eq(file_exists("m2"), 1, "served: the child ran");

    var ex = vec_new();
    vec_push(ex, "CYR_HX=1");
    refuse();
    var r3 = regression_exec_in_dir3_env(".", "/bin/sh", "-c", "echo x > m3", 0, ex, 0, &envp);
    serve();
    assert_eq(r3, 0 - 1, "exec_in_dir3_env with the envp merge refused returns -1");
    assert_eq(file_exists("m3"), 0, "a child ran although the envp merge was refused");
    var r4 = regression_exec_in_dir3_env(".", "/bin/sh", "-c", "echo x > m4", 0, ex, 0, &envp);
    assert_eq(r4, 0, "served: exec_in_dir3_env runs");
    assert_eq(file_exists("m4"), 1, "served: its child ran");

    refuse();
    var r5 = regression_pipe_to_bin_capture("/bin/cat", "m2", "m5", &envp);
    serve();
    assert_eq(r5, 0 - 1, "pipe_to_bin_capture with its source buffer refused returns -1");

    var pid = sys_fork();
    if (pid == 0) { syscall(7, 0, 0, 5000); sys_exit(0); }
    refuse();
    var n = regression_terminate_children(100);
    serve();
    assert_eq(n, 1, "terminate_children with `_regression_termed` refused still counts the child");
    var st[8];
    assert_eq(sys_waitpid(pid, &st, 1) < 0, 1, "…and still ends it");
    var r = assert_summary();
    return r;
}
var ec = main();
syscall(60, ec);
CYR
    mkdir -p "$W/r3"
    if "$CC" < "$W/p3.cyr" > "$W/p3.bin" 2>/dev/null; then
        chmod +x "$W/p3.bin"
        RRC=0; ( cd "$W/r3" && timeout 120 "$W/p3.bin" ) > "$W/p3.out" 2>&1 || RRC=$?
        [ "$RRC" = 0 ] || { _fail "row 3: exit $RRC"; grep -E 'FAIL|passed' "$W/p3.out" | sed 's/^/      /'; }
        grep -qE '^[1-9][0-9]* passed, 0 failed' "$W/p3.out" || _fail "row 3: no clean summary"
    else
        _fail "row 3: the regression probe did not compile"
    fi
    ;;
*) echo "  SKIP: row 3 — x86_64 Linux only (it forks and walks /proc)" ;;
esac

echo ""
if [ "$FAILS" -gt 0 ]; then
    echo "FAIL: $NAME — $FAILS check(s) failed"
    exit 1
fi
echo "PASS: $NAME (test_scratch panics by name on $NT target(s); bench_new and the regression verbs refuse cleanly)"

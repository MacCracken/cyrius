#!/bin/sh
# test_exit_code_contract.sh — 6.7.6 (Break 1, lane C, part T). THE EXIT CODE IS `cyrius test`'s
# CONTRACT: in every form — a file, a directory, several operands, bare — it exits non-zero on ANY
# failing test, ANY compile failure (of a test, of its configuration, of the dependency resolve)
# and when it finds ZERO tests; zero exactly when every test it found passed. So a CI step is one
# line — `cyrius test` / `cyrius test tests/x` — under `set -e`, with no summary grep and no
# hand-written loop (55 consumer ci.ymls loop over files or grep the summary today: 34 list files
# by name, 19 grep `N passed, M failed`). Every row runs the CLI the way such a step does, under
# `sh -e`, and asserts what the shell sees.
#
# ROWS
#   X1  all pass (file, dir, several operands, bare): rc 0
#   X2  an assertion failure (exit 3) in a directory of passes: non-zero, the file named
#   X3  a test that does not compile: non-zero
#   X4  a test killed by a signal (SIGSEGV): non-zero
#   X5  a test that runs past its deadline: non-zero
#   X6  ZERO tests: bare with no tests/ and no [test] files; an empty directory; two empty
#       directories as operands; `[test] files = []` with no tests/ — each non-zero, named
#   X7  a test that exits 0 but whose assert summary reports a failure: non-zero
#   X8  a refused [test] value: non-zero, nothing run
#   X9  a dependency resolve that fails (an unknown stdlib leaf): non-zero, nothing run
#   X10 a missing operand file: non-zero
#   X11 256 failing tests: still non-zero (an exit status keeps 8 bits; the count is not the code)
#
# MUTATION LEDGER (6.7.6) — each mutant built in a SCRATCH copy of the tree, the gate run against
# it; the unmutated copy PASSES, and each mutant turns the rows named RED:
#   M1  cyrius.cyr: bare `cyrius test` that finds nothing exits 0                X6a X6d
#   M2  commands.cyr: `cyrius test <dir>` exits 0 over failures              X2-X7 dir, X11
#   M3  cyrius.cyr: several operands exit 0 over failures                    X2-X7 operands, X6c
#   M4  cyrius.cyr: bare `cyrius test` exits 0 over failures                 X2-X7 bare
#   M5  commands.cyr: the assert-summary grade ignored (exit code alone)     X7 (every form)
#   M6  commands.cyr: an empty <dir> exits 0                                 X6b
# The contract held at this gate's first run (6.7.6): the rows pin it.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=test_exit_code_contract
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: $G: no compiler at $CC"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
unset CYRIUS_LOCAL CYRIUS_LOCKED CYRIUS_LIB_OVERLAY CYRIUS_DEFINES CYRIUS_TEST_TIMEOUT
ulimit -c 0 2>/dev/null
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/build.err" || { echo "FAIL: $G: cbt/cyrius.cyr does not build"; tail -3 "$W/build.err"; exit 1; }
chmod +x "$W/cyrius"
VER=$(tr -d '[:space:]' < VERSION)
mkdir -p "$W/home/bin" "$W/home/versions/$VER" "$W/h"
cp "$CC" "$W/home/bin/cycc"
cp -R lib "$W/home/versions/$VER/lib" || { echo "FAIL: $G: could not stage the stdlib"; exit 1; }
# step <dir> <args...> — the CI step: `sh -e -c 'cyrius ARGS'`; RC is what the job sees
step() {
    d=$1; shift
    RC=0
    ( cd "$W/$d" && HOME="$W/h" CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 \
        sh -e -c '"$0" "$@"; echo STEP-CONTINUED' "$W/cyrius" "$@" ) > "$W/out" 2> "$W/err" < /dev/null || RC=$?
}
cont() { grep -c '^STEP-CONTINUED$' "$W/out" || true; }
show() { cat "$W/out" "$W/err" | sed 's/^/      /' | head -10; }
proj() { rm -rf "$W/$1"; mkdir -p "$W/$1"; { printf '[package]\nname = "%s"\nversion = "0.1.0"\ncyrius = "%s"\n\n' "$1" "$VER"; cat; } > "$W/$1/cyrius.cyml"; }
prog() { mkdir -p "$(dirname "$1")"; printf 'syscall(60, %d);\n' "$2" > "$1"; }
# nonzero <row> <what> — the step failed AND `sh -e` stopped it
nonzero() { if [ "$RC" != 0 ] && [ "$(cont)" = 0 ]; then echo "  ok $1: $2 (rc $RC)"; else fail "$1: $2 — rc $RC, continued $(cont)"; show; fi; }

# ── X1 ──
proj a <<'EOF'
EOF
prog "$W/a/tests/p1.tcyr" 0; prog "$W/a/tests/u/p2.tcyr" 0
x=$FAIL
step a test tests/p1.tcyr; [ "$RC" = 0 ] && [ "$(cont)" = 1 ] || fail "X1 file: rc $RC"
step a test tests;          [ "$RC" = 0 ] && [ "$(cont)" = 1 ] || fail "X1 dir: rc $RC"
step a test tests/p1.tcyr tests/u; [ "$RC" = 0 ] && [ "$(cont)" = 1 ] || fail "X1 operands: rc $RC"
step a test;                [ "$RC" = 0 ] && [ "$(cont)" = 1 ] || fail "X1 bare: rc $RC"
[ "$FAIL" = "$x" ] && echo "  ok X1: every test passes — file, dir, operands, bare: rc 0 and the step continues"

# ── X2 .. X5, X7: one failing test among passes, in every form ──
for kind in assert compile signal timeout graded; do
    proj "f$kind" <<'EOF'
[test]
timeout = 1
EOF
    prog "$W/f$kind/tests/ok.tcyr" 0
    case $kind in
        assert)  prog "$W/f$kind/tests/bad.tcyr" 3 ;;
        compile) printf 'var x = ;\n' > "$W/f$kind/tests/bad.tcyr" ;;
        signal)  printf 'store64(0, 1);\nsyscall(60, 0);\n' > "$W/f$kind/tests/bad.tcyr" ;;
        timeout) printf 'while (1 == 1) { }\nsyscall(60, 0);\n' > "$W/f$kind/tests/bad.tcyr" ;;
        graded)  printf 'fn assert_summary(): i64 { return 0; }\nsyscall(1, 1, "1 passed, 1 failed\\n", 19);\nsyscall(60, 0);\n' > "$W/f$kind/tests/bad.tcyr" ;;
    esac
    x=$FAIL
    step "f$kind" test tests/bad.tcyr;            [ "$RC" != 0 ] && [ "$(cont)" = 0 ] || fail "$kind file: rc $RC"
    step "f$kind" test tests;                     [ "$RC" != 0 ] && [ "$(cont)" = 0 ] && grep -q 'FAIL: tests/bad.tcyr' "$W/err" || fail "$kind dir: rc $RC"
    step "f$kind" test tests/ok.tcyr tests/bad.tcyr; [ "$RC" != 0 ] && [ "$(cont)" = 0 ] || fail "$kind operands: rc $RC"
    step "f$kind" test;                           [ "$RC" != 0 ] && [ "$(cont)" = 0 ] || fail "$kind bare: rc $RC"
    case $kind in assert) r=X2;; compile) r=X3;; signal) r=X4;; timeout) r=X5;; graded) r=X7;; esac
    [ "$FAIL" = "$x" ] && echo "  ok $r: a failing test ($kind) among passes — file, dir, operands, bare: non-zero, the step stops" || show
done

# ── X6: zero tests ──
proj z <<'EOF'
EOF
step z test; nonzero X6a "bare, no tests/ and no [test] files"
mkdir -p "$W/z/e1" "$W/z/e2"
step z test e1; nonzero X6b "an empty directory"
step z test e1 e2; nonzero X6c "two empty directories as operands"
proj z2 <<'EOF'
[test]
files = []
EOF
step z2 test; nonzero X6d "[test] files = [] and no tests/"

# ── X8 / X9 / X10 ──
proj r8 <<'EOF'
[test]
timeout = "soon"
EOF
prog "$W/r8/tests/ok.tcyr" 0
step r8 test; nonzero X8 "a refused [test] value"
proj r9 <<'EOF'
[deps]
stdlib = ["syscalls", "no_such_leaf"]
EOF
prog "$W/r9/tests/ok.tcyr" 0
step r9 test; nonzero X9 "a dependency resolve that fails"
step a test tests/missing.tcyr; nonzero X10 "a missing operand file"

# ── X11 ──
proj m <<'EOF'
EOF
i=0; while [ $i -lt 256 ]; do prog "$W/m/tests/f$i.tcyr" 1; i=$((i + 1)); done
step m test tests
if [ "$RC" != 0 ] && [ "$(cont)" = 0 ] && grep -q '^0 passed, 256 failed$' "$W/out"; then echo "  ok X11: 256 failing tests — rc $RC, not a wrapped 0"
else fail "X11: rc $RC"; tail -2 "$W/out"; fi

[ "$FAIL" = 0 ] || { echo "FAIL: $G ($FAIL row(s))"; exit 1; }
echo "PASS: $G"

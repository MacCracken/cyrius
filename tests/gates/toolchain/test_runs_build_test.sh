#!/bin/sh
# test_runs_build_test.sh — 6.6.17 (P1). Bare `cyrius test` runs what `[build] test` declares,
# then the tests/ walk, each file once; with the key absent it is exactly what it was.
#
# WHY: 41 manifests declare `[build] test` and nothing read it. The init templates and 25 consumer
# CIs say bare `cyrius test` "picks up the [build].test entry AND auto-discovers tests/*.tcyr";
# it only ever did the second half, so kashi's 397 assertions (src/test.cyr) never ran in CI, and a
# project with no tests/ dir failed "No .tcyr files found". The fixtures use the three spellings
# consumers actually write (measured 2026-10-05): `src/test.cyr` (37), `tests/<name>.tcyr` (3) and
# the directory `tests` (1). Every program prints a marker, so "ran" and "ran once" are counted.
#
# AXES
#   1. a declared src/test.cyr that FAILS fails the run (6.6.16: exit 0, never ran).
#   2. a declared file that passes runs, then tests/ — both counted.
#   3. `test = "tests"` (a directory): each .tcyr runs ONCE, not once per mention.
#   4. `test = "tests/x.tcyr"`: runs once.
#   5. no tests/ directory, a declared file: it runs, exit 0.
#   6. a declared path that does not exist: a named failure.
#   7. a list of targets: every one runs.
#   8. the key absent: only tests/ runs (today's behaviour).
#   9. an argument wins: `cyrius test tests/a.tcyr` does not run the declared target.
#  10. `cyrius build --print-config` reports build.test from the manifest.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: test_runs_build_test: no compiler at $CC"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: test_runs_build_test: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/build.err" || { echo "FAIL: test_runs_build_test: cbt/cyrius.cyr does not build"; tail -3 "$W/build.err"; exit 1; }
chmod +x "$W/cyrius"
mkdir -p "$W/home/bin"; cp "$CC" "$W/home/bin/cycc"

# prog <path> <marker> <exit>
prog() { mkdir -p "$(dirname "$1")"; printf 'syscall(1, 1, "MARK-%s\\n", %d);\nsyscall(60, %d);\n' "$2" $((${#2} + 6)) "$3" > "$1"; }
# proj <name> <extra [build] lines> — a fresh project dir
proj() { rm -rf "$W/$1"; mkdir -p "$W/$1"; printf '[package]\nname = "%s"\n\n[build]\nentry = "src/main.cyr"\noutput = "build/x"\n%b' "$1" "$2" > "$W/$1/cyrius.cyml"; }
run() { d=$1; shift; RC=0; ( cd "$W/$d" && CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 "$W/cyrius" test "$@" ) > "$W/out" 2>&1 || RC=$?; }
marks() { grep -c "^MARK-$1\$" "$W/out" || true; }
show() { sed 's/^/      /' "$W/out" | head -6; }

# ── 1: a failing declared test fails the run ────────────────────────────────────────────
proj a1 'test = "src/test.cyr"\n'; prog "$W/a1/src/test.cyr" decl 3; prog "$W/a1/tests/a.tcyr" walk 0
run a1
if [ "$RC" -ne 0 ] && [ "$(marks decl)" = 1 ] && [ "$(marks walk)" = 1 ]; then echo "  ok 1: a declared src/test.cyr that exits 3 runs and fails the run (rc $RC); tests/ still runs"
else fail "1: rc $RC, declared ran $(marks decl)x, tests/ ran $(marks walk)x (want non-zero, 1, 1)"; show; fi

# ── 2: a passing declared test, then tests/ ─────────────────────────────────────────────
proj a2 'test = "src/test.cyr"\n'; prog "$W/a2/src/test.cyr" decl 0; prog "$W/a2/tests/tcyr/a.tcyr" walk 0
run a2
if [ "$RC" = 0 ] && [ "$(marks decl)" = 1 ] && [ "$(marks walk)" = 1 ] && grep -q '^2 passed, 0 failed$' "$W/out"; then echo "  ok 2: declared + tests/ both run: 2 passed, 0 failed"
else fail "2: rc $RC, declared $(marks decl)x, walk $(marks walk)x"; show; fi

# ── 3: a declared directory — once each ─────────────────────────────────────────────────
proj a3 'test = "tests"\n'; prog "$W/a3/tests/one.tcyr" one 0; prog "$W/a3/tests/sub/two.tcyr" two 0
run a3
if [ "$RC" = 0 ] && [ "$(marks one)" = 1 ] && [ "$(marks two)" = 1 ] && grep -q '^2 passed, 0 failed$' "$W/out"; then echo "  ok 3: test = \"tests\" — each .tcyr runs once (2 passed)"
else fail "3: rc $RC, one ran $(marks one)x, two ran $(marks two)x (want 1 and 1)"; show; fi

# ── 4: a declared tests/<name>.tcyr — once ──────────────────────────────────────────────
proj a4 'test = "./tests/x.tcyr"\n'; prog "$W/a4/tests/x.tcyr" x 0
run a4
[ "$RC" = 0 ] && [ "$(marks x)" = 1 ] && echo "  ok 4: test = \"./tests/x.tcyr\" runs once" || { fail "4: rc $RC, x ran $(marks x)x (want 1)"; show; }

# ── 5: no tests/ dir ────────────────────────────────────────────────────────────────────
proj a5 'test = "src/test.cyr"\n'; prog "$W/a5/src/test.cyr" decl 0
run a5
[ "$RC" = 0 ] && [ "$(marks decl)" = 1 ] && echo "  ok 5: no tests/ directory — the declared test runs, exit 0" || { fail "5: rc $RC, declared $(marks decl)x"; show; }

# ── 6: a declared path that does not exist ──────────────────────────────────────────────
proj a6 'test = "src/tset.cyr"\n'; prog "$W/a6/tests/a.tcyr" walk 0
run a6
[ "$RC" -ne 0 ] && grep -q 'does not exist: src/tset.cyr' "$W/out" && echo "  ok 6: a typo'd [build] test is a named failure (rc $RC)" || { fail "6: rc $RC"; show; }

# ── 7: a list ───────────────────────────────────────────────────────────────────────────
proj a7 'test = ["src/t1.cyr", '"'"'src/t2.cyr'"'"']\n'; prog "$W/a7/src/t1.cyr" t1 0; prog "$W/a7/src/t2.cyr" t2 0
run a7
[ "$RC" = 0 ] && [ "$(marks t1)" = 1 ] && [ "$(marks t2)" = 1 ] && echo "  ok 7: a list of targets — each runs" || { fail "7: rc $RC, t1 $(marks t1)x t2 $(marks t2)x"; show; }

# ── 8: the key absent ───────────────────────────────────────────────────────────────────
proj a8 ''; prog "$W/a8/src/test.cyr" decl 3; prog "$W/a8/tests/a.tcyr" walk 0
run a8
[ "$RC" = 0 ] && [ "$(marks decl)" = 0 ] && [ "$(marks walk)" = 1 ] && echo "  ok 8: with no [build] test only tests/ runs" || { fail "8: rc $RC, decl $(marks decl)x, walk $(marks walk)x"; show; }

# ── 9: an argument wins ─────────────────────────────────────────────────────────────────
run a1 tests/a.tcyr
[ "$RC" = 0 ] && [ "$(marks decl)" = 0 ] && [ "$(marks walk)" = 1 ] && echo "  ok 9: cyrius test <file> runs that file only" || { fail "9: rc $RC, decl $(marks decl)x"; show; }

# ── 10: print-config ────────────────────────────────────────────────────────────────────
( cd "$W/a2" && CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 "$W/cyrius" build --print-config ) > "$W/out" 2>&1 || true
grep -qF '  build.test = ["src/test.cyr"]  (manifest: [build] test)' "$W/out" && echo "  ok 10: --print-config reports build.test" || { fail "10: no build.test row"; show; }

[ "$FAIL" = 0 ] || exit 1
echo "PASS: test_runs_build_test ([build] test runs first, tests/ after, each file once; absent = unchanged)"

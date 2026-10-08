#!/bin/sh
# test_absorbs_tests.sh — 6.7.6 (Break 1, lane G). ONE test verb: `cyrius test <file>`,
# `cyrius test <dir>` (recursive), several operands (each file once) and a bare `cyrius test`
# (unchanged); `cyrius tests [dir]` is a deprecated alias for one release with a one-line notice
# naming the new spelling.
#
# WHY: two verbs did one job and CLAUDE.md had to warn about the difference: `cyrius test <dir>`
# was `error: not a file`, exit 1, and the walk lived in `cyrius tests`.
#
# ROWS (each program prints MARK-<name> and exits with its code; none calls assert_summary, so
# the verdict is the exit code)
#   1  `cyrius test <file>` runs that file only; a failing file fails the run, named
#   2  `cyrius test <dir>` runs every .tcyr under it at any depth, nothing outside it, no notice
#   3  a <dir> holding a failing test: 1 passed, 1 failed, exit 1, the file named
#   4  a <dir> holding no .tcyr: exit 1, "No .tcyr files found under <dir>"
#   5  several operands mixing a dir, a subdir and a file: each file ONCE (3 passed, not 5);
#      an empty dir among them is a counted, named failure
#   6  bare `cyrius test`: every .tcyr under tests/, each once (unchanged)
#   7  `cyrius tests <dir>`: one stderr line naming `cyrius test <dir>`, the same stdout and exit
#      as `cyrius test <dir>`; bare `cyrius tests` names `cyrius test tests`
#
# MUTATION LEDGER (6.7.6) — each RUN against a fresh scratch copy of the tree (cbt/ + lib/ +
# src/ + tests/tcyr + build/cycc + cyrius.cyml + VERSION + this gate); the unmutated copy PASSES
# and the gate exits 1 on each mutant, red rows as measured:
#   M1  cyrius.cyr: the single-dir `cmd_tests` arm dropped (`test <dir>` = not a file)  2 3 4 7
#   M2  cyrius.cyr: the multi-operand loop calls cmd_test (no dir walk, no dedupe)      5 5b
#   M3  commands.cyr: _test_path without `_tests_first_run`, no `_tests_seen`           5
#   M4  cyrius.cyr: the `tests` branch without _tests_verb_deprecated                   7 7b
#   M8  cyrius.cyr: bare `cyrius test` no longer walks tests/                           6
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: test_absorbs_tests: no compiler at $CC"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: test_absorbs_tests: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/build.err" || { echo "FAIL: test_absorbs_tests: cbt/cyrius.cyr does not build"; tail -3 "$W/build.err"; exit 1; }
[ "$(wc -c < "$W/cyrius")" -ge 20000 ] || { echo "FAIL: test_absorbs_tests: cbt/cyrius.cyr built a $(wc -c < "$W/cyrius")-byte binary"; exit 1; }
chmod +x "$W/cyrius"
VER=$(tr -d '[:space:]' < VERSION)
mkdir -p "$W/home/bin" "$W/h"
cp "$CC" "$W/home/bin/cycc"

# prog <path> <marker> <exit>
prog() { mkdir -p "$(dirname "$1")"; printf 'syscall(1, 1, "MARK-%s\\n", %d);\nsyscall(60, %d);\n' "$2" $((${#2} + 6)) "$3" > "$1"; }
# proj <name> <extra [build] lines> [<[deps] stdlib list>] — a fresh project dir
proj() {
    rm -rf "$W/$1"; mkdir -p "$W/$1"
    printf '[package]\nname = "%s"\nversion = "0.1.0"\ncyrius = "%s"\n\n[build]\nentry = "src/main.cyr"\noutput = "build/x"\n%b' "$1" "$VER" "$2" > "$W/$1/cyrius.cyml"
    [ -n "${3:-}" ] && printf '\n[deps]\nstdlib = [%s]\n' "$3" >> "$W/$1/cyrius.cyml"
    return 0
}
# cy <dir> <args...> — stdout to $W/out, stderr to $W/err, exit in RC
cy() { d=$1; shift; RC=0; ( cd "$W/$d" && HOME="$W/h" CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 "$W/cyrius" "$@" ) > "$W/out" 2> "$W/err" < /dev/null || RC=$?; }
marks() { cat "$W/out" "$W/err" | grep -c "^MARK-$1\$" || true; }
show() { cat "$W/out" "$W/err" | sed 's/^/      /' | head -8; }

# ── the corpus: tests/a.tcyr, tests/u/b.tcyr, tests/u/deep/c.tcyr, tests/empty/ ────────────
proj p ''
prog "$W/p/tests/a.tcyr" a 0
prog "$W/p/tests/u/b.tcyr" b 0
prog "$W/p/tests/u/deep/c.tcyr" c 0
mkdir -p "$W/p/tests/empty"; printf 'not a test\n' > "$W/p/tests/empty/readme.txt"

# ── 1 ──
cy p test tests/a.tcyr
if [ "$RC" = 0 ] && [ "$(marks a)" = 1 ] && [ "$(marks b)" = 0 ] && [ "$(marks c)" = 0 ]; then echo "  ok 1: cyrius test <file> runs that file only"
else fail "1: rc $RC, a $(marks a)x b $(marks b)x c $(marks c)x (want 0, 1, 0, 0)"; show; fi
proj p1 ''; prog "$W/p1/tests/bad.tcyr" bad 3
cy p1 test tests/bad.tcyr
if [ "$RC" != 0 ] && grep -q 'FAIL: tests/bad.tcyr (exit 3)' "$W/err"; then echo "  ok 1b: a failing <file> fails the run (rc $RC), named"
else fail "1b: rc $RC"; show; fi

# ── 2 ──
cy p test tests/u
if [ "$RC" = 0 ] && [ "$(marks a)" = 0 ] && [ "$(marks b)" = 1 ] && [ "$(marks c)" = 1 ] && grep -q '^2 passed, 0 failed$' "$W/out" && ! grep -q 'deprecated' "$W/err"; then
    echo "  ok 2: cyrius test <dir> walks it recursively (b, deep/c), nothing outside it, no notice: 2 passed"
else fail "2: rc $RC, a $(marks a)x b $(marks b)x c $(marks c)x"; show; fi

# ── 3 ──
proj p3 ''; prog "$W/p3/tests/u/ok.tcyr" ok 0; prog "$W/p3/tests/u/sub/bad.tcyr" bad 3
cy p3 test tests/u
if [ "$RC" = 1 ] && grep -q '^1 passed, 1 failed$' "$W/out" && grep -q 'FAIL: tests/u/sub/bad.tcyr (exit 3)' "$W/err"; then echo "  ok 3: a <dir> with a failing test: 1 passed, 1 failed, exit 1, the file named"
else fail "3: rc $RC"; show; fi

# ── 4 ──
cy p test tests/empty
if [ "$RC" = 1 ] && grep -q '^No .tcyr files found under tests/empty$' "$W/out"; then echo "  ok 4: a <dir> holding no .tcyr is a failure, named"
else fail "4: rc $RC"; show; fi

# ── 5 ──
cy p test tests tests/u ./tests/a.tcyr
if [ "$RC" = 0 ] && [ "$(marks a)" = 1 ] && [ "$(marks b)" = 1 ] && [ "$(marks c)" = 1 ] && grep -q '^3 passed, 0 failed$' "$W/out"; then
    echo "  ok 5: tests + tests/u + ./tests/a.tcyr — each file once: 3 passed"
else fail "5: rc $RC, a $(marks a)x b $(marks b)x c $(marks c)x (want 1 each, 3 passed)"; show; fi
cy p test tests/a.tcyr tests/empty
if [ "$RC" = 1 ] && grep -q '^No .tcyr files found under tests/empty$' "$W/out" && grep -q '^1 passed, 1 failed$' "$W/out"; then echo "  ok 5b: an empty <dir> among several operands is a counted, named failure"
else fail "5b: rc $RC"; show; fi

# ── 6 ──
cy p test
if [ "$RC" = 0 ] && [ "$(marks a)" = 1 ] && [ "$(marks b)" = 1 ] && [ "$(marks c)" = 1 ] && grep -q '^3 passed, 0 failed$' "$W/out"; then echo "  ok 6: bare cyrius test — every .tcyr under tests/, each once (unchanged)"
else fail "6: rc $RC, a $(marks a)x b $(marks b)x c $(marks c)x"; show; fi

# ── 7 ──
cy p test tests/u; cp "$W/out" "$W/new.out"; NRC=$RC
cy p tests tests/u
nl=$(grep -c . "$W/err" || true)
if [ "$RC" = "$NRC" ] && cmp -s "$W/out" "$W/new.out" && [ "$nl" = 1 ] \
    && grep -qF 'warn: `cyrius tests` is deprecated and goes in the next release; use `cyrius test tests/u`' "$W/err"; then
    echo "  ok 7: cyrius tests tests/u — one notice naming \`cyrius test tests/u\`, same stdout and exit as the new spelling"
else fail "7: rc $RC (new spelling $NRC), stderr $nl line(s), stdout $(cmp -s "$W/out" "$W/new.out" && echo same || echo differs)"; show; fi
cy p tests
if [ "$RC" = 0 ] && grep -qF 'use `cyrius test tests`' "$W/err" && grep -q '^3 passed, 0 failed$' "$W/out"; then echo "  ok 7b: bare cyrius tests names \`cyrius test tests\` and still runs tests/"
else fail "7b: rc $RC"; show; fi

[ "$FAIL" = 0 ] || { echo "FAIL: test_absorbs_tests — $FAIL row(s) failed"; exit 1; }
echo "PASS: test_absorbs_tests (cyrius test <file|dir>..., bare unchanged, tests = deprecated alias)"

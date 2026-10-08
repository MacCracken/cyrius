#!/bin/sh
# test_absorbs_tests.sh — 6.7.6 (Break 1, lane G). ONE test verb: `cyrius test <file>`,
# `cyrius test <dir>` (recursive), several operands (each file once) and a bare `cyrius test`
# (unchanged); `cyrius tests [dir]` is a deprecated alias for one release with a one-line notice
# naming the new spelling. And `[build] test_standalone = true` lets `cyrius test` run a corpus
# whose tests define a fn the [deps] stdlib prepend also defines — this repo's own.
#
# WHY: two verbs did one job and CLAUDE.md had to warn about the difference: `cyrius test <dir>`
# was `error: not a file`, exit 1, and the walk lived in `cyrius tests`. And `cyrius test <file>`
# inside this repo could not build the 22 .tcyr that define `fn run()`: the manifest's
# `[deps] stdlib` prepends lib/process.cyr, whose `fn run(cmd, arg1, arg2)` collides ("duplicate
# fn 'run' disagrees about arity"). check.sh, ci.yml and the cross-OS runner feed build/cycc
# directly, so nothing gated the wrapper over the repo's own corpus.
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
#   8  the run collision: [deps] stdlib carries process, a test defines `fn run()` — without the
#      key a duplicate-fn compile error; with `[build] test_standalone = true` it passes
#   9  the key really drops the prepend: a test calling strlen with no include passes WITHOUT the
#      key (the prepend supplies it) and fails to compile WITH it
#  10  `test_standalone = "yes"` is refused by name; the test is not run; exit 1
#  11  --print-config shows build.test_standalone from the manifest
#  12  THIS repo: a scratch copy of the real cyrius.cyml + VERSION + lib/ + build/cycc and every
#      tests/tcyr file defining `fn run()` (floor 22): `cyrius test tests` passes all of them;
#      the same copy with test_standalone deleted fails (the key is what makes it work)
#
# MUTATION LEDGER (6.7.6) — each RUN against a fresh scratch copy of the tree (cbt/ + lib/ +
# src/ + tests/tcyr + build/cycc + cyrius.cyml + VERSION + this gate); the unmutated copy PASSES
# and the gate exits 1 on each mutant, red rows as measured:
#   M1  cyrius.cyr: the single-dir `cmd_tests` arm dropped (`test <dir>` = not a file)  2 3 4 7 12 12b
#   M2  cyrius.cyr: the multi-operand loop calls cmd_test (no dir walk, no dedupe)      5 5b
#   M3  commands.cyr: _test_path without `_tests_first_run`, no `_tests_seen`           5
#   M4  cyrius.cyr: the `tests` branch without _tests_verb_deprecated                   7 7b
#   M5  commands.cyr: cmd_test never sets _skip_deps for test_standalone                8 9 12
#   M6  manifest.cyr: a non-bool test_standalone read as false, unnamed                 10
#   M7  cyrius.cyml: `test_standalone = true` deleted                                   12 (x2)
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
# A throwaway home whose pinned slot carries the tree's stdlib (rows 8-9 resolve [deps] stdlib).
mkdir -p "$W/home/bin" "$W/home/versions/$VER" "$W/h"
cp "$CC" "$W/home/bin/cycc"
cp -R lib "$W/home/versions/$VER/lib" || { echo "FAIL: test_absorbs_tests: could not stage the stdlib"; exit 1; }

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

# ── 8 ──
RUNFN='include "lib/syscalls.cyr"\nfn run(): i64 { return 7; }\nsyscall(1, 1, "MARK-run\\n", 9);\nsyscall(60, run() - 7);\n'
STD='"syscalls", "string", "alloc", "str", "fmt", "vec", "process"'
proj p8 '' "$STD"; mkdir -p "$W/p8/tests"; printf "$RUNFN" > "$W/p8/tests/run_fn.tcyr"
cy p8 test tests/run_fn.tcyr
if [ "$RC" != 0 ] && grep -q "duplicate fn 'run'" "$W/err" && [ "$(marks run)" = 0 ]; then echo "  ok 8a: premise — with the [deps] prepend, a test's own fn run() collides with lib/process.cyr (rc $RC)"
else fail "8a premise: rc $RC, no duplicate-fn error"; show; fi
proj p8 'test_standalone = true\n' "$STD"; mkdir -p "$W/p8/tests"; printf "$RUNFN" > "$W/p8/tests/run_fn.tcyr"
cy p8 test tests/run_fn.tcyr
if [ "$RC" = 0 ] && [ "$(marks run)" = 1 ]; then echo "  ok 8: [build] test_standalone = true — the same test compiles and passes"
else fail "8: rc $RC, run $(marks run)x"; show; fi

# ── 9 ──
NOINC='var n = strlen("abcd");\nsyscall(1, 1, "MARK-pre\\n", 9);\nsyscall(60, n - 4);\n'
proj p9 '' "$STD"; mkdir -p "$W/p9/tests"; printf "$NOINC" > "$W/p9/tests/pre.tcyr"
cy p9 test tests/pre.tcyr
R1=$RC; M1=$(marks pre)
proj p9 'test_standalone = true\n' "$STD"; mkdir -p "$W/p9/tests"; printf "$NOINC" > "$W/p9/tests/pre.tcyr"
cy p9 test tests/pre.tcyr
if [ "$R1" = 0 ] && [ "$M1" = 1 ] && [ "$RC" != 0 ] && [ "$(marks pre)" = 0 ] && grep -q 'FAIL: tests/pre.tcyr' "$W/err"; then
    echo "  ok 9: a test leaning on the prepend passes without the key and does not compile with it"
else fail "9: without the key rc $R1 ($M1 run), with it rc $RC ($(marks pre) run)"; show; fi

# ── 10 ──
proj p10 'test_standalone = "yes"\n'; prog "$W/p10/tests/a.tcyr" a 0
cy p10 test tests/a.tcyr
if [ "$RC" != 0 ] && grep -qF 'cyrius.cyml [build] test_standalone must be true or false' "$W/err" && [ "$(marks a)" = 0 ]; then echo "  ok 10: a non-bool test_standalone is refused by name; nothing runs"
else fail "10: rc $RC, a $(marks a)x"; show; fi

# ── 11 ──
cy p8 build --print-config
grep -qF '  build.test_standalone = true  (manifest: [build] test_standalone)' "$W/out" && echo "  ok 11: --print-config reports build.test_standalone" || { fail "11: no build.test_standalone row"; show; }

# ── 12: this repo's own corpus ──────────────────────────────────────────────────────────────
R="$W/repo"; mkdir -p "$R/build"
cp cyrius.cyml VERSION "$R/" && cp -R lib "$R/lib" && cp "$CC" "$R/build/cycc" || { echo "FAIL: test_absorbs_tests: could not stage the repo copy"; exit 1; }
grep -rl '^fn run(' tests/tcyr | sort > "$W/runfns"
NR=$(grep -c . "$W/runfns" || true)
[ "$NR" -ge 22 ] || fail "12: only $NR tests/tcyr files define fn run() (floor 22) — the reader is blind"
while read -r f; do mkdir -p "$R/$(dirname "$f")"; cp "$f" "$R/$f"; done < "$W/runfns"
grep -q '^test_standalone = true$' "$R/cyrius.cyml" || fail "12: cyrius.cyml does not declare [build] test_standalone = true"
RC=0; ( cd "$R" && HOME="$W/h" CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 "$W/cyrius" test tests ) > "$W/out" 2> "$W/err" < /dev/null || RC=$?
if [ "$RC" = 0 ] && grep -q "^$NR passed, 0 failed\$" "$W/out"; then echo "  ok 12: this repo's manifest — cyrius test tests runs all $NR fn-run() tests: $NR passed"
else fail "12: rc $RC, want $NR passed, 0 failed"; grep -E 'passed|FAIL' "$W/out" "$W/err" | head -6; fi
grep -v '^test_standalone = ' "$R/cyrius.cyml" > "$R/cyrius.cyml.new" && mv "$R/cyrius.cyml.new" "$R/cyrius.cyml"
RC=0; ( cd "$R" && HOME="$W/h" CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 "$W/cyrius" test tests ) > "$W/out" 2> "$W/err" < /dev/null || RC=$?
if [ "$RC" != 0 ] && grep -q "duplicate fn 'run'" "$W/err"; then echo "  ok 12b: the same copy without the key fails on the run collision (the key is the fix)"
else fail "12b: rc $RC without the key — the anti-vacuous half did not collide"; fi

[ "$FAIL" = 0 ] || { echo "FAIL: test_absorbs_tests — $FAIL row(s) failed"; exit 1; }
echo "PASS: test_absorbs_tests (cyrius test <file|dir>..., bare unchanged, tests = deprecated alias, [build] test_standalone runs this repo's corpus)"

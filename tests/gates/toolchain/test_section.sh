#!/bin/sh
# test_section.sh — 6.7.6 (Break 1, lane C, part T). The `[test]` section of cyrius.cyml: what
# `cyrius test` / `bench` / `fuzz` compiles get, and nothing else does. ADDITIVE: a manifest
# without the new keys behaves exactly as before (row A).
#
# WHY: test-only configuration had nowhere to live. `[build] test` sat among the production keys,
# `assert` / `bench` went into `[deps] stdlib` and from there into every production binary
# (hello world 94,160 -> 111,440 B) and every published sidecar, and a test define or fixture had
# to be spelled on the command line of every CI loop.
#
# ROWS (each program prints MARK-<name> and exits with its code)
#   A   additive: the same project without a [test] section — `cyrius test` runs [build] test
#       then tests/, output and exit unchanged
#   F1  `[test] files` is what a bare `cyrius test` runs first, then tests/
#   F2  `[build] test` alone is still read (the older spelling of the same key)
#   F3  both declared: `[test] files` is read, `[build] test` warned by name and not run
#   F4  a `[test] files` that is not a path / list is refused by name, exit 1
#   F5  a `[test] files` path that does not exist is a named failure under its own key
#   F6  `cyrius build --print-config` shows test.files and the key it came from
#   F7  a key nothing reads in [test] is warned by name (once), the run still passes
#   S1-S3  `[test] defines` and `[test] modules` reach `cyrius test`, `bench` and `fuzz` compiles
#          (fuzz keeps its [build] defines, 6.6.18); [build] defines still do not reach tests
#   S4-S5  `cyrius run` / `cyrius build` see neither (the production binary carries no TESTING)
#   S6-S7  -D and CYRIUS_DEFINES replace [test] defines (argument > environment > manifest)
#   S8     a [test] module that cannot be read is named; the test fails, not run
#   T1-T3  `[test] timeout`: --timeout > CYRIUS_TEST_TIMEOUT > [test] timeout (a spinning test
#          ends at 1s / 2s / 1s, named)
#   T4-T6  a refused --timeout / timeout / defines value is named and nothing runs
#   T7     --print-config shows test.modules / test.defines / test.timeout with their origins
#   L1     `[test] stdlib` leaves are vendored into lib/, locked, and prepended to a test that
#          includes nothing itself
#   L2-L3  `cyrius build` does not prepend them: the binary loses assert + bench, and a build
#          source calling assert_summary does not compile
#   L4     lib/ and cyrius.lock are identical whether a build or a test resolved (every resolve
#          vendors the test leaves; only the prepend is scoped)
#   L5     a manifest whose only dependency is [test] stdlib still resolves
#   L6-L7  a non-leaf name is refused by name (deps and test); a leaf the stdlib lacks fails
#   L8     --print-config shows test.stdlib
#   L9     `cyrius distlib`: the published sidecar names no [test] stdlib leaf
#
# MUTATION LEDGER (6.7.6) — each mutant built in a SCRATCH copy of the tree (cbt/ + lib/ + src/ +
# build/cycc + VERSION + this gate), the gate run against it; the unmutated copy PASSES, and each
# mutant turns the rows named RED:
#   M1  manifest.cyr: _cfg_test_files never reads [test] files                         F1 F3 F4 F5 F6
#   M2  manifest.cyr: _cfg_test_files never reads [build] test                         A F2 F3 F6b
#   M3  manifest.cyr: the both-declared warning removed                                F3
#   M4  deps.cyr: _dep_warn_manifest no longer warns [test]'s keys                     F7
#   M5  build.cyr: [test] modules never prepended                                     S1 S2 S3 S6 S7 S8
#   M6  manifest.cyr: _tc_for drops [test] defines                                    S1 S2 S3
#   M7  manifest.cyr: _tc_for ignores -D                                              S6
#   M8  build.cyr: _run_timeout_ms ignores [test] timeout (the outer 60 s bound ends T1)  T1
#   M9  build.cyr: [test] timeout read before CYRIUS_TEST_TIMEOUT                     T2
#   M10 manifest.cyr: --timeout parsed and dropped                                    T3
#   M11 deps.cyr: _auto_deps hands [test] defines to every resolving verb             S4
#   M11b manifest.cyr: _cfg_apply_build appends [test] defines to cyrius build        S5
#   M12 manifest.cyr: _tc_scope_verb leaves bench out of the test scope               S2
#   M13 deps.cyr: _deps_test_scope pulls the leaves top-level (onto _dep_includes)     L2 L3
#   M14 build.cyr: the test-scope includes are never prepended                         L1 L5
#   M15 deps.cyr: _auto_deps ignores [test] stdlib when there is no [deps]            L5
#   M16 deps.cyr: phase 4 (the test scope) dropped from cmd_deps                      L1 L4 L5 L6 L7
#   M17 commands.cyr: distlib seeds the sidecar with [test] stdlib (the pre-6.6.18 union)  L9
#   M18 manifest.cyr: _tc_resolve_leaves skips the leaf-name rule                      L6
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=test_section
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: $G: no compiler at $CC"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
unset CYRIUS_LOCAL CYRIUS_LOCKED CYRIUS_LIB_OVERLAY CYRIUS_DEFINES CYRIUS_TEST_TIMEOUT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/build.err" || { echo "FAIL: $G: cbt/cyrius.cyr does not build"; tail -3 "$W/build.err"; exit 1; }
[ "$(wc -c < "$W/cyrius")" -ge 20000 ] || { echo "FAIL: $G: cbt/cyrius.cyr built a $(wc -c < "$W/cyrius")-byte binary"; exit 1; }
chmod +x "$W/cyrius"
VER=$(tr -d '[:space:]' < VERSION)
mkdir -p "$W/home/bin" "$W/home/versions/$VER" "$W/h"
cp "$CC" "$W/home/bin/cycc"
cp -R lib "$W/home/versions/$VER/lib" || { echo "FAIL: $G: could not stage the stdlib"; exit 1; }

# prog <path> <marker> <exit>
prog() { mkdir -p "$(dirname "$1")"; printf 'syscall(1, 1, "MARK-%s\\n", %d);\nsyscall(60, %d);\n' "$2" $((${#2} + 6)) "$3" > "$1"; }
# proj <name> — a fresh project dir whose manifest is the [package] head plus stdin
proj() {
    rm -rf "$W/$1"; mkdir -p "$W/$1"
    { printf '[package]\nname = "%s"\nversion = "0.1.0"\ncyrius = "%s"\n\n' "$1" "$VER"; cat; } > "$W/$1/cyrius.cyml"
}
# cy <dir> <args...> — stdout to $W/out, stderr to $W/err, exit in RC
cy() { d=$1; shift; RC=0; ( cd "$W/$d" && HOME="$W/h" CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 "$W/cyrius" "$@" ) > "$W/out" 2> "$W/err" < /dev/null || RC=$?; }
marks() { cat "$W/out" "$W/err" | grep -c "^MARK-$1\$" || true; }
show() { cat "$W/out" "$W/err" | sed 's/^/      /' | head -12; }

# ── A: additive ──────────────────────────────────────────────────────────────────────────
proj a <<'EOF'
[build]
entry = "src/main.cyr"
test = "src/test.cyr"
EOF
prog "$W/a/src/test.cyr" decl 0; prog "$W/a/tests/w.tcyr" walk 0
cy a test
if [ "$RC" = 0 ] && [ "$(marks decl)" = 1 ] && [ "$(marks walk)" = 1 ] && grep -q '^2 passed, 0 failed$' "$W/out" && [ ! -s "$W/err" ]; then
    echo "  ok A: no [test] section — [build] test then tests/, 2 passed, nothing on stderr (unchanged)"
else fail "A: rc $RC, decl $(marks decl)x walk $(marks walk)x"; show; fi

# ── F1 ──
proj f1 <<'EOF'
[test]
files = ["src/t1.cyr", "src/t2.cyr"]
EOF
prog "$W/f1/src/t1.cyr" t1 0; prog "$W/f1/src/t2.cyr" t2 0; prog "$W/f1/tests/w.tcyr" walk 0
cy f1 test
if [ "$RC" = 0 ] && [ "$(marks t1)" = 1 ] && [ "$(marks t2)" = 1 ] && [ "$(marks walk)" = 1 ] && grep -q '^3 passed, 0 failed$' "$W/out" \
    && [ "$(cat "$W/out" | grep '^MARK' | head -1)" = MARK-t1 ]; then
    echo "  ok F1: [test] files run first (t1, t2), then tests/: 3 passed"
else fail "F1: rc $RC, t1 $(marks t1)x t2 $(marks t2)x walk $(marks walk)x"; show; fi

# ── F2 ──
proj f2 <<'EOF'
[build]
test = "src/old.cyr"
EOF
prog "$W/f2/src/old.cyr" old 0
cy f2 test
if [ "$RC" = 0 ] && [ "$(marks old)" = 1 ] && grep -q '^1 passed, 0 failed$' "$W/out"; then echo "  ok F2: [build] test alone is still read"
else fail "F2: rc $RC, old $(marks old)x"; show; fi

# ── F3 ──
proj f3 <<'EOF'
[build]
test = "src/old.cyr"

[test]
files = "src/new.cyr"
EOF
prog "$W/f3/src/old.cyr" old 0; prog "$W/f3/src/new.cyr" new 0
cy f3 test
if [ "$RC" = 0 ] && [ "$(marks new)" = 1 ] && [ "$(marks old)" = 0 ] \
    && grep -qF 'warn: cyrius.cyml [build] test is not read: [test] files is declared too' "$W/err"; then
    echo "  ok F3: both declared — [test] files runs, [build] test is warned by name and not run"
else fail "F3: rc $RC, new $(marks new)x old $(marks old)x"; show; fi

# ── F4 ──
proj f4 <<'EOF'
[test]
files = 3
EOF
prog "$W/f4/tests/w.tcyr" walk 0
cy f4 test
if [ "$RC" = 1 ] && grep -qF 'cyrius.cyml [test] files must be a path or an array of paths' "$W/err" && [ "$(marks walk)" = 0 ]; then
    echo "  ok F4: [test] files = 3 is refused by name, nothing runs, exit 1"
else fail "F4: rc $RC, walk $(marks walk)x"; show; fi

# ── F5 ──
proj f5 <<'EOF'
[test]
files = ["src/tset.cyr"]
EOF
prog "$W/f5/tests/w.tcyr" walk 0
cy f5 test
if [ "$RC" = 1 ] && grep -qF 'cyrius.cyml [test] files names a path that does not exist: src/tset.cyr' "$W/err"; then
    echo "  ok F5: a [test] files path that does not exist is a named failure under its own key (rc 1)"
else fail "F5: rc $RC"; show; fi

# ── F6 ──
cy f3 build --print-config
if [ "$RC" = 0 ] && grep -qF '  test.files = ["src/new.cyr"]  (manifest: [test] files)' "$W/out" \
    && grep -qF '  build.test = ["src/old.cyr"]  (manifest: [build] test)' "$W/out"; then
    echo "  ok F6: --print-config shows test.files from [test] files (and build.test as written)"
else fail "F6: rc $RC"; show; fi
cy f2 build --print-config
grep -qF '  test.files = ["src/old.cyr"]  (manifest: [build] test)' "$W/out" && echo "  ok F6b: --print-config: test.files read through [build] test" || { fail "F6b"; show; }

# ── F7 ──
proj f7 <<'EOF'
[test]
fixtures = ["x"]
EOF
prog "$W/f7/tests/w.tcyr" walk 0
cy f7 test
n=$(grep -c 'warn: cyrius.cyml \[test\] fixtures is not a known key and nothing reads it' "$W/err" || true)
if [ "$RC" = 0 ] && [ "$n" = 1 ] && [ "$(marks walk)" = 1 ]; then echo "  ok F7: an unknown [test] key is warned by name, once; the run passes"
else fail "F7: rc $RC, warned $n time(s)"; show; fi


# ── the test scope: [test] defines / modules / timeout reach test, bench and fuzz only ─────
proj s <<'EOF'
[build]
entry = "src/main.cyr"
defines = ["BUILDDEF"]

[test]
modules = ["support/fix.cyr"]
defines = ["TESTING"]
EOF
mkdir -p "$W/s/support" "$W/s/src" "$W/s/tests" "$W/s/benches" "$W/s/fuzz"
printf 'fn fix_v(): i64 { return 5; }\n' > "$W/s/support/fix.cyr"
# a unit that marks each define it sees and calls the [test] module's fn
UNIT='var r = fix_v() - 5;\n#ifdef TESTING\nsyscall(1, 1, "MARK-testing\\n", 13);\n#endif\n#ifdef BUILDDEF\nsyscall(1, 1, "MARK-builddef\\n", 14);\n#endif\n#ifdef OTHER\nsyscall(1, 1, "MARK-other\\n", 11);\n#endif\n#ifdef ENVD\nsyscall(1, 1, "MARK-envd\\n", 10);\n#endif\nsyscall(60, r);\n'
printf "$UNIT" > "$W/s/tests/u.tcyr"
printf "$UNIT" > "$W/s/benches/u.bcyr"
printf "$UNIT" > "$W/s/fuzz/u.fcyr"
printf '#ifdef TESTING\nsyscall(1, 1, "MARK-testing\\n", 13);\n#endif\nsyscall(60, 0);\n' > "$W/s/src/main.cyr"

cy s test tests/u.tcyr
if [ "$RC" = 0 ] && [ "$(marks testing)" = 1 ] && [ "$(marks builddef)" = 0 ]; then
    echo "  ok S1: cyrius test — [test] defines and [test] modules reach the test; [build] defines do not (as before)"
else fail "S1: rc $RC, testing $(marks testing)x builddef $(marks builddef)x"; show; fi
cy s bench benches/u.bcyr
if [ "$RC" = 0 ] && [ "$(marks testing)" = 1 ] && [ "$(marks builddef)" = 0 ]; then echo "  ok S2: cyrius bench — the same"
else fail "S2: rc $RC, testing $(marks testing)x builddef $(marks builddef)x"; show; fi
cy s fuzz fuzz/u.fcyr
# a harness's output lands on its padded header line, so count the markers anywhere
ft=$(grep -c 'MARK-testing' "$W/out" || true); fb=$(grep -c 'MARK-builddef' "$W/out" || true)
if [ "$RC" = 0 ] && [ "$ft" = 1 ] && [ "$fb" = 1 ]; then
    echo "  ok S3: cyrius fuzz — [build] defines (since 6.6.18) AND [test] defines, and [test] modules"
else fail "S3: rc $RC, testing ${ft}x builddef ${fb}x"; show; fi
cy s run src/main.cyr
if [ "$RC" = 0 ] && [ "$(marks testing)" = 0 ]; then echo "  ok S4: cyrius run — no [test] define"
else fail "S4: rc $RC, testing $(marks testing)x"; show; fi
cy s build src/main.cyr build/m
( cd "$W/s" && ./build/m ) > "$W/out" 2>&1
if [ "$(marks testing)" = 0 ] && [ -x "$W/s/build/m" ]; then echo "  ok S5: cyrius build — no [test] define in the production binary"
else fail "S5: testing $(marks testing)x"; show; fi
cy s test -D OTHER tests/u.tcyr
if [ "$RC" = 0 ] && [ "$(marks other)" = 1 ] && [ "$(marks testing)" = 0 ]; then echo "  ok S6: -D OTHER replaces [test] defines (argument > manifest)"
else fail "S6: rc $RC, other $(marks other)x testing $(marks testing)x"; show; fi
RC=0; ( cd "$W/s" && HOME="$W/h" CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 CYRIUS_DEFINES=ENVD "$W/cyrius" test tests/u.tcyr ) > "$W/out" 2> "$W/err" < /dev/null || RC=$?
if [ "$RC" = 0 ] && [ "$(marks envd)" = 1 ] && [ "$(marks testing)" = 0 ]; then echo "  ok S7: CYRIUS_DEFINES=ENVD replaces [test] defines (environment > manifest)"
else fail "S7: rc $RC, envd $(marks envd)x testing $(marks testing)x"; show; fi

proj s8 <<'EOF'
[test]
modules = ["support/nope.cyr"]
EOF
prog "$W/s8/tests/a.tcyr" a 0
cy s8 test tests/a.tcyr
if [ "$RC" = 1 ] && grep -qF 'test module cannot be read (declared in [test] modules): support/nope.cyr' "$W/err" && [ "$(marks a)" = 0 ]; then
    echo "  ok S8: a [test] module that cannot be read is named; the test fails, not run"
else fail "S8: rc $RC, a $(marks a)x"; show; fi

# timeout: --timeout > CYRIUS_TEST_TIMEOUT > [test] timeout > 300
proj t <<'EOF'
[test]
timeout = 1
EOF
mkdir -p "$W/t/tests"; printf 'while (1 == 1) { }\nsyscall(60, 0);\n' > "$W/t/tests/spin.tcyr"
# cyt <env...> -- <args...>: as cy in $W/t, under an outer 60 s bound (a mutant that loses the
# deadline falls back to 300 s; the bound keeps the gate's own run short)
cyt() { RC=0; ( cd "$W/t" && env HOME="$W/h" CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 "$@" ) > "$W/out" 2> "$W/err" < /dev/null || RC=$?; }
cyt timeout 60 "$W/cyrius" test tests/spin.tcyr
if [ "$RC" != 0 ] && grep -qF 'FAIL: tests/spin.tcyr (timed out after 1s' "$W/err"; then echo "  ok T1: [test] timeout = 1 ends a spinning test after 1s, named"
else fail "T1: rc $RC"; show; fi
cyt CYRIUS_TEST_TIMEOUT=2 timeout 60 "$W/cyrius" test tests/spin.tcyr
if [ "$RC" != 0 ] && grep -qF '(timed out after 2s' "$W/err"; then echo "  ok T2: CYRIUS_TEST_TIMEOUT=2 beats [test] timeout = 1"
else fail "T2: rc $RC"; show; fi
cyt CYRIUS_TEST_TIMEOUT=2 timeout 60 "$W/cyrius" test --timeout 1 tests/spin.tcyr
if [ "$RC" != 0 ] && grep -qF '(timed out after 1s' "$W/err"; then echo "  ok T3: --timeout 1 beats CYRIUS_TEST_TIMEOUT=2"
else fail "T3: rc $RC"; show; fi
cyt timeout 60 "$W/cyrius" test --timeout -1 tests/spin.tcyr
if [ "$RC" = 1 ] && grep -qF -- '--timeout needs a whole number of seconds (0 = no deadline)' "$W/err" && ! grep -q 'timed out' "$W/err"; then
    echo "  ok T4: --timeout -1 is refused by name before anything runs"
else fail "T4: rc $RC"; show; fi
proj t5 <<'EOF'
[test]
timeout = "10"
EOF
prog "$W/t5/tests/a.tcyr" a 0
cy t5 test
if [ "$RC" = 1 ] && grep -qF 'cyrius.cyml [test] timeout must be a whole number of seconds' "$W/err" && [ "$(marks a)" = 0 ]; then
    echo "  ok T5: timeout = \"10\" is refused by name; nothing runs"
else fail "T5: rc $RC, a $(marks a)x"; show; fi
proj t6 <<'EOF'
[test]
defines = 3
EOF
prog "$W/t6/tests/a.tcyr" a 0
cy t6 test
if [ "$RC" = 1 ] && grep -qF 'cyrius.cyml [test] defines must be a string or an array of strings' "$W/err" && [ "$(marks a)" = 0 ]; then
    echo "  ok T6: defines = 3 is refused by name; nothing runs"
else fail "T6: rc $RC, a $(marks a)x"; show; fi
cy s build --print-config
if [ "$RC" = 0 ] && grep -qF '  test.modules = ["support/fix.cyr"]  (manifest: [test] modules)' "$W/out" \
    && grep -qF '  test.defines = ["TESTING"]  (manifest: [test] defines)' "$W/out" \
    && grep -qF '  test.timeout = 300  (default)' "$W/out" && grep -qF '  build.defines = ["BUILDDEF"]  (manifest: [build] defines)' "$W/out"; then
    echo "  ok T7: --print-config shows test.modules / test.defines / test.timeout and where each came from"
else fail "T7: rc $RC"; show; fi

# ── [test] stdlib: vendored by every resolve, prepended in the test scope only ─────────────
# lproj <name> <deps-stdlib-list> <test-stdlib-list or ""> — main.cyr calls an assert fn; the test
# uses assert with no include of its own
lproj() {
    rm -rf "$W/$1"; mkdir -p "$W/$1/src" "$W/$1/tests"
    { printf '[package]\nname = "%s"\nversion = "0.1.0"\ncyrius = "%s"\n\n[build]\nentry = "src/main.cyr"\noutput = "build/m"\n' "$1" "$VER"
      [ -n "$2" ] && printf '\n[deps]\nstdlib = [%s]\n' "$2"
      [ -n "$3" ] && printf '\n[test]\nstdlib = [%s]\n' "$3"
      true; } > "$W/$1/cyrius.cyml"
    printf 'fn main(): i64 {\n    println("hello");\n    return 0;\n}\nvar r = main();\nsyscall(60, r);\n' > "$W/$1/src/main.cyr"
    printf 'fn main() {\n    alloc_init();\n    assert(1, "one");\n    assert_eq(1 + 1, 2, "two");\n    return assert_summary();\n}\nsyscall(60, main());\n' > "$W/$1/tests/a.tcyr"
}
PROD='"string", "fmt", "alloc", "io", "vec", "str", "syscalls"'
lproj la "$PROD, \"assert\", \"bench\"" ""
lproj lb "$PROD" '"assert", "bench"'
cy la test; ra=$RC
cy lb test
if [ "$ra" = 0 ] && [ "$RC" = 0 ] && grep -q '^1 passed, 0 failed$' "$W/out" && [ -f "$W/lb/lib/assert.cyr" ] && [ -f "$W/lb/lib/bench.cyr" ] \
    && grep -q 'lib/assert.cyr' "$W/lb/cyrius.lock" && grep -q 'lib/bench.cyr' "$W/lb/cyrius.lock"; then
    echo "  ok L1: [test] stdlib = assert, bench — vendored into lib/, locked, and prepended to the test (no include of its own)"
else fail "L1: rc $RC (assert in [deps]: $ra)"; show; fi
cy la build; cy lb build
sa=$(wc -c < "$W/la/build/m" 2>/dev/null || echo 0); sb=$(wc -c < "$W/lb/build/m" 2>/dev/null || echo 0)
if [ "$sb" -gt 0 ] && [ "$sa" -gt "$sb" ]; then echo "  ok L2: the production binary loses assert + bench: $sa -> $sb bytes"
else fail "L2: sizes [deps] $sa, [test] $sb"; fi
printf 'var r = assert_summary();\nsyscall(60, 0);\n' > "$W/lb/src/main.cyr"
cy lb build
if [ "$RC" != 0 ] && grep -q "assert_summary" "$W/out" "$W/err"; then echo "  ok L3: cyrius build has no [test] stdlib in scope (assert_summary is undefined there)"
else fail "L3: rc $RC"; show; fi
cp -R "$W/lb" "$W/lc"; rm -rf "$W/lc/lib" "$W/lc/cyrius.lock"; cp -R "$W/lb" "$W/ld"; rm -rf "$W/ld/lib" "$W/ld/cyrius.lock"
cy lc build; cy ld test tests/a.tcyr
if [ -f "$W/lc/lib/assert.cyr" ] && diff -r "$W/lc/lib" "$W/ld/lib" > /dev/null && cmp -s "$W/lc/cyrius.lock" "$W/ld/cyrius.lock"; then
    echo "  ok L4: lib/ and cyrius.lock are the same whether a build or a test resolved them"
else fail "L4: lib/ or cyrius.lock differ between a build and a test resolve"; diff -r "$W/lc/lib" "$W/ld/lib" | head -3; fi
lproj le "" '"string", "fmt", "alloc", "syscalls", "vec", "assert"'
cy le test
if [ "$RC" = 0 ] && grep -q '^1 passed, 0 failed$' "$W/out" && [ -f "$W/le/lib/assert.cyr" ]; then echo "  ok L5: no [deps] at all — [test] stdlib alone still resolves and is prepended"
else fail "L5: rc $RC"; show; fi
lproj lf "$PROD" '"assert", "../x"'
cy lf deps; rd=$RC; grep -qF "error: cyrius.cyml [test] stdlib names '../x', which is not a stdlib leaf name" "$W/err"; gd=$?
cy lf test
if [ "$rd" = 1 ] && [ "$gd" = 0 ] && [ "$RC" = 1 ] && grep -qF "error: cyrius.cyml [test] stdlib names '../x', which is not a stdlib leaf name" "$W/err" && [ ! -f "$W/lf/lib/assert.cyr" ]; then
    echo "  ok L6: a [test] stdlib entry that is not a leaf name is refused by name (deps and test) before anything is vendored"
else fail "L6: deps rc $rd (named: $gd), test rc $RC"; show; fi
lproj lg "$PROD" '"assert", "nosuchleaf"'
cy lg test
if [ "$RC" = 1 ] && grep -q 'nosuchleaf' "$W/err" && [ "$(grep -c '^1 passed' "$W/out")" = 0 ]; then echo "  ok L7: a [test] stdlib leaf the stdlib does not have fails the resolve, named"
else fail "L7: rc $RC"; show; fi
cy lb build --print-config
grep -qF '  test.stdlib = ["assert", "bench"]  (manifest: [test] stdlib)' "$W/out" && echo "  ok L8: --print-config shows test.stdlib" || { fail "L8"; show; }
# L9: the published sidecar — a bundle in a project whose tests declare assert never names it
# (the distlib verify needs cycc and cycc_aarch64 beside the CLI)
mkdir -p "$W/tools"; cp "$W/cyrius" "$CC" "$W/tools/" 2>/dev/null
if ( "$CC" < src/main_aarch64.cyr > "$W/tools/cycc_aarch64" ) 2> /dev/null && chmod +x "$W/tools/cycc_aarch64" "$W/tools/cyrius"; then
    lproj lh "$PROD" '"assert", "bench"'
    printf '\n[lib]\nmodules = ["src/lh.cyr"]\n' >> "$W/lh/cyrius.cyml"
    printf 'fn lh_add(a, b): i64 { return a + b; }\nfn lh_show(s): i64 { println(s); return 0; }\n' > "$W/lh/src/lh.cyr"
    RC=0; ( cd "$W/lh" && HOME="$W/h" CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 "$W/tools/cyrius" distlib ) > "$W/out" 2> "$W/err" < /dev/null || RC=$?
    if [ "$RC" = 0 ] && [ -f "$W/lh/dist/lh.cyr" ] && ! grep -qx 'assert\|bench' "$W/lh/dist/lh.deps" 2>/dev/null; then
        echo "  ok L9: cyrius distlib — the sidecar names no [test] stdlib leaf ($(grep -v '^#' "$W/lh/dist/lh.deps" 2>/dev/null | tr '\n' ' '))"
    else fail "L9: rc $RC"; show; cat "$W/lh/dist/lh.deps" 2>/dev/null | sed 's/^/      /'; fi
else echo "  skip L9: could not stage cycc_aarch64 beside the CLI"; fi
[ "$FAIL" = 0 ] || { echo "FAIL: $G ($FAIL row(s))"; exit 1; }
echo "PASS: $G"

#!/bin/sh
# test_cyml_per_directory.sh — 6.7.6 (Break 1, lane C, part T). A `test.cyml` beside a project's
# tests: [test] keys (stdlib, modules, defines, timeout) and [test.embed] for every test-scope
# unit under its directory — each level APPENDING to the lists above it (cyrius.cyml's [test],
# ./test.cyml, tests/test.cyml, tests/net/test.cyml, …), an inner `timeout` REPLACING the outer,
# its paths relative to its own directory. It carries no pin and no dependencies — any other
# table is refused by name — so there is nothing in it to drift from the project (agnos keeps 21
# per-test manifests whose pins a script forces equal to the root's). `cyrius deps` vendors the
# stdlib leaves of every test.cyml beside cyrius.cyml, under tests/, benches/ and fuzz/, and on the
# way to [test] files.
#
# ROWS
#   C1  levels append: tests/net/x.tcyr sees ROOTDEF (cyrius.cyml) + LVL1 (tests/test.cyml) + LVL2
#       (tests/net/test.cyml), tests/test.cyml's module (support/f1.cyr, relative to tests/) and
#       tests/net/test.cyml's embed (data.bin, relative to tests/net/); tests/y.tcyr sees LVL1 only
#   C2  an inner `timeout = 1` replaces the outer 5: a spinning tests/net unit ends after 1s
#   C3  a project with NO [deps] and no [test]: tests/test.cyml's stdlib = ["assert"] alone makes
#       the resolve vendor + lock assert, and the test compiles with it
#   C4  a test.cyml carrying [package] / a cyrius pin, or [deps], is refused by name; its units fail
#       (not compiled); a unit outside its directory still passes
#   C5  `files` in a test.cyml is refused by name (what a bare `cyrius test` runs is the project's)
#   C6  a key nothing reads in a test.cyml's [test] is warned by name, once
#   C7  `cyrius build` of a test source ignores test.cyml (f1_v undefined there)
#   C8  a unit outside the project (`cyrius test ../other/t.tcyr`) gets no test.cyml of its own
#       directory's
#   C9  a test.cyml outside the discovery roots: its leaf is named as not vendored when the unit is
#       an operand; with that directory in [test] files the resolve vendors it and the unit passes
#   C10 bench and fuzz units honour test.cyml (benches/test.cyml, fuzz/test.cyml defines)
#   C11 a directory under tests/ that cannot be listed is WARNED by name and the resolve proceeds (a
#       build must not fail on it; a unit needing a leaf from an unread test.cyml fails by name, and
#       the walk that runs those tests fails on the directory itself)
#
# MUTATION LEDGER (6.7.6) — each mutant built in a SCRATCH copy of the tree, the gate run against
# it; the unmutated copy PASSES, and each mutant turns the rows named RED:
#   M1  manifest.cyr: _tc_for never reads the unit's directory chain    C1 C2 C3 C4 C5 C6 C9 C10
#   M2  manifest.cyr: _tc_merge keeps the OUTER timeout                                 C2
#   M3  manifest.cyr: a test.cyml's tables and keys are not checked                     C4 C5 C6
#   M4  manifest.cyr: the resolver reads no test.cyml (cyrius.cyml's [test] stdlib only) C3 C9b
#   M5  manifest.cyr: a test.cyml's paths are taken relative to the project root        C1 C2
#   M6  manifest.cyr: _tc_unit_dir lets a `..` component through                        C8
#   M7  manifest.cyr: discovery skips the directories of [test] files                   C9b
#   M8  manifest.cyr: an unlistable directory is skipped by the discovery walk, silently  C11
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
G=test_cyml_per_directory
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: $G: no compiler at $CC"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
unset CYRIUS_LOCAL CYRIUS_LOCKED CYRIUS_LIB_OVERLAY CYRIUS_DEFINES CYRIUS_TEST_TIMEOUT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
"$CC" < cbt/cyrius.cyr > "$W/cyrius" 2> "$W/build.err" || { echo "FAIL: $G: cbt/cyrius.cyr does not build"; tail -3 "$W/build.err"; exit 1; }
chmod +x "$W/cyrius"
VER=$(tr -d '[:space:]' < VERSION)
mkdir -p "$W/home/bin" "$W/home/versions/$VER" "$W/h"
cp "$CC" "$W/home/bin/cycc"
cp -R lib "$W/home/versions/$VER/lib" || { echo "FAIL: $G: could not stage the stdlib"; exit 1; }
cy() { d=$1; shift; RC=0; ( cd "$W/$d" && HOME="$W/h" CYRIUS_HOME="$W/home" CYRIUS_RESOLVED=1 CYRIUS_NO_WARN_PIN_DRIFT=1 timeout 120 "$W/cyrius" "$@" ) > "$W/out" 2> "$W/err" < /dev/null || RC=$?; }
show() { cat "$W/out" "$W/err" | sed 's/^/      /' | head -12; }
# proj <name> — the [package] head plus stdin
proj() { rm -rf "$W/$1"; mkdir -p "$W/$1"; { printf '[package]\nname = "%s"\nversion = "0.1.0"\ncyrius = "%s"\n\n' "$1" "$VER"; cat; } > "$W/$1/cyrius.cyml"; }
# lv <path> <want> — a .tcyr whose exit is 0 only when the defines it sees add up to <want>
# (ROOTDEF 1, LVL1 10, LVL2 100, OTHERDEF 1000)
lv() {
    mkdir -p "$(dirname "$1")"
    printf 'var lv = 0;\n#ifdef ROOTDEF\nlv = lv + 1;\n#endif\n#ifdef LVL1\nlv = lv + 10;\n#endif\n#ifdef LVL2\nlv = lv + 100;\n#endif\n#ifdef OTHERDEF\nlv = lv + 1000;\n#endif\n%bsyscall(60, lv - %d);\n' "${3:-}" "$2" > "$1"
}

# ── C1 / C2 ──
proj p <<'EOF'
[build]
entry = "src/main.cyr"

[deps]
stdlib = ["syscalls"]

[test]
defines = ["ROOTDEF"]
EOF
mkdir -p "$W/p/tests/net" "$W/p/tests/support" "$W/p/src"
printf '[test]\ndefines = ["LVL1"]\nmodules = ["support/f1.cyr"]\ntimeout = 5\n' > "$W/p/tests/test.cyml"
printf '[test]\ndefines = ["LVL2"]\ntimeout = 1\n\n[test.embed]\nNETDATA = "data.bin"\n' > "$W/p/tests/net/test.cyml"
printf 'fn f1_v(): i64 { return 11; }\n' > "$W/p/tests/support/f1.cyr"
printf 'netdata' > "$W/p/tests/net/data.bin"
lv "$W/p/tests/net/x.tcyr" 111 'lv = lv + f1_v() - 11 + NETDATA_len() - 7;\n'
lv "$W/p/tests/y.tcyr" 11 'lv = lv + f1_v() - 11;\n'
printf 'syscall(60, 0);\n' > "$W/p/src/main.cyr"
cy p test tests/net/x.tcyr tests/y.tcyr
if [ "$RC" = 0 ] && grep -q '^2 passed, 0 failed$' "$W/out"; then
    echo "  ok C1: levels append — tests/net sees ROOTDEF+LVL1+LVL2, tests/ module and the tests/net embed; tests/ sees LVL1 only"
else fail "C1: rc $RC"; show; fi
printf 'while (1 == 1) { }\nsyscall(60, 0);\n' > "$W/p/tests/net/spin.tcyr"
cy p test tests/net/spin.tcyr
if [ "$RC" != 0 ] && grep -qF 'FAIL: tests/net/spin.tcyr (timed out after 1s' "$W/err"; then echo "  ok C2: tests/net's timeout = 1 replaces tests/'s 5"
else fail "C2: rc $RC"; show; fi
rm -f "$W/p/tests/net/spin.tcyr"

# ── C3 ──
proj q <<'EOF'
EOF
mkdir -p "$W/q/tests"
printf '[test]\nstdlib = ["string", "fmt", "alloc", "syscalls", "vec", "assert"]\n' > "$W/q/tests/test.cyml"
printf 'fn main() {\n    alloc_init();\n    assert_eq(2, 2, "two");\n    return assert_summary();\n}\nsyscall(60, main());\n' > "$W/q/tests/a.tcyr"
cy q test
if [ "$RC" = 0 ] && grep -q '^1 passed, 0 failed$' "$W/out" && [ -f "$W/q/lib/assert.cyr" ] && grep -q 'lib/assert.cyr' "$W/q/cyrius.lock"; then
    echo "  ok C3: a test.cyml's stdlib alone (no [deps], no [test]) is vendored, locked and prepended"
else fail "C3: rc $RC"; show; fi

# ── C4 / C5 / C6 ──
proj r <<'EOF'
[test]
defines = ["ROOTDEF"]
EOF
mkdir -p "$W/r/tests/bad1" "$W/r/tests/bad2" "$W/r/tests/bad3" "$W/r/tests/ok"
printf '[package]\ncyrius = "%s"\n\n[test]\ndefines = ["LVL1"]\n' "$VER" > "$W/r/tests/bad1/test.cyml"
printf '[test]\ndefines = ["LVL1"]\n\n[deps]\nstdlib = ["assert"]\n' > "$W/r/tests/bad2/test.cyml"
printf '[test]\nfiles = ["x.tcyr"]\n' > "$W/r/tests/bad3/test.cyml"
printf '[test]\ndefines = ["LVL1"]\nfixture = "x"\n' > "$W/r/tests/ok/test.cyml"
lv "$W/r/tests/bad1/a.tcyr" 11; lv "$W/r/tests/bad2/a.tcyr" 11; lv "$W/r/tests/bad3/a.tcyr" 11
lv "$W/r/tests/ok/a.tcyr" 11; lv "$W/r/tests/ok/b.tcyr" 11
cy r test tests/bad1 tests/bad2 tests/ok
if [ "$RC" = 1 ] && grep -qF 'error: tests/bad1/test.cyml: [package] is not read: a test.cyml holds [test] and [test.embed] only' "$W/err" \
    && grep -qF 'error: tests/bad2/test.cyml: [deps] is not read' "$W/err" \
    && grep -qF 'FAIL: tests/bad1/a.tcyr (not compiled' "$W/err" && grep -qF 'FAIL: tests/bad2/a.tcyr (not compiled' "$W/err" \
    && grep -q '^2 passed, 2 failed$' "$W/out"; then
    echo "  ok C4: a test.cyml with [package] (a pin) or [deps] is refused by name; its units fail, tests/ok still passes"
else fail "C4: rc $RC"; show; fi
cy r test tests/bad3
if [ "$RC" = 1 ] && grep -qF 'error: tests/bad3/test.cyml: [test] files is not read here' "$W/err"; then echo "  ok C5: [test] files in a test.cyml is refused by name"
else fail "C5: rc $RC"; show; fi
cy r test tests/ok
n=$(grep -c 'warn: tests/ok/test.cyml \[test\] fixture is not a known key' "$W/err" || true)
if [ "$RC" = 0 ] && [ "$n" = 1 ]; then echo "  ok C6: an unknown key in a test.cyml is warned by name, once for two units"
else fail "C6: rc $RC, warned $n time(s)"; show; fi

# ── C7 ──
cy p build tests/y.tcyr build/y
if [ "$RC" != 0 ] && grep -q "f1_v" "$W/out" "$W/err"; then echo "  ok C7: cyrius build of a test source ignores test.cyml (f1_v undefined there)"
else fail "C7: rc $RC"; show; fi

# ── C8 ──
mkdir -p "$W/other"
printf '[test]\ndefines = ["OTHERDEF"]\n' > "$W/other/test.cyml"
lv "$W/other/t.tcyr" 1
cy p test ../other/t.tcyr
if [ "$RC" = 0 ]; then echo "  ok C8: a unit outside the project gets cyrius.cyml's [test] only (ROOTDEF, not ../other/test.cyml's OTHERDEF)"
else fail "C8: rc $RC"; show; fi

# ── C9 ──
proj s <<'EOF'
[deps]
stdlib = ["string", "fmt", "alloc", "syscalls", "vec"]
EOF
mkdir -p "$W/s/spec"
printf '[test]\nstdlib = ["assert"]\n' > "$W/s/spec/test.cyml"
printf 'fn main() {\n    alloc_init();\n    assert_eq(2, 2, "two");\n    return assert_summary();\n}\nsyscall(60, main());\n' > "$W/s/spec/a.tcyr"
cy s test spec/a.tcyr
if [ "$RC" = 1 ] && grep -qF "[test] stdlib names 'assert', which is not vendored into lib/" "$W/err" && [ ! -f "$W/s/lib/assert.cyr" ]; then
    echo "  ok C9a: a test.cyml outside tests/ benches/ fuzz/: an operand unit's leaf is named as not vendored"
else fail "C9a: rc $RC"; show; fi
printf '\n[test]\nfiles = ["spec"]\n' >> "$W/s/cyrius.cyml"
cy s test
if [ "$RC" = 0 ] && grep -q '^1 passed, 0 failed$' "$W/out" && [ -f "$W/s/lib/assert.cyr" ]; then
    echo "  ok C9b: with spec in [test] files the resolve reads spec/test.cyml and the unit passes"
else fail "C9b: rc $RC"; show; fi

# ── C10 ──
mkdir -p "$W/p/benches" "$W/p/fuzz"
printf '[test]\ndefines = ["LVL2"]\n' > "$W/p/benches/test.cyml"
printf '[test]\ndefines = ["LVL1"]\n' > "$W/p/fuzz/test.cyml"
lv "$W/p/benches/b.bcyr" 101
lv "$W/p/fuzz/f.fcyr" 11
cy p bench benches/b.bcyr; rb=$RC
cy p fuzz fuzz/f.fcyr
if [ "$rb" = 0 ] && [ "$RC" = 0 ]; then echo "  ok C10: bench and fuzz units honour their directory's test.cyml"
else fail "C10: bench rc $rb, fuzz rc $RC"; show; fi

# ── C11 ──
if [ "$(id -u)" = 0 ]; then echo "  skip C11: running as root (an unreadable directory is readable)"
else
    mkdir -p "$W/q/tests/locked"; chmod 000 "$W/q/tests/locked"
    cy q deps
    chmod 755 "$W/q/tests/locked"
    if [ "$RC" = 0 ] && grep -qF "warn: cannot list directory: tests/locked — a test.cyml in it is not read by the resolve" "$W/err"; then
        echo "  ok C11: a directory under tests/ that cannot be listed is warned by name; the resolve itself proceeds"
    else fail "C11: rc $RC"; show; fi
fi

[ "$FAIL" = 0 ] || { echo "FAIL: $G ($FAIL row(s))"; exit 1; }
echo "PASS: $G"

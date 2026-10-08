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
#
# MUTATION LEDGER (6.7.6) — each mutant built in a SCRATCH copy of the tree (cbt/ + lib/ + src/ +
# build/cycc + VERSION + this gate), the gate run against it; the unmutated copy PASSES, and each
# mutant turns the rows named RED:
#   M1  manifest.cyr: _cfg_test_files never reads [test] files                         F1 F3 F4 F5 F6
#   M2  manifest.cyr: _cfg_test_files never reads [build] test                         A F2 F3 F6b
#   M3  manifest.cyr: the both-declared warning removed                                F3
#   M4  deps.cyr: _dep_warn_manifest no longer warns [test]'s keys                     F7
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

[ "$FAIL" = 0 ] || { echo "FAIL: $G ($FAIL row(s))"; exit 1; }
echo "PASS: $G"

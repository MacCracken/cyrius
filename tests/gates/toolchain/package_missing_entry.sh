#!/bin/sh
# package_missing_entry.sh — 6.7.12 (the tools lane). `cyrius package` refuses a missing entry by
# name and builds only a real one.
#
# WHY: cmd_package (cbt/deps.cyr) compiled the entry only `if (file_exists(entry) == 1)`, with no
# else, and created build/ first: a `[build] entry` naming a file that does not exist printed
# `package ready: build/<out>`, exited 0, wrote nothing and left an empty build/ behind (and with
# no manifest and no src/main.cyr, `package ready: build/main`). `cyrius build` in the same
# directory said `error: no such file: <entry>`, rc 1. v6.5.19 closed the same green placeholder for
# a FAILED compile, not for a missing entry.
#
# ROWS (a throwaway HOME / CYRIUS_HOME; the CLI built from cbt/cyrius.cyr by build/cycc)
#   1  [build] entry = "src/nope.cyr": rc 1, `error: no such file: src/nope.cyr`, no `package
#      ready`, no build/ created
#   2  no manifest and no src/main.cyr: rc 1, `error: no such file: src/main.cyr`, no `package
#      ready`, no build/ created
#   3  a real entry: rc 0, `package ready: build/pk`, build/pk byte-identical to `cyrius build`'s
#      output for the same manifest, and it runs
#   4  `cyrius build` on row 1's manifest says the same words (`error: no such file: src/nope.cyr`)
#
# MUTATION LEDGER (6.7.12) — each a scratch copy of the tree (git archive HEAD + the mutant) through
# this gate:
#   M1  cmd_package's missing-entry refusal deleted, the compile still guarded by file_exists
#       (the 6.7.11 fall-through)                                                     RED 1, 2
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: package_missing_entry: no compiler at $CC"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: package_missing_entry: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
mkdir -p "$W/bin" "$W/h" "$W/ch"
"$CC" < cbt/cyrius.cyr > "$W/bin/cyrius" 2> "$W/build.err" || { echo "FAIL: package_missing_entry: cbt/cyrius.cyr does not build"; tail -3 "$W/build.err"; exit 1; }
[ "$(wc -c < "$W/bin/cyrius")" -ge 20000 ] || { echo "FAIL: package_missing_entry: cbt/cyrius.cyr built a $(wc -c < "$W/bin/cyrius")-byte binary"; exit 1; }
chmod +x "$W/bin/cyrius"
cp "$CC" "$W/bin/cycc"   # the CLI takes the cycc beside it (v6.5.42)

# cy <dir> <args...> — stdout to $W/out, stderr to $W/err, exit in RC
cy() { d=$1; shift; RC=0; ( cd "$W/$d" && HOME="$W/h" CYRIUS_HOME="$W/ch" "$W/bin/cyrius" "$@" ) > "$W/out" 2> "$W/err" < /dev/null || RC=$?; }
show() { cat "$W/out" "$W/err" | sed 's/^/      /' | head -8; }
manifest() { printf '[package]\nname = "pk"\nversion = "0.1.0"\n\n[build]\nentry = "%s"\noutput = "build/pk"\n' "$2" > "$W/$1/cyrius.cyml"; }

# ── 1 ──
mkdir -p "$W/p"; manifest p src/nope.cyr
cy p package
if [ "$RC" = 1 ] && grep -qxF 'error: no such file: src/nope.cyr' "$W/err" && ! grep -q 'package ready' "$W/out" && [ ! -e "$W/p/build" ]; then
    echo "  ok 1: a missing [build] entry — rc 1, 'error: no such file: src/nope.cyr', no 'package ready', no build/"
else fail "1: rc $RC (want 1), build/ $( [ -e "$W/p/build" ] && echo created || echo absent)"; show; fi

# ── 2 ──
mkdir -p "$W/q"
cy q package
if [ "$RC" = 1 ] && grep -qxF 'error: no such file: src/main.cyr' "$W/err" && ! grep -q 'package ready' "$W/out" && [ ! -e "$W/q/build" ]; then
    echo "  ok 2: no manifest, no src/main.cyr — rc 1, 'error: no such file: src/main.cyr', no build/"
else fail "2: rc $RC (want 1), build/ $( [ -e "$W/q/build" ] && echo created || echo absent)"; show; fi

# ── 3 ──
mkdir -p "$W/r/src"; manifest r src/main.cyr
printf 'fn main(): i64 { return 7; }\nvar r = main();\nsyscall(60, r);\n' > "$W/r/src/main.cyr"
cy r build
BRC=$RC
if [ "$BRC" = 0 ] && [ -f "$W/r/build/pk" ]; then cp "$W/r/build/pk" "$W/built.pk"; rm -rf "$W/r/build"; else fail "3 premise: cyrius build rc $BRC, no build/pk"; show; fi
cy r package
PRC=$RC
XRC=0; [ -x "$W/r/build/pk" ] && { "$W/r/build/pk" || XRC=$?; }
if [ "$PRC" = 0 ] && grep -qxF '  package ready: build/pk' "$W/out" && [ -f "$W/r/build/pk" ] && cmp -s "$W/r/build/pk" "$W/built.pk" && [ "$XRC" = 7 ]; then
    echo "  ok 3: a real entry — rc 0, 'package ready: build/pk', byte-identical to cyrius build's output, exits 7"
else fail "3: package rc $PRC, build/pk $( [ -f "$W/r/build/pk" ] && echo present || echo absent), cmp $(cmp -s "$W/r/build/pk" "$W/built.pk" && echo same || echo differs), run exit $XRC (want 7)"; show; fi

# ── 4 ──
cy p build
if [ "$RC" = 1 ] && grep -qxF 'error: no such file: src/nope.cyr' "$W/err"; then
    echo "  ok 4: cyrius build on the same manifest says the same words"
else fail "4: cyrius build rc $RC, not 'error: no such file: src/nope.cyr'"; show; fi

[ "$FAIL" = 0 ] || { echo "FAIL: package_missing_entry — $FAIL row(s) failed"; exit 1; }
echo "PASS: package_missing_entry (a missing entry refused by name with no build/; a real entry builds as cyrius build does)"

#!/bin/sh
# Gate: the ONE corpus walker's rules hold for every verb that walks a corpus (6.6.20,
# REFACTOR-09).
#
# `cyrius test` / `cyrius tests` (.tcyr), `cyrius fuzz` (.fcyr) and `cyrius bench` (.bcyr) each
# had their own copy of the directory walk, and every walker fix had to be made three times:
# v6.5.12's depth cap, `elif` and never-descend-a-symlink, then 6.6.10's unlistable-directory
# failure (that one is walkers_fail_closed_unreadable_dir.sh). 6.6.20 folded the three into
# `_corpus_walk_d` (cbt/commands.cyr). This gate pins the rules ONCE PER VERB, so a fourth corpus
# or a re-forked walker that drops one goes red here — nothing gated the v6.5.12 rules before.
#
# One fixture, the same shape under tests/ (for test/tests), fuzz/ and benches/:
#   <root>/sub/deeper/a.X     a nested file                       → runs
#   <root>/d.X/in.X           a DIRECTORY named like a corpus file → walked into, never run as a file
#   <root>/linked.X           a SYMLINKED file                    → runs
#   <root>/sub/loop -> ..     a symlink loop                      → never descended
#   <root>/.X                 a name that is ONLY the extension   → not a corpus file
#   <root>/deep/d/…/d/z.X     66 real directories deep            → past the depth cap (64): skipped,
#                                                                    with the capped directory named
# so each verb must report EXACTLY 3 passed, 0 failed, rc 0, and the depth-cap warning.
# Plus an ABSENT-root axis: no fuzz/ and no benches/ is an empty scope, not "cannot list".
#
# MUTATIONS (each against _corpus_walk_d): the is_symlink guard removed → the loop is walked to
# the cap and the counts inflate; `elif` made a second `if` → d.X is handed to the runner as a
# file; `nl > el` made `>=` → the dotfile runs (4 passed); the absent-root check removed → the
# absent axis reports "cannot list directory".
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=corpus_walk_rules
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}
[ -x "$CC" ] || { echo "FAIL: $NAME — $CC not built"; exit 1; }
command -v timeout > /dev/null 2>&1 || { echo "FAIL: $NAME — needs timeout(1)"; exit 1; }
ulimit -c 0 2>/dev/null || :
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT

# The CLI finds its compiler beside itself.
B="$T/bin"; mkdir -p "$B" "$T/hh" "$T/cyhome"
( cd "$ROOT" && "$CC" < cbt/cyrius.cyr > "$B/cyrius" 2> "$T/build.err" ) || {
    echo "FAIL: $NAME — could not build cbt/cyrius.cyr"; sed -n '1,5p' "$T/build.err"; exit 1; }
cp "$CC" "$B/cycc"
chmod +x "$B/cyrius" "$B/cycc"
# The stdlib the corpus files include resolves through CYRIUS_HOME; a throwaway copy of THIS tree's.
cp -R "$ROOT/lib" "$T/cyhome/lib"

cy() {   # $1 project dir, rest: the verb → $T/o, RC
    _d=$1; shift
    RC=0
    ( cd "$_d" && HOME="$T/hh" CYRIUS_HOME="$T/cyhome" CYRIUS_TEST_TIMEOUT=60 timeout 600 "$B/cyrius" "$@" ) > "$T/o" 2>&1 || RC=$?
}
has() { if grep -qF -- "$1" "$T/o"; then echo yes; else echo no; fi; }

OK='var r = 0;\nsyscall(60, r);\n'
P="$T/proj"
mkdir -p "$P"
printf '[package]\nname = "cw"\nversion = "0.1.0"\n' > "$P/cyrius.cyml"
for pair in tests:tcyr fuzz:fcyr benches:bcyr; do
    r=${pair%%:*}; x=${pair##*:}
    mkdir -p "$P/$r/sub/deeper" "$P/$r/d.$x"
    printf "$OK" > "$P/$r/sub/deeper/a.$x"
    printf "$OK" > "$P/$r/d.$x/in.$x"
    printf "$OK" > "$P/outside.$x"
    ln -s "../outside.$x" "$P/$r/linked.$x"
    ln -s .. "$P/$r/sub/loop"
    printf "$OK" > "$P/$r/.$x"
    deep="$P/$r/deep"; i=0
    while [ "$i" -lt 65 ]; do deep="$deep/d"; i=$((i + 1)); done
    mkdir -p "$deep"
    printf "$OK" > "$deep/z.$x"
done

echo "axis 1 — cyrius tests tests: 3 run (nested, inside d.tcyr/, the symlinked file); loop, dotfile, past-the-cap skipped:"
cy "$P" tests tests
check "rc 0" 0 "$RC"
check "exactly '3 passed, 0 failed'" "yes" "$(has '3 passed, 0 failed')"
check "the depth cap is hit and names the directory" "yes" "$(has 'test walk depth cap (64) hit — symlink loop? subtree skipped: tests/deep/d')"
check "no 'not a file' (d.tcyr/ was never handed to the runner)" "no" "$(has 'not a file')"

echo "axis 2 — bare cyrius test (the same walk, once per file):"
cy "$P" test
check "rc 0" 0 "$RC"
check "exactly '3 passed, 0 failed'" "yes" "$(has '3 passed, 0 failed')"

echo "axis 3 — cyrius fuzz (fuzz/ AND tests/ — tests/ holds no .fcyr):"
cy "$P" fuzz
check "rc 0" 0 "$RC"
check "exactly '=== 3 passed, 0 failed ==='" "yes" "$(has '=== 3 passed, 0 failed ===')"
check "the depth cap is hit and names the directory" "yes" "$(has 'fuzz walk depth cap (64) hit — symlink loop? subtree skipped: fuzz/deep/d')"
check "d.fcyr/ was never compiled as a file" "no" "$(has 'COMPILE FAIL')"

echo "axis 4 — cyrius bench (benches/ AND tests/):"
cy "$P" bench
check "rc 0" 0 "$RC"
check "exactly '=== 3 passed, 0 failed ==='" "yes" "$(has '=== 3 passed, 0 failed ===')"
check "the depth cap is hit and names the directory" "yes" "$(has 'bench walk depth cap (64) hit — symlink loop? subtree skipped: benches/deep/d')"
check "d.bcyr/ was never compiled as a file" "no" "$(has 'not a file')"

echo "axis 5 — an ABSENT fuzz/ and benches/ are empty scopes, not unlistable directories:"
Q="$T/absent"; mkdir -p "$Q/tests"
printf '[package]\nname = "ca"\nversion = "0.1.0"\n' > "$Q/cyrius.cyml"
printf "$OK" > "$Q/tests/only.fcyr"
printf "$OK" > "$Q/tests/only.bcyr"
cy "$Q" fuzz
check "fuzz rc 0, '=== 1 passed, 0 failed ==='" "0 yes" "$RC $(has '=== 1 passed, 0 failed ===')"
check "fuzz never says 'cannot list directory'" "no" "$(has 'cannot list directory')"
cy "$Q" bench
check "bench rc 0, '=== 1 passed, 0 failed ==='" "0 yes" "$RC $(has '=== 1 passed, 0 failed ===')"
check "bench never says 'cannot list directory'" "no" "$(has 'cannot list directory')"

if [ "$fails" = "0" ]; then
    echo "PASS: $NAME — test/tests, fuzz and bench walk one corpus the same way"
    exit 0
fi
echo "FAIL: $NAME — $fails assertion(s) failed"
exit 1

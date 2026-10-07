#!/bin/sh
# Gate: every scripts/ file a release-tarball builder names exists (6.6.20).
#
# scripts/build-macos-x86-tarball.sh carried
#     [ -f scripts/macos-x86-README.md ] && cp scripts/macos-x86-README.md "$WORK/$STAGE/README.md"
# and `git log --all -- scripts/macos-x86-README.md` is empty: the file never existed, so the
# guard skipped the copy on every release and nothing said so — the x86-macOS tarball shipped no
# README while its arm64 sibling copied one. A `[ -f X ] &&` guard around a packaging input turns
# a missing input into a silent omission. This gate reads each scripts/build-*-tarball.sh (code
# lines only — a comment may name a file that is gone) and requires every scripts/… path it names
# to exist in the tree.
#
# Mutation ledger (measured 6.6.20): the 6.6.19 build-macos-x86-tarball.sh → red, naming
# scripts/macos-x86-README.md; a builder naming scripts/nope.sh → red.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
fail() { echo "FAIL: tarball_inputs_exist: $1"; exit 1; }

nb=0
np=0
missing=""
for b in scripts/build-*-tarball.sh; do
    [ -f "$b" ] || continue
    nb=$((nb + 1))
    for p in $(sed 's/^[[:space:]]*#.*$//' "$b" | grep -oE 'scripts/[A-Za-z0-9._/-]+' | sort -u); do
        np=$((np + 1))
        [ -e "$p" ] || missing="$missing $b:$p"
    done
done
# Anti-vacuous: the three release builders exist and between them name the shared inputs.
[ "$nb" -ge 3 ] || fail "only $nb scripts/build-*-tarball.sh found (expected the macOS arm64, macOS x86 and Windows builders)"
[ "$np" -ge 6 ] || fail "only $np scripts/ references read from $nb builders — the extraction is broken"
[ -z "$missing" ] || fail "a tarball builder names a scripts/ file that does not exist:$missing"
echo "PASS: tarball_inputs_exist ($nb builders, $np scripts/ references, all present)"

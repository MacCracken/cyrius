#!/bin/sh
# tests/gates/toolchain/cyriusly_setup_bootstrap_and_env.sh — 6.7.12
#
# The compiled `cyriusly setup` (programs/cyriusly.cyr `_cmd_setup`, the Linux x86_64 tarball's
# cyriusly) refuses by name without build/cycc, builds no cross_bins, and installs the DEFAULT
# build of every tool whatever compile-mode switch the caller's shell holds.
#
# THE FILED DEFECT (docs/development/issues/2026-10-12-cyriusly-setup-bootstrap-cross-loop-and-env.md),
# measured on the 6.7.10 slot-open tree:
#   (a) build/cycc missing: setup ran `sh bootstrap/bootstrap.sh` — which assembles cybs and asm
#       from the seed and builds no cycc — and carried on: 15 compiles against the missing
#       compiler (`./build/cycc: No such file or directory`), `built 0 tool(s)`, 15 zero-byte
#       build/<tool> files left by the `>` redirects, then install.sh failed by another name, rc 1.
#   (b) its cross loop stripped the `cc5_` prefix retired at v6.0.0, so every [release] cross_bins
#       name mapped to a src/main_<name>.cyr that does not exist and it never built anything
#       (correcting the prefix would be WRONG: cycc_win needs CYRIUS_TARGET_WIN=1, and
#       cycc-native-aarch64 is built by cycc_aarch64). install.sh --refresh-only owns them.
#   (c) CYRIUS_BOUNDS=1 in the caller's shell: setup exited 0 and the installed bin/cyrfmt was the
#       bounds build (99,280 B), not the default (95,144 B) — the case 6.7.9 closed in the twin.
# The fix (the decided shape: REFUSE rather than derive — deriving would add a compiler-building
# path outside the gated seed-derive script): after bootstrap.sh, a still-missing build/cycc is
# refused by name before any build; the cross loop is gone; the tool loop and the install step
# run behind `unset CYRIUS_BOUNDS CYRIUS_POISON CYRIUS_COVERAGE CYRIUS_COVERAGE_FILE;`
# (the static half is bounds_mode_checked.sh row E4).
#
# HOW — a `git archive HEAD` copy of this checkout (build/cycc is tracked) and THIS tree's cyriusly;
# HOME and CYRIUS_HOME are throwaways under the gate's temp dir (checked before each run: the live
# store is never written).
#   A  build/cycc removed: rc 1; the refusal named (`bootstrap did not produce build/cycc`, naming
#      `git checkout build/cycc` and scripts/seed-derive-cycc.sh); no compile ran (no
#      `./build/cycc: No such file`, no `built N tool(s)`); no zero-byte file under build/ and no
#      tool built; no store slot written; build/cycc still absent.
#   B  STATIC: `_cmd_setup` carries no cross_bins loop (no `cc5_`, no `$CROSS`).
#   C  build/cycc present, CYRIUS_BOUNDS=1 inherited: rc 0, and the installed bin/cyrfmt is
#      byte-identical to the default build of programs/cyrfmt.cyr (anti-vacuous: the
#      CYRIUS_BOUNDS=1 build differs).
#
# MUTATION PROOF (each a scratch copy of the tree with programs/cyriusly.cyr mutated, run through
# THIS gate; GREEN 10/10 on the real tree):
#   MA  the post-bootstrap build/cycc check removed                  RED 4: A2-A5 (15 `No such file`,
#                                                                    `built 0 tool(s)`, 15 zero-byte
#                                                                    files, a versions/ dir; A1 stays
#                                                                    green: install.sh's own rc 1)
#   MB  the 6.7.11 cross loop restored                               RED 1: B1
#   MC  the `unset` dropped from the tool loop's shell line          RED 1: C2 (the bounds cyrfmt)
set -u
G=cyriusly_setup_bootstrap_and_env
# The reference builds below are the DEFAULT build: the caller's own switches stay out of them.
unset CYRIUS_BOUNDS CYRIUS_POISON CYRIUS_COVERAGE CYRIUS_COVERAGE_FILE
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G — no compiler at $CC"; exit 1; }
command -v git > /dev/null 2>&1 || { echo "FAIL: $G — needs git (the checkout copy is a git archive)"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
checks=0
check() {
    checks=$((checks + 1))
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}

# THIS tree's cyriusly (never build/cyriusly, the store or PATH).
if ! "$CC" < programs/cyriusly.cyr > "$T/cyriusly" 2> "$T/cy.err" || [ ! -s "$T/cyriusly" ]; then
    echo "FAIL: $G — programs/cyriusly.cyr does not build: $(grep -m1 -i error "$T/cy.err")"; exit 1
fi
chmod +x "$T/cyriusly"
VER=$(tr -d '[:space:]' < VERSION)
# co <dir>: a clean checkout copy (the tracked build/cycc included).
co() {
    mkdir -p "$1" && git -C "$ROOT" archive HEAD | tar -x -C "$1" \
        || { echo "FAIL: $G — git archive of the checkout failed"; exit 1; }
}
# setup_in <checkout> <home> <cyrius_home> <log> [VAR=value ...] -> RC
setup_in() {
    _co=$1; _h=$2; _ch=$3; _log=$4; shift 4
    case "$_ch" in "$T"/*) ;; *) echo "FAIL: $G — CYRIUS_HOME $_ch is not a throwaway under $T"; exit 1 ;; esac
    case "$_h" in "$T"/*) ;; *) echo "FAIL: $G — HOME $_h is not a throwaway under $T"; exit 1 ;; esac
    mkdir -p "$_h"
    RC=0
    (cd "$_co" && env "$@" HOME="$_h" CYRIUS_HOME="$_ch" timeout 600 "$T/cyriusly" setup < /dev/null) > "$_log" 2>&1 || RC=$?
}

echo "== A: build/cycc missing — refused by name, nothing built =="
co "$T/a"
rm -f "$T/a/build/cycc"
setup_in "$T/a" "$T/ha" "$T/cha" "$T/a.log"
check "A1 setup exits 1" 1 "$RC"
check "A2 the refusal is named, with both remedies" "1 1 1" \
    "$(grep -c 'error: bootstrap did not produce build/cycc' "$T/a.log") $(grep -c 'git checkout build/cycc' "$T/a.log") $(grep -c 'scripts/seed-derive-cycc.sh' "$T/a.log")"
check "A3 no compile ran (no 'build/cycc: No such file', no 'built N tool(s)')" "0 0" \
    "$(grep -c 'build/cycc: No such file' "$T/a.log") $(grep -c 'built [0-9]* tool' "$T/a.log")"
check "A4 no zero-byte file under build/, no tool built (build/cyrfmt)" "0 absent" \
    "$(find "$T/a/build" -type f -size 0 | wc -l | tr -d ' ') $([ -e "$T/a/build/cyrfmt" ] && echo present || echo absent)"
check "A5 no store slot written" absent "$([ -e "$T/cha/versions" ] && echo present || echo absent)"
check "A6 build/cycc still absent (setup derives no compiler)" absent "$([ -e "$T/a/build/cycc" ] && echo present || echo absent)"

echo "== B: no cross_bins loop (install.sh --refresh-only owns them) =="
S0=$(grep -n '^fn _cmd_setup(' programs/cyriusly.cyr | head -1 | cut -d: -f1)
[ -n "$S0" ] || { echo "FAIL: $G — programs/cyriusly.cyr has no fn _cmd_setup"; exit 1; }
E0=$(awk -v s="$S0" 'NR > s && /^fn / { print NR - 1; exit }' programs/cyriusly.cyr)
check "B1 _cmd_setup names no cc5_ and no \$CROSS loop" 0 \
    "$(awk -v s="$S0" -v e="${E0:-999999}" 'NR >= s && NR <= e && !/^[[:space:]]*#/ && /cc5_|\$CROSS/' programs/cyriusly.cyr | wc -l | tr -d ' ')"

echo "== C: CYRIUS_BOUNDS=1 inherited — the default build is installed =="
"$CC" < programs/cyrfmt.cyr > "$T/cyrfmt.plain" 2> /dev/null
CYRIUS_BOUNDS=1 "$CC" < programs/cyrfmt.cyr > "$T/cyrfmt.bounds" 2> /dev/null
check "C0 anti-vacuous: the CYRIUS_BOUNDS=1 build of cyrfmt differs from the default" differs \
    "$(cmp -s "$T/cyrfmt.plain" "$T/cyrfmt.bounds" && echo same || echo differs)"
co "$T/c"
setup_in "$T/c" "$T/hc" "$T/chc" "$T/c.log" CYRIUS_BOUNDS=1
check "C1 setup exits 0" 0 "$RC"
check "C2 the installed bin/cyrfmt is the default build, byte for byte" identical \
    "$(cmp -s "$T/chc/versions/$VER/bin/cyrfmt" "$T/cyrfmt.plain" && echo identical || echo differs)"

echo ""
if [ "$fails" -gt 0 ]; then
    for f in a.log c.log; do [ -s "$T/$f" ] && { echo "  ($f, last lines)"; tail -6 "$T/$f" | sed 's/^/    /'; }; done
    echo "FAIL: $G — $fails of $checks checks failed"
    exit 1
fi
echo "PASS: $G — $checks checks"
exit 0

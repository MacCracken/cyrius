#!/bin/sh
# scripts/build-cycc-verify.sh — byte-identical self-host fixpoint check.
#
# This formalizes the canonical cycc-fixpoint verifier that's lived as
# ad-hoc one-liners in chat / commit messages. Pinned at v5.11.7
# close (2026-05-11), shipped v5.11.67 as part of the v6.0-runway
# triple-pull bundle. (`cycc` is the compiler's name for good — CLAUDE.md § Key Principles.)
#
# The three byte-identity invariants:
#
#   1. cycc compiles its own source clean
#        `cat src/main.cyr | build/cycc > stage_a && chmod +x stage_a`
#
#   2. stage_a compiles the same source byte-identical to itself
#      (fixpoint)
#        `cat src/main.cyr | stage_a > stage_b && cmp stage_a stage_b`
#
#   3. stage_a matches the committed build/cycc (no silent drift)
#        `cmp stage_a build/cycc`
#
# Any compiler-source edit MUST keep invariants 1 + 2 green. Invariant
# 3 fails after legitimate compiler changes (the build/cycc binary lags
# the source until rebuild); the post-build re-run is when it should
# pass. See ADR-005 "Two-Step Bootstrap" for the heap-change variant
# (cycc → cc5b == cc5c).
#
# Every stage must also produce a NON-EMPTY output: a compiler that exits 0 and writes nothing
# leaves a 0-byte stage, and a 0-byte stage cmp's equal to another 0-byte stage.
#
# Exit codes:
#   0 — all three invariants pass
#   1 — stage_a compile failed or wrote nothing (invariant 1); also a usage / setup error
#   2 — fixpoint diverged, or stage_b failed or wrote nothing (invariant 2; real correctness bug)
#   3 — stage_a != build/cycc (invariant 3; stale build artifact)
#
# --install <scratch-dir> — rebuild build/cycc from the source, once the source reaches a
# fixpoint (what invariant 3's "Refresh via" asks for, done safely):
#
#   c1 = build/cycc(src/main.cyr), c2 = c1(src/main.cyr), c3 = c2(src/main.cyr)
#
# each written to <scratch-dir>/c1..c3 (stderr beside it as c<N>.err, kept for inspection); every
# stage must exit 0 with a non-empty output, and c2 == c3 is required (c1 may differ from c2:
# build/cycc can lag the source by a codegen change — the two-step bootstrap of ADR-005). Only then
# is c2 copied to a temp file inside build/ and renamed over build/cycc with `mv -f` — atomic, and
# never a cp over a binary that may be running. Exit codes:
#   0 — build/cycc replaced by c2 (== c3)
#   1 — c1 failed or wrote nothing; also a usage / setup error
#   2 — c2 or c3 failed or wrote nothing, or c2 != c3
#   4 — the replace of build/cycc failed
# build/cycc is untouched on every non-zero exit.
#
# --fixpoint <scratch-dir> — the same three stages and checks as --install, and nothing installed:
# "does the edited source reach a fixpoint?", asked before deciding to install (verify cannot
# answer it after a codegen change: its stage_a == stage_b fails while build/cycc lags the source).
# Exit codes 0 (c2 == c3), 1 and 2 as --install's; build/cycc is never touched.
#
# Usage: sh scripts/build-cycc-verify.sh                        (verify; CI's trust-root job)
#        sh scripts/build-cycc-verify.sh --fixpoint <scratch-dir> (c2 == c3 check only)
#        sh scripts/build-cycc-verify.sh --install <scratch-dir>  (rebuild build/cycc at a fixpoint)

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Parsed before the cd, so a relative <scratch-dir> is the caller's.
MODE=verify
STAGES=""
case "$#:${1:-}" in
    0:) ;;
    2:--install|2:--fixpoint)
        [ -n "$2" ] || { echo "ERROR: $1 needs a scratch directory" >&2; exit 1; }
        MODE=${1#--}
        case "$2" in /*) STAGES=$2 ;; *) STAGES="$(pwd)/$2" ;; esac ;;
    *)
        echo "usage: sh scripts/build-cycc-verify.sh [--fixpoint <scratch-dir> | --install <scratch-dir>]" >&2
        exit 1 ;;
esac
cd "$ROOT"
# 6.7.9 — the fixpoint it checks is the DEFAULT build's: an inherited CYRIUS_BOUNDS /
# CYRIUS_POISON would verify a bounds-checked / poison-mode compiler (and fail invariant 3)
# (gate row E4, tests/gates/frontend/bounds_mode_checked.sh). CHANGELOG [6.7.9]
# 6.7.10 — CYRIUS_COVERAGE too: an inherited execution-coverage mode would instrument (or, with no
# CYRIUS_COVERAGE_FILE, refuse) every compile below. CHANGELOG [6.7.10]
unset CYRIUS_BOUNDS CYRIUS_POISON CYRIUS_COVERAGE

CC="$ROOT/build/cycc"
SRC="$ROOT/src/main.cyr"

if [ ! -x "$CC" ]; then
    echo "ERROR: $CC missing — run 'sh bootstrap/bootstrap.sh' first." >&2
    exit 1
fi
if [ ! -f "$SRC" ]; then
    echo "ERROR: $SRC missing — repo layout broken?" >&2
    exit 1
fi

# v6.6.6: CHECKED — an unchecked mktemp leaves the variable EMPTY on a full or unwritable
# temp dir, and every "$V/x" below then becomes "/x". CHANGELOG [6.6.6]
TMPDIR=$(mktemp -d) && [ -d "$TMPDIR" ] || { echo "error: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})" >&2; exit 1; }
trap "rm -rf $TMPDIR" EXIT

if [ "$MODE" != verify ]; then
    if [ "$MODE" = install ]; then
        echo "=== cycc self-host fixpoint + install (stages in $STAGES) ==="
    else
        echo "=== cycc self-host fixpoint (stages in $STAGES) ==="
    fi
    mkdir -p "$STAGES" || { echo "ERROR: cannot create $STAGES" >&2; exit 1; }
    prev="$CC"
    for n in 1 2 3; do
        echo "  [$n/3] cat src/main.cyr | $(basename "$prev") > c$n..."
        if ! cat "$SRC" | "$prev" > "$STAGES/c$n" 2> "$STAGES/c$n.err"; then
            echo "  FAIL: stage c$n compile failed (stderr: $STAGES/c$n.err)" >&2
            head -20 "$STAGES/c$n.err" >&2
            [ "$n" = 1 ] && exit 1
            exit 2
        fi
        if [ ! -s "$STAGES/c$n" ]; then
            echo "  FAIL: stage c$n is EMPTY — the compiler exited 0 and wrote nothing" >&2
            [ "$n" = 1 ] && exit 1
            exit 2
        fi
        chmod +x "$STAGES/c$n"
        echo "        c$n $(wc -c < "$STAGES/c$n") bytes"
        prev="$STAGES/c$n"
    done
    if ! cmp -s "$STAGES/c2" "$STAGES/c3"; then
        echo "  FAIL: fixpoint diverged — c2 != c3" >&2
        echo "        c2: $(sha256sum "$STAGES/c2" | cut -d' ' -f1)" >&2
        echo "        c3: $(sha256sum "$STAGES/c3" | cut -d' ' -f1)" >&2
        exit 2
    fi
    echo "        FIXPOINT OK (c2 == c3 at $(wc -c < "$STAGES/c2") B)"
    [ "$MODE" = fixpoint ] && exit 0
    if cmp -s "$STAGES/c2" "$CC"; then WAS="already byte-identical to c2"; else WAS="replaced"; fi
    # A temp in build/ itself, so the rename is on one filesystem (atomic).
    NEW=$(mktemp "$ROOT/build/.cycc-install.XXXXXX") && [ -f "$NEW" ] || { echo "  FAIL: mktemp in build/ failed, build/cycc untouched" >&2; exit 4; }
    # The EXIT trap now removes the build/ temp too, should the run stop before the rename (after
    # it, the name is gone and the rm is a no-op).
    trap 'rm -rf "$TMPDIR" "$NEW"' EXIT
    if cp "$STAGES/c2" "$NEW" && chmod 755 "$NEW" && mv -f "$NEW" "$CC"; then
        echo ""
        echo "=== INSTALLED build/cycc ($WAS) ==="
        exit 0
    fi
    rm -f "$NEW"
    echo "  FAIL: replacing build/cycc failed — build/cycc untouched" >&2
    exit 4
fi

STAGE_A="$TMPDIR/cc5_stage_a"
STAGE_B="$TMPDIR/cc5_stage_b"

echo "=== cycc self-host fixpoint verify ==="

# Invariant 1: build stage_a from current source
echo "  [1/3] cat src/main.cyr | build/cycc > stage_a..."
if ! cat "$SRC" | "$CC" > "$STAGE_A" 2>"$TMPDIR/stderr_a"; then
    echo "  FAIL: stage_a compile failed (invariant 1)" >&2
    head -20 "$TMPDIR/stderr_a" >&2
    exit 1
fi
if [ ! -s "$STAGE_A" ]; then
    echo "  FAIL: stage_a is EMPTY — build/cycc exited 0 and wrote nothing (invariant 1)" >&2
    exit 1
fi
chmod +x "$STAGE_A"
SIZE_A=$(wc -c < "$STAGE_A")
echo "        stage_a $SIZE_A bytes"

# Invariant 2: stage_a recompiles its own source byte-identical (fixpoint)
echo "  [2/3] cat src/main.cyr | stage_a > stage_b; cmp stage_a stage_b..."
if ! cat "$SRC" | "$STAGE_A" > "$STAGE_B" 2>"$TMPDIR/stderr_b"; then
    echo "  FAIL: stage_b compile failed under stage_a (invariant 2)" >&2
    head -20 "$TMPDIR/stderr_b" >&2
    exit 2
fi
if [ ! -s "$STAGE_B" ]; then
    echo "  FAIL: stage_b is EMPTY — stage_a exited 0 and wrote nothing (invariant 2)" >&2
    exit 2
fi
chmod +x "$STAGE_B"
if ! cmp -s "$STAGE_A" "$STAGE_B"; then
    echo "  FAIL: fixpoint diverged — stage_a != stage_b (invariant 2)" >&2
    echo "        stage_a: $(sha256sum "$STAGE_A" | cut -d' ' -f1)" >&2
    echo "        stage_b: $(sha256sum "$STAGE_B" | cut -d' ' -f1)" >&2
    echo "        See ADR-005 for the two-step bootstrap variant when" >&2
    echo "        the change involves heap-offset relocation." >&2
    exit 2
fi
echo "        FIXPOINT OK (stage_a == stage_b at $SIZE_A B)"

# Invariant 3: stage_a matches committed build/cycc
echo "  [3/3] cmp stage_a build/cycc..."
if cmp -s "$STAGE_A" "$CC"; then
    echo "        stage_a == build/cycc (no drift)"
    echo ""
    echo "=== VERIFY OK ==="
    exit 0
else
    SIZE_CC5=$(wc -c < "$CC")
    echo "  WARN: stage_a != build/cycc (invariant 3)" >&2
    echo "        stage_a:   $SIZE_A bytes — $(sha256sum "$STAGE_A" | cut -d' ' -f1)" >&2
    echo "        build/cycc: $SIZE_CC5 bytes — $(sha256sum "$CC" | cut -d' ' -f1)" >&2
    echo "        Likely cause: build/cycc lags source edits. Refresh via:" >&2
    echo "          sh scripts/build-cycc-verify.sh --install <scratch-dir>" >&2
    exit 3
fi

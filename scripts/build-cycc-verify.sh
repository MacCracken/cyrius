#!/bin/sh
# scripts/build-cycc-verify.sh — byte-identical self-host fixpoint check.
#
# This formalizes the canonical cycc-fixpoint verifier that's lived as
# ad-hoc one-liners in chat / commit messages. Pinned at v5.11.7
# close (2026-05-11), shipped v5.11.67 as part of the v6.0-runway
# triple-pull bundle. Renames to `scripts/build-cyc.sh` at the v6.0.0
# `cycc` → `cyc` rename per CLAUDE.md "Key Principles" #7.
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
# Exit codes:
#   0 — all three invariants pass
#   1 — stage_a compile failed (invariant 1)
#   2 — fixpoint diverged (invariant 2; real correctness bug)
#   3 — stage_a != build/cycc (invariant 3; stale build artifact)

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

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

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

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
    echo "          cp $STAGE_A $CC" >&2
    exit 3
fi

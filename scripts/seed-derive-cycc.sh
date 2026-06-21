#!/bin/sh
# scripts/seed-derive-cycc.sh — prove `build/cycc` is machine-derivable from
# the ~29 KB seed (CVE-20 resolution, 2026-06-20). No bridge rung.
#
# Chain:
#   bootstrap/asm (seed) assembles bootstrap/cybs.cyr  -> cybs
#   CLOSURE:  cybs compiles bootstrap/asm.cyr           == bootstrap/asm
#   cybs compiles src/main.cyr                          -> gen1 (a working cycc)
#   gen1 compiles src/main.cyr                          -> gen2
#   gen2 == build/cycc        (the committed cycc IS seed-derived)
#   gen2 compiles src/main.cyr -> gen3 ; gen2 == gen3   (self-host fixpoint)
#
# SCOPE — this is SINGLE-ROOT CLOSURE validation, NOT diverse double
# compilation. It takes the committed bootstrap/asm binary as the TRUSTED root
# and proves the whole downstream chain is consistent with it (asm assembles
# cybs; cybs reproduces asm; cybs compiles main.cyr to a cycc that self-hosts to
# build/cycc). It does NOT re-derive the asm binary from source — so a backdoor
# baked into the committed asm binary itself would pass here.
#
# The INDEPENDENT re-derivation of the asm root (the diverse leg that defeats a
# Thompson "trusting-trust" tamper IN the asm binary) is a SEPARATE step:
# bootstrap/verify.sh rebuilds bootstrap/asm from the archived Rust seed
# (archive/seed/) and checks byte-identity. Run that on a clean machine to trust
# the asm binary; THEN this script proves build/cycc descends from it. Full
# trusting-trust resistance = BOTH legs. This script (in the trust-root-attest
# CI job, alongside build-cycc-verify.sh's build/cycc self-host fixpoint) is the
# closure leg only — CI does not run verify.sh (no Rust on the build path).
#
# Exit: 0 = all pass; 1 = a build step failed or a comparison diverged.

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEED="bootstrap/asm"
[ -f "$SEED" ] || { echo "ERROR: $SEED missing" >&2; exit 1; }
[ -f build/cycc ] || { echo "ERROR: build/cycc missing" >&2; exit 1; }
chmod +x "$SEED" 2>/dev/null || true

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

echo "=== seed -> cybs -> cycc derivation (seed: $(wc -c < "$SEED") bytes) ==="

echo "  [1/5] seed assembles bootstrap/cybs.cyr -> cybs"
cat bootstrap/cybs.cyr | "$SEED" > "$TMP/cybs"
chmod +x "$TMP/cybs"

echo "  [2/5] closure: cybs(bootstrap/asm.cyr) == bootstrap/asm"
cat bootstrap/asm.cyr | "$TMP/cybs" > "$TMP/asm2"
if ! cmp -s "$TMP/asm2" "$SEED"; then
    echo "  FAIL: closure broken — cybs does not reproduce the seed" >&2
    exit 1
fi

echo "  [3/5] cybs compiles src/main.cyr -> gen1"
cat src/main.cyr | "$TMP/cybs" > "$TMP/gen1"
chmod +x "$TMP/gen1"

echo "  [4/5] gen1 compiles src/main.cyr -> gen2 ; gen2 == build/cycc"
cat src/main.cyr | "$TMP/gen1" > "$TMP/gen2"
chmod +x "$TMP/gen2"
if ! cmp -s "$TMP/gen2" build/cycc; then
    echo "  FAIL: seed-derived cycc != committed build/cycc" >&2
    echo "        gen2:       $(sha256sum "$TMP/gen2" | cut -d' ' -f1)" >&2
    echo "        build/cycc: $(sha256sum build/cycc | cut -d' ' -f1)" >&2
    exit 1
fi

echo "  [5/5] fixpoint: gen2 compiles src/main.cyr -> gen3 ; gen2 == gen3"
cat src/main.cyr | "$TMP/gen2" > "$TMP/gen3"
chmod +x "$TMP/gen3"
if ! cmp -s "$TMP/gen2" "$TMP/gen3"; then
    echo "  FAIL: self-host fixpoint diverged" >&2
    exit 1
fi

echo ""
echo "=== OK: build/cycc is machine-derivable from the $(wc -c < "$SEED")-byte seed ==="

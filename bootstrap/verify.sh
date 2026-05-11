#!/bin/sh
# Verify the committed asm binary by rebuilding from the Rust seed.
# Requires: rustc, cargo (one-time verification only).
#
# This script proves the committed bootstrap/asm binary was correctly
# produced from asm.cyr by cyrc compiled by the Rust seed.

set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$DIR")"

echo "=== Bootstrap Verification ==="
echo "This rebuilds the asm binary from scratch using the Rust seed."
echo ""

# Check Rust seed exists
if [ ! -f "$ROOT/archive/seed/Cargo.toml" ] && [ ! -f "$ROOT/seed/Cargo.toml" ]; then
    echo "ERROR: Rust seed not found. Need archive/seed/ or seed/ to verify."
    exit 1
fi

SEED_DIR="$ROOT/seed"
if [ -f "$ROOT/archive/seed/Cargo.toml" ]; then
    SEED_DIR="$ROOT/archive/seed"
fi

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Step 1: Build Rust seed
echo "Building Rust seed..."
cargo build --manifest-path "$SEED_DIR/Cargo.toml" --release 2>&1 | tail -3
SEED="$SEED_DIR/target/release/cyrius-seed"

# Step 2: Seed assembles cyrc
echo "Seed -> cyrc..."
"$SEED" "$DIR/cyrc.cyr" "$TMPDIR/cyrc"
chmod +x "$TMPDIR/cyrc"

# Step 3: cyrc compiles asm.cyr
echo "cyrc -> asm..."
cat "$DIR/asm.cyr" | "$TMPDIR/cyrc" > "$TMPDIR/asm"
chmod +x "$TMPDIR/asm"

# Step 4: Compare against committed binary
echo ""
echo "Comparing against bootstrap/asm..."
if cmp -s "$DIR/asm" "$TMPDIR/asm"; then
    echo "  PASS: Committed binary matches rebuild"
    echo "  SHA256: $(sha256sum "$DIR/asm" | cut -d' ' -f1)"
else
    echo "  FAIL: Committed binary does NOT match rebuild!"
    echo "  Committed: $(sha256sum "$DIR/asm" | cut -d' ' -f1)"
    echo "  Rebuilt:   $(sha256sum "$TMPDIR/asm" | cut -d' ' -f1)"
    exit 1
fi

# Step 5: Verify bootstrap closure
echo ""
echo "Verifying bootstrap closure..."
cat "$DIR/cyrc.cyr" | "$TMPDIR/asm" > "$TMPDIR/cyrc_v2"
if cmp -s "$TMPDIR/cyrc" "$TMPDIR/cyrc_v2"; then
    echo "  PASS: asm -> cyrc_v2 matches seed -> cyrc"
else
    echo "  FAIL: bootstrap closure broken!"
    exit 1
fi

echo ""
echo "=== VERIFICATION COMPLETE ==="
echo "The committed bootstrap/asm binary is reproducible and correct."

#!/bin/sh
# Bootstrap the Cyrius toolchain from the committed asm binary.
# Requires: Linux x86_64, sh, chmod. Nothing else.
#
# Produces: build/cybs (bootstrap compiler) and build/asm (assembler)
# After this, compile any .cyr program with:
#   cat program.cyr | ./build/cybs > program && chmod +x program

set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$DIR")"

# Validate inputs
if [ ! -f "$DIR/asm" ]; then
    echo "ERROR: bootstrap/asm not found" >&2
    exit 1
fi
if [ ! -f "$DIR/cybs.cyr" ]; then
    echo "ERROR: bootstrap/cybs.cyr not found" >&2
    exit 1
fi

mkdir -p "$ROOT/build"
chmod +x "$DIR/asm"

echo "=== Cyrius Bootstrap ==="
echo "Seed: $DIR/asm ($(wc -c < "$DIR/asm") bytes)"

# Step 1: Assemble the bootstrap compiler from source
echo "Assembling cybs..."
cat "$DIR/cybs.cyr" | "$DIR/asm" > "$ROOT/build/cybs"
chmod +x "$ROOT/build/cybs"
SZ=$(wc -c < "$ROOT/build/cybs")
echo "  -> build/cybs ($SZ bytes)"
if [ "$SZ" -lt 10000 ]; then echo "ERROR: cybs output truncated" >&2; exit 1; fi

# Step 2: Compile the assembler from source (self-hosting verification)
echo "Compiling asm..."
cat "$DIR/asm.cyr" | "$ROOT/build/cybs" > "$ROOT/build/asm"
chmod +x "$ROOT/build/asm"
SZ=$(wc -c < "$ROOT/build/asm")
echo "  -> build/asm ($SZ bytes)"
if [ "$SZ" -lt 20000 ]; then echo "ERROR: asm output truncated" >&2; exit 1; fi

# Step 3: Verify bootstrap closure
echo "Verifying bootstrap closure..."
cat "$DIR/cybs.cyr" | "$ROOT/build/asm" > "$ROOT/build/cybs_check"
if cmp -s "$ROOT/build/cybs" "$ROOT/build/cybs_check"; then
    echo "  PASS: cybs assembled by build/asm matches cybs assembled by seed"
else
    echo "  FAIL: bootstrap mismatch!"
    exit 1
fi

echo ""
echo "Bootstrap complete. Toolchain ready:"
echo "  Compiler: $ROOT/build/cybs"
echo "  Assembler: $ROOT/build/asm"
echo ""
echo "Usage:"
echo "  cat program.cyr | ./build/cybs > program && chmod +x program"
echo "  cat assembly.cyr | ./build/asm > binary && chmod +x binary"

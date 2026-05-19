#!/bin/sh
# mac-selfhost.sh — validate cycc_macho byte-identical self-host on Apple Silicon.
# Run this ON the Mac (archaemenid.local) after you've scp'd cycc_macho over
# and ad-hoc-signed it. The source file can already live alongside (checked
# out) or be scp'd in too — script handles both.
#
# Usage (from the Mac):
#   ./mac-selfhost.sh [path-to-cycc_macho] [path-to-main_aarch64_macho.cyr]
# Defaults: ./cycc_macho and ./main_aarch64_macho.cyr (or src/...)
set -e

CC5=${1:-./cycc_macho}
SRC=${2:-}

# Locate the source file if not explicit
if [ -z "$SRC" ]; then
    if [ -f "./main_aarch64_macho.cyr" ]; then
        SRC=./main_aarch64_macho.cyr
    elif [ -f "./src/main_aarch64_macho.cyr" ]; then
        SRC=./src/main_aarch64_macho.cyr
    else
        echo "error: main_aarch64_macho.cyr not found. Pass as arg 2, or place"
        echo "  in cwd / src/. Pull with:"
        echo "    scp macro@<linux-host>:Repos/cyrius/src/main_aarch64_macho.cyr ."
        exit 1
    fi
fi

if [ ! -x "$CC5" ]; then
    echo "error: $CC5 not executable. Run: chmod +x $CC5 && codesign -s - --force $CC5"
    exit 1
fi

echo "cycc:    $CC5 ($(wc -c < "$CC5") bytes)"
echo "source: $SRC ($(wc -c < "$SRC") bytes)"
echo ""

# Strip macOS 26 quarantine xattrs BEFORE signing. The Codex CLI team
# documented this (github.com/openai/codex issues/17447): on macOS 26.4.1,
# binaries carrying `com.apple.provenance` get silently blocked by
# AppleSystemPolicy and hang at `_dyld_start` — no output, no crash, no
# stderr. `xattr -c` clears all xattrs; re-signing is mandatory after.
echo "  stripping macOS 26 quarantine xattrs..."
xattr -c "$CC5" 2>/dev/null
echo "  re-signing ad-hoc..."
codesign --force --sign - "$CC5"

# Round 1: use the cycc_macho to compile itself → cc5_macho_b.
# Guarded by a 30s watchdog: a correct compile on M-series takes <2s, so if
# we're past 30s the compiler is looping and we bail with enough context.
echo "=== Round 1: compile self ==="
echo "  cycc:  $CC5 ($(wc -c < "$CC5") bytes)"
echo "  src:  $SRC ($(wc -c < "$SRC") bytes)"
echo "  starting compile..."

"$CC5" < "$SRC" > cc5_macho_b 2> cc5_macho_b.err &
pid=$!
elapsed=0
while kill -0 $pid 2>/dev/null; do
    sleep 1
    elapsed=$((elapsed + 1))
    if [ $elapsed -ge 30 ]; then
        echo "  TIMEOUT after ${elapsed}s — compiler is stuck. Killing pid $pid."
        kill -9 $pid 2>/dev/null
        wait $pid 2>/dev/null
        echo "  partial stdout (first 256 bytes):"
        head -c 256 cc5_macho_b | xxd | head -4
        echo "  stderr:"
        head -20 cc5_macho_b.err
        echo
        echo "FAIL: self-host compile hung. Likely causes:"
        echo "  - cycc_macho built with wrong backend (re-check it's cycc_aarch64 output)"
        echo "  - infinite loop in a host-specific code path"
        echo "  - stdin redirect not wired; try: cat \"$SRC\" | \"$CC5\" > cc5_macho_b"
        exit 1
    fi
done
wait $pid
rc=$?
echo "  finished in ${elapsed}s, cc5_macho_b: $(wc -c < cc5_macho_b 2>/dev/null) bytes, exit=$rc"
if [ $rc -ne 0 ]; then
    echo "  stderr:"
    head -20 cc5_macho_b.err
    exit 1
fi
# Save an UNSIGNED copy for round-2 comparison. Ad-hoc codesigning is
# non-deterministic (uuid + internal timestamps) so any cmp between two
# signed binaries will fail even when the compiler outputs are identical.
# We run a second round and compare the pre-sign outputs.
cp cc5_macho_b cc5_macho_b_unsigned
chmod +x cc5_macho_b
codesign -s - --force cc5_macho_b 2>&1 | grep -v "^cc5_macho_b: replacing" || true

# Round 2: second-generation self-host — cc5_macho_b compiles self → cc5_macho_c.
# Both cc5_macho_b and cc5_macho_c are the compiler's raw output (unsigned);
# byte-identity here proves the fixed point without codesign noise.
echo ""
echo "=== Round 2: second-gen self-host ==="
./cc5_macho_b < "$SRC" > cc5_macho_c
echo "  cc5_macho_c: $(wc -c < cc5_macho_c) bytes (unsigned)"

if cmp cc5_macho_b_unsigned cc5_macho_c; then
    echo ""
    echo "PASS: round-1 and round-2 compiler outputs are byte-identical"
    echo "      (fixed-point self-host on Apple Silicon)"
else
    echo "FAIL: round-2 drift — $(cmp cc5_macho_b_unsigned cc5_macho_c 2>&1 | head -1)"
    echo "  sizes: $(wc -c < cc5_macho_b_unsigned) vs $(wc -c < cc5_macho_c)"
    exit 1
fi
rm -f cc5_macho_b_unsigned
chmod +x cc5_macho_c
codesign -s - --force cc5_macho_c 2>&1 | grep -v "^cc5_macho_c: replacing" || true

echo ""
echo "Apple Silicon self-host verified. You can pull these back to Linux with:"
echo "  scp macro@archaemenid.local:$(pwd)/cc5_macho_b /tmp/"

#!/bin/sh
# cyrius watch — recompile on source change
# Usage: cyrius watch [src] [out]
# Default: cyrius watch src/main.cyr build/app

set -e

SRC="${1:-src/main.cyr}"
OUT="${2:-build/app}"
CC="${CYRIUS_CC:-$(which cycc 2>/dev/null || echo "$HOME/.cyrius/bin/cycc")}"
INTERVAL="${CYRIUS_WATCH_INTERVAL:-1}"

if [ ! -f "$SRC" ]; then echo "error: $SRC not found"; exit 1; fi
if [ ! -x "$CC" ]; then echo "error: cycc not found"; exit 1; fi

mkdir -p "$(dirname "$OUT")"
STAMP="/tmp/cyrius_watch_stamp_$$"
touch "$STAMP"

echo "cyrius watch: $SRC → $OUT (every ${INTERVAL}s)"
echo "  cycc: $CC"
echo "  ctrl-c to stop"
echo ""

# Initial build
cat "$SRC" | "$CC" > "$OUT" 2>/dev/null && chmod +x "$OUT" && echo "[$(date +%H:%M:%S)] built $(wc -c < "$OUT") bytes" || echo "[$(date +%H:%M:%S)] COMPILE ERROR"
touch "$STAMP"

while true; do
    sleep "$INTERVAL"
    # Check if any .cyr file is newer than last build
    changed=$(find . -name "*.cyr" -newer "$STAMP" -print -quit 2>/dev/null)
    if [ -n "$changed" ]; then
        cat "$SRC" | "$CC" > "$OUT" 2>/dev/null && chmod +x "$OUT" && echo "[$(date +%H:%M:%S)] rebuilt $(wc -c < "$OUT") bytes" || echo "[$(date +%H:%M:%S)] COMPILE ERROR"
        touch "$STAMP"
    fi
done

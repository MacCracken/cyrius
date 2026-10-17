#!/bin/sh
# cyrius-watch.sh — rebuild a project whenever one of its .cyr files changes
# Usage: cyrius-watch.sh [src] [out]
# Default: cyrius-watch.sh src/main.cyr build/app
#
# Each build is `cyrius build "$SRC" "$OUT"`: the same build the CLI runs — the manifest's deps and
# includes prepended, `include` resolved relative to the entry file, the macOS ad-hoc signature, the
# compiler's diagnostics shown, and the previous output kept when a build fails. It ran the bare
# compiler (`cat "$SRC" | cycc > "$OUT" 2>/dev/null`) until 6.7.14: Apple Silicon killed its
# unsigned output at launch, an entry-relative include failed on every OS, the diagnostic was
# discarded and a failed build left an empty "$OUT" (the user's decision D60, 2026-10-16).
# The CLI is CYRIUS_BIN, else `cyrius` on PATH, else $CYRIUS_HOME/bin/cyrius; the CLI picks the
# compiler (CYRIUS_CC no longer does). CHANGELOG [6.7.14]

set -e

SRC="${1:-src/main.cyr}"
OUT="${2:-build/app}"
CY="${CYRIUS_BIN:-$(command -v cyrius 2>/dev/null || echo "${CYRIUS_HOME:-$HOME/.cyrius}/bin/cyrius")}"
INTERVAL="${CYRIUS_WATCH_INTERVAL:-1}"

if [ ! -f "$SRC" ]; then echo "error: $SRC not found"; exit 1; fi
if [ ! -x "$CY" ]; then echo "error: the cyrius CLI not found (set CYRIUS_BIN, or put cyrius on PATH)"; exit 1; fi

mkdir -p "$(dirname "$OUT")"
# v6.6.6: a CHECKED private temp, not a hand-built "/tmp/<name>.$$" — a pid is predictable and
# reused, and the mtime this stamp carries decides whether the watcher rebuilds. CHANGELOG [6.6.6]
_watch_d=$(mktemp -d) && [ -d "$_watch_d" ] || { echo "error: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})" >&2; exit 1; }
trap 'rm -rf "$_watch_d"' EXIT INT TERM
STAMP="$_watch_d/stamp"
touch "$STAMP"

echo "cyrius watch: $SRC → $OUT (every ${INTERVAL}s)"
echo "  cyrius: $CY"
echo "  ctrl-c to stop"
echo ""

# Initial build
"$CY" build "$SRC" "$OUT" && echo "[$(date +%H:%M:%S)] built $(wc -c < "$OUT") bytes" || echo "[$(date +%H:%M:%S)] COMPILE ERROR"
touch "$STAMP"

while true; do
    sleep "$INTERVAL"
    # Check if any .cyr file is newer than last build
    changed=$(find . -name "*.cyr" -newer "$STAMP" -print -quit 2>/dev/null)
    if [ -n "$changed" ]; then
        "$CY" build "$SRC" "$OUT" && echo "[$(date +%H:%M:%S)] rebuilt $(wc -c < "$OUT") bytes" || echo "[$(date +%H:%M:%S)] COMPILE ERROR"
        touch "$STAMP"
    fi
done

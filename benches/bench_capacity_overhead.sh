#!/bin/sh
# bench_capacity_overhead.sh — measure CYRIUS_STATS=1 overhead.
#
# Compiles `src/main.cyr` (the largest realistic unit shipped with
# the toolchain) N times in two modes:
#   1. baseline       — no env var, default warnings only
#   2. with stats     — CYRIUS_STATS=1, six stat lines emitted
# Reports total wall time per mode + per-compile delta.
#
# Expected: delta ≈ 0 (six syscall writes + PRNUM formatting).
# A noticeable delta (> ~100 µs/compile) would mean we accidentally
# put expensive work behind the stats flag.
set -e

N="${1:-50}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CC="$ROOT/build/cycc"
SRC="$ROOT/src/main.cyr"

if [ ! -x "$CC" ]; then
    echo "error: $CC not found"; exit 1
fi
if [ ! -f "$SRC" ]; then
    echo "error: $SRC not found"; exit 1
fi

# Wrap the time output of $N compiles. POSIX `time` writes to stderr
# in a wide variety of formats; use a TMP file for portability.
measure() {
    label="$1"
    env_pair="$2"
    TMPTIME=$(mktemp)
    i=0
    start=$(date +%s%N)
    while [ "$i" -lt "$N" ]; do
        if [ -n "$env_pair" ]; then
            cat "$SRC" | env "$env_pair" "$CC" > /dev/null 2>/dev/null
        else
            cat "$SRC" | "$CC" > /dev/null 2>/dev/null
        fi
        i=$((i + 1))
    done
    end=$(date +%s%N)
    rm -f "$TMPTIME"
    elapsed_ns=$((end - start))
    elapsed_ms=$((elapsed_ns / 1000000))
    per_us=$((elapsed_ns / N / 1000))
    printf "  %-25s %4d compiles in %5d ms  (%4d µs / compile)\n" \
        "$label" "$N" "$elapsed_ms" "$per_us"
    echo "$elapsed_ns" > "/tmp/bench_cap_$$_${label}_ns"
}

echo "=== Capacity stats overhead (cc3 self-compile, N=$N) ==="

measure baseline ""
measure with_stats "CYRIUS_STATS=1"

baseline_ns=$(cat "/tmp/bench_cap_$$_baseline_ns")
stats_ns=$(cat "/tmp/bench_cap_$$_with_stats_ns")
rm -f "/tmp/bench_cap_$$_"*

delta_ns=$((stats_ns - baseline_ns))
# Bound at 0 — noise can flip sign on small samples.
if [ "$delta_ns" -lt 0 ]; then delta_ns=0; fi
per_us=$((delta_ns / N / 1000))

echo ""
printf "  delta:                    %4d µs / compile (stats vs baseline)\n" "$per_us"

# Sanity: delta should be small. Anything > 200 µs warrants investigation.
if [ "$per_us" -gt 200 ]; then
    echo "  WARN: stats overhead exceeds 200 µs / compile — investigate"
    exit 1
fi
echo "  ok: stats overhead is negligible"

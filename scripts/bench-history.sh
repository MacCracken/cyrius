#!/bin/sh
set -e

# Run Cyrius benchmark suite, append results to CSV, regenerate BENCHMARKS.md.
# Matches bhava/hisab pattern but uses Cyrius-native lib/bench.cyr framework.
#
# Usage:
#   ./scripts/bench-history.sh                    # all 3 tiers
#   ./scripts/bench-history.sh --tier1             # stdlib only (fast)
#   ./scripts/bench-history.sh --tier2             # + data structures
#   BENCH_ITERS=1000 ./scripts/bench-history.sh   # override iteration count
#
# Tiers:
#   1 — Core stdlib (string, alloc, vec)           ~5s
#   2 — Data structures (hashmap, fmt, tagged)     ~10s
#   3 — Compiler/toolchain (self-compile, tools)   ~30s

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CC="$REPO_ROOT/build/cycc"
HISTORY_FILE="$REPO_ROOT/bench-history.csv"
BENCHMARKS_MD="$REPO_ROOT/BENCHMARKS.md"
TMPDIR="/tmp/cyr_bench_$$"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
COMMIT=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
BRANCH=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo "unknown")

TIER="${1:-all}"

mkdir -p "$TMPDIR"

# Create CSV header if needed
if [ ! -f "$HISTORY_FILE" ]; then
    echo "timestamp,commit,branch,benchmark,estimate_ns" > "$HISTORY_FILE"
fi

echo "======================================"
echo "  Cyrius Benchmark Suite"
echo "======================================"
echo "  commit  : $COMMIT"
echo "  branch  : $BRANCH"
echo "  date    : $TIMESTAMP"
echo "  tier    : $TIER"
echo "======================================"
echo ""

# Compile and run a benchmark file, parse output, append to CSV
run_bench() {
    local src="$1"
    local name=$(basename "$src" .bcyr)

    # Compile
    if ! cat "$src" | "$CC" > "$TMPDIR/$name" 2>/dev/null; then
        echo "  SKIP: $name (compile failed)"
        return
    fi
    chmod +x "$TMPDIR/$name"

    # Run and capture output (tr converts null bytes to newlines)
    local output
    output=$("$TMPDIR/$name" 2>/dev/null | tr '\0' '\n') || true

    # Parse bench output lines:
    #   bench_name: 123ns avg (min=100ns max=200ns) [10000 iters]
    #   bench_name: 1us avg (min=900ns max=2us) [10000 iters]
    echo "$output" | while IFS= read -r line; do
        # Skip header lines
        case "$line" in "=== "*) continue ;; esac
        # Match lines with benchmark results
        case "$line" in
            *": "*" avg"*)
                # Extract benchmark name (before ": ")
                local bname=$(echo "$line" | sed 's/^  //' | sed 's/: .*//')
                # Extract avg value (between ": " and " avg")
                local avg_raw=$(echo "$line" | sed 's/.*: //' | sed 's/ avg.*//')

                # Convert to nanoseconds
                local ns=""
                case "$avg_raw" in
                    *ms) ns=$(echo "$avg_raw" | sed 's/ms//' | awk '{printf "%.0f", $1 * 1000000}') ;;
                    *us) ns=$(echo "$avg_raw" | sed 's/us//' | awk '{printf "%.0f", $1 * 1000}') ;;
                    *ns) ns=$(echo "$avg_raw" | sed 's/ns//' | awk '{printf "%.0f", $1}') ;;
                    *s)  ns=$(echo "$avg_raw" | sed 's/s//' | awk '{printf "%.0f", $1 * 1000000000}') ;;
                    *)   ns="$avg_raw" ;;
                esac

                if [ -n "$ns" ] && [ "$ns" != "" ]; then
                    echo "${TIMESTAMP},${COMMIT},${BRANCH},${bname},${ns}" >> "$HISTORY_FILE"
                    printf "  %-35s %s\n" "$bname" "$avg_raw"
                fi
                ;;
        esac
    done
}

# ── Tier 1: Core stdlib ──
echo "--- Tier 1: Core stdlib ---"
run_bench "$REPO_ROOT/benches/bench_string.bcyr"
run_bench "$REPO_ROOT/benches/bench_str.bcyr"
run_bench "$REPO_ROOT/benches/bench_alloc.bcyr"
run_bench "$REPO_ROOT/benches/bench_freelist.bcyr"
run_bench "$REPO_ROOT/benches/bench_interning.bcyr"
run_bench "$REPO_ROOT/benches/bench_vec.bcyr"

if [ "$TIER" = "--tier1" ]; then
    echo ""
    echo "Tier 1 complete."
    rm -rf "$TMPDIR"
    exit 0
fi

# ── Tier 2: Data structures & compute ──
echo ""
echo "--- Tier 2: Data structures & compute ---"
run_bench "$REPO_ROOT/benches/bench_hashmap.bcyr"
run_bench "$REPO_ROOT/benches/bench_fmt.bcyr"
run_bench "$REPO_ROOT/benches/bench_tagged.bcyr"
run_bench "$REPO_ROOT/benches/bench_float.bcyr"
run_bench "$REPO_ROOT/benches/bench_keccak.bcyr"
run_bench "$REPO_ROOT/benches/bench_mulmod.bcyr"

if [ "$TIER" = "--tier2" ]; then
    echo ""
    echo "Tier 2 complete."
    rm -rf "$TMPDIR"
    exit 0
fi

# ── Tier 3: Compiler/toolchain ──
echo ""
echo "--- Tier 3: Compiler/toolchain ---"

# Codegen-quality benches — measure the RUNTIME of compiled code patterns the
# v6.4.x regalloc/copy-prop arc targets. Run via run_bench (they emit "name: Xns avg").
run_bench "$REPO_ROOT/benches/bench_regalloc.bcyr"
run_bench "$REPO_ROOT/benches/bench_shortcircuit.bcyr"
run_bench "$REPO_ROOT/benches/bench_switch.bcyr"

# Compiler self-compile timing (direct, no fork overhead)
bench_cmd() {
    local name="$1"
    shift
    local total=0
    local runs=5
    local i=0
    while [ $i -lt $runs ]; do
        local start=$(date +%s%N 2>/dev/null || echo 0)
        eval "$@" > /dev/null 2>&1 || true
        local end=$(date +%s%N 2>/dev/null || echo 0)
        local elapsed=$((end - start))
        total=$((total + elapsed))
        i=$((i + 1))
    done
    local avg=$((total / runs))
    echo "${TIMESTAMP},${COMMIT},${BRANCH},${name},${avg}" >> "$HISTORY_FILE"

    # Format for display
    if [ $avg -ge 1000000000 ]; then
        local ms=$((avg / 1000000))
        printf "  %-35s %dms\n" "$name" "$ms"
    elif [ $avg -ge 1000000 ]; then
        local ms=$((avg / 1000000))
        printf "  %-35s %dms\n" "$name" "$ms"
    elif [ $avg -ge 1000 ]; then
        local us=$((avg / 1000))
        printf "  %-35s %dus\n" "$name" "$us"
    else
        printf "  %-35s %dns\n" "$name" "$avg"
    fi
}

bench_cmd "compiler/trivial" "echo 'var x = 42;' | $CC > /dev/null"
bench_cmd "compiler/self_compile" "cat $REPO_ROOT/src/main.cyr | $CC > /dev/null"

# v6.3.17 (PF-03): per-phase-resolved self-compile via the v5.10.0 CYRIUS_PROF profiler.
# Appends compiler/phase_<pp|lex|gvar|parse|fixup|emit|write> rows (ns) so the cycle
# carries a phase-resolved trend into the v6.5.x perf-refactor "first-step audit" (which
# needs history already accumulated at its entry). One extra self-compile; the profiler
# line goes to stderr as: `prof: compile NNN ms (pp=NN lex=NN gvar=NN parse=NN fixup=NN
# emit=NN write=NN ms)`. Phases are ms-granularity (profiler resolution); recorded as ns.
prof_tmp=$(mktemp)
cat "$REPO_ROOT/src/main.cyr" | CYRIUS_PROF=1 $CC > /dev/null 2>"$prof_tmp"
prof_line=$(grep '^prof:' "$prof_tmp" | head -1)
rm -f "$prof_tmp"
if [ -n "$prof_line" ]; then
    echo "$prof_line" | grep -oE '(pp|lex|gvar|parse|fixup|emit|write)=[0-9]+' | while IFS='=' read -r ph val; do
        ns=$((val * 1000000))
        echo "${TIMESTAMP},${COMMIT},${BRANCH},compiler/phase_${ph},${ns}" >> "$HISTORY_FILE"
        printf "  %-35s %dms\n" "compiler/phase_${ph}" "$val"
    done
fi

# Binary sizes (not timing, but track as metrics)
if [ -f "$REPO_ROOT/build/cycc" ]; then
    local_cc5_size=$(wc -c < "$REPO_ROOT/build/cycc")
    echo "${TIMESTAMP},${COMMIT},${BRANCH},size/cc5_bytes,${local_cc5_size}" >> "$HISTORY_FILE"
    printf "  %-35s %d bytes\n" "size/cycc" "$local_cc5_size"
fi

# Tool compile times. v6.2.15 (PF-01): the guard checked programs/${tool}.bcyr,
# which never exists (programs/ holds .cyr — the .cyr→.bcyr split landed at
# 4563d3fe), so this loop NEVER ran. Check the .cyr that actually gets compiled.
# cybs dropped: it's the bootstrap compiler, not a programs/ tool.
for tool in cyrfmt cyrlint cyrdoc ark; do
    if [ -f "$REPO_ROOT/programs/${tool}.cyr" ]; then
        bench_cmd "compiler/${tool}" "cat $REPO_ROOT/programs/${tool}.cyr | $CC > /dev/null"
    fi
done

echo ""

# ── Count entries ──
TOTAL=$(grep -c "^${TIMESTAMP}" "$HISTORY_FILE" 2>/dev/null || echo 0)
echo "Appended $TOTAL entries to bench-history.csv"

# ── Generate BENCHMARKS.md ──

# Find last 3 distinct commits
RUNS=$(awk -F, 'NR>1 {print $1","$2}' "$HISTORY_FILE" | sort -u | tail -3)
NUM_RUNS=$(echo "$RUNS" | wc -l)

# Extract arrays
RUN1_TS=""; RUN1_C=""
RUN2_TS=""; RUN2_C=""
RUN3_TS=""; RUN3_C=""
i=1
for run in $RUNS; do
    ts=$(echo "$run" | cut -d, -f1)
    cm=$(echo "$run" | cut -d, -f2)
    if [ $i -eq 1 ]; then RUN1_TS="$ts"; RUN1_C="$cm"; fi
    if [ $i -eq 2 ]; then RUN2_TS="$ts"; RUN2_C="$cm"; fi
    if [ $i -eq 3 ]; then RUN3_TS="$ts"; RUN3_C="$cm"; fi
    i=$((i + 1))
done

# Lookup function
lookup() {
    local commit="$1" bench="$2"
    awk -F, -v c="$commit" -v b="$bench" '$2 == c && $4 == b {print $5}' "$HISTORY_FILE" | tail -1
}

# Format ns
fmt_ns() {
    local ns="$1"
    if [ -z "$ns" ]; then echo "-"; return; fi
    if [ "$ns" -ge 1000000000 ] 2>/dev/null; then
        echo "$((ns / 1000000))ms"
    elif [ "$ns" -ge 1000000 ] 2>/dev/null; then
        echo "$((ns / 1000000))ms"
    elif [ "$ns" -ge 1000 ] 2>/dev/null; then
        echo "$((ns / 1000))us"
    else
        echo "${ns}ns"
    fi
}

{
    echo "# Benchmarks"
    echo ""
    echo "> Auto-generated by \`scripts/bench-history.sh\` -- do not edit manually."
    echo "> 3-tier benchmark suite: stdlib, data structures, compiler/toolchain."
    echo ""
    echo "## Run History"
    echo ""
    echo "| | Run 1 | Run 2 | Run 3 |"
    echo "|---|---|---|---|"
    echo "| **Date** | \`$RUN1_TS\` | \`$RUN2_TS\` | \`$RUN3_TS\` |"
    echo "| **Commit** | \`$RUN1_C\` | \`$RUN2_C\` | \`$RUN3_C\` |"
    echo ""

    # Get all unique benchmark names from the latest commit
    LATEST_C=""
    if [ -n "$RUN3_C" ]; then LATEST_C="$RUN3_C"
    elif [ -n "$RUN2_C" ]; then LATEST_C="$RUN2_C"
    else LATEST_C="$RUN1_C"; fi

    BENCHMARKS=$(awk -F, -v c="$LATEST_C" '$2 == c {print $4}' "$HISTORY_FILE" | sort -u)

    CURRENT_GROUP=""
    for bench in $BENCHMARKS; do
        GROUP=$(echo "$bench" | cut -d/ -f1)
        NAME=$(echo "$bench" | cut -d/ -f2-)

        if [ "$GROUP" != "$CURRENT_GROUP" ]; then
            if [ -n "$CURRENT_GROUP" ]; then echo ""; fi
            echo "## $GROUP"
            echo ""
            echo "| Benchmark | \`$RUN1_C\` | \`$RUN2_C\` | \`$RUN3_C\` | Delta |"
            echo "|---|---|---|---|---|"
            CURRENT_GROUP="$GROUP"
        fi

        V1=$(lookup "$RUN1_C" "$bench")
        V2=$(lookup "$RUN2_C" "$bench")
        V3=$(lookup "$RUN3_C" "$bench")

        D1=$(fmt_ns "$V1")
        D2=$(fmt_ns "$V2")
        D3=$(fmt_ns "$V3")

        # Compute delta first vs last
        DELTA="-"
        FIRST=""; LAST=""
        if [ -n "$V1" ]; then FIRST="$V1"; fi
        if [ -n "$V2" ]; then
            if [ -z "$FIRST" ]; then FIRST="$V2"; fi
            LAST="$V2"
        fi
        if [ -n "$V3" ]; then
            if [ -z "$FIRST" ]; then FIRST="$V3"; fi
            LAST="$V3"
        fi
        if [ -n "$FIRST" ] && [ -n "$LAST" ] && [ "$FIRST" != "$LAST" ] && [ "$FIRST" -gt 0 ] 2>/dev/null; then
            DELTA=$(awk "BEGIN {d=($LAST - $FIRST) / $FIRST * 100; printf \"%+.1f%%\", d}")
        fi

        echo "| $NAME | $D1 | $D2 | $D3 | $DELTA |"
    done

    echo ""
    echo "---"
    echo ""
    echo "Run benchmarks: \`./scripts/bench-history.sh\`"
    echo ""
    echo "Tiers: \`--tier1\` (stdlib), \`--tier2\` (+data), default (all 3)"
    echo ""
    echo "History: [\`bench-history.csv\`](bench-history.csv)"
} > "$BENCHMARKS_MD"

echo "Updated BENCHMARKS.md"

rm -rf "$TMPDIR"

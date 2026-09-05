#!/bin/sh
# fn_hash_load_bounded.sh — v6.5.51. The fn-name hash must never approach saturation, so
# lookup stays O(1) and compile time stays LINEAR in function count.
#
# WHAT THIS PINS. `_fnt_hash_mask` was `nc - 1` for an nc-entry fn table, i.e. exactly as
# many hash slots as table entries — and REGFN only grows once `fc >= _fnt_cap`. So the
# open-addressed name hash filled to EXACTLY 100 % before every doubling, and linear probing
# at that load degenerates into a full-table scan. MEASURED with an instrumented compiler on
# a 120,000-fn unit: max probe 65,263 (essentially the whole 65,536-slot table for ONE
# insertion) and 31,504,006 probes for the compile. After giving the hash two slots per entry:
# max probe 38, total 131,892 — a 239x reduction. Compile time went from 10.3 us/fn at 15k
# and 25.6 us/fn at 120k to a FLAT 5.3 us/fn across that whole range.
#
# ⛔ THE COST WAS MISATTRIBUTED TO `_fnt_grow` FOR A WHOLE RELEASE, and that is the reason
# this gate measures rather than reasons. The v6.5.50 investigation saw cost jump at the cap
# boundary and concluded one grow cost ~1145 ms. Direct instrumentation says every grow in a
# whole 120,000-fn compile costs 4-9 ms COMBINED (copy 2-4 ms, rehash 1-4 ms). The jump at the
# boundary is not the grow; it is the table having just been driven to 100 % load on the way
# there. A correlation with a doubling is not the doubling.
#
# ⭐ IT ASSERTS maxprobe, NOT ONLY LOAD. Load is the mechanism; displacement from the home
# slot is the PROPERTY that costs time. A gate pinning load alone would stay green under any
# future scheme that holds load down while still clustering — the v6.5.36 lesson, where an
# enum gate passed through five bad releases because it pinned the mechanism and the mechanism
# was what was broken. The meter is computed on demand by `_fnhash_health` under
# CYRIUS_STATS=1, so it costs nothing on the hot path.
#
# ⚠ DELIBERATELY NOT A TIMING GATE. An absolute ms bound measures the box, and even a ratio is
# load-sensitive: while five subagents were saturating this machine the same comparison read
# 1.44x where a quiet box read 1.19x. These numbers are counts and are identical on any box.
#
# ⚠ TWO SIZES, because the defect was SIZE-DEPENDENT: at equal ~52 % load, 34,000 fns cost
# 16.9 us/fn and 70,000 cost 29.7 — so a single-size check could sit at a load that looks fine
# while a larger table degenerates.
#
# ⚠ NO `set -e`: grep/arithmetic exit non-zero as DATA.
#
# MUTATION PROOF (2026-09-04): restoring `_fnt_hash_mask = nc - 1` with `alloc(nc * 4)` and
# `_fnt_cap = 4096` and rebuilding puts the 64,000-fn case at 97.7 % load and a five-figure
# maxprobe; both axes go RED. ⚠ MUTATE THE SOURCE, NOT build/cycc — a stale binary changes
# nothing here because the fixture runs the CURRENT build/cycc, so revert parse_fn.cyr and
# rebuild.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
CC="$ROOT/build/cycc"
FAIL=0

# The hash must stay under this load, and no entry may sit this far from its home slot.
MAX_LOAD_PCT=60
MAX_PROBE=200

probe_axis() {   # $1 = fn count
    n=$1
    python3 -c "
import sys
n = int(sys.argv[1])
open(sys.argv[2], 'w').write('object;\n' + '\n'.join(
    'fn f%d(): i64 { return %d; }' % (i, i % 97) for i in range(n)) +
    '\nfn main(): i64 { return 42; }\n')
" "$n" "$D/p.cyr"
    CYRIUS_STATS=1 "$CC" < "$D/p.cyr" > /dev/null 2>"$D/p.err"
    line=$(grep 'fn_name_hash:' "$D/p.err")
    if [ -z "$line" ]; then
        echo "FAIL: no fn_name_hash meter for $n fns — CYRIUS_STATS lost its hash-health line, so this gate cannot see the defect at all"
        FAIL=1; return
    fi
    used=$(echo "$line"  | sed 's/.*fn_name_hash: *\([0-9]*\) .*/\1/')
    slots=$(echo "$line" | sed 's/.*\/ *\([0-9]*\) slots.*/\1/')
    probe=$(echo "$line" | sed 's/.*maxprobe *\([0-9]*\).*/\1/')
    pct=$(( used * 100 / slots ))
    if [ "$pct" -gt "$MAX_LOAD_PCT" ]; then
        echo "FAIL: $n fns — hash at ${pct}% load ($used/$slots), limit ${MAX_LOAD_PCT}%; linear probing degenerates as it approaches saturation"
        FAIL=1
    elif [ "$probe" -gt "$MAX_PROBE" ]; then
        echo "FAIL: $n fns — maxprobe $probe exceeds $MAX_PROBE at ${pct}% load; the hash is clustering even though the load looks healthy"
        FAIL=1
    else
        echo "  ok: $n fns -> ${pct}% load ($used/$slots), maxprobe $probe"
    fi
}

probe_axis 8000
probe_axis 64000

if [ "$FAIL" != 0 ]; then
    echo "FAIL: the fn-name hash saturates — compile time is superlinear in function count"
    exit 1
fi
echo "PASS fn_hash_load_bounded (fn-name hash stays under ${MAX_LOAD_PCT}% load with maxprobe <= ${MAX_PROBE})"

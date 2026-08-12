#!/bin/sh
# tests/gates/toolchain/bench_timer_floor_measured.sh — v6.5.19 bench-timer gate.
#
# `lib/bench.cyr` opened with `clock_gettime: ~120ns per call` for two years. Measured
# on the hosts 2026-08-11: 1,332-1,720 ns on this box, 3,691 ns on pi, 540-571 ns on ach
# and 11-39 ns on ecb — an 11-14× error here and a 335× spread across the four POSIX gate
# hosts, with cass's read below its 15 ms tick entirely. agnosai filed it 2026-08-11.
# `tests/tcyr/crossos/bench_timer_floor.tcyr` gates the RUNTIME behaviour; this gate
# covers the two things a runtime test cannot:
#
#  A. ⭐ THE CONSTANT MUST NOT COME BACK. The defect was never a wrong calculation —
#     `120` appeared in no arithmetic anywhere in the tree, only in a comment. It was a
#     wrong FACT that readers acted on: it is what made per-iteration timing look
#     affordable, which put all 18 benches on a ~2-clock-read floor and left 57 of 79
#     recorded micro rows measuring the timer. A runtime test cannot see a comment, so
#     a grep is the only thing standing between us and someone "helpfully" writing the
#     number back in the next time they measure it on one host.
#  B. Every timing path must route through the measured floor. A new path added later
#     that forgets `_bench_net` reintroduces the bias silently on that path alone.
#
# Plus axis D, which BUILDS AND MEASURES rather than greps (it was a pair of substring
# checks until v6.5.19 and passed the exact defect this release fixed — see its own
# header), axis D2, which reproves D's sensitivity every run against a deliberately
# broken stdlib copy, and an anti-vacuous check that the grep patterns still match
# something (a rename would otherwise make axis A pass by finding nothing).
set -u
cd "$(dirname "$0")/../../.." || exit 2
ROOT=$(pwd)
TMP="${TMPDIR:-/tmp}/btfg.$$"
mkdir -p "$TMP" || exit 2
trap 'rm -rf "$TMP"' EXIT

F=lib/bench.cyr
fail() { echo "FAIL: $1"; exit 1; }
[ -f "$F" ] || fail "$F missing"

# ── A. no hardcoded per-call clock cost, anywhere in the file ───────
# Matches the shape `clock_gettime: ~120ns per call`, `clock read: 120 ns per call` —
# a stated per-call cost for the timer, in a comment or in code.
#
# A line marked `RETIRED:` is exempt, so the header can still QUOTE the figure it
# replaced — losing that history is how the same number gets re-derived on one host and
# written back. The exemption is capped at 3 lines below, so it cannot become a way to
# smuggle a live constant back in.
PAT='(clock_gettime|clock read|now_ns)[^\n]*[:~][^\n]*[0-9]+ *(ns|us) per call'
if grep -nE "$PAT" "$F" | grep -v 'RETIRED:' >/dev/null 2>&1; then
    grep -nE "$PAT" "$F" | grep -v 'RETIRED:'
    fail "$F states a per-call cost for the clock. It is 15ns on ecb and 3,550ns on pi — no single number is right, which is why bench_clock_overhead_ns() measures it"
fi
nret=$(grep -c 'RETIRED:' "$F")
[ "$nret" -le 3 ] || fail "$nret RETIRED: exemptions in $F (max 3) — the escape hatch is being used to keep live constants"
# The historical paragraph must still be there: it is the only thing that tells the
# next measurer why they must not write their own host's number down.
[ "$nret" -ge 1 ] || fail "the RETIRED: paragraph explaining the ~120ns figure is gone — axis A would pass vacuously and the lesson with it"

# ── B. the measured floor exists and every timing path uses it ──────
grep -q '^fn bench_clock_overhead_ns()' "$F" || fail "bench_clock_overhead_ns() is gone — the floor is no longer measured"
grep -q '^fn _bench_calibrate_clock()' "$F" || fail "_bench_calibrate_clock() is gone"
grep -q '^fn _bench_net(' "$F" || fail "_bench_net() is gone — nothing subtracts the floor"
grep -q 'elapsed - bench_clock_overhead_ns()' "$F" || fail "_bench_net no longer subtracts the measured floor"

# Anti-vacuous for the loop below: the path inventory must actually match.
nnet=$(grep -c '_bench_net(' "$F")
[ "$nnet" -ge 6 ] || fail "only $nnet _bench_net references (expected >= 6: its definition, bench_stop, bench_batch_stop, bench_run and the three bench_run_batch* variants) — a timing path has stopped netting the floor out"

# Per-function scan: every fn that closes a timing window must net it.
scan() {
    awk -v want="$2" 'index($0, "fn " want "(") == 1 {f=1} f {print} f && /^}/ {exit}' "$1"
}
for fnname in bench_stop bench_batch_stop bench_run bench_run_batch bench_run_batch1 bench_run_batch2; do
    body=$(scan "$F" "$fnname")
    [ -n "$body" ] || fail "could not locate fn $fnname in $F"
    echo "$body" | grep -q '_bench_net(' || fail "fn $fnname closes a timing window without subtracting the measured floor"
done

# `bench_run` must not be back to one clock pair per iteration.
scan "$F" bench_run | grep -q '_bench_chunk_for(' || fail "bench_run no longer sizes its own chunks — it is back to a clock pair per iteration, the shape that floored all 18 benches"

# ── C. provenance ships with the numbers ────────────────────────────
grep -q '^fn bench_report_clock()' "$F" || fail "bench_report_clock() is gone — reports would stop carrying the floor they were measured against"
scan "$F" bench_report | grep -q 'bench_report_clock()' || fail "bench_report no longer emits the measured floor; a wrong floor becomes invisible again"
# It must stay invisible to the history recorder, which selects on `*": "*" avg"*`.
scan "$F" bench_report_clock | grep -q ' avg' \
    && fail "bench_report_clock's line contains ' avg' — scripts/bench-history.sh would record it as a benchmark row"
[ -f docs/development/benchmark-regimes.md ] || fail "docs/development/benchmark-regimes.md missing — the pre-v6.5.19 recorded rows have no provenance"
grep -q 'benchmark-regimes.md' scripts/bench-history.sh || fail "scripts/bench-history.sh no longer points BENCHMARKS.md at the regime ledger"

# ── D. build and run: measure the BEHAVIOUR, not the text ────────────
# ⛔ THIS AXIS WAS VACUOUS FOR THE VERY DEFECT IT SHIPPED WITH. Until v6.5.19 it built a
# probe, greped that the report contained "timer floor" and "noop: ", and stopped —
# which a `_bench_chunk_for` forced to `return 1`, i.e. LITERALLY the pre-6.5.19
# one-clock-pair-per-iteration bug that floored all 18 benches, passes with rc=0.
# Measured, not supposed: the mutation was applied to a copy of the tree and this gate
# printed PASS. Axis B is no better on its own — it greps that `bench_run` still
# CONTAINS the string `_bench_chunk_for(`, and calling a function that returns 1 keeps
# the string.
#
# What cannot be faked is the COST OF MEASURING. Per-iteration timing performs 2n clock
# reads for n iterations; chunked timing performs a few dozen. The probe therefore times
# `bench_run` from the OUTSIDE and refuses a wall clock anywhere near `n × floor`, and
# separately refuses a reported average that still has a whole clock read in it. Exit
# codes are distinct so a failure says which property broke.
cat > "$TMP/p.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/fnptr.cyr"
include "lib/bench.cyr"
var _s = 0;
fn op(): i64 { _s = _s + 1; return 0; }
fn main(): i64 {
    var fl = bench_clock_overhead_ns();
    var n = 50000;
    var b = bench_new("noop");
    var t = now_ns();
    bench_run(b, &op, n);
    var wall = now_ns() - t;
    bench_report(b);
    # No measurable floor on this clock — the cost assertions below would be
    # meaningless rather than green. Distinct code so the gate can say so.
    if (fl <= 0) { return 3; }
    # 2n clock reads vs a few dozen: at n = 50,000 that is ~134 ms against ~0.2 ms here.
    # Half of n x floor is far above the chunked cost and far below the per-iteration
    # one, on any clock, because both sides scale with the same floor.
    if (wall >= n * fl / 2) { return 4; }
    # A sub-floor op must not report a whole clock read: that is the floor still being
    # inside the number, which is the other half of the same defect.
    if (bench_avg_ns(b) >= fl) { return 5; }
    # fp is still called exactly n times — chunking changes the windows, not the work.
    if (bench_iterations(b) != n) { return 6; }
    return 0;
}
var rc = main();
syscall(60, rc);
EOF
cp "$TMP/p.cyr" "$TMP/probe.cyr"
"$ROOT/build/cycc" < "$TMP/probe.cyr" > "$TMP/p" 2> "$TMP/p.err" || fail "probe build"
chmod +x "$TMP/p"
"$TMP/p" > "$TMP/out" 2> "$TMP/run.err"
prc=$?
case "$prc" in
  0) : ;;
  3) fail "the probe measured a floor of 0 — bench_clock_overhead_ns() is not calibrating on this host, so nothing below it can be trusted" ;;
  4) fail "bench_run spent close to one clock PAIR PER ITERATION measuring a no-op — it is back to the pre-v6.5.19 shape that put all 18 benches on a ~2-clock-read floor" ;;
  5) fail "bench_run reported a no-op as costing a whole clock read or more — the measured floor is not being subtracted" ;;
  6) fail "bench_run did not call the function exactly n times — chunking must change the windows, not the work" ;;
  *) cat "$TMP/out"; fail "probe run exited $prc" ;;
esac
grep -q 'timer floor' "$TMP/out" || { cat "$TMP/out"; fail "bench_report printed no timer-floor line"; }
grep -q 'noop: ' "$TMP/out" || { cat "$TMP/out"; fail "bench_report printed no result row"; }
# The floor line must not look like a benchmark row to the recorder.
if grep 'timer floor' "$TMP/out" | grep -q ' avg'; then
    fail "the timer-floor line would be recorded as a benchmark row by scripts/bench-history.sh"
fi

# ── D2. the axis proves its own sensitivity, every run ───────────────
# Same probe, against a COPY of the stdlib whose `_bench_chunk_for` returns 1 — the
# exact pre-v6.5.19 defect. It must FAIL. A behavioural axis that has quietly stopped
# being able to observe the behaviour is the thing this whole gate exists to prevent,
# and this one demonstrably was one.
mkdir -p "$TMP/mut/lib" || exit 2
cp lib/*.cyr "$TMP/mut/lib/" || exit 2
awk '
/^fn _bench_chunk_for\(per, fl\): i64 \{$/ { print; print "    return 1;"; skip = 1; next }
skip == 1 && /^\}$/ { print; skip = 0; next }
skip == 1 { next }
{ print }
' lib/bench.cyr > "$TMP/mut/lib/bench.cyr"
if cmp -s lib/bench.cyr "$TMP/mut/lib/bench.cyr"; then
    fail "the chunk-1 mutation is a no-op — _bench_chunk_for's signature changed, so axis D2 proves nothing and axis D could be vacuous again without anyone noticing"
fi
grep -q '^    return 1;$' "$TMP/mut/lib/bench.cyr" || fail "the chunk-1 mutant does not contain the forced return — the awk no longer matches lib/bench.cyr"
cp "$TMP/probe.cyr" "$TMP/mut/probe.cyr"
( cd "$TMP/mut" && "$ROOT/build/cycc" < probe.cyr > mut.bin 2> mut.err ) || fail "probe build against the chunk-1 stdlib"
chmod +x "$TMP/mut/mut.bin"
"$TMP/mut/mut.bin" > /dev/null 2>&1
mrc=$?
[ "$mrc" != "0" ] || fail "the probe PASSED against a bench_run pinned to one iteration per clock pair — axis D cannot see the defect this release fixed (VACUOUS, which is exactly what it was before v6.5.19)"

echo "PASS: bench timer floor is measured (no hardcoded per-call constant, 6 timing paths net it out, bench_run self-sizes and PROVES it by cost, report carries provenance and stays out of bench-history, chunk-1 mutant rejected with rc=$mrc)"
exit 0

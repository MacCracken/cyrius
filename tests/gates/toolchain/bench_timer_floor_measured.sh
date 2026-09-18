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
#
# v6.6.5 adds axis D3 (a SCRIPTED clock plus ten mutants, self-reproving every run), axis
# D4 (a consumer's row grammar copied verbatim from goonj) and the axis-B statements about
# `bench_sub_floor` and the bounded tick spin.
#
# ── MUTATION LEDGER for the assertions added at the 6.6.5 review ─────
# Every one proven RED against a mutated copy of the tree, 2026-09-18 (scratch root with
# a private lib/; see the bite-6 impl report):
#   bench_sub_floor renamed away        → "bench_sub_floor() is gone"
#   'SUB-FLOOR' dropped from the report → "no longer says SUB-FLOOR"
#   _bench_tick_cap renamed away        → "_bench_tick_cap() is gone"
#   the 100,000,000 spin guard restored → "no longer bounds its spin by the derived cap"
#   a mutant that does not COMPILE      → "does not COMPILE — it proves nothing" (it used
#                                          to increment the kill count and return silently)
#   D3 mutant (10) sub_floor_never_flagged → probe rc 30
#
# ── MUTATION LEDGER, 6.6.5 review round 2 (axis A's pattern controls, axis B's derived
#    inventory, axis E) — all proven RED 2026-09-18 against a scratch tree with a private
#    lib/ and a private copy of this gate:
#   M1 PAT broken to match nothing        → "the axis-A pattern no longer matches"
#   M2 PAT widened to match prose too     → "the axis-A pattern now matches ordinary prose"
#   M3 a new window-closing fn (bench_stop_v2) that never books
#                                         → "fn bench_stop_v2 closes a timing window without booking"
#   M4 bench_report renamed away          → "axis B's non-window exclusion 'bench_report' is not a fn"
#   M5 chrono's WIN arm back on sys_qpc_ns → "lib/chrono.cyr is no longer self-sufficient for PE"
#   M6 bench's  WIN arm back on sys_qpc_ns → "lib/bench.cyr is no longer self-sufficient for PE"
#   M7 chrono's WIN arm reverted to GetTickCount64
#                                         → "has no CYRIUS_TARGET_WIN arm that returns a local call"
#      ⚠ M7 is why axis E does not rely on the PE import table alone: the reverted build
#        STILL carried both QueryPerformance imports, because the now-unreachable helper
#        stays in the binary. The source-derived check is what kills it.
#   M8 the raw helper drops the QPF read  → "does not spell QueryPerformanceFrequency"
#   M9 the raw helper renamed out of the module → "no longer self-sufficient for PE"
# The gate also runs clean under `bash -eo pipefail` (rc 0) as well as under /bin/sh,
# which is what `_gate_run` execs: every intentionally-failing invocation is written
# `rc=0; cmd || rc=$?`, since the bare form aborted the gate at exit 4 before its own
# bookkeeping. CHANGELOG [6.6.5].
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

# ⭐ CONTROL FOR THE PATTERN ITSELF (6.6.5 review). `nret >= 1` counts the literal string
# `RETIRED:` — a DIFFERENT property from "PAT can still match a constant". Today PAT
# matches exactly one line in $F (the RETIRED paragraph), so rewording that paragraph, or
# breaking PAT, leaves axis A — the stated reason this gate exists — passing by matching
# NOTHING while nret stays 1. So the pattern is proved against SYNTHETIC lines it has
# never seen, which is an expected value computed a different way from $F entirely.
printf '%s\n' '# clock_gettime: ~120ns per call' '# clock read: 120 ns per call' > "$TMP/pat_yes.txt"
[ "$(grep -cE "$PAT" "$TMP/pat_yes.txt" || true)" -eq 2 ] \
    || fail "the axis-A pattern no longer matches a stated per-call clock cost — it cannot see a re-introduced constant, so axis A passes over anything"
printf '%s\n' '# the floor is measured at runtime, per host, per boot' '# 120 windows of 1000 iterations' > "$TMP/pat_no.txt"
[ "$(grep -cE "$PAT" "$TMP/pat_no.txt" || true)" -eq 0 ] \
    || fail "the axis-A pattern now matches ordinary prose — it would fail on any rewording, and a pattern that matches everything is not a check"

# ── B. the measured floor exists and every timing path books through it ──
#
# ⭐ v6.6.5: the inventory moved from `_bench_net(` to `_bench_record(`. Six timing
# functions each carried their own copy of the min/max/total bookkeeping, which is how
# ONE arithmetic mistake — a mean floor subtracted from a quantity whose MINIMUM is then
# reported — reached all six at once and printed `min=0ns` for real work. There is now a
# single accounting site and this axis pins every path to it.
grep -q '^fn bench_clock_overhead_ns()' "$F" || fail "bench_clock_overhead_ns() is gone — the floor is no longer measured"
grep -q '^fn _bench_calibrate_clock()' "$F" || fail "_bench_calibrate_clock() is gone"
grep -q '^fn bench_clock_tick_ns()' "$F" || fail "bench_clock_tick_ns() is gone — window sizing would be blind to a coarse counter again (cass: a 0 floor against a 15ms tick)"
grep -q '^fn bench_clock_recheck()' "$F" || fail "bench_clock_recheck() is gone — one calibration taken in a slow moment would be subtracted from every row again"
grep -q '^fn _bench_record(' "$F" || fail "_bench_record() is gone — the single accounting site is back to six copies"
grep -q '^fn _bench_net(' "$F" || fail "_bench_net() is gone — bench_stop's documented return value"
grep -q 'elapsed - bench_clock_overhead_ns()' "$F" || fail "_bench_net no longer subtracts the measured floor"

# Anti-vacuous for the loop below: the path inventory must actually match.
nrec=$(grep -c '_bench_record(' "$F")
[ "$nrec" -ge 7 ] || fail "only $nrec _bench_record references (expected >= 7: its definition, bench_stop, bench_batch_stop, bench_run and the three bench_run_batch* variants) — a timing path has stopped booking through the single accounting site"

# Per-function scan: every fn that closes a timing window must book through it.
scan() {
    awk -v want="$2" 'index($0, "fn " want "(") == 1 {f=1} f {print} f && /^}/ {exit}' "$1"
}

# ⭐ THE INVENTORY IS DERIVED, NOT LISTED (6.6.5 review). This loop used to run a
# hand-written list of six names against a fixed floor of 7, so a SEVENTH window-closing
# fn added later was neither scanned nor required to raise the floor — the self-drifting
# duplicate shape `capacity_meter_denominators` and `raw_syscall_literals_routed` exist to
# avoid. Derive instead: every fn in $F whose body calls now_ns() is a timing path unless
# it is one of the declared NON-window callers below (the clock itself, the calibration
# set, the two window OPENERS, and bench_report's recheck cadence). A new closer is then
# swept in automatically and must book; a new calibration helper fails loudly here and has
# to be declared, which is the direction the failure should point.
NONWIN='now_ns _bench_cal_round _bench_calibrate_clock _bench_measure_tick _bench_err_ns bench_clock_overhead_ns bench_clock_recheck bench_start bench_batch_start bench_report'
# Every declared exclusion must still EXIST, or the list is carrying a stale name and the
# derived set is smaller than it looks.
for x in $NONWIN; do
    grep -q "^fn $x(" "$F" || fail "axis B's non-window exclusion '$x' is not a fn in $F any more — re-derive the list rather than leaving a stale entry in it"
done
CLOSERS=$(awk '/^fn /{fn=$0; sub(/^fn /,"",fn); sub(/\(.*/,"",fn)} /now_ns\(\)/{if (fn != "") print fn}' "$F" | sort -u)
WINFNS=''
for fnname in $CLOSERS; do
    skip=0
    for x in $NONWIN; do [ "$fnname" = "$x" ] && skip=1; done
    [ "$skip" -eq 1 ] && continue
    WINFNS="$WINFNS $fnname"
done
nwin=$(echo "$WINFNS" | wc -w)
[ "$nwin" -ge 6 ] || fail "only $nwin derived window-closing fns in $F (expected >= 6: bench_stop, bench_batch_stop, bench_run and the three bench_run_batch* variants) — a timing path has been renamed out of the derivation or deleted"
for fnname in $WINFNS; do
    body=$(scan "$F" "$fnname")
    [ -n "$body" ] || fail "could not locate fn $fnname in $F"
    echo "$body" | grep -q '_bench_record(' || fail "fn $fnname closes a timing window without booking it through _bench_record"
    echo "$body" | grep -q 'load64(b + 32)' \
        && fail "fn $fnname touches the min slot directly — that is the per-path duplication _bench_record replaced, and it is how one arithmetic error reached six functions"
done
echo "  derived: $nwin window-closing timing paths, all booking through _bench_record ($(echo $WINFNS))"

# The resolution rule is what stops a window shorter than the clock's own error from
# claiming an extreme. It must live in the accounting site, and it must use the TICK.
scan "$F" _bench_record | grep -q '_BENCH_RESOLVE' || fail "_bench_record no longer applies the resolution rule — every window can claim a per-op min again, which is the 2026-09-16 defect verbatim"
scan "$F" _bench_record | grep -q '_bench_err_ns()' || fail "_bench_record's resolution test no longer uses the clock error (floor PLUS tick)"
grep -q 'bench_clock_overhead_ns() + _bench_clock_tick' "$F" || fail "_bench_err_ns is no longer floor + tick — floor-only error sizes for 0 on a coarse counter (cass)"
# v6.6.5 review: 0 IS still reachable, in exactly one case — an op at or under one clock
# read — and the fix for that is to NAME it, not to invent a number. The predicate and the
# words in the report line are the contract; axis 0 leg (g) of the tcyr and mutant (10)
# below check the behaviour.
grep -q '^fn bench_sub_floor(' "$F" || fail "bench_sub_floor() is gone — the one case where a row legitimately reports 0 (every window at or under one clock read) would be indistinguishable from the 2026-09-16 defect again"
scan "$F" _bench_report_ps | grep -q 'SUB-FLOOR' || fail "the report's supplementary line no longer says SUB-FLOOR — a reader seeing 0 has nothing telling them it means 'below the instrument' rather than the filed bug"
# The tick spin must stay bounded by a DERIVED read budget. The literal 100,000,000 that
# stood here was ~9 minutes on this box's 1.4us reads, x4 rounds, on a clock that stopped.
grep -q '^fn _bench_tick_cap(' "$F" || fail "_bench_tick_cap() is gone — the tick spin is unbounded or bounded by a hardcoded iteration count again"
scan "$F" _bench_measure_tick | grep -q 'guard < cap' || fail "_bench_measure_tick no longer bounds its spin by the derived cap"
scan "$F" _bench_measure_tick | grep -q 'b = a + 1' \
    && fail "_bench_measure_tick fabricates a 1ns tick again — the most broken possible clock would report the smallest possible error, and every window would 'resolve'"
# The book must keep the RAW total and net it at READ time; a per-window clamp biases
# the mean upward and freezes rows against a later floor correction.
scan "$F" bench_total_ns | grep -q 'bench_clock_overhead_ns()' || fail "bench_total_ns no longer nets the floor at read time — a re-measured floor could not correct rows already accumulated"

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
# reads for n iterations; chunked timing performs a few dozen. The probe therefore COUNTS
# the windows `bench_run` consumed — one clock PAIR each — and separately refuses a
# reported average that still has a whole clock read in it. Exit codes are distinct so a
# failure says which property broke.
#
# ⛔ IT USED TO TIME THAT INSTEAD OF COUNTING IT, AND THE TIMED FORM WAS HOST-SPEED
# DEPENDENT. The check was `wall >= n * fl / 2`; divide through by n and it demands that
# the benchmarked op cost less than half a clock read. Here a read is ~1,330 ns and a
# no-op ~3 ns, so it passed by 400×; the identical assertion in
# tests/tcyr/crossos/bench_timer_floor.tcyr was RED 6 runs of 6 on ecb, where v6.6.5's own
# move to `mach_continuous_time` took a read down to 5 ns against a 2.698 ns op. The bar
# and the measurement both being host quantities is what disguises it. `bench_windows(b)`
# states the same property as a count: 3 windows here, 97 on ecb, 5 on a modelled 15 ms
# counter, and exactly n if the chunking is reverted — which is what D2 below proves it
# still catches. CHANGELOG [6.6.5].
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
    bench_run(b, &op, n);
    bench_report(b);
    # No measurable floor on this clock — the cost assertions below would be
    # meaningless rather than green. Distinct code so the gate can say so.
    if (fl <= 0) { return 3; }
    # 2n clock reads vs a few dozen, COUNTED: one window is one clock pair, so this is
    # the read count with no wall clock in it. Per-iteration timing spends n windows.
    if (bench_windows(b) * 20 >= n) { return 4; }
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
prc=0
"$TMP/p" > "$TMP/out" 2> "$TMP/run.err" || prc=$?
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
/^fn _bench_chunk_for\(per_ps, err\): i64 \{$/ { print; print "    return 1;"; skip = 1; next }
skip == 1 && /^\}$/ { print; skip = 0; next }
skip == 1 { next }
{ print }
' lib/bench.cyr > "$TMP/mut/lib/bench.cyr"
if cmp -s lib/bench.cyr "$TMP/mut/lib/bench.cyr"; then
    fail "the chunk-1 mutation is a no-op — _bench_chunk_for's signature changed (v6.6.5 made it (per_ps, err)), so axis D2 proves nothing and axis D could be vacuous again without anyone noticing"
fi
grep -q '^    return 1;$' "$TMP/mut/lib/bench.cyr" || fail "the chunk-1 mutant does not contain the forced return — the awk no longer matches lib/bench.cyr"
cp "$TMP/probe.cyr" "$TMP/mut/probe.cyr"
( cd "$TMP/mut" && "$ROOT/build/cycc" < probe.cyr > mut.bin 2> mut.err ) || fail "probe build against the chunk-1 stdlib"
chmod +x "$TMP/mut/mut.bin"
# `|| mrc=$?`, not a bare call: this mutant is EXPECTED to exit nonzero, and the bare
# form aborts the gate under `bash -eo pipefail` before the assertion below runs.
mrc=0
"$TMP/mut/mut.bin" > /dev/null 2>&1 || mrc=$?
[ "$mrc" != "0" ] || fail "the probe PASSED against a bench_run pinned to one iteration per clock pair — axis D cannot see the defect this release fixed (VACUOUS, which is exactly what it was before v6.5.19)"

# ── D3. the resolution rule, proved by a SCRIPTED clock, and by mutants ──
# ⭐ WHY A SCRIPTED CLOCK AND NOT A MEASUREMENT. The defect fixed in v6.6.5 is a
# STATISTICS defect: a mean floor subtracted from a quantity whose minimum is reported.
# tests/tcyr/crossos/bench_timer_floor.tcyr's own header records two previous attempts to
# gate this file with live timing statistics — one unsatisfiable by construction, one
# flaky enough to pass two runs in three — and the axis that survived them both had
# written the defect down as "not a defect". A host-jitter statistic cannot discriminate
# a bias of the same order as its noise, at any threshold.
#
# `lib/bench.cyr`'s `_bench_clock_fp` seam makes `now_ns()` return scripted virtual time,
# so the probe below states a per-read cost, a jitter, an op and a tick, and every
# expected value is CLOSED FORM from those four numbers — computed from the script, never
# read back from the library. It is identical on every host at any load.
#
# The probe is deliberately NOT the tcyr: two independent statements of the same
# expectations, so a mistake in one is visible against the other. The exit code says which
# property broke.
cat > "$TMP/sc.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/fnptr.cyr"
include "lib/bench.cyr"

var _sc_t = 1000000000000;
var _sc_step = 1000;
var _sc_q0 = 0;
var _sc_q1 = 0;
var _sc_qn = 0;
var _sc_qi = 0;
var _sc_quant = 0;
var _sc_switch_at = 0;
var _sc_step_after = 0;
var _op_ns = 0;

fn _sc_clock(): i64 {
    var s = _sc_step;
    if (_sc_switch_at > 0 && _sc_t >= _sc_switch_at) { s = _sc_step_after; }
    if (_sc_qi < _sc_qn) {
        if (_sc_qi == 0) { s = _sc_q0; } else { s = _sc_q1; }
        _sc_qi = _sc_qi + 1;
    }
    _sc_t = _sc_t + s;
    if (_sc_quant > 0) { return (_sc_t / _sc_quant) * _sc_quant; }
    return _sc_t;
}
fn _sc_reset(step): i64 {
    _bench_clock_fp = &_sc_clock;
    _sc_step = step;
    _sc_qn = 0; _sc_qi = 0; _sc_quant = 0; _sc_switch_at = 0;
    _bench_clock_ns = 0 - 1;
    _bench_floor_shown = 1;
    return bench_clock_overhead_ns();
}
fn _sc_queue2(a, b): i64 { _sc_q0 = a; _sc_q1 = b; _sc_qn = 2; _sc_qi = 0; return 0; }
fn _sc_advance(ns): i64 { _sc_t = _sc_t + ns; return 0; }
fn _sc_op(): i64 { _sc_t = _sc_t + _op_ns; return 0; }
fn _sc_window(b, op, c): i64 {
    bench_start(b);
    _sc_advance(op);
    _sc_queue2(c, c);
    bench_stop(b);
    _sc_qn = 0;
    return 0;
}

fn main(): i64 {
    alloc_init();
    # (1) a 250ns op, one per window, on a 1000ns clock jittering 400/1600: the filed
    #     shape. Net windows -350 and +850. Nothing resolves, so min reports the mean.
    _sc_reset(1000);
    var b = bench_new("j");
    var i = 0;
    while (i < 50) {
        _sc_window(b, 250, 400);
        _sc_window(b, 250, 1600);
        i = i + 1;
    }
    if (bench_min_ps(b) != 250000) { return 21; }
    if (bench_avg_ps(b) != 250000) { return 22; }
    # (2) 1000-op windows of 250.5ns: these resolve, and the arithmetic is sub-ns.
    _sc_reset(1000);
    var c = bench_new("r");
    i = 0;
    while (i < 10) {
        bench_batch_start(c);
        _sc_advance(250500);
        _sc_queue2(400, 400);
        bench_batch_stop(c, 1000);
        _sc_qn = 0;
        bench_batch_start(c);
        _sc_advance(250500);
        _sc_queue2(1600, 1600);
        bench_batch_stop(c, 1000);
        _sc_qn = 0;
        i = i + 1;
    }
    if (bench_min_ps(c) != 249900) { return 23; }
    if (bench_avg_ns(c) != 251) { return 24; }
    # (3) a floor calibrated in a slow moment is re-measured, and rows already booked are
    #     corrected by it.
    _sc_reset(3861);
    _sc_step = 733;
    var d = bench_new("s");
    i = 0;
    while (i < 20) { _sc_window(d, 5000, 733); i = i + 1; }
    _sc_advance(2000000000);
    _bench_floor_shown = 0;
    bench_report(d);
    if (bench_clock_overhead_ns() != 733) { return 25; }
    if (bench_avg_ps(d) != 5000000) { return 25; }
    # (4) a HIGHER re-measurement is reported and declined.
    _sc_reset(733);
    _sc_step = 3861;
    _sc_advance(2000000000);
    bench_report(d);
    if (bench_clock_overhead_ns() != 733) { return 26; }
    # (5) calibration repeats until two rounds agree.
    _bench_clock_fp = &_sc_clock;
    _sc_qn = 0; _sc_quant = 0;
    _sc_step = 3861;
    _sc_switch_at = _sc_t + 45000000;
    _sc_step_after = 733;
    _bench_clock_ns = 0 - 1;
    if (bench_clock_overhead_ns() != 733) { return 27; }
    _sc_switch_at = 0;
    # (6) bench_run's pilot and tail cannot set an extreme.
    _sc_reset(1000);
    _op_ns = 3;
    var e = bench_new("p");
    _sc_queue2(1000, 0);
    bench_run(e, &_sc_op, 300000);
    if (bench_iterations(e) != 300000) { return 29; }
    if (bench_min_ps(e) != 3000) { return 29; }
    if (bench_max_ps(e) != 3000) { return 29; }
    # (7) a 15ms counter: windows are sized by the TICK, not by a 0 floor.
    _bench_clock_fp = &_sc_clock;
    _sc_qn = 0; _sc_switch_at = 0;
    _sc_step = 50;
    _sc_quant = 15000000;
    _bench_clock_ns = 0 - 1;
    if (bench_clock_overhead_ns() != 0) { return 28; }
    if (bench_clock_tick_ns() != 15000000) { return 28; }
    _op_ns = 2000;
    var f = bench_new("c");
    bench_run(f, &_sc_op, 4000000);
    if (bench_min_resolved(f) != 1) { return 28; }
    if (bench_min_ps(f) < 1960000) { return 28; }
    if (bench_min_ps(f) > 2040000) { return 28; }
    # (8) THE ONE CASE THAT MAY REPORT 0, and it must be FLAGGED rather than silent. An op
    #     at or under one clock read leaves raw_total <= windows*floor, the netted total
    #     clamps, and mean/min/max are 0 with it. The 6.6.5 header claimed "never 0 for
    #     real work" and review disproved it; 0 stays (reporting the raw mean would report
    #     the clock) and `bench_sub_floor` names it. The 250ns control on the SAME script
    #     must NOT be flagged, so "always 1" and "always 0" both fail here.
    _sc_reset(1000);
    var g = bench_new("s");
    i = 0;
    while (i < 100) { _sc_window(g, 0, 1000); i = i + 1; }
    if (bench_total_ns(g) != 0) { return 30; }
    if (bench_avg_ps(g) != 0) { return 30; }
    if (bench_min_ps(g) != 0) { return 30; }
    if (bench_sub_floor(g) != 1) { return 30; }
    var h = bench_new("t");
    i = 0;
    while (i < 50) {
        _sc_window(h, 250, 400);
        _sc_window(h, 250, 1600);
        i = i + 1;
    }
    if (bench_sub_floor(h) != 0) { return 30; }
    if (bench_min_ps(h) != 250000) { return 30; }
    _bench_clock_fp = 0;
    return 0;
}
var rc = main();
syscall(60, rc);
EOF
"$ROOT/build/cycc" < "$TMP/sc.cyr" > "$TMP/sc" 2> "$TMP/sc.err" || { cat "$TMP/sc.err"; fail "scripted-clock probe build"; }
[ -s "$TMP/sc" ] || fail "the scripted-clock probe compiled to an EMPTY binary — an empty file runs with exit 0, so every mutant below would look killed and the baseline would look green"
chmod +x "$TMP/sc"
src=0
"$TMP/sc" > "$TMP/sc.out" 2>&1 || src=$?
case "$src" in
  0)  : ;;
  21) fail "scripted: a 250ns op timed one-per-window does not report min=250ns — a window shorter than the clock's own error is claiming a per-op minimum again (this is the 2026-09-16 filing verbatim)" ;;
  22) fail "scripted: the mean of the same windows is not exact — a per-window clamp at 0 is biasing it upward again" ;;
  23) fail "scripted: a resolved window's min is not exact to the picosecond" ;;
  24) fail "scripted: 250.5ps-per-op does not round HALF UP to 251ns — per-op values are truncating again" ;;
  25) fail "scripted: a floor calibrated in a slow moment is not re-measured, or rows already booked are not re-netted by the correction" ;;
  26) fail "scripted: a HIGHER re-measured floor was ADOPTED — over-subtraction is exactly what makes rows read 0" ;;
  27) fail "scripted: calibration stopped at one round, so a slow moment becomes the whole process's floor" ;;
  28) fail "scripted: on a 15ms counter the windows are not sized by the tick — floor-only sizing is back, which is what made cass thrash between 1 and 4096 iterations per window" ;;
  29) fail "scripted: bench_run's pilot or tail chunk set min/max — that is what made bench_run(noop, 1e5) report min=0 in 91 of 200 runs" ;;
  30) fail "scripted: the sub-floor case is wrong — either an op at or under one clock read is no longer reported as 0-with-bench_sub_floor()==1, or a 250ns op on the same clock is being flagged sub-floor (0 is legitimate ONLY there, and it must be named)" ;;
  *)  cat "$TMP/sc.out"; fail "scripted-clock probe exited $src" ;;
esac

# Nine mutants, applied to COPIES of lib/bench.cyr. Each must be a real edit (cmp) and
# each must turn the probe RED. The gate re-proves its own sensitivity on every run —
# axis D was demonstrably vacuous for the defect it shipped with, so "this axis can still
# see it" is not something to take on trust.
nmut=0
run_mut() {
    mname=$1; mold=$2; mnew=$3
    md="$TMP/mut3/$mname"
    mkdir -p "$md/lib" || exit 2
    cp lib/*.cyr "$md/lib/" || exit 2
    awk -v old="$mold" -v new="$mnew" \
        'BEGIN{n=0} $0==old {print new; n++; next} {print} END{ if (n!=1) exit 9 }' \
        lib/bench.cyr > "$md/lib/bench.cyr" \
        || fail "mutant $mname: its anchor line no longer appears EXACTLY once in lib/bench.cyr, so this mutant is not being applied and the axis is silently weaker"
    if cmp -s lib/bench.cyr "$md/lib/bench.cyr"; then
        fail "mutant $mname is a no-op — it proves nothing"
    fi
    cp "$TMP/sc.cyr" "$md/p.cyr"
    # ⛔ A MUTANT THAT DOES NOT COMPILE PROVES NOTHING, AND USED TO BE COUNTED AS KILLED.
    # Through the first cut of this axis a build failure incremented the kill count and
    # returned, so "9/9 mutants killed" could include a mutant that only demonstrated a
    # syntax error — the probe never ran and the axis was that much weaker, silently.
    # (Latent when found: all nine did build.) Now it is a loud FAIL. Same for an empty
    # binary: an empty file executes with exit 0, which would read as a SURVIVING mutant
    # here and produce a confusing failure instead of an accurate one.
    # ⚠ Every invocation below is written `rc=0; cmd || rc=$?` rather than `cmd; rc=$?`:
    # the mutant run is EXPECTED to fail, and the bare form aborts the whole gate under
    # `bash -eo pipefail` before the bookkeeping runs (measured: exit 4). CHANGELOG [6.6.5].
    mbrc=0
    ( cd "$md" && "$ROOT/build/cycc" < p.cyr > m.bin 2> m.err ) || mbrc=$?
    if [ "$mbrc" != "0" ]; then
        cat "$md/m.err" 2>/dev/null || true
        fail "mutant $mname does not COMPILE — it proves nothing about the axis, and counting it as killed is how a mutation ledger inflates itself"
    fi
    [ -s "$md/m.bin" ] || fail "mutant $mname compiled to an EMPTY binary — an empty file runs with exit 0, so it would be scored as a survivor rather than as the broken build it is"
    chmod +x "$md/m.bin"
    mrc2=0
    ( cd "$md" && ./m.bin > m.out 2>&1 ) || mrc2=$?
    [ "$mrc2" != "0" ] || fail "mutant $mname SURVIVED the scripted-clock probe — the axis cannot see that defect, which is what 'vacuous' looks like"
    nmut=$((nmut + 1))
}
run_mut min_over_all_windows \
    '    if (net >= _BENCH_RESOLVE * _bench_err_ns()) {' \
    '    if (1 == 1) {'
run_mut per_window_clamp_in_total \
    '    store64(b + 16, load64(b + 16) + raw);' \
    '    var rr = raw;\n    if (rr < fl) { rr = fl; }\n    store64(b + 16, load64(b + 16) + rr);'
run_mut integer_ns_per_op \
    '    var ps = (net / k) * 1000 + ((net % k) * 1000) / k;' \
    '    var ps = (net / k) * 1000;'
run_mut recheck_removed \
    'fn bench_clock_recheck(): i64 {' \
    'fn bench_clock_recheck(): i64 {\n    return 0;'
run_mut recheck_adopts_higher \
    '    _bench_puts("  [clock floor re-measured HIGHER: ");' \
    '    _bench_clock_ns = cur;\n    _bench_puts("  [clock floor re-measured HIGHER: ");'
run_mut single_calibration_round \
    '    var r = 1;' \
    '    var r = 8;'
run_mut err_is_floor_only \
    '    return bench_clock_overhead_ns() + _bench_clock_tick;' \
    '    return bench_clock_overhead_ns();'
run_mut truncating_round \
    '    return (ps + 500) / 1000;' \
    '    return ps / 1000;'
run_mut unresolved_min_is_zero \
    '    if (load64(b + 56) > 0) { return load64(b + 32); }' \
    '    if (load64(b + 56) > 0) { return load64(b + 32); }\n    return 0;'
# (10) v6.6.5 review. `bench_sub_floor` is the NAME on the one case that legitimately
# reports 0; a predicate that always answers 0 would leave that case looking exactly like
# the filed defect. The probe's leg (8) also runs a 250ns control, so the mirror mutant
# ("always 1") is caught by the same exit code.
run_mut sub_floor_never_flagged \
    'fn bench_sub_floor(b): i64 {' \
    'fn bench_sub_floor(b): i64 {\n    return 0;'
[ "$nmut" -eq 10 ] || fail "only $nmut of 10 mutants ran"

# ── D4. a CONSUMER's grammar, copied verbatim, not this file's own ───
# ⭐ The row shape is an ecosystem contract: goonj, hisab, mabda, chitra, vani, libro and
# szal parse it. v6.6.5 moves per-op values to picoseconds internally and adds two
# supplementary lines, so the thing to check is not "bench_report still prints something"
# but "goonj can still read it". ROW_RE, TIME_RE and FLOOR_RE below are COPIED from
# goonj/scripts/bench-history.sh (they are EREs there too, matched with bash `=~`; the
# only change here is `grep -E`). The integer-ns check reproduces its `to_ns`, which does
# `$((10#${t%ns}))` and fails outright on a fractional ns.
TIME_RE='[0-9]+\.?[0-9]*(ns|us|ms|s)'
ROW_RE="^[[:space:]]*(.+): ($TIME_RE) avg \(min=($TIME_RE) max=($TIME_RE)\) \[([0-9]+) iters\][[:space:]]*$"
FLOOR_RE="\[timer floor ($TIME_RE) per clock read"

grep -E "$FLOOR_RE" "$TMP/out" >/dev/null || { cat "$TMP/out"; fail "the timer-floor line no longer matches goonj's FLOOR_RE — bench-history.sh would record no floor for any suite"; }
nrows=0
while IFS= read -r line; do
    # goonj's selector, verbatim: anything without ": " + " avg" is not a row.
    case "$line" in *": "*" avg"*) ;; *) continue ;; esac
    echo "$line" | grep -E "$ROW_RE" >/dev/null \
        || { echo "$line"; fail "a bench_report row matches goonj's ' avg' selector but NOT its ROW_RE — every consumer would warn and drop the row, which looks identical to the benchmark having been deleted"; }
    # Integer ns, or goonj's to_ns is a bash syntax error on the row.
    for t in $(echo "$line" | sed 's/.*: //; s/ avg (min=/ /; s/ max=/ /; s/).*//'); do
        case "$t" in
            *ns) echo "$t" | grep -q '\.' && fail "bench_report printed a FRACTIONAL ns ($t) — goonj's to_ns does \$((10#\${t%ns})) and fails outright; sub-nanosecond belongs on the supplementary line, not in the row" ;;
        esac
    done
    nrows=$((nrows + 1))
done < "$TMP/out"
[ "$nrows" -ge 1 ] || { cat "$TMP/out"; fail "no parseable result row in the probe output — axis D4 would be vacuous"; }

# Every line bench_report adds must be invisible to the recorders: it starts with '[' and
# never contains ' avg'. A supplementary line that looked like a row would land in
# bench-history.csv as a fake benchmark.
grep -v -E "$ROW_RE" "$TMP/out" | grep ' avg' \
    && fail "a non-row line in bench_report's output contains ' avg' — scripts/bench-history.sh and goonj both select on that and would record it as a benchmark"
sed 's/^[[:space:]]*//' "$TMP/out" | grep -v -E "$ROW_RE" | grep -v '^\[' | grep -v '^$' \
    && fail "bench_report emitted a line that is neither a result row nor bracketed — the consumer grammars assume every non-row line starts with '['"
# Anti-vacuous for the two checks above: there IS at least one non-row line to classify
# (the floor line, and on a sub-100ns row the picosecond line). Without this, deleting
# every supplementary line would make them pass by having nothing to look at.
nbr=$(sed 's/^[[:space:]]*//' "$TMP/out" | grep -c '^\[')
[ "$nbr" -ge 2 ] || fail "only $nbr bracketed line(s) in the probe output (expected >= 2: the timer-floor line and the per-op picosecond line for a sub-100ns row) — the two grammar checks above would be vacuous"

# ── E. the two clock modules stay SELF-SUFFICIENT for PE ────────────────────────────
#
# ⛔ 6.6.5 review. This bite's first cut routed the Windows clock through
# lib/syscalls_windows.cyr's `sys_qpc_ns()` from BOTH lib/chrono.cyr and lib/bench.cyr.
# chrono.cyr includes only atomic.cyr and bench.cyr includes nothing at all, so a consumer
# whose `[deps] stdlib` names "chrono" (or "bench") without "syscalls" stopped building for
# Windows with `undefined function 'sys_qpc_ns'` — where 6.6.4's `syscall(228)` had built.
# Nothing in-repo saw it: every in-repo consumer pulls lib/syscalls.cyr. The vendoring
# closure cannot rescue it either — `_distlib_union_declared_stdlib` (cbt/commands.cyr)
# derives its edges from literal `include "lib/X.cyr"` lines, and neither file has one.
# Both now spell 0xF038/0xF039 raw. This axis CROSS-BUILDS the two probes for PE rather
# than grepping for the wrapper name, so it also fails if the raw route stops compiling.
for mod in chrono bench; do
    if [ "$mod" = chrono ]; then
        cat > "$TMP/self_$mod.cyr" <<'EOS'
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/chrono.cyr"
fn main(): i64 { if (clock_now_ns() <= 0) { return 1; } return 0; }
EOS
    else
        cat > "$TMP/self_$mod.cyr" <<'EOS'
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
include "lib/bench.cyr"
fn main(): i64 { var b = bench_new("x"); bench_start(b); var r = bench_stop(b); return 0; }
EOS
    fi
    erc=0
    CYRIUS_TARGET_WIN=1 "$ROOT/build/cycc" < "$TMP/self_$mod.cyr" > "$TMP/self_$mod.exe" 2> "$TMP/self_$mod.err" || erc=$?
    [ "$erc" -eq 0 ] || { grep -E "^(error|warning: undefined)" "$TMP/self_$mod.err" | head -4 | sed 's/^/    /'
        fail "lib/$mod.cyr is no longer self-sufficient for PE: a consumer declaring only \"$mod\" cannot cross-build for Windows (rc $erc)"; }
    # An empty file "runs" with exit 0, so the size floor is not decoration.
    [ "$(wc -c < "$TMP/self_$mod.exe")" -gt 4096 ] || fail "the PE build of the $mod-only consumer produced a $(wc -c < "$TMP/self_$mod.exe")-byte binary"
    grep -q "undefined function 'sys_" "$TMP/self_$mod.err" \
        && { grep "undefined function 'sys_" "$TMP/self_$mod.err" | head -3 | sed 's/^/    /'
             fail "lib/$mod.cyr references a lib/syscalls*.cyr wrapper the module does not include — spell the route raw, the way its other arms spell syscall(228)"; }
    # ANTI-VACUOUS #1, from the SOURCE rather than the compile: derive the fn the clock's
    # CYRIUS_TARGET_WIN arm actually calls, and require THAT fn to live in this same file
    # and to spell both raw routes. A compile-only check passes over a Windows arm that was
    # simply reverted to GetTickCount64 — measured: mutant M7 (chrono's arm rewritten to
    # `syscall(228, 1, &ts) * 1000000`) still built, and still carried both QueryPerformance
    # imports, because the now-unreachable helper is kept in the binary.
    entry=clock_now_ns
    [ "$mod" = bench ] && entry=now_ns
    grep -q "^fn $entry(" "lib/$mod.cyr" || fail "lib/$mod.cyr has no fn $entry — axis E cannot find the clock entry point"
    armfn=$(scan "lib/$mod.cyr" "$entry" \
        | awk '/#ifdef CYRIUS_TARGET_WIN/{w=1;next} w&&/#endif/{w=0} w&&/^ *return [_A-Za-z0-9]+\(\);/{print; exit}' \
        | sed 's/^ *return //; s/().*//')
    [ -n "$armfn" ] || fail "lib/$mod.cyr's $entry has no CYRIUS_TARGET_WIN arm that returns a local call — the Windows clock route has been changed or removed"
    grep -q "^fn $armfn(" "lib/$mod.cyr" \
        || fail "lib/$mod.cyr's Windows clock arm calls $armfn, which is NOT defined in this file — that is exactly the self-sufficiency break (it was sys_qpc_ns, from lib/syscalls_windows.cyr)"
    scan "lib/$mod.cyr" "$armfn" | grep -q 'syscall(61496' \
        || fail "lib/$mod.cyr's $armfn does not spell QueryPerformanceCounter (raw 61496 / 0xF038) — the Windows clock is back on a coarser source"
    scan "lib/$mod.cyr" "$armfn" | grep -q 'syscall(61497' \
        || fail "lib/$mod.cyr's $armfn does not spell QueryPerformanceFrequency (raw 61497 / 0xF039) — a QPC count with no frequency is not nanoseconds"
    # ANTI-VACUOUS #2: and the PE import table must name both routes, so a source that
    # merely MENTIONS them while the emitter stopped routing them fails here.
    nqp=$(strings -a "$TMP/self_$mod.exe" 2>/dev/null | grep -c 'QueryPerformance' || true)
    [ "$nqp" -ge 2 ] || fail "the PE build of the $mod-only consumer imports $nqp QueryPerformance* names (expected 2: Counter and Frequency) — the Windows clock arm is not in the binary, so this axis proved nothing"
    # And it must still build for the host, so a PE-only fix cannot pass here.
    lrc=0
    "$ROOT/build/cycc" < "$TMP/self_$mod.cyr" > "$TMP/self_$mod.elf" 2> "$TMP/self_$mod.lerr" || lrc=$?
    [ "$lrc" -eq 0 ] || { grep -E '^error' "$TMP/self_$mod.lerr" | head -3 | sed 's/^/    /'
        fail "the ELF build of the $mod-only consumer failed (rc $lrc)"; }
done

echo "PASS: bench timer floor is measured (no hardcoded per-call constant, 6 timing paths book through one accounting site, bench_run self-sizes and PROVES it by cost, resolution rule proved by a scripted clock with $nmut/10 mutants killed, $nrows row(s) parse under goonj's own ROW_RE, report stays out of bench-history, chunk-1 mutant rejected with rc=$mrc, chrono-only and bench-only consumers both cross-build for PE)"
exit 0

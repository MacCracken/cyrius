#!/bin/sh
# agnos_monotonic_clock_rdtsc.sh — v6.6.1. On AGNOS, `clock_now_ns()` must read #95
# (`uptime_us`, rdtsc) and NOT #40 (`uptime_ms`, timer_ticks).
#
# ⛔ WHY. A foreground `run` program on AGNOS executes with IF CLEARED — only /bin/agnsh gets
# IF=1 — so the 100 Hz timer ISR never fires, `timer_ticks` never advances, and #40 is FROZEN
# for that program's entire run. Anything timing itself with it measured exactly ZERO, forever,
# with no error. #95 is read via rdtsc, needs no interrupts, and is the only correct monotonic
# source on that path.
#
# ⚠ THE TRAP WAS ALREADY DOCUMENTED TWO FILES AWAY, above the very wrapper this code did not
# call — `lib/syscalls_x86_64_agnos.cyr`'s sys_uptime_us says in as many words that "#95 is the
# only correct clock there", and AGNOS's ABI note records that it cost two iron burns on the 3D
# arc's rung-10 gate. The general-purpose clock still walked into it, from v6.2.6 to v6.6.0.
# That is what this gate is for: prose next to the hazard did not stop the next caller.
# (v6.2.6's binding was correct WHEN WRITTEN — #95 did not exist yet.)
#
# ⭐ AXIS 2 IS THE ANTI-VACUOUS ONE. A source grep alone would pass if the wrapper were never
# linked; axis 2 compiles for AGNOS and asserts the syscall immediate 95 (0x5f) is actually
# EMITTED. Axis 3 proves the non-AGNOS path was not disturbed.
# v6.6.5 (review): SHELL-AGNOSTIC. Every `llvm-objdump ... | grep -q ...` here false-RED'd
# under `bash -eo pipefail` — grep -q closes the pipe on its first hit, objdump takes
# SIGPIPE, and pipefail makes the pipeline 141, so the gate printed axis 3's FAIL text on a
# perfectly good tree (rc 1) while passing under /bin/sh, which is what `_gate_run` execs.
# `grep -c` in a `$(...)` is the same class one step over: it exits 1 on a count of 0, which
# aborts the assignment under `set -e`. Both are now disassemble-to-a-file then grep, with
# `|| true` on the counts. The sibling gate this bite also touched
# (tests/gates/toolchain/bench_timer_floor_measured.sh) had the same defect repaired in the
# same release and it was not carried across — hence this note. CHANGELOG [6.6.5].
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL agnos_monotonic_clock_rdtsc: no build/cycc"; exit 1; }

# ── axis 1 — the AGNOS branch of clock_now_ns names uptime_us, not uptime_ms ─────────────────
BODY=$(awk '/^fn clock_now_ns\(\)/,/^}/' "$R/lib/chrono.cyr" | sed 's/#.*//')
echo "$BODY" | grep -q 'sys_uptime_us' || {
  echo "FAIL agnos_monotonic_clock_rdtsc axis1: clock_now_ns does not call sys_uptime_us (#95)."
  echo "  On AGNOS the timer-tick clock (#40) is FROZEN in a foreground run program."; exit 1; }
if echo "$BODY" | grep -q 'sys_uptime_ms'; then
  echo "FAIL agnos_monotonic_clock_rdtsc axis1: clock_now_ns still calls sys_uptime_ms (#40) —"
  echo "  that clock never advances for a foreground AGNOS program."; exit 1
fi

# ── axis 2 — an AGNOS build actually EMITS syscall 95 ────────────────────────────────────────
cat > "$T/c.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/chrono.cyr"
fn main(): i64 { return clock_now_ns(); }
var e = main();
EOF
CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/c.cyr" > "$T/c.out" 2>"$T/c.err" || {
  echo "FAIL agnos_monotonic_clock_rdtsc axis2: CYRIUS_TARGET_AGNOS build failed"
  grep -E '^error' "$T/c.err" | head -3 | sed 's/^/    /'; exit 1; }

if command -v llvm-objdump > /dev/null 2>&1; then
  # ⚠ DISASSEMBLE TO A FILE, THEN GREP — never `objdump | grep`. `grep -q` closes the pipe
  # on its first hit, objdump takes SIGPIPE, and under `-o pipefail` the whole pipeline is
  # 141 → this gate false-REDs with axis 3's message under `bash -eo pipefail` while passing
  # under /bin/sh. `grep -c` is no safer: it exits 1 on a count of 0, which aborts the
  # assignment under `set -e`. Both shapes are spelled out below. CHANGELOG [6.6.5].
  llvm-objdump -d --no-show-raw-insn "$T/c.out" > "$T/c.dis" 2>/dev/null || true
  N95=$(grep -c 'movl.*\$0x5f, %eax' "$T/c.dis" || true)
  [ "$N95" -ge 1 ] || {
    echo "FAIL agnos_monotonic_clock_rdtsc axis2: the AGNOS build emits no syscall 95 (0x5f)."
    echo "  The uptime_us wrapper is not reaching the binary, so axis 1 proves nothing."; exit 1; }
else
  echo "  (llvm-objdump absent — axis 2 emission check skipped)"
fi

# ── axis 3 — ANTI-VACUOUS: the non-AGNOS path still uses clock_gettime (228 = 0xe4) ──────────
"$CC" < "$T/c.cyr" > "$T/l.out" 2>/dev/null || {
  echo "FAIL agnos_monotonic_clock_rdtsc axis3: the ordinary (Linux) build failed"; exit 1; }
if command -v llvm-objdump > /dev/null 2>&1; then
  llvm-objdump -d --no-show-raw-insn "$T/l.out" > "$T/l.dis" 2>/dev/null || true
  [ "$(grep -c '0xe4' "$T/l.dis" || true)" -ge 1 ] || {
    echo "FAIL agnos_monotonic_clock_rdtsc axis3: the Linux build no longer references"
    echo "  clock_gettime (228/0xe4) — the AGNOS change leaked into the portable path."; exit 1; }
fi

# ── axis 4 — v6.6.5: lib/bench.cyr's now_ns has the SAME AGNOS arm ───────────────────────────
# ⛔ chrono got its #95 arm at 6.6.1 and lib/bench.cyr DID NOT, for four patch releases. An
# AGNOS build of the bench framework emitted a raw `movl $0xe4,%eax; syscall` — clock_gettime,
# which AGNOS does not define at all (it is absent from lib/syscalls_x86_64_agnos.cyr) — so the
# `var ts[16]` it then read back was undefined memory. Verified with llvm-objdump before the
# fix. The general lesson is the one axis 1 already carries: a correction applied to ONE clock
# caller is not a correction. Both callers are pinned here, on the same axis, so the next one
# cannot drift alone.
BB=$(awk '/^fn now_ns\(\)/,/^}/' "$R/lib/bench.cyr" | sed 's/#ifdef/@IFDEF/; s/#ifndef/@IFNDEF/; s/#endif/@ENDIF/; s/#.*//')
echo "$BB" | grep -q 'sys_uptime_us' || {
  echo "FAIL agnos_monotonic_clock_rdtsc axis4: lib/bench.cyr's now_ns has no sys_uptime_us (#95) arm."
  echo "  An AGNOS build then emits a raw syscall 228, which AGNOS does not define."; exit 1; }
echo "$BB" | grep -q '@IFDEF CYRIUS_TARGET_AGNOS' || {
  echo "FAIL agnos_monotonic_clock_rdtsc axis4: bench's now_ns does not guard the AGNOS arm with"
  echo "  #ifdef CYRIUS_TARGET_AGNOS — it would take that path on Linux too."; exit 1; }

cat > "$T/b.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/fnptr.cyr"
include "lib/bench.cyr"
fn main(): i64 { return now_ns(); }
var e = main();
EOF
CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/b.cyr" > "$T/b.out" 2>"$T/b.err" || {
  echo "FAIL agnos_monotonic_clock_rdtsc axis4: CYRIUS_TARGET_AGNOS build of lib/bench.cyr failed"
  grep -E '^error' "$T/b.err" | head -3 | sed 's/^/    /'; exit 1; }
[ -s "$T/b.out" ] || { echo "FAIL agnos_monotonic_clock_rdtsc axis4: the AGNOS bench build produced an EMPTY binary"; exit 1; }

if command -v llvm-objdump > /dev/null 2>&1; then
  llvm-objdump -d --no-show-raw-insn "$T/b.out" > "$T/b.dis" 2>/dev/null || true
  B95=$(grep -c 'movl.*\$0x5f, %eax' "$T/b.dis" || true)
  [ "$B95" -ge 1 ] || {
    echo "FAIL agnos_monotonic_clock_rdtsc axis4: the AGNOS bench build emits no syscall 95 (0x5f)."; exit 1; }
  B228=$(grep -c 'movl.*\$0xe4, %eax' "$T/b.dis" || true)
  [ "$B228" -eq 0 ] || {
    echo "FAIL agnos_monotonic_clock_rdtsc axis4: the AGNOS bench build still emits $B228 raw"
    echo "  syscall 228 (0xe4) — AGNOS does not define clock_gettime, so that read is undefined."; exit 1; }
  # ANTI-VACUOUS: the ordinary Linux build of the SAME probe must still use 228, or axis 4
  # would pass on a bench.cyr whose clock was simply deleted.
  "$CC" < "$T/b.cyr" > "$T/bl.out" 2>/dev/null || {
    echo "FAIL agnos_monotonic_clock_rdtsc axis4: the Linux build of the bench probe failed"; exit 1; }
  llvm-objdump -d --no-show-raw-insn "$T/bl.out" > "$T/bl.dis" 2>/dev/null || true
  [ "$(grep -c 'movl.*\$0xe4, %eax' "$T/bl.dis" || true)" -ge 1 ] || {
    echo "FAIL agnos_monotonic_clock_rdtsc axis4: the Linux bench build no longer emits"
    echo "  clock_gettime (228/0xe4) — the AGNOS arm leaked into the portable path."; exit 1; }
else
  echo "  (llvm-objdump absent — axis 4 emission checks skipped)"
fi

echo 'PASS agnos_monotonic_clock_rdtsc: clock_now_ns AND bench now_ns read #95 (rdtsc uptime_us), never #40 (frozen timer_ticks) · both AGNOS builds emit syscall 95 and no raw 228 · the Linux path still uses clock_gettime'
exit 0

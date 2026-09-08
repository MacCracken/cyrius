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
  N95=$(llvm-objdump -d --no-show-raw-insn "$T/c.out" 2>/dev/null | grep -c 'movl.*\$0x5f, %eax')
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
  llvm-objdump -d --no-show-raw-insn "$T/l.out" 2>/dev/null | grep -q '0xe4' || {
    echo "FAIL agnos_monotonic_clock_rdtsc axis3: the Linux build no longer references"
    echo "  clock_gettime (228/0xe4) — the AGNOS change leaked into the portable path."; exit 1; }
fi

echo 'PASS agnos_monotonic_clock_rdtsc: clock_now_ns reads #95 (rdtsc uptime_us), never #40 (frozen timer_ticks) · an AGNOS build emits syscall 95 · the Linux path still uses clock_gettime'
exit 0

#!/bin/sh
# agnos_monotonic_clock_rdtsc.sh — v6.6.1, reworked 6.6.7. On AGNOS every monotonic clock in
# lib/ must read #95 (`uptime_us`, rdtsc) FIRST, and may read #40 (`uptime_ms`) only as the
# LATCHED fallback taken once #95 has answered < 0 (TSC calibration refused).
#
# ⛔ 6.6.7 — THE -1 SENTINEL. #95 returns -1, never a plausible 0, when calibration was refused;
# that is permanent for the boot and ALWAYS the case under mirshi. clock_now_ns and bench's
# now_ns multiplied it by 1000 unchecked, so the clock stood still at -1000 ns (0 ms after
# clock_now_ms truncated it) and every `while (clock_now_ms() - t0 < N)` wait spun forever —
# daimon's repro. The old axis 1 FORBADE #40 in clock_now_ns outright, which made the correct
# fallback impossible to write, and it pinned each file separately, which is how bench lagged
# chrono by four releases. Axis 1 is now DERIVED: it finds every #95 reader in lib/*.cyr and
# requires each to test the result `< 0` / `>= 0`, with any #40 read strictly after that test.
# A new copy (a socket deadline, a third clock) is pinned the moment it is written.
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
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: agnos_monotonic_clock_rdtsc: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL agnos_monotonic_clock_rdtsc: no build/cycc"; exit 1; }

# ── axis 1 — DERIVED: every #95 reader in lib/ checks the -1 sentinel before using it ──────
# For each fn in lib/*.cyr (comments stripped) that reads #95 — `sys_uptime_us()`,
# `syscall(95)` or `syscall(SYS_UPTIME_US)` — other than the wrapper itself:
#   (a) the result must land in a variable (`[var] X = <read>;`), never feed arithmetic directly;
#   (b) that variable must be tested `X < 0` or `X >= 0` later in the same fn;
#   (c) any #40 read — `sys_uptime_ms()`, `syscall(40)`, `syscall(SYS_UPTIME_MS)`; spelling it
#       raw does not dodge the axis — must come AFTER that test, i.e. only as the fallback.
# A fn that reads #40 and NOT #95 fails too: that is the frozen-timer_ticks clock of v6.6.0.
# clock_now_ns and bench's now_ns must also LATCH (assign a top-level flag after the test), so a
# refused boot costs one #95 call and not one per read. Prints "BAD <file>:<fn> <why>" per
# violation and "OK <file>:<fn> [latch]" per conforming reader.
A1=$(awk '
function flush(   i, j, v, chk, r95, bad, why, latch, ln) {
    if (fn == "" || fn == "sys_uptime_us" || fn == "sys_uptime_ms") { fn = ""; n = 0; return }
    r95 = 0; bad = 0; chk = 0; latch = 0
    for (i = 1; i <= n; i++) {
        ln = L[i]
        if (ln ~ /sys_uptime_us\(\)|syscall\((95|SYS_UPTIME_US)\)/) {
            r95 = r95 + 1
            if (ln !~ /^[ \t]*(var[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*(sys_uptime_us\(\)|syscall\((95|SYS_UPTIME_US)\))[ \t]*;/) {
                bad = 1; why = "uses the #95 result without first storing and testing it (line " S[i] ")"; break
            }
            v = ln; sub(/^[ \t]*(var[ \t]+)?/, "", v); sub(/[ \t]*=.*/, "", v)
            chk = 0
            for (j = i + 1; j <= n; j++) {
                if (L[j] ~ ("(^|[^A-Za-z0-9_])" v "[ \t]*(<|>=)[ \t]*0([^0-9A-Za-z_x]|$)")) { chk = j; break }
            }
            if (chk == 0) { bad = 1; why = "reads #95 into `" v "` and never tests it < 0 / >= 0 (line " S[i] ")"; break }
        }
        if (ln ~ /sys_uptime_ms\(\)|syscall\((40|SYS_UPTIME_MS)\)/) {
            if (r95 == 0 || chk == 0 || i <= chk) {
                bad = 1; why = "reads #40 (line " S[i] ") other than as the fallback after a tested #95 read"; break
            }
        }
        if (chk > 0 && i > chk && ln ~ /^[ \t]*_[A-Za-z0-9_]+[ \t]*=[ \t]*[1-9][0-9]*[ \t]*;/) latch = 1
    }
    if (bad) print "BAD " F ":" fn " " why
    else if (r95 > 0) print "OK " F ":" fn (latch ? " latch" : "")
    fn = ""; n = 0
}
FNR == 1 { flush() }
/^(pub[ \t]+|public[ \t]+|private[ \t]+)?fn[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*\(/ {
    flush()
    F = FILENAME; fn = $0; sub(/^(pub[ \t]+|public[ \t]+|private[ \t]+)?fn[ \t]+/, "", fn); sub(/[ \t]*\(.*/, "", fn)
}
fn != "" {
    t = $0; sub(/#.*/, "", t); n = n + 1; L[n] = t; S[n] = FNR
    if (t ~ /^}/ || (n == 1 && t ~ /}[ \t]*$/)) flush()
}
END { flush() }
' "$R"/lib/*.cyr | sed "s|$R/||")
BAD1=$(printf '%s\n' "$A1" | grep '^BAD ' || true)
[ -z "$BAD1" ] || {
  echo "FAIL agnos_monotonic_clock_rdtsc axis1: a #95 (uptime_us) reader does not handle the -1 sentinel:"
  printf '%s\n' "$BAD1" | sed 's/^BAD /    /'
  echo "  #95 answers -1 whenever TSC calibration was refused (always under mirshi); an unchecked"
  echo "  read is a clock that stands still. Test it and fall back to #40 (see lib/chrono.cyr)."; exit 1; }
NR1=$(printf '%s\n' "$A1" | grep -c '^OK ' || true)
# ANTI-VACUOUS: an awk that matched nothing reports nothing wrong. chrono, bench and sakshi
# all read #95 today, so fewer than 3 readers means the scan is broken, not the tree clean.
[ "$NR1" -ge 3 ] || { echo "FAIL agnos_monotonic_clock_rdtsc axis1: derived only $NR1 #95 readers in lib/ (expected >= 3: chrono, bench, sakshi) — the scan is reading nothing"; exit 1; }
for want in 'lib/chrono.cyr:clock_now_ns' 'lib/bench.cyr:now_ns'; do
  printf '%s\n' "$A1" | grep -q "^OK $want latch\$" || {
    echo "FAIL agnos_monotonic_clock_rdtsc axis1: $want is not a LATCHED #95 reader."
    echo "  It must read #95 first and, on the first < 0 answer, set a top-level flag and use #40"
    echo "  from then on — a per-call retry floods mirshi's stderr and can step the clock backwards."; exit 1; }
done

# ── axis 2 — an AGNOS build actually EMITS syscall 95, and the #40 fallback ──────────────────
# 6.6.7: counted on a CYRIUS_DCE=1 build, as `movl $IMM, %eax` IMMEDIATELY followed by
# `syscall`. The plain build compiles every peer wrapper whether or not anything calls it, so
# sys_uptime_ms's body put a `movl $0x28` in the binary with clock_now_ns's fallback deleted —
# measured, the fallback-removal mutation passed an immediate count — and a bare `$0x28` also
# matches the constant 40 loaded for any other purpose. DCE NOPs the unreached wrappers, so
# what is left is what the clock actually reaches.
_nsys() { awk -v imm="$1" 'p ~ ("movl[ \t]+[$]" imm ", %eax") && $0 ~ /[ \t]syscall/ { c++ } { p = $0 } END { print c + 0 }' "$2"; }
cat > "$T/c.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/chrono.cyr"
fn main(): i64 { return clock_now_ns(); }
var e = main();
EOF
CYRIUS_DCE=1 CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/c.cyr" > "$T/c.out" 2>"$T/c.err" || {
  echo "FAIL agnos_monotonic_clock_rdtsc axis2: CYRIUS_TARGET_AGNOS build failed"
  grep -E '^error' "$T/c.err" | head -3 | sed 's/^/    /'; exit 1; }

if command -v llvm-objdump > /dev/null 2>&1; then
  # ⚠ DISASSEMBLE TO A FILE, THEN GREP — never `objdump | grep`. `grep -q` closes the pipe
  # on its first hit, objdump takes SIGPIPE, and under `-o pipefail` the whole pipeline is
  # 141 → this gate false-REDs with axis 3's message under `bash -eo pipefail` while passing
  # under /bin/sh. `grep -c` is no safer: it exits 1 on a count of 0, which aborts the
  # assignment under `set -e`. Both shapes are spelled out below. CHANGELOG [6.6.5].
  llvm-objdump -d --no-show-raw-insn "$T/c.out" > "$T/c.dis" 2>/dev/null || true
  N95=$(_nsys 0x5f "$T/c.dis")
  [ "$N95" -ge 1 ] || {
    echo "FAIL agnos_monotonic_clock_rdtsc axis2: the AGNOS build emits no syscall 95 (0x5f)."
    echo "  The uptime_us wrapper is not reaching the binary, so axis 1 proves nothing."; exit 1; }
  N40=$(_nsys 0x28 "$T/c.dis")
  [ "$N40" -ge 1 ] || {
    echo "FAIL agnos_monotonic_clock_rdtsc axis2: the AGNOS build emits no syscall 40 (0x28) —"
    echo "  clock_now_ns has lost its #40 fallback, so a refused-calibration boot has no clock."; exit 1; }
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
# The reachability counts (95 / 40) use a DCE build — see axis 2; the raw-228 ban below keeps
# the plain build, so a 228 anywhere in the file is caught, reached or not.
CYRIUS_DCE=1 CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/b.cyr" > "$T/bd.out" 2>/dev/null || {
  echo "FAIL agnos_monotonic_clock_rdtsc axis4: CYRIUS_DCE=1 AGNOS build of lib/bench.cyr failed"; exit 1; }

if command -v llvm-objdump > /dev/null 2>&1; then
  llvm-objdump -d --no-show-raw-insn "$T/b.out" > "$T/b.dis" 2>/dev/null || true
  llvm-objdump -d --no-show-raw-insn "$T/bd.out" > "$T/bd.dis" 2>/dev/null || true
  B95=$(_nsys 0x5f "$T/bd.dis")
  [ "$B95" -ge 1 ] || {
    echo "FAIL agnos_monotonic_clock_rdtsc axis4: the AGNOS bench build emits no syscall 95 (0x5f)."; exit 1; }
  B40=$(_nsys 0x28 "$T/bd.dis")
  [ "$B40" -ge 1 ] || {
    echo "FAIL agnos_monotonic_clock_rdtsc axis4: the AGNOS bench build emits no syscall 40 (0x28) —"
    echo "  now_ns has lost its #40 fallback."; exit 1; }
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

# ── axis 5 — 6.6.7 RUNTIME, under mirshi: a refused-calibration clock ADVANCES, latched ─────
# mirshi answers #95 with ENOSYS → -1 (and one stderr line per call), which is exactly the
# refused-calibration boot. The probe first checks that premise with a raw #95 read and exits
# 10 if #95 answers >= 0 — a mirshi that emulates #95 cannot reach the fallback, so the axis
# SKIPs BY NAME rather than passing vacuously. Then it waits 10 ms on clock_now_ms and 5 ms on
# bench's now_ns, each with a poll cap (3 / 4 = the clock stood still). Pre-6.6.7 both stuck,
# and printed one ENOSYS line per read; the latch allows at most one per clock (+1 for the
# probe's own premise read).
MIRSHI="$HOME/Repos/mirshi/build/mirshi"
RT="mirshi absent — runtime axis skipped"
if [ -x "$MIRSHI" ]; then
cat > "$T/rt.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/fnptr.cyr"
include "lib/chrono.cyr"
include "lib/bench.cyr"
fn main(): i64 {
    if (syscall(95) >= 0) { return 10; }
    var t0 = clock_now_ms();
    var p = 0;
    while (clock_now_ms() - t0 < 10) { p = p + 1; if (p > 20000) { return 3; } }
    if (p < 2) { return 5; }
    var b0 = now_ns();
    p = 0;
    while (now_ns() - b0 < 5000000) { p = p + 1; if (p > 20000) { return 4; } }
    if (p < 2) { return 6; }
    return 0;
}
var r = main();
sys_exit(r);
EOF
  CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/rt.cyr" > "$T/rt.out" 2>"$T/rt.cerr" || {
    echo "FAIL agnos_monotonic_clock_rdtsc axis5: CYRIUS_TARGET_AGNOS build of the runtime probe failed"
    grep -E '^error' "$T/rt.cerr" | head -3 | sed 's/^/    /'; exit 1; }
  chmod +x "$T/rt.out"
  ( cd "$T" && "$MIRSHI" ./rt.out > "$T/rt.so" 2> "$T/rt.se" ); rc=$?
  case "$rc" in
    0)
      NE=$(grep -c '#95' "$T/rt.se" || true)
      [ "$NE" -le 3 ] || {
        echo "FAIL agnos_monotonic_clock_rdtsc axis5: $NE mirshi '#95' stderr lines for two clock waits —"
        echo "  a clock is re-trying #95 on every read instead of latching to #40."; exit 1; }
      RT="mirshi: both clocks advance on a refused-calibration #95, $NE #95 calls total (latched)" ;;
    10) RT="SKIP axis5 by name: this mirshi answers #95 >= 0 (it emulates uptime_us), so the refused-calibration fallback is unreachable here" ;;
    3) echo "FAIL agnos_monotonic_clock_rdtsc axis5: clock_now_ms stood still under mirshi (#95 = -1) — 20000 polls, no 10 ms elapsed"; exit 1 ;;
    4) echo "FAIL agnos_monotonic_clock_rdtsc axis5: bench now_ns stood still under mirshi (#95 = -1) — 20000 polls, no 5 ms elapsed"; exit 1 ;;
    *) echo "FAIL agnos_monotonic_clock_rdtsc axis5: runtime probe under mirshi exited $rc"
       head -5 "$T/rt.se" | sed 's/^/    /'; exit 1 ;;
  esac
fi

echo "PASS agnos_monotonic_clock_rdtsc: $NR1 #95 readers in lib/ all test the -1 sentinel, #40 only as the fallback, clock_now_ns + bench now_ns latched · both AGNOS builds emit syscall 95 + 40 and no raw 228 · the Linux path still uses clock_gettime · $RT"
exit 0

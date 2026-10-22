#!/bin/sh
# agnos_sock_recv_bound.sh — v6.6.7. An agnos socket read waits for its DEADLINE, on a real
# clock, and says "timed out" (-11) rather than "EOF" (0); a stalled send is retried under the
# same deadline.
#
# ⛔ THE DEFECT. _agnos_sock_recv_block polls the non-blocking sock_recv#49 and pauses between
# polls. Its pause-count backstop (AGNOS_SOCK_RECV_MAX_SPINS, 6000) ran whether or not the RTC
# read, on the belief that a pause is one ~10 ms hlt. On agnos 1.57.x a pause first yields to any
# READY process and returns with NO hlt, so 6000 pauses took ~1 s on a guest with a few pollers
# (daimon's forwarded MCP calls answered 502) and ~7 s under mirshi's 1 ms pause — against a 30 s
# deadline. Sibling shapes: the RTC deadline was sampled once at entry, so an entry read of 0 made
# it "30" (already passed); a timeout returned 0, indistinguishable from EOF; and
# sock_set_recv_timeout ignored its argument on agnos. Axis 2 also pins the review fix: an RTC
# that armed the deadline and then read 0 for good was treated as "a glitch" for ever, so the
# wait never ended — a post-arm 0 now counts against the pause backstop like any unreadable read.
#
# Axes 1-4 run the peer against the scripted fake kernel (tests/fixtures/agnos_sctrace.cyr, a
# PTRACE_SYSEMU tracer: nothing executes, every answer is scripted), which makes each clock tier
# deterministic and instant. CHANGELOG [6.6.7]
# 6.7.16 — axis 5 is gone: it ran a REAL TCP exchange under mirshi, a BUILT binary from another
# project's checkout, and a language does not gate on other projects
# (docs/development/issues/archived/2026-10-19-gates-read-other-projects-checkouts.md). The live path
# under an agnos supervisor is agnos's own CI's check now; axes 1-4 carry every clock tier
# against the in-tree fake kernel and need nothing outside this checkout.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: agnos_sock_recv_bound: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$R" || exit 2
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL agnos_sock_recv_bound: no build/cycc"; exit 1; }
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}
"$CC" < tests/fixtures/agnos_sctrace.cyr > "$T/sct" 2>"$T/sct.err" && chmod +x "$T/sct" || {
    echo "FAIL agnos_sock_recv_bound: the fake-kernel tracer did not build"; head -3 "$T/sct.err"; exit 1; }

# One probe for every tier: connect (#47 answers conn 0), optionally set a per-socket timeout,
# read once, and report the result with syscall(999, 1, r). MAX_SPINS is lowered to 5 so that a
# backstop consulted outside tier 3 shows up as an early return.
probe() {  # $1 = extra statements before the read → $T/p.bin
    cat > "$T/p.cyr" <<EOF
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/tagged.cyr"
include "lib/net.cyr"
AGNOS_SOCK_RECV_MAX_SPINS = 5;
var fd_t, fd = tcp_socket();
sock_connect(fd, INADDR_LOOPBACK(), 8080);
var b[16];
$1
syscall(999, 1, sys_read(fd, &b, 16));
syscall(999, 2, sys_write(fd, "abcdefghij", 10));
sys_exit(0);
EOF
    CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/p.cyr" > "$T/p.bin" 2>"$T/p.err" || {
        echo "  FAIL: the agnos probe did not build"; grep -E '^error' "$T/p.err" | head -3; fails=$((fails + 1)); }
    chmod +x "$T/p.bin" 2>/dev/null
}
trace() { "$T/sct" "$T/p.bin" "$1" > "$T/run.log" 2>&1 || true; }
mark() { awk -v t="$1" '$1 == "sc" && $2 == 999 && $3 == t { print $4; exit }' "$T/run.log"; }
# count <nr> → syscalls <nr> between marker-less start and marker 1 (the read's own polls)
count() { awk -v n="$1" '$1 == "sc" && $2 == 999 { exit } $1 == "sc" && $2 == n { c++ } END { print c + 0 }' "$T/run.log"; }
count2() { awk -v n="$1" '$1 == "sc" && $2 == 999 && $3 == 1 { on = 1; next } on && $1 == "sc" && $2 == 999 { exit } on && $1 == "sc" && $2 == n { c++ } END { print c + 0 }' "$T/run.log"; }

# ── axis 1 — tier 1 (#95 reads): the MONOTONIC deadline decides, and a timeout is -11 ────────
echo "axis 1 — uptime_us#95 tier: 30 s default, per-socket override, -11 on timeout:"
probe ""
trace us
# the fake #95 advances 0.25 s per read: 30 s ⇒ the 121st read is the first at/after the deadline
check "a timed-out read returns -11 (EAGAIN), not 0 (EOF)" "-11" "$(mark 1)"
check "the 30 s default is timed by #95 (121 clock reads), not cut short by MAX_SPINS=5" "121" "$(count 95)"
check "the wait pauses between polls that found nothing (119 pauses; none after the last)" "119" "$(count 14)"
probe "sock_set_recv_timeout(fd, 2, 0);"
trace us
check "sock_set_recv_timeout(fd, 2, 0) bounds the read at 2 s (9 clock reads)" "-11 9" "$(mark 1) $(count 95)"

# ── axis 2 — tier 2 (#95 refused → the RTC): an entry 0 cannot poison the deadline ───────────
echo "axis 2 — time_unix#46 tier: armed on the first non-zero read, spins ignored while it reads:"
probe ""
trace rtc
# #46 answers 0, 0, then 1002, 1003, …: armed at 1002, fires at >= 1002 + 30 + 1 = 1033 (k = 33)
check "a read with #95 refused waits for the RTC, then returns -11" "-11" "$(mark 1)"
check "the RTC deadline is armed on the first NON-ZERO read (34 reads of #46)" "34" "$(count 46)"
check "MAX_SPINS (5) is not consulted while the RTC times the wait (> 5 pauses)" "yes" \
    "$([ "$(count 14)" -gt 5 ] && echo yes || echo no)"
probe ""
trace rtcdie
# #46: 0 (entry), 0, 1002, 1003, 1004 — armed at 1002 — then 0 for ever. The 0 reads after the
# arm count against MAX_SPINS (5): spins 1 (k=1), then 2..6 at k=5..9 ⇒ -11 on the 10th read.
# Pre-fix a post-arm 0 was "a glitch" and never counted, so the wait ran until the tracer's
# MAX_CALLS stop and no marker was ever written.
check "an RTC that arms the deadline and then reads 0 for ever still ends the wait (-11, 10 reads)" \
    "-11 10" "$(mark 1) $(count 46)"

# ── axis 3 — tier 3 (no clock at all): only here does the pause count bound the wait ─────────
echo "axis 3 — no-clock tier: the pause-count backstop, and only there:"
probe ""
trace spin
check "with #95 refused and #46 = 0 the read gives up after MAX_SPINS + 1 polls, -11" "-11 6" "$(mark 1) $(count 49)"

# ── axis 4 — EOF stays EOF; the send route retries a stalled #48 ─────────────────────────────
echo "axis 4 — EOF is 0; a 0 from sock_send#48 is retried under the deadline:"
probe ""
trace eof
check "sock_recv -1 (peer closed) still reads as EOF 0, at once" "0 1" "$(mark 1) $(count 49)"
trace send3
check "sys_write re-sends the remainder after short counts (3+3+3+1 = 10 in 4 calls)" "10 4" "$(mark 2) $(count2 48)"
trace send0
check "sys_write retries a 0 (no ACK progress) until the deadline, then -1 (nothing sent)" "-1" "$(mark 2)"
check "  …and it did retry, not return on the first 0" "yes" "$([ "$(count2 48)" -gt 1 ] && echo yes || echo no)"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: agnos_sock_recv_bound — socket waits are timed by a real clock and a timeout is -11"
    exit 0
fi
echo "FAIL: agnos_sock_recv_bound — $fails assertion(s) failed"
exit 1

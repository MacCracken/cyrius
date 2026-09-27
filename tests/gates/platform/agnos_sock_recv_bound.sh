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
# sock_set_recv_timeout ignored its argument on agnos.
#
# Axes 1-4 run the peer against the scripted fake kernel (tests/fixtures/agnos_sctrace.cyr, a
# PTRACE_SYSEMU tracer: nothing executes, every answer is scripted), which makes each clock tier
# deterministic and instant. Axis 5 runs a REAL TCP exchange under mirshi (skipped, and said
# so, when mirshi is absent): a Linux-target cyrius peer on an ephemeral port — never a fixed
# one, concurrent check.sh runs share the host — that answers after ~2 s. CHANGELOG [6.6.7]
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: agnos_sock_recv_bound: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
SRVPID=""
trap '[ -n "$SRVPID" ] && kill "$SRVPID" 2>/dev/null; rm -rf "$T"' EXIT
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
echo "axis 2 — time_unix#46 tier: armed on the first non-zero read, spins ignored:"
probe ""
trace rtc
# #46 answers 0, 0, then 1002, 1003, …: armed at 1002, fires at >= 1002 + 30 + 1 = 1033 (k = 33)
check "a read with #95 refused waits for the RTC, then returns -11" "-11" "$(mark 1)"
check "the RTC deadline is armed on the first NON-ZERO read (34 reads of #46)" "34" "$(count 46)"
check "MAX_SPINS (5) is not consulted while the RTC times the wait (> 5 pauses)" "yes" \
    "$([ "$(count 14)" -gt 5 ] && echo yes || echo no)"

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

# ── axis 5 — a REAL socket under mirshi: a 2 s answer arrives, it is not cut to EOF ──────────
echo "axis 5 — a real TCP exchange under mirshi (#95 absent there → the RTC tier):"
MIRSHI="${MIRSHI:-$HOME/Repos/mirshi/build/mirshi}"
if [ -x "$MIRSHI" ]; then
    # The peer: Linux-target cyrius, port 0, reports the port it got, answers "hello" after 2 s.
    cat > "$T/srv.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/tagged.cyr"
include "lib/net.cyr"
include "lib/fmt.cyr"
alloc_init();
var s_t, s = tcp_socket();
sock_bind(s, INADDR_LOOPBACK(), 0);
sock_listen(s, 1);
var sa[16];
var al[8];
store64(&al, 16);
sys_getsockname(s, &sa, &al);
var port = (load8(&sa + 2) << 8) | load8(&sa + 3);
var pb[32];
var pl = fmt_int_buf(port, &pb);
syscall(SYS_WRITE, 1, &pb, pl);
syscall(SYS_WRITE, 1, "\n", 1);
var c_t, c = sock_accept(s);
var ts[16];
store64(&ts, 2);
store64(&ts + 8, 0);
sys_nanosleep(&ts, 0);
sys_write(c, "hello", 5);
sys_nanosleep(&ts, 0);
sys_exit(0);
EOF
    cat > "$T/cli.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/tagged.cyr"
include "lib/args.cyr"
include "lib/net.cyr"
alloc_init();
args_init();
AGNOS_SOCK_RECV_MAX_SPINS = 300;
var p = argv(1);
var port = 0;
var i = 0;
while (load8(p + i) != 0) { port = port * 10 + load8(p + i) - 48; i = i + 1; }
var fd_t, fd = tcp_socket();
var cr_t, cr = sock_connect(fd, INADDR_LOOPBACK(), port);
var b[16];
var r = sys_read(fd, &b, 16);
if (r == 5) { sys_exit(42); }
sys_exit(10 + r);
EOF
    "$CC" < "$T/srv.cyr" > "$T/srv" 2>/dev/null && chmod +x "$T/srv"
    CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/cli.cyr" > "$T/cli" 2>/dev/null && chmod +x "$T/cli"
    "$T/srv" > "$T/port" 2>/dev/null &
    SRVPID=$!
    k=0; while [ ! -s "$T/port" ] && [ "$k" -lt 50 ]; do sleep 0.1; k=$((k + 1)); done
    PORT=$(head -1 "$T/port" 2>/dev/null)
    if [ -z "$PORT" ]; then
        check "the Linux TCP peer bound an ephemeral port" "a port" "none"
    else
        rc=0
        timeout 60 "$MIRSHI" --net-allow 127.0.0.1/32 "$T/cli" "$PORT" > /dev/null 2>&1 || rc=$?
        # 42 = the 5 bytes arrived; 10 = the read returned 0 (the pre-fix early "EOF").
        check "a read on a peer that answers after 2 s gets its 5 bytes (not an early EOF)" "42" "$rc"
    fi
    kill "$SRVPID" 2>/dev/null || true; SRVPID=""
else
    echo "  SKIP: mirshi not built at $MIRSHI — axes 1-4 carry the tiers; this is the live path"
fi

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: agnos_sock_recv_bound — socket waits are timed by a real clock and a timeout is -11"
    exit 0
fi
echo "FAIL: agnos_sock_recv_bound — $fails assertion(s) failed"
exit 1

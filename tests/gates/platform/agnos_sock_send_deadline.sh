#!/bin/sh
# agnos_sock_send_deadline.sh — 6.6.13. _agnos_sock_send_dl(conn, buf, n, tmo_us, rearm) bounds
# an agnos socket send by a deadline of the CALLER's choosing: rearm=0 makes `tmo_us` a bound on
# the WHOLE transfer, and rearm=1 (what sys_write uses, through _agnos_sock_send_all) keeps the
# 6.6.7 stall bound, re-armed by every call that moves bytes.
#
# ⛔ WHY. Native TLS writes had no deadline (the 2026-10-01 tls-native-no-deadline filing). On
# agnos a socket write is sock_send#48 retried by the peer under the socket's own STALL bound: a
# peer that ACKs a few bytes every few seconds re-arms it on each call, so no caller-chosen
# deadline could end the transfer. agnos has no poll(2) — fd_wait_ready declines there with -38 —
# so the bound has to live inside the peer's send loop. rearm=0 is that bound; sys_write must not
# change, which axis 3 pins.
#
# Every axis runs the peer against the scripted fake kernel (tests/fixtures/agnos_sctrace.cyr, a
# PTRACE_SYSEMU tracer: nothing executes, every answer is scripted). In `send3` #48 accepts
# min(3, len) bytes per call and in `send0` it accepts nothing; in both, uptime_us#95 advances
# 0.25 s per read, so a 1 s deadline armed at the first read (0.25 s) fires at the fifth (1.25 s).
#
# MUTATION LEDGER (each on the working tree, gate re-run, restored):
#   1. rearm=0 re-arms on progress like rearm=1   -> FAIL axis 1 (100 bytes sent, not 12)
#   2. rearm=0 skips the clock check after progress -> FAIL axis 1 (100 bytes sent, not 12)
#   3. _agnos_sock_send_all passes rearm=0         -> FAIL axis 3 (12 bytes sent, not 100)
#   4. rearm=0 ignores a 0 from #48 (no clock check) -> axis 2 never ends: no marker, FAIL
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: agnos_sock_send_deadline: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$R" || exit 2
CC=${CYCC:-"$R/build/cycc"}
[ -x "$CC" ] || { echo "FAIL agnos_sock_send_deadline: no compiler at $CC"; exit 1; }
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}
"$CC" < tests/fixtures/agnos_sctrace.cyr > "$T/sct" 2>"$T/sct.err" && chmod +x "$T/sct" || {
    echo "FAIL agnos_sock_send_deadline: the fake-kernel tracer did not build"; head -3 "$T/sct.err"; exit 1; }

# One probe: connect (#47 answers conn 0), then the statement under test, its result reported
# with syscall(999, 1, r). $1 = the send expression → $T/p.bin
probe() {
    cat > "$T/p.cyr" <<EOF
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/tagged.cyr"
include "lib/net.cyr"
var fd_t, fd = tcp_socket();
sock_connect(fd, INADDR_LOOPBACK(), 8080);
var big[128];
$1
syscall(999, 1, r);
sys_exit(0);
EOF
    CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/p.cyr" > "$T/p.bin" 2>"$T/p.err" || {
        echo "  FAIL: the agnos probe did not build"; grep -E '^error' "$T/p.err" | head -3; fails=$((fails + 1)); }
    chmod +x "$T/p.bin" 2>/dev/null
}
trace() { "$T/sct" "$T/p.bin" "$1" > "$T/run.log" 2>&1 || true; }
mark() { awk -v t="$1" '$1 == "sc" && $2 == 999 && $3 == t { print $4; exit }' "$T/run.log"; }
# calls of syscall <nr> before the first marker
count() { awk -v n="$1" '$1 == "sc" && $2 == 999 { exit } $1 == "sc" && $2 == n { c++ } END { print c + 0 }' "$T/run.log"; }

# ── axis 1 — rearm=0: the deadline bounds the whole transfer, progress or not ────────────────
echo "axis 1 — rearm=0 under a trickle (#48 takes 3 bytes a call): the deadline ends the transfer:"
probe "var r = _agnos_sock_send_dl(0, &big, 100, 1000000, 0);"
trace send3
# armed at 0.25 s (deadline 1.25 s); one clock read after each 3-byte call: 0.5, 0.75, 1.0, 1.25
check "a 100-byte send under a 1 s whole-transfer deadline stops at it: 12 bytes, partial count" "12" "$(mark 1)"
check "  …after 4 sock_send#48 calls" "4" "$(count 48)"
check "  …and 5 clock reads (the arm + one per call that moved bytes)" "5" "$(count 95)"

# ── axis 2 — rearm=0 with no progress at all: still the deadline, and -1 (nothing sent) ──────
echo "axis 2 — rearm=0 when #48 never makes progress:"
probe "var r = _agnos_sock_send_dl(0, &big, 100, 1000000, 0);"
trace send0
check "a send that never moves a byte returns -1 at the deadline" "-1" "$(mark 1)"
check "  …after 4 sock_send#48 calls (retried, not given up on the first 0)" "4" "$(count 48)"

# ── axis 3 — rearm=1 (sys_write's route) is the 6.6.7 STALL bound, unchanged ─────────────────
echo "axis 3 — sys_write keeps the stall bound: a trickle that keeps moving is not cut off:"
probe "sock_set_send_timeout(fd, 1, 0); var r = sys_write(fd, &big, 100);"
trace send3
check "sys_write of 100 bytes under a 1 s send timeout sends all 100 (each call re-arms it)" "100" "$(mark 1)"
check "  …in 34 sock_send#48 calls (33 × 3 + 1)" "34" "$(count 48)"
probe "var r = _agnos_sock_send_dl(0, &big, 100, 1000000, 1);"
trace send3
check "_agnos_sock_send_dl(rearm=1) is the same stall bound: all 100 bytes" "100" "$(mark 1)"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: agnos_sock_send_deadline — rearm=0 bounds the whole send; sys_write keeps its stall bound"
    exit 0
fi
echo "FAIL: agnos_sock_send_deadline — $fails assertion(s) failed"
exit 1

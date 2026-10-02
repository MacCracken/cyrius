#!/bin/sh
# agnos_tls_deadline.sh — 6.6.13 (CVE-61). On agnos, native TLS's per-connection deadline
# (tls_native_set_deadline) bounds a record read and a record write on a tagged socket fd by the
# CALLER's deadline — not by the socket's own 30 s receive timeout, and not by a send stall bound
# that every byte of progress re-arms — and with no deadline set both paths are unchanged.
#
# ⛔ WHY. Native TLS had no deadline at all (issue 2026-10-01-tls-native-no-deadline): a record
# read looped until the record was complete, so a peer dripping one byte inside the socket timeout
# held it for days. On Linux and macOS the bound is a poll before each read; agnos has no poll
# (fd_wait_ready declines with -38), so lib/tls_native_conn.cyr hands the time left to the peer's
# own deadline-taking calls instead: _agnos_sock_recv_block(conn, …, rem_us) for a read, and
# _agnos_sock_send_dl(conn, …, rem_us, rearm 0) for a write — a bound on the WHOLE transfer. Only
# a run against a kernel shows which call the TLS layer actually makes and when it stops, and
# there is no agnos host, so this gate is the agnos leg of tests/tcyr/crossos/tls_native_deadline_ccs.tcyr.
#
# Every axis runs an agnos probe against the scripted fake kernel (tests/fixtures/agnos_sctrace.cyr,
# a PTRACE_SYSEMU tracer: nothing executes, every answer is scripted). In `us`, `send0` and `send3`
# uptime_us#95 advances 0.25 s per read, so a deadline of +1 s set at the first read (0.25 s) is
# 1.25 s; sock_recv#49 answers 0 (nothing yet) in `us`, -1 (closed) in `eof`; sock_send#48 answers
# 0 (no progress) in `send0` and min(3, len) in `send3`.
#
# MUTATION LEDGER (each on the working tree, gate re-run, restored; all RED, 6.6.13):
#   1. _tn_io_read_full never takes the agnos tagged-fd path (the between-calls clock check only)
#        -> FAIL axis 1: -12 after 123 clock reads and 120 polls (the socket's 30 s default)
#   2. _tn_agnos_read_full maps every -11 to TLS_ERR_IO             -> FAIL axis 1: -12, not -22
#   3. _tn_agnos_write_all passes rearm=1                           -> FAIL axis 3: all 100 bytes, 34 calls
#   4. _tn_io_write_all drops its expired-deadline check            -> FAIL axis 3: 3 sock_send#48 calls
#      (axis 4 stays green: _tn_agnos_write_all's own time-left check also refuses an expired one)
#   5. _tn_agnos_read_full maps EOF (0) to TLS_ERR_TIMEOUT          -> FAIL axis 2: -22, not -12
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: agnos_tls_deadline: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$R" || exit 2
CC=${CYCC:-"$R/build/cycc"}
[ -x "$CC" ] || { echo "FAIL agnos_tls_deadline: no compiler at $CC"; exit 1; }
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}
"$CC" < tests/fixtures/agnos_sctrace.cyr > "$T/sct" 2>"$T/sct.err" && chmod +x "$T/sct" || {
    echo "FAIL agnos_tls_deadline: the fake-kernel tracer did not build"; head -3 "$T/sct.err"; exit 1; }

# One probe: connect (#47 answers conn 0), a zeroed ctx (`cx`, TLS_CTX_LEN bytes) whose deadline
# the statements set, then the statement under test, its result reported with syscall(999, 1, r).
# A marker syscall(999, 0, 0) precedes the statements, so the counts start there.
probe() {  # $1 = statements -> $T/p.bin
    cat > "$T/p.cyr" <<EOF
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/tagged.cyr"
include "lib/net.cyr"
include "lib/tls_native.cyr"
var fd_t, fd = tcp_socket();
sock_connect(fd, INADDR_LOOPBACK(), 8080);
var cx[576];
var big[128];
syscall(999, 0, 0);
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
# calls of syscall <nr> between marker 0 and marker 1
count() { awk -v n="$1" '$1 == "sc" && $2 == 999 && $3 == 0 { on = 1; next } on && $1 == "sc" && $2 == 999 { exit } on && $1 == "sc" && $2 == n { c++ } END { print c + 0 }' "$T/run.log"; }

[ "$(grep -c '^var TLS_CTX_LEN *= *576;' lib/tls_native_ctx.cyr)" = "1" ] || {
    echo "FAIL agnos_tls_deadline: TLS_CTX_LEN is no longer 576 — resize the probe's cx[] to match"; exit 1; }

DL1="tls_native_set_deadline(&cx, clock_now_ns() + 1000000000);"

# ── axis 1 — a record read under a +1 s deadline: TLS_ERR_TIMEOUT at the deadline ────────────
echo "axis 1 — a read with nothing arriving stops at the CALLER's deadline, not the 30 s socket default:"
probe "$DL1 var r = _tn_io_read_full(&cx, fd, &big, 16);"
trace us
# #95: 1 set (0.25 -> deadline 1.25) · 2 the loop's check (0.5: 0.75 s left) · 3 recv's arm (0.75 ->
# its own deadline 1.5) · 4, 5, 6 its polls (1.0, 1.25, 1.5 -> -11) · 7 the check that maps -11 (1.75)
check "_tn_io_read_full returns TLS_ERR_TIMEOUT (-22)" "-22" "$(mark 1)"
check "  …after 7 clock reads (the deadline), not the 30 s default's 120+" "7" "$(count 95)"
check "  …polling sock_recv#49 3 times" "3" "$(count 49)"
probe "var r = _tn_io_read_full(&cx, fd, &big, 16);"
trace us
check "with NO deadline the same read keeps the socket's 30 s default and answers TLS_ERR_IO (-12)" "-12" "$(mark 1)"
check "  …after the default's 121 clock reads (no TLS clock read at all)" "121" "$(count 95)"

# ── axis 2 — a closed peer under a deadline is EOF (TLS_ERR_IO), never a timeout ─────────────
echo "axis 2 — EOF under a deadline stays TLS_ERR_IO:"
probe "$DL1 var r = _tn_io_read_full(&cx, fd, &big, 16);"
trace eof
check "sock_recv#49 -1 (closed) under a +1 s deadline: TLS_ERR_IO (-12)" "-12" "$(mark 1)"

# ── axis 3 — a record write: the deadline bounds the WHOLE transfer (rearm 0) ─────────────────
echo "axis 3 — a write under a +1 s deadline stops at it, progress or not:"
# #95: 1 set (0.25 -> deadline 1.25) · 2 the expired check (0.5) · 3 the time left (0.75: 0.5 s) ·
# 4 send's arm (1.0 -> its own deadline 1.5) · 5 after #48 call 1 (1.25) · 6 after call 2 (1.5: over)
probe "$DL1 var r = _tn_io_write_all(&cx, fd, &big, 100);"
trace send0
check "no progress (#48 answers 0): TLS_ERR_TIMEOUT (-22)" "-22" "$(mark 1)"
check "  …after 2 sock_send#48 calls" "2" "$(count 48)"
probe "$DL1 var r = _tn_io_write_all(&cx, fd, &big, 100);"
trace send3
check "a trickle (#48 takes 3 bytes a call) cannot stretch it: TLS_ERR_TIMEOUT (-22)" "-22" "$(mark 1)"
check "  …after 2 sock_send#48 calls (6 of 100 bytes)" "2" "$(count 48)"
probe "sock_set_send_timeout(fd, 1, 0); var r = _tn_io_write_all(&cx, fd, &big, 100);"
trace send3
check "with NO deadline the write is sys_write's 6.6.7 stall bound, unchanged: all 100 bytes" "100" "$(mark 1)"
check "  …in 34 sock_send#48 calls (33 x 3 + 1)" "34" "$(count 48)"

# ── axis 4 — an expired deadline does no I/O at all ──────────────────────────────────────────
echo "axis 4 — an expired deadline fails before any socket call:"
probe "tls_native_set_deadline(&cx, 1); var r = _tn_io_write_all(&cx, fd, &big, 100);"
trace send3
check "a write: TLS_ERR_TIMEOUT (-22)" "-22" "$(mark 1)"
check "  …with no sock_send#48 call" "0" "$(count 48)"
probe "tls_native_set_deadline(&cx, 1); var r = _tn_io_read_full(&cx, fd, &big, 16);"
trace us
check "a read: TLS_ERR_TIMEOUT (-22)" "-22" "$(mark 1)"
check "  …with no sock_recv#49 call" "0" "$(count 49)"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: agnos_tls_deadline — the TLS deadline bounds agnos socket reads and writes; no deadline, no change"
    exit 0
fi
echo "FAIL: agnos_tls_deadline — $fails assertion(s) failed"
exit 1

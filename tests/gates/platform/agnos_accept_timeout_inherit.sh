#!/bin/sh
# agnos_accept_timeout_inherit.sh — v6.6.8. On agnos an ACCEPTED socket starts with its
# listener's recv/send timeouts, as it does on Linux (the kernel copies SO_RCVTIMEO/SO_SNDTIMEO
# into the accepted socket) — and an OUTBOUND connection that reuses the conn id never does.
#
# ⛔ THE DEFECT. net.cyr's agnos sock_accept wraps the accepted conn in a FRESH fd slot, whose
# per-socket timeout tables sys_close had cleared, so it fell back to the 30 s default whatever
# the listener was set to. Every in-ecosystem server set the timeout on the accepted fd itself
# (sit, bote, sandhi), so nothing broke — but a server ported from Linux that sets it once on
# the listener waited 30 s per stalled client on agnos. The adapter now remembers which listen
# slot each accepted conn_id came from (_agnos_accept_from, written by sys_sock_accept) and
# _agnos_sock_bind copies that slot's timeouts; sys_sock_connect drops the mark, and that clear
# is the load-bearing one this gate pins (the recycled-conn-id row below). sys_sock_close drops
# it too, but only defensively: every path to a bind goes through an accept or a connect first,
# so removing the close clear leaves this gate GREEN (measured by mutation, 6.6.10) and no
# behaviour gate can see it. (This line read "sys_sock_connect / sys_sock_close drop the mark"
# as though both were pinned. CHANGELOG [6.6.10])
#
# Runs against tests/fixtures/agnos_sctrace.cyr in its `us` / `send0` modes: #56 and #57 answer
# id 0, #47 answers conn 0 (the SAME conn id — the recycling case), uptime_us#95 advances
# 0.25 s per read. A 2 s deadline is therefore 9 clock reads and the 30 s default is 121.
# CHANGELOG [6.6.8]
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: agnos_accept_timeout_inherit: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$R" || exit 2
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL agnos_accept_timeout_inherit: no build/cycc"; exit 1; }
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}
"$CC" < tests/fixtures/agnos_sctrace.cyr > "$T/sct" 2>"$T/sct.err" && chmod +x "$T/sct" || {
    echo "FAIL agnos_accept_timeout_inherit: the fake-kernel tracer did not build"; head -3 "$T/sct.err"; exit 1; }

# probe <body> → $T/p.bin: a listener on 127.0.0.1:8080 (fd `lfd`), then <body>, then exit.
probe() {
    cat > "$T/p.cyr" <<EOF
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/tagged.cyr"
include "lib/net.cyr"
var lt, lfd = tcp_socket();
sock_bind(lfd, INADDR_LOOPBACK(), 8080);
sock_listen(lfd, 4);
var b[16];
$1
sys_exit(0);
EOF
    CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/p.cyr" > "$T/p.bin" 2>"$T/p.err" || {
        echo "  FAIL: the agnos probe did not build"; grep -E '^error' "$T/p.err" | head -3; fails=$((fails + 1)); }
    chmod +x "$T/p.bin" 2>/dev/null
}
trace() { "$T/sct" "$T/p.bin" "$1" > "$T/run.log" 2>&1 || true; }
mark() { awk -v t="$1" '$1 == "sc" && $2 == 999 && $3 == t { print $4; exit }' "$T/run.log"; }
# #95 reads between marker $1 and the next marker (marker 0 = from the start).
reads() { awk -v m="$1" 'BEGIN { on = (m == 0) } $1 == "sc" && $2 == 999 { if (on) exit; if ($3 == m) on = 1; next } on && $1 == "sc" && $2 == 95 { c++ } END { print c + 0 }' "$T/run.log"; }

echo "axis 1 — a recv timeout set on the LISTENER bounds a read on the accepted socket:"
probe 'sock_set_recv_timeout(lfd, 2, 0);
var ct, cfd = sock_accept(lfd);
syscall(999, 1, sys_read(cfd, &b, 16));'
trace us
check "the accepted read times out (-11) after the listener's 2 s (9 clock reads), not 30 s (121)" \
    "-11 9" "$(mark 1) $(reads 0)"

echo "axis 2 — a send timeout set on the LISTENER bounds a stalled send on the accepted socket:"
probe 'sock_set_send_timeout(lfd, 2, 0);
var ct, cfd = sock_accept(lfd);
syscall(999, 1, sys_write(cfd, "abc", 3));'
trace send0
check "the accepted send gives up (-1) after the listener's 2 s (9 clock reads), not 30 s" \
    "-1 9" "$(mark 1) $(reads 0)"

echo "axis 3 — a listener with no timeout leaves the accepted socket on the default:"
probe 'var ct, cfd = sock_accept(lfd);
syscall(999, 1, sys_read(cfd, &b, 16));'
trace us
check "the accepted read waits the 30 s default (121 clock reads)" "-11 121" "$(mark 1) $(reads 0)"

echo "axis 4 — an accept mark never reaches an OUTBOUND conn that reuses the conn id:"
# A raw sys_sock_accept caller marks conn 0 and never wraps it; the next sock_connect gets conn
# 0 back from #47. Without the clear in sys_sock_connect that client would inherit the 2 s.
probe 'sock_set_recv_timeout(lfd, 2, 0);
sys_sock_accept(0);
var ot, ofd = tcp_socket();
sock_connect(ofd, INADDR_LOOPBACK(), 9090);
syscall(999, 1, sys_read(ofd, &b, 16));'
trace us
check "the outbound read keeps the 30 s default (121 clock reads)" "-11 121" "$(mark 1) $(reads 0)"

echo "axis 5 — the accepted socket's OWN setting still wins, and the listener keeps its own:"
probe 'sock_set_recv_timeout(lfd, 2, 0);
var ct, cfd = sock_accept(lfd);
sock_set_recv_timeout(cfd, 1, 0);
syscall(999, 1, sys_read(cfd, &b, 16));
syscall(999, 2, _agnos_sock_tmo(&_agnos_sock_rcvto_us, lfd));'
trace us
check "a timeout set on the accepted fd (1 s = 5 clock reads) overrides the inherited one" \
    "-11 5" "$(mark 1) $(reads 0)"
check "the listener's own recv timeout is untouched (2000000 µs)" "2000000" "$(mark 2)"

if [ "$fails" -ne 0 ]; then echo "FAIL agnos_accept_timeout_inherit: $fails check(s)"; exit 1; fi
echo "PASS agnos_accept_timeout_inherit"
exit 0

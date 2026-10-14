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
# 6.7.11 — sock_send_dl#109 (agnos 1.57.13): each call is handed the TIME LEFT as its own ceiling,
# so one call can no longer outlast the deadline (a #48 call blocks up to ~8 s before answering 0:
# the overshoot the 2026-09-03 audit's CYRIUS-2026-0017 left "not covered"). In the dl* modes the
# fake kernel HAS #109; in every other mode #109 answers -1, i.e. a kernel before 1.57.13, so axes
# 1-3 are the #48 fallback and axis 6 pins the probe that chooses it. Axes 4-8 are the #109 kernel:
# the ceilings handed over (#109's a4, logged as the 4th register) are the time left, strictly
# decreasing and never 0 — 0 is #109's "NO ceiling", so passing it at time-up would be the
# unbounded call this exists to remove. This is the fake kernel only: cyrius has no agnos host, so
# no real-kernel leg runs here (agnos's own scripts/smoke/sock-send-dl-smoke.sh is the kernel side).
#
# MUTATION LEDGER (each on the working tree, gate re-run, restored):
#   1. rearm=0 re-arms on progress like rearm=1   -> FAIL axis 1 (100 bytes sent, not 12)
#   2. rearm=0 skips the clock check after progress -> FAIL axis 1 (100 bytes sent, not 12)
#   3. _agnos_sock_send_all passes rearm=0         -> FAIL axis 3 (12 bytes sent, not 100)
#   4. rearm=0 ignores a 0 from #48 (no clock check) -> axis 2 never ends: no marker, FAIL
# 6.7.11 (measured; assertions failed per axis):
#   5. time-up handed over as 0 (_agnos_dl_left_us answers 0, not -1, once tier 1 has passed)
#        -> 17 FAIL, axes 1 2 4 5 6 7 8: no loop stops at its deadline any more — the trickle
#           sends all 100 bytes, the later calls with a 0 (= no ceiling) a4
#   6. no probe — #109 assumed (_agnos_sdl_ok starts at 1)
#        -> 14 FAIL, axes 1 2 3 4 6 7: on an older kernel every write is -1 at its first call
#   7. "no #109" cached on a dead conn (_agnos_sdl_ok = 2 whatever #48 answered)
#        -> 2 FAIL, axis 7: the next write on a live conn goes to #48, its deadline unenforced
#   8. the 6.7.10 loop (#48 only, no ceiling handed over) -> 11 FAIL, axes 4 5 6 7 8
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

# The #109 calls before the first marker: `a3 a4` per call, space-joined — the probe is "0 0".
c109() { awk '$1 == "sc" && $2 == 999 { exit } $1 == "sc" && $2 == 109 { printf "%s%s:%s", s, $5, $6; s = " " }' "$T/run.log"; }
# The a4 (ceiling) of each DATA #109 call (len > 0) before the first marker.
ceil109() { awk '$1 == "sc" && $2 == 999 { exit } $1 == "sc" && $2 == 109 && $5 > 0 { printf "%s%s", s, $6; s = " " }' "$T/run.log"; }
# "yes" iff every data #109 ceiling is > 0 and strictly below the one before it.
decr109() { awk '$1 == "sc" && $2 == 999 { exit } $1 == "sc" && $2 == 109 && $5 > 0 { if ($6 <= 0 || (n && $6 >= p)) bad = 1; p = $6; n++ } END { print (n && !bad) ? "yes" : "no" }' "$T/run.log"; }

# ── axis 4 — a #109 kernel, rearm=0 under a trickle: each call's ceiling is the time left ─────
echo "axis 4 — rearm=0 on a kernel with sock_send_dl#109 (#109 takes 3 bytes a call):"
probe "var r = _agnos_sock_send_dl(0, &big, 100, 1000000, 0);"
trace dl3
# armed at 0.25 s (deadline 1.25 s); the first call gets the whole 1 s, each later one what the
# clock read after the call before it leaves: 0.75, 0.5, 0.25 s; at 1.25 s the loop stops.
check "a 100-byte send under a 1 s whole-transfer deadline stops at it: 12 bytes" "12" "$(mark 1)"
check "  …one #109 probe (len 0, ceiling 0), then 4 sends, all on #109" "0:0 100:1000000 97:750000 94:500000 91:250000" "$(c109)"
check "  …every ceiling > 0 and strictly decreasing — never 0, which #109 reads as NO ceiling" "yes" "$(decr109)"
check "  …no sock_send#48 at all, and 5 clock reads (unchanged)" "0 5" "$(count 48) $(count 95)"

# ── axis 5 — a #109 kernel with no progress at all: still bounded, never a 0 ceiling ──────────
echo "axis 5 — rearm=0 on a #109 kernel when nothing moves:"
probe "var r = _agnos_sock_send_dl(0, &big, 100, 1000000, 0);"
trace dl0
check "a send that never moves a byte returns -1 at the deadline" "-1" "$(mark 1)"
check "  …after 4 #109 sends with ceilings 1 s, 0.75, 0.5, 0.25 s — no call after expiry, none with 0" \
    "1000000 750000 500000 250000" "$(ceil109)"

# ── axis 6 — an older kernel: ONE probe, then sock_send#48 only ───────────────────────────────
echo "axis 6 — a kernel before 1.57.13 (#109 unknown, -1): one probe, then #48, still bounded:"
probe "var r = _agnos_sock_send_dl(0, &big, 100, 1000000, 0); var r2 = _agnos_sock_send_dl(0, &big, 9, 1000000, 0); r = r * 100 + r2;"
trace send3
check "two sends (100 bytes under 1 s, then 9): 12 bytes, then all 9" "1209" "$(mark 1)"
check "  …exactly one #109 — the probe (len 0, ceiling 0) — for both" "0:0" "$(c109)"
check "  …and the probe comes before the first #48" "109" \
    "$(awk '$1 == "sc" && ($2 == 109 || $2 == 48) { print $2; exit }' "$T/run.log")"
check "  …7 sock_send#48 calls (4 bounded by the deadline + 3 for the 9 bytes)" "7" "$(count 48)"
probe "var r = _agnos_sock_send_dl(0, &big, 100, 1000000, 0);"
trace send0
check "no progress on an older kernel: -1 at the deadline, 1 probe and 4 #48 calls" "-1 0:0 4" \
    "$(mark 1) $(c109) $(count 48)"

# ── axis 7 — a dead conn on a #109 kernel is NOT proof the number is unknown ──────────────────
echo "axis 7 — the probe failing on a dead conn does not cache 'no #109':"
probe "var r1 = _agnos_sock_send_dl(1, &big, 100, 1000000, 0); var r = _agnos_sock_send_dl(0, &big, 100, 1000000, 0); r = r1 * 1000 + r;"
trace dl3dead
check "the dead conn's send is -1; the live conn's then stops at its deadline with 12 bytes" "-988" "$(mark 1)"
check "  …dead conn: probe -1, #48 -1, so nothing is cached; live conn: probed again, then #109" \
    "0:0 0:0 100:1000000 97:750000 94:500000 91:250000" "$(c109)"
check "  …and the only sock_send#48 is the dead conn's fallback" "1" "$(count 48)"

# ── axis 8 — rearm=1 (sys_write) on a #109 kernel: the stall window is the ceiling ────────────
echo "axis 8 — sys_write on a #109 kernel: each call's ceiling is the stall window left:"
probe "sock_set_send_timeout(fd, 1, 0); var r = sys_write(fd, &big, 100);"
trace dl3
check "sys_write of 100 bytes under a 1 s send timeout sends all 100 (each call re-arms the window)" "100" "$(mark 1)"
check "  …in 34 #109 sends, every one with the whole 1 s window as its ceiling" "34 1000000" \
    "$(ceil109 | wc -w | tr -d ' ') $(ceil109 | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//')"
probe "sock_set_send_timeout(fd, 1, 0); var r = sys_write(fd, &big, 100);"
trace dl0
check "with no progress the window is not re-armed: ceilings 1 s, 0.75, 0.5, 0.25 s, then -1" \
    "-1 1000000 750000 500000 250000" "$(mark 1) $(ceil109)"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: agnos_sock_send_deadline — rearm=0 bounds the whole send; sys_write keeps its stall bound"
    exit 0
fi
echo "FAIL: agnos_sock_send_deadline — $fails assertion(s) failed"
exit 1

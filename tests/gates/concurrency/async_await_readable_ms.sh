#!/bin/sh
# Gate: `async_await_readable_ms` bounds the wait AND reports which way it ended.
#
# THE BUG (filed by sandhi/agnosai 2026-08-03, fixed v6.5.6). `async_await_readable(fd)`
# parked in `sys_epoll_wait` with a hardcoded `-1` timeout and `lib/async.cyr` exposed no
# timeout-carrying variant. A caller parked there was unwakeable by anything except data
# on `fd` — no flag, no deadline, no cancellation. Fine for a server whose only job is to
# serve; not fine for one that must also STOP. An idle cooperative accept loop blocked
# there forever, so a shutdown request set by another thread was never observed.
#
# `async_with_timeout(rt, handle, ms)` does NOT cover this: it races a spawned TASK
# against a deadline inside a runtime, whereas this is a bare fd-readiness wait taken on
# the accept path, outside any task, before a runtime is meaningfully in play.
#
# THE RETURN VALUE MATTERS AS MUCH AS THE TIMEOUT. The old helper returned a constant 0
# and discarded `sys_epoll_wait`'s result, so even with a timeout a caller could not tell
# "readable" from "timed out". Axes 2 and 3 pin BOTH directions — a variant that always
# returned 1, or always 0, would pass a one-sided test and be useless.
#
# sandhi 1.9.9 shipped a 100 ms polling workaround (`SANDHI_SERVER_STOP_POLL_MS`) taken
# only when a stop flag is configured; this primitive is what lets that go back to
# parking in epoll. The old name is kept as a wrapper returning 0, so no call site moves.
#
# SCOPE. Axes 1-6 run the Linux epoll body (`lib/async.cyr` is gated NOT-agnos AND NOT-win;
# cx never reaches it). ⛔ Until 6.6.19 that was the ONLY definition: on macOS and Windows
# async_await_readable was a no-op returning 0 at once, so sandhi's cooperative accept loop spun
# at 100 % CPU there and async_await_readable_ms did not exist. Axis 7 pins the peers: macOS
# (lib/async_macos.cyr, BSD poll) and Windows (lib/async_win.cyr, WSAPoll) define it over
# fd_wait_ready, agnos (lib/async_agnos.cyr) over the socket adapter's readiness stash, each
# legacy wrapper delegates with no bound, and a probe calling it builds for all three. They RUN in
# tests/tcyr/crossos/async_await_readable_ms.tcyr on ecb, ach and cass, and agnos under the fake
# kernel (tests/gates/platform/agnos_peer_fake_kernel.sh axis 8).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: async_await_readable_ms: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

PRE='include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/syscalls.cyr"
include "lib/chrono.cyr"
include "lib/result.cyr"
include "lib/tagged.cyr"
include "lib/fnptr.cyr"
include "lib/net.cyr"
include "lib/thread.cyr"
include "lib/async.cyr"'

# Build + run a probe body, echoing the exit code. 124 = timed out (hung).
runprobe() {
    printf '%s\n%s\n' "$PRE" "$1" > "$D/p.cyr"
    "$CC" < "$D/p.cyr" > "$D/p.bin" 2>/dev/null || true
    chmod +x "$D/p.bin" 2>/dev/null || true
    prc=0; timeout 10 "$D/p.bin" >/dev/null 2>&1 || prc=$?
    echo "$prc"
}

# ── AXIS 1: a bounded wait RETURNS on an idle fd instead of parking forever. This is the
# whole filing. 42 = returned; 124 = still parked.
echo "axis 1 — a bounded wait on an idle fd returns (42 = ok, 124 = still parks forever):"
runprobe 'fn main(): i64 {
    alloc_init();
    var pfd[16];
    sys_pipe(&pfd);
    var rfd = load32(&pfd);
    async_await_readable_ms(rfd, 200);
    return 42;
}
var r = main();
sys_exit_group(r);' > "$D/a1"
check "idle fd, 200 ms bound" 42 "$(cat "$D/a1")"

# ── AXIS 2: it reports 0 on timeout — NOT 1. A variant hardwired to 1 passes axis 1.
echo "axis 2 — an idle fd reports 0 (timed out), never 1:"
runprobe 'fn main(): i64 {
    alloc_init();
    var pfd[16];
    sys_pipe(&pfd);
    var rfd = load32(&pfd);
    if (async_await_readable_ms(rfd, 200) != 0) { return 7; }
    return 42;
}
var r = main();
sys_exit_group(r);' > "$D/a2"
check "timeout reports 0" 42 "$(cat "$D/a2")"

# ── AXIS 3: it reports 1 when the fd IS readable — NOT 0. The other half of axis 2; a
# variant hardwired to 0 (the OLD behaviour) passes axes 1 and 2 but fails here.
echo "axis 3 — a readable fd reports 1, never 0 (this is the old constant-0 mutation):"
runprobe 'fn main(): i64 {
    alloc_init();
    var pfd[16];
    sys_pipe(&pfd);
    var rfd = load32(&pfd);
    var wfd = load32(&pfd + 4);
    sys_write(wfd, "x", 1);
    if (async_await_readable_ms(rfd, 5000) != 1) { return 8; }
    return 42;
}
var r = main();
sys_exit_group(r);' > "$D/a3"
check "readable reports 1" 42 "$(cat "$D/a3")"

# ── AXIS 4: the motivating shape end-to-end — an idle listener whose loop must observe a
# stop flag set by another thread. This is sandhi's `run_async` accept loop in miniature.
echo "axis 4 — a cooperative accept loop observes an external stop flag:"
runprobe 'var STOP = 0;
fn _stopper(arg) { sleep_ms(250); STOP = 1; return 0; }
fn main(): i64 {
    alloc_init();
    var sfd_t, sfd = tcp_socket();
    sock_reuse(sfd);
    sock_bind(sfd, INADDR_LOOPBACK(), 0);
    sock_listen(sfd, 16);
    sock_set_nonblocking(sfd);
    thread_create(&_stopper, 0);
    while (1 == 1) {
        if (STOP != 0) { return 42; }
        async_await_readable_ms(sfd, 100);
    }
    return 9;
}
var r = main();
sys_exit_group(r);' > "$D/a4"
check "stop flag observed on an idle listener" 42 "$(cat "$D/a4")"

# ── AXIS 5: backward compatibility. The old name must survive with its old contract
# (always 0), because every existing call site relies on it.
echo "axis 5 — async_await_readable still exists and still returns 0:"
runprobe 'fn main(): i64 {
    alloc_init();
    var pfd[16];
    sys_pipe(&pfd);
    var rfd = load32(&pfd);
    var wfd = load32(&pfd + 4);
    sys_write(wfd, "y", 1);
    if (async_await_readable(rfd) != 0) { return 10; }
    return 42;
}
var r = main();
sys_exit_group(r);' > "$D/a5"
check "legacy wrapper returns 0" 42 "$(cat "$D/a5")"

# ── AXIS 6: structural. The `_ms` body must pass its parameter through, not a literal.
# Guards against someone "simplifying" the wrapper back into a hardcoded wait.
echo "axis 6 — the _ms body passes ms through to sys_epoll_wait:"
body=$(awk '/^fn async_await_readable_ms\(/,/^}/' lib/async.cyr)
n_par=$(printf '%s\n' "$body" | grep -cE 'sys_epoll_wait\(epfd, &revents, 1, ms\)' || true)
check "sys_epoll_wait(..., ms)" 1 "$n_par"
n_lit=$(printf '%s\n' "$body" | grep -cE 'sys_epoll_wait\(.*0 - 1\)' || true)
check "no hardcoded -1 left in _ms" 0 "$n_lit"

# ── AXIS 7 (6.6.19): the macOS and Windows peers define the bounded wait and delegate to it.
# Structural (each body read fn-line to closing brace) plus a build: a probe that calls it must
# compile for x86 Mach-O, PE and agnos with no undefined function — before 6.6.19 all refused it.
echo "axis 7 — macOS, Windows and agnos define async_await_readable_ms and the legacy wait delegates:"
_fnbody() { awk -v n="fn $2(" 'index($0, n) == 1 {p = 1} p {print} p && /^}/ {exit}' "$1"; }
for f in lib/async_macos.cyr lib/async_win.cyr; do
    b=$(_fnbody "$f" async_await_readable_ms)
    check "$f: async_await_readable_ms(fd, ms) passes ms to fd_wait_ready" 1 \
        "$(printf '%s\n' "$b" | grep -cE 'fd_wait_ready\(fd, 0, ms\)')"
    l=$(_fnbody "$f" async_await_readable)
    check "$f: async_await_readable delegates with no bound" 1 \
        "$(printf '%s\n' "$l" | grep -cE 'async_await_readable_ms\(fd, 0 - 1\)')"
done
# agnos (6.6.19): no poll at all — the socket adapter's readiness stash (_agnos_fd_ready), run
# under the scripted fake kernel by tests/gates/platform/agnos_peer_fake_kernel.sh axis 8.
b=$(_fnbody lib/async_agnos.cyr async_await_readable_ms)
check "lib/async_agnos.cyr: async_await_readable_ms probes _agnos_fd_ready(fd) before and after each sleep, and honours ms" "2 yes" \
    "$(printf '%s\n' "$b" | grep -cE 'if \(_agnos_fd_ready\(fd\) != 0\) \{ return 1; \}' || true) $(printf '%s\n' "$b" | grep -qE 'el >= ms' && echo yes || echo no)"
l=$(_fnbody lib/async_agnos.cyr async_await_readable)
check "lib/async_agnos.cyr: async_await_readable delegates with no bound" 1 \
    "$(printf '%s\n' "$l" | grep -cE 'async_await_readable_ms\(fd, 0 - 1\)' || true)"
printf '%s\n%s\n' "$PRE" 'fn main(): i64 { alloc_init(); return async_await_readable_ms(0 - 1, 0); }
var r = main();
sys_exit(r);' > "$D/x.cyr"
for tgt in CYRIUS_MACHO CYRIUS_TARGET_WIN CYRIUS_TARGET_AGNOS; do
    rc=0; env "$tgt=1" "$CC" < "$D/x.cyr" > "$D/x.bin" 2> "$D/x.err" || rc=$?
    nu=$(grep -c "undefined function 'async_await_readable_ms'" "$D/x.err" || true)
    check "$tgt=1: a probe calling async_await_readable_ms builds (rc, undefined)" "0 0" "$rc $nu"
done

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: async-await-readable-ms — wait is bounded and reports readable-vs-timeout"
    exit 0
fi
echo "FAIL: async-await-readable-ms — $fails assertion(s) failed"
exit 1

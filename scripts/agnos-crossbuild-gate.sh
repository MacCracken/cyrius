#!/bin/sh
# AGNOS cross-build gate (v6.0.87 — the arc-.32 gate). The `CYRIUS_TARGET_AGNOS`
# target landed .48-.49 + boot-to-prompt .55-.56, but nothing GUARDS agnos
# codegen from silent rot — the exact "found by ports" class that rotted the
# macOS port for 9 minors. This compiles a representative agnos-target program
# (+ agnoshi, the gating consumer, if checked out) and asserts a valid agnos-ABI
# ELF. Runs in CI (ci.yml) and standalone.
#
#   sh scripts/agnos-crossbuild-gate.sh
#
# Exit 0 = pass. A missing agnoshi checkout is FLAGGED (not silently skipped,
# per feedback_flag_missing_repos_dont_skip) but does not fail the gate — the
# always-present in-tree probe is the hard gate. Set CYRIUS_AGNOSHI_DIR to point
# at a non-default agnoshi checkout.
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[ -x build/cycc ] || { echo "ERROR: build/cycc missing (run bootstrap first)"; exit 1; }
[ -x build/cyrius ] || { echo "ERROR: build/cyrius missing"; exit 1; }

# A valid agnos ring-3 binary is a static x86-64 ELF (the agnos target emits a
# flat ET_EXEC over the agnos syscall ABI; no interpreter). Checked with only
# portable tools — the agnos CI container is minimal (no xxd/file/git), so we
# read the magic with grep -a (binary-safe) and the e_machine with od (guarded;
# skipped cleanly if od is unavailable rather than erroring under `set -e`).
assert_agnos_elf() {
    f="$1"
    [ -f "$f" ] || { echo "FAIL: $f not produced"; exit 1; }
    if command -v od >/dev/null 2>&1; then
        magic=$(od -An -tx1 -N4 "$f" 2>/dev/null | tr -d ' \n')      # 7f 45 4c 46
        [ "$magic" = "7f454c46" ] || { echo "FAIL: $f bad ELF magic ($magic)"; exit 1; }
        em=$(od -An -tx1 -j18 -N2 "$f" 2>/dev/null | tr -d ' \n')    # e_machine (LE)
        [ "$em" = "3e00" ] || { echo "FAIL: $f not x86-64 (e_machine=$em)"; exit 1; }
        et=$(od -An -tx1 -j16 -N2 "$f" 2>/dev/null | tr -d ' \n')    # e_type (LE)
        [ "$et" = "0200" ] || { echo "FAIL: $f not a static ET_EXEC (e_type=$et)"; exit 1; }
    else
        # Fallback when od is absent — only cat+grep (always present). The
        # \x7fELF magic guarantees the "ELF" substring near the start.
        grep -q 'ELF' "$f" 2>/dev/null || { echo "FAIL: $f has no ELF magic"; exit 1; }
    fi
}

# 1. In-tree probe — exercises the agnos peer surface that's bitten us before:
#    args (entry rsp capture), getenv (envp walk, v6.0.87), alloc, syscalls,
#    plus chrono's monotonic-clock + sleep binding (#40/#41, v6.2.6 — guards
#    the stale-stub regression that made every agnos timing/poll consumer
#    re-roll a direct-syscall workaround; issue 2026-06-14-chrono-agnos-...).
cat > /tmp/_agnos_gate.cyr <<'CYR'
include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/io.cyr"
include "lib/args.cyr"
include "lib/chrono.cyr"
fn main(): i64 {
    var h = getenv("HOME");          # envp walk on agnos (1.43.2 ABI §4.6)
    if (h == 0) { return 1; }
    var n = argc();                   # entry init-rsp capture
    if (n < 1) { return 2; }
    var t0 = clock_now_ms();          # uptime_ms #40 (monotonic, was fixed-0 pre-6.2.6)
    sleep_ms(1);                       # sleep_ms #41 (real sleep, was no-op pre-6.2.6)
    var us = sys_uptime_ms();          # raw wrapper (#40)
    var sl = sys_sleep_ms(0);          # raw wrapper (#41); ms<=0 guarded in chrono
    return load8(h) + (t0 - t0) + (us - us) + sl;
}
CYR
build/cyrius build --agnos /tmp/_agnos_gate.cyr /tmp/_agnos_gate.out >/dev/null 2>&1 \
    || { echo "FAIL: CYRIUS_TARGET_AGNOS probe did not compile (agnos codegen/peer regression)"; exit 1; }
assert_agnos_elf /tmp/_agnos_gate.out
echo "PASS: CYRIUS_TARGET_AGNOS probe (args + getenv envp) -> valid agnos ELF"

# 1b. Net / entropy / wall-clock / TLS peer (v6.2.3). Guards the agnos syscall
#     peer (#45-#55), the socket fd<->conn_id adapter in net.cyr, the threading
#     serial-fallback (tls_native pulls sigil -> thread.cyr; agnos has no clone),
#     and the chrono/tls_native wall-clock wiring. tls_native_connect exercises
#     the full TLS-over-agnos-TCP path (entropy #45, send/recv via the tagged
#     #48/#49 route, cert window via time_unix #46). Compile-only here — real
#     socket behavior is validated on agnos hardware, not in this gate.
cat > /tmp/_agnos_net_gate.cyr <<'CYR'
include "lib/net.cyr"
include "lib/http.cyr"
include "lib/tls_native.cyr"
fn main(): i64 {
    var buf = alloc(64);
    var gr = sys_getrandom(buf, 32, 0);             # #45 entropy (un-fail-closed)
    var t = clock_epoch_secs();                     # #46 wall clock
    var sr = tcp_socket();                           # agnos conn-slot reserve
    if (is_err_result(sr) == 1) { return 1; }
    var fd = payload(sr);
    sock_connect(fd, INADDR_LOOPBACK(), 443);        # #47 (+ NBO->ip4 bswap)
    var ctx = tls_native_new_client("h", 1);         # tls + threading fallback
    if (ctx == 0) { sock_close(fd); return 2; }
    tls_native_connect(ctx, fd);                     # send/recv via tagged #48/#49; #46 cert window
    sock_close(fd);                                  # #50
    var lid = sys_udp_bind(53);                      # #51
    var ao = alloc(16);
    sys_udp_send(0x08080808, (53 << 16) | 53, buf, 4);  # #52 (len rides a4=r10)
    sys_udp_recv(lid, buf, 64, ao);                  # #53 (addr_out rides a4=r10)
    sys_udp_unbind(lid);                             # #54
    var rtt = sys_icmp_echo(0x01010101);             # #55
    return gr + t + rtt;
}
CYR
build/cyrius build --agnos /tmp/_agnos_net_gate.cyr /tmp/_agnos_net_gate.out >/dev/null 2>&1 \
    || { echo "FAIL: CYRIUS_TARGET_AGNOS net/TLS peer did not compile (#45-#55 / net adapter / threading fallback regression)"; exit 1; }
assert_agnos_elf /tmp/_agnos_net_gate.out
echo "PASS: CYRIUS_TARGET_AGNOS net/entropy/clock/TLS peer (#45-#55) -> valid agnos ELF"

# 1c. async serial-peer + net multicast/sockopt guards (v6.2.7). Anti-rot for
#     the sandhi-filed cascade: lib/async.cyr's agnos peer-split (async_agnos.cyr
#     — agnos has no epoll_create1/fcntl/fork/wait4; async is server-path,
#     unused on the client) and lib/net.cyr's agnos guards on the sockopt/shutdown
#     fns (Linux SYS_SETSOCKOPT=54 / SYS_SHUTDOWN=48 silently mis-dispatch to
#     agnos #54=UDP_UNBIND / #48=SOCK_SEND) + the new IPv4 multicast helpers
#     (unsupported→-1 on agnos). If async loses its peer this fails to compile
#     (SYS_EPOLL_CREATE1 undefined). Compile-only. See issues
#     2026-06-15-cyrius-thread-agnos-clone-dispatch.md + -mdns-multicast-primitives.md.
cat > /tmp/_agnos_async_gate.cyr <<'CYR'
include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
include "lib/tagged.cyr"
include "lib/net.cyr"
include "lib/async.cyr"
fn _w(a): i64 { return a + 1; }
fn main(): i64 {
    var rt = async_new();                            # agnos serial peer (no epoll)
    if (rt == 0) { return 1; }
    async_spawn(rt, &_w, 41);
    async_run(rt);
    var tok = cancel_token_new();                     # shared (atomic-only) on agnos
    cancel_token_signal(tok);
    var c = cancel_token_check(tok);
    var sr = tcp_socket();
    if (is_err_result(sr) == 1) { return 2; }
    var fd = payload(sr);
    sock_reuse(fd);                                   # agnos no-op (was #54 mis-dispatch)
    sock_reuseport(fd);                               # agnos unsupported (-1)
    net_set_multicast_ttl(fd, 255);                   # agnos unsupported (-1)
    net_set_multicast_loop(fd, 0);
    net_join_multicast(fd, 0xFB0000E0, INADDR_ANY()); # 224.0.0.251; -1 on agnos
    net_drop_multicast(fd, 0xFB0000E0, INADDR_ANY());
    sock_shutdown(fd, 2);                             # agnos no-op (was #48 mis-dispatch)
    sock_close(fd);
    return c;
}
CYR
build/cyrius build --agnos /tmp/_agnos_async_gate.cyr /tmp/_agnos_async_gate.out >/dev/null 2>&1 \
    || { echo "FAIL: CYRIUS_TARGET_AGNOS async-peer / net-multicast-guard probe did not compile (async peer-split or net.cyr agnos guard regression)"; exit 1; }
assert_agnos_elf /tmp/_agnos_async_gate.out
echo "PASS: CYRIUS_TARGET_AGNOS async serial-peer + net multicast/sockopt guards -> valid agnos ELF"

# 1d. Server-socket peer (#56/#57, agnos 1.45.5/.6; v6.2.22). Guards the
#     listen<->fd adapter in lib/net.cyr + lib/syscalls_x86_64_agnos.cyr: the
#     server path (sock_bind stashes the port, sock_listen issues #56,
#     sock_accept issues #57 + wraps the accepted conn_id as a fresh tagged
#     #48/#49/#50 fd) that was fail-loud Err(1) before the kernel exposed
#     inbound TCP. Without this, the old "AGNOS Phase B" stubs could silently
#     rot back. Compile-only + an emit-inspect that the reachable sock_listen/
#     sock_accept lower to syscalls 56/57 (NOT a stub) — real accept/echo
#     behavior is validated on agnos hardware (QEMU tcp-listen-smoke), not here.
#     See 2026-06-18-agnos-server-socket-peer.md.
cat > /tmp/_agnos_server_gate.cyr <<'CYR'
include "lib/net.cyr"
fn main(): i64 {
    var sr = tcp_socket();                            # reserve a conn slot
    if (is_err_result(sr) == 1) { return 1; }
    var lfd = payload(sr);
    sock_reuse(lfd);                                  # agnos no-op
    var b = sock_bind(lfd, INADDR_ANY(), 8080);       # stash port
    if (is_err_result(b) == 1) { return 2; }
    var l = sock_listen(lfd, 8);                       # #56 sock_listen
    if (is_err_result(l) == 1) { return 3; }
    var ar = sock_accept(lfd);                         # #57 sock_accept (+ wrap conn)
    if (is_err_result(ar) == 1) { return 4; }
    var cfd = payload(ar);
    var buf = alloc(256);
    sock_recv(cfd, buf, 256);                          # #49 via tagged conn fd
    sock_send(cfd, buf, 4);                            # #48
    sock_close(cfd);                                   # #50 conn
    sock_close(lfd);                                   # #50 listen-reap
    return 0;
}
CYR
build/cyrius build --agnos /tmp/_agnos_server_gate.cyr /tmp/_agnos_server_gate.out >/dev/null 2>&1 \
    || { echo "FAIL: CYRIUS_TARGET_AGNOS server-socket peer did not compile (#56/#57 / listen-fd adapter regression)"; exit 1; }
assert_agnos_elf /tmp/_agnos_server_gate.out
if command -v objdump >/dev/null 2>&1; then
    sdis=$(objdump -d -M intel /tmp/_agnos_server_gate.out 2>/dev/null)
    echo "$sdis" | grep -qE 'mov +eax,0x38\b' || { echo "FAIL: server probe emits no syscall 56 (sock_listen rotted to a stub?)"; exit 1; }
    echo "$sdis" | grep -qE 'mov +eax,0x39\b' || { echo "FAIL: server probe emits no syscall 57 (sock_accept rotted to a stub?)"; exit 1; }
fi
echo "PASS: CYRIUS_TARGET_AGNOS server-socket peer (#56/#57) -> valid agnos ELF + emits sock_listen/sock_accept"

# 2. agnoshi — the gating consumer (agnsh is the first agnos userland program).
AGNOSHI="${CYRIUS_AGNOSHI_DIR:-$ROOT/../agnoshi}"
if [ -f "$AGNOSHI/src/agnsh.cyr" ]; then
    ( cd "$AGNOSHI" && CYRIUS_NO_WARN_PIN_DRIFT=1 CYRIUS_NO_WARN_SHADOW_LIB=1 \
        "$ROOT/build/cyrius" build --agnos src/agnsh.cyr /tmp/_agnsh_gate.out >/dev/null 2>&1 ) \
        || { echo "FAIL: agnoshi did not cross-build for CYRIUS_TARGET_AGNOS"; exit 1; }
    assert_agnos_elf /tmp/_agnsh_gate.out
    echo "PASS: agnoshi (agnsh) -> valid agnos ELF"
else
    echo "FLAG: agnoshi checkout not at $AGNOSHI (set CYRIUS_AGNOSHI_DIR) — consumer cross-build NOT verified"
fi

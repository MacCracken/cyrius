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

# 1e. Filesystem dir-listing peer (v6.2.23). Guards the agnos branch added to
#     lib/fs.cyr's dir_list/is_dir: the agnos sys_open (name, namelen, flags)
#     ABI + getdents #29 (3-arg) + the sovereign reclen-delimited dirent parse
#     (§4.2), replacing the Linux getdents64 #217 / dirent64 assumptions that
#     silently mis-ran on agnos (agnoshi `ls` + owl dep-fs). Without the branch
#     these rot back to Linux numbers on agnos. Compile-only + an emit-inspect
#     that the reachable getdents lowers to syscall 29 (0x1d), NOT the Linux
#     217 (0xd9). Real dir behavior is validated on agnos hardware (whirl
#     ext2 + agnoshi ls), not here. See 2026-06-18-stdlib-native-agnos-abi-fs.md.
cat > /tmp/_agnos_fs_gate.cyr <<'CYR'
include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
include "lib/fs.cyr"
fn main(): i64 {
    var p = str_from("/");
    var d = is_dir(p);                # agnos sys_open (name,namelen,flags) + getdents #29
    var entries = dir_list(p);         # agnos dirent §4.2 parse (reclen@0/namelen@3/name@8)
    return d + vec_len(entries) - d - vec_len(entries);
}
CYR
build/cyrius build --agnos /tmp/_agnos_fs_gate.cyr /tmp/_agnos_fs_gate.out >/dev/null 2>&1 \
    || { echo "FAIL: CYRIUS_TARGET_AGNOS fs dir-listing peer did not compile (fs.cyr agnos getdents/dirent branch regression)"; exit 1; }
assert_agnos_elf /tmp/_agnos_fs_gate.out
if command -v objdump >/dev/null 2>&1; then
    fdis=$(objdump -d -M intel /tmp/_agnos_fs_gate.out 2>/dev/null)
    echo "$fdis" | grep -qE 'mov +eax,0x1d\b' || { echo "FAIL: fs probe emits no syscall 29 (agnos getdents rotted to Linux #217?)"; exit 1; }
    # AO_DIRECTORY(0x800) MUST be the open flag: without it the agnos kernel
    # routes to ext2_open() which rejects a directory inode (-1), so dir_list
    # returns empty + is_dir returns 0 for every dir. This guards the exact
    # P0 the v6.2.23 adversarial review caught (open flags=0 was dead on agnos).
    echo "$fdis" | grep -qE 'mov +e[a-z]+,0x800\b' || { echo "FAIL: fs probe does not pass AO_DIRECTORY(0x800) to sys_open (dir opens dead on agnos)"; exit 1; }
fi
echo "PASS: CYRIUS_TARGET_AGNOS fs dir-listing peer (getdents #29 + AO_DIRECTORY open + dirent §4.2) -> valid agnos ELF"

# 1f. sync.cyr agnos mutex backend + sys_access stub (v6.2.35). Both guard the
#     SILENT-undefined class: cycc lowers a call to an undefined function to a
#     ud2 (SIGILL) stub + a *warning* (not an error) and still exits 0 — so a
#     plain "does it compile" check PASSES a regression here. Before v6.2.35,
#     sync.cyr had no CYRIUS_TARGET_AGNOS branch, so patra's unconditional
#     mutex_new() (patra_init) compiled green but trapped at runtime on agnos;
#     sigil's sys_access() probes were the same. This probe references all four
#     symbols and FAILS if cycc reports ANY of them undefined. See
#     2026-06-21-agnos-peer-m6-chain-syscalls.md (the no-op-mutex resolution).
cat > /tmp/_agnos_sync_gate.cyr <<'CYR'
include "lib/syscalls.cyr"
include "lib/atomic.cyr"
include "lib/alloc.cyr"
include "lib/sync.cyr"
fn main(): i64 {
    var m = mutex_new();              # sync.cyr agnos no-op mutex (was undefined pre-6.2.35)
    mutex_lock(m);
    mutex_unlock(m);
    var a = sys_access("/dev/tpmrm0", 0);  # agnos sys_access stub (fail-closed -1)
    return (m - m) + (a + 1);
}
CYR
build/cyrius build --agnos /tmp/_agnos_sync_gate.cyr /tmp/_agnos_sync_gate.out >/tmp/_agnos_sync_gate.log 2>&1 \
    || { echo "FAIL: CYRIUS_TARGET_AGNOS sync/access probe did not compile"; cat /tmp/_agnos_sync_gate.log; exit 1; }
if grep -q "undefined function 'mutex_\|undefined function 'sys_access" /tmp/_agnos_sync_gate.log; then
    echo "FAIL: agnos mutex/sys_access undefined (sync.cyr agnos branch or peer sys_access stub regressed -> ud2/SIGILL at runtime):"
    grep "undefined function" /tmp/_agnos_sync_gate.log
    exit 1
fi
assert_agnos_elf /tmp/_agnos_sync_gate.out
echo "PASS: CYRIUS_TARGET_AGNOS sync.cyr no-op mutex + sys_access stub -> defined (no ud2 stub) + valid agnos ELF"

# 1g. io.cyr file-lock helpers (v6.2.36). Same silent-undefined class as 1f:
#     file_lock/file_unlock/file_trylock/file_lock_shared/file_append_locked were
#     CYRIUS_TARGET_LINUX-only + raw syscall(73), so undefined -> ud2/SIGILL stubs
#     on agnos (descent's persist_init -> libro FileStore -> file_append_locked
#     trapped at BOOT). Now routed through xflock (#59) + xlseek SEEK_END (agnos
#     AO_APPEND is a kernel TODO). FAILS if cycc reports any helper undefined, and
#     asserts the agnos flock number #59 (0x3b) is emitted (a regression to raw
#     #73 or a dropped helper is caught). See 2026-06-21-agnos-io-flock-helpers.md.
cat > /tmp/_agnos_flock_gate.cyr <<'CYR'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
fn main(): i64 {
    var fd = file_open("/tmp/_agnos_flock_probe", O_WRONLY | O_CREAT, 0x1A4);
    file_lock(fd);            # xflock LOCK_EX -> agnos SYS_FLOCK #59
    file_lock_shared(fd);
    file_trylock(fd);
    file_unlock(fd);
    file_close(fd);
    return file_append_locked("/tmp/_agnos_flock_probe", "x", 1);  # open + lock + xlseek SEEK_END + write
}
CYR
build/cyrius build --agnos /tmp/_agnos_flock_gate.cyr /tmp/_agnos_flock_gate.out >/tmp/_agnos_flock_gate.log 2>&1 \
    || { echo "FAIL: CYRIUS_TARGET_AGNOS io flock probe did not compile"; cat /tmp/_agnos_flock_gate.log; exit 1; }
if grep -q "undefined function 'file_" /tmp/_agnos_flock_gate.log; then
    echo "FAIL: agnos io file-lock helper undefined (io.cyr lock group regressed to Linux-only -> ud2/SIGILL at runtime):"
    grep "undefined function" /tmp/_agnos_flock_gate.log
    exit 1
fi
assert_agnos_elf /tmp/_agnos_flock_gate.out
if command -v objdump >/dev/null 2>&1; then
    objdump -d -M intel /tmp/_agnos_flock_gate.out 2>/dev/null | grep -qE 'mov +e[a-z]+,0x3b\b' \
        || { echo "FAIL: io flock probe emits no SYS_FLOCK #59 (0x3b) — agnos flock rotted to raw Linux #73?"; exit 1; }
fi
echo "PASS: CYRIUS_TARGET_AGNOS io.cyr file-lock helpers (xflock #59 + xlseek SEEK_END) -> defined + valid agnos ELF"

# 1h. signal constants + sigset wrappers + net_config #61 + winsize #60 (v6.2.39).
#     SILENT-undefined class again: an undefined CONST (SIGHUP / SYS_NET_CONFIG /
#     SYS_WINSIZE) hard-errors, but an undefined sigset_*/sys_net_*/sys_winsize FN
#     lowers to a ud2 stub (exit-0 compile, SIGILL at runtime). This probe
#     references every new symbol and FAILS if cycc reports any undefined, pins the
#     kernel numbers (61=0x3d net_config, 60=0x3c winsize), and asserts the POSIX
#     signal numbering the agnos kernel hard-codes (SIGCHLD=17). NOTE winsize #60
#     == the Linux exit number — legitimate here; the `_agnos_emit_gate`
#     (programs/checks/ts.cyr) is peer-independent so it does NOT false-positive on
#     this. From 2026-06-23-agnos-net-config-syscall-wrapper.md +
#     2026-06-23-cyrius-agnos-peer-missing-signal-number-constants.md.
cat > /tmp/_agnos_signet_gate.cyr <<'CYR'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
fn main(): i64 {
    if (SYS_NET_CONFIG != 61) { return 1; }   # pin kernel numbers (undefined const hard-errors)
    if (SYS_WINSIZE != 60) { return 1; }
    if (SIGCHLD != 17) { return 1; }          # agnos kernel hard-codes POSIX numbering
    # signal mask: agnos kernel is bit-per-signal-NUMBER (1<<sig), NOT 1<<(sig-1)
    var m = sigset_new();
    sigset_add(m, SIGHUP);
    sigset_add(m, SIGCHLD);
    var pm = sys_sigprocmask(SIG_BLOCK, m, 0);
    var fd = sys_signalfd(0 - 1, m, SFD_NONBLOCK);
    var dns = sys_net_dns_server();
    var ip = sys_net_ip();
    var nm = sys_net_netmask();
    var gw = sys_net_gateway();
    var nc = sys_net_config(0);
    var ws = sys_winsize();
    return sigset_has(m, SIGCHLD) + pm + fd + dns + ip + nm + gw + nc + ws;
}
CYR
build/cyrius build --agnos /tmp/_agnos_signet_gate.cyr /tmp/_agnos_signet_gate.out >/tmp/_agnos_signet_gate.log 2>&1 \
    || { echo "FAIL: CYRIUS_TARGET_AGNOS signal/net_config/winsize probe did not compile (peer const/wrapper regression)"; cat /tmp/_agnos_signet_gate.log; exit 1; }
if grep -q "undefined function 'sys_net_\|undefined function 'sys_winsize\|undefined function 'sigset_" /tmp/_agnos_signet_gate.log; then
    echo "FAIL: agnos signal/net_config/winsize wrapper undefined (peer regressed to ud2/SIGILL stub at runtime):"
    grep "undefined function" /tmp/_agnos_signet_gate.log
    exit 1
fi
assert_agnos_elf /tmp/_agnos_signet_gate.out
if command -v objdump >/dev/null 2>&1; then
    ndis=$(objdump -d -M intel /tmp/_agnos_signet_gate.out 2>/dev/null)
    echo "$ndis" | grep -qE 'mov +eax,0x3d\b' || { echo "FAIL: probe emits no SYS_NET_CONFIG #61 (0x3d) — net_config rotted to a stub?"; exit 1; }
    echo "$ndis" | grep -qE 'mov +eax,0x3c\b' || { echo "FAIL: probe emits no SYS_WINSIZE #60 (0x3c) — winsize rotted to a stub?"; exit 1; }
fi
echo "PASS: CYRIUS_TARGET_AGNOS signal constants + sigset wrappers (1<<sig) + net_config #61 + winsize #60 -> defined + correct numbers + valid agnos ELF"

# 1i. GPU-compute band (#82-83, v6.4.63). Two legs — the second is SAFETY, not
#     portability. On Linux x86_64 #82 is rename(old,new) and #83 is mkdir(path,mode),
#     so a wrapper that resolved off-agnos would hand the caller's 8x8 matmul buffer
#     POINTERS to the kernel as filesystem PATHS. That is materially worse than the
#     #81/fchdir precedent (1e). The ONLY thing preventing it is that the band lives in
#     the standalone agnos peer, included behind `#ifdef CYRIUS_TARGET_AGNOS` in
#     lib/syscalls.cyr — i.e. the fns simply do not exist off-agnos. This gate pins BOTH
#     halves of that invariant so a future refactor (e.g. hoisting the band into a shared
#     syscalls file) cannot silently arm rename/mkdir.
#     From 2026-07-14-agnos-sys-gpu-dispatch-wrappers.md; consumer: gpumm 0.2.0.
cat > /tmp/_agnos_gpu_gate.cyr <<'CYR'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
fn main(): i64 {
    var a[512];
    var b[512];
    var c[512];
    var r = sys_gpu_dispatch(&a, &b, &c);          # 64xi32 8x8 A*B -> C
    var r2 = sys_gpu_dispatch_f64(&a, &b, &c);     # 64xf64 8x8, rosnet-bit-correct
    var r3 = sys_gpu_present();                    # #84 present (RMDIR on Linux — DESTRUCTIVE)
    var r4 = sys_gpu_fill(0x00FF0000);             # #85 CP-DMA fill (CREAT on Linux)
    var r5 = sys_shm_create_gpu(4096);             # #86 GPU-visible shm (LINK on Linux)
    var r6 = sys_gpu_blit_shm(1, 4194368, 0);      # #87 composite (UNLINK on Linux — DELETES)
    var r7 = sys_gpu_fill_rect(16711680, 4194368, 0);  # #88 rect fill (SYMLINK on Linux)
    var r8 = sys_gpu_caps(&a, 512);                # #89 bb geometry (READLINK on Linux — WRITES arg2)
    var r9 = sys_gpu_readback_shm(1, 4194368, 0);  # #90 capture bb→shm (CHMOD on Linux — setuid)
    var r10 = sys_gpu_blit_bb(0, 4194368, 65536);  # #91 bb→bb move (FCHMOD on Linux — (0,0)=fd 0 succeeds)
    var r11 = sys_gpu_shader_op(&a, 512);          # #92 shader desc array (CHOWN on Linux — arg1 read as a PATH)
    var r12 = sys_gpu_modeset_op(&a, 512);         # #93 modeset desc array (FCHOWN on Linux)
    return r + r2 + r3 + r4 + r5 + r6 + r7 + r8 + r9 + r10 + r11 + r12;
}
CYR
# Leg 1 — the band resolves + emits the right numbers on agnos.
build/cyrius build --agnos /tmp/_agnos_gpu_gate.cyr /tmp/_agnos_gpu_gate.out >/tmp/_agnos_gpu_gate.log 2>&1 \
    || { echo "FAIL: CYRIUS_TARGET_AGNOS gpu-dispatch probe did not compile (peer band regression)"; cat /tmp/_agnos_gpu_gate.log; exit 1; }
if grep -qE "undefined function 'sys_gpu_(dispatch|present|fill)" /tmp/_agnos_gpu_gate.log; then
    echo "FAIL: an agnos gpu_* wrapper is undefined (peer band regressed to ud2/SIGILL stub at runtime):"
    grep "undefined function" /tmp/_agnos_gpu_gate.log
    exit 1
fi
assert_agnos_elf /tmp/_agnos_gpu_gate.out
if command -v objdump >/dev/null 2>&1; then
    # PRECISE number check. A bare `grep 'mov eax,0x54'` is a PLACEBO here: 0x52-0x55 are
    # ASCII 'R','S','T','U', so a string-literal byte store (`mov eax,0x54; pop rcx;
    # mov BYTE PTR [rcx],al`) matches it and the check PASSES even when the syscall number
    # is wrong — proven by mutation (#84 -> 99 still reported PASS). The real syscall
    # number is the `mov eax,0xNN` immediately preceding each `syscall`, so extract that
    # set and assert membership. CHANGELOG [6.4.70].
    gnums=$(objdump -d -M intel /tmp/_agnos_gpu_gate.out 2>/dev/null | awk '
      /mov +eax,0x[0-9a-f]+/ { if (match($0, /0x[0-9a-f]+$/)) last=substr($0, RSTART, RLENGTH) }
      /\<syscall\>/ { if (last != "") { print last; last="" } }' | sort -u)
    for want in 0x52:82:SYS_GPU_DISPATCH 0x53:83:SYS_GPU_DISPATCH_F64 0x54:84:SYS_GPU_PRESENT 0x55:85:SYS_GPU_FILL \
                0x56:86:SYS_SHM_CREATE_GPU 0x57:87:SYS_GPU_BLIT_SHM 0x58:88:SYS_GPU_FILL_RECT 0x59:89:SYS_GPU_CAPS \
                0x5a:90:SYS_GPU_READBACK_SHM 0x5b:91:SYS_GPU_BLIT_BB \
                0x5c:92:SYS_GPU_SHADER_OP 0x5d:93:SYS_GPU_MODESET_OP; do
        hex=${want%%:*}; rest=${want#*:}; dec=${rest%%:*}; nm=${rest#*:}
        echo "$gnums" | grep -qw "$hex" \
            || { echo "FAIL: gpu probe emits no $nm #$dec ($hex) AT A SYSCALL SITE — band rotted to a stub or renumbered?"; exit 1; }
    done
fi
# Leg 2 — THE SAFETY LEG. The same probe must NOT build for Linux: the wrappers must be
# absent (hard "reachable undefined function" error, no binary), never resolved to #82/#83
# = rename/mkdir. `if` guards the intentional failure from `set -e`.
# Clear the target FIRST: this leg's own `exit 1` path skips any trailing cleanup, so a
# previous RED run would otherwise leave a binary here and pin the gate red forever.
rm -f /tmp/_agnos_gpu_linux.out
if build/cyrius build /tmp/_agnos_gpu_gate.cyr /tmp/_agnos_gpu_linux.out >/tmp/_agnos_gpu_linux.log 2>&1; then
    echo "FAIL: the gpu band RESOLVED on a non-agnos (Linux) build. On Linux x86_64 the band lands on"
    echo "      #82=rename #83=mkdir #84=RMDIR #85=creat #86=link #87=UNLINK #88=symlink #89=readlink"
    echo "      #90=CHMOD #91=FCHMOD #92=CHOWN #93=FCHOWN — so matmul pointers become paths, a NULLARY"
    echo "      present() DELETES A DIRECTORY at whatever stale rdi holds, gpu_blit_shm DELETES A FILE,"
    echo "      readlink WRITES into arg2, chmod can set setuid, gpu_blit_bb's (0,0) is fd 0 = stdin so"
    echo "      fchmod SUCCEEDS, and #92's arg1 is a real user VA the kernel resolves AS A PATH (chown)"
    echo "      — the most dangerous collision in the band."
    echo "      The band must live ONLY in the #ifdef CYRIUS_TARGET_AGNOS peer (lib/syscalls_x86_64_agnos.cyr)."
    exit 1
fi
if command -v objdump >/dev/null 2>&1 && [ -f /tmp/_agnos_gpu_linux.out ]; then
    objdump -d -M intel /tmp/_agnos_gpu_linux.out 2>/dev/null | grep -qE 'mov +eax,0x5[2-9a-d]\b' \
        && { echo "FAIL: a Linux build emitted syscall 82-93 (rename..fchown) for the gpu band"; exit 1; }
fi
rm -f /tmp/_agnos_gpu_linux.out
echo "PASS: CYRIUS_TARGET_AGNOS gpu band (#82-#93 correct numbers) + ABSENT on Linux (6 destructive rows gated)"

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

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
#    args (entry rsp capture), getenv (envp walk, v6.0.87), alloc, syscalls.
cat > /tmp/_agnos_gate.cyr <<'CYR'
include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/io.cyr"
include "lib/args.cyr"
fn main(): i64 {
    var h = getenv("HOME");          # envp walk on agnos (1.43.2 ABI §4.6)
    if (h == 0) { return 1; }
    var n = argc();                   # entry init-rsp capture
    if (n < 1) { return 2; }
    return load8(h);
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

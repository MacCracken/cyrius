#!/bin/sh
# agnos_negative_fd_not_socket.sh — 6.7.11. On agnos a NEGATIVE fd is not a tagged socket fd:
# sys_write / sys_read / sys_close of -1 never reach a socket slot, and sys_close(-1) is -1.
#
# ⛔ THE BUG (issues/archived/2026-10-12-agnos-negative-fd-taken-for-socket-slot-7.md, from darshana 1.3.0's
# 1.1.4 audit). The socket adapter in lib/syscalls_x86_64_agnos.cyr hands out tagged fds
# AGNOS_SOCK_TAG | slot (0x40000000 | 0..7) and recognised one with `fd & AGNOS_SOCK_TAG`. Every
# negative i64 has that bit set, so the -1 of a failed open was socket slot `-1 & 7 = 7`:
# sys_write(-1, …) sent the bytes to slot 7's peer, sys_read(-1, …) read from it, and
# sys_close(-1) — so file_close(-1) — cleared slot 7, sent FIN on its connection and returned 0.
# The fix: _agnos_is_sock_fd accepts exactly AGNOS_SOCK_TAG + 0..7, _agnos_fd_conn answers -1 for
# anything else, and sys_close answers -1 for fd < 0 before any table or kernel call (agnos's own
# answer for an fd that does not exist). CHANGELOG [6.7.11]
#
# 6.7.12 — the same class in the adapter's OTHER slot helpers
# (issues/archived/2026-10-13-agnos-net-arms-take-any-fd-for-a-socket-slot.md): _agnos_sock_bind,
# _agnos_listen_stash, _agnos_listen_start and _agnos_fd_listen indexed slot `fd & 7` for ANY fd,
# so lib/net.cyr's agnos sock_bind / sock_listen / sock_accept / sock_connect (and net_connect_nb)
# stashed into, listened on, accepted from or connected into an unrelated socket's slot with a
# success return. Each helper now answers -1 for an fd that is not a tagged socket fd, and each
# net.cyr arm refuses it first — Err(9) (EBADF) for a negative fd, Err(88) (ENOTSOCK) for any
# other, _NET_CONN_NB_ERR from net_connect_nb — before any table write or kernel call.
#
# AXES (x86_64 Linux only: the repro is an agnos ELF run directly on the host, which works
# because it issues no socket syscall and ends with the HOST's exit(2); anything else is a named
# SKIP, exit 77).
#   A1  the FILED repro, verbatim (its manifest's stdlib list as includes), built for agnos and
#       run: the five lines the filing expects — 0, 0, -1, -1, 12345.
#   A2  the 6.7.12 filed repro, verbatim, built for agnos and run: the four lines the filing
#       expects — 1 (sock_bind(-1) is an Err), 0 (slot 7 keeps port 0), -1 (_agnos_fd_listen(-1)),
#       4 (slot 7 keeps conn #4).
#   A3  each net.cyr arm's answer for a non-socket fd (-1, fd 1, AGNOS_SOCK_TAG + 9): sock_bind
#       9 / 88 / 88, _agnos_listen_stash(-1) -1 with slot 7's port still 0, sock_listen 9 / 88,
#       sock_accept 9 / 88, sock_connect 9 / 88, net_connect_nb(-1) -1. It runs on the host too:
#       the slot tables stay empty, so no arm reaches #56 / #57 (the host's clone / fork) even with
#       one guard removed; sock_connect's #47 without its guard is the host's recvmsg on the fd
#       0x7F000001, which answers EBADF.
#   M1-M3  ANTI-VACUOUS, built in: the same repro against a copy of lib/ with ONE of the three
#       fix lines put back (each mutant must differ from the tree in exactly that line) must NOT
#       print the expected lines — so A1 distinguishes each line of the fix, not just the whole.
#   M4-M10  the same for the 6.7.12 guards, one per guard line, each against A2 + A3: the
#       _agnos_fd_listen, _agnos_sock_bind and _agnos_listen_stash guards
#       (lib/syscalls_x86_64_agnos.cyr) and the sock_bind / sock_listen / sock_accept /
#       sock_connect guards (lib/net.cyr). _agnos_listen_start's and net_connect_nb's guards have
#       no host-observable answer (the arm's guard answers first; net_connect_nb's error is -1
#       either way): axis 13 of agnos_peer_fake_kernel.sh pins them by trace (no #56 / #47).
# The register-level rows (sys_write(-1) is write#1 with a1 = -1 and no #48, sys_read(-1) is
# read#5, sys_close(-1) issues no #50 and no #6, AGNOS_SOCK_TAG + 8 is not a socket, slot 7
# stays live) are axis 9 of agnos_peer_fake_kernel.sh; the 6.7.12 arms' traces are its axis 13.
#
# MUTATION LEDGER (6.7.11, each edit made to the tree's lib/syscalls_x86_64_agnos.cyr, gate re-run,
# restored — and the same three as M1-M3 on every run):
#   _agnos_is_sock_fd back to `(fd & AGNOS_SOCK_TAG) != 0`  -> A1 prints 1 1 4 -1 12345: RED
#   _agnos_fd_conn without its _agnos_is_sock_fd guard      -> A1 prints 0 0 4 -1 12345: RED
#   sys_close without its `fd < 0` answer                   -> A1 prints 0 0 -1 -14 12345: RED
#     (the host's syscall 6, lstat, on a -1 path; on agnos close#6 answers -1, so the line is
#     the same there — the early answer keeps the filed host repro meaningful and costs nothing)
# 6.7.12 (measured; M4-M10 re-run them every time): on the 6.7.11 lib/ A2 prints 0 8080 2 6 —
# the filing's "Actual" — and A3 0 0 0 0 8081 1 1 1 1 1 1 -1 (sock_bind Ok for all three, the
# stash taken; listen / accept / connect Err(1) only because those slots held no port, no
# listener, and the host's recvmsg stood in for #47; measured with slot 1's
# port cleared before sock_listen(AGNOS_SOCK_TAG + 9), which on 6.7.11 issues #56 for the port
# sock_bind(1) stashed — the host's clone, so never run there);
#   _agnos_fd_listen without its guard                     -> A2 1 0 2 4: RED
#   _agnos_sock_bind without its guard                     -> A2 1 0 -1 6: RED
#   _agnos_listen_stash without its guard                  -> A3's stash 0, slot 7 port 8081: RED
#   net.cyr's sock_bind / sock_listen / sock_accept / sock_connect guard removed
#                                                          -> A3 22 22 22 / 1 1 / 1 1 / 1 1: RED
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$R" || exit 2
CC=${CYCC:-"$R/build/cycc"}
G=agnos_negative_fd_not_socket
if [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != x86_64 ]; then
    echo "SKIP: $G — the agnos repro runs directly on an x86_64 Linux host only"; exit 77
fi
[ -x "$CC" ] || { echo "FAIL $G: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}

# The filed repro, VERBATIM (issue § Reproduction), behind its manifest's
# `stdlib = ["syscalls", "string", "fmt", "io"]` as includes.
cat > "$T/repro.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
fn show(label, v) { sys_write(1, label, strlen(label)); fmt_int(v); sys_write(1, "\n", 1); return 0; }
fn main() {
    _agnos_conn_init();
    show("_agnos_is_sock_fd(-1)       = ", _agnos_is_sock_fd(0 - 1));
    show("_agnos_is_sock_fd(-9)       = ", _agnos_is_sock_fd(0 - 9));
    store64(&_agnos_conn_tbl + 7 * 8, 5);            # slot 7 holds conn #4 (stored +1)
    show("_agnos_fd_conn(-1)          = ", _agnos_fd_conn(0 - 1));
    store64(&_agnos_conn_tbl + 7 * 8, 0);            # no kernel close below
    store64(&_agnos_sock_rcvto_us + 7 * 8, 12345);
    show("sys_close(-1) returns       = ", sys_close(0 - 1));
    show("slot 7 rcvto after close(-1) = ", load64(&_agnos_sock_rcvto_us + 7 * 8));
    return 0;
}
main();
#ifdef CYRIUS_TARGET_AGNOS
var HOST_SYS_EXIT = 60;   # the Linux host's exit(2)
#endif
syscall(HOST_SYS_EXIT, 0);
EOF

# $1 = the directory holding lib/ (the compile's cwd), $2 = the probe (default: A1's repro).
# Prints the probe's answers on one line, or a build / run failure.
run_repro() {
    rc=0
    (cd "$1" && CYRIUS_TARGET_AGNOS=1 "$CC" < "${2:-$T/repro.cyr}" > "$T/r.bin" 2> "$T/r.err") || rc=$?
    if [ "$rc" != 0 ] || [ ! -s "$T/r.bin" ]; then
        echo "build failed (rc $rc: $(grep -v 'unreachable fns' "$T/r.err" | head -2 | tr '\n' ' '))"; return
    fi
    chmod +x "$T/r.bin"
    rc=0
    out=$("$T/r.bin" 2>&1) || rc=$?
    [ "$rc" = 0 ] || { echo "rc=$rc $(printf '%s' "$out" | tr '\n' ' ')"; return; }
    printf '%s\n' "$out" | sed 's/.*= *//' | tr '\n' ' ' | sed 's/ $//'
}

WANT="0 0 -1 -1 12345"
echo "A1 — the filed repro on the tree's lib/:"
check "A1 a negative fd is no socket; _agnos_fd_conn(-1) -1; sys_close(-1) -1 with slot 7 untouched" \
    "$WANT" "$(run_repro "$R")"

# The 6.7.12 filed repro, VERBATIM (issues/archived/2026-10-13-agnos-net-arms-take-any-fd-for-a-socket-slot.md
# § Reproduction).
cat > "$T/repro2.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
include "lib/alloc.cyr"
include "lib/tagged.cyr"
include "lib/net.cyr"
fn show(label, v) { sys_write(1, label, strlen(label)); fmt_int(v); sys_write(1, "\n", 1); return 0; }
fn main() {
    _agnos_conn_init();
    var b_t, b = sock_bind(0 - 1, INADDR_ANY(), 8080);
    show("sock_bind(-1, 0.0.0.0, 8080) is_err       = ", is_err_result(b_t));
    show("slot 7 listen port after it               = ", load64(&_agnos_listen_port + 7 * 8));
    store64(&_agnos_listen_tbl + 7 * 8, 3);          # slot 7 is a LISTEN socket (listen id 2)
    show("_agnos_fd_listen(-1) (sock_accept's map)  = ", _agnos_fd_listen(0 - 1));
    store64(&_agnos_conn_tbl + 7 * 8, 5);            # slot 7 holds conn #4
    _agnos_sock_bind(0 - 1, 6);                      # sock_connect(-1)'s bind of a new conn #6
    show("slot 7 conn after _agnos_sock_bind(-1, 6) = ", load64(&_agnos_conn_tbl + 7 * 8) - 1);
    return 0;
}
main();
#ifdef CYRIUS_TARGET_AGNOS
var HOST_SYS_EXIT = 60;
#endif
syscall(HOST_SYS_EXIT, 0);
EOF

# A3: each net.cyr arm's answer for a non-socket fd. The slot tables stay EMPTY (no listener, no
# conn, slot 7's port reset at once), so no arm — even with one guard removed — reaches #56 / #57.
cat > "$T/arms.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/io.cyr"
include "lib/alloc.cyr"
include "lib/tagged.cyr"
include "lib/net.cyr"
fn show(v) { fmt_int(v); sys_write(1, "\n", 1); return 0; }
fn main() {
    _agnos_conn_init();
    var b1_t, b1 = sock_bind(0 - 1, INADDR_ANY(), 8080);
    show(err_code_of(b1_t, b1));
    var b2_t, b2 = sock_bind(1, INADDR_ANY(), 8080);
    show(err_code_of(b2_t, b2));
    var b3_t, b3 = sock_bind(AGNOS_SOCK_TAG + 9, INADDR_ANY(), 8080);
    show(err_code_of(b3_t, b3));
    show(_agnos_listen_stash(0 - 1, 8081, 0, 0));
    show(load64(&_agnos_listen_port + 7 * 8));
    store64(&_agnos_listen_port + 7 * 8, 0);
    var l1_t, l1 = sock_listen(0 - 1, 4);
    show(err_code_of(l1_t, l1));
    var l2_t, l2 = sock_listen(AGNOS_SOCK_TAG + 9, 4);
    show(err_code_of(l2_t, l2));
    var a1_t, a1 = sock_accept(0 - 1);
    show(err_code_of(a1_t, a1));
    var a2_t, a2 = sock_accept(1);
    show(err_code_of(a2_t, a2));
    var c1_t, c1 = sock_connect(0 - 1, INADDR_LOOPBACK(), 8080);
    show(err_code_of(c1_t, c1));
    var c2_t, c2 = sock_connect(AGNOS_SOCK_TAG + 9, INADDR_LOOPBACK(), 8080);
    show(err_code_of(c2_t, c2));
    show(net_connect_nb(0 - 1, INADDR_LOOPBACK(), 8080, 100));
    return 0;
}
main();
#ifdef CYRIUS_TARGET_AGNOS
var HOST_SYS_EXIT = 60;
#endif
syscall(HOST_SYS_EXIT, 0);
EOF

# $1 = lib/ dir → A2's four answers, then A3's twelve, on one line
run_612() { echo "$(run_repro "$1" "$T/repro2.cyr") | $(run_repro "$1" "$T/arms.cyr")"; }
A3OK="9 88 88 -1 0 9 88 9 88 9 88 -1"
echo "A2 + A3 — the 6.7.12 filed repro, and every agnos net arm's answer for a non-socket fd:"
check "A2 sock_bind(-1) Err, slot 7 port 0, _agnos_fd_listen(-1) -1, slot 7 keeps conn #4 | A3 Err(9) / Err(88) from every arm, no stash" \
    "1 0 -1 4 | $A3OK" "$(run_612 "$R")"

# ── M1-M10: one fix line put back per mutant ────────────────────────────────────────────────
P=lib/syscalls_x86_64_agnos.cyr
N=lib/net.cyr
mutant() {  # $1 = name, $2 = file, $3 = sed expression, $4 = the run → the mutant's answers
    rm -rf "$T/m" && mkdir "$T/m" && cp -R "$R/lib" "$T/m/lib"
    sed "$3" "$R/$2" > "$T/m/$2"
    n=$(diff "$R/$2" "$T/m/$2" | grep -c '^>' | tr -d ' ')
    if [ "$n" != 1 ]; then echo "the $1 mutation changed $n lines, not 1 (drifted)"; return; fi
    $4 "$T/m"
}
echo "M1-M3 — each fix line, put back alone, makes A1 RED:"
m1=$(mutant "is_sock_fd" "$P" 's/if (fd >= AGNOS_SOCK_TAG \&\& fd <= AGNOS_SOCK_TAG + 7) { return 1; }/if ((fd \& AGNOS_SOCK_TAG) != 0) { return 1; }/' run_repro)
check "M1 _agnos_is_sock_fd as a bit test: a negative fd is slot 7 again" "1 1 4 -1 12345" "$m1"
m2=$(mutant "fd_conn guard" "$P" '/^fn _agnos_fd_conn(fd): i64 {$/{n;s/^    if (_agnos_is_sock_fd(fd) == 0) { return 0 - 1; }$/    # (guard removed)/;}' run_repro)
check "M2 _agnos_fd_conn without its guard: -1 resolves to slot 7's conn" "0 0 4 -1 12345" "$m2"
m3=$(mutant "close fd<0" "$P" '/^fn sys_close(fd): i64 {$/{n;s/^    if (fd < 0) { return 0 - 1; }$/    # (fd < 0 answer removed)/;}' run_repro)
check "M3 sys_close without its fd < 0 answer: -1 reaches the kernel (the host's lstat -> -14)" \
    "0 0 -1 -14 12345" "$m3"
echo "M4-M10 — each 6.7.12 guard, removed alone, makes A2 or A3 RED:"
hg() {  # $1 = a helper's header line → the sed that drops its guard (the line after it)
    printf '/^%s$/{n;s/^    if (_agnos_is_sock_fd(fd) == 0) { return 0 - 1; }$/    # (guard removed)/;}' "$1"
}
ng() {  # $1 = a net.cyr fn's header line → the sed that disables the guard inside that fn only
    printf '/^%s$/,/^}$/s/^    if (_agnos_is_sock_fd(fd) == 0) {/    if (0 == 1) {/' "$1"
}
m4=$(mutant "fd_listen guard" "$P" "$(hg 'fn _agnos_fd_listen(fd): i64 {')" run_612)
check "M4 _agnos_fd_listen without its guard: -1 maps to slot 7's listener" "1 0 2 4 | $A3OK" "$m4"
m5=$(mutant "sock_bind guard" "$P" "$(hg 'fn _agnos_sock_bind(fd, conn_id): i64 {')" run_612)
check "M5 _agnos_sock_bind without its guard: -1 overwrites slot 7's conn" "1 0 -1 6 | $A3OK" "$m5"
m6=$(mutant "listen_stash guard" "$P" "$(hg 'fn _agnos_listen_stash(fd, port, cls, ip): i64 {')" run_612)
check "M6 _agnos_listen_stash without its guard: -1 stashes into slot 7" \
    "1 0 -1 4 | 9 88 88 0 8081 9 88 9 88 9 88 -1" "$m6"
m7=$(mutant "net sock_bind guard" "$N" "$(ng 'fn sock_bind(fd, addr, port) : Result {')" run_612)
check "M7 net.cyr sock_bind without its guard: the helper's refusal reads EINVAL, not EBADF / ENOTSOCK" \
    "1 0 -1 4 | 22 22 22 -1 0 9 88 9 88 9 88 -1" "$m7"
m8=$(mutant "net sock_listen guard" "$N" "$(ng 'fn sock_listen(fd, backlog) : Result {')" run_612)
check "M8 net.cyr sock_listen without its guard: Err(1), not EBADF / ENOTSOCK" \
    "1 0 -1 4 | 9 88 88 -1 0 1 1 9 88 9 88 -1" "$m8"
m9=$(mutant "net sock_accept guard" "$N" "$(ng 'fn sock_accept(fd) : Result {')" run_612)
check "M9 net.cyr sock_accept without its guard: Err(1), not EBADF / ENOTSOCK" \
    "1 0 -1 4 | 9 88 88 -1 0 9 88 1 1 9 88 -1" "$m9"
m10=$(mutant "net sock_connect guard" "$N" "$(ng 'fn sock_connect(fd, addr, port) : Result {')" run_612)
check "M10 net.cyr sock_connect without its guard: #47 is issued (the host's recvmsg -> Err(1))" \
    "1 0 -1 4 | 9 88 88 -1 0 9 88 9 88 1 1 -1" "$m10"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: $G — a negative fd is never taken for socket slot 7; sys_close(-1) is -1; no agnos net arm takes a non-socket fd (EBADF / ENOTSOCK, nothing touched)"
    exit 0
fi
echo "FAIL: $G — $fails assertion(s) failed"
exit 1

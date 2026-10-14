#!/bin/sh
# agnos_negative_fd_not_socket.sh — 6.7.11. On agnos a NEGATIVE fd is not a tagged socket fd:
# sys_write / sys_read / sys_close of -1 never reach a socket slot, and sys_close(-1) is -1.
#
# ⛔ THE BUG (issues/2026-10-12-agnos-negative-fd-taken-for-socket-slot-7.md, from darshana 1.3.0's
# 1.1.4 audit). The socket adapter in lib/syscalls_x86_64_agnos.cyr hands out tagged fds
# AGNOS_SOCK_TAG | slot (0x40000000 | 0..7) and recognised one with `fd & AGNOS_SOCK_TAG`. Every
# negative i64 has that bit set, so the -1 of a failed open was socket slot `-1 & 7 = 7`:
# sys_write(-1, …) sent the bytes to slot 7's peer, sys_read(-1, …) read from it, and
# sys_close(-1) — so file_close(-1) — cleared slot 7, sent FIN on its connection and returned 0.
# The fix: _agnos_is_sock_fd accepts exactly AGNOS_SOCK_TAG + 0..7, _agnos_fd_conn answers -1 for
# anything else, and sys_close answers -1 for fd < 0 before any table or kernel call (agnos's own
# answer for an fd that does not exist). CHANGELOG [6.7.11]
#
# AXES (x86_64 Linux only: the repro is an agnos ELF run directly on the host, which works
# because it issues no socket syscall and ends with the HOST's exit(2); anything else is a named
# SKIP, exit 77).
#   A1  the FILED repro, verbatim (its manifest's stdlib list as includes), built for agnos and
#       run: the five lines the filing expects — 0, 0, -1, -1, 12345.
#   M1-M3  ANTI-VACUOUS, built in: the same repro against a copy of lib/ with ONE of the three
#       fix lines put back (each mutant must differ from the tree in exactly that line) must NOT
#       print the expected lines — so A1 distinguishes each line of the fix, not just the whole.
# The register-level rows (sys_write(-1) is write#1 with a1 = -1 and no #48, sys_read(-1) is
# read#5, sys_close(-1) issues no #50 and no #6, AGNOS_SOCK_TAG + 8 is not a socket, slot 7
# stays live) are axis 9 of agnos_peer_fake_kernel.sh.
#
# MUTATION LEDGER (6.7.11, each edit made to the tree's lib/syscalls_x86_64_agnos.cyr, gate re-run,
# restored — and the same three as M1-M3 on every run):
#   _agnos_is_sock_fd back to `(fd & AGNOS_SOCK_TAG) != 0`  -> A1 prints 1 1 4 -1 12345: RED
#   _agnos_fd_conn without its _agnos_is_sock_fd guard      -> A1 prints 0 0 4 -1 12345: RED
#   sys_close without its `fd < 0` answer                   -> A1 prints 0 0 -1 -14 12345: RED
#     (the host's syscall 6, lstat, on a -1 path; on agnos close#6 answers -1, so the line is
#     the same there — the early answer keeps the filed host repro meaningful and costs nothing)
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

# $1 = the directory holding lib/ (the compile's cwd). Prints the repro's five answers on one
# line, or a build / run failure.
run_repro() {
    rc=0
    (cd "$1" && CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/repro.cyr" > "$T/r.bin" 2> "$T/r.err") || rc=$?
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

# ── M1-M3: one fix line put back per mutant ─────────────────────────────────────────────────
P=lib/syscalls_x86_64_agnos.cyr
mutant() {  # $1 = name, $2 = sed expression → prints the mutant's repro answers
    rm -rf "$T/m" && mkdir "$T/m" && cp -R "$R/lib" "$T/m/lib"
    sed "$2" "$R/$P" > "$T/m/$P"
    n=$(diff "$R/$P" "$T/m/$P" | grep -c '^>' | tr -d ' ')
    if [ "$n" != 1 ]; then echo "the $1 mutation changed $n lines, not 1 (drifted)"; return; fi
    run_repro "$T/m"
}
echo "M1-M3 — each fix line, put back alone, makes A1 RED:"
m1=$(mutant "is_sock_fd" 's/if (fd >= AGNOS_SOCK_TAG \&\& fd <= AGNOS_SOCK_TAG + 7) { return 1; }/if ((fd \& AGNOS_SOCK_TAG) != 0) { return 1; }/')
check "M1 _agnos_is_sock_fd as a bit test: a negative fd is slot 7 again" "1 1 4 -1 12345" "$m1"
m2=$(mutant "fd_conn guard" '/^fn _agnos_fd_conn(fd): i64 {$/{n;s/^    if (_agnos_is_sock_fd(fd) == 0) { return 0 - 1; }$/    # (guard removed)/;}')
check "M2 _agnos_fd_conn without its guard: -1 resolves to slot 7's conn" "0 0 4 -1 12345" "$m2"
m3=$(mutant "close fd<0" '/^fn sys_close(fd): i64 {$/{n;s/^    if (fd < 0) { return 0 - 1; }$/    # (fd < 0 answer removed)/;}')
check "M3 sys_close without its fd < 0 answer: -1 reaches the kernel (the host's lstat -> -14)" \
    "0 0 -1 -14 12345" "$m3"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: $G — a negative fd is never taken for socket slot 7; sys_close(-1) is -1"
    exit 0
fi
echo "FAIL: $G — $fails assertion(s) failed"
exit 1

#!/bin/sh
# agnos_peer_fake_kernel.sh — v6.6.7. RUNS agnos-target code against a scripted fake kernel
# and asserts on the exact registers each peer wrapper hands the kernel.
#
# ⛔ WHY RUN IT. Every defect this gate pins is in an ARGUMENT, and every one compiles clean:
#   - a4 (r10) left undefined on a short syscall — read#5/write#1 block or not by call history;
#   - a spawn length above 0xFFFF bleeding into #43's flag bits (a silent SPAWN_F_ARGV/CLEANFD);
#   - an exec_redirect src of 0x100+ becoming #62's ADD/CLEAR op;
#   - CH_ENDOW(-1), which since agnos 1.57.6 means DISARM and returns 0 — "the child gets fd 0".
# A source grep sees the call, not the value; a disassembly sees the value only when it is a
# literal. tests/fixtures/agnos_sctrace.cyr runs the agnos ELF under PTRACE_SYSEMU (nothing it
# asks for executes), logs `sc <nr> <a1> <a2> <a3> <a4>` per syscall and answers from a table,
# so the assertions read what the kernel would have been given. The probe reports its own
# results through an unused number (`syscall(999, tag, value)`), which the tracer logs too.
# CHANGELOG [6.6.7]
# 6.6.17: axis 5 the BSD socket verbs (sys_socket / bind / listen / connect / accept4) this peer
# lacked, axis 6 their arity against the Linux-common wrappers, axis 7 the agnos build of the CLI
# (cbt/cyrius.cyr), which stopped at ~110 arity errors. Measured on the 4a37046b peer: axis 5's
# probes do not build (5 undefined fns), axis 6 reads 0 for all five, axis 7 does not compile.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: agnos_peer_fake_kernel: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$R" || exit 2
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL agnos_peer_fake_kernel: no build/cycc"; exit 1; }
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}

"$CC" < tests/fixtures/agnos_sctrace.cyr > "$T/sct" 2>"$T/sct.err" && chmod +x "$T/sct" || {
    echo "FAIL agnos_peer_fake_kernel: the fake-kernel tracer did not build"; head -3 "$T/sct.err"; exit 1; }
# The tracer itself must work before any assertion means anything: a 1-syscall agnos program
# must log exactly its write and its exit.
printf 'include "lib/syscalls.cyr"\nsys_write(1, "x", 1);\nsys_exit(7);\n' > "$T/h.cyr"
CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/h.cyr" > "$T/h.bin" 2>/dev/null && chmod +x "$T/h.bin"
"$T/sct" "$T/h.bin" plain > "$T/h.log" 2>&1
check "the fake kernel traces a trivial agnos program (write, then exit 7)" "1 0 7" \
    "$(awk '$1 == "sc" && $2 == 1 { w++ } $1 == "sc" && $2 == 0 { e++ } $1 == "exit" { c = $2 } END { print w + 0, (e == 1 ? 0 : 9), c + 0 }' "$T/h.log")"

run() {  # $1 = probe body file, $2 = mode → $T/run.log
    printf 'include "lib/syscalls.cyr"\ninclude "lib/string.cyr"\n' > "$T/p.cyr"
    cat "$1" >> "$T/p.cyr"
    CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/p.cyr" > "$T/p.bin" 2>"$T/p.err" || {
        echo "  FAIL: the agnos probe did not build"; grep -E '^error' "$T/p.err" | head -3; fails=$((fails + 1)); return; }
    chmod +x "$T/p.bin"
    "$T/sct" "$T/p.bin" "$2" > "$T/run.log" 2>&1
}
# mark <tag> → the value the probe reported with syscall(999, tag, value)
mark() { awk -v t="$1" '$1 == "sc" && $2 == 999 && $3 == t { print $4; exit }' "$T/run.log"; }
# after <tag> <nr> → "a1 a2 a3 a4" of the first syscall <nr> after marker <tag>
after() { awk -v t="$1" -v n="$2" '$1 == "sc" && $2 == 999 && $3 == t { on = 1; next } on && $1 == "sc" && $2 == n { print $3, $4, $5, $6; exit }' "$T/run.log"; }
# between <tag> <nr> → how many syscalls <nr> occur between marker <tag> and the next marker
between() { awk -v t="$1" -v n="$2" '$1 == "sc" && $2 == 999 { if (on) exit; if ($3 == t) { on = 1; next } } on && $1 == "sc" && $2 == n { c++ } END { print c + 0 }' "$T/run.log"; }

# ── axis 1 — a4 is DEFINED at runtime, even straight after a 7-arg call left r10 = 5 ─────────
echo "axis 1 — the kernel sees a4 = 0 on short syscalls (no r10 residue):"
cat > "$T/a1.cyr" <<'EOF'
fn f7(a, b, c, d, e, f, g): i64 { return a + g; }
var b[16];
f7(1, 2, 3, 4, 5, 6, 5);
syscall(999, 1, 0);
println("p");
f7(1, 2, 3, 4, 5, 6, 5);
syscall(999, 2, 0);
sys_read(0, &b, 1);
f7(1, 2, 3, 4, 5, 6, 5);
syscall(999, 3, 0);
sys_write(1, "w", 1);
syscall(999, 4, 0);
sys_read_nb(0, &b, 1);
sys_exit(0);
EOF
run "$T/a1.cyr" plain
check "println's raw 3-arg write#1 carries a4 = 0" "0" "$(after 1 1 | awk '{ print $4 }')"
check "sys_read's read#5 carries a4 = 0 (blocking)" "0" "$(after 2 5 | awk '{ print $4 }')"
check "sys_write's write#1 carries a4 = 0 (blocking)" "0" "$(after 3 1 | awk '{ print $4 }')"
check "sys_read_nb's read#5 carries a4 = 1 (O_NONBLOCK)" "1" "$(after 4 5 | awk '{ print $4 }')"

# ── axis 2 — the 1.57.6 spawn / redirect / endow surface packs exactly what the kernel decodes
echo "axis 2 — spawn_path#43, exec_redirect#62 and CH_ENDOW#97 arguments (agnos 1.57.6):"
cat > "$T/a2.cyr" <<'EOF'
var blob = "/bin/x\0a b\0";
syscall(999, 10, 0);
sys_spawn_argv(blob, 11, 0, 0, SPAWN_F_CLEANFD);
syscall(999, 11, 0);
sys_spawn_argv(blob, 11, 0, 0, 0);
syscall(999, 12, 0);
sys_spawn_argv(blob, 0x20005, 0, 0, 0);
syscall(999, 13, 0);
sys_spawn_argv(blob, 11, 0, 0, SPAWN_F_ARGV);
syscall(999, 14, 0);
sys_spawn_path("/bin/x", 0x10005);
syscall(999, 15, 0);
sys_spawn_path("/bin/x", 6);
syscall(999, 16, 0);
sys_spawn_path_env("/bin/x", 0x30006, "K=V\0", 4);
syscall(999, 20, sys_exec_redirect(0x105, 3));
syscall(999, 21, 0);
sys_exec_redirect(1, 3);
syscall(999, 22, 0);
sys_exec_redirect_add(2, 1);
syscall(999, 23, sys_exec_redirect_add(0x101, 1));
syscall(999, 24, 0);
sys_exec_redirect_clear();
syscall(999, 30, sys_chan_endow(0 - 1));
syscall(999, 31, 0);
sys_chan_endow(3);
syscall(999, 32, 0);
sys_chan_endow_stdio(3);
syscall(999, 33, 0);
sys_chan_endow_disarm();
syscall(999, 34, 0);
syscall(999, 40, SPAWN_E_OTHER * 1000000 + SPAWN_E_NOPROC * 100000 + SPAWN_E_NOMEM * 10000 + SPAWN_E_NOENT * 1000 + SPAWN_E_NOEXEC * 100 + SPAWN_E_ARGS * 10 + SPAWN_E_LIMIT);
sys_exit(0);
EOF
run "$T/a2.cyr" plain
check "sys_spawn_argv(CLEANFD) packs len | ARGV | CLEANFD, env (0, 0)" "196619 0 0" "$(after 10 43 | cut -d' ' -f2-)"
check "sys_spawn_argv(0) packs len | ARGV" "65547" "$(after 11 43 | awk '{ print $2 }')"
check "an oversized argv len never reaches the flag bits (refused via bit 18)" "262144" "$(after 12 43 | awk '{ print $2 }')"
check "flags = SPAWN_F_ARGV is refused (only 0 / CLEANFD are callers' flags)" "262144" "$(after 13 43 | awk '{ print $2 }')"
check "sys_spawn_path(len 0x10005) is refused, not an ARGV spawn" "262144" "$(after 14 43 | awk '{ print $2 }')"
check "sys_spawn_path passes env (0, 0)" "6 0 0" "$(after 15 43 | cut -d' ' -f2-)"
check "sys_spawn_path_env(len 0x30006) is refused" "262144" "$(after 16 43 | awk '{ print $2 }')"
check "sys_exec_redirect(src 0x105) is refused before the kernel" "-1 0" "$(mark 20) $(between 16 62)"
check "sys_exec_redirect(1, 3) is op 0" "1 3" "$(after 21 62 | cut -d' ' -f1-2)"
check "sys_exec_redirect_add(2, 1) is REDIR_ADD | 2" "258 1" "$(after 22 62 | cut -d' ' -f1-2)"
check "sys_exec_redirect_add(src 0x101) is refused" "-1" "$(mark 23)"
check "sys_exec_redirect_clear is exactly (0x200, 0)" "512 0" "$(after 24 62 | cut -d' ' -f1-2)"
check "sys_chan_endow(-1) is refused (-CH_E_BADFD), never a silent disarm" "-5 0" "$(mark 30) $(between 24 97)"
check "sys_chan_endow(3) passes a4 = 0" "5 3 0 0" "$(after 31 97)"
check "sys_chan_endow_stdio(3) passes a4 = CH_ENDOW_STDIO" "5 3 0 1000" "$(after 32 97)"
check "sys_chan_endow_disarm is CH_ENDOW(-1)" "5 -1 0 0" "$(after 33 97)"
check "SPAWN_E_OTHER..SPAWN_E_LIMIT are 1..7 (kernel syscall.cyr:137-146)" "1234567" "$(mark 40)"

# ── axis 3 — the 1.57.7 wait / kill / limits / peer-address surface ──────────────────────────
echo "axis 3 — waitpid WAIT_BLOCK, KILL_TREE, spawn_limits, W* and getpeername (agnos 1.57.7):"
cat > "$T/a3.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/tagged.cyr"
include "lib/net.cyr"
syscall(999, 50, sys_waitpid_block(0 - 1));
syscall(999, 51, sys_waitpid_block(255));
syscall(999, 52, 0);
sys_waitpid_block(3);
syscall(999, 53, 0);
sys_waitpid_any_block();
syscall(999, 54, 0);
sys_kill_tree(5, 9);
syscall(999, 55, sys_kill_tree(5, 0x109));
syscall(999, 56, 0);
sys_spawn_limits(512, 1000);
syscall(999, 57, WIFEXITED(265) * 1000 + WIFSIGNALED(265) * 100 + WTERMSIG(265));
syscall(999, 58, WIFEXITED(0x2A) * 1000 + WIFSIGNALED(0x2A) * 100 + WEXITSTATUS(0x12A));
syscall(999, 59, WIFSIGNALED(280) * 100 + WTERMSIG(280));
var fd_t, fd = tcp_socket();
sock_connect(fd, INADDR_LOOPBACK(), 8080);
var sa[16];
var alen[8];
store64(&alen, 16);
syscall(999, 60, 0);
syscall(999, 61, sys_getpeername(fd, &sa, &alen));
syscall(999, 62, load64(&sa));
syscall(999, 63, load64(&alen));
var sb[16];
store64(&sb, 0);
store64(&sb + 8, 0);
store64(&alen, 4);
sys_getpeername(fd, &sb, &alen);
syscall(999, 64, load64(&sb));
syscall(999, 65, sys_getsockname(fd, &sa, &alen));
syscall(999, 66, sys_getpeername(1, &sa, &alen));
syscall(999, 67, SIGXCPU * 1000 + FLOCK_E_TABLE_FULL * 100 + PROCLIST_ZOMBIE);
sys_exit(0);
EOF
run "$T/a3.cyr" plain
check "sys_waitpid_block(-1) is refused — 0x100|-1 is the reaping wait-any POLL" "-1 0" "$(mark 50) $(between 50 4)"
check "sys_waitpid_block(255) is refused — it would become 0x1FF (any child)" "-1" "$(mark 51)"
check "sys_waitpid_block(3) is #4(0x103)" "259" "$(after 52 4 | awk '{ print $1 }')"
check "sys_waitpid_any_block is #4(0x1FF)" "511" "$(after 53 4 | awk '{ print $1 }')"
check "sys_kill_tree(5, 9) is #16(5, 0x109)" "5 265" "$(after 54 16 | cut -d' ' -f1-2)"
check "sys_kill_tree with a sig above 63 is refused" "-1" "$(mark 55)"
check "sys_spawn_limits(512, 1000) is #107(512, 1000)" "512 1000" "$(after 56 107 | cut -d' ' -f1-2)"
check "W*(265): not exited, signaled, sig 9 (SIGKILL)" "109" "$(mark 57)"
check "W*(0x2A): exited; WEXITSTATUS(0x12A) = 0x2A" "1042" "$(mark 58)"
check "W*(280): signaled by SIGXCPU (24)" "124" "$(mark 59)"
check "sys_getpeername asks #106 for the fd's conn and succeeds" "0 0" "$(after 60 106 | awk '{ print $1 }') $(mark 61)"
# 02 00 | 1f 90 | 7f 00 00 01 read as a little-endian u64
check "sys_getpeername writes sockaddr_in {AF_INET, 8080 BE, 127.0.0.1 BE}" "72058141916725250" "$(mark 62)"
check "sys_getpeername sets *addrlen = 16" "16" "$(mark 63)"
check "a 4-byte capacity gets 4 bytes, never 16 (POSIX truncation)" "2417950722" "$(mark 64)"
check "sys_getsockname on a client conn is -38 (agnos reports no local port)" "-38" "$(mark 65)"
check "sys_getpeername on a non-socket fd is -1" "-1" "$(mark 66)"
check "SIGXCPU = 24, FLOCK_E_TABLE_FULL = 2, PROCLIST_ZOMBIE = 7" "24207" "$(mark 67)"

# ── axis 4 — CVE-48: the bind ADDRESS picks the #56 listen class ─────────────────────────────
echo "axis 4 — sock_bind's address becomes the #56 listen class (CVE-48, agnos 1.57.7):"
cat > "$T/a4.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/tagged.cyr"
include "lib/net.cyr"
var f1_t, f1 = tcp_socket();
syscall(999, 70, 0);
sock_bind(f1, INADDR_LOOPBACK(), 8080);
sock_listen(f1, 4);
var f2_t, f2 = tcp_socket();
syscall(999, 71, 0);
sock_bind(f2, INADDR_ANY(), 8081);
sock_listen(f2, 4);
var f3_t, f3 = tcp_socket();
syscall(999, 72, 0);
sock_bind(f3, 0x0F02000A, 8082);
sock_listen(f3, 4);
var f4_t, f4 = tcp_socket();
var b4_t, b4 = sock_bind(f4, 0x6302000A, 8083);
syscall(999, 73, is_err_result(b4_t) * 1000 + b4);
var b5_t, b5 = sock_bind(f4, INADDR_LOOPBACK(), 70000);
syscall(999, 74, is_err_result(b5_t) * 1000 + b5);
var sa[16];
var al[8];
store64(&al, 16);
syscall(999, 75, sys_getsockname(f1, &sa, &al));
syscall(999, 76, load64(&sa));
sys_close(f1);
var f5_t, f5 = tcp_socket();
syscall(999, 77, f5 - f1);
var l5_t, l5 = sock_listen(f5, 4);
syscall(999, 78, is_err_result(l5_t));
var f6_t, f6 = tcp_socket();
sock_bind(f6, INADDR_LOOPBACK(), 8084);
var l6_t, l6 = sock_listen(f6, 4);
syscall(999, 79, is_err_result(l6_t));
sys_exit(0);
EOF
run "$T/a4.cyr" plain
check "bind 127.0.0.1 → #56(8080 | SOCK_LISTEN_LOOPBACK): loopback only" "4294975376" "$(after 70 56 | awk '{ print $1 }')"
check "bind 0.0.0.0 → #56(8081): class 0 (ANY)" "8081" "$(after 71 56 | awk '{ print $1 }')"
check "bind this host's net_ip (10.0.2.15) → #56(8082): class 0" "8082" "$(after 72 56 | awk '{ print $1 }')"
check "bind an address this host lacks (10.0.2.99) → Err(99), never widened" "1099" "$(mark 73)"
check "bind port 70000 → Err(22) (it would bleed into the class bits)" "1022" "$(mark 74)"
check "getsockname on the loopback listener reports 127.0.0.1:8080" "0 72058141916725250" "$(mark 75) $(mark 76)"
check "a recycled slot (closed loopback listener) inherits no port and no class" "0 1" "$(mark 77) $(mark 78)"
run "$T/a4.cyr" oldnet
check "on a pre-1.57.7 kernel (flagged #56 → -1) a loopback server FAILS CLOSED" "1" "$(mark 79)"

# ── axis 5 — the BSD socket verbs (6.6.17): built on #47 / #56 / #57, declining what agnos lacks ──
# They were missing from the peer (a portable caller failed to LINK on agnos). Each one must drive
# the same kernel calls lib/net.cyr's agnos arms do, with the same address and class rules.
echo "axis 5 — sys_socket / sys_bind / sys_listen / sys_connect / sys_accept4 on the agnos adapter (6.6.17):"
cat > "$T/a5.cyr" <<'EOF'
include "lib/alloc.cyr"
fn sa_in(sa, ip0, ip1, ip2, ip3, port): i64 {
    store64(sa, 0);
    store64(sa + 8, 0);
    store16(sa, 2);
    store8(sa + 2, (port >> 8) & 0xFF);
    store8(sa + 3, port & 0xFF);
    store8(sa + 4, ip0);
    store8(sa + 5, ip1);
    store8(sa + 6, ip2);
    store8(sa + 7, ip3);
    return sa;
}
var sa[16];
var pa[16];
var al[8];
var l = sys_socket(2, 1, 0);
syscall(999, 80, (l & AGNOS_SOCK_TAG) / AGNOS_SOCK_TAG);
syscall(999, 81, sys_socket(2, 2, 0) * 1000000 + sys_socket(10, 1, 0) * 1000 + sys_socket(2, 1, 17));
syscall(999, 82, sys_socket(2, 0x801, 0) * 1000 + (sys_socket(2, 0x80001, 6) & AGNOS_SOCK_TAG) / AGNOS_SOCK_TAG);
syscall(999, 83, sys_listen(l, 4));
syscall(999, 84, sys_bind(1, sa_in(&sa, 127, 0, 0, 1, 8080), 16));
syscall(999, 85, sys_bind(l, sa_in(&sa, 127, 0, 0, 1, 8080), 8) * 1000 + sys_bind(l, sa_in(&sa, 127, 0, 0, 1, 0), 16));
store16(&sa, 10);
syscall(999, 86, sys_bind(l, &sa, 16));
syscall(999, 87, sys_bind(l, sa_in(&sa, 10, 0, 2, 99, 8080), 16));
syscall(999, 88, sys_bind(l, sa_in(&sa, 127, 0, 0, 1, 8080), 16));
syscall(999, 89, sys_listen(l, 4));
var g = sys_socket(2, 1, 0);
sys_bind(g, sa_in(&sa, 0, 0, 0, 0, 8081), 16);
syscall(999, 90, 0);
sys_listen(g, 4);
var c = sys_socket(2, 1, 0);
syscall(999, 91, sys_connect(c, sa_in(&sa, 127, 0, 0, 1, 8080), 16));
syscall(999, 92, sys_connect(c, sa_in(&sa, 127, 0, 0, 1, 8080), 16) * 1000 + sys_connect(l, sa_in(&sa, 127, 0, 0, 1, 8080), 16));
store64(&al, 16);
syscall(999, 98, 0);
var rn = sys_accept4(l, &pa, &al, 0x800);
syscall(999, 93, rn);
var a = sys_accept4(l, &pa, &al, 0);
syscall(999, 94, (a & AGNOS_SOCK_TAG) / AGNOS_SOCK_TAG);
syscall(999, 95, load64(&pa));
syscall(999, 96, load64(&al) * 1000 + sys_accept4(c, 0, 0, 0) * 0 - sys_accept4(1, 0, 0, 0));
syscall(999, 97, sys_accept4(c, 0, 0, 0));
sys_exit(0);
EOF
run "$T/a5.cyr" plain
check "sys_socket(AF_INET, SOCK_STREAM, 0) is a tagged socket fd" "1" "$(mark 80)"
check "UDP, AF_INET6 and protocol 17 decline -38 (no fd form on agnos)" "-38038038" "$(mark 81)"
check "SOCK_NONBLOCK declines -38; SOCK_CLOEXEC with IPPROTO_TCP is a socket" "-37999" "$(mark 82)"
check "sys_listen on an unbound socket is -22 (EINVAL)" "-22" "$(mark 83)"
check "sys_bind on a non-socket fd is -88 (ENOTSOCK)" "-88" "$(mark 84)"
check "a short sockaddr and port 0 are -22 each" "-22022" "$(mark 85)"
check "a non-AF_INET sockaddr is -97 (EAFNOSUPPORT)" "-97" "$(mark 86)"
check "an address this host lacks (10.0.2.99) is -99, never widened (CVE-48)" "-99" "$(mark 87)"
check "sys_bind(127.0.0.1:8080) then sys_listen: #56(8080 | SOCK_LISTEN_LOOPBACK)" "0 0 4294975376" "$(mark 88) $(mark 89) $(after 88 56 | awk '{ print $1 }')"
check "sys_bind(0.0.0.0:8081) then sys_listen: #56(8081), class ANY" "8081" "$(after 90 56 | awk '{ print $1 }')"
check "sys_connect(127.0.0.1:8080) is #47(0x7F000001, 8080, 0) and answers 0" "0 2130706433 8080 0" "$(mark 91) $(after 90 47 | cut -d' ' -f1-3)"
check "connecting a connected or a listening socket is -106 (EISCONN)" "-106106" "$(mark 92)"
check "sys_accept4 with SOCK_NONBLOCK declines -38 before taking a connection" "-38 0" "$(mark 93) $(between 98 57)"
check "sys_accept4 is #57 on the listener's id and returns a tagged fd" "1 0" "$(mark 94) $(after 93 57 | awk '{ print $1 }')"
check "  and writes the peer (#106) as sockaddr_in {AF_INET, 8080 BE, 127.0.0.1 BE}" "72058141916725250" "$(mark 95)"
check "  with *addrlen = 16; accept on a non-socket fd is -88" "16088" "$(mark 96)"
check "sys_accept4 on a socket that is not listening is -22" "-22" "$(mark 97)"
cat > "$T/a5b.cyr" <<'EOF'
include "lib/alloc.cyr"
var sa[16];
store64(&sa, 0);
store64(&sa + 8, 0);
store16(&sa, 2);
store8(&sa + 2, 0x1F);
store8(&sa + 3, 0x90);
store8(&sa + 4, 127);
store8(&sa + 7, 1);
var l = sys_socket(2, 1, 0);
sys_bind(l, &sa, 16);
sys_listen(l, 4);
syscall(999, 100, sys_accept4(l, 0, 0, 0));
var c = sys_socket(2, 1, 0);
syscall(999, 101, sys_connect(c, &sa, 16));
var pa[16];
var al[8];
store64(&al, 0xFFFFFFFF);
syscall(999, 102, 0);
var e1 = sys_accept4(l, &pa, 0, 0);
var e2 = sys_accept4(l, &pa, &al, 0);
syscall(999, 103, e1 * 1000 + e2);
sys_exit(0);
EOF
run "$T/a5b.cyr" noacc
check "nothing pending (#57 -1) is -11 (EAGAIN), as on a non-blocking Linux listener" "-11" "$(mark 100)"
run "$T/a5b.cyr" plain
check "an address with no length is -14 (EFAULT), a negative length -22 — checked BEFORE #57 is issued" \
    "-14022 0" "$(mark 103) $(between 102 57)"
run "$T/a5b.cyr" noconn
check "a refused connect (#47 -1) is -111 (ECONNREFUSED)" "-111" "$(mark 101)"
run "$T/a5b.cyr" oldnet
check "a LOOPBACK listen on a pre-1.57.7 kernel is refused: sys_accept4 then reads -22 (not listening)" "-22" "$(mark 100)"

# ── axis 6 — the five verbs exist on the agnos peer at their Linux-common arity ──────────────
echo "axis 6 — the agnos peer defines the Linux-common BSD socket verbs at the same arity:"
for v in sys_socket sys_bind sys_listen sys_connect sys_accept4; do
    want=$(grep -E "^fn $v\(" lib/syscalls_linux_common.cyr | head -1 | sed 's/).*//' | tr ',' '\n' | wc -l)
    got=$(grep -E "^fn $v\(" lib/syscalls_x86_64_agnos.cyr | head -1 | sed 's/).*//' | tr ',' '\n' | wc -l)
    [ -n "$(grep -E "^fn $v\(" lib/syscalls_x86_64_agnos.cyr)" ] || got=0
    check "$v: agnos arity = Linux-common arity" "$want" "$got"
done

# ── axis 7 — the CLI builds for agnos (6.6.17): its refusal block, run under the fake kernel ─
echo "axis 7 — cbt/cyrius.cyr compiles for CYRIUS_TARGET_AGNOS=1 and its help path exits 0:"
if CYRIUS_TARGET_AGNOS=1 "$CC" < cbt/cyrius.cyr > "$T/cli.bin" 2>"$T/cli.err"; then
    chmod +x "$T/cli.bin"
    "$T/sct" "$T/cli.bin" plain > "$T/run.log" 2>&1
    check "the agnos CLI (no verb) writes its help to fd 2 and exits 0" "1 0" \
        "$(awk '$1 == "sc" && $2 == 1 && $3 == 2 { w = 1 } $1 == "exit" { c = $2 } END { print w + 0, c + 0 }' "$T/run.log")"
else
    echo "  FAIL: cbt/cyrius.cyr does not compile for agnos:"; grep -E '^error' "$T/cli.err" | head -5; fails=$((fails + 1))
fi

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: agnos_peer_fake_kernel — the agnos peer hands the kernel exactly the registers it decodes"
    exit 0
fi
echo "FAIL: agnos_peer_fake_kernel — $fails assertion(s) failed"
exit 1

#!/bin/sh
# 6.6.11 — the ws2_32 socket reroutes 0xF045-0xF04A are ROUTED by the parser at their arity, and
# lib/net.cyr + lib/http.cyr compile for PE with NO unrouted socket syscall left in them.
#
# ⛔ WHY: every verb in lib/net.cyr issued the Linux socket numbers (41/42/43/48/49/50/54), none
# of which is routed on CYRIUS_TARGET_WIN, so each returned -38 (-ENOSYS) at run time and http_*
# could not work on Windows. net.cyr's PE arms now reach ws2_32 — the older band (WSASocketW,
# bind, connect, listen, setsockopt, getsockopt, closesocket, getaddrinfo) plus six new reroutes
# the blocking verbs need: accept, shutdown, send, recv, ioctlsocket (FIONBIO) and WSAPoll. They
# reach the EACCEPT_PE … EWSAPOLL_PE emitters through `_PE_ROUTE_SOCK`
# (src/frontend/parse_expr.cyr); without that route each id is an unrouted literal again.
#
# THE AXES (compile-only; the behaviour is tests/tcyr/crossos/net_loopback_tcp.tcyr and
# net_resolve_pe.tcyr on real cass in the release gate's cross-OS leg).
#   axis 1  each id at its arity builds with CYRIUS_TARGET_WIN=1 and prints no "not routed"
#           warning for it.
#   axis 2  each id one argument short still warns — the route is literal-and-arity.
#   axis 3  the routed-number note names 0xF045-0xF04A (the note and the route table agree).
#   axis 4  a PE build of lib/http.cyr (which includes lib/net.cyr) and every net.cyr verb
#           prints no "not routed" warning attributed to lib/net.cyr or lib/http.cyr. ⚠ That
#           warning names LITERAL numbers only: a verb that regressed to a var-held number
#           (`syscall(NSYS_SOCKET, ...)`) goes to the dynamic path silently, so the behaviour
#           rows in tests/tcyr/crossos/net_loopback_tcp.tcyr (wine / cass) are its check.
#   axis 5  the axis-1 builds IMPORT all six ws2_32 functions (objdump -p's import table; that
#           axis alone is skipped without an objdump that reads PE).
#
# MUTATION (built and run 2026-09-29, lane W bite B07): the cycc WITHOUT the `_PE_ROUTE_SOCK`
# hunk FAILS axes 1, 3, 4 and 5 (and the row floor); `_PE_ROUTE_SOCK` accepting any arity FAILS
# axis 2; making net_connect_sa_nb's POSIX arm reachable on PE (its literal 42/7/55) FAILS axis 4.
# Exit 77 = could not run (the SKIP protocol). CHANGELOG [6.6.11]
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: pe_socket_reroutes_routed: build/cycc missing"; exit 77; }

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: pe_socket_reroutes_routed: mktemp -d failed"; exit 1; }
trap 'rm -rf "$D"' EXIT INT TERM

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { printf '  FAIL: %s\n' "$1"; fail=$((fail + 1)); }

# id  decimal  name  args-at-arity  args-one-short
ROWS="0xF045 61509 accept 0,0,0 0,0
0xF046 61510 shutdown 0,0 0
0xF047 61511 send 0,0,0,0 0,0,0
0xF048 61512 recv 0,0,0,0 0,0,0
0xF049 61513 ioctlsocket 0,0,0 0,0
0xF04A 61514 WSAPoll 0,0,0 0,0"

build() {  # $1 = file stem, $2 = the syscall's argument list
    printf 'fn main(): i64 {\n    var j = syscall(%s);\n    return j & 0;\n}\nvar r = main();\nsyscall(60, r);\n' "$2" > "$D/$1.cyr"
    CYRIUS_TARGET_WIN=1 "$CC" < "$D/$1.cyr" > "$D/$1.exe" 2> "$D/$1.err"
}

echo "$ROWS" | while read -r id dec name good short; do
    build "g$dec" "$id, $good"
    rc=$?
    if [ "$rc" -ne 0 ] || [ ! -s "$D/g$dec.exe" ]; then echo "BAD axis 1: $id ($name) build rc $rc"
    elif grep -q "syscall $dec with" "$D/g$dec.err"; then echo "BAD axis 1: $id ($name) at its arity is reported not routed"
    else echo "OK"; fi
    build "s$dec" "$id, $short"
    if grep -q "syscall $dec with" "$D/s$dec.err"; then echo "OK"
    else echo "BAD axis 2: $id ($name) one argument short did not warn"; fi
done > "$D/rows.txt"
while read -r line; do
    case "$line" in OK) ok ;; *) bad "${line#BAD }" ;; esac
done < "$D/rows.txt"

# axis 3: any unrouted literal prints the routed-number note once; it must list the socket range.
build note "0xF03C, 0, 0"
if grep -q '^  note: CYRIUS_TARGET_WIN=1 routes' "$D/note.err"; then
    if grep '^  note: CYRIUS_TARGET_WIN=1 routes' "$D/note.err" | grep -q '0xF045-0xF04A (ws2_32: accept/shutdown/send/recv/ioctlsocket/WSAPoll)'; then ok
    else bad "axis 3: the routed-number note does not name 0xF045-0xF04A"; fi
else bad "axis 3: the unrouted 0xF03C probe printed no routed-number note"; fi

# axis 4: every net.cyr verb, compiled for PE from the tree's lib/. Raw cat | cycc resolves
# includes against the CWD, so it runs from ROOT.
cat > "$D/verbs.cyr" <<'CYR'
include "lib/http.cyr"
fn main(): i64 {
    alloc_init();
    var t, fd = tcp_socket();
    var u, ud = udp_socket();
    sock_reuse(fd);
    sock_reuseport(ud);
    sock_set_recv_timeout(fd, 1, 0);
    sock_set_send_timeout(fd, 1, 0);
    var bt, bv = sock_bind(fd, INADDR_LOOPBACK(), 0);
    var lt, lv = sock_listen(fd, 4);
    var at, av = sock_accept(fd);
    var ct, cv = sock_connect(ud, INADDR_LOOPBACK(), 9);
    var st, sv = sock_send(ud, "x", 1);
    sock_send_all(ud, "x", 1);
    var rt, rv = sock_recv(ud, &bv, 1);
    sock_send_a(0, ud, "x", 1);
    sock_recv_a(0, ud, &bv, 1);
    sock_shutdown(fd, 2);
    net_join_multicast(ud, 0, 0);
    net_drop_multicast(ud, 0, 0);
    net_set_multicast_ttl(ud, 1);
    net_set_multicast_loop(ud, 1);
    net_set_multicast_if(ud, 0);
    var s = sock_set_nonblocking(fd);
    sock_clear_nonblocking(fd, s);
    net_connect_nb(fd, INADDR_LOOPBACK(), 9, 10);
    net_connect_nb6(fd, &bv, 9, 10);
    net_resolve_ipv4("example.invalid");
    net_dns_query_ipv4("example.invalid", INADDR_LOOPBACK(), 53);
    http_get("http://127.0.0.1:9/");
    var gt, gv = http_get_r("http://127.0.0.1:9/");
    http_get_a(0, "http://127.0.0.1:9/");
    sock_close(fd);
    return 0;
}
var r = main();
syscall(60, r);
CYR
if (cd "$ROOT" && CYRIUS_TARGET_WIN=1 "$CC" < "$D/verbs.cyr" > "$D/verbs.exe" 2> "$D/verbs.err") && [ -s "$D/verbs.exe" ]; then
    if grep -E '^warning:lib/(net|http)\.cyr:[0-9]+:[0-9]+: syscall ' "$D/verbs.err" > "$D/unrouted.txt"; then
        bad "axis 4: lib/net.cyr / lib/http.cyr still issue unrouted syscalls on PE: $(head -3 "$D/unrouted.txt" | cut -c1-120 | tr '\n' ' ')"
    else ok; fi
else
    bad "axis 4: the PE build of every net.cyr verb failed: $(head -3 "$D/verbs.err" | tr '\n' ' ')"
fi

# axis 5: the imports, read from the import directory.
if objdump -p "$D/g61509.exe" > "$D/imp.txt" 2>/dev/null && grep -q 'DLL Name' "$D/imp.txt"; then
    for dec in 61509 61510 61511 61512 61513 61514; do objdump -p "$D/g$dec.exe"; done > "$D/imp.txt" 2>/dev/null
    for fn in accept shutdown send recv ioctlsocket WSAPoll; do
        if grep -q " $fn\$" "$D/imp.txt"; then ok; else bad "axis 5: no build imports $fn"; fi
    done
else
    echo "  SKIP: axis 5 (no objdump that reads PE)"
fi

echo "$pass passed, $fail failed"
[ "$pass" -ge 14 ] || { echo "FAIL: pe_socket_reroutes_routed: only $pass rows ran (floor 14)"; exit 1; }
if [ "$fail" -ne 0 ]; then echo "FAIL: pe_socket_reroutes_routed"; exit 1; fi
echo "PASS: pe_socket_reroutes_routed — 0xF045-0xF04A routed at their arity, named, imported; no unrouted net.cyr verb on PE"

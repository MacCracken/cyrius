#!/bin/sh
# tls_libssl_hostname_binding.sh — 6.6.13 (I1, CVE-59). The libssl TLS backend binds the
# server's leaf certificate to `host`, and answers EXACTLY as the native backend does, against an
# independent peer (OpenSSL's s_server — a peer that shared our code could share the defect).
#
# ⛔ THE DEFECT. lib/tls.cyr's libssl client set SSL_VERIFY_PEER and SNI and nothing else.
# SSL_VERIFY_PEER checks the CHAIN; with no expected identity in the SSL's X509_VERIFY_PARAM,
# OpenSSL accepted ANY chain-valid leaf for ANY host: a cert for DNS:localhost verified
# www.example.com, 127.0.0.1 and host == 0, and a CN-only leaf and a partial wildcard
# (f*.example.com) verified too. Reached by every -D CYRIUS_TLS_LIBSSL build and by a default
# build after tls_set_backend(TLS_BACKEND_LIBSSL). Native refused all of it (CVE-18).
# Filed repro: docs/development/issues/repros/2026-09-30-tls-libssl-no-hostname-verification.sh.
#
# THE FIX (lib/tls.cyr `_tls_libssl_bind_host`, run in tls_connect_alloc after the hook): the
# host is classified by the native stack's own code (lib/tls_hostid.cyr) — an IP literal is
# bound with X509_VERIFY_PARAM_set1_ip_asc and sends NO SNI; a DNS name gets hostflags
# NO_PARTIAL_WILDCARDS|NEVER_CHECK_SUBJECT, X509_VERIFY_PARAM_set1_host and SNI; host 0 / "" / a
# ':'-bearing non-literal is refused under SSL_VERIFY_PEER (tls_connect_alloc returns 0, no
# handshake) and binds nothing after a hook's tls_set_verify(h, 0, 0). The five symbols are
# REQUIRED by _tls_init: one missing => tls_available() == 0, every libssl connect returns 0.
#
# LEGS (one probe, compiled twice):
#   N  default build, native backend               — the reference answers
#   B  default build, tls_set_backend(LIBSSL)      — libssl through the runtime switch
#   L  `#define CYRIUS_TLS_LIBSSL` build            — the libssl-only build (no native stack)
#   S  native and libssl rows against s_server -servername sni.invalid -servername_fatal: an IP
#      host sends no SNI (the handshake survives), a DNS host does (the fatal alert refuses it —
#      the control that shows the leg can see an SNI). Native rows since 6.6.14: its ClientHello
#      builders sent an IP literal as SNI until then (RFC 6066 3; lib/tls_hostid.cyr _tn_sni_len).
#   P  libssl rows where the hook pins a name / an IP on the SSL_CTX's X509_VERIFY_PARAM: the
#      binding REPLACES a pin of host's own kind and keeps a pin of the other kind (documented
#      in lib-tls-contract.md "Server identity"; pass the name to verify as `host`).
#   X  bogus-symbol legs: L rebuilt against a lib/ copy whose lib/tls.cyr asks dlsym for a
#      nonexistent name in place of each binder symbol in turn — tls_available() must be 0 and
#      tls_connect_alloc must return 0 (fail closed). An unmutated copy must read available.
# SKIP (exit 77, named): openssl(1) missing (whole gate); $HOME/.cyrius/dlopen-helper or
# libssl.so.3 missing (the libssl legs — N still runs, a FAIL there is still a FAIL).
# ANTI-VACUITY: with helper and libssl.so.3 present, tls_available() must be 1 under libssl
# (a broken required-symbol resolution cannot read green as a skip), and the libssl rows run
# are counted and floored.
#
# MUTATION LEDGER (6.6.13, each measured RED here):
#   MI1 the _tls_libssl_bind_host call deleted from tls_connect_alloc (the 6.6.12 shape)
#       -> B/L www.example.com, 127.0.0.1, host 0 / "", CN-only, f*.example.com, [::1], ...
#   MI2 the X509_VERIFY_PARAM_set_hostflags call dropped -> B/L CN-only and f*.example.com
#   MI3 one required-symbol bail line removed from _tls_init -> its X leg (available, crash)
#   MI4 SSL_set1_host-style binding (no shared classifier; the name routed by OpenSSL's own
#       IP parse) -> the [::1] rows
#   MI5 SNI set for every host again -> S 127.0.0.1 / ::1
# 6.6.14:
#   MI6 the native ClientHello builders before _tn_sni_len (SNI for every host) -> the three
#       native S rows for 127.0.0.1 / ::1 (the fatal-on-mismatch server refuses the literal)
#   MI7 the native matcher before _tn_wildcard_ok (any "*." a wildcard, any byte under the star)
#       -> the N rows a_b.example.com, a.com and example.com vs *.com (CVE-67)
#   MI8 serve's 6.6.13 readiness probe (any TCP connect on the port) with the first port held ->
#       S0: serve settles on the held port, and the 127.0.0.1 rows meet the foreign DNS leaf
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 1
G=tls_libssl_hostname_binding
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
command -v openssl >/dev/null 2>&1 || {
    echo "SKIP: $G: openssl(1) not found — the peer under test is OpenSSL's s_server"; exit 77; }

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
SP=0
trap '[ "$SP" -ne 0 ] && kill "$SP" 2>/dev/null; rm -rf "$T"' EXIT
FAILS=0
NLIB=0
NNAT=0
TO=""
command -v timeout >/dev/null 2>&1 && TO="timeout 60"

# ── certificates: a CA, an untrusted CA, seven leaves ──
q() { "$@" >/dev/null 2>&1 || { echo "FAIL: $G: setup: $*"; exit 1; }; }
q openssl ecparam -name prime256v1 -genkey -noout -out "$T/ca.key"
q openssl req -x509 -new -key "$T/ca.key" -subj /CN=gate-ca -days 2 -out "$T/ca.crt"
q openssl ecparam -name prime256v1 -genkey -noout -out "$T/other.key"
q openssl req -x509 -new -key "$T/other.key" -subj /CN=other-ca -days 2 -out "$T/other.crt"
leaf() {  # <name> <subject CN> <subjectAltName or empty>
    q openssl ecparam -name prime256v1 -genkey -noout -out "$T/$1.key"
    q openssl req -new -key "$T/$1.key" -subj "/CN=$2" -out "$T/$1.csr"
    if [ -n "$3" ]; then
        printf 'subjectAltName=%s\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n' "$3" > "$T/$1.ext"
    else
        printf 'basicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n' > "$T/$1.ext"
    fi
    q openssl x509 -req -in "$T/$1.csr" -CA "$T/ca.crt" -CAkey "$T/ca.key" -CAcreateserial \
        -days 2 -extfile "$T/$1.ext" -out "$T/$1.crt"
}
leaf dns localhost "DNS:localhost"
leaf ip ip-leaf "IP:127.0.0.1"
leaf wc wc-leaf "DNS:*.example.com"
leaf cn localhost ""
leaf pw pw-leaf "DNS:f*.example.com"
leaf bait bait-leaf "DNS:010.0.0.1,DNS:[::1],IP:10.0.0.1,IP:::1"
leaf ip10 ip10-leaf "IP:10.0.0.1"
leaf tld tld-leaf "DNS:*.com"

# ── the probe ──
# probe <native|libssl|libssl0> <port> <cafile> <host|@0|@empty> <peer|none|pinhost N|pinip A>;
# probe tcp <port>; pinhost/pinip = the hook pins a name / an IP on the SSL_CTX param (libssl);
# probe avail. libssl0 = libssl with no tls_available() pre-check (tls_connect_alloc's own answer).
# exit 10 accepted / 20 handshake refused / 30 tls_connect_alloc returned 0 / 40 no TCP /
#      50 libssl unavailable / 60 backend not compiled in / 11|12 avail yes|no / 0 tcp ok
cat > "$T/probe.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/io.cyr"
include "lib/net.cyr"
include "lib/args.cyr"
include "lib/tls.cyr"

var G_CA = 0;
var G_NONE = 0;
var G_PINK = 0;    # 1 = the hook pins a NAME on the SSL_CTX param, 2 = an IP
var G_PIN = 0;

fn _hook(hctx, handle): i64 {
    if (tls_ctx_load_verify_locations(handle, G_CA, 0) != 1) { return 1; }
    if (G_NONE == 1) {
        if (tls_set_verify(handle, 0, 0) != 0) { return 1; }
    }
    if (G_PINK != 0) {
        # libssl only: a consumer pinning an identity on the SSL_CTX's X509_VERIFY_PARAM
        var gp = tls_dlsym("SSL_CTX_get0_param");
        if (gp == 0) { return 1; }
        var p = fncall1(gp, handle);
        if (p == 0) { return 1; }
        var pr = 0;
        if (G_PINK == 1) {
            var sh = tls_dlsym("X509_VERIFY_PARAM_set1_host");
            if (sh == 0) { return 1; }
            pr = fncall3(sh, p, G_PIN, strlen(G_PIN));
        } else {
            var si = tls_dlsym("X509_VERIFY_PARAM_set1_ip_asc");
            if (si == 0) { return 1; }
            pr = fncall2(si, p, G_PIN);
        }
        if ((pr & 0xFFFFFFFF) != 1) { return 1; }
    }
    return 0;
}

fn main(): i64 {
    alloc_init();
    args_init();
    if (argc() < 2) { return 2; }
    var be = argv(1);
    if (streq(be, "avail") == 1) {
        if (tls_set_backend(TLS_BACKEND_LIBSSL) != 0) { return 60; }
        if (tls_available() == 1) { return 11; }
        return 12;
    }
    if (argc() < 3) { return 2; }
    var port = atoi(argv(2));
    var st, fd = tcp_socket();
    if (is_err_result(st) != 0) { return 40; }
    var cs, cv = sock_connect(fd, INADDR_LOOPBACK(), port);
    if (is_err_result(cs) != 0) { sock_close(fd); return 40; }
    if (streq(be, "tcp") == 1) { sock_close(fd); return 0; }
    if (argc() < 6) { sock_close(fd); return 2; }
    if (streq(be, "libssl") == 1) {
        if (tls_set_backend(TLS_BACKEND_LIBSSL) != 0) { sock_close(fd); return 60; }
        if (tls_available() != 1) { sock_close(fd); return 50; }
    } elif (streq(be, "libssl0") == 1) {
        # no availability check: what tls_connect_alloc itself does when libssl is not usable
        if (tls_set_backend(TLS_BACKEND_LIBSSL) != 0) { sock_close(fd); return 60; }
    } else {
        if (tls_set_backend(TLS_BACKEND_NATIVE) != 0) { sock_close(fd); return 60; }
    }
    G_CA = argv(3);
    var host = argv(4);
    if (streq(host, "@0") == 1) { host = 0; }
    elif (streq(host, "@empty") == 1) { host = ""; }
    if (streq(argv(5), "none") == 1) { G_NONE = 1; }
    elif (streq(argv(5), "pinhost") == 1) { G_PINK = 1; }
    elif (streq(argv(5), "pinip") == 1) { G_PINK = 2; }
    if (G_PINK != 0) {
        if (argc() < 7) { sock_close(fd); return 2; }
        G_PIN = argv(6);
    }
    var ctx = tls_connect_alloc(fd, host, &_hook, 0);
    if (ctx == 0) { sock_close(fd); return 30; }
    var ok = tls_connect_complete(ctx);
    tls_close(ctx);
    sock_close(fd);
    if (ok == 1) { return 10; }
    return 20;
}
var r = main();
syscall(SYS_EXIT_GROUP, r);
EOF
"$CC" < "$T/probe.cyr" > "$T/pd" 2>"$T/pd.err" && chmod +x "$T/pd" || {
    echo "FAIL: $G: the default-build probe did not compile"; tail -3 "$T/pd.err"; exit 1; }
{ echo '#define CYRIUS_TLS_LIBSSL'; cat "$T/probe.cyr"; } | "$CC" > "$T/pl" 2>"$T/pl.err" && chmod +x "$T/pl" || {
    echo "FAIL: $G: the libssl-only probe did not compile"; tail -3 "$T/pl.err"; exit 1; }

# ── is the libssl backend reachable here? ──
LIBSSL=1
WHY=""
HELPER="${HOME:-}/.cyrius/dlopen-helper"
if [ -z "${HOME:-}" ] || [ ! -f "$HELPER" ]; then
    LIBSSL=0; WHY="$HELPER missing (built by scripts/install.sh)"
else
    found=0
    if ldconfig -p 2>/dev/null | grep -q 'libssl\.so\.3 '; then found=1; fi
    for d in /usr/lib /usr/lib64 /lib /lib64 /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu \
             /usr/lib/aarch64-linux-gnu /usr/local/lib; do
        [ -e "$d/libssl.so.3" ] && found=1
    done
    [ "$found" = 1 ] || { LIBSSL=0; WHY="libssl.so.3 not found"; }
fi
if [ "$LIBSSL" = 1 ]; then
    # ANTI-VACUITY: helper + libssl present => the backend MUST come up, in both builds.
    a=0; $TO "$T/pd" avail || a=$?
    b=0; $TO "$T/pl" avail || b=$?
    if [ "$a" != 11 ] || [ "$b" != 11 ]; then
        echo "  FAIL: helper and libssl.so.3 are present but tls_available() under libssl is not 1 (default build exit $a, libssl-only build exit $b; 11 = available) — a required symbol did not resolve, or the bootstrap broke"
        exit 1
    fi
    echo "  ok: libssl backend available in both builds (helper $HELPER)"
else
    echo "  SKIP (libssl legs): $WHY — the native rows still run"
fi

# ── servers ──
# serve <leaf> [extra s_server args...]: start ONE s_server on a random loopback port and wait for
# its own "ACCEPT" line, which s_server prints only once ITS listen() has succeeded; a bind failure
# ends the process before the line, and serve retries on another port. No row connects before then.
# ⛔ 6.6.14 — WHY. serve used to wait for ANY TCP connect to succeed on the port: a foreign listener
# already holding it answered the probe while s_server died on its bind, and the rows then ran
# against a stranger (a flake that read as a TLS verdict). SERVE_FIRST_PORT forces the first port
# tried (the S0 self-check below occupies one on purpose).
PORT=0
SERVE_FIRST_PORT=
serve() {
    c=$1; shift
    tries=0
    while [ $tries -lt 5 ]; do
        if [ -n "$SERVE_FIRST_PORT" ]; then PORT=$SERVE_FIRST_PORT; SERVE_FIRST_PORT=
        else PORT=$((20000 + $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % 20000)); fi
        openssl s_server -accept "127.0.0.1:$PORT" -cert "$T/$c.crt" -key "$T/$c.key" -www "$@" \
            > "$T/sv.log" 2>&1 < /dev/null &
        SP=$!
        if _serve_ready "$SP" "$T/sv.log"; then return 0; fi
        kill "$SP" 2>/dev/null || true; wait "$SP" 2>/dev/null || true; SP=0
        tries=$((tries + 1))
    done
    echo "FAIL: $G: s_server for leaf '$c' never reached ACCEPT (5 ports tried)"; tail -3 "$T/sv.log"; exit 1
}
# _serve_ready <pid> <log>: 0 once <log> holds s_server's ACCEPT line; 1 when the process ends
# first (its bind failed) or 10 s pass.
_serve_ready() {
    i=0
    while [ $i -lt 200 ]; do
        if grep -q '^ACCEPT' "$2" 2>/dev/null; then return 0; fi
        kill -0 "$1" 2>/dev/null || return 1
        sleep 0.05
        i=$((i + 1))
    done
    return 1
}
stop() { [ "$SP" -ne 0 ] && { kill "$SP" 2>/dev/null || true; wait "$SP" 2>/dev/null || true; }; SP=0; }

# A = accepted (10); R = refused, at alloc or handshake (30|20); R0 = tls_connect_alloc returned 0
# without a handshake (30); RH = the handshake refused (20).
_want() {  # <want> <rc> -> 0 if rc satisfies want
    case "$1:$2" in A:10|R:20|R:30|R0:30|RH:20) return 0 ;; esac
    return 1
}
one() {  # <leg> <binary> <backend> <host> <verify> <cafile> <want> <label>
    rc=0; $TO "$2" "$3" "$PORT" "$6" "$4" "$5" >/dev/null 2>&1 || rc=$?
    if _want "$7" "$rc"; then
        echo "  ok: [$1] $8 -> $7"
    else
        echo "  FAIL: [$1] $8 — want $7, probe exit $rc (10 accepted, 20 handshake refused, 30 alloc refused, 40 no TCP, 50 libssl unavailable)"
        FAILS=$((FAILS + 1))
    fi
}
# row <host> <verify> <cafile> <want native> <want libssl> <label>
row() {
    one N "$T/pd" native "$1" "$2" "$3" "$4" "$6"; NNAT=$((NNAT + 1))
    if [ "$LIBSSL" = 1 ]; then
        one B "$T/pd" libssl "$1" "$2" "$3" "$5" "$6"
        one L "$T/pl" libssl "$1" "$2" "$3" "$5" "$6"
        NLIB=$((NLIB + 2))
    fi
}
# srow <host> <verify> <want> <label> — the S leg: native and both libssl builds answer alike
srow() {
    one S "$T/pd" native "$1" "$2" "$T/ca.crt" "$3" "$4 (native)"; NNAT=$((NNAT + 1))
    if [ "$LIBSSL" = 1 ]; then
        one S "$T/pd" libssl "$1" "$2" "$T/ca.crt" "$3" "$4"
        one S "$T/pl" libssl "$1" "$2" "$T/ca.crt" "$3" "$4 (libssl-only build)"
        NLIB=$((NLIB + 2))
    fi
}

# prow <host> <pinhost|pinip> <pin> <want libssl> <label> — the P leg: a hook's pin on the
# SSL_CTX's X509_VERIFY_PARAM. The binding goes on the per-SSL param and REPLACES a pin of the
# SAME kind as `host` (a name for a DNS host, an IP for a literal); a pin of the OTHER kind
# survives and must match too. Libssl only (native has no X509_VERIFY_PARAM).
prow() {
    if [ "$LIBSSL" = 1 ]; then
        for pb in pd pl; do
            rc=0; $TO "$T/$pb" libssl "$PORT" "$T/ca.crt" "$1" "$2" "$3" >/dev/null 2>&1 || rc=$?
            if _want "$4" "$rc"; then echo "  ok: [P/$pb] $5 -> $4"
            else
                echo "  FAIL: [P/$pb] $5 — want $4, probe exit $rc (10 accepted, 20 handshake refused, 30 alloc refused)"
                FAILS=$((FAILS + 1))
            fi
            NLIB=$((NLIB + 1))
        done
    fi
}

CA="$T/ca.crt"
# ── S0: serve's own readiness (6.6.14) — a port another listener holds is never connected to ──
# A foreign s_server (leaf DNS:localhost) holds a port; serve is forced to try that port first for
# the IP leaf. It must see its own s_server die on the bind and come up on ANOTHER port, and the
# 127.0.0.1 row must then pass — against the foreign DNS leaf it would be refused.
echo "S0: serve when the first port is already held"
serve dns
FPORT=$PORT; FSP=$SP; SP=0
SERVE_FIRST_PORT=$FPORT
serve ip
if [ "$PORT" != "$FPORT" ] && kill -0 "$SP" 2>/dev/null; then
    echo "  ok: [S0] the bind failure on $FPORT was seen; s_server is up on $PORT"
else
    echo "  FAIL: [S0] serve settled on port $PORT (the held port was $FPORT) — it would connect to a stranger"
    FAILS=$((FAILS + 1))
fi
row 127.0.0.1       peer "$CA"            A  A  "S0: 127.0.0.1 reaches the IP leaf, not the listener that held the port"
kill "$FSP" 2>/dev/null || true; wait "$FSP" 2>/dev/null || true
stop
echo "leaf DNS:localhost"
serve dns
row localhost       peer "$CA"            A  A  "localhost: the SAN name"
row LOCALHOST       peer "$CA"            A  A  "LOCALHOST: case-insensitive"
row www.example.com peer "$CA"            R  R  "www.example.com: a name outside the SAN (the filed row)"
row 127.0.0.1       peer "$CA"            R  R  "127.0.0.1: an IP host never matches a dNSName"
row @0              peer "$CA"            R  R0 "host 0 under SSL_VERIFY_PEER"
row @empty          peer "$CA"            R  R0 "host \"\" under SSL_VERIFY_PEER"
row @0              none "$CA"            A  A  "host 0 after the hook's tls_set_verify(h, 0, 0)"
row 127.0.0.1       none "$CA"            A  A  "127.0.0.1 after tls_set_verify(h, 0, 0): nothing is bound"
row localhost       peer "$T/other.crt"   R  R  "localhost, trusting only an unrelated CA (chain control)"
prow localhost pinhost other.name A "localhost, hook pinned the NAME other.name: replaced by host"
prow localhost pinip 10.9.9.9     RH "localhost, hook pinned the IP 10.9.9.9: kept, and the leaf has no such IP"
stop
echo "leaf IP:127.0.0.1"
serve ip
row 127.0.0.1       peer "$CA"            A  A  "127.0.0.1: the iPAddress SAN"
row localhost       peer "$CA"            R  R  "localhost: a DNS name never matches an iPAddress"
row 127.000.0.1     peer "$CA"            R  R  "127.000.0.1: leading zeros are no literal (I7)"
row 127.1           peer "$CA"            R  R  "127.1: a short form is no literal"
prow 127.0.0.1 pinip 10.9.9.9     A  "127.0.0.1, hook pinned the IP 10.9.9.9: replaced by host"
prow 127.0.0.1 pinhost other.name RH "127.0.0.1, hook pinned the NAME other.name: kept, and the leaf has no such name"
stop
echo "leaf DNS:*.example.com"
serve wc
row a.example.com   peer "$CA"            A  A  "a.example.com: one label under the wildcard"
row example.com     peer "$CA"            R  R  "example.com: the wildcard needs a label"
row a.b.example.com peer "$CA"            R  R  "a.b.example.com: the wildcard covers ONE label"
row a_b.example.com peer "$CA"            R  R  "a_b.example.com: the star stands for LDH bytes only (6.6.14)"
stop
echo "leaf DNS:*.com (6.6.14, CVE-67)"
serve tld
row a.com           peer "$CA"            R  R  "a.com vs *.com: one label after the star is no wildcard"
row example.com     peer "$CA"            R  R  "example.com vs *.com"
stop
echo "leaf CN=localhost, no SAN"
serve cn
row localhost       peer "$CA"            R  R  "localhost vs a CN-only leaf: no subject-CN fallback"
stop
echo "leaf DNS:f*.example.com"
serve pw
row foo.example.com peer "$CA"            R  R  "foo.example.com vs f*.example.com: no partial wildcard"
stop
echo "leaf DNS:010.0.0.1, DNS:[::1], IP:10.0.0.1, IP:::1 (the classifier's bait)"
serve bait
row 010.0.0.1       peer "$CA"            A  A  "010.0.0.1 is a DNS name (no literal has a leading zero): its dNSName"
row "[::1]"         peer "$CA"            RH R0 "[::1] has no identity (a bracketed host is no literal, no name)"
row ::1             peer "$CA"            A  A  "::1: the IPv6 iPAddress SAN"
row 10.0.0.1        peer "$CA"            A  A  "10.0.0.1: the IPv4 iPAddress SAN"
stop
echo "leaf IP:10.0.0.1"
serve ip10
row 010.0.0.1       peer "$CA"            R  R  "010.0.0.1 never reaches the iPAddress 10.0.0.1"
row 10.0.0.1        peer "$CA"            A  A  "10.0.0.1: the iPAddress SAN"
stop
echo "SNI (native + libssl): s_server -servername sni.invalid -servername_fatal"
serve ip -servername sni.invalid -servername_fatal -cert2 "$T/ip.crt" -key2 "$T/ip.key"
srow 127.0.0.1 peer A "127.0.0.1 sends no SNI (RFC 6066 3) - the fatal-on-mismatch server lets it through"
srow 127.0.0.1 none A "127.0.0.1 after tls_set_verify(h, 0, 0) sends no SNI either"
stop
serve bait -servername sni.invalid -servername_fatal -cert2 "$T/bait.crt" -key2 "$T/bait.key"
srow ::1 peer A "::1 sends no SNI"
stop
serve dns -servername sni.invalid -servername_fatal -cert2 "$T/dns.crt" -key2 "$T/dns.key"
srow localhost peer RH "localhost DOES send SNI: the mismatch is fatal (the leg can see an SNI)"
stop
serve dns -servername localhost -servername_fatal -cert2 "$T/dns.crt" -key2 "$T/dns.key"
srow localhost peer A "localhost's SNI is the host itself"
stop

# ── X: every binder symbol is REQUIRED ──
if [ "$LIBSSL" = 1 ]; then
    echo "required symbols (a libssl-only build against a lib/ copy with one dlsym name broken)"
    # lib/ is LINKED entry by entry (8+ MB copied into a busy /tmp flaked under check.sh load);
    # only tls.cyr is a real copy — the sed below writes it, and must never write through a link.
    mkdir -p "$T/mut/lib" || { echo "FAIL: $G: cannot make $T/mut/lib"; exit 1; }
    for e in "$ROOT"/lib/* "$ROOT"/lib/.[!.]*; do
        [ -e "$e" ] || continue
        b=${e##*/}
        [ "$b" = tls.cyr ] && continue
        ln -s "$e" "$T/mut/lib/$b" || { echo "FAIL: $G: cannot link lib/$b"; exit 1; }
    done
    cp "$ROOT/lib/tls.cyr" "$T/mut/lib/tls.cyr" || { echo "FAIL: $G: cannot copy tls.cyr into $T/mut"; exit 1; }
    serve dns
    (cd "$T/mut" && { echo '#define CYRIUS_TLS_LIBSSL'; cat "$T/probe.cyr"; } | "$CC" > "$T/px" 2>/dev/null) && chmod +x "$T/px"
    rc=0; $TO "$T/px" avail || rc=$?
    if [ "$rc" = 11 ]; then echo "  ok: [X] control: the unmutated copy reads available"
    else echo "  FAIL: [X] control: the unmutated lib/ copy reads exit $rc, want 11 — the X leg cannot measure"; FAILS=$((FAILS + 1)); fi
    NX=0
    for sym in SSL_get0_param SSL_get_verify_mode X509_VERIFY_PARAM_set1_host \
               X509_VERIFY_PARAM_set_hostflags X509_VERIFY_PARAM_set1_ip_asc; do
        n=$(grep -c "\"$sym\"" "$ROOT/lib/tls.cyr")
        if [ "$n" != 1 ]; then
            echo "  FAIL: [X] lib/tls.cyr names \"$sym\" $n times (want 1) — the mutation would not be the dlsym call"
            FAILS=$((FAILS + 1)); continue
        fi
        sed "s/\"$sym\"/\"cyrius_bogus_$sym\"/" "$ROOT/lib/tls.cyr" > "$T/mut/lib/tls.cyr"
        (cd "$T/mut" && { echo '#define CYRIUS_TLS_LIBSSL'; cat "$T/probe.cyr"; } | "$CC" > "$T/px" 2>/dev/null) && chmod +x "$T/px" || {
            echo "  FAIL: [X] $sym: the mutated probe did not compile"; FAILS=$((FAILS + 1)); continue; }
        a=0; $TO "$T/px" avail || a=$?
        b=0; $TO "$T/px" libssl0 "$PORT" "$CA" localhost peer || b=$?
        if [ "$a" = 12 ] && [ "$b" = 30 ]; then
            echo "  ok: [X] $sym unresolvable -> tls_available() 0, tls_connect_alloc 0"
        else
            echo "  FAIL: [X] $sym unresolvable -> avail exit $a (want 12 = 0), tls_connect_alloc exit $b (want 30 = returned 0; 10 = it connected unbound)"
            FAILS=$((FAILS + 1))
        fi
        NX=$((NX + 1))
    done
    cp "$ROOT/lib/tls.cyr" "$T/mut/lib/tls.cyr"
    stop
    NLIB=$((NLIB + NX))
fi

echo "rows: $NNAT native, $NLIB libssl"
# 28 rows (the S0 row included) + 5 SNI rows (6.6.14)
[ "$NNAT" -ge 33 ] || { echo "  FAIL: only $NNAT native rows ran (floor 33)"; FAILS=$((FAILS + 1)); }
if [ "$LIBSSL" = 1 ]; then
    # 28 rows x 2 libssl legs (B, L) + 5 SNI rows x 2 builds + 4 pin rows x 2 builds
    # + 5 required-symbol legs
    [ "$NLIB" -ge 79 ] || { echo "  FAIL: only $NLIB libssl rows ran (floor 79)"; FAILS=$((FAILS + 1)); }
fi
if [ "$FAILS" -ne 0 ]; then echo "FAIL: $G: $FAILS row(s)"; exit 1; fi
if [ "$LIBSSL" != 1 ]; then echo "SKIP: $G: the libssl legs could not run ($WHY); native rows PASS"; exit 77; fi
echo "PASS: $G"
exit 0

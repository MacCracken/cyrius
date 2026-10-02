#!/bin/sh
# tls_native_client_auth_openssl.sh — 6.6.14 (CVE-64). Native TLS client authentication, both
# directions, against an INDEPENDENT peer: OpenSSL's s_client presenting certificates to the
# native server, and the native TLS 1.2 client answering s_server's CertificateRequest. A peer
# that shared our code could share the defect; the native<->native matrix on every host is
# tests/tcyr/crossos/tls_native_client_auth.tcyr.
#
# ⛔ THE DEFECTS (6.6.13, each reproduced before the fix):
#   - the native TLS 1.2 server sent no CertificateRequest and ignored the verify mode, so
#     `s_client -tls1_2` with NO certificate completed against a server that required one;
#   - the native TLS 1.3 server checked possession only: a self-signed or expired leaf, or one
#     from a CA the server did not trust, was accepted as an identity;
#   - tls_set_verify turned SSL_VERIFY_PEER|SSL_VERIFY_FAIL_IF_NO_PEER_CERT into plain PEER;
#   - the native TLS 1.2 client failed `s_server -tls1_2 -Verify 1` with TLS_ERR_BAD_HANDSHAKE
#     (it could not parse a CertificateRequest), with or without a certificate of its own.
#
# LEGS
#   S  the native server (lib/tls.cyr's tls_accept_alloc + tls_accept_complete; the hook calls
#      tls_set_verify(handle, <OpenSSL mode>, 0) and tls_ctx_load_verify_locations(handle, ca))
#      against `openssl s_client -tls1_3 | -tls1_2` with -cert/-key [-cert_chain]: a leaf from the
#      trusted CA, a leaf behind an intermediate, Ed25519 and P-384 leaves, an untrusted
#      self-signed leaf, an expired leaf, a keyEncipherment-only leaf (its keyUsage permits no
#      client signature), no certificate under PEER and under PEER|FAIL. The
#      server reports its result, the client's identity through tls_get_peer_spki_der, and the
#      "ping" s_client sends after the handshake.
#   C  the native client (TLS 1.2, and 1.3 as the control) against `openssl s_server -Verify 1`
#      (a certificate REQUIRED; -verify 1 = requested) with an Ed25519 server certificate (the
#      native 1.2 client offers x25519 only, and OpenSSL refuses an ECDSA certificate on a curve
#      the client did not list — see the CHANGELOG): its P-256 / Ed25519 / P-384 certificate is
#      verified by s_server ("verify return:1" for its CN), the -rev echo comes back, and with no
#      certificate it reads s_server's alert (TLS_ERR_ALERT) — or completes when it was only asked.
# SKIP (exit 77, named): openssl(1) missing. ANTI-VACUITY: the rows run are counted and floored.
#
# MUTATION LEDGER (6.6.14, each measured RED here; the pre-fix 6.6.13 lib fails 21 of the 24 rows):
#   MA1 the CertificateRequest dropped from tls_native_12_build_server_flight -> all 8 S 1.2 rows
#   MA2 _tn_server_take_client_chain's _tn_verify_chain call removed -> the 4 untrusted / expired rows
#   MA3 tls_set_verify's FAIL bit dropped -> the 2 PEER|FAIL no-certificate rows
#   MA4 the CertificateRequest branch of _tn_12_client_consume_flight disabled -> the 4 C 1.2 REQUIRED rows
#   MA5 _tn_peer_leaf reading SERVER_CERT on a server again -> the 8 S identity rows
#   MA6 the 1.2 client signature checked as 1.3 (curve bound to the scheme) -> S 1.2 P-384
#   MA7 the client certificate's curve left out of the 1.2 supported_groups -> C 1.2 P-256 / P-384
#   MA8 the 1.2 server's FAIL_IF_NO_PEER_CERT check disabled -> S 1.2 PEER|FAIL no-certificate
#   MA9 _tn_leaf_purpose_ok's keyUsage test skipped for the client purpose -> the 2 keyEncipherment rows
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 1
G=tls_native_client_auth_openssl
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
command -v openssl >/dev/null 2>&1 || {
    echo "SKIP: $G: openssl(1) not found — the peer under test is OpenSSL's s_client / s_server"; exit 77; }

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
BGP=""
trap 'for p in $BGP; do kill "$p" 2>/dev/null || true; done; rm -rf "$T"' EXIT
FAILS=0
NROWS=0
TO=""
command -v timeout >/dev/null 2>&1 && TO="timeout 30"

# ── certificates: a CA, an untrusted self-signed leaf, an intermediate, leaves ──
q() { "$@" >/dev/null 2>&1 || { echo "FAIL: $G: setup: $*"; exit 1; }; }
printf 'basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n' > "$T/ca.ext"
printf 'basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\n' > "$T/int.ext"
printf 'basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=clientAuth\n' > "$T/cli.ext"
printf 'basicConstraints=CA:FALSE\nkeyUsage=critical,keyEncipherment\nextendedKeyUsage=clientAuth\n' > "$T/cliku.ext"
printf 'basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost\n' > "$T/srv.ext"
mkkey() {  # <name> <p256|p384|ed>
    case $2 in
        p256) q openssl ecparam -name prime256v1 -genkey -noout -out "$T/$1.key" ;;
        p384) q openssl ecparam -name secp384r1 -genkey -noout -out "$T/$1.key" ;;
        ed) q openssl genpkey -algorithm ed25519 -out "$T/$1.key" ;;
    esac
}
mkcert() {  # <name> <keytype> <CN> <issuer> <ext> [<not_before> <not_after>]
    mkkey "$1" "$2"
    q openssl req -new -key "$T/$1.key" -subj "/CN=$3" -out "$T/$1.csr"
    if [ $# -ge 7 ]; then
        q openssl x509 -req -in "$T/$1.csr" -CA "$T/$4.crt" -CAkey "$T/$4.key" -CAcreateserial \
            -not_before "$6" -not_after "$7" -extfile "$T/$5" -out "$T/$1.crt"
    else
        q openssl x509 -req -in "$T/$1.csr" -CA "$T/$4.crt" -CAkey "$T/$4.key" -CAcreateserial \
            -days 2 -extfile "$T/$5" -out "$T/$1.crt"
    fi
    q openssl x509 -in "$T/$1.crt" -outform DER -out "$T/$1.der"
    q openssl pkey -in "$T/$1.key" -outform DER -out "$T/$1.key.der"
}
selfsigned() {  # <name> <CN> <ext>
    mkkey "$1" p256
    q openssl req -x509 -new -key "$T/$1.key" -subj "/CN=$2" -days 2 \
        -addext "$(sed -n 1p "$T/$3")" -out "$T/$1.crt"
    q openssl x509 -in "$T/$1.crt" -outform DER -out "$T/$1.der"
    q openssl pkey -in "$T/$1.key" -outform DER -out "$T/$1.key.der"
}
mkkey ca p256
q openssl req -x509 -new -key "$T/ca.key" -subj /CN=gate-mtls-ca -days 2 \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" -out "$T/ca.crt"
mkcert int p256 gate-mtls-int ca int.ext
mkcert cli p256 client-one ca cli.ext
mkcert cliint p256 client-via-int int cli.ext
mkcert clied ed client-ed ca cli.ext
mkcert cli384 p384 client-p384 ca cli.ext
mkcert cliexp p256 client-expired ca cli.ext 20200101000000Z 20210101000000Z
mkcert cliku p256 client-keyencipherment ca cliku.ext
mkcert srv p256 localhost ca srv.ext
mkcert srved ed localhost ca srv.ext
selfsigned self client-self cli.ext

# ── probes ──
# srv <portfile> <cert.der> <key.der> <ca.pem> <openssl verify mode>: one native accept through
# lib/tls.cyr. Prints `accept=<1|0> err=<LAST_ERR> spki=<n> read=<n>`.
cat > "$T/srv.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/io.cyr"
include "lib/net.cyr"
include "lib/args.cyr"
include "lib/fmt.cyr"
include "lib/tls.cyr"

var G_CA = 0;
var G_MODE = 0;

fn _hook(hctx, handle): i64 {
    if (tls_set_verify(handle, G_MODE, 0) != 0) { return 1; }
    if (tls_ctx_load_verify_locations(handle, G_CA, 0) != 1) { return 1; }
    return 0;
}

fn _num(s): i64 {
    var v = 0;
    var i = 0;
    while (load8(s + i) != 0) { v = v * 10 + (load8(s + i) - 48); i = i + 1; }
    return v;
}

fn _kv(k, v): i64 {
    sys_write(1, k, strlen(k));
    print_num(v);
    sys_write(1, " ", 1);
    return 0;
}

fn main(): i64 {
    alloc_init();
    args_init();
    var cl = 0;
    var kl = 0;
    var cert = alloc(65536);
    var key = alloc(65536);
    cl = file_read_all(argv(2), cert, 65536);
    kl = file_read_all(argv(3), key, 65536);
    G_CA = argv(4);
    G_MODE = _num(argv(5));
    var lt, lfd = tcp_socket();
    if (is_err_result(lt) == 1) { return 40; }
    var bt, bv = sock_bind(lfd, INADDR_LOOPBACK(), 0);
    var st, sv = sock_listen(lfd, 1);
    var sa[16];
    var sl[8];
    store64(&sl, 16);
    if (sys_getsockname(lfd, &sa, &sl) != 0) { return 41; }
    var port = ((load8(&sa + 2) & 0xFF) << 8) | (load8(&sa + 3) & 0xFF);
    var pf = argv(1);
    var tmpbuf[32];
    var n = fmt_int_buf(port, &tmpbuf);
    file_write_all(pf, &tmpbuf, n);
    var at, afd = sock_accept(lfd);
    if (is_err_result(at) == 1) { return 42; }
    sock_set_recv_timeout(afd, 10, 0);
    var creds: i64[4];
    store64(&creds, cert);
    store64(&creds + 8, cl);
    store64(&creds + 16, key);
    store64(&creds + 24, kl);
    var sh = tls_accept_alloc(afd, &creds, &_hook, 0);
    if (sh == 0) { return 43; }
    var ok = tls_accept_complete(sh);
    _kv("accept=", ok);
    _kv("err=", tls_native_get_last_error(load64(sh)));
    var g = alloc(4096);
    _kv("spki=", tls_get_peer_spki_der(sh, g, 4096));
    var rd = 0 - 99;
    if (ok == 1) {
        var b[64];
        rd = tls_read(sh, &b, 64);
    }
    _kv("read=", rd);
    println("");
    tls_close(sh);
    sock_close(afd);
    sock_close(lfd);
    return 0;
}
var r = main();
sys_exit(r);
EOF
# cli <port> <12|13> <cert.der|-> <key.der|->: one native connect (no server verification: the
# server's chain is not under test). Prints `connect=<rc> read=<n> echo=<1|0>`.
cat > "$T/cli.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/io.cyr"
include "lib/net.cyr"
include "lib/args.cyr"
include "lib/tls.cyr"

fn _num(s): i64 {
    var v = 0;
    var i = 0;
    while (load8(s + i) != 0) { v = v * 10 + (load8(s + i) - 48); i = i + 1; }
    return v;
}

fn _kv(k, v): i64 {
    sys_write(1, k, strlen(k));
    print_num(v);
    sys_write(1, " ", 1);
    return 0;
}

fn main(): i64 {
    alloc_init();
    args_init();
    var port = _num(argv(1));
    var ver = _num(argv(2));
    var ct, fd = tcp_socket();
    if (is_err_result(ct) == 1) { return 40; }
    var kt, kv = sock_connect(fd, INADDR_LOOPBACK(), port);
    if (is_err_result(kt) == 1) { return 41; }
    sock_set_recv_timeout(fd, 10, 0);
    var c = tls_native_new_client(0, 0);
    tls_native_set_verify(c, TLS_VERIFY_NONE);
    if (ver == 12) { tls_native_set_version_range(c, TLS_VERSION_1_2, TLS_VERSION_1_2); }
    if (load8(argv(3)) != 45) {
        var cb = alloc(65536);
        var kb = alloc(65536);
        var cl = file_read_all(argv(3), cb, 65536);
        var kl = file_read_all(argv(4), kb, 65536);
        if (tls_native_set_client_cert(c, cb, cl, 1) != TLS_OK) { return 42; }
        if (tls_native_set_client_key(c, kb, kl) != TLS_OK) { return 43; }
    }
    var rc = tls_native_connect(c, fd);
    _kv("connect=", rc);
    var rd = 0 - 99;
    var echo = 0;
    if (rc == TLS_OK) {
        tls_native_write(c, "ping\n", 5);
        var b[64];
        store64(&b, 0);
        rd = tls_native_read(c, &b, 64);
        if (rd >= 4) { if (memeq(&b, "gnip", 4) == 1) { echo = 1; } }
    }
    _kv("read=", rd);
    _kv("echo=", echo);
    println("");
    tls_native_close(c);
    sock_close(fd);
    return 0;
}
var r = main();
sys_exit(r);
EOF
for p in srv cli; do
    "$CC" < "$T/$p.cyr" > "$T/$p" 2>"$T/$p.err" && chmod +x "$T/$p" || {
        echo "FAIL: $G: the $p probe did not compile"; tail -3 "$T/$p.err"; exit 1; }
done

_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }

# srow <13|12> <mode> <cert|-> <chain|-> <want: ok|refused> <spki: id|none> "<label>"
srow() {
    NROWS=$((NROWS + 1))
    _rf=$FAILS
    rm -f "$T/port" "$T/s.out" "$T/sc.out"
    $TO "$T/srv" "$T/port" "$T/srv.der" "$T/srv.key.der" "$T/ca.crt" "$2" > "$T/s.out" 2>&1 &
    _sp=$!
    BGP="$BGP $_sp"
    _w=0
    while [ ! -s "$T/port" ] && [ "$_w" -lt 50 ]; do sleep 0.1; _w=$((_w + 1)); done
    _port=$(cat "$T/port" 2>/dev/null || true)
    if [ -z "$_port" ]; then _fail "$7 — the native server published no port"; return 0; fi
    _ca=""
    [ "$3" != "-" ] && _ca="-cert $T/$3.crt -key $T/$3.key"
    [ "$4" != "-" ] && _ca="$_ca -cert_chain $T/$4.crt"
    # shellcheck disable=SC2086
    printf 'ping\n' | $TO openssl s_client -connect "127.0.0.1:$_port" "-tls1_$(echo "$1" | cut -c2)" \
        $_ca -ign_eof > "$T/sc.out" 2>&1 || true
    wait "$_sp" 2>/dev/null || true
    _s=$(cat "$T/s.out" 2>/dev/null || true)
    case "$5" in
        ok)
            case "$_s" in *"accept=1 "*) : ;; *) _fail "$7 — the server refused: $_s"; return 0 ;; esac
            case "$_s" in *"read=5 "*) : ;; *) _fail "$7 — no \"ping\" after the handshake: $_s" ;; esac
            ;;
        refused)
            case "$_s" in *"accept=0 err=-6 "*|*"accept=0 err=-16 "*) : ;; *) _fail "$7 — expected a refusal (CERT_INVALID / AUTHN): $_s"; return 0 ;; esac
            ;;
    esac
    case "$6" in
        id) case "$_s" in *"spki=0 "*) _fail "$7 — tls_get_peer_spki_der names nobody: $_s" ;; esac ;;
        none) case "$_s" in *"spki=0 "*) : ;; *) _fail "$7 — an identity where none was presented: $_s" ;; esac ;;
    esac
    [ "$FAILS" = "$_rf" ] && echo "  ok: S $7"
    return 0
}

echo "== S: the native server, OpenSSL s_client presenting =="
for V in 13 12; do
    srow "$V" 1 cli    -   ok      id   "TLS 1.$(echo $V | cut -c2): PEER, a leaf from the trusted CA"
    srow "$V" 1 cliint int ok      id   "TLS 1.$(echo $V | cut -c2): PEER, a leaf behind an intermediate (-cert_chain)"
    srow "$V" 1 clied  -   ok      id   "TLS 1.$(echo $V | cut -c2): PEER, an Ed25519 leaf"
    srow "$V" 1 cli384 -   ok      id   "TLS 1.$(echo $V | cut -c2): PEER, a P-384 leaf"
    srow "$V" 1 -      -   ok      none "TLS 1.$(echo $V | cut -c2): PEER, no certificate: no identity"
    srow "$V" 3 -      -   refused none "TLS 1.$(echo $V | cut -c2): PEER|FAIL_IF_NO_PEER_CERT, no certificate"
    srow "$V" 1 self   -   refused none "TLS 1.$(echo $V | cut -c2): PEER, an untrusted self-signed leaf"
    srow "$V" 1 cliexp -   refused none "TLS 1.$(echo $V | cut -c2): PEER, an expired leaf"
    srow "$V" 1 cliku  -   refused none "TLS 1.$(echo $V | cut -c2): PEER, a keyEncipherment-only leaf (no digitalSignature)"
done

# crow <12|13> <-verify|-Verify> <cert|-> <want: ok|alert> "<label>"
crow() {
    NROWS=$((NROWS + 1))
    _rf=$FAILS
    rm -f "$T/ss.out" "$T/c.out"
    # -rev never reads stdin, so /dev/null does not end it early, and $! is s_server itself:
    # killing it leaves nothing behind (a `sleep | s_server` subshell left its sleep running).
    $TO openssl s_server -accept 127.0.0.1:0 "-tls1_$(echo "$1" | cut -c2)" \
        -cert "$T/srved.crt" -key "$T/srved.key" -CAfile "$T/ca.crt" "$2" 1 -naccept 1 -rev \
        < /dev/null > "$T/ss.out" 2>&1 &
    _sp=$!
    BGP="$BGP $_sp"
    _w=0
    _port=""
    while [ -z "$_port" ] && [ "$_w" -lt 50 ]; do
        sleep 0.1
        _w=$((_w + 1))
        _port=$(sed -n 's/^ACCEPT .*:\([0-9][0-9]*\)$/\1/p' "$T/ss.out" 2>/dev/null | head -1 || true)
    done
    if [ -z "$_port" ]; then _fail "$5 — s_server did not start: $(head -3 "$T/ss.out")"; return 0; fi
    if [ "$3" = "-" ]; then
        $TO "$T/cli" "$_port" "$1" - - > "$T/c.out" 2>&1 || true
    else
        $TO "$T/cli" "$_port" "$1" "$T/$3.der" "$T/$3.key.der" > "$T/c.out" 2>&1 || true
    fi
    sleep 0.3
    kill "$_sp" 2>/dev/null || true
    wait "$_sp" 2>/dev/null || true
    _c=$(cat "$T/c.out" 2>/dev/null || true)
    case "$4" in
        ok)
            case "$_c" in *"connect=0 "*) : ;; *) _fail "$5 — the native client failed: $_c"; return 0 ;; esac
            case "$_c" in *"echo=1 "*) : ;; *) _fail "$5 — no reversed echo from s_server: $_c" ;; esac
            if [ "$3" != "-" ]; then
                _cn=$(openssl x509 -in "$T/$3.crt" -noout -subject | sed 's/.*CN *= *//')
                grep -q "CN *= *$_cn" "$T/ss.out" || _fail "$5 — s_server did not verify the client's $_cn"
                if grep -q "verify error" "$T/ss.out"; then _fail "$5 — s_server: $(grep 'verify error' "$T/ss.out" | head -1)"; fi
            fi
            ;;
        alert)
            case "$_c" in *"connect=-17 "*) : ;; *) _fail "$5 — expected TLS_ERR_ALERT: $_c" ;; esac
            ;;
    esac
    [ "$FAILS" = "$_rf" ] && echo "  ok: C $5"
    return 0
}

echo "== C: the native client, OpenSSL s_server asking =="
crow 12 -Verify cli    ok    "TLS 1.2, a certificate REQUIRED: the native P-256 certificate"
crow 12 -Verify clied  ok    "TLS 1.2, REQUIRED: an Ed25519 certificate"
crow 12 -Verify cli384 ok    "TLS 1.2, REQUIRED: a P-384 certificate"
crow 12 -Verify -      alert "TLS 1.2, REQUIRED, the native client has none: it reads s_server's alert"
crow 12 -verify -      ok    "TLS 1.2, REQUESTED, none: the empty Certificate completes"
crow 13 -Verify cli    ok    "TLS 1.3 control, REQUIRED: the native P-256 certificate"

FLOOR=24
if [ "$NROWS" -lt "$FLOOR" ]; then
    echo "  FAIL: $G: only $NROWS rows ran (floor $FLOOR)"; FAILS=$((FAILS + 1)); fi
if [ "$FAILS" -ne 0 ]; then echo "FAIL: $G: $FAILS failure(s) in $NROWS rows"; exit 1; fi
echo "PASS: $G: $NROWS rows"
exit 0

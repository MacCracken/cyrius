#!/bin/sh
# tls_native_client_auth_openssl.sh — 6.6.14 (CVE-64). Native TLS client authentication, both
# directions, against an INDEPENDENT peer: OpenSSL's s_client presenting certificates to the
# native server, and the native TLS 1.2 client answering s_server's CertificateRequest. A peer
# that shared our code could share the defect; the native<->native matrix on every host is
# tests/tcyr/crossos/tls_native_client_auth.tcyr. 6.6.15 adds the key exchange — ECDHE on
# secp256r1 / secp384r1 in both roles and versions and the HelloRetryRequest both ways (legs E, H
# and G); its native<->native matrix is tests/tcyr/crossos/tls_native_ecdhe_groups.tcyr.
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
#      (a certificate REQUIRED; -verify 1 = requested) with an Ed25519 server certificate: its
#      P-256 / Ed25519 / P-384 certificate is verified by s_server ("verify return:1" for its CN),
#      the -rev echo comes back, and with no certificate it reads s_server's alert (TLS_ERR_ALERT)
#      — or completes when it was only asked.
#   E  (6.6.15) the native TLS 1.2 client's ECDHE on secp256r1 / secp384r1, each row asserting the
#      group it negotiated (tls_native_get_group): a server ranking P-256 above X25519, with and
#      without a client certificate held (6.6.14 FAILED the first — the documented trade-off this
#      gate pinned); servers offering only P-256 or only P-384; ECDSA P-256 and P-384 SERVER
#      certificates (6.6.14: "no shared cipher" — the curve was never listed), on X25519 and on
#      their own curve, the P-384 one signing its ServerKeyExchange with SHA-256 (0x0403, which in
#      TLS 1.2 names only the hash); and mTLS over P-384 end to end. An RSA-2048 SERVER certificate
#      (ECDHE-RSA, the commonest 1.2 deployment) on X25519, P-256 and P-384; the SHA-384 PRF with
#      secp384r1's 48-byte premaster (ECDHE-ECDSA-AES256-GCM-SHA384), with extended master secret
#      and — where s_server has -no_ems (3.6 does; 3.0, Ubuntu 24.04 / Debian 12, rejects it as an
#      unknown option, so there that one row is SKIPPED by name and the floor drops by one) — with
#      the legacy master secret.
#   H  (6.6.15) the native TLS 1.3 client against `s_server -tls1_3 -groups ...`, each row asserting
#      the group it negotiated and whether it took a HelloRetryRequest: P-256 only and P-384 only
#      (a HelloRetryRequest each — the client shares x25519), P-256:X25519 (no round trip: OpenSSL
#      takes the x25519 share), X448:P-384, -no_middlebox (no CCS after the HelloRetryRequest), ECDSA
#      P-384 and RSA server certificates on the other curve, mTLS with a P-384 client certificate
#      after a HelloRetryRequest, and P-521 only (no shared group: s_server's alert).
#   G  (6.6.15) the native SERVER against `s_client -tls1_3 | -tls1_2 -groups ...`, asserting the
#      server's group and HelloRetryRequest: P-256 only, P-384 only, P-521 only (handshake_failure,
#      both versions), P-256:X25519 (1.3: the P-256 share taken; 1.2: the server's x25519), the
#      HelloRetryRequest from the native side (s_client X448:P-256, secp521r1:P-384, and a server
#      restricted to P-384 — tls_native_set_groups in the probe's hook), a server preferring P-384,
#      and ECDSA certificates on the other curve. An Ed25519 server certificate unless named:
#      OpenSSL's 1.2 client refuses an ECDSA certificate whose curve is missing from its own -groups.
#      Every TLS 1.3 row that completes also checks the server's middlebox-compatibility CCS (RFC
#      8446 §D.4) through s_client -msg: exactly one, right after its first handshake message, and
#      none for s_client -no_middlebox (an empty session id).
# SKIP (exit 77, named): openssl(1) missing. ANTI-VACUITY: the rows run are counted and floored.
#
# MUTATION LEDGER (6.6.14, each measured RED here; the pre-fix 6.6.13 lib fails 22 of the 27 rows —
# one of them the trade-off row, which 6.6.13 passed by never listing the curve):
#   MA1 the CertificateRequest dropped from tls_native_12_build_server_flight -> all 8 S 1.2 rows
#   MA2 _tn_server_take_client_chain's _tn_verify_chain call removed -> the 4 untrusted / expired rows
#   MA3 tls_set_verify's FAIL bit dropped -> the 2 PEER|FAIL no-certificate rows
#   MA4 the CertificateRequest branch of _tn_12_client_consume_flight disabled -> the 4 C 1.2 REQUIRED rows
#   MA5 _tn_peer_leaf reading SERVER_CERT on a server again -> the 8 S identity rows
#   MA6 the 1.2 client signature checked as 1.3 (curve bound to the scheme) -> S 1.2 P-384
#   MA7 the client certificate's curve left out of the 1.2 supported_groups -> C 1.2 P-256 / P-384
#       (6.6.15: the list no longer depends on the certificate — ME1 is its successor)
#   MA8 the 1.2 server's FAIL_IF_NO_PEER_CERT check disabled -> S 1.2 PEER|FAIL no-certificate
#   MA9 _tn_leaf_purpose_ok's keyUsage test skipped for the client purpose -> the 2 keyEncipherment rows
# MUTATION LEDGER (6.6.15, each measured RED here against the first 34 rows; the 6.6.14 lib fails
# 9 of them — every E row except "X25519 ranked first" — and 4 of the 5 rows the fix pass added,
# all but the RSA certificate on X25519):
#   ME1 the 1.2 supported_groups back to x25519 alone -> 11 rows: those 9, and the two C 1.2
#       REQUIRED rows holding a P-256 / P-384 certificate (OpenSSL: "wrong curve")
#   ME2 _tn_12_parse_server_kex x25519-only again -> the 7 E rows negotiating secp256r1 / secp384r1
#   ME3 the SKE signature read as 1.3 reads it (curve bound to the scheme) -> the 3 P-384
#       server-certificate rows
#   ME4 secp384r1's premaster computed on P-256 -> the 3 rows negotiating secp384r1
#   ME5 the ClientKeyExchange point length off by one -> 14 rows: every 1.2 row that completes a
#       handshake, x25519 included (the builder is shared)
#   ME6 (measured on all 39) secp384r1's premaster length taken as 32 -> the 6 rows negotiating
#       secp384r1, the SHA-384 PRF row and the legacy-master row among them
# MUTATION LEDGER (6.6.15, the H and G legs; eac97bb2's lib fails 21 of their 24 rows — all but
# the three that negotiate x25519 or end in s_server's alert — and the 39 rows above stay green):
#   MH1 the transcript after a HelloRetryRequest starts with ClientHello1 itself, not message_hash
#       (RFC 8446 §4.4.1; both native sides share the helper, so only an independent peer sees
#       it) -> the 10 rows with a HelloRetryRequest
#   MH2 the server reads the second ClientHello refusing a CCS -> the 3 G rows with a native
#       HelloRetryRequest (s_client sends its middlebox CCS before the second ClientHello)
# MUTATION LEDGER (6.6.15 review pass, the G rows it added and the CCS check every G 1.3 row makes):
#   MH3 the server's RFC 8446 §D.4 CCS never sent -> the 7 G TLS 1.3 rows that complete, all but
#       the -no_middlebox one
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
        rsa) q openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$T/$1.key" ;;
    esac
}
# A certificate with a chosen validity window (the expired leaf) is issued by `openssl ca`, whose
# -startdate / -enddate every OpenSSL 3.x has: `x509 -req -not_before / -not_after` exist only from
# 3.4, and on 3.0 (Ubuntu 24.04, Debian 12) the setup step failed the whole gate.
mkdir "$T/ca.new"
: > "$T/ca.index"
echo 1000 > "$T/ca.serial"
printf '[ ca ]\ndefault_ca = gate\n[ gate ]\ndatabase = %s/ca.index\nnew_certs_dir = %s/ca.new\nserial = %s/ca.serial\ndefault_md = sha256\npolicy = gate_policy\nunique_subject = no\n[ gate_policy ]\ncommonName = supplied\n' \
    "$T" "$T" "$T" > "$T/ca.cnf"
mkcert() {  # <name> <keytype> <CN> <issuer> <ext> [<not_before> <not_after>, UTCTime YYMMDDHHMMSSZ]
    mkkey "$1" "$2"
    q openssl req -new -key "$T/$1.key" -subj "/CN=$3" -out "$T/$1.csr"
    if [ $# -ge 7 ]; then
        q openssl ca -batch -config "$T/ca.cnf" -cert "$T/$4.crt" -keyfile "$T/$4.key" -in "$T/$1.csr" \
            -notext -startdate "$6" -enddate "$7" -extfile "$T/$5" -out "$T/$1.crt"
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
mkcert cliexp p256 client-expired ca cli.ext 200101000000Z 210101000000Z
mkcert cliku p256 client-keyencipherment ca cliku.ext
mkcert srv p256 localhost ca srv.ext
mkcert srv384 p384 localhost ca srv.ext
mkcert srved ed localhost ca srv.ext
mkcert srvrsa rsa localhost ca srv.ext
selfsigned self client-self cli.ext

# ── probes ──
# srv <portfile> <cert.der> <key.der> <ca.pem> <openssl verify mode> [<groups: "23,24" | ->]: one
# native accept through lib/tls.cyr; the hook installs the groups with tls_native_set_groups.
# Prints `accept=<1|0> err=<LAST_ERR> group=<TlsNamedGroup> hrr=<1|0> spki=<n> read=<n>`.
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
var G_GROUPS: i64[3];
var G_NG = 0;

fn _hook(hctx, handle): i64 {
    if (tls_set_verify(handle, G_MODE, 0) != 0) { return 1; }
    if (tls_ctx_load_verify_locations(handle, G_CA, 0) != 1) { return 1; }
    if (G_NG > 0) {
        if (tls_native_set_groups(handle, &G_GROUPS, G_NG) != TLS_OK) { return 1; }
    }
    return 0;
}

# "23,24" -> G_GROUPS / G_NG (decimal TlsNamedGroup values; "-" = the default list)
fn _groups(s): i64 {
    if (load8(s) == 45) { return 0; }
    var v = 0;
    var i = 0;
    while (1 == 1) {
        var ch = load8(s + i);
        if (ch == 44) { G_GROUPS[G_NG] = v; G_NG = G_NG + 1; v = 0; }
        elif (ch == 0) { G_GROUPS[G_NG] = v; G_NG = G_NG + 1; return 0; }
        else { v = v * 10 + (ch - 48); }
        i = i + 1;
    }
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
    if (argc() > 6) { _groups(argv(6)); }
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
    _kv("group=", tls_native_get_group(load64(sh)));
    _kv("hrr=", load64(load64(sh) + TLS_CTX_OFF_HRR));
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
# server's chain is not under test). Prints `connect=<rc> group=<TlsNamedGroup> hrr=<1|0> read=<n>
# echo=<1|0>`.
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
    _kv("group=", tls_native_get_group(c));
    _kv("hrr=", load64(c + TLS_CTX_OFF_HRR));
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

# crow <12|13> <-verify|-Verify|-> <cert|-> <want: ok|alert|hsfail> "<label>" [<s_server flags>
#      [<group the client must report, decimal, or -> [<server certificate, default srved>
#      [<1|0: the client took a HelloRetryRequest, or ->]]]]
# (`-` for the verify flag: s_server asks for no certificate.)
crow() {
    NROWS=$((NROWS + 1))
    _rf=$FAILS
    rm -f "$T/ss.out" "$T/c.out"
    _vf=""
    [ "$2" != "-" ] && _vf="$2 1"
    # -rev never reads stdin, so /dev/null does not end it early, and $! is s_server itself:
    # killing it leaves nothing behind (a `sleep | s_server` subshell left its sleep running).
    # shellcheck disable=SC2086
    $TO openssl s_server -accept 127.0.0.1:0 "-tls1_$(echo "$1" | cut -c2)" \
        -cert "$T/${8:-srved}.crt" -key "$T/${8:-srved}.key" -CAfile "$T/ca.crt" $_vf ${6:-} -naccept 1 -rev \
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
            if [ "${7:--}" != "-" ]; then
                case "$_c" in *"group=$7 "*) : ;; *) _fail "$5 — expected group $7: $_c" ;; esac
            fi
            if [ "${9:--}" != "-" ]; then
                case "$_c" in *"hrr=$9 "*) : ;; *) _fail "$5 — expected hrr=$9: $_c" ;; esac
            fi
            if [ "$3" != "-" ] && [ "$2" != "-" ]; then
                _cn=$(openssl x509 -in "$T/$3.crt" -noout -subject | sed 's/.*CN *= *//')
                grep -q "CN *= *$_cn" "$T/ss.out" || _fail "$5 — s_server did not verify the client's $_cn"
                if grep -q "verify error" "$T/ss.out"; then _fail "$5 — s_server: $(grep 'verify error' "$T/ss.out" | head -1)"; fi
            fi
            ;;
        alert)
            case "$_c" in *"connect=-17 "*) : ;; *) _fail "$5 — expected TLS_ERR_ALERT: $_c" ;; esac
            ;;
        hsfail)
            case "$_c" in *"connect=-2 "*) : ;; *) _fail "$5 — expected TLS_ERR_HANDSHAKE_FAILED: $_c" ;; esac
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

echo "== E: the native TLS 1.2 client's ECDHE on secp256r1 / secp384r1 (6.6.15) =="
# Groups by number: x25519 29, secp256r1 23, secp384r1 24.
# ⛔ 6.6.14 pinned the first row as hsfail — the documented trade-off: the client listed its P-256
# certificate's curve but did ECDHE on x25519 alone, so a server ranking P-256 first failed it.
crow 12 -      cli    ok "TLS 1.2, not asked, P-256 certificate held: P-256 ranked first negotiates secp256r1" "-groups P-256:X25519 -serverpref" 23
crow 12 -      -      ok "TLS 1.2, no certificate: P-256 ranked first negotiates secp256r1" "-groups P-256:X25519 -serverpref" 23
crow 12 -      cli    ok "TLS 1.2, P-256 certificate held: X25519 ranked first still negotiates x25519" "-groups X25519:P-256 -serverpref" 29
crow 12 -      -      ok "TLS 1.2, a server offering only P-256" "-groups P-256" 23
crow 12 -      -      ok "TLS 1.2, a server offering only P-384" "-groups P-384" 24
crow 12 -      -      ok "TLS 1.2, an ECDSA P-256 server certificate (6.6.14: no shared cipher)" "" 29 srv
crow 12 -      -      ok "TLS 1.2, an ECDSA P-256 server certificate, ECDHE on P-256" "-groups P-256" 23 srv
crow 12 -      -      ok "TLS 1.2, an ECDSA P-384 server certificate (its SKE signs SHA-256: 0x0403)" "" 29 srv384
crow 12 -      -      ok "TLS 1.2, an ECDSA P-384 server certificate, ECDHE on P-384" "-groups P-384" 24 srv384
crow 12 -Verify cli384 ok "TLS 1.2, REQUIRED: P-384 client and server certificates, ECDHE on P-384" "-groups P-384" 24 srv384
crow 12 -      -      ok "TLS 1.2, an RSA-2048 server certificate (ECDHE-RSA) on X25519" "" 29 srvrsa
crow 12 -      -      ok "TLS 1.2, an RSA-2048 server certificate, ECDHE on P-256" "-groups P-256" 23 srvrsa
crow 12 -      -      ok "TLS 1.2, an RSA-2048 server certificate, ECDHE on P-384" "-groups P-384" 24 srvrsa
crow 12 -      -      ok "TLS 1.2, the SHA-384 PRF over secp384r1's 48-byte premaster (AES256-GCM-SHA384)" \
    "-groups P-384 -cipher ECDHE-ECDSA-AES256-GCM-SHA384" 24 srv384
# s_server -no_ems: OpenSSL 3.0 (Ubuntu 24.04, Debian 12) rejects it as an unknown option. Probed into
# a file, not a pipe: `s_server -help | grep -q` under pipefail reads a SIGPIPE'd s_server as "absent".
NOEMS_SKIP=0
openssl s_server -no_ems -help > "$T/noems.out" 2>&1 || true
if grep -q "Unknown option" "$T/noems.out"; then
    NOEMS_SKIP=1
    echo "  skip: C TLS 1.2, the legacy master secret over secp384r1 — $(openssl version | cut -d' ' -f1-2) has no s_server -no_ems"
else
    crow 12 -      -      ok "TLS 1.2, the legacy master secret (no EMS) over secp384r1's 48-byte premaster, SHA-384 PRF" \
        "-groups P-384 -no_ems -cipher ECDHE-ECDSA-AES256-GCM-SHA384" 24 srv384
fi

echo "== H: the native TLS 1.3 client's groups and HelloRetryRequest, OpenSSL s_server choosing (6.6.15) =="
# ⛔ 6.6.14 / eac97bb2: every row asking for P-256 or P-384 failed — the 1.3 client offered x25519
# alone and refused every HelloRetryRequest (s_server: "no suitable key share"; connect -17).
crow 13 -      -      ok "TLS 1.3, s_server taking only P-256: a HelloRetryRequest, then P-256" "-groups P-256" 23 srved 1
crow 13 -      -      ok "TLS 1.3, s_server taking only P-384: a HelloRetryRequest, then P-384" "-groups P-384" 24 srved 1
crow 13 -      -      ok "TLS 1.3, s_server P-256:X25519 takes the client's x25519 share (no round trip)" "-groups P-256:X25519" 29 srved 0
crow 13 -      -      ok "TLS 1.3, s_server X448:P-384: a HelloRetryRequest for P-384" "-groups X448:P-384" 24 srved 1
crow 13 -      -      ok "TLS 1.3, a HelloRetryRequest without middlebox CCS (-no_middlebox)" "-groups P-256 -no_middlebox" 23 srved 1
crow 13 -      -      ok "TLS 1.3, an ECDSA P-384 server certificate, ECDHE on P-256 after a HelloRetryRequest" "-groups P-256" 23 srv384 1
crow 13 -      -      ok "TLS 1.3, an RSA-2048 server certificate (RSA-PSS), ECDHE on P-384" "-groups P-384" 24 srvrsa 1
crow 13 -Verify cli384 ok "TLS 1.3, REQUIRED: a P-384 client certificate, ECDHE on P-384 after a HelloRetryRequest" "-groups P-384" 24 srved 1
crow 13 -      -      alert "TLS 1.3, s_server taking only P-521: the client's groups share none" "-groups P-521"

# grow <13|12> "<s_client -groups>" <server cert> <server groups: "23,24" | -> <want: ok|fail> <group> <hrr: 1|0|-> "<label>"
#      [<more s_client flags>]
# The native server (no client authentication) against `openssl s_client -tls1_N -groups ... -msg`.
# A TLS 1.3 row that completes also checks the server's middlebox-compatibility CCS (RFC 8446
# §D.4): s_client sends a 32-byte legacy_session_id unless -no_middlebox, and then must receive
# exactly one CCS, directly after the server's first handshake message (the HelloRetryRequest or
# the ServerHello); with -no_middlebox, none.
grow() {
    NROWS=$((NROWS + 1))
    _rf=$FAILS
    rm -f "$T/port" "$T/s.out" "$T/sc.out"
    $TO "$T/srv" "$T/port" "$T/$3.der" "$T/$3.key.der" "$T/ca.crt" 0 "$4" > "$T/s.out" 2>&1 &
    _sp=$!
    BGP="$BGP $_sp"
    _w=0
    while [ ! -s "$T/port" ] && [ "$_w" -lt 50 ]; do sleep 0.1; _w=$((_w + 1)); done
    _port=$(cat "$T/port" 2>/dev/null || true)
    if [ -z "$_port" ]; then _fail "$8 — the native server published no port"; return 0; fi
    # shellcheck disable=SC2086
    printf 'ping\n' | $TO openssl s_client -connect "127.0.0.1:$_port" "-tls1_$(echo "$1" | cut -c2)" \
        -groups "$2" -msg ${9:-} -ign_eof > "$T/sc.out" 2>&1 || true
    wait "$_sp" 2>/dev/null || true
    _s=$(cat "$T/s.out" 2>/dev/null || true)
    case "$5" in
        ok)
            case "$_s" in *"accept=1 "*) : ;; *) _fail "$8 — the server failed: $_s"; return 0 ;; esac
            case "$_s" in *"read=5 "*) : ;; *) _fail "$8 — no \"ping\" after the handshake: $_s" ;; esac
            case "$_s" in *"group=$6 "*) : ;; *) _fail "$8 — expected group $6: $_s" ;; esac
            if [ "$7" != "-" ]; then
                case "$_s" in *"hrr=$7 "*) : ;; *) _fail "$8 — expected hrr=$7: $_s" ;; esac
            fi
            if [ "$1" = "13" ]; then
                _wccs=1
                case "${9:-}" in *-no_middlebox*) _wccs=0 ;; esac
                _nccs=$(grep -c '^<<< .*ChangeCipherSpec' "$T/sc.out" || true)
                [ "$_nccs" = "$_wccs" ] || _fail "$8 — s_client received $_nccs CCS from the server, expected $_wccs (RFC 8446 §D.4)"
                if [ "$_wccs" = 1 ]; then
                    _m2=$(grep '^<<< ' "$T/sc.out" | grep -v RecordHeader | sed -n 2p || true)
                    case "$_m2" in *ChangeCipherSpec*) : ;; *) _fail "$8 — the server's second message is not its CCS: $_m2" ;; esac
                fi
            fi
            ;;
        fail)
            case "$_s" in *"accept=0 err=-2 "*) : ;; *) _fail "$8 — expected TLS_ERR_HANDSHAKE_FAILED: $_s"; return 0 ;; esac
            grep -q "alert handshake failure" "$T/sc.out" || _fail "$8 — s_client saw no handshake_failure alert"
            ;;
    esac
    [ "$FAILS" = "$_rf" ] && echo "  ok: G $8"
    return 0
}

echo "== G: the native server's groups and HelloRetryRequest, OpenSSL s_client choosing (6.6.15) =="
# ⛔ 6.6.14 / eac97bb2: the 1.2 server sent x25519 to every client (s_client -groups P-256: "wrong
# curve", accept -17) and the 1.3 server refused any client without an x25519 share (accept -2,
# no alert) — even -groups P-256:X25519, whose HelloRetryRequest the driver refused to send.
# Groups by number: x25519 29, secp256r1 23, secp384r1 24. An Ed25519 server certificate unless
# named: OpenSSL's TLS 1.2 client also refuses an ECDSA certificate whose curve is not in its own
# -groups ("wrong curve", RFC 8422 §5.1.1), which is about the certificate, not the key exchange.
for V in 13 12; do
    grow "$V" P-256         srved - ok 23 0 "TLS 1.$(echo $V | cut -c2): s_client P-256 only"
    grow "$V" P-384         srved - ok 24 0 "TLS 1.$(echo $V | cut -c2): s_client P-384 only"
    grow "$V" P-521         srved - fail 0 - "TLS 1.$(echo $V | cut -c2): s_client P-521 only: handshake_failure"
done
grow 13 P-256:X25519   srved - ok 23 0 "TLS 1.3: s_client P-256:X25519 shares P-256, which the server takes (6.6.14: accept -2)"
grow 12 P-256:X25519   srved - ok 29 - "TLS 1.2: s_client P-256:X25519, the server's preference: x25519"
grow 13 X448:P-256     srved - ok 23 1 "TLS 1.3: s_client X448:P-256 shares X448: the server's HelloRetryRequest, then P-256"
grow 13 secp521r1:P-384 srved - ok 24 1 "TLS 1.3: s_client secp521r1:P-384: a HelloRetryRequest for P-384"
grow 13 P-256:P-384    srved 24 ok 24 1 "TLS 1.3: a server taking only P-384, s_client sharing P-256: a HelloRetryRequest"
grow 12 P-256:P-384    srved 24,23 ok 24 - "TLS 1.2: a server preferring P-384: P-384"
grow 13 P-256          srv384 - ok 23 0 "TLS 1.3: an ECDSA P-384 server certificate, ECDHE on P-256"
grow 12 P-256:P-384    srv384 - ok 23 - "TLS 1.2: an ECDSA P-384 server certificate signs a P-256 ServerKeyExchange"
grow 12 P-384:P-256    srv    - ok 23 - "TLS 1.2: an ECDSA P-256 server certificate, P-384 listed first: P-256 (server preference)"
grow 13 P-256          srved - ok 23 0 "TLS 1.3: s_client -no_middlebox (an empty session id): no CCS from the server" \
    "-no_middlebox"

FLOOR=$((39 + 9 + 16 - NOEMS_SKIP))
if [ "$NROWS" -lt "$FLOOR" ]; then
    echo "  FAIL: $G: only $NROWS rows ran (floor $FLOOR)"; FAILS=$((FAILS + 1)); fi
if [ "$FAILS" -ne 0 ]; then echo "FAIL: $G: $FAILS failure(s) in $NROWS rows"; exit 1; fi
echo "PASS: $G: $NROWS rows"
exit 0

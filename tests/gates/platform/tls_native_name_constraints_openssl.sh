#!/bin/sh
# tls_native_name_constraints_openssl.sh — 6.7.18 (CYRIUS-2026-0042, the native-TLS side). A native
# TLS client CONNECTING, verification on, to `openssl s_server` presenting a chain through a
# name-constrained CA: the audit's end-to-end repro, against an independent peer.
#
# ⛔ THE DEFECT (docs/audit/2026-10-22-security-audit.md): the native chain verifier never read a
# CA's nameConstraints, so the audit's nc_e2e — the native client trusting one root, `s_server
# -cert leaf(victim-bank.test) -cert_chain <sub-CA constrained to permitted;DNS:good.test,
# non-critical>` — printed `tls_native_connect -> 0`, negotiated TLS 1.3 and read `HTTP/1.0 200
# ok`, where `openssl s_client -verify_hostname victim-bank.test` failed num=47 (permitted subtree
# violation). sigil 3.13.14's link check catches the DIRECT issuer's constraints; the walker
# (_tn_verify_chain, _tn_nc_below_ok) applies every CA's, the trust anchor's included, to everything
# below it. The verdict table at every depth, offline on every host target, is
# tests/tcyr/crossos/tls_native_name_constraints.tcyr.
#
# ROWS — the native client (TLS 1.3) against `s_server -naccept 1 -rev`; each row
# also asks `openssl verify -purpose sslserver` for its verdict on the same files, and a row whose
# native verdict differs from OpenSSL's fails unless it is the named divergence:
#   the audit's repro: victim-bank.test <- int_nc (non-critical permitted;DNS:good.test) <- root
#     REFUSED (TLS_ERR_CERT_INVALID, -6); the same under int_ncc (critical) REFUSED;
#   permitted: www.good.test <- int_nc and <- int_ncc (critical: sigil 3.13.13 refused the CA at
#     parse) connect and echo;
#   excluded: x.bad.good.test <- int_ex (excluded;DNS:bad.good.test) REFUSED;
#   the ANCHOR: root_nc (critical permitted;DNS:good.test, root's subject and key) trusted:
#     victim-bank.test <- int_plain REFUSED, www.good.test <- int_plain connects;
#   an UPPER CA: victim-bank.test <- nc-lower <- int_nc REFUSED, www.good.test <- nc-lower <- int_nc
#     connects;
#   the trailing dot: the client dials `victim-bank.test.`, the leaf's SAN is `victim-bank.test.`
#     (so the literal hostname check passes), under nc-lower <- int_xv (excluded;DNS:victim-bank.test)
#     REFUSED — OpenSSL 3.6.5 compares literally and lets it out (the named divergence);
#   control: victim-bank.test <- int_plain <- root connects (the PKI is sound without constraints).
# SKIP (exit 77, named): openssl(1) missing. ANTI-VACUITY: the rows run are counted and floored.
#
# MEASURED RED (6.7.18): with l6718-integ's lib/ (sigil 3.13.13, no walker check) 5 rows fail —
# the audit's repro and the upper-CA refusal connect (and echo), and every row through a CRITICAL
# constraint fails to install or parse it (int_ncc's permitted row, both anchor rows); with sigil
# 3.13.14 refolded and no walker check 3 fail — the anchor, upper-CA and trailing-dot refusals
# connect (the direct issuer's constraints are already caught by sigil's link check).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 1
G=tls_native_name_constraints_openssl
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
command -v openssl >/dev/null 2>&1 || {
    echo "SKIP: $G: openssl(1) not found — the peer under test is OpenSSL's s_server"; exit 77; }

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
BGP=""
trap 'for p in $BGP; do kill "$p" 2>/dev/null || true; done; rm -rf "$T"' EXIT
FAILS=0
NROWS=0
FLOOR=12
TO=""
command -v timeout >/dev/null 2>&1 && TO="timeout 30"

# ── the PKI (P-256; families share a subject and a key, so the constraint is a row's only variable) ──
q() { "$@" >/dev/null 2>&1 || { echo "FAIL: $G: setup: $*"; exit 1; }; }
cat > "$T/ext.cnf" <<'EOF'
[ root_nc ]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
nameConstraints = critical,permitted;DNS:good.test
[ int_nc ]
basicConstraints = critical,CA:TRUE,pathlen:1
keyUsage = critical,keyCertSign,cRLSign
nameConstraints = permitted;DNS:good.test
[ int_ncc ]
basicConstraints = critical,CA:TRUE,pathlen:1
keyUsage = critical,keyCertSign,cRLSign
nameConstraints = critical,permitted;DNS:good.test
[ int_plain ]
basicConstraints = critical,CA:TRUE,pathlen:1
keyUsage = critical,keyCertSign,cRLSign
[ int_ex ]
basicConstraints = critical,CA:TRUE,pathlen:1
keyUsage = critical,keyCertSign,cRLSign
nameConstraints = critical,excluded;DNS:bad.good.test
[ int_xv ]
basicConstraints = critical,CA:TRUE,pathlen:1
keyUsage = critical,keyCertSign,cRLSign
nameConstraints = critical,excluded;DNS:victim-bank.test
[ lower ]
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
EOF
for s in "victim DNS:victim-bank.test" "www DNS:www.good.test" "bad DNS:x.bad.good.test" "dot DNS:victim-bank.test."; do
    # shellcheck disable=SC2086
    set -- $s
    printf '[ l_%s ]\nbasicConstraints = critical,CA:FALSE\nkeyUsage = critical,digitalSignature\nextendedKeyUsage = serverAuth\nsubjectAltName = %s\n' \
        "$1" "$2" >> "$T/ext.cnf"
done
for k in root int low leaf; do q openssl ecparam -name prime256v1 -genkey -noout -out "$T/$k.key"; done
q openssl req -x509 -new -key "$T/root.key" -subj /CN=nc-gate-root -days 2 \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" -out "$T/root.pem"
q openssl req -new -key "$T/root.key" -subj /CN=nc-gate-root -out "$T/root_nc.csr"
q openssl x509 -req -in "$T/root_nc.csr" -signkey "$T/root.key" -days 2 -extfile "$T/ext.cnf" -extensions root_nc \
    -out "$T/root_nc.pem"
SER=100
# sign <name> <CN> <issuer cert> <issuer key> <section> <subject key>
sign() {
    SER=$((SER + 1))
    q openssl req -new -key "$T/$6.key" -subj "/CN=$2" -out "$T/$1.csr"
    q openssl x509 -req -in "$T/$1.csr" -CA "$T/$3.pem" -CAkey "$T/$4.key" -set_serial "$SER" -days 2 \
        -extfile "$T/ext.cnf" -extensions "$5" -out "$T/$1.pem"
}
for v in int_nc int_ncc int_plain int_ex int_xv; do sign "$v" nc-gate-int root root "$v" int; done
sign lower nc-gate-lower int_plain int lower low
sign leaf_victim leaf-victim int_plain int l_victim leaf
sign leaf_www leaf-www int_plain int l_www leaf
sign leaf_bad leaf-bad int_plain int l_bad leaf
sign leaf_l_victim leaf-l-victim lower low l_victim leaf
sign leaf_l_www leaf-l-www lower low l_www leaf
sign leaf_l_dot leaf-l-dot lower low l_dot leaf

# ── the native client: cli <port> <host> <trust root .pem> <12|13> ──
# Verification ON (the default), the one root installed with tls_native_set_ca_bundle. Prints
# `connect=<rc> echo=<1|0>`.
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
    var host = argv(2);
    var pem = alloc(65536);
    var pl = file_read_all(argv(3), pem, 65536);
    if (pl <= 0) { return 44; }
    var ver = _num(argv(4));
    var ct, fd = tcp_socket();
    if (is_err_result(ct) == 1) { return 40; }
    var kt, kv = sock_connect(fd, INADDR_LOOPBACK(), port);
    if (is_err_result(kt) == 1) { return 41; }
    sock_set_recv_timeout(fd, 10, 0);
    var c = tls_native_new_client(host, strlen(host));
    if (tls_native_set_ca_bundle(c, pem, pl, 0) != TLS_OK) { return 42; }
    if (ver == 12) { tls_native_set_version_range(c, TLS_VERSION_1_2, TLS_VERSION_1_2); }
    var rc = tls_native_connect(c, fd);
    _kv("connect=", rc);
    var echo = 0;
    if (rc == TLS_OK) {
        tls_native_write(c, "ping\n", 5);
        var b[64];
        store64(&b, 0);
        var rd = tls_native_read(c, &b, 64);
        if (rd >= 4) { if (memeq(&b, "gnip", 4) == 1) { echo = 1; } }
    }
    _kv("echo=", echo);
    println("");
    tls_native_close(c);
    sock_close(fd);
    return 0;
}
var r = main();
sys_exit(r);
EOF
"$CC" < "$T/cli.cyr" > "$T/cli" 2>"$T/cli.err" && chmod +x "$T/cli" || {
    echo "FAIL: $G: the client probe did not compile"; tail -3 "$T/cli.err"; exit 1; }

_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }

# row <12|13> <trust root> <leaf> <chain: a,b | -> <host> <want: ok|refused> <openssl: ok|47|48|ok-diverges> "<label>"
row() {
    NROWS=$((NROWS + 1))
    _rf=$FAILS
    : > "$T/chain.pem"
    if [ "$4" != "-" ]; then
        for c in $(echo "$4" | tr ',' ' '); do cat "$T/$c.pem" >> "$T/chain.pem"; done
    fi
    # the oracle: OpenSSL's own verdict on the same files
    _ov=$(openssl verify -purpose sslserver -CAfile "$T/$2.pem" -untrusted "$T/chain.pem" "$T/$3.pem" 2>&1 || true)
    case "$_ov" in
        *": OK"*) _o=ok ;;
        *"error 47 "*) _o=47 ;;
        *"error 48 "*) _o=48 ;;
        *) _o="other: $(echo "$_ov" | tr '\n' ' ' | cut -c1-160)" ;;
    esac
    case "$7" in
        ok-diverges) [ "$_o" = ok ] || _fail "$8 — openssl verify was expected to accept (the named divergence), got $_o" ;;
        *) [ "$_o" = "$7" ] || _fail "$8 — openssl verify says $_o, the row expects $7" ;;
    esac
    rm -f "$T/ss.out" "$T/c.out"
    _chain=""
    [ "$4" != "-" ] && _chain="-cert_chain $T/chain.pem"
    # shellcheck disable=SC2086
    $TO openssl s_server -accept 127.0.0.1:0 "-tls1_$(echo "$1" | cut -c2)" -cert "$T/$3.pem" -key "$T/leaf.key" \
        $_chain -naccept 1 -rev < /dev/null > "$T/ss.out" 2>&1 &
    _sp=$!
    BGP="$BGP $_sp"
    _w=0
    _port=""
    while [ -z "$_port" ] && [ "$_w" -lt 50 ]; do
        sleep 0.1
        _w=$((_w + 1))
        _port=$(sed -n 's/^ACCEPT .*:\([0-9][0-9]*\)$/\1/p' "$T/ss.out" 2>/dev/null | head -1 || true)
    done
    if [ -z "$_port" ]; then _fail "$8 — s_server did not start: $(head -3 "$T/ss.out")"; return 0; fi
    $TO "$T/cli" "$_port" "$5" "$T/$2.pem" "$1" > "$T/c.out" 2>&1 || true
    sleep 0.2
    kill "$_sp" 2>/dev/null || true
    wait "$_sp" 2>/dev/null || true
    _c=$(cat "$T/c.out" 2>/dev/null || true)
    case "$6" in
        ok)
            case "$_c" in *"connect=0 "*) : ;; *) _fail "$8 — the native client did not connect: $_c"; return 0 ;; esac
            case "$_c" in *"echo=1 "*) : ;; *) _fail "$8 — no reversed echo from s_server: $_c" ;; esac
            ;;
        refused)
            case "$_c" in *"connect=-6 "*) : ;; *) _fail "$8 — expected TLS_ERR_CERT_INVALID (-6): $_c" ;; esac
            ;;
    esac
    [ "$FAILS" = "$_rf" ] && echo "  ok: TLS 1.$(echo "$1" | cut -c2): $8"
    return 0
}

echo "== the native client against s_server, verification on =="
row 13 root    leaf_victim   int_plain       victim-bank.test  ok      ok "control: victim-bank.test <- int_plain <- root connects"
row 13 root    leaf_victim   int_nc          victim-bank.test  refused 47 "the audit's repro: victim-bank.test <- int_nc (non-critical) <- root"
row 13 root    leaf_victim   int_ncc         victim-bank.test  refused 47 "victim-bank.test <- int_ncc (critical) <- root"
row 13 root    leaf_www      int_nc          www.good.test     ok      ok "permitted: www.good.test <- int_nc <- root"
row 13 root    leaf_www      int_ncc         www.good.test     ok      ok "permitted: www.good.test <- int_ncc (critical) <- root"
row 13 root    leaf_bad      int_ex          x.bad.good.test   refused 48 "excluded: x.bad.good.test <- int_ex <- root"
row 13 root_nc leaf_victim   int_plain       victim-bank.test  refused 47 "the ANCHOR: victim-bank.test <- int_plain <- root_nc"
row 13 root_nc leaf_www      int_plain       www.good.test     ok      ok "the ANCHOR: www.good.test <- int_plain <- root_nc"
row 13 root    leaf_l_victim lower,int_nc    victim-bank.test  refused 47 "an UPPER CA: victim-bank.test <- nc-lower <- int_nc <- root"
row 13 root    leaf_l_www    lower,int_nc    www.good.test     ok      ok "an UPPER CA: www.good.test <- nc-lower <- int_nc <- root"
row 13 root    leaf_l_dot    lower,int_xv    victim-bank.test. refused ok-diverges "the trailing dot: victim-bank.test. <- nc-lower <- int_xv (excluded victim-bank.test)"
row 13 root    leaf_l_victim lower,int_plain victim-bank.test  ok      ok "control: victim-bank.test <- nc-lower <- int_plain <- root connects"

if [ "$NROWS" -lt "$FLOOR" ]; then _fail "only $NROWS rows ran (floor $FLOOR)"; fi
if [ "$FAILS" = 0 ]; then echo "PASS: $G: $NROWS rows"; exit 0; fi
echo "FAIL: $G: $FAILS of $NROWS rows"
exit 1

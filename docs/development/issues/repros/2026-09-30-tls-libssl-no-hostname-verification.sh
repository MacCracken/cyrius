#!/usr/bin/env bash
# Repro: lib/tls.cyr libssl backend accepts a chain-valid cert for ANY hostname.
# Makes a throwaway P-256 CA + a server cert with SAN DNS:localhost only, serves
# it with `openssl s_server`, then runs the .cyr client twice: a default
# (native) build -- which also reaches libssl via tls_set_backend() -- and a
# `-D CYRIUS_TLS_LIBSSL` build. Needs openssl(1), libssl.so.3 and
# ~/.cyrius/dlopen-helper.  Run from anywhere:
#   docs/development/issues/repros/2026-09-30-tls-libssl-no-hostname-verification.sh
# Exit code = total failing checks (0 when fixed; 2 on 6.6.12).
set -u
R=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$R/../../../.." && pwd)
SRC="$R/2026-09-30-tls-libssl-no-hostname-verification.cyr"
D=$(mktemp -d)
SP=0
trap '[ "$SP" -ne 0 ] && kill "$SP" 2>/dev/null; rm -rf "$D"' EXIT
cd "$D" || exit 99
q() { "$@" >/dev/null 2>&1 || { echo "setup failed: $*"; exit 99; }; }
q openssl ecparam -name prime256v1 -genkey -noout -out ca.key
q openssl req -x509 -new -key ca.key -subj /CN=repro-ca -days 2 -out ca.crt
q openssl ecparam -name prime256v1 -genkey -noout -out other.key
q openssl req -x509 -new -key other.key -subj /CN=other-ca -days 2 -out other.crt
q openssl ecparam -name prime256v1 -genkey -noout -out srv.key
q openssl req -new -key srv.key -subj /CN=localhost -out srv.csr
printf 'subjectAltName=DNS:localhost\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n' > srv.ext
q openssl x509 -req -in srv.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 2 -extfile srv.ext -out srv.crt
PORT=$((20000 + RANDOM % 20000))
openssl s_server -quiet -accept "$PORT" -cert srv.crt -key srv.key -www >/dev/null 2>&1 &
SP=$!
sleep 0.5
cd "$ROOT" || exit 99
cyrius build -q "$SRC" "$D/native" || exit 99
cyrius build -q -D CYRIUS_TLS_LIBSSL "$SRC" "$D/libssl" || exit 99
echo "== default (native) build =="; "$D/native" "$PORT" "$D/ca.crt" "$D/other.crt"; A=$?
echo "== -D CYRIUS_TLS_LIBSSL build =="; "$D/libssl" "$PORT" "$D/ca.crt" "$D/other.crt"; B=$?
echo "failing checks: native-build=$A libssl-build=$B"
exit $((A + B))

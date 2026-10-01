#!/usr/bin/env bash
# Repro: first native-TLS use from two threads poisons the process; first use
# on a worker then on main SIGSEGVs. Makes a throwaway P-256 CA + server cert
# (SAN DNS:localhost), serves it with two `openssl s_server`s, builds and runs the
# .cyr client (default native backend). Needs openssl(1).  Run from anywhere:
#   docs/development/issues/repros/2026-09-30-tls-first-use-thread-race.sh
# Exit code = failing checks (0 when fixed; 3 on 6.6.12 -- A, B, C fail, D passes).
set -u
R=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$R/../../../.." && pwd)
SRC="$R/2026-09-30-tls-first-use-thread-race.cyr"
D=$(mktemp -d)
SP=""
trap 'kill $SP 2>/dev/null; rm -rf "$D"' EXIT
cd "$D" || exit 99
q() { "$@" >/dev/null 2>&1 || { echo "setup failed: $*"; exit 99; }; }
q openssl ecparam -name prime256v1 -genkey -noout -out ca.key
q openssl req -x509 -new -key ca.key -subj /CN=repro-ca -days 2 -out ca.crt
q openssl ecparam -name prime256v1 -genkey -noout -out srv.key
q openssl req -new -key srv.key -subj /CN=localhost -out srv.csr
printf 'subjectAltName=DNS:localhost\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n' > srv.ext
q openssl x509 -req -in srv.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 2 -extfile srv.ext -out srv.crt
PORT=$((20000 + RANDOM % 20000))
# s_server is serial, so each thread gets its own server (their handshakes must overlap)
for P in "$PORT" "$((PORT + 1))"; do
    openssl s_server -quiet -accept "$P" -cert srv.crt -key srv.key -www >/dev/null 2>&1 &
    SP="$SP $!"
done
sleep 0.5
cd "$ROOT" || exit 99
cyrius build -q "$SRC" "$D/client" || exit 99
"$D/client" "$PORT" "$((PORT + 1))" "$D/ca.crt"
exit $?

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
# serve: one s_server on a random loopback port, ready once it prints ACCEPT — only after ITS
# listen() succeeded, so a port someone else holds is never connected to; a bind failure retries
# elsewhere. Sets PORT. (6.6.14: this was `sleep 0.5`, then connect — a slow start or a taken port
# made the repro a flake.)
serve() {
    for _t in 1 2 3 4 5; do
        PORT=$((20000 + RANDOM % 20000))
        openssl s_server -accept "127.0.0.1:$PORT" -cert srv.crt -key srv.key -www \
            > "sv.$PORT.log" 2>&1 < /dev/null &
        _sp=$!
        for _i in $(seq 1 200); do
            if grep -q '^ACCEPT' "sv.$PORT.log"; then SP="$SP $_sp"; return 0; fi
            kill -0 "$_sp" 2>/dev/null || break
            sleep 0.05
        done
        kill "$_sp" 2>/dev/null
    done
    echo "setup failed: s_server never came up"; exit 99
}
# s_server is serial, so each thread gets its own server (their handshakes must overlap)
serve; P1=$PORT
serve; P2=$PORT
cd "$ROOT" || exit 99
cyrius build -q "$SRC" "$D/client" || exit 99
"$D/client" "$P1" "$P2" "$D/ca.crt"
exit $?

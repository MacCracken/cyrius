#!/usr/bin/env bash
# Exit code = number of certificates wrongly accepted for https://127.0.0.1.
set -u
D="$(cd "$(dirname "$0")" && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"; kill $(jobs -p) 2>/dev/null' EXIT
cd "$T"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout ca.key -out ca.pem -days 2 \
  -subj "/CN=repro CA" -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign 2>/dev/null
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out leaf.key 2>/dev/null
cyrius build "$D/2026-10-01-tls-ip-literal-dnsname.cyr" client >/dev/null 2>&1 || { echo "build failed"; exit 99; }
# serve: s_server on a random loopback port, ready once it prints ACCEPT — only after ITS listen()
# succeeded, so a port someone else holds is never connected to; a bind failure retries elsewhere.
# (6.6.14: this was `sleep 0.5`, then connect — a slow start or a taken port made the row a flake.)
serve() {
  for _t in 1 2 3 4 5; do
    port=$((20000 + RANDOM % 20000))
    openssl s_server -accept 127.0.0.1:$port -cert leaf.pem -key leaf.key -tls1_3 -www -naccept 1 \
      > sv.log 2>&1 < /dev/null &
    sp=$!
    for _i in $(seq 1 200); do
      grep -q '^ACCEPT' sv.log && return 0
      kill -0 $sp 2>/dev/null || break
      sleep 0.05
    done
    kill $sp 2>/dev/null
  done
  echo "s_server never came up"; exit 99
}
bad=0; port=0
for san in "DNS:127.0.0.1" "DNS:*.0.0.1" "IP:127.0.0.1"; do
  openssl req -new -key leaf.key -subj "/CN=leaf" -out leaf.csr 2>/dev/null
  printf 'subjectAltName=%s\nextendedKeyUsage=serverAuth\n' "$san" > leaf.ext
  openssl x509 -req -in leaf.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 2 -extfile leaf.ext -out leaf.pem 2>/dev/null
  serve
  out=$(./client $port ca.pem)
  want=refused; case "$san" in IP:*) want=accepted;; esac
  echo "SAN $san, host 127.0.0.1: $out (RFC 9525 6.3: $want)"
  [ "$out" = "$want" ] || bad=$((bad + 1))
done
exit $bad

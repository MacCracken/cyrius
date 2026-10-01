#!/usr/bin/env bash
# Exit code = number of certificates wrongly accepted for https://127.0.0.1.
set -u
D="$(cd "$(dirname "$0")" && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"; kill $(jobs -p) 2>/dev/null' EXIT
cd "$T"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout ca.key -out ca.pem -days 2 \
  -subj "/CN=repro CA" -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign 2>/dev/null
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out leaf.key 2>/dev/null
cyrius build "$D/2026-10-01-tls-ip-literal-dnsname.cyr" client >/dev/null 2>&1 || { echo "build failed"; exit 99; }
bad=0; port=$((30000 + RANDOM % 1000))
for san in "DNS:127.0.0.1" "DNS:*.0.0.1" "IP:127.0.0.1"; do
  openssl req -new -key leaf.key -subj "/CN=leaf" -out leaf.csr 2>/dev/null
  printf 'subjectAltName=%s\nextendedKeyUsage=serverAuth\n' "$san" > leaf.ext
  openssl x509 -req -in leaf.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 2 -extfile leaf.ext -out leaf.pem 2>/dev/null
  port=$((port + 1))
  openssl s_server -accept $port -cert leaf.pem -key leaf.key -tls1_3 -quiet -naccept 1 >/dev/null 2>&1 &
  sleep 0.5
  out=$(./client $port ca.pem)
  want=refused; case "$san" in IP:*) want=accepted;; esac
  echo "SAN $san, host 127.0.0.1: $out (RFC 9525 6.3: $want)"
  [ "$out" = "$want" ] || bad=$((bad + 1))
done
exit $bad

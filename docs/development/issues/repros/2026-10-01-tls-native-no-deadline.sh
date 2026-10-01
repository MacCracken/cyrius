#!/usr/bin/env bash
# Exit code = cases where the client was still blocked at 10 s.
set -u
D="$(cd "$(dirname "$0")" && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout ca.key -out ca.pem -days 2 \
  -subj "/CN=repro CA" -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign 2>/dev/null
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out leaf.key 2>/dev/null
openssl pkcs8 -topk8 -nocrypt -in leaf.key -outform DER -out leaf-key.der
openssl req -new -key leaf.key -subj "/CN=leaf" -out leaf.csr 2>/dev/null
printf 'subjectAltName=DNS:localhost\nextendedKeyUsage=serverAuth\n' > leaf.ext
openssl x509 -req -in leaf.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 2 -extfile leaf.ext \
  -outform DER -out leaf.der 2>/dev/null
cyrius build "$D/2026-10-01-tls-native-no-deadline.cyr" repro >/dev/null 2>&1 || { echo "build failed"; exit 99; }
./repro leaf.der leaf-key.der ca.pem

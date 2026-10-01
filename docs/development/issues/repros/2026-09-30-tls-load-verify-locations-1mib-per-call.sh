#!/usr/bin/env bash
# Repro: tls_ctx_load_verify_locations (native) retains 1 MiB of bump heap per
# call. Makes a throwaway one-cert CA file, builds + runs the .cyr. Needs
# openssl(1).  Run from anywhere:
#   docs/development/issues/repros/2026-09-30-tls-load-verify-locations-1mib-per-call.sh
# Exit code = failing checks (0 when fixed; 1 on 6.6.12).
set -u
R=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$R/../../../.." && pwd)
SRC="$R/2026-09-30-tls-load-verify-locations-1mib-per-call.cyr"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
openssl ecparam -name prime256v1 -genkey -noout -out "$D/ca.key" 2>/dev/null &&
openssl req -x509 -new -key "$D/ca.key" -subj /CN=repro-ca -days 2 -out "$D/ca.crt" 2>/dev/null || exit 99
cd "$ROOT" || exit 99
cyrius build -q "$SRC" "$D/probe" || exit 99
"$D/probe" "$D/ca.crt"
exit $?

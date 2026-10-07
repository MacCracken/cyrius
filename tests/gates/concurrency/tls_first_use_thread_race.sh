#!/bin/sh
# tls_first_use_thread_race.sh — 6.6.13 (I3). The FILED repro of issue
# 2026-09-30-tls-first-use-thread-race, built VERBATIM from
# docs/development/issues/repros/2026-09-30-tls-first-use-thread-race.cyr with build/cycc against
# the tree's lib/ (not `cyrius build` from the store), run against two OpenSSL s_servers.
#
# ⛔ THE DEFECT. Native TLS's first use was not thread-safe: two threads whose first connects
# overlapped failed all 10 handshakes and poisoned the process (a third thread later: 5 of 5
# failed), and a first use on a worker followed by one on the main thread was a SIGSEGV. sigil's
# lazy table inits were check-then-set and crypto_tls_main_init gave its block to whichever thread
# came first. The sigil half was fixed in sigil 3.13.6 (the fold); cyrius's half — the system-CA
# bundle cache publishing once — is pinned by tests/tcyr/crossos/tls_first_use_threads.tcyr, which
# needs no network and runs on every cross-OS host. This gate keeps the networked A/B/C/D
# scenarios alive in check.sh, because the .tcyr cannot make a handshake.
#
# LEGS: the client against a P-256 chain (the filing's), then RSA-2048 and Ed25519 chains — the
# init paths the filing called unproven. Each leg needs exit 0 AND the client's four PASS lines
# (A, B, C, D) with no FAIL: a client that ran nothing cannot read green.
# SKIP (exit 77, named): openssl(1) missing — the peer is OpenSSL's s_server.
#
# MUTATION LEDGER (6.6.13, measured RED here):
#   MT1 lib/sigil.cyr from sigil 3.13.5 (6c05a2c6, the pre-fold tree) -> P-256 leg exit 3
#       (FAIL A 10/10, FAIL B 5/5, FAIL C signal 11, PASS D) — the filing's exact numbers; the
#       RSA-2048 and Ed25519 legs exit 1 (FAIL C, signal 11).
#   MT2 (6.6.14) serve's 6.6.13 readiness (any TCP connect on the port) -> S0: the second server
#       "comes up" on the held port, i.e. the repro's thread would talk to the first server.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 1
G=tls_first_use_thread_race
CC=${CYCC:-"$ROOT/build/cycc"}
REPRO=docs/development/issues/repros/2026-09-30-tls-first-use-thread-race.cyr
[ -x "$CC" ] || { echo "FAIL: $G: no compiler at $CC"; exit 1; }
[ -f "$REPRO" ] || { echo "FAIL: $G: the filed repro is missing ($REPRO) — it is the spec"; exit 1; }
command -v openssl >/dev/null 2>&1 || {
    echo "SKIP: $G: openssl(1) not found — the peer is OpenSSL's s_server"; exit 77; }

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
SP=""
trap '[ -n "$SP" ] && kill $SP 2>/dev/null; rm -rf "$T"' EXIT
TO=""
command -v timeout >/dev/null 2>&1 && TO="timeout 180"

cat "$REPRO" | "$CC" > "$T/client" 2> "$T/client.err" || {
    echo "FAIL: $G: the filed repro did not compile"; tail -3 "$T/client.err"; exit 1; }
chmod +x "$T/client"


q() { "$@" >/dev/null 2>&1 || { echo "FAIL: $G: setup: $*"; exit 1; }; }
genkey() {  # <kind> <out>
    case "$1" in
        p256)    q openssl ecparam -name prime256v1 -genkey -noout -out "$2" ;;
        rsa)     q openssl genrsa -out "$2" 2048 ;;
        ed25519) q openssl genpkey -algorithm ed25519 -out "$2" ;;
    esac
}

# serve <dir>: start one s_server on a random loopback port and wait for its own "ACCEPT" line,
# which s_server prints only once ITS listen() has succeeded; a bind failure ends the process before
# the line, and serve retries on another port. Sets PORT; adds the pid to SP.
# ⛔ 6.6.14 — WHY. serve used to wait for ANY TCP connect to succeed on the port: a foreign listener
# already holding it answered while s_server died on its bind, and the repro's thread then talked to
# a stranger — a flake that read as a TLS failure. SERVE_FIRST_PORT forces the first port (S0).
# ⛔ 6.6.20 — EVERY ATTEMPT READS ITS OWN, FRESH LOG. The log was `sv.$PORT.log`, and S0 forces
# the second serve onto P1 — the FIRST server's log name. The `>` truncation runs in the
# backgrounded child, so the parent's grep could run before it and read the first server's stale
# ACCEPT: serve returned PORT=P1 and S0 failed (30 of 300 under 16-core load, 0 idle; the 6.6.19
# flake). Each attempt now gets a name no earlier attempt used (SERVE_N) and the parent creates
# it empty before launching. SV_LOG is the log of the server serve settled on.
# Pinned by tests/gates/concurrency/tls_serve_fresh_log.sh. CHANGELOG [6.6.20]
PORT=0
SERVE_FIRST_PORT=
SERVE_N=0
SV_LOG=
serve() {
    tries=0
    while [ $tries -lt 5 ]; do
        if [ -n "$SERVE_FIRST_PORT" ]; then PORT=$SERVE_FIRST_PORT; SERVE_FIRST_PORT=
        else PORT=$((20000 + $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % 20000)); fi
        SERVE_N=$((SERVE_N + 1))
        SV_LOG="$1/sv.$SERVE_N.$PORT.log"
        : > "$SV_LOG"
        openssl s_server -accept "127.0.0.1:$PORT" -cert "$1/srv.crt" -key "$1/srv.key" -www \
            > "$SV_LOG" 2>&1 < /dev/null &
        sp=$!
        i=0
        while [ $i -lt 200 ]; do
            if grep -q '^ACCEPT' "$SV_LOG" 2>/dev/null; then SP="$SP $sp"; return 0; fi
            kill -0 "$sp" 2>/dev/null || break
            sleep 0.05
            i=$((i + 1))
        done
        kill "$sp" 2>/dev/null || true; wait "$sp" 2>/dev/null || true
        tries=$((tries + 1))
    done
    echo "FAIL: $G: s_server never reached ACCEPT (5 ports tried)"; exit 1
}

FAILS=0
LEGS=0
for KIND in p256 rsa ed25519; do
    D="$T/$KIND"
    mkdir "$D"
    genkey "$KIND" "$D/ca.key"
    q openssl req -x509 -new -key "$D/ca.key" -subj /CN=repro-ca -days 2 -out "$D/ca.crt"
    genkey "$KIND" "$D/srv.key"
    q openssl req -new -key "$D/srv.key" -subj /CN=localhost -out "$D/srv.csr"
    printf 'subjectAltName=DNS:localhost\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n' > "$D/srv.ext"
    q openssl x509 -req -in "$D/srv.csr" -CA "$D/ca.crt" -CAkey "$D/ca.key" -CAcreateserial \
        -days 2 -extfile "$D/srv.ext" -out "$D/srv.crt"
    # s_server is serial, so each of the repro's two threads gets its own server.
    serve "$D"; P1=$PORT
    if [ "$KIND" = p256 ]; then
        # S0 (6.6.14): serve forced onto the port the first server holds must see its own s_server
        # die on the bind and come up elsewhere — never settle on a port another process answers.
        SERVE_FIRST_PORT=$P1
    fi
    serve "$D"; P2=$PORT
    if [ "$KIND" = p256 ]; then
        if [ "$P2" != "$P1" ] && grep -q '^ACCEPT' "$SV_LOG"; then
            echo "  ok: S0 — the held port $P1 was refused by the bind; the second server is up on $P2"
        else
            echo "  FAIL: S0 — the second server settled on $P2 (the held port was $P1): it would be a stranger"
            FAILS=$((FAILS + 1))
        fi
    fi
    rc=0
    $TO "$T/client" "$P1" "$P2" "$D/ca.crt" > "$D/out.txt" 2>&1 || rc=$?
    kill $SP 2>/dev/null || true; wait 2>/dev/null || true; SP=""
    NPASS=$(grep -c '^PASS$' "$D/out.txt" || true)
    NFAIL=$(grep -c '^FAIL$' "$D/out.txt" || true)
    if [ "$rc" -eq 0 ] && [ "$NPASS" -eq 4 ] && [ "$NFAIL" -eq 0 ]; then
        echo "  ok: $KIND chain — A, B, C, D all PASS"
    else
        echo "  FAIL: $KIND chain — client exit $rc, $NPASS PASS / $NFAIL FAIL (want exit 0, 4 / 0):"
        sed 's/^/    /' "$D/out.txt" | head -20
        FAILS=$((FAILS + 1))
    fi
    LEGS=$((LEGS + 1))
done

[ "$LEGS" -eq 3 ] || { echo "FAIL: $G: $LEGS legs ran, expected 3"; exit 1; }
[ "$FAILS" -eq 0 ] || { echo "FAIL: $G: $FAILS of $LEGS chains failed"; exit 1; }
echo "PASS: $G (the filed repro: A, B, C, D green against P-256, RSA-2048 and Ed25519 chains)"
exit 0

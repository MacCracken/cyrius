#!/bin/sh
# Gate: the TLS gates' `serve` readiness wait reads only ITS OWN attempt's log (6.6.20).
#
# tls_first_use_thread_race.sh and tls_libssl_hostname_binding.sh start OpenSSL s_servers with
# `serve`, which launches `openssl s_server … > LOG &` and then waits for an `ACCEPT` line in LOG.
# The `>` truncation runs in the BACKGROUNDED child, so a parent grep that runs before it reads
# whatever LOG held before. And LOG was REUSED: tls_first_use's S0 forces the second server onto
# the first one's port, whose log name `sv.$PORT.log` is the first server's; the libssl gate wrote
# ONE `$T/sv.log` for every server. A stale ACCEPT then read as "ready" — on the held port (S0
# fails) or on a port nothing listened on yet. Removed from the backlog as shipped at 6.6.14, it
# recurred as the 6.6.19 load flake (simulated: 30 of 300 stale reads under 16-core load, 0 idle).
#
# The race itself is timing; what makes it possible is not. This gate runs each gate's OWN
# `serve` (extracted from the file, so it tests the code check.sh runs) against a fake `openssl`
# that "binds" a port unless it is held and logs every attempt, through the S0 shape (serve; serve
# forced onto the held port; serve). It requires:
#   axis 1  one log file per attempt — no attempt's readiness wait can see an earlier server's
#           output, whatever the scheduling (the 6.6.19 code: 3 files for 4 attempts, and 1);
#   axis 2  the S0 outcome: the serve forced onto the held port settles elsewhere.
# (The parent also creates each log empty before launching — belt and braces; a fresh name is
# what closes the race, and it is what this gate measures.)
#
# Mutation ledger (measured 6.6.20): each gate's 6.6.19 `serve` → axis 1 red for that gate.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: tls_serve_fresh_log: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
cleanup() {
    for f in "$W"/pids/*; do [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null || true; done
    rm -rf "$W"
}
trap cleanup EXIT
fail() { echo "FAIL: tls_serve_fresh_log: $1"; exit 1; }
mkdir -p "$W/bin" "$W/pids"

# The fake: `openssl s_server -accept 127.0.0.1:PORT …`. Records the attempt; refuses a held port
# the way a failed bind does (message, exit 1, no ACCEPT); otherwise holds the port, prints ACCEPT
# and stays up.
cat > "$W/bin/openssl" <<'FAKE'
#!/bin/sh
[ "$1" = s_server ] || exit 2
port=""
while [ $# -gt 0 ]; do
    case "$1" in -accept) port=${2##*:}; shift ;; esac
    shift
done
echo "$port" >> "$FAKE_DIR/ledger"
if [ -e "$FAKE_DIR/held.$port" ]; then echo "bind: Address already in use"; exit 1; fi
: > "$FAKE_DIR/held.$port"
echo $$ > "$FAKE_DIR/pids/$$"
echo "ACCEPT"
exec sleep 60
FAKE
chmod +x "$W/bin/openssl"

# drive <label> <gate file> <serve dir> <how serve is called: dir|leaf>
drive() {
    _lab=$1; _gf=$2; _sd=$3; _how=$4
    [ -f "$_gf" ] || fail "$_lab: $_gf missing"
    _fns=$(awk '/^serve\(\) \{/,/^\}/' "$_gf"; awk '/^_serve_ready\(\) \{/,/^\}/' "$_gf")
    printf '%s\n' "$_fns" | grep -q '^serve() {' || fail "$_lab: no serve() in $_gf"
    mkdir -p "$_sd"
    : > "$W/ledger"
    (
        PATH="$W/bin:$PATH"; FAKE_DIR="$W"; export PATH FAKE_DIR
        G=$_lab; T=$_sd; SP=""; PORT=0; SERVE_FIRST_PORT=; SERVE_N=0; SV_LOG=
        eval "$_fns"
        if [ "$_how" = dir ]; then serve "$_sd"; else serve leaf; fi
        P1=$PORT
        SERVE_FIRST_PORT=$P1
        if [ "$_how" = dir ]; then serve "$_sd"; else serve leaf; fi
        P2=$PORT
        if [ "$_how" = dir ]; then serve "$_sd"; else serve leaf; fi
        echo "$P1 $P2" > "$W/ports"
    ) > "$W/drive.out" 2>&1 || fail "$_lab: serve itself failed: $(cat "$W/drive.out")"
    _att=$(grep -c . "$W/ledger" || true)
    _files=$(ls -1 "$_sd" | grep -c . || true)
    [ "$_att" -ge 4 ] || fail "$_lab: premise — expected at least 4 server attempts, the fake saw $_att"
    [ "$_files" = "$_att" ] ||
        fail "$_lab: axis 1 — $_att server attempts wrote $_files log file(s): a readiness wait can read an earlier server's ACCEPT ($(ls "$_sd" | tr '\n' ' '))"
    read -r _p1 _p2 < "$W/ports"
    [ "$_p2" != "$_p1" ] || fail "$_lab: axis 2 — the serve forced onto held port $_p1 settled on it"
    echo "  ok: $_lab — $_att attempts, $_files fresh logs, S0 moved off $_p1 to $_p2"
    for f in "$W"/pids/*; do [ -f "$f" ] && { kill "$(cat "$f")" 2>/dev/null || true; rm -f "$f"; }; done
    rm -f "$W"/held.*
}

drive tls_first_use_thread_race tests/gates/concurrency/tls_first_use_thread_race.sh "$W/race" dir
drive tls_libssl_hostname_binding tests/gates/platform/tls_libssl_hostname_binding.sh "$W/libssl" leaf

echo "PASS: tls_serve_fresh_log (both gates' serve: one fresh log per attempt; S0 moves off the held port)"

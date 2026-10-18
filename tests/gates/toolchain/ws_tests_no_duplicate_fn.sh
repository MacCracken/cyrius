#!/bin/sh
# ws_tests_no_duplicate_fn.sh — the ws tests run the stdlib's own sandhi / bayan fns, and compile
# without a `duplicate fn` warning.
#
# 6.7.14. Since 6.6.19 R2 lib/ws_server.cyr includes lib/sandhi.cyr and lib/bayan.cyr itself, but
# five tests kept the stand-ins they wrote before that include: a local `sandhi_server_find_header`
# (and in net_plain_write_peer_reset a `base64_encode`). Every compile of each warned
# `duplicate fn` — a warning a real one scrolls past — and sock_send_all_short_write.tcyr defined
# its stand-in AFTER the include, so its stub bound last and that test's handshake group ran the
# stand-in, not sandhi's fn. The stand-ins are gone; each test runs the fns its includes bring.
# issues/archived/2026-10-15-ws-tests-carry-stale-sandhi-find-header-stubs.md, CHANGELOG [6.7.14]
#
# AXES
#   1  each of the five compiles (rc 0, a non-empty binary) with ZERO `duplicate fn` lines on
#      stderr — the count is printed per file (the 6.7.13 files gave 1 / 1 / 1 / 2 / 1)
#   2  none of the five defines `fn sandhi_server_find_header` or `fn base64_encode` itself
#   3  the compiler still reports the shape, so axis 1 is not reading a silenced warning: a staged
#      copy of ws_server_recv_frame_exact.tcyr with the 6.7.13 stub put back BEFORE the ws_server
#      include warns once, and with it put back AFTER the include (the sock_send_all shape) warns once
#   4  anti-vacuous: all five files exist (a renamed test reads RED by name, not as clean)
#
# Mutation ledger (6.7.14, each in the tree, each RED):
#   ws_server_handshake.tcyr with its 6.7.13 stand-in restored          -> axes 1 + 2 (1 warning)
#   net_plain_write_peer_reset.tcyr with its two stubs restored         -> axes 1 + 2 (2 warnings)
#   sock_send_all_short_write.tcyr with its stub restored (after the include) -> axes 1 + 2
#
# Compile-only: the tests themselves run in the .tcyr corpus, the crossos three on ecb / ach /
# cass / pi through the release gate's cross-OS leg.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
NAME=ws_tests_no_duplicate_fn
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: $NAME: $CC missing"; exit 1; }
FAILS=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }
_ok() { echo "  ok: $1"; }

FILES="tests/tcyr/formats/ws_server_handshake.tcyr
tests/tcyr/stdlib/ws_server_recv_frame_exact.tcyr
tests/tcyr/crossos/ws_server_socket_reads.tcyr
tests/tcyr/crossos/net_plain_write_peer_reset.tcyr
tests/tcyr/crossos/sock_send_all_short_write.tcyr"

echo "axis 4 — the five files exist:"
N=0
for f in $FILES; do
    if [ -f "$f" ]; then N=$((N + 1)); else _fail "$f: missing — the gate is blind, not the test clean"; fi
done
[ "$N" -eq 5 ] && _ok "5 of 5 present"

echo "axis 1 — each compiles with no duplicate-fn warning:"
for f in $FILES; do
    [ -f "$f" ] || continue
    b=$(basename "$f" .tcyr)
    rc=0
    cat "$f" | "$CC" > "$D/$b.bin" 2> "$D/$b.err" || rc=$?
    if [ "$rc" -ne 0 ] || [ ! -s "$D/$b.bin" ]; then
        _fail "$f: compile rc=$rc: $(grep -v '^note' "$D/$b.err" | head -1)"; continue
    fi
    nd=$(grep -c 'duplicate fn' "$D/$b.err" || true)
    if [ "$nd" -eq 0 ]; then _ok "$f: 0 duplicate-fn warnings"
    else _fail "$f: $nd duplicate-fn warning(s) — a test defines a fn its includes already bring: $(grep 'duplicate fn' "$D/$b.err" | tr '\n' ' ')"; fi
done

echo "axis 2 — no test defines the stdlib's fns itself:"
for f in $FILES; do
    [ -f "$f" ] || continue
    DEF=$(grep -nE '^[[:space:]]*fn (sandhi_server_find_header|base64_encode)\(' "$f" || true)
    if [ -z "$DEF" ]; then _ok "$f: no stand-in"
    else _fail "$f: defines a stand-in for a fn lib/ws_server.cyr's includes bring: $(echo "$DEF" | tr '\n' ' ')"; fi
done

echo "axis 3 — the compiler still reports the shape:"
SRC=tests/tcyr/stdlib/ws_server_recv_frame_exact.tcyr
if [ -f "$SRC" ] && grep -q '^include "lib/ws_server.cyr"' "$SRC"; then
    STUB='fn sandhi_server_find_header(buf, blen, name): i64 { return 0; }'
    awk -v s="$STUB" '/^include "lib\/ws_server.cyr"/ { print s } { print }' "$SRC" > "$D/before.tcyr"
    awk -v s="$STUB" '{ print } /^include "lib\/ws_server.cyr"/ { print s }' "$SRC" > "$D/after.tcyr"
    for v in before after; do
        rc=0
        cat "$D/$v.tcyr" | "$CC" > "$D/$v.bin" 2> "$D/$v.err" || rc=$?
        nd=$(grep -c "duplicate fn 'sandhi_server_find_header'" "$D/$v.err" || true)
        if [ "$rc" -eq 0 ] && [ "$nd" -eq 1 ]; then _ok "a stub $v the ws_server include warns once"
        else _fail "a stub $v the ws_server include: rc=$rc, $nd warning(s) (want rc 0 and 1) — axis 1 may be reading a silenced warning"; fi
    done
else
    _fail "$SRC: missing, or no top-level include of lib/ws_server.cyr — axis 3 has nothing to stage"
fi

if [ "$FAILS" -ne 0 ]; then echo "FAIL: $NAME ($FAILS)"; exit 1; fi
echo "PASS: $NAME (5 ws tests compile with no duplicate-fn warning)"

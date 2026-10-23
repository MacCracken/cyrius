#!/bin/sh
# Gate: cyrius's own network parsers read the peer's bytes through fn-local [u8] slices, so a
# bounds check they get wrong is `slice bounds violation` (exit 134), never a read past the buffer
# (6.7.18 — the user's D1; issues/archived/2026-10-22-network-parsers-unfuzzed-and-bounds-mode-blind-to-raw-loads.md).
#
# ⛔ WHY. Bounds mode (#bounds / --bounds) checks subscripts; these parsers read through raw
# load8/16/32(base + off), which no build checks — measured over twelve parser entry fns at the
# 6.7.18 open, 87 raw loads to 7 subscripts. D1: each parser wraps its (buf, len) in a slice
# (`var s: [u8] = 0; slice_set(&s, buf, len);`) and reads `s[i]`, checked in EVERY build; a
# multi-byte big-endian field goes through the one checked helper, lib/slice.cyr's slice_get_be.
# The parsers keep their own checks (a malformed message is still a graceful -1 / 0); the slice is
# what stops a check that is wrong.
#
# AXES, per parser family
#   S  static: the parser fns' bodies hold no raw load8 / load16 / load32 (a byte is `s[i]`, a
#      wider field slice_get_be; load64 stays for the fns' own handle / header-record words)
#   M  caught: in a COPY of lib/, one of the parser's own bounds checks is removed (or loosened by
#      one); a probe then feeds the message that check stopped. The parser must stop at the slice —
#      exit 134 and `slice bounds violation` on stderr. The same probe on the real lib/ is the
#      control: the graceful answer, exit 0.
# Families: the async DNS answer parser (lib/async.cyr), the HTTP/1 response parser (lib/http.cyr),
# the WebSocket client's frame reader (lib/ws.cyr), the WebSocket server's frame reader and its
# upgrade handshake's key (lib/ws_server.cyr), and the blocking resolver's DNS reply parser
# (lib/net.cyr's _net_dns_answer / _net_dns_skip: a datagram from whoever answers the query,
# brought under D1 by the 6.7.18 lib review).
#
# RED before 6.7.18: the static rows name every raw load, and with the same check removed the
# parent's raw loads read on past the message (the probe exits 0 with whatever the heap held).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
NAME=net_parsers_read_through_slices
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: $NAME: no compiler at $CC"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT INT TERM
FAILS=0
ROWS=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }
_ok() { echo "  ok: $1"; ROWS=$((ROWS + 1)); }

# body FILE FN — the source of `fn FN(` through its closing `}` at column 0.
body() { awk -v f="fn $2(" 'index($0, f) == 1 { p = 1 } p { print } p && /^}/ { exit }' "$1"; }

# no_raw FILE FN... — each fn exists and its body has no load8/16/32.
no_raw() {
    _f=$1; shift
    for _fn in "$@"; do
        _b=$(body "$ROOT/$_f" "$_fn")
        if [ -z "$_b" ]; then _fail "S $_f: fn $_fn not found — the gate is blind, not the code clean"; continue; fi
        _raw=$(printf '%s\n' "$_b" | sed 's/#.*//' | grep -nE 'load(8|16|32)\(' || true)
        if [ -z "$_raw" ]; then _ok "S $_f: $_fn reads through slices (no load8/16/32)"
        else _fail "S $_f: $_fn still reads raw: $(echo "$_raw" | tr '\n' ' ')"; fi
    done
}

# caught LABEL FILE OLD NEW PROBE WANT — in a copy of lib/ replace the one line equal to OLD (after
# its indentation) with NEW, build PROBE (a file under $T) against the real lib/ and the copy: the
# real one must exit 0 printing WANT, the copy exit 134 with `slice bounds violation`.
caught() {
    _lbl=$1; _file=$2; _old=$3; _new=$4; _probe=$5; _want=$6
    _n=$(grep -cxF "    $_old" "$ROOT/$_file"; true)
    _n2=$(grep -cxF "        $_old" "$ROOT/$_file"; true)
    _n3=$(grep -cxF "            $_old" "$ROOT/$_file"; true)
    if [ $((_n + _n2 + _n3)) -ne 1 ]; then _fail "M $_lbl: the check '$_old' is not on exactly one line of $_file — update the gate"; return; fi
    rm -rf "$T/mut" && mkdir -p "$T/mut" && cp -R "$ROOT/lib" "$T/mut/lib"
    awk -v o="$_old" -v n="$_new" '{ s = $0; sub(/^ +/, "", s); if (s == o) { ind = substr($0, 1, length($0) - length(s)); print ind n } else print }' \
        "$ROOT/$_file" > "$T/mut/$_file"
    rc=0; ( cd "$ROOT" && "$CC" < "$T/$_probe" > "$T/real" 2> "$T/real.err" ) || rc=$?
    if [ "$rc" != 0 ] || [ ! -s "$T/real" ]; then _fail "M $_lbl: the probe did not build against lib/ (rc $rc)"; return; fi
    chmod +x "$T/real"
    rc=0; _out=$("$T/real" 2>&1) || rc=$?
    if [ "$rc" = 0 ] && [ "$_out" = "$_want" ]; then _ok "M $_lbl: control — the real parser answers '$_want'"
    else _fail "M $_lbl: control — the real parser exited $rc printing '$_out' (want 0, '$_want')"; fi
    rc=0; ( cd "$T/mut" && "$CC" < "$T/$_probe" > "$T/mutb" 2> "$T/mut.err" ) || rc=$?
    if [ "$rc" != 0 ] || [ ! -s "$T/mutb" ]; then _fail "M $_lbl: the probe did not build against the mutated copy (rc $rc)"; return; fi
    chmod +x "$T/mutb"
    rc=0; "$T/mutb" > "$T/mut.out" 2> "$T/mut.stderr" || rc=$?
    if [ "$rc" = 134 ] && grep -qx 'slice bounds violation' "$T/mut.stderr"; then
        _ok "M $_lbl: with '$_old' gone the read stops at the slice (exit 134, slice bounds violation)"
    else _fail "M $_lbl: with '$_old' gone the parser exited $rc printing '$(cat "$T/mut.out")' — it read past the message"; fi
}

# ── the async DNS answer parser (lib/async.cyr) ──
echo "the async DNS answer parser:"
no_raw lib/async.cyr _async_dns_skip_name _async_dns_parse_a
cat > "$T/dns.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/async.cyr"
# arg: 1 = an answer cut 7 bytes short of its fixed fields; 2 = a question label running off the end
fn main(): i64 {
    alloc_init();
    var b = alloc(64);
    memset(b, 0, 64);
    store8(b, 0x43); store8(b + 1, 0x42); store8(b + 2, 0x81); store8(b + 3, 0x80);
    store8(b + 5, 1); store8(b + 7, 1);                     # QDCOUNT 1, ANCOUNT 1
    store8(b + 12, 1); store8(b + 13, 97); store8(b + 14, 0); # question "a"
    store8(b + 16, 1); store8(b + 18, 1);                   # QTYPE A, QCLASS IN
    store8(b + 19, 0xC0); store8(b + 20, 12);               # answer name: a pointer
    store8(b + 22, 1);                                      # TYPE A, then nothing
    var n = 24;
    #ifdef DNS_LABEL
    store8(b + 12, 63);                                     # a 63-byte label in a 14-byte message
    n = 14;
    #endif
    fmt_int(_async_dns_parse_a(b, n, 0x4342));
    return 0;
}
var r = main();
syscall(60, r);
EOF
caught "dns answer" lib/async.cyr 'if (off + 10 > blen) { return 0 - 1; }' '# (removed)' dns.cyr '-1'
{ echo '#define DNS_LABEL'; cat "$T/dns.cyr"; } > "$T/dnsl.cyr"
caught "dns name" lib/async.cyr 'if (p < 0 || p >= blen) { return 0 - 1; }' '# (removed)' dnsl.cyr '-1'

# ── the blocking resolver's DNS reply parser (lib/net.cyr) ──
echo "the net.cyr DNS reply parser:"
no_raw lib/net.cyr _net_dns_skip _net_dns_answer
cat > "$T/ndns.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/net.cyr"
# The reply to the query for "a": the question echoed, ANCOUNT 1, the answer's name a pointer, its
# TYPE, then nothing — cut 7 bytes short of its fixed fields. NDNS_LABEL: the answer's name is a
# 63-byte label in the 5 bytes left.
fn main(): i64 {
    alloc_init();
    var q = alloc(512);
    var ql = _net_dns_build(q, 0x4342, "a");
    var b = alloc(128);
    memset(b, 0, 128);
    memcpy(b, q, ql);
    store8(b + 2, 0x81); store8(b + 3, 0x80);              # QR + RD, RA, rcode 0
    store8(b + 7, 1);                                       # ANCOUNT 1
    store8(b + ql, 0xC0); store8(b + ql + 1, 12);           # answer name: a pointer
    store8(b + ql + 3, 1);                                  # TYPE A, then nothing
    #ifdef NDNS_LABEL
    store8(b + ql, 63);
    #endif
    fmt_int(_net_dns_answer(b, ql + 5, q, ql));
    return 0;
}
var r = main();
syscall(60, r);
EOF
caught "net dns answer" lib/net.cyr 'if (off + 10 > n) { return 0 - 1; }' '# (removed)' ndns.cyr '-1'
{ echo '#define NDNS_LABEL'; cat "$T/ndns.cyr"; } > "$T/ndnsl.cyr"
caught "net dns name" lib/net.cyr 'while (off < n) {' 'while (off < n + 64) {' ndnsl.cyr '-1'

# ── the HTTP/1 response parser (lib/http.cyr) ──
echo "the HTTP/1 response parser:"
no_raw lib/http.cyr _http_parse_into _http_parse_response _http_parse_response_a
cat > "$T/http.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/http.cyr"
# a response that ends one byte short of its blank line (HTTP_SHORT: a 10-byte one), on the heap
fn main(): i64 {
    alloc_init();
    var src = "HTTP/1.1 200 OK\r\nX: y\r\n\r";
    #ifdef HTTP_SHORT
    src = "HTTP/1.1 2";
    #endif
    var n = strlen(src);
    var b = alloc(64);
    memset(b, 0, 64);
    memcpy(b, src, n);
    var r = _http_parse_response(b, n);
    fmt_int(http_status(r));
    syscall(1, 1, " ", 1);
    fmt_int(http_body_len(r));
    return 0;
}
var r = main();
syscall(60, r);
EOF
caught "http blank-line scan" lib/http.cyr 'while (pi < len - 3) {' 'while (pi < len) {' http.cyr '200 0'
{ echo '#define HTTP_SHORT'; cat "$T/http.cyr"; } > "$T/https.cyr"
caught "http status line" lib/http.cyr 'if (len < 12) { return result; }' '# (removed)' https.cyr '0 0'

# ── the WebSocket client's frame reader (lib/ws.cyr) ──
echo "the WebSocket client's frame reader:"
no_raw lib/ws.cyr ws_recv_frame _ws_header_end
cat > "$T/wsc.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/net.cyr"
include "lib/bayan.cyr"
include "lib/ws.cyr"
# a masked TEXT frame "abc" through a pipe (no file in the tree, no socket)
fn main(): i64 {
    alloc_init();
    var fds[16];
    sys_pipe(&fds);
    var f[16];
    store8(&f, 0x81); store8(&f + 1, 0x80 | 3);
    store8(&f + 2, 1); store8(&f + 3, 2); store8(&f + 4, 3); store8(&f + 5, 4);
    store8(&f + 6, 97 ^ 1); store8(&f + 7, 98 ^ 2); store8(&f + 8, 99 ^ 3);
    sys_write(load32(&fds + 4), &f, 9);
    sys_close(load32(&fds + 4));
    var ws = ws_new(load32(&fds));
    store64(ws + 8, WS_OPEN);
    var m = ws_recv(ws);
    if (m == 0) { syscall(1, 1, "(null)", 6); } else { syscall(1, 1, m, strlen(m)); }
    return 0;
}
var r = main();
syscall(60, r);
EOF
caught "ws client unmask" lib/ws.cyr 'while (i < plen) {' 'while (i <= plen) {' wsc.cyr 'abc'

# ── the WebSocket server's frame reader (lib/ws_server.cyr) ──
echo "the WebSocket server's frame reader:"
no_raw lib/ws_server.cyr _wss_recv_header _wss_recv_payload ws_server_recv_frame ws_server_recv
cat > "$T/wss.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/net.cyr"
include "lib/bayan.cyr"
include "lib/ws_server.cyr"
# a masked client TEXT frame "abc" through a pipe
fn main(): i64 {
    alloc_init();
    var fds[16];
    sys_pipe(&fds);
    var f[16];
    store8(&f, 0x81); store8(&f + 1, 0x80 | 3);
    store8(&f + 2, 1); store8(&f + 3, 2); store8(&f + 4, 3); store8(&f + 5, 4);
    store8(&f + 6, 97 ^ 1); store8(&f + 7, 98 ^ 2); store8(&f + 8, 99 ^ 3);
    sys_write(load32(&fds + 4), &f, 9);
    sys_close(load32(&fds + 4));
    var ws = ws_server_new(load32(&fds));
    var buf = alloc(256);
    var op[8];
    var n = ws_server_recv_frame(ws, buf, 255, &op);
    if (n != 3) { syscall(1, 1, "(short)", 7); } else { syscall(1, 1, buf, 3); }
    return 0;
}
var r = main();
syscall(60, r);
EOF
caught "ws server unmask" lib/ws_server.cyr 'while (pi < len) {' 'while (pi <= len) {' wss.cyr 'abc'

# ── the WebSocket server's upgrade handshake (lib/ws_server.cyr) ──
echo "the WebSocket server's upgrade handshake:"
no_raw lib/ws_server.cyr ws_server_handshake _wss_b64_char
cat > "$T/wsh.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/fmt.cyr"
include "lib/net.cyr"
include "lib/bayan.cyr"
include "lib/ws_server.cyr"
# an upgrade whose key is 5 bytes ("short"); fd -1: nothing is sent
fn main(): i64 {
    alloc_init();
    var q = "GET / HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: short\r\n\r\n";
    fmt_int(ws_server_handshake(0 - 1, q, strlen(q)));
    return 0;
}
var r = main();
syscall(60, r);
EOF
caught "ws handshake key" lib/ws_server.cyr 'if (klen != 24) { return 0; }' '# (removed)' wsh.cyr '0'

# Floor: every family's rows ran.
if [ "$ROWS" -lt 33 ] && [ "$FAILS" = 0 ]; then _fail "only $ROWS rows ran (floor 33) — the gate is reading nothing"; fi
if [ "$FAILS" = 0 ]; then echo "PASS: $NAME ($ROWS rows: the parsers read through slices, and a bound they get wrong stops there)"; exit 0; fi
echo "FAIL: $NAME ($FAILS)"
exit 1

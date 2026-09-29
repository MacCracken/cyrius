#!/bin/sh
# Gate: a REFUSED alloc() in the first-party stdlib returns the fn's error sentinel — it is never
# written through (6.6.10, bite 14).
#
# ⛔ THE DEFECT. About 80 first-party `var x = alloc(..)` sites in files no other 6.6.10 lane owns
# (chrono, http, regex, sha1, str, string, sync*, thread*, trait, tls, unicode, ws*, the Linux
# syscall peers' *_new helpers, boxed, cffi, dynlib) stored through the result with no zero check,
# so an exhausted or refused heap became a SIGSEGV at a small address inside the stdlib instead of
# the 0 / -1 the caller's `== 0` guard is written for. Same class as the io.cyr refused-alloc work
# (6.6.7 / 6.6.8). Lane T's static census (stdlib_alloc_checked_census.sh) finds the SHAPE; this
# gate proves the checks WORK, at run time, one allocation at a time.
#
# HOW. The probe compiles against a copy of lib/ whose `alloc` is wrapped (derived from the live
# lib/alloc.cyr by renaming its Linux `fn alloc`, exactly as alloc_failure_returns_zero.sh axis 5
# does): armed with k, the k-th alloc from now returns 0 and every other call is served. Each fn
# is driven for every k over its allocation count and must (a) return its sentinel, (b) have
# REACHED the k-th call (anti-vacuous: a fn that never allocated would pass without testing
# anything), and (c) SUCCEED at k = count + 1, so the count is exact.
#
# MUTATION LEDGER (6.6.10, measured — ONE check removed from the live lib/ each time):
#   * boxed_new's check                         -> rc 139 (stored through the refused alloc)
#   * sha1's `w` check (k=2)                    -> rc 139
#   * sigset_new's check (syscalls_x86_64_linux) -> rc 139
#   * chan_new's `buf` check (k=2)              -> rc 1   (returned a channel over a 0 buffer)
#   * normalize: the 6.6.9 step-buffer `return off` -> rc 1 (a SHORTER string, returned as success);
#     dropping the -1 propagation in the walk    -> rc 1 at the nested row (k=4)
#   * each of lib/ws.cyr's four checks (ws_new, the handshake buffer, the sender's masked copy,
#     CVE-53's ws_recv_frame payload) and lib/ws_server.cyr's six (ws_server_new, concat,
#     digest, ws_server_send_close, the recv buffer, the recv copy) -> rc 139 in its probe
#   * every lib/ file at its pre-6.6.10 state   -> rc 139 at the first row
# Linux x86_64 only (the harness is host-built); the static census covers the other targets.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: stdlib_alloc_refusal_sentinels: $CC missing"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: stdlib_alloc_refusal_sentinels: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT INT TERM
fail() { echo "FAIL: stdlib_alloc_refusal_sentinels: $*"; exit 1; }

mkdir -p "$W/fi"
cp -R "$ROOT/lib" "$W/fi/lib"
[ "$(grep -c '^fn alloc(size): i64 {$' "$ROOT/lib/alloc.cyr")" = "1" ] \
    || fail "lib/alloc.cyr no longer has exactly one 'fn alloc(size): i64 {' to wrap — update the fault-injection harness"
sed 's/^fn alloc(size): i64 {$/fn _fi_real_alloc(size): i64 {/' "$ROOT/lib/alloc.cyr" > "$W/fi/lib/alloc.cyr"
cat >> "$W/fi/lib/alloc.cyr" <<'CYR'

# ── gate-only fault injection (tests/gates/memory/stdlib_alloc_refusal_sentinels.sh) ──
var _fi_at = 0;      # armed: the _fi_at-th alloc from now returns 0; 0 = disarmed
var _fi_seen = 0;
fn alloc(size): i64 {
    if (_fi_at > 0) {
        _fi_seen = _fi_seen + 1;
        if (_fi_seen == _fi_at) { _fi_at = 0; return 0; }
    }
    return _fi_real_alloc(size);
}
fn _fi_arm(k): i64 { _fi_at = k; _fi_seen = 0; return 0; }
CYR

# The row helpers, shared by every probe (the ws client and server stdlibs declare the same
# WS_* names, so they cannot share one translation unit).
cat > "$W/fi/rows.cyr" <<'CYR'
var _rows = 0;

fn _bad(site, k, what): i64 {
    _fi_at = 0;
    syscall(1, 2, site, strlen(site));
    syscall(1, 2, " k=", 3);
    var d[8];
    store8(&d, 48 + k);
    syscall(1, 2, &d, 1);
    syscall(1, 2, ": ", 2);
    syscall(1, 2, what, strlen(what));
    syscall(1, 2, "\n", 1);
    syscall(60, 1);
    return 1;
}

# After a call under arm(k): `got` must be the sentinel AND the k-th alloc must have fired.
fn _refused(site, k, got, want): i64 {
    if (_fi_at != 0) { return _bad(site, k, "the k-th alloc was never reached (count is wrong)"); }
    if (got != want) { return _bad(site, k, "did not return its sentinel"); }
    _rows = _rows + 1;
    return 0;
}

# After a call under arm(count + 1): it must succeed and never reach the armed call.
fn _served(site, k, ok): i64 {
    if (_fi_at == 0) { return _bad(site, k, "allocated MORE than its stated count"); }
    _fi_at = 0;
    if (ok != 1) { return _bad(site, k, "failed with every allocation served"); }
    _rows = _rows + 1;
    return 0;
}

# Emit the probe's row count and exit 0 (the runner below parses "<n> rows").
fn _rows_done(): i64 {
    fmt_int(_rows);
    syscall(1, 1, " rows\n", 6);
    return 0;
}
CYR

cat > "$W/fi/probe.cyr" <<'CYR'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
include "lib/fmt.cyr"
include "lib/chrono.cyr"
include "lib/boxed.cyr"
include "lib/cffi.cyr"
include "lib/trait.cyr"
include "lib/regex.cyr"
include "lib/sha1.cyr"
include "lib/thread.cyr"
include "lib/unicode/casefold.cyr"
include "lib/unicode/normalize.cyr"
include "lib/tagged.cyr"
include "lib/net.cyr"
include "lib/http.cyr"
include "rows.cyr"

# str_len, or -1 for a refused (0) result — a served row must not dereference a refusal.
fn _norm_len(s): i64 {
    if (s == 0) { return 0 - 1; }
    return str_len(s);
}

fn main(): i64 {
    alloc_init();
    var sb[64];

    _fi_arm(1); _refused("boxed_new", 1, boxed_new(1, 2), 0);
    _fi_arm(2); _served("boxed_new", 2, boxed_new(1, 2) != 0);
    _fi_arm(1); _refused("cffi_struct_new", 1, cffi_struct_new(), 0);
    _fi_arm(2); _served("cffi_struct_new", 2, cffi_struct_new() != 0);
    _fi_arm(1); _refused("dur_new", 1, dur_new(1, 2), 0);
    _fi_arm(2); _served("dur_new", 2, dur_new(1, 2) != 0);

    # epoch_to_date: the month table (first use only), then the result.
    _fi_arm(1); _refused("epoch_to_date/_chrono_init_mdays", 1, epoch_to_date(86400), 0);
    _fi_arm(2); _refused("epoch_to_date", 2, epoch_to_date(86400), 0);
    _fi_arm(3); _served("epoch_to_date", 3, epoch_to_date(86400) != 0);
    _fi_arm(1); _refused("iso8601", 1, iso8601(86400), 0);
    _fi_arm(2); _refused("iso8601", 2, iso8601(86400), 0);
    _fi_arm(3); _served("iso8601", 3, iso8601(86400) != 0);
    _fi_arm(1); _refused("dt_format", 1, dt_format(86400000000000, "%Y"), 0);
    _fi_arm(2); _refused("dt_format", 2, dt_format(86400000000000, "%Y"), 0);
    _fi_arm(3); _served("dt_format", 3, dt_format(86400000000000, "%Y") != 0);

    _fi_arm(1); _refused("trait_obj_new", 1, trait_obj_new(1, 2), 0);
    _fi_arm(2); _served("trait_obj_new", 2, trait_obj_new(1, 2) != 0);
    _fi_arm(1); _refused("display_vtable", 1, display_vtable(1, 2), 0);
    _fi_arm(1); _refused("default_vtable", 1, default_vtable(1), 0);
    _fi_arm(1); _refused("eq_vtable", 1, eq_vtable(1), 0);
    _fi_arm(1); _refused("from_vtable", 1, from_vtable(1), 0);
    _fi_arm(1); _refused("_int_to_string", 1, _int_to_string(42), 0);

    _fi_arm(1); _refused("str_lower_cstr", 1, str_lower_cstr("AbC"), 0);
    _fi_arm(2); _served("str_lower_cstr", 2, str_lower_cstr("AbC") != 0);
    _fi_arm(1); _refused("str_upper_cstr", 1, str_upper_cstr("AbC"), 0);
    var s = str_from("hello world");
    _fi_arm(1); _refused("str_cstr", 1, str_cstr(s), 0);
    _fi_arm(1); _refused("str_from_buf", 1, str_from_buf("abc", 3), 0);
    _fi_arm(1); _refused("str_glob", 1, str_glob(s, "h*"), 0);
    var wo = str_from("world");
    var th = str_from("there");
    _fi_arm(1); _refused("str_replace", 1, str_replace(s, wo, th), 0);

    _fi_arm(1); _refused("regex_compile", 1, regex_compile("a+b"), 0);
    var re = regex_compile("a+b");
    if (re == 0) { return _bad("regex_compile", 0, "no NFA with every allocation served"); }
    # _re_pike_run: three lazy-init buffers (first match only), then two per run.
    _fi_arm(1); _refused("regex_match/_re_m_lazy_init cur", 1, regex_match(re, "aab"), 0);
    _fi_arm(2); _refused("regex_match/_re_m_lazy_init next", 2, regex_match(re, "aab"), 0);
    _fi_arm(3); _refused("regex_match/_re_m_lazy_init lastgen", 3, regex_match(re, "aab"), 0);
    _fi_arm(4); _refused("regex_match/_re_pike_run saves_scratch", 4, regex_match(re, "aab"), 0);
    # (arm 4 completed the lazy init, so from here a run makes exactly two allocations)
    _fi_arm(2); _refused("regex_match/_re_pike_run match_saves", 2, regex_match(re, "aab"), 0);
    _fi_arm(3); _served("regex_match", 3, regex_match(re, "aab") == 1);

    var dig[24];
    _fi_arm(1); _refused("sha1 buf", 1, sha1("abc", 3, &dig), 0 - 1);
    _fi_arm(2); _refused("sha1 w", 2, sha1("abc", 3, &dig), 0 - 1);
    _fi_arm(3); _served("sha1", 3, sha1("abc", 3, &dig) == 0);

    _fi_arm(1); _refused("mutex_new", 1, mutex_new(), 0);
    _fi_arm(2); _served("mutex_new", 2, mutex_new() != 0);
    _fi_arm(1); _refused("chan_new ch", 1, chan_new(4), 0);
    _fi_arm(2); _refused("chan_new buf", 2, chan_new(4), 0);
    _fi_arm(1); _refused("thread_create", 1, thread_create(0, 0), 0);
    _fi_arm(1); _refused("sigset_new", 1, sigset_new(), 0);
    _fi_arm(1); _refused("epoll_event_new", 1, epoll_event_new(1, 2), 0);
    _fi_arm(1); _refused("timerspec_new", 1, timerspec_new(1, 2), 0);

    var u = str_from("Hello");
    _fi_arm(1); _refused("str_lower_unicode buf", 1, str_lower_unicode(u), 0);
    _fi_arm(2); _refused("str_lower_unicode cp_out", 2, str_lower_unicode(u), 0);
    _fi_arm(1); _refused("str_upper_unicode buf", 1, str_upper_unicode(u), 0);
    _fi_arm(2); _refused("str_upper_unicode cp_out", 2, str_upper_unicode(u), 0);
    _fi_arm(1); _refused("str_normalize dec_buf", 1, str_normalize(u, NFC), 0);
    _fi_arm(2); _refused("str_normalize cp_slot", 2, str_normalize(u, NFC), 0);
    # 6.6.10 review: then ONE step buffer per decomposition step, recursively. A refused step
    # returned the offset unchanged — the cp "decomposed to nothing" — so a SHORTER string came
    # back as a success. k = 3 is 'H''s step (canonical and compat walkers); for U+00E9 k = 3 is
    # its own step and 4 / 5 are the nested steps for 'e' and U+0301 (the -1 must propagate up).
    _fi_arm(3); _refused("str_normalize step_buf NFC", 3, str_normalize(u, NFC), 0);
    _fi_arm(3); _refused("str_normalize step_buf NFKD (compat)", 3, str_normalize(u, NFKD), 0);
    var eb[8];
    store8(&eb, 0xC3);
    store8(&eb + 1, 0xA9);
    var ea = str_new(&eb, 2);
    _fi_arm(3); _refused("str_normalize step_buf U+00E9", 3, str_normalize(ea, NFD), 0);
    _fi_arm(4); _refused("str_normalize nested step_buf e", 4, str_normalize(ea, NFD), 0);
    _fi_arm(5); _refused("str_normalize nested step_buf U+0301", 5, str_normalize(ea, NFD), 0);
    _fi_arm(5); _refused("str_normalize nested step_buf U+0301 (compat)", 5, str_normalize(ea, NFKD), 0);
    _fi_arm(6); _refused("str_normalize out_buf", 6, str_normalize(ea, NFD), 0);
    _fi_arm(7); _refused("str_normalize str_new", 7, str_normalize(ea, NFD), 0);
    _fi_arm(8); _served("str_normalize U+00E9", 8, _norm_len(str_normalize(ea, NFD)) == 3);

    _fi_arm(1); _refused("_http_parse_url result", 1, _http_parse_url("http://h/p"), 0);
    _fi_arm(2); _refused("_http_parse_url host", 2, _http_parse_url("http://h/p"), 0);
    _fi_arm(1); _refused("_http_build_request", 1, _http_build_request("GET", "h", 80, "/"), 0);
    _fi_arm(1); _refused("_http_parse_response", 1, _http_parse_response("HTTP/1.1 200 OK\r\n\r\n", 19), 0);
    # http_get on an empty host: parse_url allocates its result then refuses, and the error
    # response is the SECOND allocation.
    _fi_arm(2); _refused("http_get (bad-url response)", 2, http_get("http://"), 0);

    return _rows_done();
}
var ec = main();
syscall(60, ec);
CYR


# ── the WebSocket client (lib/ws.cyr) — CVE-53's "the allocation is checked" half ──
# Frames come from a FILE in the probe's cwd, as ws_recv_frame_short_reads.tcyr does, so no
# socket is needed. ⚠ THE REFUSED-PAYLOAD ROW USES A ZERO-LENGTH FRAME ON PURPOSE: for a non-empty
# frame an unchecked alloc would read into address 0, get EFAULT, and close the connection — the
# right answer by accident. With plen = 0 nothing is read, so without the check the reader stores
# the NUL terminator at address 0 (rc 139).
cat > "$W/fi/ws_probe.cyr" <<'CYR'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
include "lib/fmt.cyr"
include "lib/tagged.cyr"
include "lib/net.cyr"
include "lib/bayan.cyr"
include "lib/ws.cyr"
include "rows.cyr"

# A ws handle (state OPEN) reading one unmasked FIN|TEXT frame of `n` <= 3 bytes ("abc").
# O_WRONLY|O_CREAT|O_TRUNC = 577. Allocates (ws_new) — call it BEFORE arming.
fn _frame_ws(n): i64 {
    var fb[8];
    store8(&fb, 0x81);
    store8(&fb + 1, n);
    memcpy(&fb + 2, "abc", 3);
    var wfd = sys_open("wsframe.bin", 577, 420);
    sys_write(wfd, &fb, 2 + n);
    sys_close(wfd);
    var ws = ws_new(sys_open("wsframe.bin", 0, 0));
    store64(ws + 8, WS_OPEN);
    return ws;
}

# 1 iff ws_recv_frame refused the frame the documented way: 0, len_out 0, connection CLOSED.
fn _recv_refused(ws): i64 {
    var op[8];
    var ln[8];
    store64(&ln, 99);
    var p = ws_recv_frame(ws, &op, &ln);
    if (p != 0) { return 0; }
    if (load64(&ln) != 0) { return 0; }
    if (ws_state(ws) != WS_CLOSED) { return 0; }
    return 1;
}

# 1 iff ws_recv_frame returned the n-byte payload with the connection still OPEN.
fn _recv_served(ws, n): i64 {
    var op[8];
    var ln[8];
    var p = ws_recv_frame(ws, &op, &ln);
    if (p == 0) { return 0; }
    if (load64(&ln) != n) { return 0; }
    if (ws_state(ws) != WS_OPEN) { return 0; }
    return 1;
}

# ws_connect's state, or -1 when it returned no handle.
fn _connect_state(r): i64 {
    if (r == 0) { return 0 - 1; }
    return ws_state(r);
}

fn main(): i64 {
    alloc_init();
    var key[32];

    _fi_arm(1); _refused("ws_new", 1, ws_new(3), 0);
    _fi_arm(2); _served("ws_new", 2, ws_new(3) != 0);

    # the Sec-WebSocket-Key base64 (k=1), then the request buffer sized from its inputs (k=2).
    # ⚠ k=1 is NOT armed: bayan_base64_encode (the lib/bayan.cyr fold) stores through its own
    # refused alloc — a bayan defect, reported for bayan's next release, not a lib/ws.cyr site.
    _fi_arm(2); _refused("_ws_handshake_request buf", 2, _ws_handshake_request("/p", "h", &key), 0);
    _fi_arm(3); _served("_ws_handshake_request", 3, _ws_handshake_request("/p", "h", &key) != 0);
    # ws_connect: no handle at all, or a CLOSED one when the request could not be built (fd -1:
    # the refusal must come before any I/O)
    _fi_arm(1); _refused("ws_connect ws_new", 1, ws_connect(0 - 1, "/p", "h"), 0);
    _fi_arm(3); _refused("ws_connect request buf", 3, _connect_state(ws_connect(0 - 1, "/p", "h")), WS_CLOSED);

    # the sender's masked copy
    var ow = ws_new(sys_open("wsout.bin", 577, 420));
    store64(ow + 8, WS_OPEN);
    _fi_arm(1); _refused("_ws_send_frame masked", 1, ws_send_text(ow, "hi"), 0 - 1);
    _fi_arm(2); _served("_ws_send_frame", 2, ws_send_text(ow, "hi") == 2);

    # CVE-53: the payload allocation (zero-length frame — see the note above this probe)
    var w0 = _frame_ws(0);
    _fi_arm(1); _refused("ws_recv_frame payload (empty frame)", 1, _recv_refused(w0), 1);
    var w3 = _frame_ws(3);
    _fi_arm(1); _refused("ws_recv_frame payload (3 bytes)", 1, _recv_refused(w3), 1);
    var w0b = _frame_ws(0);
    _fi_arm(2); _served("ws_recv_frame (empty frame)", 2, _recv_served(w0b, 0));
    var w3b = _frame_ws(3);
    _fi_arm(2); _served("ws_recv_frame (3 bytes)", 2, _recv_served(w3b, 3));
    return _rows_done();
}
var ec = main();
syscall(60, ec);
CYR

# ── the WebSocket server (lib/ws_server.cyr) ──
# sandhi_server_find_header is stubbed WITHOUT allocating (lib/sandhi.cyr would drag the TLS
# stack in for one symbol, and its allocs are sandhi's, not this file's), so the handshake's
# first allocations are its own: concat (k=1), digest (k=2), then sha1's two (k=3, 4).
# ⚠ ws_server_recv's two rows follow the same zero-length reasoning as ws_recv_frame's: an
# unchecked recv BUFFER only writes through (store8 at 0 + 0) for an empty frame, and an
# unchecked OUT copy only does (memcpy to 0) for a non-empty one.
cat > "$W/fi/wss_probe.cyr" <<'CYR'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
include "lib/fmt.cyr"
include "lib/tagged.cyr"
include "lib/net.cyr"
include "lib/bayan.cyr"

fn sandhi_server_find_header(buf, blen, name): i64 {
    if (streq(name, "Upgrade") == 1) { return "websocket"; }
    if (streq(name, "Connection") == 1) { return "Upgrade"; }
    if (streq(name, "Sec-WebSocket-Version") == 1) { return "13"; }
    if (streq(name, "Sec-WebSocket-Key") == 1) { return "dGhlIHNhbXBsZSBub25jZQ=="; }
    return 0;
}
include "lib/ws_server.cyr"
include "rows.cyr"

# A server handle reading one unmasked FIN|TEXT frame of `n` <= 3 bytes. Allocates — call it
# BEFORE arming.
fn _frame_wss(n): i64 {
    var fb[8];
    store8(&fb, 0x81);
    store8(&fb + 1, n);
    memcpy(&fb + 2, "abc", 3);
    var wfd = sys_open("wssframe.bin", 577, 420);
    sys_write(wfd, &fb, 2 + n);
    sys_close(wfd);
    return ws_server_new(sys_open("wssframe.bin", 0, 0));
}

fn main(): i64 {
    alloc_init();
    var ofd = sys_open("wssout.bin", 577, 420);

    _fi_arm(1); _refused("ws_server_new", 1, ws_server_new(ofd), 0);
    _fi_arm(2); _served("ws_server_new", 2, ws_server_new(ofd) != 0);

    _fi_arm(1); _refused("ws_server_handshake concat", 1, ws_server_handshake(ofd, "x", 1), 0);
    _fi_arm(2); _refused("ws_server_handshake digest", 2, ws_server_handshake(ofd, "x", 1), 0);
    _fi_arm(3); _refused("ws_server_handshake sha1 buf", 3, ws_server_handshake(ofd, "x", 1), 0);
    _fi_arm(4); _refused("ws_server_handshake sha1 w", 4, ws_server_handshake(ofd, "x", 1), 0);

    var ws = ws_server_new(ofd);
    _fi_arm(1); _refused("ws_server_send_close payload", 1, ws_server_send_close(ws, 1000, "bye"), 0 - 1);
    _fi_arm(2); _served("ws_server_send_close", 2, ws_server_send_close(ws, 1000, "bye") == 0);

    # the recv buffer is lazy (first use), then one copy per data frame
    var r0 = _frame_wss(0);
    _fi_arm(1); _refused("ws_server_recv buffer (empty frame)", 1, ws_server_recv(r0), 0);
    var r3 = _frame_wss(3);
    _fi_arm(2); _refused("ws_server_recv out (3 bytes)", 2, ws_server_recv(r3), 0);
    var r3b = _frame_wss(3);
    _fi_arm(2); _served("ws_server_recv", 2, ws_server_recv(r3b) != 0);
    return _rows_done();
}
var ec = main();
syscall(60, ec);
CYR

# Compile and run one probe from $W/fi; leaves its row count in $_n (fails the gate on anything
# else). Called directly, never in $(...), so a `fail` inside it ends the gate AND is printed.
_run_probe() {
    _p=$1
    rc=0
    ( cd "$W/fi" && "$CC" < "$_p.cyr" > "$W/$_p" 2> "$W/$_p.err" ) || rc=$?
    [ "$rc" = 0 ] && [ -s "$W/$_p" ] || { grep -m5 'error' "$W/$_p.err" | sed 's/^/      /'; fail "the fault-injection $_p did not compile (rc $rc)"; }
    chmod +x "$W/$_p"
    rc=0
    _out=$(cd "$W" && "./$_p" 2> "$W/$_p.run.err") || rc=$?
    if [ "$rc" != 0 ]; then
        sed 's/^/      /' "$W/$_p.run.err" | head -5
        fail "$_p exited $rc — a refused allocation was written through (139 = SIGSEGV) or returned the wrong value"
    fi
    _n=$(printf '%s\n' "$_out" | sed -n 's/^\([0-9][0-9]*\) rows$/\1/p' | tail -1)
    [ -n "$_n" ] || fail "$_p printed no row count — it did not run to the end"
}
_run_probe probe; n=$_n
[ "$n" -ge 67 ] || fail "only $n rows ran in probe (floor 67) — the probe is not exercising the sites it names"
_run_probe ws_probe; nw=$_n
[ "$nw" -ge 12 ] || fail "only $nw rows ran in ws_probe (floor 12)"
_run_probe wss_probe; ns=$_n
[ "$ns" -ge 11 ] || fail "only $ns rows ran in wss_probe (floor 11)"
echo "PASS: stdlib_alloc_refusal_sentinels ($n + $nw ws + $ns ws_server rows: every refused alloc returned its sentinel, every count exact)"

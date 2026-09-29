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

    _fi_arm(1); _refused("_http_parse_url result", 1, _http_parse_url("http://h/p"), 0);
    _fi_arm(2); _refused("_http_parse_url host", 2, _http_parse_url("http://h/p"), 0);
    _fi_arm(1); _refused("_http_build_request", 1, _http_build_request("GET", "h", "/"), 0);
    _fi_arm(1); _refused("_http_parse_response", 1, _http_parse_response("HTTP/1.1 200 OK\r\n\r\n", 19), 0);
    # http_get on an empty host: parse_url allocates its result then refuses, and the error
    # response is the SECOND allocation.
    _fi_arm(2); _refused("http_get (bad-url response)", 2, http_get("http://"), 0);

    fmt_int(_rows);
    syscall(1, 1, " rows\n", 6);
    return 0;
}
var ec = main();
syscall(60, ec);
CYR

rc=0
( cd "$W/fi" && "$CC" < probe.cyr > "$W/probe" 2> "$W/probe.err" ) || rc=$?
[ "$rc" = 0 ] && [ -s "$W/probe" ] || { grep -m5 'error' "$W/probe.err" | sed 's/^/      /'; fail "the fault-injection probe did not compile (rc $rc)"; }
chmod +x "$W/probe"
rc=0
out=$(cd "$W" && ./probe 2> "$W/run.err") || rc=$?
if [ "$rc" != 0 ]; then
    sed 's/^/      /' "$W/run.err" | head -5
    fail "the probe exited $rc — a refused allocation was written through (139 = SIGSEGV) or returned the wrong value"
fi
n=$(printf '%s\n' "$out" | sed -n 's/^\([0-9][0-9]*\) rows$/\1/p' | tail -1)
[ -n "$n" ] || fail "the probe printed no row count — it did not run to the end"
[ "$n" -ge 58 ] || fail "only $n rows ran (floor 58) — the probe is not exercising the sites it names"
echo "PASS: stdlib_alloc_refusal_sentinels ($n rows: every refused alloc returned its sentinel, every count exact)"

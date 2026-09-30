#!/bin/sh
# 6.6.12 (B10, S-B1) — cbt/core.cyr `_macho_fill_environ` never writes past its buffer and
# returns at most cap - 1.
#
# THE BUG. On macOS the CLI has no /proc/self/environ, so `_macho_fill_environ(buf, cap)`
# flattens the entry-stack envp into buf as NUL-separated NAME=VALUE. The v6.0.34 loop
# bounded each entry's payload bytes (`if (pos < cap - 1)`) but stored each entry's NUL
# UNCONDITIONALLY, so an environment larger than the buffer returned pos > cap — and all
# four callers (`_cbt_env_is_1`, `_cbt_env_int`, `_cbt_env_str`, `find_tools`) then write
# their own terminator at `buf + pos`. With 40 x 25-byte entries and cap 64 the 6.6.11 body
# returned 101 and overwrote 37 bytes of the allocation after the buffer.
#
# THE CHECK. The macOS-only fn is extracted verbatim from cbt/core.cyr into an x86 LOGIC
# probe (it is pure byte shuffling; only `_macho_envp` is stubbed, to return a synthetic
# envp), with the buffer carved from the front of one allocation whose tail is a 0xA5
# canary. Axes:
#   1  40 x 25-byte entries, cap 64: returns <= 63 (exactly 50: two whole entries), the
#      canary is intact, and the caller-style `store8(buf + n, 0)` stays inside the buffer.
#   2  no partial entry: every NUL-separated piece in buf is a WHOLE 24-byte entry.
#   3  one oversized entry is DROPPED, not truncated, and a HOME= after it still lands whole
#      (a truncated "HOME=/Us" must never be matchable).
#   4  the boundary: a 62-byte entry (63 with its NUL) fits cap 64 exactly (returns 63); a
#      63-byte entry does not and is dropped (returns 0).
#   5  an empty envp and a null envp return 0.
# The real-hardware half (a >32 KB environment through `cyrius` on ecb and ach, and HOME /
# CYRIUS_HOME still resolving for a normal build) was run at 6.6.12 and is recorded in the
# CHANGELOG; nothing here needs a Mac.
#
# MUTATION LEDGER (2026-09-30, 6.6.12): `MACHO_ENV_SRC=<the 2bc29059 cbt/core.cyr>` (the
# 6.6.11 body) FAILS axes 1-4 (canary overwritten, 10 checks red); the fixed body with the
# rewind removed (a partially copied entry kept) FAILS axes 1-4 (6 checks red); with the
# NUL-room check removed (`pos >= cap - 1` dropped from the keep test) FAILS axis 4 (the
# 63-byte entry returns 64, one past the last byte a caller may terminate at).
#
# Exit 77 = could not run (the compiler is missing).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=macho_fill_environ_bounded
SRC=${MACHO_ENV_SRC:-"$ROOT/cbt/core.cyr"}

[ -x "$CC" ] || { echo "SKIP: $NAME — $CC missing"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT

awk '/^fn _macho_fill_environ\(/ { on = 1 } on { print } on && /^}/ { exit }' "$SRC" > "$T/fn.cyr"
if ! grep -q '^fn _macho_fill_environ(' "$T/fn.cyr" || ! grep -q '^}' "$T/fn.cyr"; then
    echo "FAIL: $NAME — could not extract fn _macho_fill_environ from $SRC (renamed or moved?)"; exit 1
fi

{
cat <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"

var _t_envp = 0;
fn _macho_envp(): i64 { return _t_envp; }
EOF
cat "$T/fn.cyr"
cat <<'EOF'

# A NUL-terminated entry: `name` then `fill` repeated until the entry is `len` bytes
# long (not counting its NUL).
fn _entry(name, fill, len): i64 {
    var p = alloc(len + 1);
    var nl = strlen(name);
    memcpy(p, name, nl);
    var i = nl;
    while (i < len) { store8(p + i, fill); i = i + 1; }
    store8(p + len, 0);
    return p;
}

var _fails = 0;
fn _chk(ok, what): i64 {
    if (ok == 0) {
        _fails = _fails + 1;
        var m = "  FAIL: ";
        syscall(1, 2, m, strlen(m));
        syscall(1, 2, what, strlen(what));
        syscall(1, 2, "\n", 1);
    }
    return 0;
}

# The buffer is the first `cap` bytes of one allocation; the next 256 bytes are the canary.
var _region = 0;
fn _fill(cap): i64 {
    memset(_region, 0, cap);
    memset(_region + cap, 0xA5, 256);
    return _macho_fill_environ(_region, cap);
}
fn _canary_ok(cap): i64 {
    var i = 0;
    while (i < 256) {
        if (load8(_region + cap + i) != 0xA5) { return 0; }
        i = i + 1;
    }
    return 1;
}

fn main(): i64 {
    alloc_init();
    _region = alloc(4096);
    var envp = alloc(64 * 8);

    # axes 1-2: 40 x 25-byte entries (24 + NUL), cap 64
    var i = 0;
    while (i < 40) {
        var nm = alloc(8);
        store8(nm, 75); store8(nm + 1, 48 + i / 10); store8(nm + 2, 48 + i % 10);
        store8(nm + 3, 61); store8(nm + 4, 0);
        store64(envp + i * 8, _entry(nm, 118, 24));
        i = i + 1;
    }
    store64(envp + 40 * 8, 0);
    _t_envp = envp;
    var n = _fill(64);
    _chk(n <= 63, "axis 1: 40 x 25 B into cap 64 returned more than cap - 1");
    _chk(n == 50, "axis 1: expected exactly two whole entries (50 bytes)");
    _chk(_canary_ok(64), "axis 1: the canary after the buffer was overwritten");
    if (n >= 0 && n <= 63) { store8(_region + n, 0); }
    _chk(_canary_ok(64), "axis 1: the caller-style terminator landed past the buffer");
    var p = 0;
    var bad = 0;
    while (p < n) {
        var l = strlen(_region + p);
        if (l != 24) { bad = 1; }
        p = p + l + 1;
    }
    _chk(bad == 0, "axis 2: a piece of buf is not a whole 24-byte entry (a partial copy was kept)");

    # axis 3: an oversized entry is dropped whole; HOME after it lands whole
    store64(envp, _entry("BIG=", 120, 100));
    store64(envp + 8, "HOME=/Users/me");
    store64(envp + 16, 0);
    n = _fill(64);
    _chk(n == 15, "axis 3: expected only HOME=/Users/me (15 bytes with its NUL)");
    _chk(memeq(_region, "HOME=/Users/me", 15) == 1, "axis 3: HOME= is not the first, whole entry");
    _chk(_canary_ok(64), "axis 3: the canary was overwritten");
    # ... and a HOME that does not fit is dropped, never truncated to a matchable prefix
    store64(envp, _entry("HOME=/Us", 101, 80));
    store64(envp + 8, 0);
    n = _fill(64);
    _chk(n == 0, "axis 3: a HOME= longer than the buffer was kept (truncated) instead of dropped");
    _chk(_canary_ok(64), "axis 3: the canary was overwritten (long HOME)");

    # axis 4: the exact boundary
    store64(envp, _entry("A=", 97, 62));
    store64(envp + 8, 0);
    n = _fill(64);
    _chk(n == 63, "axis 4: a 62-byte entry must fit cap 64 exactly (63 with its NUL)");
    _chk(_canary_ok(64), "axis 4: the canary was overwritten (62-byte entry)");
    store64(envp, _entry("A=", 97, 63));
    n = _fill(64);
    _chk(n == 0, "axis 4: a 63-byte entry has no room for its NUL in cap 64 and must be dropped");
    _chk(_canary_ok(64), "axis 4: the canary was overwritten (63-byte entry)");

    # axis 5: empty and null envp
    store64(envp, 0);
    _chk(_fill(64) == 0, "axis 5: an empty envp must return 0");
    _t_envp = 0;
    _chk(_fill(64) == 0, "axis 5: a null envp must return 0");

    return _fails;
}
var r = main();
syscall(60, r);
EOF
} > "$T/probe.cyr"

if ! ( cd "$ROOT" && "$CC" < "$T/probe.cyr" > "$T/probe" 2> "$T/cc.err" ); then
    echo "FAIL: $NAME — the extracted probe did not compile"; sed -n '1,5p' "$T/cc.err"; exit 1
fi
chmod +x "$T/probe"
( ulimit -c 0; "$T/probe" ) > "$T/out" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
    cat "$T/out"
    echo "FAIL: $NAME — _macho_fill_environ is not bounded (probe exit $rc)"; exit 1
fi
echo "PASS: $NAME (returns <= cap - 1, whole entries only, oversized entries dropped, canary intact)"
exit 0

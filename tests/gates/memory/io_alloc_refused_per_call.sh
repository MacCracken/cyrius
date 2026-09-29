#!/bin/sh
# Gate: EVERY allocation check lib/io.cyr gained at 6.6.8 holds when ITS call ALONE is refused.
#
# ⛔ THE DEFECT (6.6.7 review). `_io_tmp_name`, `_io_link_join`, `_io_replace_target` (twice)
# and `getenv` stored through an unchecked alloc() on the next line, so a refused allocation was
# a SIGSEGV inside file_write_atomic / file_replace_atomic / getenv instead of -ENOMEM / a miss.
# tests/tcyr/crossos/io_refused_alloc.tcyr pins the FIRST check on each path on real hardware
# by refusing EVERY allocation (ALLOC_MAX = 0) — a size refusal is monotonic, so it can never
# reach the second or third check on a path (the link join, the absolute-link copy). This gate
# does: it compiles a probe against a copy of lib/ whose `alloc` is wrapped (the harness of
# tests/gates/memory/alloc_failure_returns_zero.sh axis 5, derived from the live lib/alloc.cyr
# so it cannot drift), and for each path refuses the k-th allocation alone, for every k.
#
# ROWS (x86_64 Linux; each with an unchanged target file and no temp file left behind)
#   1. file_write_atomic                              k=1          -> -12;  k=2 -> 0
#   2. file_replace_atomic through a RELATIVE symlink k=1 (lb), 2 (the join), 3 (tmp) -> -12
#                                                     k=4          -> 0, the link's target written
#   3. file_replace_atomic through an ABSOLUTE link   k=1 (lb), 2 (the copy), 3 (tmp) -> -12
#                                                     k=4          -> 0
#   4. getenv (environment already loaded)            k=1          -> 0;    k=2 -> the value
# ANTI-VACUOUS both ways: the k-th call must actually be reached, and k = count + 1 succeeds, so
# the counts above are exact and an allocation added later is caught by the same loop.
#
# MUTATION LEDGER (6.6.8, each check removed ALONE from a scratch copy of lib/io.cyr)
#   * the 6.6.7 lib/io.cyr                                   -> rc 139
#   * `_io_tmp_name`'s check (file_write_atomic's `tmp == 0`) -> "file_write_atomic k=1: a refused
#                                                               temp name was not -ENOMEM"
#   * `_io_replace_target`'s `lb == 0`                        -> "replace-relative k=1: ... not -ENOMEM"
#   * `_io_link_join`'s `out == 0`                            -> rc 139
#   * `_io_replace_target`'s `cur == 0` after the join        -> rc 139
#   * the absolute-link copy's `ab == 0`                      -> rc 139
#   * getenv's `result == 0`                                  -> rc 139
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: io_alloc_refused_per_call: build/cycc missing"; exit 1; }
case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) : ;;
    *) echo "SKIP: io_alloc_refused_per_call: x86_64 Linux only (the wrapper targets the Linux alloc arm)"; exit 77 ;;
esac
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: io_alloc_refused_per_call: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT

cp -R "$ROOT/lib" "$W/lib"
if [ "$(grep -c '^fn alloc(size): i64 {$' "$ROOT/lib/alloc.cyr")" != "1" ]; then
    echo "FAIL: io_alloc_refused_per_call: lib/alloc.cyr no longer has exactly one 'fn alloc(size): i64 {' to wrap"
    exit 1
fi
sed 's/^fn alloc(size): i64 {$/fn _fi_real_alloc(size): i64 {/' "$ROOT/lib/alloc.cyr" > "$W/lib/alloc.cyr"
cat >> "$W/lib/alloc.cyr" <<'CYR'

# ── gate-only fault injection (tests/gates/memory/io_alloc_refused_per_call.sh) ──
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

mkdir -p "$W/run"
cat > "$W/fi.cyr" <<'CYR'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/io.cyr"

# "<row> k=<k>: <what>" on stderr, exit 1.
fn _bad(row, k, what): i64 {
    _fi_at = 0;
    var d[8];
    store8(&d, 48 + k);
    syscall(1, 2, row, strlen(row));
    syscall(1, 2, " k=", 3);
    syscall(1, 2, &d, 1);
    syscall(1, 2, ": ", 2);
    syscall(1, 2, what, strlen(what));
    syscall(1, 2, "\n", 1);
    return 1;
}

# 1 iff `path` holds exactly the `n` bytes at `want`.
fn _holds(path, want, n): i64 {
    var b[64];
    var r = file_read_all(path, &b, 63);
    if (r != n) { return 0; }
    if (memeq(&b, want, n) == 0) { return 0; }
    return 1;
}

# One replace row: `path` resolves to "tgt.txt" through a link; `count` allocations.
fn _replace_row(row, path, count): i64 {
    var k = 1;
    while (k <= count + 1) {
        _fi_at = 0;
        if (file_write_atomic("tgt.txt", "orig", 4) != 0) { return _bad(row, k, "setup: could not write tgt.txt"); }
        _fi_arm(k);
        var r = file_replace_atomic(path, "newbytes", 8);
        if (k <= count) {
            if (_fi_at != 0) { return _bad(row, k, "never reached the k-th allocation"); }
            if (r != 0 - 12) { return _bad(row, k, "a refused allocation was not -ENOMEM"); }
            if (_holds("tgt.txt", "orig", 4) == 0) { return _bad(row, k, "the target changed"); }
        } else {
            _fi_at = 0;
            if (r != 0) { return _bad(row, k, "failed with every allocation served (the count moved)"); }
            if (_holds("tgt.txt", "newbytes", 8) == 0) { return _bad(row, k, "the link's target was not written"); }
        }
        k = k + 1;
    }
    return 0;
}

fn main(): i64 {
    alloc_init();
    # row 1: file_write_atomic — the temp name
    var k = 1;
    while (k <= 2) {
        _fi_at = 0;
        xunlink("w.txt");
        _fi_arm(k);
        var r = file_write_atomic("w.txt", "abc", 3);
        if (k == 1) {
            if (_fi_at != 0) { return _bad("file_write_atomic", k, "never reached the k-th allocation"); }
            if (r != 0 - 12) { return _bad("file_write_atomic", k, "a refused temp name was not -ENOMEM"); }
            if (file_exists("w.txt") != 0) { return _bad("file_write_atomic", k, "the file was created"); }
        } else {
            _fi_at = 0;
            if (r != 0) { return _bad("file_write_atomic", k, "failed with every allocation served"); }
        }
        k = k + 1;
    }
    xunlink("w.txt");
    # rows 2-3: a relative and an absolute link to tgt.txt
    if (file_write_atomic("tgt.txt", "orig", 4) != 0) { return _bad("setup", 0, "tgt.txt"); }
    if (xsymlink("tgt.txt", "rel.lnk") != 0) { return _bad("setup", 0, "relative symlink"); }
    var cwd[4096];
    if (syscall(79, &cwd, 4000) <= 0) { return _bad("setup", 0, "getcwd"); }
    var abs = alloc(4200);
    var cl = strlen(&cwd);
    memcpy(abs, &cwd, cl);
    memcpy(abs + cl, "/tgt.txt", 9);
    if (xsymlink(abs, "abs.lnk") != 0) { return _bad("setup", 0, "absolute symlink"); }
    if (_replace_row("replace-relative", "rel.lnk", 3) != 0) { return 1; }
    if (_replace_row("replace-absolute", "abs.lnk", 3) != 0) { return 1; }
    # row 4: getenv, environment already loaded
    if (getenv("CYRIUS_FI_PROBE") == 0) { return _bad("getenv", 0, "setup: CYRIUS_FI_PROBE not visible"); }
    k = 1;
    while (k <= 2) {
        _fi_arm(k);
        var v = getenv("CYRIUS_FI_PROBE");
        if (k == 1) {
            if (_fi_at != 0) { return _bad("getenv", k, "never reached the k-th allocation"); }
            if (v != 0) { return _bad("getenv", k, "returned a value although its copy was refused"); }
        } else {
            _fi_at = 0;
            if (v == 0) { return _bad("getenv", k, "missed with every allocation served"); }
            if (streq(v, "present") == 0) { return _bad("getenv", k, "the wrong value"); }
        }
        k = k + 1;
    }
    syscall(1, 1, "returned\n", 9);
    return 0;
}
var ec = main();
syscall(60, ec);
CYR
( cd "$W" && "$CC" < fi.cyr > fi 2> fi.err ) || { echo "FAIL: io_alloc_refused_per_call: the probe did not compile: $(grep -m2 -i 'error' "$W/fi.err")"; exit 1; }
if grep -q '^warning: undefined function' "$W/fi.err"; then
    echo "FAIL: io_alloc_refused_per_call: the probe has undefined functions: $(grep -m2 '^warning: undefined' "$W/fi.err")"
    exit 1
fi
chmod +x "$W/fi"
rc=0; out=$( cd "$W/run" && ulimit -c 0; CYRIUS_FI_PROBE=present "$W/fi" 2> "$W/fi.stderr" ) || rc=$?
if [ "$rc" -ne 0 ] || [ "$out" != "returned" ]; then
    why=""; [ "$rc" = 139 ] && why=" (SIGSEGV: a store through the refused allocation)"
    echo "FAIL: io_alloc_refused_per_call: exited $rc$why: $(head -1 "$W/fi.stderr")"
    exit 1
fi
# No temp left behind by ANY row: the run dir holds exactly the three fixtures the probe made.
left=$(cd "$W/run" && ls -A | sort | tr '\n' ' ')
if [ "$left" != "abs.lnk rel.lnk tgt.txt " ]; then
    echo "FAIL: io_alloc_refused_per_call: the run dir holds [$left] — a refused path left a file behind"
    exit 1
fi
echo "PASS: io_alloc_refused_per_call (file_write_atomic 1, file_replace_atomic via a relative and an absolute link 3 each, getenv 1 — each allocation refused alone is -ENOMEM / a miss, the target unchanged, no temp left)"
exit 0

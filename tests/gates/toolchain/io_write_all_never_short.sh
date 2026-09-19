#!/bin/sh
# io_write_all_never_short.sh — v6.6.6 bite 17a. A lib/io.cyr helper that promises to write the
# WHOLE buffer writes the whole buffer, or reports an ERROR. It never returns a positive count
# smaller than `len`.
#
# ⛔ THE DEFECT. write(2) may write FEWER bytes than asked and return that count as SUCCESS
# (full disk, RLIMIT_FSIZE, a signal, a pipe). `file_write_all`, `file_append_locked` and
# `file_write_all_r` each made ONE write and returned that count, so every caller testing only
# `< 0` — the documented check, and what lib/bayan.cyr, cbt/ and the vendored sigil copy do —
# accepted a truncated file as a good one. Measured on this tree before the fix, under
# `ulimit -f 2` (1024 B): file_write_all(p, buf, 4096) returned 1024 and left a 1024-byte file;
# file_append_locked the same; file_write_all_r returned Ok(1024). After: -27 (-EFBIG), -27,
# Err. file_write_atomic already looped (bite 13) — all four now share `_io_write_full`.
#
# ⚠ THE FD-LEVEL PRIMITIVES ARE NOT IN SCOPE AND MUST NOT BE "FIXED". `file_write` and
# `file_write_r` are raw write(2) and say so in their own comments ("caller may need to loop");
# looping there would silently change a documented primitive. The contract this gate pins is
# the one the NAME makes: `_all` (and the whole-record append) means all.
#
# ⚠ HOW A FULL DISK IS REPRODUCED WITHOUT A MOUNT: RLIMIT_FSIZE with SIGXFSZ ignored gives the
# writer a real full disk's exact sequence — the write that crosses the limit comes back SHORT,
# the next one fails EFBIG. Without `trap '' XFSZ` the kernel kills the probe (rc 153) and the
# gate would measure the signal, not the return value. `ulimit -f` counts 512-byte blocks on
# some shells and 1024 on others; every axis here is written to hold under both (it asserts a
# NEGATIVE return, never a particular byte count).
#
# AXES
#   1. ANTI-VACUOUS, unconstrained: each of the three helpers returns exactly LEN and leaves a
#      LEN-byte file. The size is read back with stat(1) — a DIFFERENT mechanism from the
#      return value the probe prints, so a helper that lies about its count is still caught.
#   2. Under RLIMIT_FSIZE: each returns a NEGATIVE errno (never a positive short count), the
#      Result variant is Err, and the file left behind is SHORTER than LEN — i.e. the caller
#      is told, and what is on disk is genuinely partial (file_write_all is not crash-safe by
#      design; file_write_atomic is the crash-safe one and axis 4 pins that it also errors).
#   3. STATIC: every helper in lib/io.cyr whose name promises the whole buffer
#      (`*_write_all*`, `*_append_locked*`, `file_write_atomic`) routes through
#      `_io_write_full`, and `_io_write_full` itself contains a loop. DERIVED from the source
#      (the fn list is grepped, not hand-written), so a new `_all` helper is covered the day it
#      lands. Self-tested on a fixture carrying the old one-shot shape.
#   4. The crash-safe writer under the same limit: file_write_atomic returns negative, leaves
#      the ORIGINAL file byte-for-byte, and leaves no `.cyrtmp.` sibling behind.
#
# MUTATION LEDGER (measured 6.6.6, each by editing a COPY of lib/io.cyr in the scratch dir)
#   a. file_write_all back to one `file_write`          -> axis 2 FAIL (returned 1024, positive)
#   b. file_append_locked back to one `file_write`      -> axis 2 FAIL (returned 1024)
#   c. file_write_all_r back to one `sys_write`         -> axis 2 FAIL (Ok(1024), tag 0)
#   d. _io_write_full returning `w` after ONE write     -> axes 2 (all three helpers, 1024) and
#      (i.e. the loop body without the loop)               4 FAIL. NOT axis 1: unconstrained the
#                                                          single write already moves all 4096,
#                                                          which is why only a constrained run
#                                                          can see this shape at all.
#   e. file_write_atomic's loop replaced by one write   -> axes 3 and 4 FAIL (original replaced
#                                                          by a 1024-byte file)
#   f. axis-3 detector pointed at a fixture with the    -> axis 3 self-test FAIL (4 of 4)
#      pre-fix bodies
#   `_io_write_full`'s `w == 0` guard has no mutant: a 0-byte write is unreachable on a regular
#   file here. It is a HANG guard (an endless loop making no progress), documented not claimed.
# Real tree -> PASS.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: io_write_all_never_short: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
FAIL=0
fail() { echo "FAIL: $*"; FAIL=1; }
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: build/cycc missing"; exit 1; }

LEN=4096

# ── the probe: exercise every whole-buffer helper and print "<name> <return>" ──
cat > "$D/probe.cyr" <<'CYR'
include "lib/alloc.cyr";
include "lib/vec.cyr";
include "lib/io.cyr";
include "lib/string.cyr";
include "lib/fmt.cyr";

fn emit(pfx, n) {
    syscall(1, 1, pfx, strlen(pfx));
    syscall(1, 1, " ", 1);
    fmt_int(n);
    syscall(1, 1, "\n", 1);
}

fn main(): i64 {
    var len = 4096;
    var buf = alloc(len);
    var i = 0;
    while (i < len) { store8(buf + i, 65); i = i + 1; }
    emit("file_write_all", file_write_all("w_all.txt", buf, len));
    emit("file_append_locked", file_append_locked("w_app.txt", buf, len));
    var tag, val = file_write_all_r("w_res.txt", buf, len);
    emit("file_write_all_r_tag", tag);
    emit("file_write_all_r_val", val);
    emit("file_write_atomic", file_write_atomic("w_atomic.txt", buf, len));
    return 0;
}
CYR
"$CC" < "$D/probe.cyr" > "$D/probe" 2> "$D/probe.err"; brc=$?
if [ "$brc" -ne 0 ] || [ ! -s "$D/probe" ]; then
    echo "FAIL: the io write probe does not build (rc=$brc):"; tail -5 "$D/probe.err" | sed 's/^/      /'; exit 1
fi
grep -q '^warning: undefined function' "$D/probe.err" && { echo "FAIL: the probe compiled with undefined functions — it would trap, not measure:"; grep '^warning: undefined' "$D/probe.err" | sed 's/^/      /'; exit 1; }
chmod +x "$D/probe"

# _ret <outfile> <name> — the value the probe printed for <name>
_ret() { awk -v n="$2" '$1 == n { print $2 }' "$1"; }
# _sz <file> — bytes on disk, via stat(1): a DIFFERENT mechanism from the probe's own count
_sz() { [ -f "$1" ] && wc -c < "$1" | tr -d ' ' || echo MISSING; }

# ── axis 1: unconstrained — every helper writes the WHOLE buffer and says so ──
mkdir -p "$D/ok"
( cd "$D/ok" && ulimit -c 0 && exec "$D/probe" ) > "$D/a1.out" 2>&1 || true
a1=0
for h in file_write_all file_append_locked; do
    [ "$(_ret "$D/a1.out" "$h")" = "$LEN" ] || { fail "axis 1: $h returned '$(_ret "$D/a1.out" "$h")', expected $LEN"; a1=1; }
done
[ "$(_ret "$D/a1.out" file_write_all_r_tag)" = "0" ] || { fail "axis 1: file_write_all_r is not Ok (tag $(_ret "$D/a1.out" file_write_all_r_tag))"; a1=1; }
[ "$(_ret "$D/a1.out" file_write_all_r_val)" = "$LEN" ] || { fail "axis 1: file_write_all_r returned Ok($(_ret "$D/a1.out" file_write_all_r_val)), expected Ok($LEN)"; a1=1; }
[ "$(_ret "$D/a1.out" file_write_atomic)" = "0" ] || { fail "axis 1: file_write_atomic returned $(_ret "$D/a1.out" file_write_atomic), expected 0"; a1=1; }
for f in w_all.txt w_app.txt w_res.txt w_atomic.txt; do
    [ "$(_sz "$D/ok/$f")" = "$LEN" ] || { fail "axis 1: $f is $(_sz "$D/ok/$f") bytes on disk, expected $LEN"; a1=1; }
done
[ "$a1" = 0 ] && echo "  ok: axis 1: unconstrained, all 4 whole-buffer helpers write $LEN bytes and return it"

# ── axis 2: under RLIMIT_FSIZE a SHORT write is an ERROR, never a positive count ──
mkdir -p "$D/lim"
rc=0; ( cd "$D/lim" && ulimit -c 0 && trap '' XFSZ && ulimit -f 2 && exec "$D/probe" ) > "$D/a2.out" 2>&1 || rc=$?
a2=0
[ "$rc" -ne 153 ] || { fail "axis 2: the probe was KILLED by SIGXFSZ — the ignore did not take, the axis measured nothing"; a2=1; }
for h in file_write_all file_append_locked; do
    v=$(_ret "$D/a2.out" "$h")
    case "$v" in
        -*) : ;;
        "") fail "axis 2: $h printed nothing (probe died early?)"; a2=1 ;;
        *)  fail "axis 2: $h returned $v — a positive SHORT count reported as success (expected a negative errno)"; a2=1 ;;
    esac
done
[ "$(_ret "$D/a2.out" file_write_all_r_tag)" = "1" ] || { fail "axis 2: file_write_all_r returned Ok($(_ret "$D/a2.out" file_write_all_r_val)) on a short write — expected Err"; a2=1; }
for f in w_all.txt w_app.txt w_res.txt; do
    s=$(_sz "$D/lim/$f")
    [ "$s" = MISSING ] || [ "$s" -lt "$LEN" ] || { fail "axis 2: $f is $s bytes — the limit did not bite, the axis is vacuous"; a2=1; }
done
[ "$a2" = 0 ] && echo "  ok: axis 2: under RLIMIT_FSIZE every whole-buffer helper errors ($(_ret "$D/a2.out" file_write_all)), none returns a short count"

# ── axis 3: STATIC — every whole-buffer helper routes through _io_write_full ──
# The fn list is DERIVED from lib/io.cyr, so a new `_all` helper is covered the day it lands.
_whole_buffer_fns() {
    awk '/^fn (file_write_all|file_write_all_r|file_append_locked|file_write_atomic)\(/ { \
             sub(/\(.*/, "", $2); print $2 }' "$1"
}
# _routes <file> <fn> — 1 when <fn>'s body calls _io_write_full, else 0
_routes() {
    awk -v want="$2" '
        $0 ~ "^fn " want "\\(" { inb = 1; next }
        inb && /^fn / { inb = 0 }
        inb && /_io_write_full\(/ { found = 1 }
        END { print (found ? 1 : 0) }' "$1"
}
a3=0
fns=$(_whole_buffer_fns lib/io.cyr)
n_fns=$(printf '%s\n' "$fns" | grep -c . )
[ "$n_fns" -ge 4 ] || { fail "axis 3: only $n_fns whole-buffer helper(s) found in lib/io.cyr — expected at least 4 (renamed? the detector is blind)"; a3=1; }
for f in $fns; do
    [ "$(_routes lib/io.cyr "$f")" = 1 ] || { fail "axis 3: lib/io.cyr $f does not call _io_write_full — it can return a short count again"; a3=1; }
done
grep -q '^fn _io_write_full(' lib/io.cyr || { fail "axis 3: lib/io.cyr has no _io_write_full"; a3=1; }
[ "$(awk '/^fn _io_write_full\(/ { inb = 1; next } inb && /^fn / { inb = 0 } inb && /while \(/ { n = n + 1 } END { print n + 0 }' lib/io.cyr)" -ge 1 ] \
    || { fail "axis 3: _io_write_full has no loop — it cannot write more than one chunk"; a3=1; }
# self-test: the pre-fix shape must be REPORTED, or the detector reads green on anything
cat > "$D/prefix.cyr" <<'CYR'
fn file_write_all(path, buf, len): i64 {
    var written = file_write(fd, buf, len);
    return written;
}
fn file_write_all_r(path, buf, len): Result {
    var n = sys_write(fd, buf, len);
    return Ok(n);
}
fn file_append_locked(path, buf, len): i64 {
    var n = file_write(fd, buf, len);
    return n;
}
fn file_write_atomic(path, buf, len): i64 {
    var w = file_write(fd, buf, len);
    return 0;
}
CYR
bad=0
for f in $(_whole_buffer_fns "$D/prefix.cyr"); do
    [ "$(_routes "$D/prefix.cyr" "$f")" = 1 ] && bad=$((bad + 1))
done
[ "$bad" -eq 0 ] || { fail "axis 3 self-test: $bad of the 4 pre-fix one-shot bodies read as routed — the detector matches anything"; a3=1; }
[ "$(_whole_buffer_fns "$D/prefix.cyr" | grep -c .)" -eq 4 ] || { fail "axis 3 self-test: the fn finder saw $(_whole_buffer_fns "$D/prefix.cyr" | grep -c .) of 4 helpers in the fixture"; a3=1; }
[ "$a3" = 0 ] && echo "  ok: axis 3: all $n_fns whole-buffer helpers route through _io_write_full (loop present; detector self-tested on the pre-fix shape)"

# ── axis 4: the crash-safe writer keeps the original when the write cannot finish ──
mkdir -p "$D/atom"
printf 'ORIGINAL CONTENT — must survive a failed atomic write\n' > "$D/atom/w_atomic.txt"
before=$(cksum < "$D/atom/w_atomic.txt")
rc=0; ( cd "$D/atom" && ulimit -c 0 && trap '' XFSZ && ulimit -f 2 && exec "$D/probe" ) > "$D/a4.out" 2>&1 || rc=$?
a4=0
v=$(_ret "$D/a4.out" file_write_atomic)
case "$v" in
    -*) : ;;
    *)  fail "axis 4: file_write_atomic returned $v under the size limit — expected a negative errno"; a4=1 ;;
esac
[ "$(cksum < "$D/atom/w_atomic.txt")" = "$before" ] || { fail "axis 4: the original file was CHANGED by a failed atomic write ($(_sz "$D/atom/w_atomic.txt") bytes)"; a4=1; }
left=$(ls -A "$D/atom" | grep '\.cyrtmp\.' | tr '\n' ' ')
[ -z "$left" ] || { fail "axis 4: a failed atomic write left a temp behind: $left"; a4=1; }
[ "$a4" = 0 ] && echo "  ok: axis 4: file_write_atomic errors ($v), keeps the original byte-for-byte, leaves no .cyrtmp sibling"

[ "$FAIL" = 0 ] || exit 1
echo "PASS: io_write_all_never_short (4 axes)"

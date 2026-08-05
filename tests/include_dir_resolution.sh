#!/bin/sh
# Gate: `#@incdir` — a source in a subdirectory can include its own neighbours,
# WITHOUT widening the set of files an include can reach.
#
# THE BUG. cycc compiles from STDIN (`cyrius build` dup2's the file onto fd 0,
# cbt/build.cyr), so it never learns where its input lives and every `include "…"`
# resolves against the process CWD. `cyrius build src/sub/app.cyr` therefore could
# not `include "helper.cyr"` for a file sitting right next to it. The directory now
# rides in-band on line 1 as `#@incdir <dir>` — in-band because `#` opens a comment
# in cyrius, so older cycc / cybs / the cx+JS forks all skip the line untaught, and
# because the two out-of-band channels are both dead here (chdir breaks the
# root-relative dep prepend; `_read_env` is stubbed on Windows and cx).
#
# ⛔ WHY HALF THIS FILE IS ATTACKS. In-band means a HOSTILE .cyr can write the
# marker itself. If an absolute directory were honoured, `#@incdir /etc` +
# `include "hostname"` would rebuild precisely the read-anything primitive CVE-16
# was filed to remove — the feature would have quietly reopened a closed CVE. So
# the guard (relative, `..`-free, byte 0 only) is the load-bearing part, and axes
# 4-8 attack it directly rather than trusting that it was implemented.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CC="$ROOT/build/cycc"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

mkdir -p "$D/src/sub/deeper" "$D/build" "$D/nohome"
echo 'fn helper_value(): i64 { return 40; }'  > "$D/src/sub/helper.cyr"
echo 'fn more_value(): i64 { return 2; }'     > "$D/src/sub/deeper/more.cyr"
# A source that compiles cleanly, so axis 9 exercises the OUTPUT path and cannot pass
# on a compile error that happens to also print FAIL.
printf 'include "helper.cyr"\nfn main(): i64 { return helper_value(); }\nvar r = main();\nsyscall(60, r);\n' > "$D/src/sub/app_ok.cyr"
cp "$ROOT/build/cycc" "$D/build/cycc" 2>/dev/null; chmod +x "$D/build/cycc" 2>/dev/null

# Run cycc on a crafted source from inside $D, return the compiled program's exit code.
# 90 = compile failed (so a refused include is loudly distinguishable from a wrong value).
run() {
    printf '%s\n' "$1" > "$D/p.cyr"
    ( cd "$D" && "$CC" < p.cyr > prog.bin 2>err.txt ) || { echo 90; return; }
    [ -s "$D/prog.bin" ] || { echo 90; return; }
    chmod +x "$D/prog.bin"
    ( cd "$D" && timeout 30 ./prog.bin >/dev/null 2>&1 )
    echo $?
}

# ── AXIS 1: the filed bug. A sibling include, and a nested one, both relative to
# the source's own directory.
echo "axis 1 — a subdirectory source includes its own neighbours:"
check "sibling + nested include resolve" 42 "$(run '#@incdir src/sub
include "helper.cyr"
include "deeper/more.cyr"
fn main(): i64 { return helper_value() + more_value(); }
var r = main();
syscall(60, r);')"

# ── AXIS 2: no marker → unchanged. The same source without the marker must still
# fail exactly as it does today; if this passed, the fallback would be firing off
# something other than the marker.
echo "axis 2 — without the marker, nothing changed:"
check "unmarked source still cannot find the sibling" 90 "$(run 'include "helper.cyr"
fn main(): i64 { return helper_value(); }
var r = main();
syscall(60, r);')"

# ── AXIS 3: CWD-FIRST, the additivity proof. With the same basename present BOTH
# cwd-relative and incdir-relative, the CWD copy must win — that is what makes this
# change incapable of moving any include that resolves today.
echo "axis 3 — CWD-first: an include that resolves today resolves to the SAME file:"
echo 'fn dup_value(): i64 { return 7; }'  > "$D/dup.cyr"
echo 'fn dup_value(): i64 { return 33; }' > "$D/src/sub/dup.cyr"
check "cwd copy wins over the incdir copy" 7 "$(run '#@incdir src/sub
include "dup.cyr"
fn main(): i64 { return dup_value(); }
var r = main();
syscall(60, r);')"

# ── AXES 4-5: ⛔ the escape attempts, against a REAL target.
#
# The target has to be a file that (a) exists, (b) sits OUTSIDE the CWD subtree, and
# (c) is valid cyrius. (c) is the part that is easy to get wrong and it cost this
# gate a round: pointed at /etc/hostname, both axes passed against a compiler with
# the guard REMOVED, because a hostname is not parseable — the include was read, the
# escape succeeded, and the compile failed for an unrelated reason that looked
# exactly like a refusal. A guard whose test cannot tell "refused" from "read and
# then choked" is not tested at all. `secret_value()` returning 55 makes a
# successful escape observable as 55 rather than indistinguishable from failure.
OUT=$(mktemp -d)
trap 'rm -rf "$D" "$OUT"' EXIT
echo 'fn secret_value(): i64 { return 55; }' > "$OUT/secret.cyr"

echo "axis 4 — an absolute #@incdir is refused (CVE-16 must stay closed):"
check "absolute directory rejected (55 = escaped)" 90 "$(run "#@incdir $OUT
include \"secret.cyr\"
fn main(): i64 { return secret_value(); }
var r = main();
syscall(60, r);")"

# The same file reached by a RELATIVE path that climbs out — $D and $OUT are both
# mktemp dirs under the same parent, so `../<basename>` is a genuine escape.
echo "axis 5 — a .. component in #@incdir is refused (CVE-02 must stay closed):"
check "leading .. rejected (55 = escaped)" 90 "$(run "#@incdir ../$(basename "$OUT")
include \"secret.cyr\"
fn main(): i64 { return secret_value(); }
var r = main();
syscall(60, r);")"
# BOTH positions, because they are separate branches in the scanner and the
# leading-`..` case alone leaves the mid-path one unproven — mutation-verified:
# deleting the mid-path check keeps the test above green.
check "mid-path .. rejected (55 = escaped)" 90 "$(run "#@incdir src/../../$(basename "$OUT")
include \"secret.cyr\"
fn main(): i64 { return secret_value(); }
var r = main();
syscall(60, r);")"

# ── AXIS 6: ⛔ BYTE 0 ONLY. This is what keeps the CLI's value the trusted one: the
# CLI writes its marker first, so a hostile file's marker is never at byte 0. A
# marker anywhere else must remain an ordinary comment.
echo "axis 6 — a marker below line 1 is an ordinary comment, not a directive:"
check "second/late marker ignored" 90 "$(run '# leading comment
#@incdir src/sub
include "helper.cyr"
fn main(): i64 { return helper_value(); }
var r = main();
syscall(60, r);')"

# ── AXIS 7: the include-name guards still fire WITH a marker set. The marker must
# not become a way to smuggle a hostile name past checks that already exist.
echo "axis 7 — CVE-02/CVE-16 still apply to the include NAME under a valid marker:"
( cd "$D" && printf '#@incdir src/sub\ninclude "../../etc/hostname"\nvar r = 0;\n' > t2.cyr && "$CC" < t2.cyr > /dev/null 2>e2.txt )
check "traversal include name still rejected" 1 "$(grep -c 'path traversal rejected' "$D/e2.txt")"
( cd "$D" && printf '#@incdir src/sub\ninclude "/etc/hostname"\nvar r = 0;\n' > t3.cyr && "$CC" < t3.cyr > /dev/null 2>e3.txt )
check "absolute include name still rejected" 1 "$(grep -c 'absolute include path rejected' "$D/e3.txt")"

# ── AXIS 8: the CLI's half of the guard — it must not emit a marker it knows cycc
# would refuse, and must not emit one when there is no directory to report.
echo "axis 8 — the CLI emits a marker only when it is safe and useful:"
n_abs=$(awk '/^fn _source_incdir/,/^}/' "$ROOT/cbt/build.cyr" | grep -c 'if (load8(source) == 47) { return 0; }')
check "absolute source path → no marker" 1 "$n_abs"
n_dot=$(awk '/^fn _source_incdir/,/^}/' "$ROOT/cbt/build.cyr" | grep -c 'if (load8(source + j - 1) == 47) { return 0; }')
check ".. component → no marker" 1 "$n_dot"
n_first=$(awk '/if \(tfd >= 0\) \{/,/Prepend dep includes/' "$ROOT/cbt/build.cyr" | grep -c 'sys_write(tfd, "#@incdir ", 9);')
check "marker written before the dep prepend (byte 0)" 1 "$n_first"

# ── AXIS 9: the adjacent defect from the same filing, same command. A missing output
# DIRECTORY used to print a bare `FAIL` and nothing else: the child had already dup2'd
# its stdout away before opening the output, so `sys_exit(1)` was the only channel it
# had left. The parent now proves the output writable before forking, so the failure
# names the directory. Runs the real CLI end-to-end — the message is the deliverable,
# so asserting on source text would test the wrong thing.
echo "axis 9 — a missing output directory says which one (was a bare FAIL):"
if [ -x "$ROOT/build/cyrius" ]; then
    ( cd "$D" && CYRIUS_HOME="$D/nohome" "$ROOT/build/cyrius" build src/sub/app_ok.cyr build/nope/deeper/out ) > "$D/od.txt" 2>&1
    check "names the absent directory" 1 "$(grep -c 'output directory does not exist: build/nope/deeper' "$D/od.txt")"
    check "still reports failure" 1 "$(grep -c 'FAIL' "$D/od.txt")"
else
    echo "  FAIL: build/cyrius missing — axis 9 cannot run (build the CLI first)"
    fails=$((fails + 1))
fi

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: include-dir-resolution — subfolder includes resolve, CWD still wins, CVE-02/16 closed"
    exit 0
fi
echo "FAIL: include-dir-resolution — $fails assertion(s) failed"
exit 1

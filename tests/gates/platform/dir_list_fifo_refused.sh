#!/bin/sh
# Gate: dir_list_into / dir_list_checked (and dir_list, which shares _dir_list_into_vec) REFUSE
# a path that is not a directory at the open, so a FIFO there fails at once instead of blocking
# the caller forever (6.7.11).
#
# THE BUG (issues/2026-10-13-dir-list-opens-directory-without-o-directory.md, from agora 1.9.1).
# Both POSIX arms of lib/fs.cyr opened the path with `sys_open(&cpath, O_RDONLY, 0)` and only
# then called getdents64. open(2) of a FIFO with O_RDONLY blocks until a writer opens the other
# end — before getdents64 could ever say ENOTDIR — so the listing never returned (agora's store
# scan froze its single-process poll server: a FIFO named like a store directory stopped every
# client). The fix opens with O_RDONLY | O_DIRECTORY | O_CLOEXEC: the kernel refuses a
# non-directory at path resolution (-ENOTDIR). Darwin does the same (ecb and ach measured by hand
# at 6.7.11: the old body hung, the new one answers -1 / -20), and tests/tcyr/crossos/
# fs_dirlist.tcyr runs the FIFO rows on every POSIX host. CHANGELOG [6.7.11]
#
# AXES (Linux only — the gate needs mkfifo and timeout; anything else is a named SKIP, exit 77).
#   A1-A4  x86_64: a FIFO, a regular file, a dangling symlink and a one-entry directory, each
#          listed by a probe under `timeout`: dir_list_into's and dir_list_checked's answers are
#          "-1 -20", "-1 -20", "-1 -2" and "1 0".
#   A5-A6  aarch64 under qemu-aarch64 (a cross compiler built from src/main_aarch64.cyr here):
#          the FIFO and the file. A named SKIP when qemu-aarch64 is absent.
#   M1-M2  ANTI-VACUOUS, built in: the same probe against a copy of lib/fs.cyr whose two open
#          sites are put back to plain O_RDONLY must TIME OUT on the FIFO (124) on x86 and under
#          qemu — so a FIFO row that passes is a FIFO row that would have hung. The copy must
#          have changed exactly two sites, or the mutation has drifted and the gate is RED.
#
# MUTATION LEDGER (6.7.11, x86_64 Linux + qemu-aarch64, each edit made to the tree's lib/fs.cyr):
#   both open sites back to `O_RDONLY`            -> M0 (0 sites), A1 + A5 'timeout': RED
#   only _dir_list_into_vec's site (dir_list_checked) -> M0 (1 site), A1 + A5 'timeout': RED
#   only dir_list_into's site                     -> M0 (1 site), A1 + A5 'timeout': RED
#
# Nothing is written inside the tree: every probe, binary and FIFO lives in a mktemp -d.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=dir_list_fifo_refused
if [ "$(uname -s)" != Linux ]; then echo "SKIP: $G — Linux only (mkfifo + timeout probes)"; exit 77; fi
for t in mkfifo timeout; do
    command -v "$t" >/dev/null 2>&1 || { echo "SKIP: $G — '$t' not found"; exit 77; }
done
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected '$2', got '$3'"; fails=$((fails + 1)); fi
}

# $1 = the include line for fs.cyr. The probe lists "target" in its cwd.
mkprobe() {
    cat <<EOF
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
include "lib/fmt.cyr"
include "lib/syscalls.cyr"
include "lib/io.cyr"
include "$1"

fn main(): i64 {
    alloc_init();
    var scr[4096];
    var nm[256];
    var ofs: i64[16];
    var a = dir_list_into(str_from("target"), &scr, 4096, &nm, 256, &ofs, 16);
    fmt_int(a);
    println("");
    var v = vec_new();
    var b = dir_list_checked(str_from("target"), v);
    fmt_int(b);
    println("");
    return 0;
}
var r = main();
syscall(SYS_EXIT, r);
EOF
}

# The mutant: lib/fs.cyr with both open sites back to plain O_RDONLY.
sed 's/O_RDONLY | O_DIRECTORY | O_CLOEXEC/O_RDONLY/' lib/fs.cyr > "$D/fs_mut.cyr"
check "M0 the mutation reverts exactly the two open sites" 2 \
    "$(diff lib/fs.cyr "$D/fs_mut.cyr" | grep -c '^>' | tr -d ' ')"
mkprobe "lib/fs.cyr" > "$D/p.cyr"
mkprobe "$D/fs_mut.cyr" > "$D/pm.cyr"

build() {   # $1 compiler, $2 source, $3 output
    rc=0
    CYRIUS_ALLOW_ABSOLUTE_INCLUDES=1 "$1" < "$2" > "$3" 2> "$3.err" || rc=$?
    chmod +x "$3" 2>/dev/null
    [ "$rc" = 0 ] && [ -s "$3" ] && echo yes || echo "no (rc $rc: $(grep -v 'unreachable fns' "$3.err" | head -2))"
}
# $1 = kind (fifo|file|link|dir), $2 = seconds, $3.. = the command. Prints the probe's two
# answers on one line, or "timeout" when it was still blocked at the deadline.
run_on() {
    kind=$1; secs=$2; shift 2
    rm -rf "$D/w" && mkdir "$D/w"
    case $kind in
        fifo) mkfifo "$D/w/target" ;;
        file) echo x > "$D/w/target" ;;
        link) ln -s nowhere "$D/w/target" ;;
        dir)  mkdir "$D/w/target" && echo x > "$D/w/target/member" ;;
    esac
    rc=0
    out=$(cd "$D/w" && timeout "$secs" "$@" 2>&1) || rc=$?
    if [ "$rc" = 124 ]; then echo timeout
    elif [ "$rc" != 0 ]; then echo "rc=$rc $(printf '%s' "$out" | tr '\n' ' ')"
    else printf '%s' "$out" | tr '\n' ' ' | sed 's/ $//'; fi
}

echo "x86_64"
check "probe builds (tree lib/fs.cyr)" yes "$(build "$CC" "$D/p.cyr" "$D/p")"
check "probe builds (mutant fs.cyr)" yes "$(build "$CC" "$D/pm.cyr" "$D/pm")"
check "A1 a FIFO is refused at once" "-1 -20" "$(run_on fifo 10 "$D/p")"
check "A2 a regular file" "-1 -20" "$(run_on file 10 "$D/p")"
check "A3 a dangling symlink" "-1 -2" "$(run_on link 10 "$D/p")"
check "A4 a one-entry directory still lists" "1 0" "$(run_on dir 10 "$D/p")"
check "M1 the O_RDONLY mutant BLOCKS on the FIFO (the hang A1 guards)" timeout "$(run_on fifo 3 "$D/pm")"

echo "aarch64 (qemu)"
if command -v qemu-aarch64 >/dev/null 2>&1; then
    rc=0; "$CC" < src/main_aarch64.cyr > "$D/cca" 2> "$D/cca.err" || rc=$?
    chmod +x "$D/cca"
    check "cycc_aarch64 cross-built from src" yes "$( [ "$rc" = 0 ] && [ -s "$D/cca" ] && echo yes || echo "no (rc $rc)")"
    check "probe builds (tree lib/fs.cyr)" yes "$(build "$D/cca" "$D/p.cyr" "$D/pa")"
    check "probe builds (mutant fs.cyr)" yes "$(build "$D/cca" "$D/pm.cyr" "$D/pma")"
    check "A5 a FIFO is refused at once" "-1 -20" "$(run_on fifo 20 qemu-aarch64 "$D/pa")"
    check "A6 a regular file" "-1 -20" "$(run_on file 20 qemu-aarch64 "$D/pa")"
    check "M2 the O_RDONLY mutant BLOCKS on the FIFO" timeout "$(run_on fifo 3 qemu-aarch64 "$D/pma")"
else
    echo "  SKIP: A5 A6 M2 — qemu-aarch64 not found (the x86 axes ran)"
fi

if [ "$fails" -ne 0 ]; then echo "FAIL: $G ($fails row(s))"; exit 1; fi
echo "PASS: $G — a FIFO, a file and a dangling link fail at the open; the O_RDONLY mutant blocks"
exit 0

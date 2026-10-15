#!/bin/sh
# Gate: lib/audit_walk.cyr's Linux lister REFUSES a path that is not a directory at the open, so
# a FIFO handed to audit_fmt_walk / audit_lint_walk / audit_doc_walk fails at once — reported as
# an unlistable directory — instead of blocking the walk forever (6.7.12).
#
# THE BUG (issues/2026-10-13-audit-walk-linux-lister-opens-without-o-directory.md, met while
# fixing the dir_list twin, issues/archived/2026-10-13-dir-list-opens-directory-without-o-directory.md).
# _aw_dir_list_typed — the getdents64 lister of the Linux x86_64 / aarch64 arm, behind the three
# public walkers — opened `sys_open(str_data(path), O_RDONLY, 0)` and only then called
# getdents64. open(2) of a FIFO with O_RDONLY blocks until a writer opens the other end, before
# getdents64 could say ENOTDIR, so the walk never returned. It now copies exactly the Str's bytes
# (lib/fs.cyr's _fs_cpath) and opens O_RDONLY | O_DIRECTORY | O_CLOEXEC: the kernel refuses a
# non-directory at path resolution (-ENOTDIR), which the walkers report as "cannot list
# directory (subtree NOT checked), error 20". macOS / Windows / agnos route through
# dir_list_checked, which takes O_DIRECTORY since 6.7.11 (dir_list_fifo_refused.sh). CHANGELOG [6.7.12]
#
# AXES (Linux only — the gate needs mkfifo and timeout; anything else is a named SKIP, exit 77).
#   A1-A3  x86_64, the FILED repro verbatim (audit_fmt_walk over "aw_probe_target", printing its
#          return and AW_FMT_ERRORS), run under `timeout` in a scratch directory: a FIFO "0 1"
#          (it returns — the filing measured rc 124), a regular file "0 1", a directory holding
#          one non-source file "0 0" (still listed).
#   B1     x86_64, all three walkers over the FIFO: each records ONE error, and the note is the
#          unlistable-directory note with error 20 (ENOTDIR — refused at the open).
#   A4-A5, B2  the same FIFO / file / three-walker rows on aarch64 under qemu-aarch64 (a cross
#          compiler built from src/main_aarch64.cyr here; aarch64's O_DIRECTORY is not x86's).
#          No qemu-aarch64 -> those rows are a named SKIP and the gate exits 77, never a PASS.
#   M1-M2  ANTI-VACUOUS, built in: the repro against a copy of lib/audit_walk.cyr whose open is
#          put back to plain O_RDONLY must TIME OUT on the FIFO (124), on x86 and under qemu —
#          so a FIFO row that passes is one that would have hung. The copy must differ in exactly
#          that one line, or the mutation has drifted and the gate is RED.
#
# MUTATION LEDGER (6.7.12, x86_64 Linux + qemu-aarch64, the edit made to the tree's
# lib/audit_walk.cyr, gate re-run, restored):
#   the open back to `O_RDONLY` (the 6.7.11 flags)  -> 5 rows: M0 (0 lines), A1 B1 A4 B2 'timeout': RED
#   O_DIRECTORY dropped, O_CLOEXEC kept             -> 5 rows: M0 (0 lines), A1 B1 A4 B2 'timeout': RED
#
# Nothing is written inside the tree: every probe, binary and FIFO lives in a mktemp -d.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC=${CYCC:-"$ROOT/build/cycc"}
G=audit_walk_fifo_refused
if [ "$(uname -s)" != Linux ]; then echo "SKIP: $G — Linux only (mkfifo + timeout probes)"; exit 77; fi
for t in mkfifo timeout; do
    command -v "$t" >/dev/null 2>&1 || { echo "SKIP: $G — '$t' not found"; exit 77; }
done
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fails=0
skips=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected '$2', got '$3'"; fails=$((fails + 1)); fi
}

# $1 = the include line for audit_walk.cyr. The filed repro, verbatim but for that line.
mkprobe() {
    cat <<EOF
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
include "lib/fmt.cyr"
include "lib/syscalls.cyr"
include "lib/io.cyr"
include "lib/fs.cyr"
include "lib/process.cyr"
include "$1"

fn main(): i64 {
    alloc_init();
    var dirs = vec_new();
    vec_push(dirs, str_from("aw_probe_target"));
    var r = audit_fmt_walk("build/cyrfmt", dirs);
    fmt_int(r); println("");
    fmt_int(AW_FMT_ERRORS); println("");
    return 0;
}
var r = main();
syscall(SYS_EXIT, r);
EOF
}

# B: the three public walkers over the same path; each prints its error count and first note.
cat > "$D/walkers.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/str.cyr"
include "lib/vec.cyr"
include "lib/fmt.cyr"
include "lib/syscalls.cyr"
include "lib/io.cyr"
include "lib/fs.cyr"
include "lib/process.cyr"
include "lib/audit_walk.cyr"

fn show(n, notes): i64 {
    fmt_int(n);
    println("");
    if (vec_len(notes) > 0) {
        var nt = vec_get(notes, 0);
        sys_write(1, str_data(nt), str_len(nt));
    }
    println("");
    return 0;
}

fn main(): i64 {
    alloc_init();
    var dirs = vec_new();
    vec_push(dirs, str_from("aw_probe_target"));
    audit_fmt_walk("build/cyrfmt", dirs);
    show(AW_FMT_ERRORS, AW_FMT_ERROR_FILES);
    audit_lint_walk("build/cyrlint", dirs);
    show(AW_LINT_ERRORS, AW_LINT_ERROR_FILES);
    audit_doc_walk("build/cyrdoc", dirs);
    show(AW_DOC_ERRORS, AW_DOC_ERROR_FILES);
    return 0;
}
var r = main();
syscall(SYS_EXIT, r);
EOF

# The mutant: lib/audit_walk.cyr with the lister's open back to plain O_RDONLY.
sed 's/sys_open(&cpath, O_RDONLY | O_DIRECTORY | O_CLOEXEC, 0)/sys_open(\&cpath, O_RDONLY, 0)/' \
    lib/audit_walk.cyr > "$D/aw_mut.cyr"
check "M0 the mutation reverts exactly the one open" 1 \
    "$(diff lib/audit_walk.cyr "$D/aw_mut.cyr" | grep -c '^>' | tr -d ' ')"
mkprobe "lib/audit_walk.cyr" > "$D/p.cyr"
mkprobe "$D/aw_mut.cyr" > "$D/pm.cyr"

build() {   # $1 compiler, $2 source, $3 output
    rc=0
    CYRIUS_ALLOW_ABSOLUTE_INCLUDES=1 "$1" < "$2" > "$3" 2> "$3.err" || rc=$?
    chmod +x "$3" 2>/dev/null
    [ "$rc" = 0 ] && [ -s "$3" ] && echo yes || echo "no (rc $rc: $(grep -v 'unreachable fns' "$3.err" | head -2))"
}
# $1 = kind (fifo|file|dir), $2 = seconds, $3.. = the command. Prints the probe's answers on one
# line ('|' between lines), or "timeout" when it was still blocked at the deadline.
run_on() {
    kind=$1; secs=$2; shift 2
    rm -rf "$D/w" && mkdir "$D/w"
    case $kind in
        fifo) mkfifo "$D/w/aw_probe_target" ;;
        file) echo x > "$D/w/aw_probe_target" ;;
        dir)  mkdir "$D/w/aw_probe_target" && echo x > "$D/w/aw_probe_target/member.txt" ;;
    esac
    rc=0
    out=$(cd "$D/w" && timeout "$secs" "$@" 2>&1) || rc=$?
    if [ "$rc" = 124 ]; then echo timeout
    elif [ "$rc" != 0 ]; then echo "rc=$rc $(printf '%s' "$out" | tr '\n' ' ')"
    else printf '%s' "$out" | tr '\n' '|' | sed 's/|$//'; fi
}
NOTE="aw_probe_target: cannot list directory (subtree NOT checked), error 20"
WANTB="1|$NOTE|1|$NOTE|1|$NOTE"

echo "x86_64"
check "probe builds (tree lib/audit_walk.cyr)" yes "$(build "$CC" "$D/p.cyr" "$D/p")"
check "probe builds (mutant audit_walk.cyr)" yes "$(build "$CC" "$D/pm.cyr" "$D/pm")"
check "three-walker probe builds" yes "$(build "$CC" "$D/walkers.cyr" "$D/pw")"
check "A1 a FIFO is refused at once, reported as an unlistable directory" "0|1" "$(run_on fifo 10 "$D/p")"
check "A2 a regular file likewise" "0|1" "$(run_on file 10 "$D/p")"
check "A3 a directory still lists (no source file, no error)" "0|0" "$(run_on dir 10 "$D/p")"
check "B1 fmt / lint / doc walkers on the FIFO: one ENOTDIR note each" "$WANTB" "$(run_on fifo 10 "$D/pw")"
check "M1 the O_RDONLY mutant BLOCKS on the FIFO (the hang A1 guards)" timeout "$(run_on fifo 3 "$D/pm")"

echo "aarch64 (qemu)"
if command -v qemu-aarch64 >/dev/null 2>&1; then
    rc=0; "$CC" < src/main_aarch64.cyr > "$D/cca" 2> "$D/cca.err" || rc=$?
    chmod +x "$D/cca"
    check "cycc_aarch64 cross-built from src" yes "$( [ "$rc" = 0 ] && [ -s "$D/cca" ] && echo yes || echo "no (rc $rc)")"
    check "probe builds (tree lib/audit_walk.cyr)" yes "$(build "$D/cca" "$D/p.cyr" "$D/pa")"
    check "probe builds (mutant audit_walk.cyr)" yes "$(build "$D/cca" "$D/pm.cyr" "$D/pma")"
    check "three-walker probe builds" yes "$(build "$D/cca" "$D/walkers.cyr" "$D/pwa")"
    check "A4 a FIFO is refused at once" "0|1" "$(run_on fifo 20 qemu-aarch64 "$D/pa")"
    check "A5 a regular file likewise" "0|1" "$(run_on file 20 qemu-aarch64 "$D/pa")"
    check "B2 fmt / lint / doc walkers on the FIFO: one ENOTDIR note each" "$WANTB" "$(run_on fifo 20 qemu-aarch64 "$D/pwa")"
    check "M2 the O_RDONLY mutant BLOCKS on the FIFO" timeout "$(run_on fifo 3 qemu-aarch64 "$D/pma")"
else
    echo "  SKIP: A4 A5 B2 M2 — qemu-aarch64 not found (the x86 axes ran)"
    skips=1
fi

if [ "$fails" -ne 0 ]; then echo "FAIL: $G ($fails row(s))"; exit 1; fi
if [ "$skips" -ne 0 ]; then
    echo "SKIP: $G — the aarch64 rows could not run; every x86 row passed (exit 77: a SKIP, not a PASS)"
    exit 77
fi
echo "PASS: $G — a FIFO or a file handed to the audit walkers fails at the open (ENOTDIR); the O_RDONLY mutant blocks"
exit 0

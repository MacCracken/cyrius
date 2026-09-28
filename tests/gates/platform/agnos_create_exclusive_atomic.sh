#!/bin/sh
# agnos_create_exclusive_atomic.sh — v6.6.9. On agnos, lib/io.cyr's file_create_exclusive is ONE
# kernel-refused create (open#7 with AO_WRONLY|AO_CREAT|AO_EXCL), not a check-then-create.
#
# ⛔ THE DEFECT. From 6.4.58 the agnos arm was `if (file_exists(path)) return -17;` followed by a
# plain AO_CREAT open, on the stated grounds that agnos had no exclusive-create bit. It has had
# one since kernel 1.56.56 (AO_EXCL 0x2000, refusing a final component that resolves, dangling
# symlinks included) and file_open has mapped O_EXCL to it since 6.6.4 — so the non-atomic
# pre-check was only ever a stale workaround: a second creator between the probe and the create
# was clobber-open'd instead of refused, and a name that exists as a DIRECTORY or a DANGLING
# symlink was not "existing" to the probe (measured on agnos-qemu 1.57.10 against the old arm:
# both came back -1, not -17). agnos answers every refusal with a bare -1 (no -errno), so the
# new arm classifies a refused create with lstat#102 (no final-link follow): exists → -17.
#
# tests/fixtures/agnos_sctrace.cyr runs the agnos probe under PTRACE_SYSEMU (nothing executes;
# every syscall is logged and answered from a table), so the SHAPE of the call is asserted
# exactly. The real kernel is exercised on agnos-qemu (CHANGELOG [6.6.9]: 10/10 at -smp 1 and 4).
#
# AXES (the probe marks the call with syscall(999, 1) … syscall(999, 2, result)):
#   1 plain    — every call answers 0: the ONLY syscall between the marks is open#7, with
#                a3 = AO_WRONLY|AO_CREAT|AO_EXCL (8449), and the fd comes back.
#   2 exclref  — open#7 answers -1, lstat#102 answers 0: exactly open#7 then lstat#102, → -17.
#   3 exclnone — both answer -1 (a missing parent): same two calls, → -1 (NOT -17).
# MUTATION (measured 2026-09-28): the 6.6.8 arm (file_exists pre-check + plain AO_CREAT) makes a
# RDONLY open#7 (a3 = 0) and a close#6 and returns -17 without creating anything in axis 1 — red
# on all three axes; dropping the lstat classification turns axes 2 and 3 red (no #102, and -1
# for a name that exists).
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: agnos_create_exclusive_atomic: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$R" || exit 2
CC=${CYCC:-"$R/build/cycc"}
[ -x "$CC" ] || { echo "FAIL agnos_create_exclusive_atomic: no build/cycc"; exit 1; }
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}
"$CC" < tests/fixtures/agnos_sctrace.cyr > "$T/sct" 2>"$T/sct.err" && chmod +x "$T/sct" || {
    echo "FAIL agnos_create_exclusive_atomic: the fake-kernel tracer did not build"; head -3 "$T/sct.err"; exit 1; }
cat > "$T/p.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/io.cyr"
syscall(999, 1, 0, 0, 0);
var r = file_create_exclusive("/cx/y", 420);
syscall(999, 2, r, 0, 0);
sys_exit(0);
EOF
CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/p.cyr" > "$T/p.bin" 2>"$T/p.err" || {
    echo "FAIL agnos_create_exclusive_atomic: the agnos probe did not build"; grep -E '^error' "$T/p.err" | head -3; exit 1; }
chmod +x "$T/p.bin"
# The syscall numbers (and open#7's a3) strictly between the two marks, then the result.
between() {
    "$T/sct" "$T/p.bin" "$1" > "$T/$1.log" 2>&1 || true
    awk '$1 == "sc" && $2 == 999 && $3 == 1 { on = 1; next }
         $1 == "sc" && $2 == 999 && $3 == 2 { on = 0; r = $4; next }
         on && $1 == "sc" { printf "%s%s", s, ($2 == 7 ? "7/" $5 : $2); s = " " }
         END { printf " => %s\n", r }' "$T/$1.log"
}
check "plain: one open#7 with AO_WRONLY|AO_CREAT|AO_EXCL, and the fd comes back" "7/8449 => 0" "$(between plain)"
check "exclref: refused create, lstat#102 finds the name, -EEXIST" "7/8449 102 => -17" "$(between exclref)"
check "exclnone: refused create, the name does not exist, the bare -1 stands" "7/8449 102 => -1" "$(between exclnone)"
if [ "$fails" = "0" ]; then
    echo "PASS: agnos file_create_exclusive is one atomic AO_EXCL create, classified by lstat"
    exit 0
fi
echo "FAIL: agnos_create_exclusive_atomic ($fails)"
exit 1

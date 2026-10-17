#!/bin/sh
# cx_guest_syscall_refusal.sh — 6.7.14 (D55, the user 2026-10-16: "cxvm answers -38";
# issues/2026-10-15-cx-untranslated-pointer-wrappers-can-reach-cxvm-image.md). cxvm's syscall opcode
# (0x70) translates read / write / open, serves getrandom / clock_gettime through the host's stdlib,
# passes a short list of SCALAR-ONLY calls to the host as they are (programs/cxvm.cyr
# `_cx_sys_scalar`), and answers every other number -ENOSYS (-38) without reaching the host.
#
# THE DEFECT. Every other number went to the host kernel with the guest's raw register values. Until
# 6.7.12 a guest address was below 1 MiB, which a static Linux cxvm never maps, so a pointer-taking
# call failed with -EFAULT; the 8 MiB guest (6.7.12, D12) overlaps cxvm's own link addresses on a
# Linux host (text 0x400000, data 0x600000). The filed repro `cyr_munmap(4194304, 65536)` unmapped
# cxvm's code (exit 139), and `syscall(5, 1, 6291712)` — fstat into guest 0x600100 — SUCCEEDED,
# writing a 144-byte struct stat over cxvm's globals (exit 100), while the same call at guest
# 0x700000 answered -14 (exit 86).
#
# ROWS (the cx leg runs in $T; a `cxvm:` fault line fails any cx row):
#   R1  the filed munmap repro verbatim: cx prints "after munmap" and exits 38 (it was 139)
#   R2  `var r = syscall(5, 1, 6291712); syscall(60, 100 + r);` on cx: 62 (it was 100)
#   R3  the same fstat at guest 0x700000: 62 (it was 86)
#   R4  every pointer-taking call answers exactly -38 on cx, through the stdlib wrapper where there
#       is one (a bitmask; 0 = all): cyr_munmap, cyr_mprotect, sys_stat, sys_statfs (the yukti
#       crossos file's cx statfs arm is this answer), sys_nanosleep, sys_mkdir, a raw mmap(9), a raw
#       uname(63), wait4(61) with a null status, futex(202), and fcntl(fd, F_GETLK, buf) — fcntl
#       passes only its scalar commands
#   R5  the scalar-only controls give the HOST's answer on both legs (a bitmask; 0 = all):
#       getpid() > 0, getppid() > 0, close(-1) == -9, kill(getpid(), 0) == 0, dup(-1) == -9,
#       fsync(-1) == -9, fcntl(1, F_GETFL) >= 0, flock(-1, LOCK_SH) == -9 (the uid getters: the
#       uid_identity rows of cx_auto_call_main.sh)
#   R6  the translated / served calls still work on both legs: open + write + lseek + read back a
#       file in the cwd, close, getrandom(16) == 16, clock_gettime(REALTIME) == 0 with tv_sec > 0
# Anti-vacuous: R1-R3 are the filed values (each was something else before); R5 runs natively as its
# oracle and fails if the dispatch refused a listed call; R4 bit 1024 fails if the fcntl command
# check passed a lock command to the host (-9 from the bad fd, not -38).
#
# MUTATION LEDGER (6.7.14, measured; the real tree green 8/8):
#   MU1 `_cx_sys_scalar` returns 1 for every number (the 6.7.13 pass-through)
#       -> RED 4: R1 cx (exit 139, no "after munmap"), R2 (100), R3 (86), R4 (139 twice: its first
#          call unmaps cxvm's own text, as the filed repro does)
#   MU2 `_cx_sys_scalar` returns 0 for every number -> RED 1: R5 cx (exit 251: every listed call but
#       close, which op 0x70 dispatches itself, answered -38)
#   MU3 the fcntl command check removed (every fcntl passes) -> RED 1: R4 cx (bit 1024: F_GETLK on a
#       bad fd answered -9 from the host)
#
# COMPILERS. CC=${CYCC:-build/cycc} builds the native legs and — unless CYCC_CX is set — the cx
# compiler from THIS tree's src/main_cx.cyr, and cxvm from programs/cxvm.cyr (CXVM overrides it).
# Exit 77 = could not run (no compiler at $CC, no timeout(1)); never a SKIP line with exit 0.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
_abs() { case $1 in /*|'') printf '%s' "$1" ;; *) printf '%s/%s' "$(pwd)" "$1" ;; esac; }
CC=$(_abs "${CYCC:-$ROOT/build/cycc}")
CYCC_CX=$(_abs "${CYCC_CX:-}")
CXVM=$(_abs "${CXVM:-}")
G=cx_guest_syscall_refusal
[ -x "$CC" ] || { echo "SKIP: $G — no compiler at $CC (exit 77: a SKIP, not a PASS)"; exit 77; }
command -v timeout >/dev/null 2>&1 || { echo "SKIP: $G — no timeout(1) (exit 77: a SKIP, not a PASS)"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G — mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT" || exit 1
ulimit -c 0 2>/dev/null || true

if [ -n "$CYCC_CX" ]; then
    [ -x "$CYCC_CX" ] || { echo "FAIL: $G — CYCC_CX=$CYCC_CX is not executable"; exit 1; }
    CX=$CYCC_CX
else
    CX=$T/cycc_cx
    "$CC" < src/main_cx.cyr > "$CX" 2> "$T/eb"; chmod +x "$CX"
    [ -s "$CX" ] || { echo "FAIL: $G — cannot build the cx compiler from src/main_cx.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
fi
if [ -n "$CXVM" ]; then
    [ -x "$CXVM" ] || { echo "FAIL: $G — CXVM=$CXVM is not executable"; exit 1; }
    VM=$CXVM
else
    VM=$T/cxvm
    "$CC" < programs/cxvm.cyr > "$VM" 2> "$T/eb"; chmod +x "$VM"
    [ -s "$VM" ] || { echo "FAIL: $G — cannot build cxvm from programs/cxvm.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
fi

pass=0
fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# build_run LEG SRC OUT — compile SRC for LEG (native / cx) and run it in $T; RC = its exit (or
# "nobuild"), its stdout + stderr in OUT.
build_run() {
    RC=0
    if [ "$1" = native ]; then
        "$CC" < "$2" > "$T/n.bin" 2> "$T/n.err" || RC=nobuild
        [ -s "$T/n.bin" ] || RC=nobuild
        [ "$RC" = nobuild ] && { cp "$T/n.err" "$3"; return; }
        chmod +x "$T/n.bin"; (cd "$T" && timeout 60 ./n.bin > "$3" 2>&1) || RC=$?
    else
        "$CX" < "$2" > "$T/c.cyx" 2> "$T/c.err" || RC=nobuild
        [ -s "$T/c.cyx" ] || RC=nobuild
        [ "$RC" = nobuild ] && { cp "$T/c.err" "$3"; return; }
        (cd "$T" && timeout 60 "$VM" < c.cyx > "$3" 2>&1) || RC=$?
    fi
}

# cxrow NAME WANT MARKER WHAT — the cx leg of $T/NAME.cyr exits WANT, prints MARKER (when set) and no
# `cxvm:` fault line.
cxrow() {
    build_run cx "$T/$1.cyr" "$T/$1.c.out"
    if [ "$RC" = nobuild ]; then bad "$4 (cx): does not build: $(grep -m1 '^error' "$T/$1.c.out")"; return; fi
    if [ "$RC" != "$2" ]; then bad "$4 (cx): exit $RC, want $2 $(grep -m1 '^cxvm:' "$T/$1.c.out")"; return; fi
    if grep -q '^cxvm:' "$T/$1.c.out"; then bad "$4 (cx): exit $RC, but cxvm faulted: $(grep -m1 '^cxvm:' "$T/$1.c.out")"; return; fi
    if [ -n "$3" ] && ! grep -qx "$3" "$T/$1.c.out"; then bad "$4 (cx): exit $RC, but '$3' was not printed"; return; fi
    ok "$4 (cx): exit $RC"
}
# bothrow NAME WANT WHAT — native (the oracle) and cx each exit WANT.
bothrow() {
    build_run native "$T/$1.cyr" "$T/$1.n.out"
    if [ "$RC" = "$2" ]; then ok "$3 (native): exit $RC"; else bad "$3 (native): exit $RC, want $2"; fi
    cxrow "$1" "$2" "" "$3"
}

# R1 the filed repro, verbatim (the issue's Reproduction).
printf 'include "lib/syscalls.cyr"\ninclude "lib/mmap.cyr"\nvar r = cyr_munmap(4194304, 65536);\nsyscall(1, 1, "after munmap\\n", 13);\nsyscall(60, 0 - r);\n' > "$T/r1.cyr"
cxrow r1 38 "after munmap" "R1 the filed repro: cyr_munmap(0x400000, 65536) answers -38 and cxvm lives (it was 139)"
# R2 / R3 the filed fstat line, inside cxvm's data segment and past it.
printf 'var r = syscall(5, 1, 6291712); syscall(60, 100 + r);\n' > "$T/r2.cyr"
cxrow r2 62 "" "R2 fstat(1, guest 0x600100) answers -38 (it was 0: a struct stat over cxvm's globals)"
printf 'var r = syscall(5, 1, 7340032); syscall(60, 100 + r);\n' > "$T/r3.cyr"
cxrow r3 62 "" "R3 fstat(1, guest 0x700000) answers -38 (it was -14)"

# R4 every pointer-taking call answers exactly -38 on cx.
cat > "$T/r4.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/mmap.cyr"
var buf[4096];
var ts[16];
store64(&ts, 0);
store64(&ts + 8, 1000);
var bad = 0;
if (cyr_munmap(4194304, 65536) != 0 - 38) { bad = bad | 1; }
if (cyr_mprotect(4194304, 4096, 1) != 0 - 38) { bad = bad | 2; }
if (sys_stat(".", &buf) != 0 - 38) { bad = bad | 4; }
if (sys_statfs(".", &buf) != 0 - 38) { bad = bad | 8; }
if (sys_nanosleep(&ts, 0) != 0 - 38) { bad = bad | 16; }
if (sys_mkdir("_cx_r4_never", 448) != 0 - 38) { bad = bad | 32; }
if (syscall(9, 0, 4096, 3, 34, 0 - 1) != 0 - 38) { bad = bad | 64; }
if (syscall(63, &buf) != 0 - 38) { bad = bad | 128; }
if (syscall(61, 0 - 1, 0, 1, 0) != 0 - 38) { bad = bad | 256; }
if (syscall(202, &buf, 0, 1) != 0 - 38) { bad = bad | 512; }
if (syscall(72, 0 - 1, 5, &buf) != 0 - 38) { bad = bad | 1024; }
EOF
# 11 bits do not fit one exit code: one run exits the low byte, a second the high bits.
cp "$T/r4.cyr" "$T/r4h.cyr"
echo 'syscall(60, bad & 255);' >> "$T/r4.cyr"
echo 'syscall(60, bad >> 8);' >> "$T/r4h.cyr"
build_run cx "$T/r4.cyr" "$T/r4.c.out"; lo=$RC
build_run cx "$T/r4h.cyr" "$T/r4h.c.out"; hi=$RC
if [ "$lo" = 0 ] && [ "$hi" = 0 ] && ! grep -q '^cxvm:' "$T/r4.c.out" "$T/r4h.c.out" && [ ! -e "$T/_cx_r4_never" ]; then
    ok "R4 (cx): munmap, mprotect, stat, statfs, nanosleep, mkdir, mmap, uname, wait4, futex and fcntl(F_GETLK) each answer -38 (no directory made)"
else bad "R4 (cx): low bits $lo, high bits $hi (1 munmap, 2 mprotect, 4 stat, 8 statfs, 16 nanosleep, 32 mkdir, 64 mmap, 128 uname; high: 1 wait4, 2 futex, 4 fcntl F_GETLK) $(grep -m1 '^cxvm:' "$T/r4.c.out" "$T/r4h.c.out")"; fi

# R5 the scalar-only controls: the host's answer on both legs.
cat > "$T/r5.cyr" <<'EOF'
var bad = 0;
var me = syscall(39);
if (me <= 0) { bad = bad | 1; }
if (syscall(110) <= 0) { bad = bad | 2; }
if (syscall(3, 0 - 1) != 0 - 9) { bad = bad | 4; }
if (syscall(62, me, 0) != 0) { bad = bad | 8; }
if (syscall(32, 0 - 1) != 0 - 9) { bad = bad | 16; }
if (syscall(74, 0 - 1) != 0 - 9) { bad = bad | 32; }
if (syscall(72, 1, 3, 0) < 0) { bad = bad | 64; }
if (syscall(73, 0 - 1, 1) != 0 - 9) { bad = bad | 128; }
syscall(60, bad);
EOF
bothrow r5 0 "R5 getpid, getppid, close(-1), kill(pid, 0), dup(-1), fsync(-1), fcntl(F_GETFL), flock(-1) give the host's answer"

# R6 the translated and served calls still work.
cat > "$T/r6.cyr" <<'EOF'
var bad = 0;
var fd = syscall(2, "_cx_r6.bin", 66, 384);
if (fd < 0) { bad = bad | 1; }
if (syscall(1, fd, "cx-r6-data", 10) != 10) { bad = bad | 2; }
if (syscall(8, fd, 0, 0) != 0) { bad = bad | 4; }
var rb[16];
if (syscall(0, fd, &rb, 10) != 10) { bad = bad | 8; }
if (load8(&rb + 9) != 97) { bad = bad | 8; }
if (syscall(3, fd) != 0) { bad = bad | 16; }
var g[16];
if (syscall(318, &g, 16, 0) != 16) { bad = bad | 32; }
var ts[16];
if (syscall(228, 0, &ts) != 0) { bad = bad | 64; }
if (load64(&ts) <= 0) { bad = bad | 64; }
syscall(60, bad);
EOF
rm -f "$T/_cx_r6.bin"; bothrow r6 0 "R6 open / write / lseek / read / close, getrandom and clock_gettime work"

WANT=8
if [ "$fail" -ne 0 ]; then echo "FAIL: $G — $fail row(s) red, $pass green"; exit 1; fi
if [ "$pass" -ne "$WANT" ]; then echo "FAIL: $G — $pass rows ran, want $WANT (a row stopped running)"; exit 1; fi
echo "PASS: $G — $pass/$WANT rows: cxvm answers a guest syscall it neither translates nor lists as scalar-only -38 without reaching the host (the filed munmap repro lives and exits 38, fstat into cxvm's data segment 62, every pointer-taking wrapper -38), the scalar-only calls and the translated ones keep the host's answer"
exit 0

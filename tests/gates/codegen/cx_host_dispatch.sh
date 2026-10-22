#!/bin/sh
# cx_host_dispatch.sh — 6.7.15 (issues/archived/2026-10-17-cxvm-forwards-guest-x86-numbers-through-host-renumbering.md).
# A cx guest's syscall carries the guest's x86-LINUX number; cxvm serves the calls it lists through the
# HOST's own stdlib wrappers (programs/cxvm.cyr `_cx_host_sys`), so each runs the call the guest names on
# every host — on Windows through the PE routes, -38 where the PE peer has only a stub — and a failure
# answers x86_64 Linux's errno on every host (6.7.16: a Darwin host's is mapped back, `_cx_errno_linux`),
# kill's signal reaches the host as the host's number (6.7.16, `_cx_sig_host`), and F_GETFL answers
# x86_64 Linux's word, O_LARGEFILE included (6.7.16's D29, `_cx_largefile`).
#
# THE DEFECT. Until 6.7.15 cxvm issued the listed calls as `syscall(sn, …)`, a RUNTIME number, and each
# host's compiler renumbers a runtime number through a chain built for that host's own stdlib numbers.
# On aarch64 Linux a guest lseek (8) ran getxattr (-14), kill (62) ran lseek (-9), sched_yield (24) and
# getppid (110) answered -22, exit_group(77) exited 0, and fork (57) ran close, so the parent took the
# child branch (tests/tcyr/crossos/audit_walk_fifo.tcyr exited 10 mid-file); on arm64 macOS kill ran
# lseek and getppid / dup / lseek / getuid / sched_yield / exit_group died of SIGSYS; on both Macs
# open's Linux flag bits read as other Darwin flags. The filed table (x86 cxvm / aarch64 cxvm under
# qemu, before): getppid ppid / 222, kill 0 / 209, dup 209 / 222, lseek 209 / 214, sched_yield 0 / 222,
# exit_group(77) 77 / 0, fork child pid / 0.
#
# THE FIXTURE is tests/fixtures/cx_host_dispatch.cyr, the same source scripts/cross-os-selfhost.sh
# builds once and runs on pi, ecb, ach and cass: raw x86-Linux syscalls, one bit per row, a
# `cxh lin=<mask> pe=<mask>` line, exit 77 when every row has the x86_64-Linux answer, 78 when every
# row has the Windows one (the exit is exit_group's own row). Rows: getpid > 0; getppid > 0;
# close(-1) -9 (Windows too since 6.7.16's D78; it answered 0, CloseHandle of the current-process
# pseudo-handle); kill(getpid(), 0) 0; dup(-1) -9; lseek(-1, 0, 0) -9; sched_yield 0; fork — the parent
# sees the child's pid and the child (which sees 0) writes its getpid() to a file the parent reads
# back; open's flags (O_CREAT|O_TRUNC, O_CREAT|O_EXCL -17, O_APPEND, O_TRUNC, O_DIRECTORY on a file
# -20); fcntl F_GETFL / F_SETFL in Linux bits both ways (O_APPEND 0x400, O_NONBLOCK 0x800, never
# 0x20000, and O_LARGEFILE 0x8000 on the opened file — 6.7.16's D29), F_GETFD, F_DUPFD_CLOEXEC
# (FD_CLOEXEC set on the copy); the path calls (6.7.15,
# issues/archived/2026-10-16-cx-crossos-mkdir-symlink-rows-fail-and-no-gate-runs-them.md) — mkdir, stat of a
# directory and of a 7-byte file (S_IFDIR / S_IFREG, st_size, st_mtime at the x86-Linux offsets cxvm
# fills from the host's own struct stat), symlink, readlink, rename, unlink, rmdir, and truncate to 3
# bytes (6.7.16: -38 on every host until then, while ftruncate was served) (Windows: stat and
# readlink -38, the rest served); dup2's self-dup (6.7.15,
# issues/archived/2026-10-18-aarch64-sys-dup2-same-fd-answers-einval.md) — dup2(1, 1) 1, dup2 of an fd the
# fixture just closed -9 (Windows: both -38, the PE peer's dup2 is a stub); a failure's errno (6.7.16,
# issues/archived/2026-10-18-cxvm-darwin-errnos-reach-the-guest-unmapped.md) — open(link, O_RDONLY|O_NOFOLLOW)
# -40 and rmdir of a non-empty directory -39 (a Mac's cxvm answered Darwin's -62 / -66), and an
# unassigned number (999) -38, cxvm's own refusal, which the map must leave 38 (Darwin's 38 is
# ENOTSOCK) (Windows the same since 6.7.16's D79 — its rmdir answered -1 for every failure);
# kill(getpid(), 99) -22 (6.7.16, issues/archived/2026-10-18-cxvm-macos-kill-signal-numbers-unmapped.md: a
# signal no host has; Windows -38). The signal map itself (SIGUSR1 10 is Darwin's 30, 10 there is
# SIGBUS) is held by the ecb / ach legs of scripts/cross-os-selfhost.sh, which run the filed repro
# (kill(getpid(), 10)) to its SIGUSR1 death, status 158 there. Row 15 (6.7.16,
# issues/archived/2026-10-18-cx-audit-walk-fifo-getdents-mknodat-refused.md): poll(NULL, 0, 60) sleeps; mknodat
# makes a FIFO stat calls one; getdents64 reads a directory whole with a 4096- and a 96-byte buffer
# (every name once, d_type DT_FIFO for the FIFO — a Darwin host converts its records and, for the
# small buffer, reads the directory again) and a 16-byte one is -22; wait4 reaps the fork row's child,
# then -ECHILD; a child that stops itself, is continued and is killed by SIGUSR1 gives 0x137f, 0xffff
# (WCONTINUED) and 10 (a Darwin host reports 0x117f, 0x137f, 30) (Windows: the sleep, the rest -38).
# Row 16 (6.7.16, issues/archived/2026-10-18-cx-crossos-rows-on-a-windows-host-miss-tmp-and-eacces.md):
# O_CREAT | O_EXCL over an existing directory -17 on every host, Windows included (cass's CreateFileW
# says ERROR_ACCESS_DENIED, which cxvm answered as -13 until 6.7.16; wine says ERROR_FILE_EXISTS).
# Row 17 (6.7.16, the platform review of issues/archived/2026-10-18-cx-audit-walk-fifo-getdents-mknodat-refused.md):
# getdents64 lists /dev — a Mac's devfs has no extended readdir, so a small re-read returns fewer
# records than were delivered — with a 200-byte buffer, the 4096-byte listing's names in its order,
# and with a 96-byte one, which ends (0, or -22 on a Mac: ecb 592 of 635) within 2 x the names in
# calls, its names a prefix of that listing (Windows: no /dev, -2; or getdents64 -38).
#
# AXES
#   1  the fixture built NATIVELY (x86_64 Linux, the oracle): exit 77, `cxh lin=0`
#   2  the fixture on the x86_64 cxvm built from this tree: exit 77, `cxh lin=0`
#   3  the fixture on an aarch64 cxvm built from this tree, under qemu-aarch64: exit 77 (named SKIP
#      without qemu — qemu is an emulator; pi runs the same .cyx in the cross-OS leg)
#   4  audit_walk_fifo.tcyr on that aarch64 cxvm reaches its summary line (it exited 10 mid-file) and,
#      since 6.7.16, reads `8 passed, 0 failed` (2 passed, 6 failed: getdents64 / mknodat / wait4 -38)
#   5  the fixture on a PE cxvm under wine: exit 78, `pe=0` (named SKIP without wine; cass runs it)
#   6  cxvm builds for every host target with no syscall diagnostic: the two Mach-O targets name no
#      unrouted number (each would SIGSYS there), and the PE build no longer warns that a runtime-
#      numbered syscall has no Windows route (the shape the pass-through had)
#
# MUTATION LEDGER (6.7.15, measured):
#   MU1 the 6.7.14 cxvm (git show 2eeb53c46:programs/cxvm.cyr) -> RED 4: axis 3 (exit 3,
#       `lin=490`: getppid, kill, lseek, sched_yield, fork, open), axis 4 (exit 10, no summary),
#       axis 5 (exit 3), axis 6 (the PE runtime-number warning)
#   MU2 `_cx_open_flags` returning the guest's bits on every host -> RED 1: axis 3 (`lin=256`, the
#       O_DIRECTORY sub-row: 0x10000 is arm64's O_DIRECT, the open succeeds)
#   MU3 `_cx_host_fcntl`'s F_GETFL without `_cx_flags_back` -> RED 1: axis 3 (`lin=512`: arm64
#       Linux reports its O_LARGEFILE 0x20000, which reads as x86's O_NOFOLLOW unmapped; Darwin's
#       O_APPEND / O_NONBLOCK bits are held by the ecb / ach legs)
#   MU4 `_cx_host_stat` without its st_mode store -> RED 1: axis 3 (`lin=1024`: the aarch64 host's
#       struct is refilled at the x86 offsets, the x86 host's is the guest's own — Darwin's layouts
#       are held by the ecb / ach legs)
#   MU5 (issues/archived/2026-10-18-aarch64-sys-dup2-same-fd-answers-einval.md) the aarch64 peer's sys_dup2
#       without its self-dup arm (dup3 for every pair, the pre-6.7.15 body) -> RED 1: axis 3 (exit 12,
#       `lin=2048`: dup2(1, 1) and the closed fd both -22, dup3's EINVAL)
# MU6 (6.7.16, the Darwin errno map) `_cx_errno_linux` answering r as it is — the 6.7.15 cxvm — ->
#       no local axis sees it (the map is the identity on a Linux or Windows host): on ecb and ach
#       the fixture exits 13, `lin=4096` (-62 / -66), measured; the cross-OS legs require 77
# MU7 `_cx_host_enosys` answering -38 on macOS (cxvm's own refusal spelled Linux's way, then mapped
#       as Darwin's ENOTSOCK) -> on ach exit 13, `lin=4096` (syscall(999) -88; every unserved number
#       and fcntl's lock commands read -88), measured; local axes unchanged, as MU6
# MU8 (6.7.16, the signal map) `_cx_host_kill` passing the guest's number as it is -> no local axis
#       sees it (the identity on a Linux host): on ecb and ach the cross-OS legs' kill repro dies of
#       Darwin's SIGBUS ("Bus error: 10", status 138, want 158), measured
# MU9 (6.7.16's D29) `_cx_largefile` answering 0 (F_GETFL without O_LARGEFILE off x86_64 Linux, the
#       6.7.15 word) -> RED 1: axis 3 (exit 10, `lin=512`: qemu reports arm64's 0x20000), measured;
#       on pi, ecb and ach the same exit 10 (the cross-OS legs require 77), measured
# MU10 (6.7.16, the audit-walk calls) the cxvm before them (86dafdc49's programs/cxvm.cyr in a scratch
#       copy of the tree, so every axis builds it) -> RED 4: axes 2 / 3 (exit 15, `lin=16384`), axis
#       4 (`2 passed, 6 failed`), axis 5 (exit 2, `pe=16384`: poll(NULL, 0, 60) was not served)
# MU11 `_cx_wstatus_linux` answering the host's word as it is -> no local axis sees it (the identity
#       on a Linux host): on ecb and ach the fixture exits 15, `lin=16384` (0x117f, Darwin's SIGSTOP),
#       measured
# MU12 `_cx_darwin_getdents` without its put-back (the records past the guest's buffer dropped) ->
#       on ecb and ach exit 15, `lin=16384` (the 96-byte listing misses names), measured
# MU13 (6.7.16) `_cx_host_open` without its Windows -13 -> -17 rule -> no local axis sees it (wine's
#       CreateFileW says ERROR_FILE_EXISTS): on cass the fixture exits 2, `pe=32768`, measured
# MU15 (6.7.16, p16) cxvm without its truncate (76) arm -> RED 3: axes 2 / 3 exit 11 (`lin=1024`:
#       truncate -38), axis 5 exits 2 (`pe=1024`), measured
# MU14 (6.7.16, the platform review) `_cx_darwin_getdents` handing the guest every record it converted
#       whatever the re-read returned (26e8eeaff's programs/cxvm.cyr) -> no local axis sees it (the
#       converter is Darwin's): on ecb the fixture exits 17, `lin=65536` (/dev with 200 bytes read 953
#       names, 318 of them repeats, for 635), measured
#
# COMPILERS. CC=${CYCC:-build/cycc}; the cx compiler, cxvm (x86 and aarch64), the aarch64 cross
# compiler and the PE cross compiler are built from THIS tree (CYCC_CX / CXVM override the first two).
# Exit 77 = could not run (no compiler at $CC, no timeout(1)); never a SKIP line with exit 0.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
_abs() { case $1 in /*|'') printf '%s' "$1" ;; *) printf '%s/%s' "$(pwd)" "$1" ;; esac; }
CC=$(_abs "${CYCC:-$ROOT/build/cycc}")
CYCC_CX=$(_abs "${CYCC_CX:-}")
CXVM=$(_abs "${CXVM:-}")
G=cx_host_dispatch
[ -x "$CC" ] || { echo "SKIP: $G — no compiler at $CC (exit 77: a SKIP, not a PASS)"; exit 77; }
command -v timeout >/dev/null 2>&1 || { echo "SKIP: $G — no timeout(1) (exit 77: a SKIP, not a PASS)"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G — mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
# A PRIVATE wine prefix and wine's own HOME under $T — never the user's ~/.wine. The EXIT teardown
# stops THIS prefix's wineserver and removes its server dir (the pe_last_error_reroute.sh shape).
WP="$T/wp"
WHM="$T/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT INT TERM
cd "$ROOT" || exit 1
ulimit -c 0 2>/dev/null || true
FX=tests/fixtures/cx_host_dispatch.cyr
[ -f "$FX" ] || { echo "FAIL: $G — $FX is missing"; exit 1; }

pass=0
fail=0
skip=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# _build OUT SRC [ENV=VAL] — compile SRC with $CC into OUT; 0 when OUT is non-empty.
_build() {
    _o=$1; _s=$2; shift 2
    _r=0; env "$@" "$CC" < "$_s" > "$_o" 2> "$_o.err" || _r=$?
    chmod +x "$_o" 2>/dev/null || true
    [ "$_r" = 0 ] && [ -s "$_o" ]
}

if [ -n "$CYCC_CX" ]; then CX=$CYCC_CX; else
    CX=$T/cycc_cx
    _build "$CX" src/main_cx.cyr || { echo "FAIL: $G — cannot build the cx compiler from src/main_cx.cyr"; sed -n 1,3p "$CX.err"; exit 1; }
fi
if [ -n "$CXVM" ]; then VM=$CXVM; else
    VM=$T/cxvm
    _build "$VM" programs/cxvm.cyr || { echo "FAIL: $G — cannot build cxvm from programs/cxvm.cyr"; sed -n 1,3p "$VM.err"; exit 1; }
fi
"$CX" < "$FX" > "$T/cxh.cyx" 2> "$T/cxh.err" || true
[ -s "$T/cxh.cyx" ] || { echo "FAIL: $G — the fixture does not build for cx: $(grep -m1 '^error' "$T/cxh.err")"; exit 1; }

# _runrow AXIS WANT OUTFILE RC WHAT — the run exited WANT and printed `cxh lin=0` (77) / `pe=0` (78).
_runrow() {
    _line=$(grep -m1 '^cxh ' "$3" | tr -d '\r' || true)
    _mark="lin=0 "
    [ "$2" = 78 ] && _mark="pe=0"
    if [ "$4" != "$2" ]; then bad "axis $1: $5 exited $4, want $2 ('$_line'; $(grep -m1 '^cxvm:' "$3" || true))"; return; fi
    case "$_line " in *"$_mark"*) ok "axis $1: $5 exits $2 ('$_line')" ;; *) bad "axis $1: $5 exited $2 but printed '$_line'" ;; esac
}

# axis 1 — the native oracle.
mkdir -p "$T/a1"
if _build "$T/nat" "$FX"; then
    rc=0; (cd "$T/a1" && timeout 60 "$T/nat" > "$T/a1.out" 2>&1) || rc=$?
    _runrow 1 77 "$T/a1.out" "$rc" "the fixture built natively (x86_64 Linux, the oracle)"
else bad "axis 1: the fixture does not build natively: $(grep -m1 '^error' "$T/nat.err")"; fi

# axis 2 — the x86_64 cxvm.
mkdir -p "$T/a2"
rc=0; (cd "$T/a2" && timeout 60 "$VM" < "$T/cxh.cyx" > "$T/a2.out" 2>&1) || rc=$?
_runrow 2 77 "$T/a2.out" "$rc" "the fixture on the x86_64 cxvm"

# axes 3 / 4 — an aarch64 cxvm under qemu (the aarch64 cross compiler also serves axis 6).
A64=0
if _build "$T/cycc_a64" src/main_aarch64.cyr; then
    A64=1
    "$T/cycc_a64" < programs/cxvm.cyr > "$T/cxvm_a64" 2> "$T/cxvm_a64.err" || true
    chmod +x "$T/cxvm_a64"
fi
if ! command -v qemu-aarch64 > /dev/null 2>&1; then
    echo "  SKIP: axes 3 / 4 — qemu-aarch64 not installed (pi runs the fixture in scripts/cross-os-selfhost.sh)"
    skip=$((skip + 2))
elif [ "$A64" != 1 ]; then bad "axes 3 / 4: cannot build the aarch64 cross compiler from src/main_aarch64.cyr"
elif [ ! -s "$T/cxvm_a64" ]; then bad "axes 3 / 4: the aarch64 cross compiler does not build cxvm: $(sed -n 1p "$T/cxvm_a64.err")"
else
    mkdir -p "$T/a3"
    rc=0; (cd "$T/a3" && timeout 120 qemu-aarch64 "$T/cxvm_a64" < "$T/cxh.cyx" > "$T/a3.out" 2>&1) || rc=$?
    _runrow 3 77 "$T/a3.out" "$rc" "the fixture on the aarch64 cxvm (qemu)"
    "$CX" < tests/tcyr/crossos/audit_walk_fifo.tcyr > "$T/aw.cyx" 2> "$T/aw.err" || true
    if [ -s "$T/aw.cyx" ]; then
        mkdir -p "$T/a4"
        rc=0; (cd "$T/a4" && timeout 120 qemu-aarch64 "$T/cxvm_a64" < "$T/aw.cyx" > "$T/a4.out" 2>&1) || rc=$?
        a4s=$(grep -m1 '^[0-9]* passed, [0-9]* failed' "$T/a4.out" || true)
        a4n=${a4s%% passed*}
        if [ -z "$a4s" ]; then bad "axis 4: audit_walk_fifo.tcyr on the aarch64 cxvm stopped without a summary (exit $rc; the parent took fork's child branch before 6.7.15)"
        elif [ "$rc" = 0 ] && [ "$a4n" -ge 8 ] && case "$a4s" in *" passed, 0 failed"*) true ;; *) false ;; esac; then
            ok "axis 4: audit_walk_fifo.tcyr on the aarch64 cxvm reaches its summary, every row green ($a4s)"
        else bad "axis 4: audit_walk_fifo.tcyr on the aarch64 cxvm: exit $rc, '$a4s' (want 8+ passed, 0 failed; getdents64 / mknodat / wait4 answered -38 before 6.7.16)"; fi
    else bad "axis 4: audit_walk_fifo.tcyr does not build for cx: $(grep -m1 '^error' "$T/aw.err")"; fi
fi

# axis 5 — a PE cxvm under wine.
if _build "$T/cycc_win" src/main_win.cyr; then
    "$T/cycc_win" < programs/cxvm.cyr > "$T/cxvm.exe" 2> "$T/cxvm_pe.err" || true
    if [ ! -s "$T/cxvm.exe" ]; then bad "axis 5: the PE cross compiler does not build cxvm: $(sed -n 1p "$T/cxvm_pe.err")"
    elif command -v wine > /dev/null 2>&1; then
        mkdir -p "$T/a5" "$WHM"
        cp "$T/cxvm.exe" "$T/cxh.cyx" "$T/a5/"
        rc=0
        ( cd "$T/a5" && LANG=C.UTF-8 WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' \
            timeout 180 wine cxvm.exe < cxh.cyx > "$T/a5.out" 2> /dev/null ) || rc=$?
        _runrow 5 78 "$T/a5.out" "$rc" "the fixture on the PE cxvm (wine)"
    else
        echo "  SKIP: axis 5 — wine not installed (cass runs the fixture in scripts/cross-os-selfhost.sh)"
        skip=$((skip + 1))
    fi
else bad "axes 5 / 6: cannot build the PE cross compiler from src/main_win.cyr"; fi

# axis 6 — cxvm builds for every host target with no syscall diagnostic.
a6=""
if [ "$A64" = 1 ]; then
    CYRIUS_MACHO_ARM=1 "$T/cycc_a64" < programs/cxvm.cyr > "$T/cxvm_ma" 2> "$T/cxvm_ma.err" || true
    [ -s "$T/cxvm_ma" ] || a6="$a6 [arm64 Mach-O does not build]"
    grep -q 'not routed' "$T/cxvm_ma.err" && a6="$a6 [arm64 Mach-O: $(grep -m1 'not routed' "$T/cxvm_ma.err")]"
else a6="$a6 [no aarch64 cross compiler for the arm64 Mach-O build]"; fi
CYRIUS_MACHO=1 "$CC" < programs/cxvm.cyr > "$T/cxvm_mx" 2> "$T/cxvm_mx.err" || true
[ -s "$T/cxvm_mx" ] || a6="$a6 [x86_64 Mach-O does not build]"
grep -q 'not routed' "$T/cxvm_mx.err" && a6="$a6 [x86_64 Mach-O: $(grep -m1 'not routed' "$T/cxvm_mx.err")]"
if [ -s "$T/cxvm.exe" ]; then
    grep -q 'non-literal number' "$T/cxvm_pe.err" && a6="$a6 [PE: $(grep -m1 'non-literal number' "$T/cxvm_pe.err" | cut -c1-110)]"
else a6="$a6 [PE does not build]"; fi
if [ -z "$a6" ]; then ok "axis 6: cxvm builds for arm64 Mach-O, x86_64 Mach-O and PE with no unrouted or runtime-numbered syscall"
else bad "axis 6:$a6"; fi

WANT=$((6 - skip))
if [ "$fail" -ne 0 ]; then echo "FAIL: $G — $fail row(s) red, $pass green"; exit 1; fi
if [ "$pass" -ne "$WANT" ]; then echo "FAIL: $G — $pass rows ran, want $WANT (a row stopped running)"; exit 1; fi
echo "PASS: $G — $pass/$WANT axes ($skip named SKIP): a cx guest's getpid / getppid / close / kill / dup / lseek / sched_yield / fork / exit_group, open's flags, fcntl's status flags, the path calls (mkdir / stat / symlink / readlink / rename / unlink / rmdir), dup2's self-dup, a failure's errno, kill's signal, F_GETFL's O_LARGEFILE and getdents64 / mknodat / wait4 / poll(NULL, 0, ms) give the fixture's x86_64-Linux answers on the x86 and aarch64 cxvm (its Windows answers on the PE one) — cxvm serves them through the host's own wrappers, running the call the guest names, not the guest's number"
exit 0

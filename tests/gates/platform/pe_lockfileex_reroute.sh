#!/bin/sh
# 6.7.12 — kernel32!LockFileEx / UnlockFileEx are routed on PE (0xF04C / 0xF04D), and xflock's
# Windows arm (lib/io.cyr `_xflock_win`) emulates flock with them.
#
# ⛔ WHY: xflock's PE arm was `return -1` — "LockFileEx — not wired". patra takes every lock
# through xflock and runs its open-time WAL recovery only under a granted LOCK_EX|LOCK_NB, so on
# Windows the recovery never ran and a crashed transaction's partial writes stayed applied.
# Windows byte locks are MANDATORY, not advisory: locking the file's real bytes would fail every
# read and write through another handle, so the arm locks ONE sentinel byte at 2^63 - 1 (length
# 1), past any data a file can hold — it excludes other lockers only. Measured on cass: every
# offset up to 2^64 - 2 is accepted by NTFS, and a second handle reads and writes the data bytes
# while the first holds LOCK_EX.
#
# THE AXES
#   axis 1  `syscall(0xF04C, …6 args)` (argc 7) and `syscall(0xF04D, …5 args)` (argc 6) build
#           with CYRIUS_TARGET_WIN=1 and are not reported as unrouted; one argument short, each
#           IS reported — the route is literal-and-arity.
#   axis 2  the routed-number note names `0xF04C-0xF04D (kernel32: LockFileEx/UnlockFileEx)`
#           and is printed WHOLE past it: the note is one literal written with a hand-counted byte
#           length, and a length left at its old value silently cuts the newest entries off the
#           end. (The END itself is pinned by the newest reroute's gate since W2's 0xF04E:
#           tests/gates/toolchain/embed_link_race_pe.sh.)
#   axis 3  the axis-1 builds IMPORT LockFileEx and UnlockFileEx (objdump -p; that axis alone is
#           skipped without an objdump that reads PE).
#   axis 4  STATIC, lib/io.cyr: xflock's CYRIUS_TARGET_WIN arm calls _xflock_win (the constant
#           -1 is gone), and _xflock_win locks the sentinel (0x7FFFFFFFFFFFFFFF, length 1) through
#           its helpers: _xflock_win_lock puts the byte's offset in the OVERLAPPED and calls 0xF04C at
#           argc 7, _xflock_win_unlock 0xF04D at argc 6, reading GetLastError (0xF04B) for
#           ERROR_LOCK_VIOLATION (33) and ERROR_NOT_LOCKED (158). _xflock_win_unlock's answers are
#           pinned (6.7.13): 0 for a byte this handle held, 1 for ERROR_NOT_LOCKED — axis 6's
#           re-lock probe reads that 0 as "held in this mode", so a helper answering otherwise
#           silently restores 6.7.12's unlock-first re-lock while axis 6 still sees its call site.
#           6.7.17 (D37: "Linux's errno via the Windows error table"): a NEGATIVE fd is -9 in
#           _xflock_win before any helper reaches Windows (-1 is the current-process pseudo-handle);
#           each helper answers a failure it does not read itself (contention -11, ERROR_NOT_LOCKED)
#           with `syscall(0xF04F)` — the code through the one Win32 table, a closed handle -9 — and
#           _xflock_win / _xflock_win_release pass that errno on: neither has a `return 0 - 1;`
#           (every such failure answered -1). The op is checked before both fd checks, as Linux
#           checks it: a bad op is -22 whatever the fd (D37: "a bad op stays -22"). The behaviour
#           rows are unopened_fd_ebadf.tcyr's (wine: axis 5 does not run it;
#           pe_last_error_reroute.sh axis 6d pins 0xF04F's -9).
#   axis 5  BEHAVIOUR under wine (skipped without wine — NOT hardware; the cass cross-OS leg of
#           the release gate runs the same .tcyr): the filed repro exits 11 (xflock LOCK_EX -> 0;
#           10 before), tests/tcyr/crossos/xflock_two_handle.tcyr's PE build reports 0 failed
#           over at least 30 rows, and xflock_relock_keeps_lock.tcyr's over at least 50.
#   axis 6  STATIC, lib/io.cyr (6.7.13): a re-lock to the mode the handle holds is a no-op that
#           never lets go of the sentinel. 6.7.12 unlocked the handle's sentinel before every
#           LOCK_SH / LOCK_EX, also for the mode already held, and on real Windows a handle blocked
#           waiting for the lock was granted it in that gap (patra lost a second handle's
#           acknowledged writes, 40 of 60 rows). The mode is recorded in the kernel as a lock on
#           one more byte: _xflock_win_mode answers 2^63 - 2 for LOCK_EX and 2^63 - 3 for LOCK_SH
#           (never the sentinel); _xflock_win probes that byte (_xflock_win_unlock(fd, mode) == 0)
#           and returns 0 from that branch BEFORE its first _xflock_win_release; it records the
#           mode only after the sentinel is granted; _xflock_win_release drops both mode bytes
#           before the sentinel. ⚠ wine shows the 6.7.12 gap only on some runs (the threaded rows
#           of xflock_relock_keeps_lock.tcyr failed 1 of 4 there), so this static axis, with axis
#           4's pin on _xflock_win_unlock's answers, is the deterministic local guard; cass failed
#           those rows on every run (3 rows, 4 of 4).
#
# MUTATION LEDGER — every mutant BUILT AND RUN 2026-10-15 (6.7.12 windows lane, W1; x86_64 Linux
# + wine; CYCC=<mutant cycc> for the compiler rows):
#   mutant                                                       result
#   the 0xF04C row removed from _PE_ROUTE_FILELOCK               axes 1, 3 and 5 FAIL
#   the note's byte count left at 1587                           axis 2 FAIL (the note ends at 0xF04B)
#   xflock's Windows arm back to `return -1`                     axes 4 and 5 FAIL (repro exits 10)
#   the sentinel offset 0 instead of 2^63 - 1 (locks real data)  axis 4 FAIL. ⚠ axis 5 PASSES: wine
#                                                                does not enforce a byte lock on
#                                                                another handle's I/O. On cass the
#                                                                same .tcyr fails 5 rows (B's read
#                                                                and write refused) — measured.
# 6.7.13 (stdlib lane, L1) — every mutant BUILT AND RUN 2026-10-16 (x86_64 Linux + wine; cass):
#   the mode-byte probe removed (6.7.12's unlock-first re-lock)  axis 6 FAIL; axis 5 flaky under
#                                                                wine (the relock .tcyr failed 1 of
#                                                                4 runs). On cass the 6.7.12 arm
#                                                                fails the relock .tcyr's 3 threaded
#                                                                rows on every run — measured.
#   _xflock_win_mode answers the sentinel for LOCK_EX            axis 6 FAIL; axis 5 FAILS by HANGING
#                                                                (the sentinel locked twice
#                                                                exclusive deadlocks the first
#                                                                LOCK_EX) — so the wine runs are
#                                                                bounded now (exit 124)
#   _xflock_win_release drops the sentinel before the mode bytes axis 6 FAIL
# 6.7.13 (stdlib lane, review fix) — BUILT AND RUN 2026-10-16 (x86_64 Linux + wine):
#   _xflock_win_unlock answers 1 for a held byte                 axis 4 FAIL (was green before this
#                                                                row: the probe never fires, every
#                                                                re-lock takes 6.7.12's unlock-first
#                                                                path; axis 5 under wine did not
#                                                                catch it either)
#   _xflock_win_unlock answers 0 for ERROR_NOT_LOCKED (158)      axis 4 FAIL; axis 5 FAILS by HANGING
#                                                                (an unheld mode byte reads as held)
# 6.7.17 (plat lane, PL3) — every mutant BUILT AND RUN 2026-10-22 (x86_64 Linux + wine 11.20):
#   _xflock_win's `fd < 0` check removed                         axis 4 FAIL (under wine LockFileEx
#                                                                of -4 / -1 answers -9 anyway: only
#                                                                this axis holds "never handed to
#                                                                Windows")
#   _xflock_win_lock's last line back to `return 0 - 1;`         axis 4 FAIL; unopened_fd_ebadf.tcyr
#                                                                under wine 2 rows (-1 for -9)
#   _xflock_win_release folds to `return 0 - 1;` again           axis 4 FAIL; unopened_fd_ebadf.tcyr
#                                                                under wine 1 row (LOCK_UN -1)
#   the op check moved back below the two fd checks (review fix) axis 4 FAIL; unopened_fd_ebadf.tcyr
#                                                                under wine 3 rows (-9 for -22)
# Exit 77 = could not run (the SKIP protocol). CHANGELOG [6.7.12] [6.7.13] [6.7.17]
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: pe_lockfileex_reroute: build/cycc missing"; exit 77; }
IO="$ROOT/lib/io.cyr"
TC="$ROOT/tests/tcyr/crossos/xflock_two_handle.tcyr"
TR="$ROOT/tests/tcyr/crossos/xflock_relock_keeps_lock.tcyr"
[ -f "$IO" ] || { echo "FAIL: pe_lockfileex_reroute: $IO is missing"; exit 1; }
[ -f "$TC" ] || { echo "FAIL: pe_lockfileex_reroute: $TC is missing"; exit 1; }
[ -f "$TR" ] || { echo "FAIL: pe_lockfileex_reroute: $TR is missing"; exit 1; }

D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: pe_lockfileex_reroute: mktemp -d failed"; exit 1; }
# A PRIVATE wine prefix, and wine's own HOME / XDG_CACHE_HOME, under $D — never the user's
# ~/.wine or ~/.cache. The EXIT teardown stops THIS prefix's wineserver and removes its server
# dir, which `wineserver -k` leaves behind (the pe_last_error_reroute.sh shape). CHANGELOG [6.6.17]
WP="$D/wp"
WHM="$D/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$D"' EXIT INT TERM

pass=0; fail=0
ok()  { pass=$((pass + 1)); }
bad() { printf '  FAIL: %s\n' "$1"; fail=$((fail + 1)); }

build() {  # $1 = file stem, $2 = the syscall's argument list
    printf 'fn main(): i64 {\n    var ov[32];\n    var j = syscall(%s);\n    return j & 0;\n}\nvar r = main();\nsyscall(60, r);\n' "$2" > "$D/$1.cyr"
    CYRIUS_TARGET_WIN=1 "$CC" < "$D/$1.cyr" > "$D/$1.exe" 2> "$D/$1.err"
}

# axis 1: routed at argc 7 / 6, reported one argument short.
rc=0; build lk "0xF04C, 0, 2, 0, 1, 0, &ov" || rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$D/lk.exe" ]; then bad "axis 1: syscall(0xF04C, 6 args) did not build for PE (rc $rc)"
elif grep -q "syscall 61516 with" "$D/lk.err"; then bad "axis 1: syscall(0xF04C, 6 args) is reported as not routed"
else ok; fi
rc=0; build un "0xF04D, 0, 0, 1, 0, &ov" || rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$D/un.exe" ]; then bad "axis 1: syscall(0xF04D, 5 args) did not build for PE (rc $rc)"
elif grep -q "syscall 61517 with" "$D/un.err"; then bad "axis 1: syscall(0xF04D, 5 args) is reported as not routed"
else ok; fi
build lks "0xF04C, 0, 2, 0, 1, &ov"
if grep -q "syscall 61516 with 5 argument" "$D/lks.err"; then ok
else bad "axis 1: syscall(0xF04C, 5 args) (one argument short) was not reported"; fi
build uns "0xF04D, 0, 0, 1, &ov"
if grep -q "syscall 61517 with 4 argument" "$D/uns.err"; then ok
else bad "axis 1: syscall(0xF04D, 4 args) (one argument short) was not reported"; fi

# axis 2: the note names 0xF04C-0xF04D and reaches its own end.
if grep -q '^  note: CYRIUS_TARGET_WIN=1 routes' "$D/lks.err"; then
    note=$(grep '^  note: CYRIUS_TARGET_WIN=1 routes' "$D/lks.err" || true)
    # 6.7.12 (W2): 0xF04C-0xF04D is no longer the newest entry (0xF04E follows it), so the END of
    # the note — its byte count — is pinned by the newest reroute's gate
    # (tests/gates/toolchain/embed_link_race_pe.sh axis 2); here the entry must be present and
    # followed by the next one. CHANGELOG [6.7.12]
    case "$note" in
        *'+ 0xF04C-0xF04D (kernel32: LockFileEx/UnlockFileEx) + '*) ok ;;
        *'+ 0xF04C-0xF04D (kernel32: LockFileEx/UnlockFileEx).') ok ;;
        *'0xF04C-0xF04D (kernel32: LockFileEx/UnlockFileEx)'*) bad "axis 2: the note names 0xF04C-0xF04D but is cut short after it — its byte count is wrong" ;;
        *) bad "axis 2: the routed-number note does not name 0xF04C-0xF04D (kernel32: LockFileEx/UnlockFileEx) — or it is cut short: ...$(printf '%s' "$note" | tail -c 60)" ;;
    esac
else
    bad "axis 2: the short-arity probe printed no routed-number note"
fi

# axis 3: the imports.
if [ -s "$D/lk.exe" ] && objdump -p "$D/lk.exe" > "$D/imp.txt" 2>/dev/null && grep -q 'DLL Name' "$D/imp.txt"; then
    if grep -qE '[[:space:]]LockFileEx$' "$D/imp.txt"; then ok
    else bad "axis 3: the syscall(0xF04C) build does not import kernel32!LockFileEx"; fi
    if [ -s "$D/un.exe" ] && objdump -p "$D/un.exe" > "$D/impu.txt" 2>/dev/null \
        && grep -qE '[[:space:]]UnlockFileEx$' "$D/impu.txt"; then ok
    else bad "axis 3: the syscall(0xF04D) build does not import kernel32!UnlockFileEx"; fi
else
    echo "  SKIP: axis 3 (no objdump that reads PE)"
fi

# axis 4: static, over the tree's lib/io.cyr.
# No reader below a pipe exits before its input ends: the writer would die of SIGPIPE, which
# `bash -eo pipefail` (GitHub's run: shell) reads as the pipeline failing — the gate stopped with
# rc 141 and no verdict (fnbody behind `grep -v`: 4 of 100 runs), and a `grep -q` match read as
# a miss (axis 3's objdump listing). A file is grepped where it lies, a body in a variable through
# a here-document (has / lno), and gates_verdict_under_pipefail.sh axis 3 scans this file for the
# shape. CHANGELOG [6.7.17]
xarm=$(awk '/^fn xflock\(/ { s = 1 } s == 1 { print } s == 1 && /^}/ { exit }' "$IO" \
    | awk 'w < 2 && /^[[:space:]]*#ifdef CYRIUS_TARGET_WIN/ { w = 1; next } w == 1 { print; w = 2 }')
case "$xarm" in
    *'return _xflock_win(fd, op);'*) ok ;;
    *) bad "axis 4: xflock's CYRIUS_TARGET_WIN arm does not call _xflock_win (it reads: $(printf '%s' "$xarm" | tr -s ' '))" ;;
esac
# One fn of lib/io.cyr, comment lines dropped: from `fn NAME(` to its closing brace (awk reads the
# file itself).
fnbody() { awk -v n="fn $1(" '/^[[:space:]]*#/ { next } index($0, n) == 1 { s = 1 } s == 1 { print } s == 1 && /^}/ { exit }' "$IO"; }
# has TEXT PATTERN: TEXT has a line matching PATTERN. lno TEXT PATTERN: the first such line's
# number. grep reads a here-document, so its stop at the first match leaves no writer to kill.
has() {
    grep -q -e "$2" <<EOF
$1
EOF
}
lno() {
    grep -n -m1 -e "$2" <<EOF | cut -d: -f1
$1
EOF
}
body=$(fnbody _xflock_win)
lbody=$(fnbody _xflock_win_lock)
ubody=$(fnbody _xflock_win_unlock)
f4=$fail
if [ -z "$body" ] || [ -z "$lbody" ] || [ -z "$ubody" ]; then
    bad "axis 4: lib/io.cyr lacks _xflock_win, _xflock_win_lock or _xflock_win_unlock"
else
    has "$body" '_xflock_win_lock(fd, 0x7FFFFFFFFFFFFFFF, fl);' \
        || bad "axis 4: _xflock_win does not lock the sentinel 2^63 - 1 (a lock on real bytes fails other handles' reads and writes)"
    has "$lbody" 'store64(&ov + 16, off);' \
        || bad "axis 4: _xflock_win_lock does not put the byte's offset in the OVERLAPPED"
    has "$lbody" 'syscall(0xF04C, fd, fl, 0, 1, 0, &ov)' \
        || bad "axis 4: _xflock_win_lock does not LockFileEx one byte (0xF04C, argc 7)"
    has "$ubody" 'store64(&ov + 16, off);' \
        || bad "axis 4: _xflock_win_unlock does not put the byte's offset in the OVERLAPPED"
    has "$ubody" 'syscall(0xF04D, fd, 0, 1, 0, &ov)' \
        || bad "axis 4: _xflock_win_unlock does not UnlockFileEx one byte (0xF04D, argc 6)"
    has "$lbody" 'e == 33' \
        || bad "axis 4: _xflock_win_lock does not map ERROR_LOCK_VIOLATION (33) to -EAGAIN"
    has "$ubody" '== 158) { return 1; }' \
        || bad "axis 4: _xflock_win_unlock does not answer 1 for ERROR_NOT_LOCKED (158) (nothing held must not read as held)"
    # 6.7.13: the re-lock probe (axis 6) reads this helper's 0 as "this handle held the byte"; a
    # helper that answers anything else for a granted unlock never fires the probe, and every
    # re-lock silently goes back to 6.7.12's unlock-first gap. CHANGELOG [6.7.13]
    has "$ubody" 'if (u > 0) { return 0; }' \
        || bad "axis 4: _xflock_win_unlock does not answer 0 for a lock this handle held (the re-lock probe would never fire: 6.7.12's unlock-first re-lock)"
    # 6.7.17 (D37): a negative fd never reaches Windows; every other failure answers its errno
    # through the one Win32 table (0xF04F), and nothing folds it back to -1. CHANGELOG [6.7.17]
    neg=$(lno "$body" 'if (fd < 0) { return 0 - 9; }')
    hlp=$(lno "$body" '_xflock_win_\(unlock\|lock\|release\)(')
    if [ -z "$neg" ] || [ -z "$hlp" ] || [ "$neg" -ge "$hlp" ]; then
        bad "axis 4: _xflock_win does not answer a negative fd -9 before its first lock call (6.7.17's D37: line '${neg}', first helper '${hlp}')"
    fi
    # The op is checked before both fd checks, as Linux's flock(2) checks it: a bad op is -22 for
    # every fd (D37: "a bad op stays -22"); with an fd check first a negative or an aliasing fd
    # answered -9. CHANGELOG [6.7.17]
    opl=$(lno "$body" 'if (cmd != 1) { if (cmd != 2) { if (cmd != 8) { return 0 - 22; } } }')
    al=$(lno "$body" 'if (_win_fd_aliases(fd) == 1) { return 0 - 9; }')
    if [ -z "$opl" ] || [ -z "$neg" ] || [ -z "$al" ] || [ "$opl" -ge "$neg" ] || [ "$opl" -ge "$al" ]; then
        bad "axis 4: _xflock_win does not refuse a bad op -22 before its fd checks (Linux answers -22 for every fd): op check line '${opl}', fd < 0 '${neg}', alias '${al}'"
    fi
    has "$lbody" 'return syscall(0xF04F);' \
        || bad "axis 4: _xflock_win_lock does not answer a failure's errno through the Win32 table (syscall(0xF04F); 6.7.17's D37)"
    has "$ubody" 'return syscall(0xF04F);' \
        || bad "axis 4: _xflock_win_unlock does not answer a failure's errno through the Win32 table (syscall(0xF04F); 6.7.17's D37)"
    if has "$body" 'return 0 - 1;' || has "$(fnbody _xflock_win_release)" 'return 0 - 1;'; then
        bad "axis 4: _xflock_win or _xflock_win_release folds a failure to -1 (6.7.17's D37: pass the errno on)"
    fi
    [ "$fail" = "$f4" ] && ok
fi

# axis 6: a re-lock to the mode the handle holds never lets go of the sentinel (6.7.13).
mbody=$(fnbody _xflock_win_mode)
rbody=$(fnbody _xflock_win_release)
f6=$fail
if [ -z "$body" ] || [ -z "$mbody" ] || [ -z "$rbody" ]; then
    bad "axis 6: lib/io.cyr lacks _xflock_win, _xflock_win_mode or _xflock_win_release"
else
    # The mode bytes: 2^63 - 2 for LOCK_EX, 2^63 - 3 otherwise; never the sentinel.
    has "$mbody" 'if (cmd == 2) { return 0x7FFFFFFFFFFFFFFE; }' \
        || bad "axis 6: _xflock_win_mode does not record LOCK_EX on byte 2^63 - 2"
    has "$mbody" 'return 0x7FFFFFFFFFFFFFFD;' \
        || bad "axis 6: _xflock_win_mode does not record LOCK_SH on byte 2^63 - 3"
    if has "$mbody" '0x7FFFFFFFFFFFFFFF'; then
        bad "axis 6: _xflock_win_mode names the sentinel 2^63 - 1 (the mode record must be its own byte)"
    fi
    # The probe and its no-op return come before the first release of the sentinel.
    lp=$(lno "$body" 'if (_xflock_win_unlock(fd, mode) == 0) {')
    lk=$(lno "$body" 'r = _xflock_win_lock(fd, mode, cmd & 2);')
    l0=$(lno "$body" 'if (r == 0) { return 0; }')
    lr=$(lno "$body" '_xflock_win_release(fd)')
    if [ -z "$lp" ] || [ -z "$lk" ] || [ -z "$l0" ] || [ -z "$lr" ]; then
        bad "axis 6: _xflock_win does not probe the handle's mode byte and return 0 when it is held (probe '${lp}', relock '${lk}', return '${l0}', release '${lr}')"
    elif [ "$lp" -lt "$lk" ] && [ "$lk" -lt "$l0" ] && [ "$l0" -lt "$lr" ]; then :
    else
        bad "axis 6: _xflock_win releases the sentinel before its held-mode no-op (probe line $lp, relock $lk, return $l0, first release $lr)"
    fi
    # The mode is recorded only after the sentinel is granted.
    ls=$(lno "$body" '_xflock_win_lock(fd, 0x7FFFFFFFFFFFFFFF, fl);')
    lm=$(lno "$body" '_xflock_win_lock(fd, _xflock_win_mode(cmd), cmd & 2)')
    if [ -z "$ls" ] || [ -z "$lm" ] || [ "$lm" -le "$ls" ]; then
        bad "axis 6: _xflock_win does not record the mode after the sentinel is granted (sentinel line '${ls}', record '${lm}')"
    fi
    # Release: both mode bytes before the sentinel.
    re=$(lno "$rbody" '_xflock_win_unlock(fd, 0x7FFFFFFFFFFFFFFE)')
    rs=$(lno "$rbody" '_xflock_win_unlock(fd, 0x7FFFFFFFFFFFFFFD)')
    rx=$(lno "$rbody" '_xflock_win_unlock(fd, 0x7FFFFFFFFFFFFFFF)')
    if [ -z "$re" ] || [ -z "$rs" ] || [ -z "$rx" ]; then
        bad "axis 6: _xflock_win_release does not unlock both mode bytes and the sentinel"
    elif [ "$re" -lt "$rx" ] && [ "$rs" -lt "$rx" ]; then :
    else
        bad "axis 6: _xflock_win_release drops the sentinel before a mode byte (a new holder would find the old record)"
    fi
    [ "$fail" = "$f6" ] && ok
fi

# axis 5: behaviour under wine.
if ! command -v wine > /dev/null 2>&1; then
    echo "  SKIP: axis 5 (wine absent — the cass cross-OS leg runs xflock_two_handle.tcyr on real Windows)"
else
    # The filed repro, verbatim (issues/archived/2026-10-08-xflock-windows-lockfileex-not-wired.md).
    cat > "$D/fl.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
include "lib/io.cyr"
alloc_init();
var fd = file_open("fl_probe.tmp", O_RDWR | O_CREAT, 420);
var r = xflock(fd, 2);                       # LOCK_EX
syscall(SYS_EXIT, 10 + r + 1);               # Linux 11 (rc 0); Windows 10 (rc -1)
EOF
    mkdir -p "$D/w"
    # Bounded: a lock that deadlocks (a mode record on the sentinel itself locks it twice) fails the
    # axis with exit 124 instead of hanging check.sh. CHANGELOG [6.7.13]
    _wine() {  # $1 = exe name inside $D/w, $2 = stdout capture
        ( cd "$D/w" && ulimit -c 0; LANG=C.UTF-8 WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
            WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' \
            timeout 120 wine "$1" > "$2" 2>&1 )
    }
    ( cd "$ROOT" && CYRIUS_TARGET_WIN=1 "$CC" < "$D/fl.cyr" > "$D/w/fl.exe" 2> "$D/fl.err" )
    if [ ! -s "$D/w/fl.exe" ]; then
        bad "axis 5: the PE build of the filed repro produced no binary: $(grep -m2 '^error' "$D/fl.err" | tr '\n' ' ')"
    else
        frc=0; _wine fl.exe "$D/fl.out" || frc=$?
        if [ "$frc" = 11 ]; then ok
        else bad "axis 5: the filed repro exits $frc under wine (want 11: xflock(fd, LOCK_EX) -> 0; 10 is the old -1)"; fi
    fi
    ( cd "$ROOT" && CYRIUS_TARGET_WIN=1 "$CC" < "$TC" > "$D/w/t.exe" 2> "$D/t.err" )
    if [ ! -s "$D/w/t.exe" ]; then
        bad "axis 5: the PE build of xflock_two_handle.tcyr produced no binary: $(grep -m2 '^error' "$D/t.err" | tr '\n' ' ')"
    else
        wrc=0; _wine t.exe "$D/t.out" || wrc=$?
        sum=$(tr -d '\r' < "$D/t.out" | sed -n 's/^\([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed.*/\1 \2/p' | tail -1)
        np=${sum% *}; nf=${sum#* }
        if [ -z "$sum" ]; then
            bad "axis 5: the PE run under wine printed no summary (exit $wrc)"
        elif [ "$wrc" != 0 ] || [ "$nf" != 0 ]; then
            bad "axis 5: xflock_two_handle.tcyr under wine: $np passed, $nf failed (exit $wrc)"
            grep -m6 'FAIL:' "$D/t.out" | tr -d '\r' | sed 's/^/      /'
        elif [ "$np" -lt 30 ]; then
            bad "axis 5: xflock_two_handle.tcyr under wine ran only $np rows (floor 30)"
        else ok; fi
    fi
    ( cd "$ROOT" && CYRIUS_TARGET_WIN=1 "$CC" < "$TR" > "$D/w/r.exe" 2> "$D/r.err" )
    if [ ! -s "$D/w/r.exe" ]; then
        bad "axis 5: the PE build of xflock_relock_keeps_lock.tcyr produced no binary: $(grep -m2 '^error' "$D/r.err" | tr '\n' ' ')"
    else
        rrc=0; _wine r.exe "$D/r.out" || rrc=$?
        sum=$(tr -d '\r' < "$D/r.out" | sed -n 's/^\([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed.*/\1 \2/p' | tail -1)
        np=${sum% *}; nf=${sum#* }
        if [ -z "$sum" ]; then
            bad "axis 5: the relock .tcyr's PE run under wine printed no summary (exit $rrc)"
        elif [ "$rrc" != 0 ] || [ "$nf" != 0 ]; then
            bad "axis 5: xflock_relock_keeps_lock.tcyr under wine: $np passed, $nf failed (exit $rrc)"
            grep -m6 'FAIL:' "$D/r.out" | tr -d '\r' | sed 's/^/      /'
        elif [ "$np" -lt 50 ]; then
            bad "axis 5: xflock_relock_keeps_lock.tcyr under wine ran only $np rows (floor 50)"
        else ok; fi
    fi
    WINEPREFIX="$WP" wineserver -k > /dev/null 2>&1 || true
fi

echo "$pass passed, $fail failed"
[ "$pass" -ge 7 ] || { echo "FAIL: pe_lockfileex_reroute: only $pass rows ran (floor 7)"; exit 1; }
if [ "$fail" -ne 0 ]; then echo "FAIL: pe_lockfileex_reroute"; exit 1; fi
echo "PASS: pe_lockfileex_reroute — 0xF04C/0xF04D routed at their arity, named, imported; xflock locks a sentinel byte on Windows, two handles contend, and a re-lock to the held mode keeps the lock"

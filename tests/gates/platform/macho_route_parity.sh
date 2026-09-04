#!/bin/sh
# macho_route_parity.sh — v6.5.16
#
# The two Mach-O backends carry INDEPENDENT syscall route tables and NOTHING compared them:
#   * arm64-macOS (ecb)      src/backend/aarch64/emit.cyr, ESYSXLAT's `_TARGET_MACHO == 2` branch
#   * x86_64-macOS (ach)     src/backend/x86/emit.cyr,     EMACHO_SYSXLAT
# A route missing from one is a SIGSYS kill (x86: the number reaches Darwin without the
# 0x2000000 Unix-class prefix) or a stale-x16 garbage call (arm64) on THAT Mac only —
# invisible on the other Mac and invisible on Linux.
#
# ⛔ WHAT THIS GATE EXISTS FOR. Every instance of this has been found by accident, late:
#   v6.5.15  SIGPWR=30 fixed on the arm64 peer, left live on x86 — and Darwin 30 is SIGUSR1,
#            so kill(pid, SIGPWR) delivered the WRONG signal.
#   v6.5.15  sys_fchmod had no EMACHO_SYSXLAT row at all → SIGSYS on every Intel-Mac for as
#            long as the wrapper existed. Surfaced only because a new crossos test CALLED it.
#   v6.5.16  the ENTIRE credential family (getuid/geteuid/getgid/getegid) was unrouted on BOTH
#            backends, hidden because lib/sys.cyr's is_root() hardcoded `return 0` on macOS so
#            the one consumer never invoked the wrapper. A primitive that fails in a way that
#            makes its caller skip is invisible — the original macOS-rot shape.
#   v6.5.16  the whole at-family (openat/mkdirat/newfstatat/unlinkat/renameat/linkat/fchmodat)
#            was routed on arm64 and unrouted on x86; sys_fstat was the mirror image.
# A behavioural test only covers the calls it happens to make. This is the static complement:
# it covers every route, on both backends, at commit time, with no Mac in the loop.
#
# ⚠ DO NOT compare the two tables by SOURCE number — that comparison is meaningless and
# produces ~32 false positives. The peers issue different source numbers BY DESIGN:
# lib/syscalls.cyr resolves x86-macOS to lib/syscalls_macos.cyr (x86-Linux numbering) and
# arm64-macOS to lib/syscalls_aarch64_linux.cyr (aarch64-Linux numbering). `sys_getuid` is
# 102 on one and 174 on the other and both are correct. The comparison that MEANS something
# is by CAPABILITY: for each SYS_* name a wrapper issues, is the number THAT peer emits
# routed on THAT backend?
#
# ⚠ Two parsing traps, both hit while producing the original numbers:
#   * `_TARGET_MACHO == 2` appears in BOTH ESYSCALL (the svc emitter, ~line 422) and ESYSXLAT
#     (~line 616). Anchoring on the string instead of the FUNCTION parsed 0 routes and called
#     it healthy. This script locates `fn ESYSXLAT`, then its branch, and asserts a floor.
#   * `cmp x8,#N` is 0xF1000000 | (N<<10) | (8<<5) | 0x1F. Dropping the Rn/Rd field silently
#     yields plausible-but-wrong numbers. Decoded here with the full mask.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"

ARM=src/backend/aarch64/emit.cyr
X86=src/backend/x86/emit.cyr
PEER_X86=lib/syscalls_macos.cyr
PEER_ARM=lib/syscalls_aarch64_linux.cyr

TMP=${TMPDIR:-/tmp}/macho_parity.$$
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT INT TERM

pass=0; fail=0
ok()   { printf '  ok: %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL: %s\n' "$1"; fail=$((fail + 1)); }

# ---------------------------------------------------------------- allow-list
# EVERY entry carries a one-line reason. An unexplained entry is how this rots again —
# a nameless allow-list is indistinguishable from a missing route.
#
# Scope: x86 | arm | both  (which backend legitimately lacks a route for this capability)
# A capability listed here is exempt from the "unrouted" and "drift" axes on that backend.
allow_reason() {
    case "$1" in
    # ---- no Darwin syscall exists at all: nothing to renumber TO ----
    SYS_ACCEPT4)      echo "both|Darwin has no accept4; lib/net.cyr uses accept(30)+fcntl for the flags" ;;
    SYS_BRK)          echo "both|Darwin has no brk; macOS targets use lib/alloc_macos.cyr (mmap-based)" ;;
    SYS_EPOLL_CREATE1|SYS_EPOLL_CTL|SYS_EPOLL_WAIT)
                      echo "both|Darwin has no epoll; the BSD equivalent is kqueue, a different API not a renumber" ;;
    SYS_FUTEX)        echo "both|Darwin has no futex; macOS sync uses __ulock/pthread, not a renumber" ;;
    SYS_INOTIFY_ADD_WATCH|SYS_INOTIFY_INIT1|SYS_INOTIFY_RM_WATCH)
                      echo "arm|Darwin has no inotify; file events are kqueue/FSEvents, a different API" ;;
    SYS_LANDLOCK_ADD_RULE|SYS_LANDLOCK_CREATE_RULESET|SYS_LANDLOCK_RESTRICT_SELF)
                      echo "both|Landlock is a Linux LSM; Darwin sandboxing is Seatbelt, no syscall peer" ;;
    SYS_SECCOMP)      echo "both|seccomp is Linux-only; no Darwin peer" ;;
    SYS_PIDFD_OPEN)   echo "both|pidfd is Linux-only; no Darwin peer" ;;
    SYS_TIMERFD_CREATE|SYS_TIMERFD_SETTIME)
                      echo "both|Darwin has no timerfd; timers are kqueue EVFILT_TIMER, a different API" ;;
    SYS_SIGNALFD4)    echo "both|Darwin has no signalfd (kqueue EVFILT_SIGNAL). NOTE the arm peer's SYS_SIGNALFD4=74 collides with the fsync row 74->95, so it LOOKS routed; it is not a route for this capability" ;;
    SYS_UTIMENSAT)    echo "both|Darwin has no utimensat; the wrapper returns -ENOSYS on macOS (see the v6.1.20 at-family note)" ;;
    SYS_EXECVEAT)     echo "both|Darwin has no execveat; execve(59) is routed and is what the macOS paths use" ;;
    SYS_MOUNT|SYS_UMOUNT2|SYS_REBOOT)
                      echo "both|admin syscalls with incompatible Darwin ABIs, unreachable from the macOS builds. NOTE the arm peer's SYS_UMOUNT2=39 collides with the x86-getpid row 39->20, so it LOOKS routed" ;;
    SYS_PRCTL)        echo "both|prctl is Linux-only; Darwin has no equivalent syscall" ;;
    SYS_UNAME)        echo "both|Darwin has no uname(2); lib/sys.cyr reads the same fields via sysctl (routed as the private alias 1202->202)" ;;
    SYS_SYSINFO)      echo "arm|Darwin has no sysinfo(2); lib/sys.cyr derives it from sysctl + gettimeofday (1202/1116, both routed)" ;;
    SYS_PAUSE)        echo "x86|Darwin has no pause(2); the x86 peer declares it but no wrapper reaches it on macOS" ;;
    SYS_PPOLL)        echo "arm|Darwin has no ppoll(2); the only caller is sys_pause (Linux-only, blocks for a signal), and a bare renumber to poll(230) would be WRONG — our call passes timeout 0, so poll returns immediately instead of blocking. ⛔ Until v6.5.36 the arm peer spelled this 73, which COLLIDED with the flock row 73->131 and so LOOKED routed while silently issuing flock; it is now the private alias 1073, honestly unrouted here. Same shape as the SYS_SIGNALFD4 note above, and on ELF-aarch64 that same collision was a live Critical" ;;
    # ---- a real Darwin call exists but a bare renumber would be WRONG ----
    SYS_RT_SIGPROCMASK)
                      echo "both|Darwin sigprocmask(48) is not a renumber of Linux rt_sigprocmask: Linux takes a 4th sigsetsize arg and a 64-bit sigset_t, Darwin a 32-bit one. Needs a shim, not a row" ;;
    SYS_SETRESUID|SYS_SETRESGID)
                      echo "both|Darwin has no setresuid/setresgid; the closest peers (setreuid/setregid) have different semantics, so a row would silently change behaviour" ;;
    # ---- same capability, different spelling: routed under the OTHER name ----
    SYS_CLONE)        echo "x86|the x86 peer implements sys_fork via bare SYS_FORK=57 (routed ->2); only the arm peer spells fork as clone(220). Same capability" ;;
    *) echo "" ;;
    esac
}
allow_scope()  { allow_reason "$1" | cut -d'|' -f1; }
allow_why()    { allow_reason "$1" | cut -d'|' -f2- ; }

# ---------------------------------------------------------------- parse: arm64 routes
# Anchor on the FUNCTION, then its macho branch, then decode the instruction words.
FN_START=$(awk '/^fn ESYSXLAT\(S\): i64 \{/{print NR; exit}' "$ARM")
[ -n "$FN_START" ] || { echo "  FAIL: could not locate 'fn ESYSXLAT' in $ARM"; exit 1; }
FN_END=$(awk -v s="$FN_START" 'NR>s && /^\}/{print NR; exit}' "$ARM")
BR_START=$(awk -v s="$FN_START" -v e="$FN_END" 'NR>=s&&NR<=e&&/if \(_TARGET_MACHO == 2\) \{/{print NR; exit}' "$ARM")
[ -n "$BR_START" ] || { echo "  FAIL: no _TARGET_MACHO==2 branch inside ESYSXLAT"; exit 1; }
BR_END=$(awk -v s="$BR_START" -v e="$FN_END" 'NR>s&&NR<=e&&/^        return 0;/{print NR; exit}' "$ARM")

# v6.5.48: read the rows as SOURCE, not as decoded machine words. ESYSXLAT's Mach-O branch used
# to spell every row as three literal EW() words, so this gate carried its own aarch64 instruction
# decoder — and its header still records the trap that decoder set (dropping the Rn/Rd field
# yields plausible-but-wrong numbers). v6.5.48 replaced those 90 hand-derived triples with a
# computed emitter, `_esx_arm(S, src, dst)`, so the numbers are now legible directly and the
# decoder is gone. Strictly less to get wrong on both sides.
sed -n "${BR_START},${BR_END}p" "$ARM" \
  | grep -oE '_esx_arm(_shift)?\(S, *[0-9]+, *[0-9]+' \
  | sed -E 's/_esx_arm(_shift)?\(S, *([0-9]+), *([0-9]+)/\2 \3/' \
  | sort -n -u > "$TMP/arm_routes"
# ⚠ BOTH FORMS. `_esx_arm_shift` is the at-family rows that renumber AND drop an argument
# (openat 56 -> open 5, mkdirat 34 -> mkdir 136, fchmodat 53 -> chmod 15). Reading only the
# plain form loses exactly those three and reports them as unrouted DRIFT — measured on this
# gate's first run after the v6.5.48 consolidation.

# ---------------------------------------------------------------- parse: x86 routes
awk '/^fn EMACHO_SYSXLAT\(S\): i64 \{/{s=1} s&&/^\}/{exit} s' "$X86" \
  | grep -oE '_msx(32)?\(S,[[:space:]]*[0-9]+,[[:space:]]*0x[0-9A-Fa-f]+\)' \
  | sed -E 's/.*S,[[:space:]]*([0-9]+),[[:space:]]*0x([0-9A-Fa-f]+)\)/\1 \2/' \
  | awk '
    function h2d(s,   i,c,v,d){ v=0; s=toupper(s);
      for(i=1;i<=length(s);i++){ c=substr(s,i,1); d=index("0123456789ABCDEF",c)-1; v=v*16+d } return v }
    { printf "%s %d\n", $1, h2d($2) - 33554432 }' | sort -n -u > "$TMP/x86_routes"

NARM=$(wc -l < "$TMP/arm_routes" | tr -d ' ')
NX86=$(wc -l < "$TMP/x86_routes" | tr -d ' ')
echo "route tables parsed: aarch64-macho = $NARM   x86-macho = $NX86"

# Corpus floor. A parse that silently returns 0 (or a handful) must fail LOUDLY rather than
# pass vacuously — the exact failure mode that made a first attempt at these numbers report
# "0 routes" for the arm64 side and look healthy.
if [ "$NARM" -ge 60 ]; then ok "aarch64 macho route parse produced $NARM routes (floor 60)"
else bad "aarch64 macho route parse produced only $NARM routes — parser is broken, not the table"; fi
if [ "$NX86" -ge 45 ]; then ok "x86 macho route parse produced $NX86 routes (floor 45)"
else bad "x86 macho route parse produced only $NX86 routes — parser is broken, not the table"; fi

# Every x86 route must carry the 0x2000000 Unix class prefix. Without it the number reaches
# Darwin unclassed and the process dies with SIGSYS — the exact v6.5.15 fchmod bug.
unclassed=$(awk '/^fn EMACHO_SYSXLAT\(S\): i64 \{/{s=1} s&&/^\}/{exit} s' "$X86" \
  | grep -cE '_msx(32)?\(S,[[:space:]]*[0-9]+,[[:space:]]*0x[0-9A-Fa-f]+\)' \
  | tr -d ' ' || true)
badpfx=$(awk '{ if ($2 < 1 || $2 > 4095) print }' "$TMP/x86_routes" | wc -l | tr -d ' ')
if [ "$badpfx" -eq 0 ]; then ok "all $unclassed x86 rows carry the 0x2000000 class prefix (BSD target in range)"
else bad "$badpfx x86 row(s) decode to an out-of-range BSD number — missing/!wrong 0x2000000 prefix"; fi

# ---------------------------------------------------------------- parse: peer constants
grep -oE 'SYS_[A-Z0-9_]+ = [0-9]+;' "$PEER_X86" | sed 's/ = / /; s/;//' | sort -u > "$TMP/peer_x86"
grep -oE 'SYS_[A-Z0-9_]+ = [0-9]+;' "$PEER_ARM" | sed 's/ = / /; s/;//' | sort -u > "$TMP/peer_arm"
# Names a wrapper actually ISSUES. A constant nobody calls cannot break anything.
grep -ohE 'syscall\(SYS_[A-Z0-9_]+' lib/*.cyr | sed 's/syscall(//' | sort -u > "$TMP/issued"

routed() { awk -v n="$2" '$1==n{f=1} END{exit !f}' "$1"; }

# ---------------------------------------------------------------- axis 1: per-backend coverage
# For each SYS_* a wrapper issues, is the number THAT peer emits routed on THAT backend?
# This is the axis that catches getuid (unrouted on both) and the at-family (x86 only).
echo ""
echo "axis 1 — every issued SYS_* is routed on its own backend (or allow-listed with a reason):"
a1f=0
while read -r name; do
    xn=$(awk -v n="$name" '$1==n{print $2; exit}' "$TMP/peer_x86")
    an=$(awk -v n="$name" '$1==n{print $2; exit}' "$TMP/peer_arm")
    scope=$(allow_scope "$name")
    if [ -n "$xn" ] && ! routed "$TMP/x86_routes" "$xn"; then
        if [ "$scope" = "x86" ] || [ "$scope" = "both" ]; then :
        else printf '  FAIL: %s (x86-macOS num %s) is issued but UNROUTED in EMACHO_SYSXLAT\n' "$name" "$xn"; a1f=$((a1f+1)); fi
    fi
    if [ -n "$an" ] && ! routed "$TMP/arm_routes" "$an"; then
        if [ "$scope" = "arm" ] || [ "$scope" = "both" ]; then :
        else printf '  FAIL: %s (arm64-macOS num %s) is issued but UNROUTED in ESYSXLAT\n' "$name" "$an"; a1f=$((a1f+1)); fi
    fi
done < "$TMP/issued"
if [ "$a1f" -eq 0 ]; then ok "no issued syscall is unrouted on either Mach-O backend"
else fail=$((fail + a1f)); fi

# ---------------------------------------------------------------- axis 2: capability drift
# Routed on exactly ONE backend => the capability is reachable on one Mac and not the other.
# This is the axis the v6.5.15 fchmod bug would have tripped.
echo ""
echo "axis 2 — no capability is reachable on one Mach-O backend but not the other:"
a2f=0
while read -r name; do
    xn=$(awk -v n="$name" '$1==n{print $2; exit}' "$TMP/peer_x86")
    an=$(awk -v n="$name" '$1==n{print $2; exit}' "$TMP/peer_arm")
    [ -n "$xn" ] || continue
    [ -n "$an" ] || continue
    rx=no; ra=no
    routed "$TMP/x86_routes" "$xn" && rx=yes
    routed "$TMP/arm_routes" "$an" && ra=yes
    [ "$rx" = "$ra" ] && continue
    if [ -n "$(allow_scope "$name")" ]; then continue; fi
    printf '  FAIL: %s routed on x86=%s arm=%s (x86 num %s, arm num %s) — DRIFT\n' "$name" "$rx" "$ra" "$xn" "$an"
    a2f=$((a2f+1))
done < "$TMP/issued"
if [ "$a2f" -eq 0 ]; then ok "no capability drift between the two Mach-O route tables"
else fail=$((fail + a2f)); fi

# ---------------------------------------------------------------- axis 3: registration drift
# _macho_arm_routes is the SINGLE SOURCE OF TRUTH parse_expr.cyr queries for the
# "syscall not routed" warning. It is a hand-maintained mirror of the ESYSXLAT sources, so it
# drifts silently in BOTH directions: a missing row makes a WORKING call warn (7 socket numbers
# did exactly that from v6.2.24 until v6.5.16 — and a warning that cries wolf is how a real one
# gets ignored), and a stale row suppresses the warning for a route that no longer exists.
echo ""
echo "axis 3 — _macho_arm_routes is DERIVED from ESYSXLAT, not mirrored:"
# ⛔ v6.5.48 — THIS AXIS USED TO COMPARE TWO LISTS. `_macho_arm_routes` was a hand-maintained
# 95-entry duplicate of every source number in the branch above, and it drifted in BOTH
# directions: a missing row made a WORKING call warn "syscall not routed" (seven socket numbers
# did exactly that from v6.2.24 to v6.5.16), and a stale row suppressed the warning for a route
# that no longer existed. This axis existed to catch that drift.
# It now replays ESYSXLAT in query mode — the same fix `_macho_x86_routes` got at v6.5.43 — so
# the drift is impossible BY CONSTRUCTION and there is no list to compare. What must be checked
# instead is that the derivation is real: a future edit that quietly re-introduces literals would
# restore the whole failure mode.
DERIV=$(awk '/^fn _macho_arm_routes\(n\): i64 \{/{s=1} s&&/^\}/{exit} s' "$ARM")
printf '%s' "$DERIV" | grep -q 'ESYSXLAT(' \
  || bad "_macho_arm_routes does not replay ESYSXLAT — it is a hand-mirrored list again, which is the v6.0.65 and v6.5.16 defect both at once"
printf '%s' "$DERIV" | grep -q '_esx_qon' \
  || bad "_macho_arm_routes does not use the query mode, so its replay would EMIT into the code stream"
# The only literals permitted are the __got reroutes parse_expr handles before ESYSXLAT sees them.
ALITS=$(printf '%s' "$DERIV" | grep -oE 'n == [0-9]+' | grep -oE '[0-9]+' | sort -n -u | tr '\n' ' ')
if [ "$ALITS" = "228 1700 " ]; then ok "_macho_arm_routes derives from ESYSXLAT; only the two __got reroutes are literal"
else bad "unexpected literal route list in _macho_arm_routes: '$ALITS' (expected exactly the two __got reroutes '228 1700 ')"; fi

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
echo "PASS: Mach-O route tables agree by capability on both backends"

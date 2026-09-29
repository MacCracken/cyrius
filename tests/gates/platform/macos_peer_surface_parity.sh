#!/bin/sh
# macos_peer_surface_parity.sh — 6.6.10. The two macOS syscall surfaces declare the same names.
#
# lib/syscalls.cyr resolves a DIFFERENT peer per Mac: arm64-macOS gets the aarch64-LINUX peer
# (lib/syscalls_aarch64_linux.cyr, #ifdef'd for Darwin where it must be) and x86-macOS gets
# lib/syscalls_macos.cyr. Nothing compared their SURFACES — macho_route_parity.sh compares route
# tables, not which fns and constants exist — so the same portable source compiled on Apple
# Silicon and failed on Intel-Mac. Measured at 6.6.10's premise check: the x86 peer lacked ten
# fns (sys_epoll_wait, the three sys_inotify_*, sigset_new/add/has, epoll_event_new,
# timerspec_new, timerfd_drain), the InotifyEvent and MsFlag enums and seven SYS_* names, so
# `sys_inotify_add_watch(fd, p, IN_MODIFY)` failed with "undefined variable 'IN_MODIFY'" and
# "reachable undefined function(s)" on ach and built on ecb. 6.6.8 had added the -ENOSYS
# declines to the arm peer only — the drift this gate stops.
#
# AXES
#   A  every fn, enum and enum member the arm peer declares OUTSIDE its CYRIUS_TARGET_LINUX-only
#      blocks (i.e. on the arm64-macOS surface) is declared by the x86-macOS peer too, or is
#      allow-listed below with a reason. Both peers include lib/syscalls_linux_common.cyr, so
#      its names are shared by construction and not compared. A floor on each side's count, so
#      a parse that silently returns nothing FAILS instead of passing vacuously.
#   B  an x86-macOS build that calls the parity fns and names the parity constants COMPILES and
#      is WARNING-FREE — a wolf-cry in every Intel-Mac build that includes lib/syscalls.cyr is
#      how a real warning gets scrolled past. (The 6.6.10 sys_kill fix passes Darwin's third
#      `posix` argument; it needs the compiler's structural arity skip for 3-arg kill, or this
#      axis reports "syscall arity mismatch" on every such build.)
#
# ⚠ STATIC + COMPILE ONLY. Whether the wrappers RUN correctly is
# tests/tcyr/crossos/darwin_unrouted_syscall_faults.tcyr on real ach and ecb.
#
# MUTATION LEDGER (each applied to a scratch copy passed as PEER_X86 / PEER_ARM — axis A reads
# those, axis B always compiles against the tree's lib/ — gate re-run, then discarded):
#   1. delete `fn sys_inotify_rm_watch` from the x86-macOS peer -> FAIL axis A naming
#      "fn sys_inotify_rm_watch"
#   2. delete `enum MsFlag` from the x86-macOS peer             -> FAIL axis A on the enum and
#      its seven members
#   3. delete `SYS_SYSINFO = 99;` from the x86-macOS peer       -> FAIL axis A (const SYS_SYSINFO)
#   4. add `fn sys_newthing(): i64 { return 0 - 78; }` to the arm peer -> FAIL axis A naming it
#   5. CYCC = a 6.6.9 cycc (no 3-arg kill arity skip)            -> FAIL axis B: the probe build
#      prints "syscall arity mismatch" from lib/syscalls_linux_common.cyr
#   6. PEER_ARM = a missing file                                 -> FAIL: missing, the floor, and
#      every allow-list entry reported stale
#   7. (in the tree) revert lib/syscalls_macos.cyr to 6.6.9      -> FAIL axis A (ten fns, two
#      enums, thirteen members) AND axis B ("undefined variable 'IN_MODIFY'", rc 1)
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
CC=${CYCC:-"$ROOT/build/cycc"}
ARM=${PEER_ARM:-lib/syscalls_aarch64_linux.cyr}
X86=${PEER_X86:-lib/syscalls_macos.cyr}

TMP=$(mktemp -d) && [ -d "$TMP" ] || { echo "FAIL: macos_peer_surface_parity: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$TMP"' EXIT INT TERM

pass=0; fail=0
ok()  { printf '  ok: %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL: %s\n' "$1"; fail=$((fail + 1)); }

# Names the arm peer legitimately has and the x86 peer does not. EVERY entry carries a reason:
# a nameless allow-list is indistinguishable from the drift this gate exists to catch.
allow_reason() {
    case "$1" in
    "const SYS_EPOLL_PWAIT"|"const SYS_PIPE2"|"const SYS_PPOLL"|"const SYS_READLINKAT"|"const SYS_SYMLINKAT")
        echo "an aarch64-Linux-only SPELLING: aarch64 dropped epoll_wait/pipe/poll/readlink/symlink for these, and the x86_64 Linux peer does not declare them either, so no portable source names them (the x86 peers spell the same capability SYS_EPOLL_WAIT/SYS_PIPE/…)" ;;
    "enum ErrnoOs")
        echo "the arm peer splits its one Darwin-valued errno (EAGAIN = 35 on macOS, 11 on Linux) into a per-target enum; the x86-macOS peer declares the same EAGAIN = 35 inside its Errno enum, so the MEMBER is on both surfaces and only the enum's name differs" ;;
    *) echo "" ;;
    esac
}

# Emit "fn NAME", "enum NAME" and "const NAME" for everything a peer declares on the macOS
# surface. Lines inside a column-0 `#ifdef CYRIUS_TARGET_LINUX` block are not on it; nested
# column-0 #ifdef/#ifndef/#endif are depth-tracked so the block ends where it really ends.
surface() {
    awk '
    BEGIN { skip = 0; depth = 0; inenum = 0 }
    /^#ifdef CYRIUS_TARGET_LINUX/ { if (skip == 0) { skip = 1; sd = depth }; depth++; next }
    /^#ifn?def / { depth++; next }
    /^#endif/ { depth--; if (skip && depth == sd) skip = 0; next }
    skip { next }
    /^fn [A-Za-z_][A-Za-z0-9_]*\(/ { n = $2; sub(/\(.*/, "", n); print "fn " n; next }
    /^enum [A-Za-z_][A-Za-z0-9_]* *\{/ {
        print "enum " $2
        if ($0 ~ /\}/) { m = $0; sub(/.*\{/, "", m); sub(/\}.*/, "", m); gsub(/ /, "", m); split(m, a, "="); print "const " a[1] }
        else inenum = 1
        next
    }
    inenum && /^\}/ { inenum = 0; next }
    inenum && /^[ \t]+[A-Z_][A-Z0-9_]* *=/ { print "const " $1; next }
    ' "$1" | sort -u
}

echo "axis A — every name on the arm64-macOS surface is on the x86-macOS surface:"
[ -f "$ARM" ] || { bad "arm peer $ARM is missing"; }
[ -f "$X86" ] || { bad "x86-macOS peer $X86 is missing"; }
surface "$ARM" > "$TMP/arm" 2>/dev/null || true
surface "$X86" > "$TMP/x86" 2>/dev/null || true
NA=$(wc -l < "$TMP/arm" | tr -d ' '); NX=$(wc -l < "$TMP/x86" | tr -d ' ')
NAF=$(grep -c '^fn ' "$TMP/arm" || true); NXF=$(grep -c '^fn ' "$TMP/x86" || true)
if [ "$NA" -ge 200 ] && [ "$NAF" -ge 30 ]; then ok "arm surface parsed: $NA names, $NAF fns (floors 200 / 30)"
else bad "arm surface parse produced only $NA names / $NAF fns — the parser is broken, not the peer"; fi
if [ "$NX" -ge 200 ] && [ "$NXF" -ge 30 ]; then ok "x86-macOS surface parsed: $NX names, $NXF fns (floors 200 / 30)"
else bad "x86-macOS surface parse produced only $NX names / $NXF fns — the parser is broken, not the peer"; fi
missing=0; allowed=0
comm -23 "$TMP/arm" "$TMP/x86" > "$TMP/only_arm"
while IFS= read -r name; do
    why=$(allow_reason "$name")
    if [ -n "$why" ]; then allowed=$((allowed + 1)); continue; fi
    printf '  FAIL: %s is declared on arm64-macOS (%s) but not on x86-macOS (%s)\n' "$name" "$ARM" "$X86"
    missing=$((missing + 1))
done < "$TMP/only_arm"
if [ "$missing" -eq 0 ]; then ok "no arm64-macOS name is missing from x86-macOS ($allowed allow-listed with a reason)"
else fail=$((fail + missing)); fi
# An allow-list entry that no longer matches anything is stale: it would silently excuse a
# FUTURE drift under the same name. Report it.
for n in "const SYS_EPOLL_PWAIT" "const SYS_PIPE2" "const SYS_PPOLL" "const SYS_READLINKAT" "const SYS_SYMLINKAT" "enum ErrnoOs"; do
    grep -qxF "$n" "$TMP/only_arm" || bad "allow-list entry '$n' matches no arm-only name — remove it"
done

echo ""
echo "axis B — an x86-macOS build using the parity surface compiles, warning-free:"
cat > "$TMP/probe.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 {
    var evs[64];
    var t = 0;
    t = t + sys_epoll_wait(0, &evs, 1, 0) + sys_inotify_init();
    t = t + sys_inotify_add_watch(0, ".", IN_MODIFY | IN_CREATE) + sys_inotify_rm_watch(0, 1);
    var ss = sigset_new();
    sigset_add(ss, 15);
    t = t + sigset_has(ss, 15) + epoll_event_new(EPOLLIN, 1) + timerspec_new(1, 2) + timerfd_drain(0 - 1);
    t = t + MS_BIND + MS_RDONLY + SYS_FLOCK + SYS_DUP3 + SYS_FACCESSAT + SYS_SYSINFO + SYS_INOTIFY_INIT1;
    t = t + sys_getdents64(0 - 1, &evs, 64) + sys_kill(0 - 1, 0) + sys_getrandom(&evs, 8, 0);
    return t & 0;
}
var r = main();
syscall(60, r);
EOF
set +e
CYRIUS_MACHO=1 "$CC" < "$TMP/probe.cyr" > "$TMP/probe.bin" 2> "$TMP/probe.err"
rc=$?
set -e
if [ "$rc" -eq 0 ] && [ -s "$TMP/probe.bin" ]; then ok "CYRIUS_MACHO=1 build of the parity probe: rc 0, $(wc -c < "$TMP/probe.bin" | tr -d ' ') bytes"
else bad "CYRIUS_MACHO=1 build of the parity probe failed (rc $rc): $(grep -v '^note' "$TMP/probe.err" | head -3 | tr '\n' ' ')"; fi
nw=$(grep -c '^warning' "$TMP/probe.err" || true)
if [ "$nw" -eq 0 ]; then ok "the x86-macOS build printed no warning"
else bad "the x86-macOS build printed $nw warning(s): $(grep -A1 '^warning' "$TMP/probe.err" | head -4 | tr '\n' ' ')"; fi

echo ""
echo "$pass passed, $fail failed"
if [ "$fail" -ne 0 ]; then echo "FAIL: macos_peer_surface_parity"; exit 1; fi
echo "PASS: macos_peer_surface_parity — the two macOS peers declare one surface"

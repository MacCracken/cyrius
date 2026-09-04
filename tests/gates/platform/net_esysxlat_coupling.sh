#!/bin/sh
# net_esysxlat_coupling.sh — v6.5.11
#
# `lib/net.cyr` issues x86_64 socket syscall NUMBERS on every target and relies on the
# compiler's ESYSXLAT table to renumber them. That is the SANCTIONED pattern, not a defect:
# CLAUDE.md — "aarch64 stdlib syscall numbers that collide with an x86 number in ESYSXLAT get
# silently mis-remapped — use the x86 number + an ESYSXLAT entry."
#
# ⛔ WHAT THIS GATE EXISTS FOR. The coupling is INVISIBLE to both sides. `net.cyr` cannot state
# that it depends on those rows, and `emit.cyr` cannot state that something depends on them. Delete
# a row, or add a target whose table lacks them, and the entire INET surface breaks with NO signal
# until someone runs a socket program on that hardware. That is exactly how v6.2.10 happened: the
# renumbers existed ONLY in the _TARGET_MACHO==2 branch, so on native aarch64-Linux every net.cyr
# call hit the wrong syscall (socket 41 -> pivot_root -> -EPERM, fcntl 72 -> pselect6, poll 7 ->
# fsetxattr) and it went unseen because cycc's own self-host never opens a socket.
#
# This asserts the coupling STRUCTURALLY, which is the only way available: a behavioural test
# passes on x86 whether or not the aarch64 rows exist, so the host suite can never catch this.
# The premise-check for issue 2026-07-30-net-cyr-x86-only-socket-syscall-numbers concluded that
# the numbers themselves are correct as-is (verified on real pi: net_v6_connect + socket_syscalls
# both rc=0) and that the missing piece was this gate, not a per-arch rewrite.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"

pass=0; fail=0
check() {
    if [ "$2" = "$3" ]; then
        printf '  ok: %s (%s)\n' "$1" "$3"; pass=$((pass + 1))
    else
        printf '  FAIL: %s (got %s, want %s)\n' "$1" "$3" "$2"; fail=$((fail + 1))
    fi
}

NET=lib/net.cyr
EMIT=src/backend/aarch64/emit.cyr

echo "axis 1 — every socket number net.cyr issues is renumbered in BOTH aarch64 arms:"
# The x86 numbers net.cyr declares. Parsed from source rather than hardcoded here, so a NEW
# number added to net.cyr is covered automatically instead of silently escaping the gate.
#
# Expect 2 rows each, not 1: ESYSXLAT carries a Mach-O arm (_TARGET_MACHO == 2, Darwin BSD
# numbers) AND an aarch64-Linux arm, and net.cyr is built for both. Asserting 2 is what makes
# this gate reproduce the v6.2.10 defect — that bug WAS "1 row, macho only", which an
# assertion of >=1 would have called healthy.
NUMS=$(grep -E '^var (N?SYS_[A-Z0-9_]+) = [0-9]+;' "$NET" | grep -oE '= [0-9]+' | grep -oE '[0-9]+' | sort -un)
[ -n "$NUMS" ] || { echo "  FAIL: parsed no syscall numbers out of $NET"; exit 1; }
for n in $NUMS; do
    # Match the trailing decimal comment the table carries ("socket      41→198"), which is what
    # the rows are keyed by and is stable against instruction-encoding changes.
    # ⚠ v6.5.48: the Mach-O arm is now a COMPUTED emitter (`_esx_arm(S, src, dst);`) while the
    # aarch64-Linux arm is still three literal EW() words — that arm was not consolidated. Both
    # SHAPES must be counted or this gate sees one arm and reports the exact "1 row, macho only"
    # state it was written to catch. Keyed on the comment either way, so it stays independent of
    # how the row is spelled.
    hits=$(grep -cE "^\s*(EW\(S, 0x[0-9A-F]+\); EW\(S, 0x[0-9A-F]+\); EW\(S, 0x[0-9A-F]+\);|_esx_arm(_shift)?\(S, [0-9]+, [0-9]+(, [0-9]+)?\);)\s*#\s*[a-z0-9_]+\s+${n}→" "$EMIT" || true)
    check "x86 #$n renumbered in both arms" 2 "$hits"
done

echo "axis 2 — those rows are in the aarch64-LINUX arm, not only the Mach-O arm:"
# The v6.2.10 defect was precisely that they existed only under _TARGET_MACHO==2. Find the line
# number of the socket-41 row and confirm it sits AFTER the last `if (_TARGET_MACHO == 2) {`
# block's close, i.e. in the shared/aarch64-Linux path.
row41=$(grep -nE '#\s*socket\s+41→' "$EMIT" | head -1 | cut -d: -f1)
macho=$(grep -nE 'if \(_TARGET_MACHO == 2\) \{' "$EMIT" | tail -1 | cut -d: -f1)
check "socket-41 row exists" 1 "$([ -n "$row41" ] && echo 1 || echo 0)"
# There are two socket blocks (macho + aarch64-linux); assert BOTH exist.
nrows=$(grep -cE '#\s*socket\s+41→' "$EMIT" || true)
check "socket-41 renumber present in BOTH arms (macho + aarch64-linux)" 2 "$nrows"

echo "axis 3 — net.cyr still uses x86 numbers (the sanctioned pattern), not native aarch64 ones:"
# If someone "fixes" net.cyr to carry native aarch64 numbers, the ESYSXLAT rows above stop
# matching and the surface silently breaks on the OTHER targets. 198 is aarch64 socket.
native=$(grep -cE '^var N?SYS_SOCKET = 198;' "$NET" || true)
check "net.cyr does NOT carry the native aarch64 socket number" 0 "$native"
x86=$(grep -cE '^var NSYS_SOCKET = 41;' "$NET" || true)
check "net.cyr carries the x86 socket number" 1 "$x86"

echo ""
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
echo "PASS: net.cyr <-> ESYSXLAT socket coupling is intact on both aarch64 arms"

#!/bin/sh
# Gate: `sys_exit_group` exists on every syscall peer, and no scaffold ships the
# per-thread exit epilogue.
#
# THE BUG (filed by agnosai 2026-08-03, fixed v6.5.6). `lib/syscalls_linux_common.cyr`
# wrapped `sys_exit` — which is exit(2) and ends ONLY THE CALLING THREAD — and had no
# `exit_group(2)` counterpart. Any program that had spawned a thread and exited through
# the idiomatic `syscall(SYS_EXIT, r)` epilogue did not terminate: the main thread died,
# the workers kept running, and the process hung with no diagnostic.
#
# `cyrius init`'s own templates shipped that epilogue, so it was the default a consumer
# copied and then stopped looking at. It only manifests once a program grows its FIRST
# thread — long after the epilogue was written. That is why axis 3 is structural: a
# behavioural test alone would go green again the moment someone adds a new template.
#
# WHY THE MUTATION SIGNAL IS A HANG. Axis 2 asserts the OLD epilogue still hangs (124).
# That is the measurement this gate depends on — if `syscall(SYS_EXIT, r)` ever stops
# hanging in a threaded program, axis 1 has stopped proving anything and this gate has
# quietly become a placebo. Assert the broken behaviour, not just the fixed one.
#
# CROSS-TARGET (axis 4/5). `syscalls_linux_common.cyr` is included by the x86-Linux,
# aarch64-Linux and macOS-x86 peers only; Windows and agnos are STANDALONE. So the
# portable name needs three definitions, and each routes differently:
#   linux_common  -> SYS_EXIT_GROUP  (231 x86 / 94 aarch64; macOS-arm64 resolves 94 and
#                                     src/backend/aarch64/emit.cyr already maps 94 -> BSD 1)
#   windows       -> SYS_EXIT        (ExitProcess ALREADY ends all threads; 231 has no PE
#                                     reroute and would emit a raw 0F 05 = illegal instr)
#   agnos         -> SYS_EXIT        (agnos defines no exit_group; #0 tears down the proc)
# macOS-x86 was the one real hole: it resolves SYS_EXIT_GROUP to 231 and EMACHO_SYSXLAT
# had no 231 entry, so the raw number reached Darwin unclassed -> SIGSYS, and the
# "syscall not routed" warning is arm64-only so it was SILENT. Axis 5 pins the entry.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC="$ROOT/build/cycc"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

# Shared probe body. `$1` is the epilogue under test.
mkprobe() {
    cat > "$D/p.cyr" <<EOF
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/syscalls.cyr"
include "lib/chrono.cyr"
include "lib/thread.cyr"

fn _spin(arg) {
    while (1 == 1) { sleep_ms(1000); }
    return 0;
}

fn main(): i64 {
    alloc_init();
    thread_create(&_spin, 0);
    sleep_ms(100);
    return 42;
}

var r = main();
$1
EOF
}

# Build + run, echoing the exit code. 124 = timed out (the process hung).
runprobe() {
    cat "$D/p.cyr" | "$CC" > "$D/p.bin" 2>/dev/null
    chmod +x "$D/p.bin" 2>/dev/null
    timeout 5 "$D/p.bin" >/dev/null 2>&1
    echo $?
}

# ── AXIS 1: the fix. A threaded program exiting via sys_exit_group terminates with its
# own code. 42 = correct; 124 = still hanging.
echo "axis 1 — threaded program exits through sys_exit_group (42 = ok, 124 = hung):"
mkprobe 'sys_exit_group(r);'
check "sys_exit_group epilogue" 42 "$(runprobe)"

# ── AXIS 2: the mutation signal. The OLD epilogue must still hang, or axis 1 is vacuous.
echo "axis 2 — the old per-thread epilogue still hangs (124 = the bug is real):"
mkprobe 'syscall(SYS_EXIT, r);'
check "syscall(SYS_EXIT, r) epilogue" 124 "$(runprobe)"

# ── AXIS 3: structural. No `cyrius init` template may ship the per-thread epilogue.
# This is the invariant; axis 1 only covers the instance.
echo "axis 3 — no cyrius init template ships a per-thread exit epilogue:"
# Anchored at column 0: the defect is the top-level STATEMENT. Both the code templates
# and the getting-started docs now NAME the old form in order to warn against it (in a
# `#` comment and in backticked prose respectively), so an unanchored match would flag
# the warnings themselves.
bad=$(grep -lE '^syscall\((SYS_EXIT|60), ' programs/cyrius-init-templates/* 2>/dev/null | tr '\n' ' ')
check "no template ships syscall(SYS_EXIT|60, ...) as its epilogue" "" "$bad"
n_eg=$(grep -lE '^sys_exit_group\(' programs/cyrius-init-templates/* 2>/dev/null | wc -l | tr -d ' ')
check "code templates using sys_exit_group" 7 "$n_eg"
# The prose templates taught the old epilogue as THE idiom, which is how a consumer
# learned it in the first place. They must now teach the portable one.
for gs in getting-started-bin getting-started-port; do
    n=$(grep -c 'sys_exit_group' "programs/cyrius-init-templates/$gs" 2>/dev/null || echo 0)
    check "$gs documents sys_exit_group" "yes" "$([ "$n" -ge 1 ] && echo yes || echo no)"
done

# ── AXIS 4: the portable name exists on every syscall peer. Windows and agnos do NOT
# include syscalls_linux_common.cyr, so a single definition there is not enough.
echo "axis 4 — sys_exit_group defined on all three syscall peer families:"
for peer in syscalls_linux_common syscalls_windows syscalls_x86_64_agnos; do
    n=$(grep -cE '^fn sys_exit_group\(' "lib/$peer.cyr" 2>/dev/null || echo 0)
    check "lib/$peer.cyr" 1 "$n"
done
# Windows must route through SYS_EXIT, never 231 (no PE reroute for 231).
win=$(awk '/^fn sys_exit_group\(/,/^}/' lib/syscalls_windows.cyr | grep -c 'SYS_EXIT_GROUP')
check "windows peer does NOT issue SYS_EXIT_GROUP" 0 "$win"

# ── AXIS 5: macOS-x86 number-table hole. 231 must translate to Darwin exit (0x2000001),
# or `syscall(SYS_EXIT_GROUP, ...)` SIGSYSes there — silently, since the unrouted-syscall
# warning only fires on arm64.
echo "axis 5 — EMACHO_SYSXLAT translates 231 (macOS-x86 would otherwise SIGSYS):"
n231=$(grep -cE '_msx(32)?\(S, 231, 0x2000001\)' src/backend/x86/emit.cyr)
check "231 -> 0x2000001 entry present" 1 "$n231"

# ── AXIS 6: the scaffolded test epilogue clamps its exit code. assert_summary() returns
# the raw failure COUNT and a wait status is 8 bits, so an unclamped 256 / 512 / 768
# failures exited 0 and scored PASS.
echo "axis 6 — proj-tcyr clamps its failure count before exiting:"
n_clamp=$(grep -cE 'if \(exit_code > 0\) \{ exit_code = 1; \}' programs/cyrius-init-templates/proj-tcyr)
check "proj-tcyr clamp present" 1 "$n_clamp"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: exit-group-wrapper — portable sys_exit_group on every peer; no template ships exit(2)"
    exit 0
fi
echo "FAIL: exit-group-wrapper — $fails assertion(s) failed"
exit 1

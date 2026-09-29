#!/bin/sh
# agnos_proc_kill_tree_refused.sh — 6.6.10. lib/process_agnos.cyr's `proc_kill_tree` still ends
# the child when the kernel REFUSES the tree kill, before it waits for it.
#
# THE BUG. The agnos peer (new in 6.6.10) was `sys_kill_tree(pid, 9); _agp_wait(pid)`. kill#16
# with the tree bit answers -1 on a pre-1.57.7 kernel (lib/syscalls_x86_64_agnos.cyr: the bit
# itself is refused) or when the authority check fails, and then NOTHING had signalled the child
# — so `_agp_wait`, a WAIT_BLOCK, blocked until the child ended by itself: a kill helper that
# never returns, on exactly the child a deadline had given up on. Now a refused tree kill falls
# back to killing the root alone before the wait. CHANGELOG [6.6.10]
#
# THE ROWS run an agnos probe under tests/fixtures/agnos_sctrace.cyr (PTRACE_SYSEMU: nothing
# executes, every syscall is logged and answered from a table) and read the ORDER of what
# `proc_kill_tree(2, …)` asks the kernel:
#   rgold — a pre-1.57.7 kernel: a #16 with the tree bit (a2 & 0x100) answers -1. The tree kill
#           (a2 = 0x109) must be followed by a plain kill of the root (a2 = 9) BEFORE any #4.
#   rg    — a current kernel: the tree kill answers 0, and it is the ONLY kill.
# The fake kernel's rgold #4 answers 265 once ANY #16 has been seen, so without the fix the
# probe still returns there; the sequence is the assertion, not the hang.
# The rg* modes are lane T's (6.6.10 bite 13) — this gate needs that fixture.
#
# MUTATION (6.6.10, run): drop the fallback (`sys_kill_tree(pid, 9);` alone) → the rgold row
# reads "16:265 4" instead of "16:265 16:9 4" and the gate fails; the rg row stays green.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL agnos_proc_kill_tree_refused: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL agnos_proc_kill_tree_refused: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT" || exit 1
ulimit -c 0
grep -q '"rgold"' tests/fixtures/agnos_sctrace.cyr || {
    echo "FAIL agnos_proc_kill_tree_refused: tests/fixtures/agnos_sctrace.cyr has no rgold mode (6.6.10 bite 13)"
    exit 1; }
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}

"$CC" < tests/fixtures/agnos_sctrace.cyr > "$T/sct" 2>"$T/sct.err" && chmod +x "$T/sct" || {
    echo "FAIL agnos_proc_kill_tree_refused: the fake-kernel tracer did not build"; head -3 "$T/sct.err"; exit 1; }

cat > "$T/p.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/vec.cyr"
include "lib/str.cyr"
include "lib/tagged.cyr"
include "lib/process.cyr"
var st[8];
syscall(999, 1, 0);
proc_kill_tree(2, &st);
syscall(999, 2, load32(&st));
sys_exit(0);
EOF
CYRIUS_TARGET_AGNOS=1 "$CC" < "$T/p.cyr" > "$T/p.bin" 2>"$T/p.err" || {
    echo "FAIL agnos_proc_kill_tree_refused: the agnos probe did not build"; grep -E '^error' "$T/p.err" | head -3; exit 1; }
chmod +x "$T/p.bin"

# The kills (as 16:<a2>) and waits (4) between the two report marks, in order.
between() {
    awk '$1 == "sc" && $2 == 999 { if ($3 == 2) exit; on = ($3 == 1); next }
         on && $1 == "sc" && $2 == 16 { printf "%s16:%d", s, $4; s = " " }
         on && $1 == "sc" && $2 == 4 && !w { printf "%s4", s; s = " "; w = 1 }
         END { print "" }' "$1"
}
mark2() { awk '$1 == "sc" && $2 == 999 && $3 == 2 { print $4; exit }' "$1"; }

echo "axis 1 — a refused tree kill (pre-1.57.7 kernel) still kills the root before the wait:"
"$T/sct" "$T/p.bin" rgold > "$T/old.log" 2>&1
check "rgold: tree kill (0x109 = 265), then a plain kill of the root (9), then the wait" \
    "16:265 16:9 4" "$(between "$T/old.log")"
check "  …and the root's status is reaped into stbuf (265: killed by SIGKILL)" "265" "$(mark2 "$T/old.log")"

echo "axis 2 — an accepted tree kill is the only kill:"
"$T/sct" "$T/p.bin" rg > "$T/new.log" 2>&1
check "rg: one tree kill (0x109 = 265), then the wait — no second kill" "16:265 4" "$(between "$T/new.log")"

if [ "$fails" -ne 0 ]; then echo "FAIL agnos_proc_kill_tree_refused: $fails check(s)"; exit 1; fi
echo "PASS agnos_proc_kill_tree_refused"
exit 0

#!/bin/sh
# Gate: `thread_join` parks only on a tid it positively observed LIVE (v6.5.8).
#
# ⚠ WHY THIS FILE EXISTS ALONGSIDE tests/tcyr/concurrency/thread_join_single_load.tcyr, AND WHY THE
# STRUCTURAL AXIS IS THE LOAD-BEARING ONE.
#
# The .tcyr proves the KERNEL semantics the fix depends on — FUTEX_WAIT with a live tid
# returns EAGAIN, FUTEX_WAIT with 0 parks — deterministically and without racing. That is
# worth having, but it drives the raw futex ABI directly, so it passes against the BROKEN
# thread_join too: reverting the fix leaves those assertions green. Mutation-verified, not
# assumed. A test that cannot tell fixed from broken is not a regression test.
#
# And the runtime backstop cannot close the gap either: the defect is a race lost roughly
# once in 150,000 joins, so a green stress loop is fully consistent with the bug still being
# present. Absence is not provable by hammering.
#
# What IS provable is the SHAPE: one load per iteration, feeding both the condition and the
# FUTEX_WAIT expected-value. Two independent loads are the bug, whatever the loop looks like
# otherwise. So this gate reads the function.
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

BODY=$(awk '/^fn thread_join\(/,/^}/' lib/thread.cyr)

echo "axis 1 — the FUTEX_WAIT expected-value is a variable, never a fresh load:"
# THE assertion. `syscall(SYS_FUTEX, t, FUTEX_WAIT, load64(t), ...)` is the defect verbatim:
# that second dereference is a value nobody observed live, and cycc does not CSE it away
# (objdump showed two dereferences ~50 bytes and a taken branch apart).
n_bad=$(printf '%s\n' "$BODY" | grep -c 'FUTEX_WAIT, load64(' || true)
check "no load64() inside the FUTEX_WAIT call" 0 "$n_bad"
n_var=$(printf '%s\n' "$BODY" | grep -c 'syscall(SYS_FUTEX, t, FUTEX_WAIT, tid,' || true)
check "expected-value is the observed tid" 1 "$n_var"

echo "axis 2 — the loop condition tests that same observed value, not another load:"
n_cond_bad=$(printf '%s\n' "$BODY" | grep -c 'while (load64(t) != 0)' || true)
check "condition does not re-load" 0 "$n_cond_bad"
n_cond=$(printf '%s\n' "$BODY" | grep -c 'while (tid != 0)' || true)
check "condition tests the observed tid" 1 "$n_cond"

echo "axis 3 — exactly one load of the tid word per iteration:"
# One before the loop (the initial observation) + one at the bottom (the re-observation).
# Three or more means someone re-introduced a read the loop does not gate on.
n_loads=$(printf '%s\n' "$BODY" | grep -c 'load64(t);' || true)
check "two loads total: initial + bottom-of-loop re-read" 2 "$n_loads"

echo "axis 4 — FUTEX_PRIVATE_FLAG stays OFF (separate, load-bearing invariant):"
# CLONE_CHILD_CLEARTID's kernel-side wake is SHARED. A private waiter sits on the private
# hash bucket and never sees it — a different permanent hang, fixed pre-v5.4.10. Asserted
# here because this function is now being edited for the tid race and the two are one line
# apart.
n_priv=$(printf '%s\n' "$BODY" | grep -c 'FUTEX_PRIVATE_FLAG' || true)
check "no FUTEX_PRIVATE_FLAG in thread_join" 0 "$n_priv"

echo "axis 5 — the sibling futex waiters keep the same discipline:"
# chan_send observes `count` once under the mutex; chan_recv and mutex_lock pass constants.
# None of them may grow a fresh load in the expected-value slot.
n_sib=$(grep -cE 'FUTEX_WAIT, load64\(' lib/thread.cyr lib/sync.cyr 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
check "no re-loading waiter anywhere in thread.cyr/sync.cyr" 0 "$n_sib"

echo "axis 6 — runtime: kernel semantics + join backstop:"
"$CC" < tests/tcyr/concurrency/thread_join_single_load.tcyr > "$D/t.bin" 2>/dev/null
chmod +x "$D/t.bin" 2>/dev/null
rc=0
timeout 120 "$D/t.bin" > "$D/t.out" 2>&1 || rc=$?
check "thread_join_single_load.tcyr exits 0" 0 "$rc"
check "no failed assertions" 1 "$(grep -c '0 failed' "$D/t.out" || true)"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: thread-join-single-load — one observed tid feeds both the condition and FUTEX_WAIT"
    exit 0
fi
echo "FAIL: thread-join-single-load — $fails assertion(s) failed"
exit 1

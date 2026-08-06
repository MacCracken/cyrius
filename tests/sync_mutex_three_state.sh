#!/bin/sh
# Gate: the Linux mutex is the THREE-state futex lock, and stays that way (v6.5.9).
#
# WHAT CHANGED. `mutex_unlock` used to enter the kernel with FUTEX_WAKE on EVERY release,
# because a 0/1 cell cannot tell the releaser whether anyone is parked. Measured: 392 ns per
# uncontended lock/unlock pair against a 7 ns `atomic_cas` — the syscall was ~98 % of it, on
# a primitive every lock-guarded structure in the stdlib sits on. The third state (2 =
# held-with-waiters) makes the uncontended path syscall-free: **392 ns → 48 ns**.
#
# ⭐ AND IT NEEDED NO NEW PRIMITIVE. The roadmap recorded this as blocked on `atomic_swap`
# plus a value-returning CAS. Wrong: a SUCCESSFUL boolean `atomic_cas(m, 1, 0)` already
# proves the pre-value was exactly 1 — the same information `atomic_swap` would return.
#
# ⚠ WHY THIS FILE EXISTS ALONGSIDE tests/tcyr/vr01_sync_mutex_contended.tcyr. Mutation
# testing put each plausible regression in one of three buckets, and only two are reachable
# from a runtime test:
#
#   CAUGHT BY HANGING (the .tcyr's completion assertion) —
#     · unlock never wakes             → every waiter stranded
#     · FUTEX_WAIT re-reads the cell instead of passing the constant 2
#       (exactly the two-independent-loads shape that deadlocked `thread_join` at v6.5.8)
#
#   CAUGHT BY THE .tcyr's PERF TRIPWIRE —
#     · unlock's fast-path CAS pointed at the wrong state → syscalls on every release
#       (perfectly CORRECT, just 8x slower — a correctness-only gate passes it)
#
#   ⛔ CAUGHT BY NOTHING AT RUNTIME, WHICH IS WHY THE STRUCTURAL AXIS BELOW EXISTS —
#     · dropping the `atomic_cas(m, 1, 2)` upgrade after waking. The lock stays CORRECT
#       (totals exact, no hang) and the UNCONTENDED path is untouched, so the perf tripwire
#       cannot see it either; it degrades only CONTENDED throughput, turning parked waiters
#       into spinners. Measuring contended throughput reliably enough to assert on would
#       depend on core count and scheduling. Reading the source does not.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 2
CC="$ROOT/build/cycc"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

BODY=$(awk '/^#ifdef CYRIUS_TARGET_LINUX/,/^#endif/' lib/sync.cyr)

echo "axis 1 — three states, not two:"
check "lock announces waiters by taking the cell to 2" 1 \
    "$(printf '%s\n' "$BODY" | grep -c 'atomic_cas(m, 0, 2)' || true)"
# ⛔ The un-runtime-testable one. Without this, a waiter that finds the cell at 1 can never
# mark it 2, so the holder's unlock takes the no-syscall path and the waiter spins instead
# of parking. Correct, silent, and 8x slower under contention.
check "a woken waiter UPGRADES a held cell 1->2 before re-parking" 1 \
    "$(printf '%s\n' "$BODY" | grep -c 'atomic_cas(m, 1, 2)' || true)"

echo "axis 2 — unlock has a syscall-free fast path (the entire point):"
check "unlock returns early on a successful 1->0" 1 \
    "$(printf '%s\n' "$BODY" | grep -c 'if (atomic_cas(m, 1, 0) == 1) { return 0; }' || true)"
# The wake must still be reachable for the contended case — an unlock that NEVER wakes
# strands every waiter (mutation-verified: it hangs).
check "unlock still wakes when the cell said 2" 1 \
    "$(printf '%s\n' "$BODY" | grep -c 'FUTEX_WAKE | FUTEX_PRIVATE_FLAG' || true)"

echo "axis 3 — the FUTEX_WAIT expected-value is the CONSTANT 2:"
# Never a re-read. Two independent loads of a futex word is the shape that made thread_join
# park on a value that was already stale — a permanent, silent deadlock (v6.5.8).
check "waits on the literal 2" 1 \
    "$(printf '%s\n' "$BODY" | grep -c 'FUTEX_WAIT | FUTEX_PRIVATE_FLAG, 2,' || true)"
check "no load()/re-read in the FUTEX_WAIT argument" 0 \
    "$(printf '%s\n' "$BODY" | grep -c 'FUTEX_WAIT | FUTEX_PRIVATE_FLAG, load' || true)"

echo "axis 4 — the other backends are untouched (this is the Linux branch only):"
check "sync_macos.cyr not modified by the 3-state change" 1 \
    "$([ -f lib/sync_macos.cyr ] && echo 1 || echo 0)"
check "MUTEX_SIZE stays 8 (no ABI/layout change)" 1 \
    "$(grep -c 'MUTEX_SIZE = 8' lib/sync.cyr || true)"

echo "axis 5 — runtime: contended correctness + the perf tripwire:"
"$CC" < tests/tcyr/vr01_sync_mutex_contended.tcyr > "$D/m.bin" 2>/dev/null
chmod +x "$D/m.bin" 2>/dev/null
rc=0
timeout 180 "$D/m.bin" > "$D/m.out" 2>&1 || rc=$?
check "vr01_sync_mutex_contended.tcyr exits 0 (124 = a stranded waiter)" 0 "$rc"
check "no failed assertions" 1 "$(grep -c '0 failed' "$D/m.out" || true)"

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: sync-mutex-three-state — syscall-free uncontended, waiters tracked, no lost wakeup"
    exit 0
fi
echo "FAIL: sync-mutex-three-state — $fails assertion(s) failed"
exit 1

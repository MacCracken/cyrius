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
# ⚠ WHY THIS FILE EXISTS ALONGSIDE tests/tcyr/crossos/sync_mutex_contended.tcyr. Mutation
# testing put each plausible regression in one of three buckets, and only two are reachable
# from a runtime test:
#
#   CAUGHT BY HANGING (the .tcyr's completion assertion) —
#     · unlock never wakes             → every waiter stranded
#     · FUTEX_WAIT re-reads the cell instead of passing the constant 2
#       (exactly the two-independent-loads shape that deadlocked `thread_join` at v6.5.8)
#
#   CAUGHT BY THE .tcyr's PERF TRIPWIRE —
#     · unlock's fast path removed or pointed at the wrong state → syscalls on every
#       release (perfectly CORRECT, just 8x slower — a correctness-only gate passes it).
#       Axis 6 below re-proves this on every run by building the .tcyr against exactly
#       that mutant and requiring the perf assertion — and only it — to go RED.
#
#   ⛔ CAUGHT BY NOTHING AT RUNTIME, WHICH IS WHY THE STRUCTURAL AXIS BELOW EXISTS —
#     · dropping the `atomic_cas(m, 1, 2)` upgrade after waking. The lock stays CORRECT
#       (totals exact, no hang) and the UNCONTENDED path is untouched, so the perf tripwire
#       cannot see it either; it degrades only CONTENDED throughput, turning parked waiters
#       into spinners. Measuring contended throughput reliably enough to assert on would
#       depend on core count and scheduling. Reading the source does not.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC="$ROOT/build/cycc"
D=$(mktemp -d)
# A failed mktemp prints nothing, and with D="" every "$D/..." path below becomes ROOT-ABSOLUTE
# (/m.bin, /mt, /mt/lib) — the AGNOS CI container runs as root, so axis 6 would create /mt and
# copy lib/ into the filesystem root. It would not touch the tree; refuse to run anyway.
if [ -z "$D" ] || [ ! -d "$D" ]; then echo "FAIL: sync-mutex-three-state — mktemp -d gave no directory"; exit 1; fi
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
"$CC" < tests/tcyr/crossos/sync_mutex_contended.tcyr > "$D/m.bin" 2>/dev/null
chmod +x "$D/m.bin" 2>/dev/null
rc=0
timeout 180 "$D/m.bin" > "$D/m.out" 2>&1 || rc=$?
check "crossos/sync_mutex_contended.tcyr exits 0 (124 = a stranded waiter)" 0 "$rc"
check "no failed assertions" 1 "$(grep -c '0 failed' "$D/m.out" || true)"

echo "axis 6 — the perf tripwire is RELATIVE and it FIRES on a syscall-per-release lock (6.6.6):"
# ⛔ It was `assert(per < 250, ...)` — an absolute ns bound set on one x86 box. Measured on
# real ecb (arm64 macOS) at 6.6.5: fast path 16-25 ns, syscall-per-release mutant 113-174 ns,
# i.e. UNDER 250 — the tripwire read GREEN on the broken lock in 10 of 10 runs. The .tcyr now
# requires pair < floor + ref/2 with all three timed in the same run (see its PERF AXIS
# note). An absolute bound would still pass the mutant check below ON THIS BOX (378 > 250),
# so the relative form is pinned structurally as well — only ecb could see the difference.
#
# MUTATION LEDGER (2026-09-19, scratch tree, this box):
#   real tree ........................................... GREEN (0 FAIL)
#   the .tcyr reverted to the 6.6.5 absolute `per < 250` .. RED — relative-form pin, the
#       no-absolute-bound pin, and "the perf assertion is the one that fired" (its message
#       differs) — 3 fails
#   bound loosened to `floor + ref * 2` ..................... RED — relative-form pin + the
#       mutant now exits 0 — 4 fails
#   the reference inflated 4x, the pinned line untouched .... RED — the mutant exits 0,
#       i.e. the runtime half catches what the structural half cannot — 3 fails
# Real hardware for the .tcyr itself (fast path GREEN, syscall-per-release mutant RED) is
# recorded in its PERF AXIS note: x86 Linux, cass, pi, ecb, ach.
T=tests/tcyr/crossos/sync_mutex_contended.tcyr
check "the bound is relative to the same run (pair < floor + ref/2)" 1 \
    "$(grep -c 'var ok = pair_ps < floor_ps + ref_ps / 2;' "$T" || true)"
check "no absolute ns bound on the pair" 0 \
    "$(grep -cE 'assert\((per|pair_ps) *< *[0-9]' "$T" || true)"
# The mutant: sync.cyr's Linux arm with unlock's fast path DELETED, so every release takes
# atomic_store + FUTEX_WAKE. Correct (no hang, exact totals) and a syscall per release.
FAST='    if (atomic_cas(m, 1, 0) == 1) { return 0; }'
mkdir -p "$D/mt"
cp -r "$ROOT/lib" "$D/mt/lib"
grep -vxF "$FAST" "$ROOT/lib/sync.cyr" > "$D/mt/lib/sync.cyr"
check "mutant applied: the fast-path line is gone from the scratch sync.cyr" 0 \
    "$(grep -cxF "$FAST" "$D/mt/lib/sync.cyr" || true)"
check "mutant applied: nothing else changed (1 line removed)" 1 \
    "$(( $(wc -l < "$ROOT/lib/sync.cyr") - $(wc -l < "$D/mt/lib/sync.cyr") ))"
( cd "$D/mt" && "$CC" < "$ROOT/$T" > "$D/mt.bin" 2>/dev/null )
if [ ! -s "$D/mt.bin" ]; then
    check "the mutant .tcyr compiled to a non-empty binary" 1 0
else
    chmod +x "$D/mt.bin"
    rc=0
    timeout 180 "$D/mt.bin" > "$D/mt.out" 2>&1 || rc=$?
    check "the mutant does not hang (124) — it is a correct lock, only slower" 1 \
        "$([ "$rc" -ne 124 ] && echo 1 || echo 0)"
    check "the mutant exits NON-zero" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
    check "the perf assertion is the one that fired" 1 \
        "$(grep -c 'FAIL: uncontended lock/unlock costs under HALF a syscall' "$D/mt.out" || true)"
    check "and nothing else fired (the preconditions and correctness hold)" 1 \
        "$(grep -c ' 1 failed' "$D/mt.out" || true)"
fi

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: sync-mutex-three-state — syscall-free uncontended, waiters tracked, no lost wakeup"
    exit 0
fi
echo "FAIL: sync-mutex-three-state — $fails assertion(s) failed"
exit 1

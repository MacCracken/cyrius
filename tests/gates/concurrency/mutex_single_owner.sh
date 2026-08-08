#!/bin/sh
# tests/gates/concurrency/mutex_single_owner.sh — v6.3.44 single-owner mutex gate.
#
# mutex_new/lock/unlock + MUTEX_SIZE live in exactly ONE module — lib/sync.cyr,
# the purpose-built "lock alone" backend-routing module. Before v6.3.44,
# lib/thread.cyr (Linux/macOS futex), lib/thread_win.cyr (SRWLOCK) and
# lib/thread_agnos.cyr (no-op) EACH carried their own copy, so any consumer
# linking both `thread` and `sync` (sync arrives transitively via
# alloc/atomic/patra) saw 3 `duplicate fn 'mutex_*'` warnings, and a silent
# link-order winner if the impls ever drifted (issue
# 2026-07-03-duplicate-mutex-fns-thread-vs-sync-stdlib). thread*.cyr now delegate
# to sync.cyr (include at the top of thread.cyr) and include-once dedup collapses
# the both-included case to one definition.
#
# Asserts:
#   (1) a unit including BOTH lib/thread.cyr and lib/sync.cyr emits ZERO
#       `duplicate fn 'mutex_*'` warnings (the reported bug);
#   (2) mutex is still functional — 4 threads x 1000 locked increments give a
#       consistent count (4000 & 0xFF = 160), proving the delegated Linux futex
#       lock still guards the critical section (no lost updates);
#   (3) thread.cyr ALONE (no explicit sync include) still resolves mutex_*
#       transitively via sync;
#   (4) source integrity — thread.cyr / thread_win.cyr / thread_agnos.cyr no
#       longer DEFINE `fn mutex_new`, and thread.cyr includes lib/sync.cyr.
set -u
cd "$(dirname "$0")/../../.." || exit 2
CYCC="${CYCC:-build/cycc}"
[ -x "$CYCC" ] || { printf 'mutex_single_owner: %s missing\n' "$CYCC" >&2; exit 2; }
TMP="${TMPDIR:-/tmp}/mtxowner.$$"
mkdir -p "$TMP" || exit 2
trap 'rm -rf "$TMP"' EXIT
rc=0

# (1) both included -> no duplicate mutex warnings
cat > "$TMP/both.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/atomic.cyr"
include "lib/alloc.cyr"
include "lib/mmap.cyr"
include "lib/sync.cyr"
include "lib/thread.cyr"
fn main(): i64 { var m = mutex_new(); mutex_lock(m); mutex_unlock(m); return 0; }
EOF
"$CYCC" < "$TMP/both.cyr" > "$TMP/both.bin" 2> "$TMP/both.err" || { printf 'mutex_single_owner: both-included compile failed\n' >&2; cat "$TMP/both.err" >&2; rc=1; }
if grep -q "duplicate fn 'mutex" "$TMP/both.err"; then
    printf 'mutex_single_owner: FAIL (1) duplicate-fn warnings still present:\n' >&2
    grep "duplicate fn 'mutex" "$TMP/both.err" >&2
    rc=1
fi

# (2) mutex still guards the critical section under contention
cat > "$TMP/ctr.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/atomic.cyr"
include "lib/alloc.cyr"
include "lib/mmap.cyr"
include "lib/thread.cyr"
var g_m = 0;
var g_ctr = 0;
fn worker(a): i64 {
    var i = 0;
    while (i < 1000) { mutex_lock(g_m); g_ctr = g_ctr + 1; mutex_unlock(g_m); i = i + 1; }
    return 0;
}
fn main(): i64 {
    g_m = mutex_new();
    var t0 = thread_create(&worker, 0);
    var t1 = thread_create(&worker, 0);
    var t2 = thread_create(&worker, 0);
    var t3 = thread_create(&worker, 0);
    thread_join(t0); thread_join(t1); thread_join(t2); thread_join(t3);
    return g_ctr;
}
EOF
if "$CYCC" < "$TMP/ctr.cyr" > "$TMP/ctr.bin" 2> "$TMP/ctr.err"; then
    chmod +x "$TMP/ctr.bin"
    "$TMP/ctr.bin"; got=$?
    if [ "$got" -ne 160 ]; then
        printf 'mutex_single_owner: FAIL (2) contended counter = %s, want 160 (4000 mod 256)\n' "$got" >&2
        rc=1
    fi
else
    printf 'mutex_single_owner: FAIL (2) contention program compile failed\n' >&2
    cat "$TMP/ctr.err" >&2; rc=1
fi

# (3) thread.cyr alone still resolves mutex_* (via transitive sync)
cat > "$TMP/alone.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/atomic.cyr"
include "lib/alloc.cyr"
include "lib/mmap.cyr"
include "lib/thread.cyr"
fn main(): i64 { var m = mutex_new(); mutex_lock(m); mutex_unlock(m); if (m == 0) { return 1; } return 42; }
EOF
if "$CYCC" < "$TMP/alone.cyr" > "$TMP/alone.bin" 2> "$TMP/alone.err"; then
    chmod +x "$TMP/alone.bin"; "$TMP/alone.bin"; got=$?
    [ "$got" -eq 42 ] || { printf 'mutex_single_owner: FAIL (3) thread-alone mutex = %s, want 42\n' "$got" >&2; rc=1; }
else
    printf 'mutex_single_owner: FAIL (3) thread-alone compile failed\n' >&2; cat "$TMP/alone.err" >&2; rc=1
fi

# (4) source integrity: thread*.cyr no longer DEFINE mutex_new; thread.cyr includes sync
for f in lib/thread.cyr lib/thread_win.cyr lib/thread_agnos.cyr; do
    if grep -qE '^fn mutex_new' "$f"; then
        printf 'mutex_single_owner: FAIL (4) %s still defines fn mutex_new (should delegate to sync)\n' "$f" >&2
        rc=1
    fi
done
grep -q 'include "lib/sync.cyr"' lib/thread.cyr || { printf 'mutex_single_owner: FAIL (4) lib/thread.cyr does not include lib/sync.cyr\n' >&2; rc=1; }

[ "$rc" -eq 0 ] && printf 'mutex_single_owner: OK (single owner, no dup warnings, lock correct)\n'
exit "$rc"

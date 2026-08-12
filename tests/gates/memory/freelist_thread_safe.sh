#!/bin/sh
# tests/gates/memory/freelist_thread_safe.sh — v6.5.19 freelist thread-safety gate.
#
# `lib/freelist.cyr` mutated `_fl_heads` / `_fl_arena_pos` / `_fl_arena_end` with plain
# loads and stores from any number of threads. Filed by majra 2026-08-10 (silent
# cross-thread memory corruption presenting as a bug in the CONSUMER's dedup logic).
# `tests/tcyr/crossos/freelist_thread_safe.tcyr` is the behavioural half; this gate
# covers the five things a runtime test on Linux structurally CANNOT see:
#
#  A. `_threads_active` must have exactly ONE declaration in the whole stdlib. Two
#     allocators now gate on it (alloc.cyr's bump lock and freelist.cyr's). A second
#     copy would be armed by thread_create and silently missed by whichever allocator
#     read the other one — both locks would look present and one would never engage.
#  B. Every thread backend must still ARM it. If thread_win.cyr's `_threads_active = 1`
#     were dropped, the freelist would run unlocked on Windows ONLY, and every test on
#     this box would stay green — the exact shape of the macOS rot.
#  C. Both public mutators must take the lock. A new early-return path added to
#     fl_alloc that skips the release is a deadlock; one that skips the acquire is the
#     original bug back.
#  D. ⭐ THE GATE PROVES ITS OWN SENSITIVITY EVERY RUN. Axis D builds the pinned race
#     probe twice — once against the real stdlib, once against a copy of freelist.cyr
#     with the lock calls stripped — and requires PASS then FAIL. A race gate that has
#     silently stopped being able to observe the race is worse than no gate, and that
#     is not hypothetical here: three releases running, a gate built only from the
#     filed repro turned out vacuous.
#  E. Every `_fl_lock_acquire()`/`_fl_lock_release()` call must carry the
#     `if (_threads_active != 0)` gate. The gate is hoisted to the call sites for a
#     measured perf reason, which makes it a PER-SITE INVARIANT: break it at one ACQUIRE
#     and a program with no threads at all deadlocks on its second fl_alloc. Axes A-D
#     are all blind to it — D's probe runs with `_threads_active == 1`, where a gated and
#     an ungated call do the same thing. (Run BEFORE D, since the defect is a hang.)
#
# ⚠ Do NOT assert on a crash. Consecutive anonymous mmaps land adjacent (measured 64
# KB apart), so an off-the-end block lands in a neighbouring MAPPED chunk: 0 SIGSEGVs
# in 80 attempts against the unfixed allocator. The corruption is silent by nature.
set -u
cd "$(dirname "$0")/../../.." || exit 2
ROOT=$(pwd)
TMP="${TMPDIR:-/tmp}/flts.$$"
mkdir -p "$TMP" || exit 2
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1"; exit 1; }

# ⛔ EVERY PROBE RUN IS TIME-BOUNDED. This gate executes freelist code built from a
# possibly-broken lib/, and the freelist's failure mode is a SPINLOCK — a defect here
# does not crash, it hangs forever, and an unbounded run wedges the whole of check.sh
# with no verdict. Measured while building axis E: a copy with one ungated acquire hung
# this gate indefinitely at axis D, and the run had to be killed by hand. `timeout` is
# present on the Linux hosts check.sh runs on; where it is not, fall back to running
# bare rather than skipping the probe (a slow verdict beats no verdict).
_HAS_TIMEOUT=0
command -v timeout >/dev/null 2>&1 && _HAS_TIMEOUT=1
run_bounded() {
    if [ "$_HAS_TIMEOUT" = "1" ]; then
        timeout 60 "$1" > /dev/null 2>&1
    else
        "$1" > /dev/null 2>&1
    fi
}

# ── A. exactly one owner for _threads_active ────────────────────────
ndecl=$(grep -c '^var _threads_active' lib/*.cyr 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')
[ "$ndecl" = "1" ] || fail "expected exactly 1 \`var _threads_active\` declaration in lib/, found $ndecl — two copies means one allocator's lock never engages"
grep -q '^var _threads_active' lib/atomic.cyr || fail "_threads_active must be declared in lib/atomic.cyr (the module alloc.cyr, freelist.cyr and thread.cyr all share)"

# ── B. every thread backend still arms it ───────────────────────────
for f in lib/thread.cyr lib/thread_win.cyr lib/thread_macos.cyr lib/thread_agnos.cyr; do
    [ -f "$f" ] || fail "$f missing — the arming-site inventory is stale"
    grep -q '_threads_active = 1' "$f" || fail "$f no longer arms _threads_active — that target's allocators run UNLOCKED and no test on this host can see it"
done

# ── C. both public mutators lock ────────────────────────────────────
# Per-function scan: awk from the `fn` line to the closing brace at column 0.
scan() {
    awk -v want="$2" 'index($0, "fn " want "(") == 1 {f=1} f {print} f && /^}/ {exit}' "$1"
}
for fnname in fl_alloc fl_free fl_init; do
    body=$(scan lib/freelist.cyr "$fnname")
    [ -n "$body" ] || fail "could not locate fn $fnname in lib/freelist.cyr"
    echo "$body" | grep -q '_fl_lock_acquire()' || fail "fn $fnname does not acquire _fl_lock"
    echo "$body" | grep -q '_fl_lock_release()' || fail "fn $fnname does not release _fl_lock"
done
# The arena helper must be documented as caller-locked — it is the R4/R5 pair and it
# has no lock of its own by design (fl_alloc holds it across the mmap).
scan lib/freelist.cyr _fl_arena_alloc | grep -q '_fl_lock_acquire()' \
    && fail "_fl_arena_alloc takes the lock itself — fl_alloc already holds it, so this self-deadlocks (the spinlock is not recursive)"
grep -q 'CALLER MUST HOLD' lib/freelist.cyr \
    || fail "_fl_arena_alloc's caller-locked contract is undocumented — the next editor will call it unlocked"

# ── E. every lock call site carries the `_threads_active` gate ───────
# (Lettered E because it was added last; RUN here, ahead of D, because it is a pure
# text check and the defect it catches is a DEADLOCK. Left after D it would be reached
# only if D's probe terminated, and the whole point is that it might not.)
# ⭐ THE GATE IS A PER-SITE INVARIANT, AND BREAKING IT ASYMMETRICALLY IS A DEADLOCK,
# not the slowdown lib/freelist.cyr used to claim. Measured 2026-08-11: drop the gate
# from fl_alloc's ACQUIRE only, leave both of its releases gated, and a program with NO
# THREADS IN IT hangs on its second fl_alloc — the lock is taken once and never given
# back, so the next CAS spins forever (exit 124 under an 8 s timeout).
#
# Axis C cannot see it: it greps that `_fl_lock_acquire()` and `_fl_lock_release()` both
# appear in each function, and an ungated call still contains the name. Axes A/B/D
# cannot either — D's probe is multi-threaded, where `_threads_active` is 1 and the
# gates are all taken anyway, so the mutation is INVISIBLE to the very axis built to
# prove sensitivity. The invariant is textual and exact, so check it textually: every
# call must be the gated one-liner, with no bare calls and no other wrapper.
sites=$(grep -n '_fl_lock_acquire()\|_fl_lock_release()' lib/freelist.cyr \
        | grep -v ':fn _fl_lock_' | grep -v ':[[:space:]]*#')
nsites=$(printf '%s\n' "$sites" | grep -c '.')
ngated=$(printf '%s\n' "$sites" | grep -c 'if (_threads_active != 0) { _fl_lock_')
# Anti-vacuous floor: fl_init 2, fl_alloc 3 (one acquire, two returns), fl_free 2.
[ "$nsites" -ge 7 ] || fail "only $nsites _fl_lock_acquire/release call sites in lib/freelist.cyr (expected >= 7: fl_init 2, fl_alloc 3, fl_free 2) — a locked path has disappeared and axis E would pass on a shrinking set"
if [ "$nsites" != "$ngated" ]; then
    printf '%s\n' "$sites" | grep -v 'if (_threads_active != 0) { _fl_lock_'
    fail "$((nsites - ngated)) of $nsites lock call sites in lib/freelist.cyr (listed above) are NOT wrapped in \`if (_threads_active != 0)\`. An ungated ACQUIRE beside gated releases takes the lock and never gives it back, so single-threaded fl_alloc spins forever; an ungated RELEASE drops a lock it never took, so mutual exclusion is silently gone once threads exist. Gate every site or none."
fi

# Anti-vacuous for E: the same check must REJECT a copy with one acquire ungated. Note
# this is a STATIC proof on purpose — proving it dynamically means waiting out a
# deliberate deadlock on every check.sh run, and the failure mode is a hang, which is
# the one result a test runner grades worst.
mkdir -p "$TMP/gate" || exit 2
awk '{
    if ($0 == "    if (_threads_active != 0) { _fl_lock_acquire(); }" && done != 1) {
        print "    _fl_lock_acquire();"; done = 1
    } else { print }
}' lib/freelist.cyr > "$TMP/gate/freelist.cyr"
if cmp -s lib/freelist.cyr "$TMP/gate/freelist.cyr"; then
    fail "axis E's own mutation is a no-op — the gated-call spelling in lib/freelist.cyr changed, so the check above matches nothing and passes vacuously"
fi
msites=$(grep -n '_fl_lock_acquire()\|_fl_lock_release()' "$TMP/gate/freelist.cyr" \
         | grep -v ':fn _fl_lock_' | grep -v ':[[:space:]]*#')
mn=$(printf '%s\n' "$msites" | grep -c '.')
mg=$(printf '%s\n' "$msites" | grep -c 'if (_threads_active != 0) { _fl_lock_')
[ "$mn" != "$mg" ] || fail "axis E scored a lock-gate-stripped copy as fully gated — the check cannot see the deadlock it exists to catch (vacuous)"

# ── D. pinned race probe: PASS on the real stdlib, FAIL on a stripped copy ──
cat > "$TMP/probe.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/mmap.cyr"
include "lib/alloc.cyr"
include "lib/atomic.cyr"
include "lib/thread.cyr"
include "lib/freelist.cyr"

var _bar = 0;
var _p[64];
var _NT = 4;

fn _wpop(arg): i64 {
    while (atomic_load(&_bar) == 0) { }
    store64(&_p + arg * 8, fl_alloc(64));
    return 0;
}

fn _warena(arg): i64 {
    while (atomic_load(&_bar) == 0) { }
    store64(&_p + arg * 8, fl_alloc(16));
    return 0;
}

fn _go(fp): i64 {
    _bar = 0;
    var t0 = thread_create(fp, 0);
    var t1 = thread_create(fp, 1);
    var t2 = thread_create(fp, 2);
    var t3 = thread_create(fp, 3);
    atomic_store(&_bar, 1);
    thread_join(t0);
    thread_join(t1);
    thread_join(t2);
    thread_join(t3);
    return 0;
}

fn _count_of(want): i64 {
    var n = 0;
    var i = 0;
    while (i < _NT) {
        if (load64(&_p + i * 8) == want) { n = n + 1; }
        i = i + 1;
    }
    return n;
}

fn main(): i64 {
    fl_init();
    var bad = 0;
    var r = 0;
    # R2: one block on a FRESH untouched page — the pop's `load64(head)` faults
    # between its load and its store, widening a 2-instruction window to microseconds.
    while (r < 128) {
        var pg = _fl_mmap(4096);
        store64(&_fl_heads + 2 * 8, pg);
        _go(&_wpop);
        if (_count_of(pg + 16) > 1) { bad = bad + 1; }
        r = r + 1;
    }
    # R4/R5: every head emptied so no pop can occur, refill branch re-armed.
    r = 0;
    while (r < 128) {
        var h = 0;
        while (h < 9) {
            store64(&_fl_heads + h * 8, 0);
            h = h + 1;
        }
        _fl_arena_pos = _fl_arena_end;
        _go(&_warena);
        var base = _fl_arena;
        var i = 0;
        while (i < _NT) {
            var q = load64(&_p + i * 8);
            if (q < base) { bad = bad + 1; }
            if (q >= base + FL_ARENA_SIZE) { bad = bad + 1; }
            i = i + 1;
        }
        r = r + 1;
    }
    if (bad != 0) { return 1; }
    return 0;
}
var rc = main();
syscall(60, rc);
EOF

"$ROOT/build/cycc" < "$TMP/probe.cyr" > "$TMP/good" 2> "$TMP/good.err" || fail "probe build against the real stdlib"
chmod +x "$TMP/good"
run_bounded "$TMP/good"
gr=$?
[ "$gr" != "124" ] || fail "the pinned race probe HUNG (60 s) against the SHIPPED freelist — a lock is taken and not released; see axis E"
[ "$gr" = "0" ] || fail "pinned race probe found corruption against the SHIPPED freelist (exit=$gr) — the lock is not holding"

# Anti-vacuous: same probe, same rounds, lock calls stripped out of a COPY of the
# stdlib. Copies rather than symlinks on purpose — a lib/ symlink is the downstream
# corruption antipattern CLAUDE.md forbids, and this tree is the one it corrupts.
mkdir -p "$TMP/mut/lib" || exit 2
cp lib/*.cyr "$TMP/mut/lib/" || exit 2
sed -e 's/^\( *\)if (_threads_active != 0) { _fl_lock_acquire(); }/\1# stripped/' \
    -e 's/^\( *\)if (_threads_active != 0) { _fl_lock_release(); }/\1# stripped/' \
    lib/freelist.cyr > "$TMP/mut/lib/freelist.cyr" || exit 2
nstrip=$(grep -c '# stripped' "$TMP/mut/lib/freelist.cyr")
[ "$nstrip" -ge 6 ] || fail "the mutant strip matched only $nstrip lock call sites (expected >= 6) — the sed no longer matches the source, so axis D would pass vacuously"
cp "$TMP/probe.cyr" "$TMP/mut/probe.cyr"
( cd "$TMP/mut" && "$ROOT/build/cycc" < probe.cyr > mut.bin 2> mut.err ) || fail "probe build against the stripped stdlib"
chmod +x "$TMP/mut/mut.bin"
run_bounded "$TMP/mut/mut.bin"
mr=$?
[ "$mr" != "0" ] || fail "the pinned probe PASSED against a freelist with the lock stripped out — the gate cannot see the race it exists to catch (vacuous)"

echo "PASS: freelist thread-safety (single _threads_active owner, 4 backends arm it, fl_alloc/fl_free/fl_init locked, all $nsites lock sites gated, pinned probe green on real stdlib and RED on a lock-stripped copy)"
exit 0

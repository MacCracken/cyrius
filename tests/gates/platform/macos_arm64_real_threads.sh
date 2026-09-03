#!/bin/sh
# macos_arm64_real_threads.sh — v6.5.44 (band J phase 2)
#
# Pins the arm64-macOS thread primitive: `syscall(1700, &tid, attr, &start, arg)` lowered to
# libSystem `pthread_create` through __got[5].
#
# ⛔ WHY NOT bsdthread_create, WHICH IS WHAT THE ROADMAP PINNED FOR THIS SLOT. Measured on real
# ecb, from a real cyrius-compiled binary: `bsdthread_register` returns EINVAL (exit 22).
# Registration is ONE-SHOT PER PROCESS, and cyrius's arm64 Mach-O output is a dyld/LC_MAIN PIE
# that links /usr/lib/libSystem.B.dylib (src/backend/macho/emit.cyr), so libpthread's
# initializer spends it before any cyrius code runs. Going raw anyway would mean hand-building a
# pthread_t against libpthread INTERNALS — sig@0x00 (guarded by a per-process ptr_munge cookie),
# fun@0x90, arg@0x98, tsd@0xE0, a PAC modifier — none of which is stable ABI. The v6.5.43
# bsdthread routes are NOT wrong and are NOT removed: they are what the x86-macOS backend, a
# static no-libSystem binary where registration DOES work, will use.
#
# ⚠ THE SLOT NUMBER IS NOT ARBITRARY and axis 3 is why this gate exists at all: __got[5] must
# actually be bound to _pthread_create. If someone reorders the GOT symbol list, this emitter
# silently calls whatever now sits in slot 5 — _fopen, say — with a thread's arguments. Nothing
# else in the tree couples those two facts.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
PE="$ROOT/src/frontend/parse_expr.cyr"
AE="$ROOT/src/backend/aarch64/emit.cyr"
ME="$ROOT/src/backend/macho/emit.cyr"
fail() { echo "FAIL macos_arm64_real_threads: $1" >&2; exit 1; }

# ── axis 1: the reroute exists, is arm64-Mach-O-guarded, and matches the right arity ──
grep -q 'sc_num == 1700' "$PE" || fail "the 1700 (pthread_create) reroute is missing from parse_expr"
CTX=$(grep -B24 'sc_num == 1700' "$PE" | grep -c '_TARGET_MACHO == 2' || true)
[ "$CTX" -ge 1 ] || fail "the 1700 reroute is not inside a _TARGET_MACHO == 2 (arm64 Mach-O) block — on any other target it would emit a GOT call into a binary with no GOT"
grep -A4 'sc_num == 1700' "$PE" | grep -q 'argc == 5' \
    || fail "the 1700 reroute does not require argc == 5 — pthread_create takes 4 args plus the number, and a wrong arity would mis-pop the stack"

# ── axis 2: the emitter calls through the GOT, not a syscall ──────────────────────────
grep -q 'fn EMACHO_PTHREAD_CREATE_ARM' "$AE" || fail "EMACHO_PTHREAD_CREATE_ARM missing from the aarch64 backend"
SLOT=$(sed -n '/fn EMACHO_PTHREAD_CREATE_ARM/,/^}/p' "$AE" | grep -oE '_EMACHO_BLR_GOT\(S, [0-9]+\)' | grep -oE '[0-9]+')
[ -n "$SLOT" ] || fail "EMACHO_PTHREAD_CREATE_ARM does not call _EMACHO_BLR_GOT — a raw svc here would be bsdthread_create, which EINVALs in a libSystem process"

# ── axis 3: that GOT slot really is _pthread_create ───────────────────────────────────
# The bind order in EMITMACHO_ARM64 is the source of truth; count the binds before this one.
IDX=$(grep -n '_macho_wbindsym(O, o, "' "$ME" | grep -n '_pthread_create' | cut -d: -f1)
[ -n "$IDX" ] || fail "no _pthread_create bind found in the Mach-O writer — the symbol was renamed or removed"
ACTUAL=$((IDX - 1))
[ "$SLOT" = "$ACTUAL" ] \
    || fail "EMACHO_PTHREAD_CREATE_ARM calls __got[$SLOT] but _pthread_create is bound at __got[$ACTUAL] — the emitter would call the wrong libSystem function with a thread's arguments"

# ── axis 4: return-0 stubs in EVERY other backend (the v6.4.26 trap) ──────────────────
# parse_expr references EMACHO_PTHREAD_CREATE_ARM in ALL forks; a missing stub links only on
# the fork nobody builds locally, and historically only cass's cycc_cx caught the miss.
for f in src/backend/x86/emit.cyr src/backend/cx/emit.cyr; do
    grep -q 'fn EMACHO_PTHREAD_CREATE_ARM' "$ROOT/$f" \
        || fail "$f has no EMACHO_PTHREAD_CREATE_ARM stub — the non-aarch64 forks will not link"
done

# ── axis 5: 1700 is registered as routed, or the v6.5.43 diagnostic false-positives ───
grep -q 'n == 1700' "$AE" || fail "_macho_arm_routes does not claim 1700 — every thread_create would warn 'syscall not routed'"

# ── axis 6: THREADS_CONCURRENT is HONEST on every backend ─────────────────────────────
# The capability the crossos discriminator guards on. A backend that runs the body INLINE
# (`fncall1` directly inside thread_create) must declare 0; declaring 1 there would make
# thread_runs_concurrently.tcyr assert against a serial backend and fail the release gate.
for f in lib/thread_win.cyr lib/thread_agnos.cyr; do
    grep -qE '^var THREADS_CONCURRENT = 0;' "$ROOT/$f" \
        || fail "$f is a serial peer (bodies run inline) but does not declare THREADS_CONCURRENT = 0"
done
grep -qE '^var THREADS_CONCURRENT = 1;' "$ROOT/lib/thread.cyr" \
    || fail "lib/thread.cyr uses real clone(2) threads but does not declare THREADS_CONCURRENT = 1"
grep -qE '^var THREADS_CONCURRENT = 1;' "$ROOT/lib/thread_macos.cyr" \
    || fail "lib/thread_macos.cyr declares no concurrent arm64 arm"
grep -qE '^var THREADS_CONCURRENT = 0;' "$ROOT/lib/thread_macos.cyr" \
    || fail "lib/thread_macos.cyr declares no serial x86 arm — x86-macOS is a static no-libSystem binary and CANNOT use pthread_create"

echo "PASS macos_arm64_real_threads (1700 -> __got[$SLOT] = _pthread_create, arm64-Mach-O-guarded, stubbed in every fork, THREADS_CONCURRENT honest on all four backends)"

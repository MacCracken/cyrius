#!/bin/sh
# macos_arm64_real_threads.sh — v6.5.44 (band J phase 2)
#
# Pins the arm64-macOS thread primitive: `syscall(1700, &tid, attr, &start, arg)` lowered to
# libSystem `pthread_create` through __got[5].
#
# ⛔ WHY NOT bsdthread_create, WHICH IS WHAT THE ROADMAP PINNED FOR THIS SLOT. Measured on real
# ecb, from a real cyrius-compiled binary: `bsdthread_register` returns EINVAL (exit 22).
# Registration is ONE-SHOT PER PROCESS, and cyrius's arm64 Mach-O output is a dyld/LC_MAIN PIE
# that links /usr/lib/libSystem.B.dylib (src/backend/macho/emit_arm64.cyr), so libpthread's
# initializer spends it before any cyrius code runs. Going raw anyway would mean hand-building a
# pthread_t against libpthread INTERNALS — sig@0x00 (guarded by a per-process ptr_munge cookie),
# fun@0x90, arg@0x98, tsd@0xE0, a PAC modifier — none of which is stable ABI. The v6.5.43
# bsdthread routes are NOT wrong and are NOT removed: they are what the x86-macOS backend, a
# static no-libSystem binary where registration DOES work, uses (6.6.19; axis 6).
#
# ⚠ THE SLOT NUMBER IS NOT ARBITRARY and axis 3 is why this gate exists at all: __got[5] must
# actually be bound to _pthread_create. If someone reorders the GOT symbol list, this emitter
# silently calls whatever now sits in slot 5 — _fopen, say — with a thread's arguments. Nothing
# else in the tree couples those two facts.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
PE="$ROOT/src/frontend/parse_expr.cyr"
AE="$ROOT/src/backend/aarch64/emit.cyr"
ME="$ROOT/src/backend/macho/emit_arm64.cyr"
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
# Windows is NOT a serial peer: thread_create is CreateThread (v6.0.61). This axis listed it
# among the serial peers from v6.5.44 to 6.6.15 and so ENFORCED the stale 0 (CHANGELOG [6.6.16]).
for f in lib/thread_agnos.cyr; do
    grep -qE '^var THREADS_CONCURRENT = 0;' "$ROOT/$f" \
        || fail "$f is a serial peer (bodies run inline) but does not declare THREADS_CONCURRENT = 0"
done
# Assert the MECHANISM, not only the value: each value below is justified by what that
# backend's thread_create body actually does, so read the body (fn line to its closing `}`).
_tc_body() { awk '/^fn thread_create\(/{p=1} p{print} p&&/^}/{exit}' "$ROOT/$1"; }
_tc_body lib/thread_agnos.cyr | grep -q 'fncall1(fp, arg)' \
    || fail "lib/thread_agnos.cyr's thread_create no longer runs the body inline (fncall1) — re-derive its THREADS_CONCURRENT from its mechanism"
_tc_body lib/thread_win.cyr | grep -q 'syscall(61447, a)' \
    || fail "lib/thread_win.cyr's thread_create no longer calls CreateThread (reroute 0xF007 = 61447), so THREADS_CONCURRENT = 1 is no longer justified"
if _tc_body lib/thread_win.cyr | grep -q 'fncall1('; then
    fail "lib/thread_win.cyr's thread_create runs a body inline (fncall1) — that is a serial backend, and THREADS_CONCURRENT = 1 would be a lie"
fi
grep -qE '^var THREADS_CONCURRENT = 1;' "$ROOT/lib/thread_win.cyr" \
    || fail "lib/thread_win.cyr's thread_create is CreateThread (real threads) but it does not declare THREADS_CONCURRENT = 1"
grep -qE '^var THREADS_CONCURRENT = 1;' "$ROOT/lib/thread.cyr" \
    || fail "lib/thread.cyr uses real clone(2) threads but does not declare THREADS_CONCURRENT = 1"
# macOS (6.6.19): BOTH Mach-O arches start real threads, so thread_macos.cyr declares each
# capability ONCE, unconditionally, as 1 — and each arm's MECHANISM is read to justify it.
# ⚠ `_tc_body` above reads the FIRST `fn thread_create(` in a file, which in thread_macos.cyr is
# the arm64 arm; the x86 arm is read out of its own `#ifndef CYRIUS_ARCH_AARCH64` block.
TM="$ROOT/lib/thread_macos.cyr"
_tm_arm() { awk -v g="$1" '$0 == g {a = 1; next} a && /^#endif$/ {exit} a' "$TM"; }
_tm_fn() { awk -v n="fn $1(" 'index($0, n) == 1 {p = 1} p {print} p && /^}/ {exit}'; }
X86=$(_tm_arm '#ifndef CYRIUS_ARCH_AARCH64')
A64=$(_tm_arm '#ifdef CYRIUS_ARCH_AARCH64')
[ -n "$X86" ] && [ -n "$A64" ] || fail "could not read thread_macos.cyr's two arch arms — the gate is blind, not the code clean"
NTC=$(grep -cE '^var THREADS_CONCURRENT = ' "$TM" || true)
NCB=$(grep -cE '^var CHAN_BLOCKING = ' "$TM" || true)
[ "$NTC" = 1 ] && [ "$NCB" = 1 ] \
    || fail "lib/thread_macos.cyr declares THREADS_CONCURRENT $NTC times and CHAN_BLOCKING $NCB times — both arches are real, so each is declared once, unconditionally"
grep -qE '^var THREADS_CONCURRENT = 1;' "$TM" && grep -qE '^var CHAN_BLOCKING = 1;' "$TM" \
    || fail "lib/thread_macos.cyr does not declare THREADS_CONCURRENT = 1 and CHAN_BLOCKING = 1"
printf '%s\n' "$A64" | _tm_fn thread_create | grep -q 'syscall(1700, ' \
    || fail "the arm64 arm's thread_create no longer calls pthread_create (1700), so THREADS_CONCURRENT = 1 is not justified there"
XTC=$(printf '%s\n' "$X86" | _tm_fn thread_create)
printf '%s' "$XTC" | grep -q 'sys_bsdthread_create(' \
    || fail "the x86 arm's thread_create does not call sys_bsdthread_create — x86 macOS has no other way to start a thread (no libSystem, no __got)"
if printf '%s' "$XTC" | grep -q 'fncall1('; then
    fail "the x86 arm's thread_create runs a body inline (fncall1) — that is the pre-6.6.19 serial backend, and THREADS_CONCURRENT = 1 would be a lie"
fi
# The trampoline never returns (there is no return address above it): it ends the thread with
# bsdthread_terminate, which also frees the thread's own stack — join does not.
LAST=$(printf '%s\n' "$X86" | _tm_fn _thr_start | grep -oE 'sys_[a-z_]+\(' | tail -1)
[ "$LAST" = "sys_bsdthread_terminate(" ] \
    || fail "the x86 trampoline _thr_start does not end in sys_bsdthread_terminate (last call: '$LAST') — it would return off the top of a stack with no return address"
# bsdthread_register succeeds with POSITIVE feature bits (ach: 0x400001DF) and answers -EINVAL
# once registered, inherited across fork: `r != 0` would refuse every thread.
REG=$(printf '%s\n' "$X86" | _tm_fn _thr_register)
printf '%s' "$REG" | grep -q 'if (r < 0)' && printf '%s' "$REG" | grep -q '0 - 22' \
    || fail "_thr_register must accept r >= 0 (feature bits) and -22 (already registered, inherited across fork)"
# -22 means "ours" only while nothing else registers first. The syscall peers DEFINE the wrapper.
OTHER=$(grep -l 'sys_bsdthread_register(' "$ROOT"/lib/*.cyr | grep -v '/lib/thread_macos\.cyr$' \
    | while read -r f; do grep 'sys_bsdthread_register(' "$f" | grep -qv '^fn sys_bsdthread_register(' && echo "$f"; done || true)
[ -z "$OTHER" ] || fail "a lib/ file other than thread_macos.cyr calls sys_bsdthread_register — _thr_register would read its registration as its own: $OTHER"

# ── axis 7: pthread_create's int result is sign-extended (sxtw x0, w0) ───────────────────
# AAPCS64 leaves x0[63:32] unspecified for an int return and thread_macos.cyr's `rc != 0` reads
# all 64 bits, so a success with dirty upper bits reads as failure while the thread runs. ecb
# measures clean upper bits today, so this is conformance: hardware cannot catch a regression,
# which is why (b) checks the EMITTED words. (a) source order, the macos_arm64_libsystem_fork
# axis 7 shape; (b) a cross-built probe with exactly two 1700 sites and no 1701 must carry two
# `blr x16` (0xD63F0200) words immediately followed by `sxtw x0, w0` (0x93407C00). Measured at
# 6.6.18: old 0, patched 2. CHANGELOG [6.6.18]
PB=$(awk -v n="fn EMACHO_PTHREAD_CREATE_ARM(" 'index($0, n) == 1 {s = 1} s {print} s && /^}/ {exit}' "$AE")
LBLR=$(printf '%s\n' "$PB" | awk '/_EMACHO_BLR_GOT\(S, 5\)/ {print NR; exit}')
LSX=$(printf '%s\n' "$PB" | awk '/EW\(S, 0x93407C00\)/ {print NR; exit}')
LRET=$(printf '%s\n' "$PB" | awk '/return 0;/ {r = NR} END {print r}')
[ -n "$LSX" ] || fail "EMACHO_PTHREAD_CREATE_ARM has no sxtw x0, w0 (0x93407C00) — pthread_create returns an int and x0's upper half is unspecified"
[ -n "$LBLR" ] && [ -n "$LRET" ] && [ "$LBLR" -lt "$LSX" ] && [ "$LSX" -lt "$LRET" ] \
    || fail "the sxtw must follow _EMACHO_BLR_GOT(S, 5) and precede the return"
CC=${CYCC:-"$ROOT/build/cycc"}
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL macos_arm64_real_threads: mktemp -d"; exit 1; }
trap 'rm -rf "$T"' EXIT
rc=0; (cd "$ROOT" && "$CC" < src/main_aarch64.cyr > "$T/cca" 2> "$T/cca.err") || rc=$?
[ "$rc" = 0 ] && [ -s "$T/cca" ] || fail "cross-building cycc_aarch64 from src failed (rc $rc): $(head -3 "$T/cca.err")"
chmod +x "$T/cca"
cat > "$T/p.cyr" <<'PROBE'
fn _p_body(a): i64 { return a; }
var _p_tid = 0;
var _p_r1 = syscall(1700, &_p_tid, 0, &_p_body, 0);
var _p_r2 = syscall(1700, &_p_tid, 0, &_p_body, 1);
PROBE
rc=0; CYRIUS_MACHO_ARM=1 "$T/cca" < "$T/p.cyr" > "$T/p.bin" 2> "$T/p.err" || rc=$?
[ "$rc" = 0 ] && [ -s "$T/p.bin" ] || fail "the arm64 Mach-O probe did not compile (rc $rc): $(head -3 "$T/p.err")"
od -An -v -tx4 "$T/p.bin" | tr -s ' ' '\n' > "$T/w"
NBLR=$(awk '$0 == "d63f0200" {n++} END {print n + 0}' "$T/w")
NPAIR=$(awk 'p == "d63f0200" && $0 == "93407c00" {n++} {p = $0} END {print n + 0}' "$T/w")
[ "$NBLR" -ge 2 ] || fail "the probe holds $NBLR blr x16 words — expected at least the two pthread_create calls (the reader is blind)"
[ "$NPAIR" = 2 ] || fail "$NPAIR of the probe's 2 pthread_create calls are followed by sxtw x0, w0 — the int result's upper half reaches \`rc != 0\` unextended"

echo "PASS macos_arm64_real_threads (1700 -> __got[$SLOT] = _pthread_create, arm64-Mach-O-guarded, stubbed in every fork, THREADS_CONCURRENT honest on every backend: 1 on Linux, both macOS arches (pthread_create / bsdthread_create) and Windows, 0 on agnos; the int result sign-extended at $NPAIR/2 emitted sites)"
